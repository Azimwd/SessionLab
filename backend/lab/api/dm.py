import csv, io, json, secrets
from decimal import Decimal, InvalidOperation
from django.db.models import Q, Count
from django.shortcuts import get_object_or_404
from rest_framework import viewsets
from rest_framework.decorators import action
from rest_framework.views import APIView
from rest_framework.response import Response
from rest_framework.exceptions import ValidationError
from drf_spectacular.utils import extend_schema
from drf_spectacular.types import OpenApiTypes
from lab.models import *
from lab.services import effects, quests, casino
from .serializers import *
from .common import *
from .campaigns import number, own_character


class ContentViewSet(viewsets.ModelViewSet):
    http_method_names = ["get", "post", "patch", "delete", "head", "options"]
    search_fields = ["title", "description"]
    ordering_fields = ["title", "created_at"]
    filterset_fields = ["category", "active", "archived"]

    def get_queryset(self):
        if getattr(self, "swagger_fake_view", False):
            return self.model.objects.none()
        c = campaign_for(self.request, dm=True)
        return self.model.objects.filter(Q(campaign=c) | Q(campaign=None)).order_by(
            "code"
        )

    def get_serializer_context(self):
        return {**super().get_serializer_context(), "dm": True}

    def create(self, request, *args, **kwargs):
        def op(c):
            payload = {**request.data, "code": "custom-" + secrets.token_hex(12)}
            form = self.get_serializer(data=payload)
            form.is_valid(raise_exception=True)
            form.save(campaign=c)
            return form.data

        return mutate(request, request.query_params.get("campaign"), op, True)

    def partial_update(self, request, *args, **kwargs):
        def op(c):
            obj = get_object_or_404(self.model, pk=kwargs["pk"], campaign=c)
            payload = dict(request.data)
            payload.pop("code", None)
            form = self.get_serializer(obj, data=payload, partial=True)
            form.is_valid(raise_exception=True)
            form.save()
            return form.data

        return mutate(request, request.query_params.get("campaign"), op, True)

    def destroy(self, request, *args, **kwargs):
        def op(c):
            obj = get_object_or_404(self.model, pk=kwargs["pk"], campaign=c)
            obj.archived = True
            obj.active = False
            obj.save()
            return {"archived": True}

        return mutate(request, request.query_params.get("campaign"), op, True)

    @action(detail=True, methods=["post"])
    @extend_schema(request=None, responses=OpenApiTypes.OBJECT)
    def copy(self, request, pk=None):
        def op(c):
            obj = get_object_or_404(self.model, Q(campaign=c) | Q(campaign=None), pk=pk)
            payload = self.get_serializer(obj).data
            for f in ["id", "campaign", "created_at", "updated_at"]:
                payload.pop(f, None)
            payload["code"] = "custom-" + secrets.token_hex(12)
            payload["title"] = payload["title"][:152] + " · копия"
            form = self.get_serializer(data=payload)
            form.is_valid(raise_exception=True)
            form.save(campaign=c)
            return form.data

        return mutate(request, request.query_params.get("campaign"), op, True)

    @action(detail=False, methods=["get"], url_path="export")
    def export_data(self, request):
        rows = self.get_serializer(self.get_queryset(), many=True).data
        if request.query_params.get("file_format") == "csv":
            out = io.StringIO()
            writer = csv.DictWriter(
                out, fieldnames=list(rows[0]) if rows else ["title"]
            )
            writer.writeheader()
            for row in rows:
                writer.writerow(
                    {
                        k: json.dumps(v, ensure_ascii=False)
                        if isinstance(v, (dict, list, bool)) or v is None
                        else v
                        for k, v in row.items()
                    }
                )
            return Response({"format": "csv", "content": out.getvalue()})
        return Response({"format": "json", "content": rows})

    @action(detail=False, methods=["post"], url_path="import")
    @extend_schema(request=OpenApiTypes.OBJECT, responses=OpenApiTypes.OBJECT)
    def import_data(self, request):
        def op(c):
            content = request.data.get("content")
            fmt = request.data.get("format", "json")
            if fmt == "csv":
                if not isinstance(content, str) or len(content) > 2000000:
                    raise ValidationError("CSV слишком большой")
                content = list(csv.DictReader(io.StringIO(content)))
                for row in content:
                    for key in [
                        "parameters",
                        "requires_approval",
                        "homebrew",
                        "active",
                        "archived",
                    ]:
                        if key in row:
                            try:
                                row[key] = json.loads(row[key])
                            except (ValueError, TypeError):
                                raise ValidationError(f"Некорректное CSV-поле {key}")
            if not isinstance(content, list) or len(content) > 500:
                raise ValidationError("Импорт: список до 500 объектов")
            imported = []
            for row in content:
                if not isinstance(row, dict):
                    raise ValidationError("Строка должна быть объектом")
                payload = dict(row)
                # Stable import keys are namespaced by campaign, so repeats update rather than duplicate.
                source = str(payload.get("code", ""))[:80] or secrets.token_hex(12)
                import hashlib

                code = (
                    source
                    if self.model.objects.filter(code=source, campaign=c).exists()
                    else "import-"
                    + str(c.pk)
                    + "-"
                    + hashlib.sha256(source.encode()).hexdigest()[:32]
                )
                for f in ["id", "campaign", "created_at", "updated_at"]:
                    payload.pop(f, None)
                payload["code"] = code
                obj = self.model.objects.filter(code=code, campaign=c).first()
                form = self.get_serializer(obj, data=payload)
                form.is_valid(raise_exception=True)
                form.save(campaign=c)
                imported.append(form.data)
            return {"imported": len(imported)}

        return mutate(request, request.query_params.get("campaign"), op, True)


