"""Map token bindings and authoritative, single-target DMHub spells."""

import re

from django.shortcuts import get_object_or_404
from drf_spectacular.types import OpenApiTypes
from drf_spectacular.utils import extend_schema
from rest_framework.exceptions import PermissionDenied, ValidationError
from rest_framework.response import Response

from lab.models import CharacterAbility, DamageApplication, SceneTarget
from lab.services.sheets import active_session, controlled_character, use_ability

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
    roll = use_ability(campaign, user, spell.pk, {
        'slot_level': integer(data.get('slot_level'), 'Уровень ячейки', 0, 9),
        'effect_target': target.pk,
        'visibility': 'public' if target.visible else 'dm',
    })
    summary = {'id': target.pk, 'name': target.name, 'resolved': False, 'parts': []}
    roll.payload['token_target'] = summary
    parts = roll.payload.get('parts') or [roll.payload]
    healing = effect_kind(roll) == 'healing'
    if not roll.payload.get('deferred') and all('damage' in part for part in parts):
        # The outcome is computed here. The client never supplies hit/save or HP values.
        # Re-read the sheet after use_ability, including when the caster targets itself.
        target = rows_for(session).get(pk=target.pk)
        armor_class = target_sheet(target).armor_class
        for index, part in enumerate(parts):
            check = part.get('roll') if not healing else None
            outcome = {}
            if check is not None:
                outcome['hit'] = check['chosen'] == 20 or (
                    check['chosen'] != 1 and check['total'] >= armor_class
                )
            if 'save' in part and not healing:
                outcome['save_outcome'] = 'roll'
            row = DamageApplication.objects.create(
                target=target, source_event=roll, requester=user, part_index=index,
                is_attack=check is not None,
            )
            apply_damage(row, campaign, user, outcome, privileged=True, emit_event=False)
            resolution = row.resolution
            # Do not include target HP, AC, resistances or exact damage received.
            summary['parts'].append({
                key: resolution[key] for key in ('hit', 'save_outcome')
                if resolution.get(key) is not None
            })
        summary['resolved'] = True
    roll.save(update_fields=['payload'])
    return {'event': EventSerializer(roll).data, 'target': token_row(target, user, master, game)}


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
            'session': session.pk if session else None, 'is_dm': master, 'targets': targets,
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
            if data.get('command') == 'cast':
                return cast_spell(campaign, user, session, master, game, data)
            raise ValidationError('Неизвестная команда токена')

        response = response_for(request, access, operation)
        response['Cache-Control'] = 'no-store'
        return response
