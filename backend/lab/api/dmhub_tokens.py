"""Map bindings and transactional DMHub action resolution."""

import re

from django.shortcuts import get_object_or_404
from drf_spectacular.types import OpenApiTypes
from drf_spectacular.utils import extend_schema
from rest_framework.exceptions import PermissionDenied, ValidationError
from rest_framework.response import Response

from lab.models import CharacterAbility, DamageApplication, SceneTarget
from lab.services.dice import d20
from lab.services.map_actions import map_targeting
from lab.services.sheets import active_session, computed, controlled_character, use_ability

from .common import is_dm
from .dmhub_edit import PersonalSheetAPI
from .dmhub_sheets import access_for, bridge_payload, response_for
from .scene import apply_damage, effect_kind, integer, target_sheet
from .sheets import EventSerializer


def identifier(value, label):
    if not isinstance(value, str) or not re.fullmatch(r'[A-Za-z0-9_.:-]{1,128}', value):
        raise ValidationError(f'Некорректный идентификатор: {label}')
    return value


def rows_for(session):
    return SceneTarget.objects.filter(
        session=session, active=True,
    ).select_related('source__sheet', 'instance__sheet')


def token_row(target, user, master, game):
    data = {
        'id': target.pk, 'name': target.name, 'targetable': target.targetable,
        'token': target.dmhub_token if target.dmhub_game == game else '',
    }
    char = target.sheet_character
    if target.uses_sheet and (master or char.kind == 'player' and char.owner_id == user.pk):
        sheet = target_sheet(target)
        data.update(sheet=char.pk, hp_current=sheet.hp_current, hp_max=sheet.hp_max,
                    hp_temp=sheet.hp_temp, armor_class=sheet.armor_class)
    return data


def link_target(session, user, master, game, data):
    if not master:
        raise PermissionDenied('Токены сцены привязывает мастер')
    if set(data) - {'command', 'session', 'game', 'token', 'target'}:
        raise ValidationError('Неизвестные поля привязки')
    token = identifier(data.get('token'), 'токен DMHub')
    targets = rows_for(session)
    if data.get('target') == 0 and type(data['target']) is int:
        targets.filter(dmhub_game=game, dmhub_token=token).update(dmhub_game='', dmhub_token='')
        return {'unlinked': True}
    target = get_object_or_404(targets, pk=integer(data.get('target'), 'Цель', 1, 2**63-1))
    if not target.uses_sheet:
        raise ValidationError('У цели должен быть лист персонажа')
    targets.filter(dmhub_game=game, dmhub_token=token).exclude(pk=target.pk).update(
        dmhub_game='', dmhub_token='',
    )
    target.dmhub_game, target.dmhub_token = game, token
    target.save(update_fields=['dmhub_game', 'dmhub_token', 'updated_at'])
    return {'target': token_row(target, user, master, game)}


def cast_spell(campaign, user, session, master, game, data):
    if set(data) - {'command', 'session', 'game', 'token', 'target', 'caster', 'spell', 'slot_level'}:
        raise ValidationError('Исход и величину урона рассчитывает SessionLab')
    token = identifier(data.get('token'), 'токен цели')
    targets = rows_for(session)
    if not master:
        targets = targets.filter(visible=True, targetable=True)
    target = get_object_or_404(
        targets, pk=integer(data.get('target'), 'Цель', 1, 2**63-1),
        dmhub_game=game, dmhub_token=token,
    )
    if not target.uses_sheet:
        raise ValidationError('У цели должен быть лист персонажа')
    caster = controlled_character(campaign, user, data.get('caster'))
    spell = get_object_or_404(
        CharacterAbility, pk=integer(data.get('spell'), 'Заклинание', 1, 2**63-1),
        character=caster, kind='spell', active=True,
    )
    if map_targeting(spell)['shape'] != 'single':
        raise ValidationError('Для этого заклинания выберите область на карте в обновлённом моде.')
    return resolve_action(campaign, user, spell, data.get('slot_level'), [target], master, game, legacy=True)


def act_on_map(campaign, user, session, master, game, data):
    if set(data) - {
        'command', 'session', 'game', 'caster', 'action', 'action_version',
        'slot_level', 'distance_ft', 'targets',
    }:
        raise ValidationError('Исход и величину урона рассчитывает SessionLab')
    caster = controlled_character(campaign, user, data.get('caster'))
    action = get_object_or_404(
        CharacterAbility.objects.select_related('catalog_entry'),
        pk=integer(data.get('action'), 'Действие', 1, 2**63-1),
        character=caster, active=True, kind__in=('attack', 'spell'),
    )
    if data.get('action_version') != action.version:
        raise ValidationError('Действие изменилось. Откройте его заново.')
    rules = map_targeting(action)
    area = rules['shape'] != 'single'
    if area and action.resolution == 'attack':
        raise ValidationError('Для области выберите спасбросок или автоматическое применение')
    distance = data.get('distance_ft')
    if rules['range_ft'] is not None:
        integer(distance, 'Расстояние в футах', 0, 100000)
        if distance > rules['range_ft']:
            raise ValidationError('Цель за пределами дальности')
    chosen = data.get('targets')
    if isinstance(chosen, dict) and len(chosen) <= 50:
        # Some Lua encoders use a numbered object for a sequence, including {} for an empty one.
        indexes = [str(i) for i in range(1, len(chosen) + 1)]
        if set(chosen) == set(indexes):
            chosen = [chosen[i] for i in indexes]
    if not isinstance(chosen, list) or not (0 if area else 1) <= len(chosen) <= (50 if area else 1):
        raise ValidationError('Некорректное количество целей')
    target_tokens = {}
    for row in chosen:
        if not isinstance(row, dict) or set(row) != {'id', 'token'}:
            raise ValidationError('Некорректная цель')
        pk = integer(row['id'], 'Цель', 1, 2**63-1)
        if pk in target_tokens:
            raise ValidationError('Цели не должны повторяться')
        target_tokens[pk] = identifier(row['token'], 'токен цели')
    targets = rows_for(session).filter(pk__in=target_tokens, dmhub_game=game)
    if not master:
        targets = targets.filter(visible=True, targetable=True)
    targets = list(targets.order_by('pk'))
    if len(targets) != len(target_tokens) or any(
        target.dmhub_token != target_tokens[target.pk] or not target.uses_sheet
        for target in targets
    ):
        raise ValidationError('Одна из целей больше недоступна. Выберите область заново.')
    return resolve_action(campaign, user, action, data.get('slot_level'), targets, master, game, area=area)


