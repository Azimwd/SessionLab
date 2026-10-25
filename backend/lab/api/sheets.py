from django.shortcuts import get_object_or_404
from drf_spectacular.types import OpenApiTypes
from drf_spectacular.utils import extend_schema
from rest_framework import serializers
from rest_framework.exceptions import APIException, ValidationError
from rest_framework.response import Response
from rest_framework.views import APIView

from lab.models import CharacterAbility, CharacterSheet, RoomEvent, SpellCatalogEntry
from lab.services.dice import parse_formula
from lab.services.sheets import (
    ABILITIES,
    CONDITIONS,
    SKILLS,
    computed,
    controlled_character,
    event,
    perform_roll,
    sheet_for,
    use_ability,
)

from .common import campaign_for, mutate


class StaleVersion(APIException):
    status_code = 409
    default_detail = (
        "Данные уже изменены в другом окне. Обновите лист перед сохранением."
    )


def require_version(obj, data):
    if type(data.get("version")) is not int or data["version"] != obj.version:
        raise StaleVersion()


class SheetSerializer(serializers.ModelSerializer):
    computed = serializers.SerializerMethodField()

    class Meta:
        model = CharacterSheet
        exclude = ["created_at", "updated_at"]
        read_only_fields = ["id", "character", "version"]

    def get_computed(self, obj) -> dict:
        return computed(obj)

    def validate_abilities(self, value):
        if (
            not isinstance(value, dict)
            or set(value) != set(ABILITIES)
            or any(type(v) is not int or not 1 <= v <= 30 for v in value.values())
        ):
            raise ValidationError("Укажите 6 характеристик: целые значения от 1 до 30")
        return value

    def validate_skills(self, value):
        if (
            not isinstance(value, dict)
            or set(value) - set(SKILLS)
            or any(type(v) is not int or v not in [0, 1, 2] for v in value.values())
        ):
            raise ValidationError(
                "Навыки: 0 — без владения, 1 — владение, 2 — экспертиза"
            )
        return value

    def validate_saves(self, value):
        if (
            not isinstance(value, list)
            or any(type(v) is not str or v not in ABILITIES for v in value)
            or len(set(value)) != len(value)
        ):
            raise ValidationError("Некорректные владения спасбросками")
        return value

    def validate_slots(self, value):
        if not isinstance(value, dict) or set(value) != {str(n) for n in range(1, 10)}:
            raise ValidationError("Укажите ячейки уровней 1–9")
        for slot in value.values():
            if (
                not isinstance(slot, dict)
                or set(slot) != {"max", "used"}
                or any(type(v) is not int for v in slot.values())
                or not 0 <= slot["used"] <= slot["max"] <= 20
            ):
                raise ValidationError("Ячейки: 0 ≤ потрачено ≤ максимум ≤ 20")
        return value

    def validate_conditions(self, value):
        if (
            not isinstance(value, list)
            or len(value) > len(CONDITIONS)
            or any(type(v) is not str or v not in CONDITIONS for v in value)
        ):
            raise ValidationError("Неизвестное состояние")
        return list(dict.fromkeys(value))

    def validate(self, data):
        for key, lo, hi in [
            ("armor_class", 0, 50),
            ("hp_max", 1, 10000),
            ("hp_current", 0, 10000),
            ("hp_temp", 0, 10000),
            ("speed", 0, 1000),
            ("initiative_bonus", -30, 30),
            ("death_successes", 0, 3),
            ("death_failures", 0, 3),
            ("proficiency_override", 0, 15),
        ]:
            if key in data and data[key] is not None and not lo <= data[key] <= hi:
                raise ValidationError({key: f"Значение от {lo} до {hi}"})
        if data.get("hp_current", self.instance.hp_current) > data.get(
            "hp_max", self.instance.hp_max
        ):
            raise ValidationError("Текущие хиты не могут превышать максимум")
        if data.get("spell_ability", self.instance.spell_ability) not in ABILITIES:
            raise ValidationError("Неизвестная заклинательная характеристика")
        for key in ["inventory", "notes", "background"]:
            if len(data.get(key, "")) > 20000:
                raise ValidationError("Текст слишком длинный")
        return data