class DMEffects(ContentViewSet):
    model = EffectDefinition
    serializer_class = EffectSerializer


class DMQuests(ContentViewSet):
    model = QuestDefinition
    serializer_class = QuestSerializer


class DMOverview(APIView):
    @extend_schema(responses=OpenApiTypes.OBJECT)
    def get(self, request):
        c = campaign_for(request, dm=True)
        return Response(
            {
                "members": list(
                    Membership.objects.filter(campaign=c).values(
                        "id",
                        "user_id",
                        "user__email",
                        "user__first_name",
                        "role",
                        "active",
                    )
                ),
                "wallets": list(
                    Wallet.objects.filter(campaign=c).values(
                        "id", "user_id", "user__first_name", "balance"
                    )
                ),
                "effects": RollSerializer(
                    EffectRoll.objects.filter(session__campaign=c)
                    .select_related("character")
                    .order_by("-pk")[:100],
                    many=True,
                    context={"dm": True},
                ).data,
                "quests": AssignmentSerializer(
                    QuestAssignment.objects.filter(session__campaign=c)
                    .select_related("character")
                    .order_by("-pk")[:100],
                    many=True,
                ).data,
                "approvals": list(
                    EffectApprovalRequest.objects.filter(
                        effect__session__campaign=c, status="pending"
                    ).values("id", "effect_id", "description")
                ),
                "exchanges": list(
                    EffectExchange.objects.filter(
                        source__session__campaign=c, status="pending_approval"
                    ).values(
                        "id", "source_id", "offered_id", "target__name", "requested_id"
                    )
                ),
                "content_stats": list(
                    EffectRoll.objects.filter(session__campaign=c)
                    .values("definition_id", "snapshot__title")
                    .annotate(count=Count("id"))
                    .order_by("-count")[:30]
                ),
            }
        )


