from django.db import transaction
from django.db.models import Q, Sum, Count
from django.shortcuts import get_object_or_404
from rest_framework import viewsets
from rest_framework.decorators import action
from rest_framework.views import APIView
from rest_framework.response import Response
from rest_framework.exceptions import ValidationError, PermissionDenied
from drf_spectacular.utils import extend_schema
from drf_spectacular.types import OpenApiTypes
from lab.models import *
from lab.services import effects, quests, casino
from lab.services.casino_math import statistics
from .common import *
from .serializers import *
from .campaigns import number, own_character


class EffectList(viewsets.ReadOnlyModelViewSet):
    serializer_class = EffectSerializer
    search_fields = ["title", "description"]
    ordering_fields = ["title", "category", "rarity"]
    filterset_fields = ["category", "rarity"]

    def get_queryset(self):
        if getattr(self, "swagger_fake_view", False):
            return self.serializer_class.Meta.model.objects.none()
        c = campaign_for(self.request)
        return EffectDefinition.objects.filter(
            Q(campaign=c) | Q(campaign=None), active=True, archived=False
        ).order_by("code")


class QuestList(viewsets.ReadOnlyModelViewSet):
    serializer_class = QuestSerializer
    search_fields = ["title", "description"]
    ordering_fields = ["title", "reward"]
    filterset_fields = ["category", "difficulty"]

    def get_queryset(self):
        if getattr(self, "swagger_fake_view", False):
            return self.serializer_class.Meta.model.objects.none()
        c = campaign_for(self.request)
        return QuestDefinition.objects.filter(
            Q(campaign=c) | Q(campaign=None), active=True, archived=False
        ).order_by("code")


class SessionPlay(APIView):
    @extend_schema(responses=OpenApiTypes.OBJECT)
    def get(self, request, pk, module):
        if module not in ["effects", "quests"]:
            raise NotFound("Раздел не найден")
        c = campaign_for(request)
        session = get_object_or_404(GameSession, pk=pk, campaign=c)
        if module == "effects":
            return Response(
                RollSerializer(
                    EffectRoll.objects.filter(
                        session=session, character__owner=request.user
                    )
                    .select_related("character")
                    .order_by("-pk"),
                    many=True,
                ).data
            )
        return Response(
            AssignmentSerializer(
                QuestAssignment.objects.filter(
                    session=session, character__owner=request.user
                )
                .select_related("character")
                .order_by("-pk"),
                many=True,
            ).data
        )

    @extend_schema(request=OpenApiTypes.OBJECT, responses=OpenApiTypes.OBJECT)
    def post(self, request, pk, module):
        if module not in ["effects", "quests"]:
            raise NotFound("Раздел не найден")

        def op(c):
            session = get_object_or_404(GameSession, pk=pk, campaign=c)
            char = own_character(request, c, request.data.get("character"))
            if module == "effects":
                return RollSerializer(effects.roll_effect(session, char)).data
            return AssignmentSerializer(quests.assign(session, char)).data

        return mutate(request, request.query_params.get("campaign"), op)


class RollAction(APIView):
    @extend_schema(request=OpenApiTypes.OBJECT, responses=RollSerializer)
    def post(self, request, pk, verb):
        def op(c):
            obj = get_object_or_404(
                EffectRoll, pk=pk, session__campaign=c, character__owner=request.user
            )
            if verb == "choose":
                obj = effects.choose(obj, request.data.get("index"))
            elif verb in ["use", "request-approval"]:
                obj = effects.use_effect(
                    obj,
                    str(request.data.get("note", ""))[:3000],
                    verb == "request-approval",
                )
            else:
                raise ValidationError("Неизвестное действие")
            return RollSerializer(obj).data

        return mutate(request, request.query_params.get("campaign"), op)


class QuestSubmit(APIView):
    @extend_schema(request=OpenApiTypes.OBJECT, responses=AssignmentSerializer)
    def post(self, request, pk):
        def op(c):
            obj = get_object_or_404(
                QuestAssignment,
                pk=pk,
                session__campaign=c,
                character__owner=request.user,
            )
            return AssignmentSerializer(
                quests.submit(obj, str(request.data.get("evidence", ""))[:3000])
            ).data

        return mutate(request, request.query_params.get("campaign"), op)


class History(APIView):
    @extend_schema(responses=OpenApiTypes.OBJECT)
    def get(self, request, module):
        c = campaign_for(request)
        from rest_framework.pagination import PageNumberPagination

        pager = PageNumberPagination()
        if module == "effects":
            qs = (
                EffectRoll.objects.filter(
                    session__campaign=c, character__owner=request.user
                )
                .select_related("character")
                .order_by("-pk")
            )
            ser = RollSerializer
        else:
            qs = (
                QuestAssignment.objects.filter(
                    session__campaign=c, character__owner=request.user
                )
                .select_related("character")
                .order_by("-pk")
            )
            ser = AssignmentSerializer
        if request.query_params.get("session"):
            qs = qs.filter(session_id=number(request.query_params["session"]))
        if request.query_params.get("character"):
            qs = qs.filter(character_id=number(request.query_params["character"]))
        data = pager.paginate_queryset(qs, request)
        return pager.get_paginated_response(ser(data, many=True).data)


class CasinoGames(APIView):
    @extend_schema(responses=OpenApiTypes.OBJECT)
    def get(self, request):
        c = campaign_for(request)
        configs = CasinoConfiguration.objects.filter(campaign=c).order_by("id")
        return Response(
            [
                {**ConfigSerializer(cfg).data, "math": statistics(cfg.game, cfg.rules)}
                for cfg in configs
            ]
        )


