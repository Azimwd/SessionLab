"""Personal-key transport for the same room read model and commands as the website."""
from drf_spectacular.types import OpenApiTypes
from drf_spectacular.utils import extend_schema
from rest_framework.exceptions import PermissionDenied, ValidationError
from rest_framework.response import Response

from .common import is_dm
from .dmhub_edit import PersonalSheetAPI
from .dmhub_sheets import access_for, bridge_payload, response_for
from .room import room_data, change_initiative, change_table_visibility
from lab.services.sheets import active_session


class NativeRoom(PersonalSheetAPI):
    @extend_schema(responses=OpenApiTypes.OBJECT)
    def get(self, request):
        access = access_for(request)
        dm = is_dm(access.campaign, access.user) and request.query_params.get('view') != 'player'
        result = room_data(access.campaign, access.user, dm)
        # Own-character metadata is irrelevant here; return only the visible table.
        result.data.pop('own_characters', None)
        result.data['master_view'] = dm
        result.data['campaign_name'] = access.campaign.name
        result['Cache-Control'] = 'no-store'
        return result


class NativeRoomCommand(PersonalSheetAPI):
    @extend_schema(request=OpenApiTypes.OBJECT, responses=OpenApiTypes.OBJECT)
    def post(self, request):
        access, data = access_for(request), bridge_payload(request)
        def operation(campaign, user):
            if not is_dm(campaign, user):
                raise PermissionDenied('Только мастер кампании может менять стол и инициативу')
            command = data.get('command')
            if command == 'initiative':
                if data.get('session') != active_session(campaign).pk:
                    raise ValidationError('Сессия изменилась: обновите комнату перед действием')
                if data.get('participants') == {}:
                    data['participants'] = []
                return change_initiative(campaign, user, data)
            if command == 'visibility':
                return change_table_visibility(campaign, user, data)
            raise ValidationError('Команда: initiative или visibility')
        response = response_for(request, access, operation)
        response['Cache-Control'] = 'no-store'
        return response