class AbilitySerializer(serializers.ModelSerializer):
    rules_verified = serializers.SerializerMethodField()
    rules_recurring = serializers.SerializerMethodField()
    rules_deferred = serializers.SerializerMethodField()
    rules_fixed_dc = serializers.SerializerMethodField()
    rules_possible_saves = serializers.SerializerMethodField()

    def get_rules_verified(self, obj) -> bool | None:
        return bool(obj.catalog_entry.template.get('verified')) if obj.catalog_entry_id else None

    def get_rules_recurring(self, obj) -> bool:
        return bool(obj.catalog_entry.template.get('recurring')) if obj.catalog_entry_id else False

    def get_rules_deferred(self, obj) -> bool:
        return bool(obj.catalog_entry.template.get('deferred')) if obj.catalog_entry_id else False

    def get_rules_fixed_dc(self, obj) -> int:
        return int(obj.catalog_entry.template.get('fixed_save_dc') or 0) if obj.catalog_entry_id else 0

    def get_rules_possible_saves(self, obj) -> list[str]:
        return obj.catalog_entry.template.get('possible_saves', []) if obj.catalog_entry_id else []

    class Meta:
        model = CharacterAbility
        exclude = ["created_at", "updated_at"]
        read_only_fields = ["id", "character", "version", "catalog_entry", "rules_verified", "rules_recurring", "rules_deferred", "rules_fixed_dc", "rules_possible_saves"]
        extra_kwargs = {"dice": {"allow_blank": True}}

    def validate(self, data):
        get = lambda k, default=None: data.get(k, getattr(self.instance, k, default))
        if (
            get("ability", "str") not in ABILITIES
            or get("save_ability", "dex") not in ABILITIES
        ):
            raise ValidationError("Неизвестная характеристика")
        for key in ["dice", "upcast_dice"]:
            if get(key):
                parse_formula(get(key))
        if not 0 <= get("level", 0) <= 9 or not -30 <= get("bonus", 0) <= 30:
            raise ValidationError("Уровень: 0–9, бонус: −30…30")
        if get("kind") == "attack" and get("level", 0) != 0:
            raise ValidationError("Атаки не используют ячейки заклинаний")
        # Cantrips scale with character level, never with a spell slot.
        if get("kind") == "spell" and get("level", 0) > 0 and not get("upcast_allowed", True) and (get("upcast_dice", "") or get("upcast_count", 0)):
            raise ValidationError("Усиление ячейкой отключено для этого заклинания")
        if not 1 <= get("roll_count", 1) <= 20 or not 0 <= get("upcast_count", 0) <= 5:
            raise ValidationError("Количество бросков: 1–20; добавочные броски: 0–5")
        if len(get("description", "")) > 10000:
            raise ValidationError("Описание слишком длинное")
        return data


class SheetUpdateRequest(SheetSerializer):
    version = serializers.IntegerField(
        min_value=1, help_text="Current server version; stale values return HTTP 409."
    )


class AbilityUpdateRequest(AbilitySerializer):
    version = serializers.IntegerField(
        min_value=1, help_text="Current server version; stale values return HTTP 409."
    )


class EventSerializer(serializers.ModelSerializer):
    actor_name = serializers.SerializerMethodField()

    class Meta:
        model = RoomEvent
        fields = [
            "id",
            "session",
            "character",
            "kind",
            "visibility",
            "payload",
            "created_at",
            "actor_name",
        ]

    def get_actor_name(self, obj) -> str:
        return obj.actor.first_name or "Участник"


class SheetView(APIView):
    @extend_schema(responses=SheetSerializer)
    def get(self, request, pk):
        c = campaign_for(request)
        char = controlled_character(c, request.user, pk)
        return Response(SheetSerializer(sheet_for(char)).data)

    @extend_schema(request=SheetUpdateRequest, responses=SheetSerializer)
    def patch(self, request, pk):
        def op(c):
            char = controlled_character(c, request.user, pk)
            sheet = sheet_for(char)
            require_version(sheet, request.data)
            form = SheetSerializer(sheet, data=request.data, partial=True)
            form.is_valid(raise_exception=True)
            form.save(version=sheet.version + 1)
            return form.data

        return mutate(request, None, op)