class DMAction(APIView):
    @extend_schema(request=OpenApiTypes.OBJECT, responses=OpenApiTypes.OBJECT)
    def post(self, request, kind, pk):
        def op(c):
            body = request.data
            if kind in ["quest", "effect", "exchange"]:
                if type(body.get("approve")) is not bool:
                    raise ValidationError("approve: boolean")
                approved = body["approve"]
                note = str(body.get("note", ""))[:3000]
                if kind == "quest":
                    obj = get_object_or_404(QuestAssignment, pk=pk, session__campaign=c)
                    return AssignmentSerializer(
                        quests.decide(obj, request.user, approved, note)
                    ).data
                if kind == "effect":
                    obj = get_object_or_404(
                        EffectApprovalRequest, pk=pk, effect__session__campaign=c
                    )
                    return RollSerializer(
                        effects.decide_effect(obj, request.user, approved, note),
                        context={"dm": True},
                    ).data
                obj = get_object_or_404(
                    EffectExchange, pk=pk, source__session__campaign=c
                )
                effects.decide_exchange(obj, approved)
                return {"status": obj.status}
            if kind == "member":
                obj = get_object_or_404(Membership, pk=pk, campaign=c)
                if obj.user_id == c.owner_id:
                    raise ValidationError("Владелец сохраняет права мастера")
                if "role" in body:
                    if body["role"] not in ["dm", "player"]:
                        raise ValidationError("Неверная роль")
                    if body['role'] == 'dm' and obj.user.account_role != 'dm':
                        raise ValidationError('Аккаунт игрока нельзя назначить мастером')
                    obj.role = body["role"]
                if "active" in body:
                    if type(body["active"]) is not bool:
                        raise ValidationError("active: boolean")
                    if (
                        not body["active"]
                        and CasinoRound.objects.filter(
                            campaign=c, user=obj.user, status="active"
                        ).exists()
                    ):
                        raise ValidationError(
                            "Сначала завершите открытый карточный раунд"
                        )
                    obj.active = body["active"]
                obj.save()
                return {"role": obj.role, "active": obj.active}
            if kind == "wallet":
                obj = get_object_or_404(Wallet, pk=pk, campaign=c)
                try:
                    amount = Decimal(str(body.get("amount")))
                    if (
                        not amount.is_finite()
                        or abs(amount) > 1000000
                        or amount != casino.money(amount)
                        or amount == 0
                    ):
                        raise ValueError()
                except (InvalidOperation, ValueError, TypeError):
                    raise ValidationError("Укажите сумму ±1000000, до двух знаков")
                if not str(body.get("note", "")).strip():
                    raise ValidationError("Укажите причину корректировки")
                obj = casino.move(
                    obj,
                    amount,
                    "adjustment",
                    f"adjust:{c.pk}:{request.headers['Idempotency-Key']}",
                    actor=request.user,
                    note=str(body["note"])[:1000],
                )
                return {"balance": str(obj.balance)}
            if kind == "cancel-quest":
                obj = get_object_or_404(QuestAssignment, pk=pk, session__campaign=c)
                if obj.status == "completed":
                    raise ValidationError("Выполненное задание нельзя отменить")
                obj.status = "cancelled"
                obj.save()
                return AssignmentSerializer(obj).data
            if kind == "cancel-effect":
                obj = get_object_or_404(EffectRoll, pk=pk, session__campaign=c)
                if obj.status not in ["active", "rolled"]:
                    raise ValidationError("Эффект недоступен для отмены")
                obj.status = "cancelled"
                obj.save()
                return RollSerializer(obj, context={"dm": True}).data
            if kind in ["assign-effect", "assign-quest", "reroll"]:
                session = get_object_or_404(
                    GameSession, pk=number(body.get("session")), campaign=c
                )
                char = own_character(request, c, body.get("character"), True)
                if kind == "assign-quest":
                    definition = get_object_or_404(
                        QuestDefinition,
                        Q(campaign=c) | Q(campaign=None),
                        pk=pk,
                        active=True,
                        archived=False,
                    )
                    return AssignmentSerializer(
                        quests.assign(session, char, definition)
                    ).data
                definition = (
                    get_object_or_404(
                        EffectDefinition,
                        Q(campaign=c) | Q(campaign=None),
                        pk=pk,
                        active=True,
                        archived=False,
                    )
                    if kind == "assign-effect"
                    else None
                )
                return RollSerializer(
                    effects.roll_effect(session, char, definition, bonus=True),
                    context={"dm": True},
                ).data
            raise ValidationError("Неизвестная операция")

        return mutate(request, request.query_params.get("campaign"), op, True)


