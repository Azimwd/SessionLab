"""Personal-token editor for the native DMHub sheet. POST for native net.Post."""
from django.shortcuts import get_object_or_404
from drf_spectacular.types import OpenApiTypes
from drf_spectacular.utils import extend_schema
from rest_framework.exceptions import ValidationError
from rest_framework.permissions import AllowAny
from rest_framework.response import Response
from rest_framework.views import APIView

from lab.models import CharacterAbility, SpellCatalogEntry
from lab.services.sheets import controlled_character, sheet_for
from .dmhub_sheets import access_for, bridge_payload, response_for, sheet_changed
from .sheets import AbilitySerializer, SheetSerializer, require_version, spell_catalog_data


class PersonalSheetAPI(APIView):
    authentication_classes = []
    permission_classes = [AllowAny]


class SheetBridgeEdit(PersonalSheetAPI):
    @extend_schema(request=OpenApiTypes.OBJECT, responses=SheetSerializer)
    def post(self, request, pk):
        access, data = access_for(request), bridge_payload(request)

        def change(campaign, user):
            char = controlled_character(campaign, user, pk)
            sheet = sheet_for(char)
            require_version(sheet, data)
            if data.pop('auto_proficiency', False) is True:
                data['proficiency_override'] = None
            form = SheetSerializer(sheet, data=data, partial=True)
            form.is_valid(raise_exception=True)
            form.save(version=sheet.version + 1)
            sheet_changed(campaign, user, char, 'Лист обновлён из DMHub')
            return form.data
        return response_for(request, access, change)


class SheetBridgeActions(PersonalSheetAPI):
    @extend_schema(request=AbilitySerializer, responses=AbilitySerializer)
    def post(self, request, pk):
        access, data = access_for(request), bridge_payload(request)

        def create(campaign, user):
            char = controlled_character(campaign, user, pk)
            if char.actions.filter(active=True).count() >= 200:
                raise ValidationError('Лимит: 200 активных действий на персонажа')
            form = AbilitySerializer(data=data)
            form.is_valid(raise_exception=True)
            form.save(character=char)
            sheet_changed(campaign, user, char, 'Добавлено действие из DMHub')
            return form.data
        return response_for(request, access, create)


class SheetBridgeActionEdit(PersonalSheetAPI):
    @extend_schema(request=OpenApiTypes.OBJECT, responses=AbilitySerializer)
    def post(self, request, pk, ability_pk):
        access, data = access_for(request), bridge_payload(request)

        def change(campaign, user):
            char = controlled_character(campaign, user, pk)
            obj = get_object_or_404(CharacterAbility, pk=ability_pk, character=char, active=True)
            require_version(obj, data)
            form = AbilitySerializer(obj, data=data, partial=True)
            form.is_valid(raise_exception=True)
            form.save(version=obj.version + 1)
            sheet_changed(campaign, user, char, 'Действие обновлено из DMHub')
            return form.data
        return response_for(request, access, change)


class SheetBridgeCatalog(PersonalSheetAPI):
    @extend_schema(responses=OpenApiTypes.OBJECT)
    def get(self, request):
        access_for(request)
        return Response(spell_catalog_data(request.query_params))


class SheetBridgeCatalogAdd(PersonalSheetAPI):
    @extend_schema(request=OpenApiTypes.OBJECT, responses=AbilitySerializer)
    def post(self, request, pk):
        access, data = access_for(request), bridge_payload(request)

        def add(campaign, user):
            char = controlled_character(campaign, user, pk)
            entry = get_object_or_404(SpellCatalogEntry, pk=data.get('spell_id'), active=True)
            existing = char.actions.filter(active=True, catalog_entry=entry).first()
            if existing:
                return AbilitySerializer(existing).data
            if char.actions.filter(active=True).count() >= 200:
                raise ValidationError('Лимит: 200 активных действий на персонажа')
            template = {**entry.template, 'kind': 'spell', 'name': entry.name_ru,
                        'level': entry.level, 'ability': sheet_for(char).spell_ability}
            form = AbilitySerializer(data=template)
            form.is_valid(raise_exception=True)
            form.save(character=char, catalog_entry=entry)
            sheet_changed(campaign, user, char, 'Добавлено заклинание из справочника')
            return form.data
        return response_for(request, access, add)
