"""Map bindings and transactional DMHub action resolution."""

import re
from collections import defaultdict

from django.shortcuts import get_object_or_404
from django.utils import timezone
from drf_spectacular.types import OpenApiTypes
from drf_spectacular.utils import extend_schema
from rest_framework.exceptions import PermissionDenied, ValidationError
from rest_framework.response import Response

from lab.models import Character, CharacterAbility, DamageApplication, DMHubTokenBinding, InitiativeTracker, SceneTarget
from lab.services.dice import d20
from lab.services.map_actions import map_targeting
from lab.services.sheets import active_session, computed, controlled_character, event, use_ability

from .common import is_dm
from .dmhub_edit import PersonalSheetAPI
from .dmhub_sheets import access_for, bridge_payload, response_for
from .scene import apply_damage, create_scene_targets, effect_kind, integer, target_sheet
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
    DMHubTokenBinding.objects.update_or_create(
        campaign_id=session.campaign_id, game=game, token=token, defaults={'source_id': target.source_id},
    )
    return {'target': token_row(target, user, master, game)}


def roster_sheets(campaign):
    return Character.objects.filter(campaign=campaign, active=True, scene_copy__isnull=True)


def change_binding(campaign, user, game, data):
    if not is_dm(campaign, user):
        raise PermissionDenied('Общей привязкой токена управляет мастер')
    if set(data) - {'command', 'game', 'token', 'sheet'}:
        raise ValidationError('Неизвестные поля привязки токена')
    token = identifier(data.get('token'), 'токен DMHub')
    source_id = integer(data.get('sheet'), 'Лист', 0, 2**63-1)
    if SceneTarget.objects.filter(
        session__campaign=campaign, session__status='active', active=True, dmhub_game=game, dmhub_token=token,
    ).exists():
        raise ValidationError('Сначала отвяжите токен от текущего участника сцены')
    bindings = DMHubTokenBinding.objects.filter(campaign=campaign, game=game, token=token)
    if source_id == 0:
        bindings.delete()
        return {'unlinked': True}
    source = get_object_or_404(roster_sheets(campaign), pk=source_id)
    bindings.update_or_create(
        campaign=campaign, game=game, token=token, defaults={'source': source},
    )
    return {'binding': {'sheet': source.pk, 'name': source.name}}


def enrollment_roster(campaign, game, session):
    return {
        'session_name': session.name if session else '',
        'characters': list(roster_sheets(campaign).order_by('name', 'pk').values('id', 'name', 'kind', 'folder__name')),
        'bindings': dict(DMHubTokenBinding.objects.filter(
            campaign=campaign, game=game, source__in=roster_sheets(campaign),
        ).values_list('token', 'source_id')),
    }


def token_selection(chosen, fields):
    if isinstance(chosen, dict) and len(chosen) <= 50:
        indexes = [str(i) for i in range(1, len(chosen) + 1)]
        if set(chosen) == set(indexes):
            chosen = [chosen[i] for i in indexes]
    if not isinstance(chosen, list) or not 1 <= len(chosen) <= 50:
        raise ValidationError('Выберите от 1 до 50 токенов')
    selection = {}
    for entry in chosen:
        if not isinstance(entry, dict) or set(entry) - fields:
            raise ValidationError('Некорректный токен')
        token = identifier(entry.get('token'), 'токен DMHub')
        if token in selection or type(entry.get('hidden', False)) is not bool:
            raise ValidationError('Некорректное выделение токенов')
        selection[token] = entry
    return selection