class DMConfig(APIView):
    @extend_schema(request=ConfigSerializer, responses=ConfigSerializer)
    def patch(self, request, game):
        def op(c):
            obj = get_object_or_404(CasinoConfiguration, campaign=c, game=game)
            form = ConfigSerializer(obj, data=request.data, partial=True)
            form.is_valid(raise_exception=True)
            form.save(version=obj.version + 1)
            return form.data

        return mutate(request, request.query_params.get("campaign"), op, True)


class DMPools(APIView):
    @extend_schema(responses=PoolSerializer(many=True))
    def get(self, request):
        return Response(
            PoolSerializer(
                EffectPool.objects.filter(campaign=campaign_for(request, dm=True)),
                many=True,
            ).data
        )

    @extend_schema(request=OpenApiTypes.OBJECT, responses=PoolSerializer)
    def post(self, request):
        def op(c):
            obj = (
                get_object_or_404(EffectPool, pk=number(request.data["id"]), campaign=c)
                if request.data.get("id")
                else EffectPool(campaign=c)
            )
            name = request.data.get("name", "Набор эффектов")
            if not isinstance(name, str) or not 1 <= len(name) <= 120:
                raise ValidationError("Название: 1–120 символов")
            obj.name = name
            obj.active = request.data.get("active", True)
            if type(obj.active) is not bool:
                raise ValidationError("active: boolean")
            obj.save()
            entries = request.data.get("entries", [])
            if not isinstance(entries, list) or len(entries) > 1000:
                raise ValidationError("Некорректный список")
            obj.entries.all().delete()
            seen = set()
            for row in entries:
                if not isinstance(row, dict):
                    raise ValidationError("Элемент должен быть объектом")
                effect = get_object_or_404(
                    EffectDefinition,
                    Q(campaign=c) | Q(campaign=None),
                    pk=number(row.get("effect_id")),
                )
                weight = row.get("weight", 100)
                if (
                    type(weight) is not int
                    or not 0 <= weight <= 1000000
                    or effect.pk in seen
                ):
                    raise ValidationError("Вес или дубликат карточки")
                seen.add(effect.pk)
                EffectPoolEntry.objects.create(pool=obj, effect=effect, weight=weight)
            return PoolSerializer(obj).data

        return mutate(request, request.query_params.get("campaign"), op, True)


class DMHistory(APIView):
    @extend_schema(responses=OpenApiTypes.OBJECT)
    def get(self, request, kind):
        c = campaign_for(request, dm=True)
        from rest_framework.pagination import PageNumberPagination

        pager = PageNumberPagination()
        if kind == "rounds":
            qs = CasinoRound.objects.filter(campaign=c).order_by("-pk")
            rows = pager.paginate_queryset(qs, request)
            return pager.get_paginated_response(
                [{**casino.public_round(r), "user": r.user_id} for r in rows]
            )
        if kind == "transactions":
            qs = WalletTransaction.objects.filter(wallet__campaign=c).order_by("-pk")
            rows = pager.paginate_queryset(qs, request)
            return pager.get_paginated_response(
                [
                    {
                        **TransactionSerializer(r).data,
                        "wallet": r.wallet_id,
                        "actor": r.actor_id,
                    }
                    for r in rows
                ]
            )
        qs = AuditLog.objects.filter(campaign=c).order_by("-pk")
        rows = pager.paginate_queryset(qs, request)
        return pager.get_paginated_response(
            [
                {
                    "id": r.pk,
                    "actor": r.actor_id,
                    "action": r.action,
                    "details": r.details,
                    "created_at": r.created_at,
                }
                for r in rows
            ]
        )