class WalletView(APIView):
    @extend_schema(responses=OpenApiTypes.OBJECT)
    def get(self, request):
        c = campaign_for(request)
        obj = get_object_or_404(Wallet, campaign=c, user=request.user)
        return Response({"id": obj.pk, "balance": str(obj.balance)})


class Transactions(viewsets.ReadOnlyModelViewSet):
    serializer_class = TransactionSerializer
    ordering_fields = ["created_at", "amount"]
    filterset_fields = ["kind"]

    def get_queryset(self):
        if getattr(self, "swagger_fake_view", False):
            return WalletTransaction.objects.none()
        return WalletTransaction.objects.filter(
            wallet__campaign=campaign_for(self.request), wallet__user=self.request.user
        ).order_by("-pk")


class RoundCreate(APIView):
    @extend_schema(request=OpenApiTypes.OBJECT, responses=OpenApiTypes.OBJECT)
    def post(self, request, game):
        return mutate(
            request,
            request.query_params.get("campaign"),
            lambda c: casino.create_round(c, request.user, game, dict(request.data)),
        )


class RoundAction(APIView):
    @extend_schema(request=OpenApiTypes.OBJECT, responses=OpenApiTypes.OBJECT)
    def post(self, request, pk):
        return mutate(
            request,
            request.query_params.get("campaign"),
            lambda c: casino.round_action(c, request.user, pk, request.data),
        )


class Rounds(APIView):
    @extend_schema(responses=OpenApiTypes.OBJECT)
    def get(self, request):
        c = campaign_for(request)
        qs = CasinoRound.objects.filter(campaign=c, user=request.user).order_by("-pk")
        if request.query_params.get("game"):
            qs = qs.filter(game=request.query_params["game"])
        if request.query_params.get("status") in ["active", "completed"]:
            qs = qs.filter(status=request.query_params["status"])
        from rest_framework.pagination import PageNumberPagination

        pager = PageNumberPagination()
        items = pager.paginate_queryset(qs, request)
        return pager.get_paginated_response([casino.public_round(r) for r in items])


class Stats(APIView):
    @extend_schema(responses=OpenApiTypes.OBJECT)
    def get(self, request):
        c = campaign_for(request)
        rows = list(
            CasinoRound.objects.filter(
                campaign=c, user=request.user, status="completed"
            )
            .values("game")
            .annotate(rounds=Count("id"), stakes=Sum("stake"), payouts=Sum("payout"))
        )
        for row in rows:
            row["profit"] = row["payouts"] - row["stakes"]
        return Response(rows)


class Feed(APIView):
    @extend_schema(responses=OpenApiTypes.OBJECT)
    def get(self, request):
        c = campaign_for(request)
        # Players see only their own audit entries; campaign master sees the entire feed.
        qs = AuditLog.objects.filter(campaign=c)
        if not is_dm(c, request.user):
            qs = qs.filter(actor=request.user)
        return Response(
            {
                "events": list(
                    qs.order_by("-pk").values(
                        "id", "action", "created_at", "actor__first_name"
                    )[:15]
                ),
                "achievements": list(
                    Achievement.objects.filter(campaign=c, user=request.user).values(
                        "code", "title", "created_at"
                    )
                ),
            }
        )


class ExchangeView(APIView):
    @extend_schema(responses=OpenApiTypes.OBJECT)
    def get(self, request):
        c = campaign_for(request)
        qs = EffectExchange.objects.filter(source__session__campaign=c)
        if not is_dm(c, request.user):
            qs = qs.filter(
                Q(source__character__owner=request.user) | Q(target__owner=request.user)
            )
        return Response(
            list(
                qs.values(
                    "id",
                    "source_id",
                    "offered_id",
                    "target_id",
                    "target__name",
                    "target__owner_id",
                    "requested_id",
                    "consented",
                    "status",
                )
            )
        )

    @extend_schema(request=OpenApiTypes.OBJECT, responses=OpenApiTypes.OBJECT)
    def post(self, request):
        def op(c):
            source = get_object_or_404(
                EffectRoll,
                pk=number(request.data.get("source")),
                session__campaign=c,
                character__owner=request.user,
            )
            offered = get_object_or_404(
                EffectRoll, pk=number(request.data.get("offered")), session__campaign=c
            )
            target = get_object_or_404(
                Character, pk=number(request.data.get("target")), campaign=c
            )
            requested = (
                get_object_or_404(
                    EffectRoll,
                    pk=number(request.data["requested"]),
                    session__campaign=c,
                )
                if request.data.get("requested")
                else None
            )
            e = effects.request_exchange(source, offered, target, requested)
            return {"id": e.pk, "status": e.status}

        return mutate(request, request.query_params.get("campaign"), op)


class ExchangeConsent(APIView):
    @extend_schema(request=OpenApiTypes.OBJECT, responses=OpenApiTypes.OBJECT)
    def post(self, request, pk):
        def op(c):
            obj = get_object_or_404(
                EffectExchange,
                pk=pk,
                source__session__campaign=c,
                target__owner=request.user,
            )
            if obj.status != "pending_consent" or obj.source.session.status != "active":
                raise ValidationError("Запрос недоступен")
            if request.data.get("accept") is True:
                obj.consented = True
                obj.status = "pending_approval"
                obj.save()
            elif request.data.get("accept") is False:
                obj.consented = True
                obj.status = "pending_approval"
                obj.save()
                effects.decide_exchange(obj, False)
            else:
                raise ValidationError("accept: boolean")
            return {"status": obj.status}

        return mutate(request, request.query_params.get("campaign"), op)
