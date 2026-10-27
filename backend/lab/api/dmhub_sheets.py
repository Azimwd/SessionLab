"""User-bound DMHub sheet access. The campaign chat bridge token has no access here."""
import hashlib
import hmac
import json
import math
import secrets

from django.core.serializers.json import DjangoJSONEncoder
from django.db import transaction
from django.db.models import Q
from django.shortcuts import get_object_or_404
from drf_spectacular.types import OpenApiTypes
from drf_spectacular.utils import extend_schema
from rest_framework.exceptions import NotAuthenticated, PermissionDenied, ValidationError
from rest_framework.authentication import BaseAuthentication
from rest_framework.permissions import AllowAny
from rest_framework.response import Response
from rest_framework.views import APIView

from lab.models import (
    AuditLog, Campaign, Character, CharacterFolder, DMHubSheetAccess, IdempotencyRecord, Membership,
)
from lab.services.sheets import controlled_character, event, perform_roll, sheet_for, use_ability
from .common import campaign_for, is_dm
from .sheets import AbilitySerializer, EventSerializer, SheetSerializer, require_version


def digest(token):
    return hashlib.sha256(token.encode('ascii')).hexdigest()


def bridge_integer(value, field):
    """Lua JSON encoders may represent whole numbers as 3.0; never round."""
    if type(value) is int:
        return value
    if type(value) is float and math.isfinite(value) and value.is_integer():
        return int(value)
    raise ValidationError({field: 'Ожидается целое число'})


def bridge_payload(request):
    """Normalize the native Lua encoder without rounding or weakening validation."""
    def normalize(value):
        if type(value) is float:
            return bridge_integer(value, 'number')
        if isinstance(value, dict):
            return {str(k): normalize(v) for k, v in value.items()}
        if isinstance(value, list):
            return [normalize(v) for v in value]
        return value
    if not isinstance(request.data, dict):
        raise ValidationError('Ожидается JSON-объект')
    data = normalize(request.data)
    for key in ('saves', 'conditions'):
        if data.get(key) == {}:
            data[key] = []
    return data


def sheet_changed(campaign, user, char, label):
    session = campaign.sessions.filter(status='active').first()
    if session:
        event(campaign, session, user, char, 'sheet', {'label': label})


class SheetAccessSettings(APIView):
    @extend_schema(responses=OpenApiTypes.OBJECT)
    def get(self, request):
        c = campaign_for(request)
        row = DMHubSheetAccess.objects.filter(campaign=c, user=request.user).first()
        return Response({'enabled': bool(row and row.enabled), 'campaign': c.pk})

    @extend_schema(request=OpenApiTypes.OBJECT, responses=OpenApiTypes.OBJECT)
    def post(self, request):
        action = request.data.get('action')
        if action not in ('rotate', 'revoke'):
            raise ValidationError('Действие: rotate или revoke')
        with transaction.atomic():
            c = campaign_for(request, lock=True)
            if action == 'rotate':
                token = secrets.token_urlsafe(48)
                DMHubSheetAccess.objects.update_or_create(
                    campaign=c, user=request.user,
                    defaults={'token_hash': digest(token), 'enabled': True},
                )
                result = {'campaign': c.pk, 'enabled': True, 'token': token}
            else:
                DMHubSheetAccess.objects.filter(campaign=c, user=request.user).update(enabled=False)
                result = {'campaign': c.pk, 'enabled': False}
            AuditLog.objects.create(
                campaign=c, actor=request.user, action='dmhub sheet ' + action,
                details={},
            )
        return Response(result)


