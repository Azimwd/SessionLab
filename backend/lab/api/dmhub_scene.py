"""Native DMHub transport for shared scene participants and immediate damage."""
from drf_spectacular.types import OpenApiTypes
from drf_spectacular.utils import extend_schema
from rest_framework.exceptions import PermissionDenied, ValidationError
from rest_framework.response import Response
from lab.models import SceneTarget, RoomEvent, DamageApplication
from lab.services.sheets import active_session
from .common import is_dm
from .dmhub_edit import PersonalSheetAPI
from .dmhub_sheets import access_for, bridge_payload, response_for
from .scene import (DAMAGE_TYPES, target_data, part_for, application_data,
                    create_targets, update_target, submit_damage, integer, effect_kind)


class NativeScene(PersonalSheetAPI):
    @extend_schema(responses=OpenApiTypes.OBJECT)
    def get(self, request):
        access = access_for(request)
        c, user = access.campaign, access.user
        dm = is_dm(c, user) and request.query_params.get('view') != 'player'
        session = c.sessions.filter(status='active').first()
        targets, sources, applications = [], [], []
        if session:
            rows = SceneTarget.objects.filter(session=session, active=True).select_related('source__sheet').order_by('id')
            if not dm:
                rows = rows.filter(visible=True)
            targets = [target_data(t, dm) for t in rows]
            events = RoomEvent.objects.filter(campaign=c, session=session, kind='ability').order_by('-id')
            if not dm:
                events = events.filter(actor=user)
            for e in events[:100]:
                parts = []
                for index, _ in enumerate(e.payload.get('parts') or [e.payload]):
                    try:
                        part = part_for(e, index)
                    except ValidationError:
                        continue
                    # Explicit projection: never send sheet resources or raw event payloads.
                    item = {'index': index, 'damage': {'total': part['damage']['total']}}
                    if 'roll' in part:
                        item['roll'] = {'total': part['roll'].get('total')}
                    if 'save' in part:
                        item['save'] = {k: v for k, v in part['save'].items()
                                        if k in ('ability', 'dc', 'failed_damage', 'success_damage')}
                    parts.append(item)
                if parts:
                    sources.append({'id': e.id, 'label': e.payload.get('label', 'Действие'),
                                    'damage_type': e.payload.get('damage_type', ''), 'effect': effect_kind(e), 'parts': parts})
            history = DamageApplication.objects.filter(target__session=session, status='applied').select_related(
                'target__source__sheet', 'source_event', 'requester').order_by('-id')
            if not dm:
                history = history.filter(requester=user, target__visible=True)
            applications = [application_data(r, dm) for r in history[:100]]
        return Response({'session': session.pk if session else None, 'master_view': dm,
                         'targets': targets, 'sources': sources, 'applications': applications,
                         'damage_types': DAMAGE_TYPES}, headers={'Cache-Control': 'no-store'})


class NativeSceneCommand(PersonalSheetAPI):
    @extend_schema(request=OpenApiTypes.OBJECT, responses=OpenApiTypes.OBJECT)
    def post(self, request):
        access, data = access_for(request), bridge_payload(request)

        def operation(campaign, user):
            if data.get('session') != active_session(campaign).pk:
                raise ValidationError('Сессия изменилась: обновите комнату перед действием')
            command = data.get('command')
            payload = {k: v for k, v in data.items() if k not in ('command', 'session')}
            if command == 'damage':
                return {'applications': submit_damage(campaign, user, payload)}
            if not is_dm(campaign, user):
                raise PermissionDenied('Участников сессии настраивает только мастер')
            if command == 'add':
                return create_targets(campaign, user, payload)
            if command == 'update':
                pk = integer(payload.pop('target', None), 'Участник', 1, 9223372036854775807)
                if payload.get('conditions') == {}:
                    payload['conditions'] = []
                return update_target(campaign, user, pk, payload)
            raise ValidationError('Команда: damage, add или update')
        response = response_for(request, access, operation)
        response['Cache-Control'] = 'no-store'
        return response