def roll_token_initiative(session, user, targets, *, reveal_hidden=True):
    # Both the site and the DMHub API hold the campaign lock during initiative writes.
    tracker, _ = InitiativeTracker.objects.get_or_create(session=session)
    entries = {}
    roster = list(tracker.entries.all())
    for entry in roster:
        entries.setdefault(entry.player_slot_id or entry.character_id, entry)
    additions = {target.sheet_character.pk for target in targets} - entries.keys()
    if len(roster) + len(additions) > 100:
        raise ValidationError('Лимит: 100 участников инициативы')
    results = []
    for target in targets:
        character = target.sheet_character
        entry = entries.get(character.pk)
        if entry and entry.hidden and not reveal_hidden:
            raise PermissionDenied('Мастер скрыл запись инициативы')
        rolled = entry is None
        if rolled:
            stats = computed(target_sheet(target))
            result = d20(stats['initiative'])
            entry = tracker.entries.create(
                character=character, player_slot=character if character.kind == 'player' else None,
                name=target.name, initiative=result['total'], dexterity=stats['modifiers']['dex'],
                hidden=not target.visible,
            )
            entries[character.pk] = entry
            event(session.campaign, session, user, character, 'roll', {
                'label': 'Инициатива', 'character_name': target.name, 'roll': result,
            }, visibility='dm' if entry.hidden else 'public')
        results.append({'id': entry.pk, 'name': entry.name, 'total': entry.initiative, 'rolled': rolled})
    if additions:
        tracker.version += 1
        tracker.save(update_fields=['version', 'updated_at'])
    return results


def token_initiative(session, user, game, data):
    if set(data) - {'command', 'game', 'session', 'tokens'}:
        raise ValidationError('Неизвестные поля броска инициативы')
    selection = token_selection(data.get('tokens'), {'token'})
    targets = rows_for(session).filter(
        dmhub_game=game, dmhub_token__in=selection, visible=True, source__kind='player', source__owner=user,
    )
    mapped = {target.dmhub_token: target for target in targets if target.uses_sheet}
    if len(mapped) != len(selection):
        raise PermissionDenied('Выберите своих персонажей, привязанных к активной сцене')
    return {'initiative': roll_token_initiative(
        session, user, [mapped[token] for token in selection], reveal_hidden=False,
    )}