class SheetResource(APIView):
    @extend_schema(request=OpenApiTypes.OBJECT, responses=SheetSerializer)
    def post(self, request, pk):
        def op(c):
            char = controlled_character(c, request.user, pk)
            sheet = sheet_for(char)
            verb, amount = request.data.get("action"), request.data.get("amount", 0)
            if type(amount) is not int or not 0 <= amount <= 10000:
                raise ValidationError("Количество: целое число от 0 до 10000")
            if verb == "damage":
                absorbed = min(sheet.hp_temp, amount)
                sheet.hp_temp -= absorbed
                sheet.hp_current = max(0, sheet.hp_current - amount + absorbed)
            elif verb == "heal":
                sheet.hp_current = min(sheet.hp_max, sheet.hp_current + amount)
                if sheet.hp_current:
                    sheet.death_successes = sheet.death_failures = 0
            elif verb == "temporary":
                sheet.hp_temp = max(sheet.hp_temp, amount)
            elif verb == "restore_slots":
                require_version(sheet, request.data)
                sheet.slots = {k: {**v, "used": 0} for k, v in sheet.slots.items()}
            else:
                raise ValidationError("Неизвестное действие")
            sheet.version += 1
            sheet.save()
            s = c.sessions.filter(status="active").first()
            if s:
                event(
                    c,
                    s,
                    request.user,
                    char,
                    "resource",
                    {
                        "label": {
                            "damage": "Получен урон",
                            "heal": "Восстановлены хиты",
                            "temporary": "Временные хиты",
                            "restore_slots": "Восстановлены ячейки",
                        }[verb],
                        "amount": amount,
                        "hp_current": sheet.hp_current,
                        "hp_max": sheet.hp_max,
                    },
                )
            return SheetSerializer(sheet).data

        return mutate(request, None, op)


class AbilitiesView(APIView):
    @extend_schema(responses=AbilitySerializer(many=True))
    def get(self, request, pk):
        char = controlled_character(campaign_for(request), request.user, pk)
        return Response(
            AbilitySerializer(
                char.actions.filter(active=True).order_by("kind", "level", "name"),
                many=True,
            ).data
        )

    @extend_schema(request=AbilitySerializer, responses=AbilitySerializer)
    def post(self, request, pk):
        def op(c):
            char = controlled_character(c, request.user, pk)
            if char.actions.filter(active=True).count() >= 200:
                raise ValidationError("Лимит: 200 активных действий на персонажа")
            form = AbilitySerializer(data=request.data)
            form.is_valid(raise_exception=True)
            form.save(character=char)
            return form.data

        return mutate(request, None, op)


