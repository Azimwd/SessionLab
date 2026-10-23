import math
from rest_framework import serializers
from drf_spectacular.utils import extend_schema_field
from drf_spectacular.types import OpenApiTypes
from lab.models import *
from .common import clean_snapshot, is_dm


def validate_settings(value, partial=False):
    if not isinstance(value, dict):
        raise serializers.ValidationError("Настройки должны быть объектом")
    if set(value) - set(default_settings()):
        raise serializers.ValidationError("Неизвестные настройки")
    for key in ["effect_limit", "quest_limit"]:
        if key in value and (type(value[key]) is not int or not 0 <= value[key] <= 10):
            raise serializers.ValidationError(f"{key}: 0–10")
    if "initial_balance" in value and (
        type(value["initial_balance"]) is not int
        or not 0 <= value["initial_balance"] <= 1000000
    ):
        raise serializers.ValidationError("Начальный баланс: 0–1000000")
    if "edition" in value and value["edition"] not in ["5e-2014", "5e-2024", "custom"]:
        raise serializers.ValidationError("Неизвестная редакция правил")
    if "casino_enabled" in value and type(value["casino_enabled"]) is not bool:
        raise serializers.ValidationError("casino_enabled: boolean")
    if "category_weights" in value:
        w = value["category_weights"]
        if (
            not isinstance(w, dict)
            or set(w) != {"gift", "complication", "paradox"}
            or not all(type(v) is int and 0 <= v <= 10000 for v in w.values())
            or sum(w.values()) <= 0
        ):
            raise serializers.ValidationError("Укажите положительные веса категорий")
    return value


class UserSerializer(serializers.ModelSerializer):
    class Meta:
        model = User
        fields = ["id", "email", "first_name", "theme", "reduced_motion"]

    def validate_theme(self, v):
        if v not in ["light", "dark"]:
            raise serializers.ValidationError("Неизвестная тема")
        return v


class CampaignSerializer(serializers.ModelSerializer):
    role = serializers.SerializerMethodField()

    class Meta:
        model = Campaign
        fields = [
            "id",
            "name",
            "description",
            "owner",
            "settings",
            "invite_code",
            "role",
        ]
        read_only_fields = ["owner", "invite_code"]

    def get_role(self, obj) -> str:
        return "dm" if is_dm(obj, self.context["request"].user) else "player"

    def validate_settings(self, v):
        return {**default_settings(), **validate_settings(v)}

    def to_representation(self, obj):
        data = super().to_representation(obj)
        if not is_dm(obj, self.context["request"].user):
            data.pop("invite_code", None)
        return data


class CharacterSerializer(serializers.ModelSerializer):
    level = serializers.IntegerField(min_value=1, max_value=30, required=False)

    class Meta:
        model = Character
        fields = [
            "id",
            "campaign",
            "owner",
            "name",
            "character_class",
            "level",
            "species",
            "description",
            "avatar",
            "active",
        ]
        read_only_fields = ["campaign", "owner"]


class SessionSerializer(serializers.ModelSerializer):
    class Meta:
        model = GameSession
        fields = ["id", "campaign", "name", "date", "status", "settings"]
        read_only_fields = ["campaign", "status"]

    def validate_settings(self, v):
        return validate_settings(v, True)


class EffectSerializer(serializers.ModelSerializer):
    class Meta:
        model = EffectDefinition
        fields = "__all__"
        read_only_fields = ["id", "campaign", "created_at", "updated_at"]

    def validate_color(self, value):
        import re

        if not re.fullmatch(r"#[0-9A-Fa-f]{6}", value):
            raise serializers.ValidationError("Цвет: #RRGGBB")
        return value

    def validate(self, data):
        if data.get("use_limit", 1) < 1:
            raise serializers.ValidationError("Минимум одно применение")
        p = data.get("parameters", {})
        if not isinstance(p, dict):
            raise serializers.ValidationError("parameters: JSON object")
        return data

    def to_representation(self, obj):
        data = super().to_representation(obj)
        if not self.context.get("dm", False):
            data.pop("secret", None)
        return data


class QuestSerializer(serializers.ModelSerializer):
    class Meta:
        model = QuestDefinition
        fields = "__all__"
        read_only_fields = ["id", "campaign", "created_at", "updated_at"]


class RollSerializer(serializers.ModelSerializer):
    character_name = serializers.CharField(source="character.name", read_only=True)

    class Meta:
        model = EffectRoll
        exclude = []

    def to_representation(self, obj):
        return clean_snapshot(
            super().to_representation(obj), self.context.get("dm", False)
        )


class AssignmentSerializer(serializers.ModelSerializer):
    character_name = serializers.CharField(source="character.name", read_only=True)

    class Meta:
        model = QuestAssignment
        fields = "__all__"


class TransactionSerializer(serializers.ModelSerializer):
    class Meta:
        model = WalletTransaction
        fields = ["id", "amount", "balance_after", "kind", "note", "created_at"]


class ConfigSerializer(serializers.ModelSerializer):
    class Meta:
        model = CasinoConfiguration
        fields = ["id", "game", "enabled", "min_bet", "max_bet", "rules", "version"]
        read_only_fields = ["id", "game", "version"]

    def validate(self, v):
        from lab.services.casino import validate_rules

        if (
            v.get("min_bet", self.instance.min_bet)
            > v.get("max_bet", self.instance.max_bet)
            or v.get("max_bet", self.instance.max_bet) > 100000
        ):
            raise serializers.ValidationError("Некорректные лимиты")
        if v.get("min_bet", self.instance.min_bet) < 1:
            raise serializers.ValidationError("Ставка должна быть положительной")
        validate_rules(self.instance.game, v.get("rules", self.instance.rules))
        return v


class PoolSerializer(serializers.ModelSerializer):
    entries = serializers.SerializerMethodField()

    class Meta:
        model = EffectPool
        fields = ["id", "name", "active", "entries"]

    @extend_schema_field(
        {
            "type": "array",
            "items": {
                "type": "object",
                "properties": {
                    "effect_id": {"type": "integer"},
                    "weight": {"type": "integer"},
                },
            },
        }
    )
    def get_entries(self, obj):
        return list(obj.entries.values("effect_id", "weight"))