def access_for(request):
    if getattr(request, '_dmhub_sheet_access', None) is not None:
        return request._dmhub_sheet_access
    scheme, _, token = request.headers.get('Authorization', '').partition(' ')
    if scheme.lower() != 'bearer' or not 32 <= len(token) <= 128 or not token.isascii():
        raise NotAuthenticated('Недействительный ключ листа')
    token_hash = digest(token)
    access = DMHubSheetAccess.objects.select_related('campaign', 'user').filter(
        token_hash=token_hash, enabled=True,
    ).first()
    if not access or not hmac.compare_digest(access.token_hash, token_hash):
        raise NotAuthenticated('Недействительный ключ листа')
    if not access.user.is_active or not Membership.objects.filter(
        campaign=access.campaign, user=access.user, active=True,
    ).exists():
        raise PermissionDenied('Доступ к кампании закрыт')
    return access


class PersonalKeyAuthentication(BaseAuthentication):
    """Resolve the user before DRF's per-user throttle; never treat a key as anonymous."""
    def authenticate(self, request):
        access = access_for(request)
        request._dmhub_sheet_access = access
        return access.user, None

    def authenticate_header(self, request):
        return 'Bearer'


def response_for(request, access, operation):
    """Serialize campaign writes and return the same event for retried requests."""
    if not isinstance(request.data, dict):
        raise ValidationError('Ожидается JSON-объект')
    key = request.headers.get('Idempotency-Key', '')
    if not 8 <= len(key) <= 100:
        raise ValidationError('Нужен Idempotency-Key длиной 8–100 символов')
    fingerprint = hashlib.sha256(json.dumps({
        'path': request.path, 'data': request.data,
    }, sort_keys=True, default=str).encode()).hexdigest()
    with transaction.atomic():
        campaign = Campaign.objects.select_for_update().get(pk=access.campaign_id)
        # Revocation/removal may have happened while this request waited for the lock.
        if not DMHubSheetAccess.objects.filter(pk=access.pk, enabled=True).exists() or not Membership.objects.filter(
            campaign=campaign, user=access.user, active=True,
        ).exists():
            raise PermissionDenied('Доступ к кампании закрыт')
        record = IdempotencyRecord.objects.filter(
            campaign=campaign, user=access.user, key=key,
        ).first()
        if record:
            if record.fingerprint != fingerprint:
                raise ValidationError('Этот ключ уже использован для другого запроса')
            return Response(record.response)
        data = json.loads(json.dumps(operation(campaign, access.user), cls=DjangoJSONEncoder))
        IdempotencyRecord.objects.create(
            campaign=campaign, user=access.user, key=key,
            fingerprint=fingerprint, response=data,
        )
        AuditLog.objects.create(
            campaign=campaign, actor=access.user,
            action=request.method + ' ' + request.path, details={'key': key},
        )
        return Response(data)


class SheetBridge(APIView):
    authentication_classes = [PersonalKeyAuthentication]
    permission_classes = [AllowAny]

    @extend_schema(responses=OpenApiTypes.OBJECT)
    def get(self, request):
        access = access_for(request)
        chars = Character.objects.filter(campaign=access.campaign, active=True)
        if not is_dm(access.campaign, access.user):
            chars = chars.filter(owner=access.user)
        folders = CharacterFolder.objects.filter(campaign=access.campaign)
        if not is_dm(access.campaign, access.user):
            folders = folders.filter(Q(is_system=True) | Q(owner=access.user) |
                                     Q(pk__in=chars.values('folder_id')))
        return Response({'campaign': access.campaign.name, 'campaign_id': access.campaign_id,
            'is_dm': is_dm(access.campaign, access.user),
            'folders': [{'id': f.pk, 'name': f.name, 'is_system': f.is_system}
                        for f in folders.order_by('-is_system', 'name', 'pk')],
            'characters': [
            {'id': c.pk, 'name': c.name, 'class': c.character_class,
             'level': c.level, 'kind': c.kind, 'folder': c.folder_id}
            for c in chars.order_by('name', 'pk')[:100]
        ]})