def resolve_action(campaign, user, ability, level, targets, master, game, *, legacy=False, area=False):
    single = targets[0] if len(targets) == 1 and not area else None
    options = {
        'slot_level': integer(level, 'Уровень ячейки', 0, 9),
        'visibility': 'public' if all(target.visible for target in targets) else 'dm',
    }
    if single:
        options['effect_target'] = single.pk
    roll = use_ability(campaign, user, ability.pk, options)
    parts = roll.payload.get('parts') or [roll.payload]
    if len(parts) * len(targets) > 200:
        raise ValidationError('За один раз можно применить не более 200 результатов по целям')
    healing = effect_kind(roll) == 'healing'
    resolved = not roll.payload.get('deferred') and all(
        any(key in part for key in ('damage', 'save', 'roll')) for part in parts
    )
    summaries = []
    for target in targets:
        summary = {'id': target.pk, 'name': target.name, 'resolved': resolved, 'parts': []}
        summaries.append(summary)
        if not resolved:
            continue
        # The caster can also be a target. Re-read after consuming slots/concentration.
        target = rows_for(roll.session).get(pk=target.pk)
        sheet = target_sheet(target)
        for index, part in enumerate(parts):
            check = part.get('roll') if not healing else None
            outcome = {}
            if check is not None:
                outcome['hit'] = check['chosen'] == 20 or (
                    check['chosen'] != 1 and check['total'] >= sheet.armor_class
                )
            save = part.get('save') if not healing else None
            if 'damage' in part:
                if save:
                    outcome['save_outcome'] = 'roll'
                application = DamageApplication.objects.create(
                    target=target, source_event=roll, requester=user, part_index=index,
                    is_attack=check is not None,
                )
                apply_damage(application, campaign, user, outcome, privileged=True, emit_event=False)
                outcome = {
                    key: application.resolution[key] for key in ('hit', 'save_outcome')
                    if application.resolution.get(key) is not None
                }
            elif save:
                saving_throw = d20(computed(sheet)['saves'][save['ability']])
                outcome['save_outcome'] = 'success' if saving_throw['total'] >= save['dc'] else 'failure'
            summary['parts'].append(outcome)
    if single:
        roll.payload['token_target'] = summaries[0]
    else:
        roll.payload['token_targets'] = summaries
        roll.payload['map_resolved'] = resolved
    roll.save(update_fields=['payload'])
    result = {'event': EventSerializer(roll).data}
    if legacy:
        result['target'] = token_row(single, user, master, game)
    return result


class NativeTokenScene(PersonalSheetAPI):
    @extend_schema(responses=OpenApiTypes.OBJECT)
    def get(self, request):
        access = access_for(request)
        game = identifier(request.query_params.get('game'), 'игра DMHub')
        master = is_dm(access.campaign, access.user)
        session = access.campaign.sessions.filter(status='active').first()
        targets = []
        if session:
            rows = rows_for(session)
            if not master:
                rows = rows.filter(visible=True, dmhub_game=game).exclude(dmhub_token='')
            targets = [token_row(t, access.user, master, game) for t in rows]
        return Response({
            'session': session.pk if session else None, 'is_dm': master, 'targets': targets, 'map_actions': True,
        }, headers={'Cache-Control': 'no-store'})

    @extend_schema(request=OpenApiTypes.OBJECT, responses=OpenApiTypes.OBJECT)
    def post(self, request):
        access, data = access_for(request), bridge_payload(request)
        game = identifier(data.get('game'), 'игра DMHub')

        def operation(campaign, user):
            session = active_session(campaign)
            if type(data.get('session')) is not int or data['session'] != session.pk:
                raise ValidationError('Игровая сессия изменилась. Выберите цель заново.')
            master = is_dm(campaign, user)
            if data.get('command') == 'link':
                return link_target(session, user, master, game, data)
            if data.get('command') == 'act':
                return act_on_map(campaign, user, session, master, game, data)
            if data.get('command') == 'cast':
                return cast_spell(campaign, user, session, master, game, data)
            raise ValidationError('Неизвестная команда токена')

        response = response_for(request, access, operation)
        response['Cache-Control'] = 'no-store'
        return response