def enroll_tokens(campaign, user, game, data):
    if not is_dm(campaign, user):
        raise PermissionDenied('Добавлять токены в сессию может только мастер')
    if set(data) - {'command', 'game', 'session', 'session_name', 'tokens'}:
        raise ValidationError('Неизвестные поля добавления токенов')
    expected = integer(data.get('session'), 'Сессия', 0, 2**63-1)
    session = campaign.sessions.filter(status='active').first()
    if expected != (session.pk if session else 0):
        raise ValidationError('Активная сессия изменилась. Откройте список токенов заново.')
    selection = token_selection(data.get('tokens'), {'token', 'sheet', 'hidden'})

    mapped = {}
    unlinked = defaultdict(list)
    if session:
        for target in rows_for(session).order_by('scene_number', 'pk'):
            if target.dmhub_game == game and target.dmhub_token:
                mapped[target.dmhub_token] = target
            elif not target.dmhub_token and target.uses_sheet:
                unlinked[target.source_id].append(target)
    bindings = dict(DMHubTokenBinding.objects.filter(
        campaign=campaign, game=game, token__in=selection,
    ).values_list('token', 'source_id'))
    groups = defaultdict(list)
    for token, entry in selection.items():
        if token in mapped:
            continue
        source_id = integer(entry.get('sheet', bindings.get(token)), 'Лист', 1, 2**63-1)
        groups[source_id].append(token)
    sources = roster_sheets(campaign).in_bulk(groups)
    if len(sources) != len(groups):
        raise ValidationError('Один из листов больше недоступен')
    if not session:
        name = data.get('session_name')
        if not isinstance(name, str) or not 1 <= len(name.strip()) <= 120:
            raise ValidationError('Введите название новой сессии')
        session = campaign.sessions.create(name=name.strip(), date=timezone.now(), status='active')

    results = {token: {'id': mapped[token].pk, 'name': mapped[token].name, 'added': False}
               for token in selection if token in mapped}
    for source_id, tokens in groups.items():
        source = sources[source_id]
        available = unlinked[source_id][:len(tokens)]
        count = len(tokens) - len(available)
        if count:
            available += create_scene_targets(session, source, count, source.name.strip()[:85], {})
        for token, target in zip(tokens, available):
            target.dmhub_game, target.dmhub_token = game, token
            fields = ['dmhub_game', 'dmhub_token', 'updated_at']
            if selection[token].get('hidden') and target.visible:
                target.visible = False
                target.version += 1
                fields += ['visible', 'version']
            target.save(update_fields=fields)
            DMHubTokenBinding.objects.update_or_create(
                campaign=campaign, game=game, token=token, defaults={'source_id': source_id},
            )
            results[token] = {'id': target.pk, 'name': target.name, 'added': True}
    result = {'session': session.pk, 'targets': [results[token] for token in selection]}
    if data['command'] == 'enroll-initiative':
        selected = rows_for(session).in_bulk(row['id'] for row in result['targets'])
        result['initiative'] = roll_token_initiative(session, user, [selected[row['id']] for row in result['targets']])
    return result


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
            saving_throw = None
            if 'damage' in part:
                if save:
                    outcome['save_outcome'] = 'roll'
                application = DamageApplication.objects.create(
                    target=target, source_event=roll, requester=user, part_index=index,
                    is_attack=check is not None,
                )
                apply_damage(application, campaign, user, outcome, privileged=True, emit_event=False)
                saving_throw = application.resolution.get('save_roll')
                outcome = {
                    key: application.resolution[key] for key in ('hit', 'save_outcome')
                    if application.resolution.get(key) is not None
                }
            elif save:
                saving_throw = d20(computed(sheet)['saves'][save['ability']])
                outcome['save_outcome'] = 'success' if saving_throw['total'] >= save['dc'] else 'failure'
            if saving_throw is not None:
                outcome.update(save_total=saving_throw['total'], save_dc=save['dc'])
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
        roster = request.query_params.get('roster') == '1'
        if roster and not master:
            raise PermissionDenied('Составом сессии управляет мастер')
        session = access.campaign.sessions.filter(status='active').first()
        targets = []
        if session:
            rows = rows_for(session)
            if not master:
                rows = rows.filter(visible=True, dmhub_game=game).exclude(dmhub_token='')
            targets = [token_row(t, access.user, master, game) for t in rows]
        result = {
            'session': session.pk if session else None, 'is_dm': master, 'targets': targets, 'map_actions': True,
        }
        if roster:
            result['enrollment'] = enrollment_roster(access.campaign, game, session)
        if master and 'token' in request.query_params:
            token = identifier(request.query_params['token'], 'токен DMHub')
            binding = DMHubTokenBinding.objects.filter(
                campaign=access.campaign, game=game, token=token, source__active=True,
            ).values_list('source_id', 'source__name').first()
            if binding:
                result['binding'] = {'sheet': binding[0], 'name': binding[1]}
        return Response(result, headers={'Cache-Control': 'no-store'})

    @extend_schema(request=OpenApiTypes.OBJECT, responses=OpenApiTypes.OBJECT)
    def post(self, request):
        access, data = access_for(request), bridge_payload(request)
        game = identifier(data.get('game'), 'игра DMHub')
        command = data.get('command')
        if command in ('bind', 'enroll', 'enroll-initiative') and not is_dm(access.campaign, access.user):
            raise PermissionDenied('Составом сессии и привязками управляет мастер')

        def operation(campaign, user):
            if command in ('enroll', 'enroll-initiative'):
                return enroll_tokens(campaign, user, game, data)
            if data.get('command') == 'bind':
                return change_binding(campaign, user, game, data)
            session = active_session(campaign)
            if type(data.get('session')) is not int or data['session'] != session.pk:
                raise ValidationError('Игровая сессия изменилась. Выберите цель заново.')
            if command == 'initiative':
                return token_initiative(session, user, game, data)
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