class SheetBridgeDetail(APIView):
    authentication_classes = [PersonalKeyAuthentication]
    permission_classes = [AllowAny]

    @extend_schema(responses=OpenApiTypes.OBJECT)
    def get(self, request, pk):
        access = access_for(request)
        char = controlled_character(access.campaign, access.user, pk)
        return Response({
            'character': {'id': char.pk, 'name': char.name,
                          'class': char.character_class, 'level': char.level,
                          'species': char.species, 'kind': char.kind},
            'sheet': SheetSerializer(sheet_for(char)).data,
            'actions': AbilitySerializer(
                char.actions.filter(active=True).select_related('catalog_entry').order_by(
                    'kind', 'level', 'name'
                ), many=True,
            ).data,
        })


class SheetBridgeRoll(APIView):
    authentication_classes = [PersonalKeyAuthentication]
    permission_classes = [AllowAny]

    @extend_schema(request=OpenApiTypes.OBJECT, responses=OpenApiTypes.OBJECT)
    def post(self, request, pk):
        access = access_for(request)
        if request.data.get('kind') not in ('ability', 'save', 'skill', 'initiative', 'death', 'custom'):
            raise ValidationError('Неизвестный тип броска')
        data = {k: request.data[k] for k in ('kind', 'key', 'mode', 'formula') if k in request.data}
        data.update(character=pk, visibility='public')
        return response_for(request, access, lambda c, u: EventSerializer(
            perform_roll(c, u, data)
        ).data)


class SheetBridgeUse(APIView):
    authentication_classes = [PersonalKeyAuthentication]
    permission_classes = [AllowAny]

    @extend_schema(request=OpenApiTypes.OBJECT, responses=OpenApiTypes.OBJECT)
    def post(self, request, pk, ability_pk):
        access = access_for(request)
        char = controlled_character(access.campaign, access.user, pk)
        ability = get_object_or_404(char.actions, pk=ability_pk, active=True)
        data = {k: request.data[k] for k in ('slot_level', 'mode', 'trigger') if k in request.data}
        if 'slot_level' in data:
            data['slot_level'] = bridge_integer(data['slot_level'], 'slot_level')
        data['visibility'] = 'public'
        return response_for(request, access, lambda c, u: EventSerializer(
            use_ability(c, u, ability.pk, data)
        ).data)


class SheetBridgeResource(APIView):
    authentication_classes = [PersonalKeyAuthentication]
    permission_classes = [AllowAny]

    @extend_schema(request=OpenApiTypes.OBJECT, responses=OpenApiTypes.OBJECT)
    def post(self, request, pk):
        access = access_for(request)
        data = bridge_payload(request)
        action = data.get('action')
        amount = bridge_integer(data.get('amount', 0), 'amount')
        if action not in ('damage', 'heal', 'temporary', 'restore_slots') or not 0 <= amount <= 10000:
            raise ValidationError('Укажите damage, heal или temporary и целое число 0–10000')

        def change(campaign, user):
            char = controlled_character(campaign, user, pk)
            sheet = sheet_for(char)
            if action == 'damage':
                absorbed = min(sheet.hp_temp, amount)
                sheet.hp_temp -= absorbed
                sheet.hp_current = max(0, sheet.hp_current - amount + absorbed)
            elif action == 'heal':
                sheet.hp_current = min(sheet.hp_max, sheet.hp_current + amount)
                if sheet.hp_current:
                    sheet.death_successes = sheet.death_failures = 0
            elif action == 'temporary':
                sheet.hp_temp = max(sheet.hp_temp, amount)
            else:
                require_version(sheet, data)
                sheet.slots = {k: {**v, 'used': 0} for k, v in sheet.slots.items()}
            sheet.version += 1
            sheet.save()
            session = campaign.sessions.filter(status='active').first()
            if session:
                event(campaign, session, user, char, 'resource', {
                    'label': {'damage': 'Получен урон', 'heal': 'Восстановлены хиты',
                              'temporary': 'Временные хиты', 'restore_slots': 'Восстановлены ячейки'}[action],
                    'amount': amount, 'hp_current': sheet.hp_current, 'hp_max': sheet.hp_max,
                })
            return SheetSerializer(sheet).data

        return response_for(request, access, change)
