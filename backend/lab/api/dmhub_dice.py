"""Authenticated dice writes and role-scoped events for the native dice tray."""
from django.db.models import Max
from drf_spectacular.types import OpenApiTypes
from drf_spectacular.utils import extend_schema
from rest_framework.exceptions import ValidationError
from rest_framework.response import Response

from lab.models import RoomEvent
from lab.services.sheets import perform_roll
from .common import is_dm
from .dmhub import _line
from .dmhub_edit import PersonalSheetAPI
from .dmhub_sheets import access_for, bridge_payload, response_for


class NativeDice(PersonalSheetAPI):
    @extend_schema(request=OpenApiTypes.OBJECT, responses=OpenApiTypes.OBJECT)
    def post(self, request):
        access, data = access_for(request), bridge_payload(request)
        if data.get('visibility', 'public') not in ('public', 'dm'):
            raise ValidationError('Видимость: public или dm')
        character = data.get('character')
        if character is not None and type(character) is not int:
            raise ValidationError('Выберите персонажа')
        if character is None and not is_dm(access.campaign, access.user):
            raise ValidationError('Игрок должен выбрать своего персонажа')
        roll = {'kind': 'custom', 'formula': data.get('formula', ''), 'character': character,
                'visibility': data.get('visibility', 'public')}
        response = response_for(request, access, lambda campaign, user: _line(perform_roll(campaign, user, roll)))
        response['Cache-Control'] = 'no-store'
        return response


class NativeDiceEvents(PersonalSheetAPI):
    @extend_schema(responses=OpenApiTypes.OBJECT)
    def get(self, request):
        access = access_for(request)
        events = RoomEvent.objects.filter(campaign=access.campaign, kind__in=('roll', 'ability'))
        if not is_dm(access.campaign, access.user):
            events = events.filter(visibility='public')
        cursor = request.query_params.get('cursor', 'latest')
        if cursor == 'latest':
            return Response({'events': [], 'cursor': events.aggregate(value=Max('id'))['value'] or 0}, headers={'Cache-Control': 'no-store'})
        try:
            cursor = int(cursor)
            if not 0 <= cursor <= 9223372036854775807:
                raise ValueError
        except (ValueError, TypeError):
            raise ValidationError('Некорректный курсор')
        rows = list(events.filter(id__gt=cursor).order_by('id')[:50])
        return Response({'events': [_line(row) for row in rows], 'cursor': rows[-1].pk if rows else cursor}, headers={'Cache-Control': 'no-store'})