class SpellCatalogView(APIView):
    @extend_schema(responses=OpenApiTypes.OBJECT)
    def get(self, request):
        campaign_for(request)
        qs = SpellCatalogEntry.objects.filter(active=True)
        q = request.query_params.get("q", "").strip()[:100]
        if q:
            from django.db.models import Q
            from django.db import connection
            if connection.vendor == 'sqlite':
                # SQLite's LIKE/LOWER do not case-fold Cyrillic. The SRD index is
                # small and this keeps local search consistent with PostgreSQL.
                needle = q.casefold()
                ids = [row['id'] for row in qs.values('id','name_ru','name_en','template')
                       if any(needle in str(value).casefold() for value in
                              (row['name_ru'],row['name_en'],row['template'].get('translated_name',''),row['template'].get('description',''),row['template'].get('source_en','')))]
                qs = qs.filter(pk__in=ids)
            else:
                qs = qs.filter(Q(name_ru__icontains=q) | Q(name_en__icontains=q) | Q(template__translated_name__icontains=q) | Q(template__description__icontains=q) | Q(template__source_en__icontains=q))
        level = request.query_params.get("level")
        if level is not None:
            try:
                level = int(level)
            except ValueError:
                raise ValidationError("Некорректный уровень")
            if not 0 <= level <= 9:
                raise ValidationError("Некорректный уровень")
            qs = qs.filter(level=level)
        from lab.data.spell_metadata import CLASS_NAMES, SCHOOL_NAMES, catalog_names
        cls = request.query_params.get('class', '')
        school = request.query_params.get('school', '')
        if cls and cls not in CLASS_NAMES:
            raise ValidationError('Неизвестный класс')
        if school and school not in SCHOOL_NAMES:
            raise ValidationError('Неизвестная школа магии')
        if cls or school:
            qs = qs.filter(name_en__in=catalog_names(cls, school))
        status = request.query_params.get('status', '')
        if status not in ['', 'verified', 'reference']:
            raise ValidationError('Неизвестный статус правил')
        if status:
            qs = qs.filter(template__verified=status == 'verified')
        sort = request.query_params.get('sort', 'level')
        if sort not in ['level', 'name', '-level']:
            raise ValidationError('Неизвестная сортировка')
        qs = qs.order_by(*({'level': ('level','name_ru'), 'name': ('name_ru',), '-level': ('-level','name_ru')}[sort]))
        offset = request.query_params.get("offset", "0")
        try:
            offset = int(offset)
        except ValueError:
            raise ValidationError("Некорректное смещение")
        if not 0 <= offset <= 10000:
            raise ValidationError("Некорректное смещение")
        total = qs.count()
        return Response({"count": total, "results": [
            {"id": entry.pk, "code": entry.code, "name_ru": entry.name_ru,
             "name_en": entry.name_en, "level": entry.level, "edition": entry.edition,
             "source": entry.source, "rules": entry.template}
            for entry in qs[offset:offset+30]
        ]})


class SpellCatalogDetail(APIView):
    @extend_schema(responses=OpenApiTypes.OBJECT)
    def get(self, request, pk):
        campaign_for(request)
        entry = get_object_or_404(SpellCatalogEntry, pk=pk, active=True)
        return Response({'id': entry.pk, 'code': entry.code, 'name_ru': entry.name_ru,
                         'name_en': entry.name_en, 'level': entry.level,
                         'edition': entry.edition, 'source': entry.source,
                         'rules': entry.template})


class AddCatalogSpell(APIView):
    @extend_schema(request=OpenApiTypes.OBJECT, responses=AbilitySerializer)
    def post(self, request, pk):
        def op(c):
            char = controlled_character(c, request.user, pk)
            entry = get_object_or_404(SpellCatalogEntry, pk=request.data.get("spell_id"), active=True)
            if char.actions.filter(active=True).count() >= 200:
                raise ValidationError("Лимит: 200 активных действий на персонажа")
            existing = char.actions.filter(catalog_entry=entry, active=True).first()
            if existing:
                return AbilitySerializer(existing).data
            template = {**entry.template, "kind": "spell", "name": entry.name_ru, "level": entry.level, "ability": sheet_for(char).spell_ability}
            form = AbilitySerializer(data=template)
            form.is_valid(raise_exception=True)
            form.save(character=char, catalog_entry=entry)
            return form.data
        return mutate(request, None, op)


class AbilityDetail(APIView):
    @extend_schema(request=AbilityUpdateRequest, responses=AbilitySerializer)
    def patch(self, request, pk):
        def op(c):
            obj = get_object_or_404(CharacterAbility, pk=pk, character__campaign=c)
            controlled_character(c, request.user, obj.character_id)
            require_version(obj, request.data)
            form = AbilitySerializer(obj, data=request.data, partial=True)
            form.is_valid(raise_exception=True)
            form.save(version=obj.version + 1)
            return form.data

        return mutate(request, None, op)


class RollView(APIView):
    @extend_schema(request=OpenApiTypes.OBJECT, responses=EventSerializer)
    def post(self, request):
        return mutate(
            request,
            None,
            lambda c: EventSerializer(perform_roll(c, request.user, request.data)).data,
        )


class AbilityUse(APIView):
    @extend_schema(request=OpenApiTypes.OBJECT, responses=EventSerializer)
    def post(self, request, pk):
        return mutate(
            request,
            None,
            lambda c: (
                EventSerializer(use_ability(c, request.user, pk, request.data)).data
            ),
        )
