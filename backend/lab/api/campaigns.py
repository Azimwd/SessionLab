from django.utils import timezone
from django.db import transaction
from django.db.models import Q
from django.shortcuts import get_object_or_404
from rest_framework import viewsets
from rest_framework.decorators import action
from rest_framework.response import Response
from rest_framework.exceptions import ValidationError, PermissionDenied
from drf_spectacular.utils import extend_schema
from drf_spectacular.types import OpenApiTypes
from lab.models import *
from lab.services.casino import ensure_configs, wallet_for
from lab.services.effects import finish_session
from .serializers import *
from .common import *


def number(value):
    try:
        if (
            type(value) not in [str, int]
            or isinstance(value, str)
            and not value.isdigit()
        ):
            raise ValueError()
        n = int(value)
        if n < 1:
            raise ValueError()
        return n
    except (TypeError, ValueError):
        raise ValidationError("Ожидается положительный ID")


def own_character(request, campaign, pk, dm=False):
    character = get_object_or_404(
        Character, pk=number(pk), campaign=campaign, active=True
    )
    if character.owner_id != request.user.pk and not dm:
        raise PermissionDenied("Это чужой персонаж")
    return character


class CampaignViewSet(viewsets.ModelViewSet):
    serializer_class = CampaignSerializer
    http_method_names = ["get", "post", "patch", "delete", "head", "options"]
    search_fields = ["name"]
    ordering_fields = ["name", "created_at"]

    def get_queryset(self):
        if getattr(self, "swagger_fake_view", False):
            return Campaign.objects.none()
        return Campaign.objects.filter(
            memberships__user=self.request.user, memberships__active=True, deleted_at__isnull=True
        ).order_by("-created_at")

    def perform_create(self, serializer):
        if self.request.user.account_role != 'dm':
            raise PermissionDenied('Создавать кампании может аккаунт мастера')
        with transaction.atomic():
            campaign = serializer.save(owner=self.request.user)
            Membership.objects.create(
                campaign=campaign, user=self.request.user, role="dm"
            )
            ensure_configs(campaign)
            wallet_for(campaign, self.request.user)

    def partial_update(self, request, *args, **kwargs):
        def op(c):
            form = self.get_serializer(c, data=request.data, partial=True)
            form.is_valid(raise_exception=True)
            form.save()
            return form.data

        return mutate(request, kwargs["pk"], op, True)

    def destroy(self, request, *args, **kwargs):
        # Keep protected historical records; revoke every entry point atomically.
        # Repeated DELETE by the owner is safe even after membership revocation.
        if not isinstance(request.data, dict):
            raise ValidationError("Ожидается JSON-объект")
        with transaction.atomic():
            campaign = get_object_or_404(Campaign.objects.select_for_update(), pk=kwargs["pk"])
            if campaign.owner_id != request.user.pk:
                raise PermissionDenied("Удалить кампанию может только её владелец")
            if request.data.get("confirm_name") != campaign.name:
                raise ValidationError("Для удаления введите точное название кампании")
            if campaign.deleted_at is None:
                campaign.deleted_at = timezone.now()
                campaign.save(update_fields=["deleted_at", "updated_at"])
                Membership.objects.filter(campaign=campaign).update(active=False)
                DMHubBridge.objects.filter(campaign=campaign).update(enabled=False)
                DMHubSheetAccess.objects.filter(campaign=campaign).update(enabled=False)
                AuditLog.objects.create(campaign=campaign, actor=request.user,
                                        action="campaign.delete", details={})
            return Response({"id": campaign.pk, "deleted": True})

    @action(detail=False, methods=["post"], url_path="join")
    @extend_schema(request=OpenApiTypes.OBJECT, responses=CampaignSerializer)
    def join(self, request):
        code = request.data.get("code", "")
        with transaction.atomic():
            campaign = get_object_or_404(
                Campaign.objects.select_for_update(), invite_code=code, deleted_at__isnull=True
            )
            member, created = Membership.objects.get_or_create(
                campaign=campaign, user=request.user
            )
            if not created and not member.active:
                raise PermissionDenied("Доступ отключён мастером")
            wallet_for(campaign, request.user)
            AuditLog.objects.create(
                campaign=campaign,
                actor=request.user,
                action="membership.join",
                details={},
            )
        return Response(self.get_serializer(campaign).data)

    @action(detail=True, methods=["get"])
    def members(self, request, pk=None):
        campaign = campaign_for(request, pk)
        return Response(
            list(
                Membership.objects.filter(campaign=campaign).values(
                    "id", "user_id", "user__first_name", "user__email", "role", "active"
                )
            )
            if is_dm(campaign, request.user)
            else list(
                Membership.objects.filter(campaign=campaign, active=True).values(
                    "id", "user_id", "user__first_name", "role"
                )
            )
        )

    @action(detail=True, methods=["get", "post"])
    @extend_schema(request=SessionSerializer, responses=SessionSerializer(many=True))
    def sessions(self, request, pk=None):
        if request.method == "GET":
            return Response(
                SessionSerializer(
                    GameSession.objects.filter(
                        campaign=campaign_for(request, pk)
                    ).order_by("-created_at"),
                    many=True,
                ).data
            )

        def op(c):
            form = SessionSerializer(data=request.data)
            form.is_valid(raise_exception=True)
            form.save(campaign=c)
            return form.data

        return mutate(request, pk, op, True)


class CharacterViewSet(viewsets.ModelViewSet):
    serializer_class = CharacterSerializer
    http_method_names = ["get", "post", "patch", "delete", "head", "options"]
    search_fields = ["name", "character_class"]
    ordering_fields = ["name", "level"]

    def get_queryset(self):
        if getattr(self, "swagger_fake_view", False):
            return Character.objects.none()
        campaign = campaign_for(self.request)
        qs = Character.objects.filter(campaign=campaign, active=True)
        if not is_dm(campaign, self.request.user):
            # Public table cards come from RoomView after folder/leaf checks.
            # Full character metadata remains private to its owner and masters.
            qs = qs.filter(kind='player', owner=self.request.user)
        return qs.order_by('name')

    def create(self, request, *args, **kwargs):
        def op(c):
            form = self.get_serializer(data=request.data)
            form.is_valid(raise_exception=True)
            if form.validated_data.get('kind') == 'npc' and not is_dm(c, request.user):
                raise PermissionDenied('Создавать NPC может только мастер')
            validate_character_folder(form.validated_data.get('folder'), c, request.user)
            form.save(campaign=c, owner=request.user)
            return form.data

        return mutate(request, request.data.get("campaign"), op)

    def partial_update(self, request, *args, **kwargs):
        def op(c):
            obj = own_character(request, c, kwargs["pk"], is_dm(c, request.user))
            if 'kind' in request.data and request.data['kind'] != obj.kind:
                raise ValidationError('Тип участника нельзя изменить')
            form = self.get_serializer(obj, data=request.data, partial=True)
            form.is_valid(raise_exception=True)
            validate_character_folder(form.validated_data.get('folder', obj.folder), c, request.user, obj)
            form.save()
            return form.data

        return mutate(request, request.query_params.get("campaign"), op)

    def destroy(self, request, *args, **kwargs):
        def op(c):
            obj = own_character(request, c, kwargs['pk'], is_dm(c, request.user))
            if InitiativeEntry.objects.filter(character=obj, tracker__running=True).exists():
                raise ValidationError('Сначала завершите бой с этим персонажем')
            obj.active = False
            obj.save(update_fields=['active', 'updated_at'])
            return {'id': obj.pk, 'archived': True}
        return mutate(request, request.query_params.get('campaign'), op)


def validate_character_folder(folder, campaign, user, character=None):
    if folder is None:
        return
    if folder.campaign_id != campaign.pk or (not folder.is_system and folder.owner_id != user.pk and not is_dm(campaign, user) and (not character or character.folder_id != folder.pk)):
        raise PermissionDenied('Папка недоступна в этой кампании')


class CharacterFolderViewSet(viewsets.ModelViewSet):
    serializer_class = CharacterFolderSerializer
    http_method_names = ['get', 'post', 'patch', 'delete', 'head', 'options']

    def get_queryset(self):
        if getattr(self, 'swagger_fake_view', False):
            return CharacterFolder.objects.none()
        c = campaign_for(self.request)
        qs = CharacterFolder.objects.filter(campaign=c)
        return qs if is_dm(c, self.request.user) else qs.filter(
            Q(is_system=True) | Q(owner=self.request.user) | Q(characters__owner=self.request.user, characters__active=True, characters__kind='player')
        ).distinct()

    def create(self, request, *args, **kwargs):
        def op(c):
            form = self.get_serializer(data=request.data)
            form.is_valid(raise_exception=True)
            if form.validated_data['name'].strip().casefold() == 'игроки':
                raise ValidationError('Папка «Игроки» создаётся автоматически')
            form.save(campaign=c, owner=request.user)
            return form.data
        return mutate(request, request.query_params.get('campaign'), op)

    def partial_update(self, request, *args, **kwargs):
        def op(c):
            folder = get_object_or_404(CharacterFolder, pk=kwargs['pk'], campaign=c, owner=request.user)
            if folder.is_system:
                raise ValidationError('Системную папку «Игроки» нельзя переименовать')
            form = self.get_serializer(folder, data=request.data, partial=True)
            form.is_valid(raise_exception=True)
            if form.validated_data.get('name', '').strip().casefold() == 'игроки':
                raise ValidationError('Название «Игроки» зарезервировано')
            form.save()
            return form.data
        return mutate(request, request.query_params.get('campaign'), op)

    def destroy(self, request, *args, **kwargs):
        def op(c):
            folder = get_object_or_404(CharacterFolder, pk=kwargs['pk'], campaign=c, owner=request.user)
            if folder.is_system:
                raise ValidationError('Системную папку «Игроки» нельзя удалить')
            pk = folder.pk
            folder.delete()
            return {'id': pk, 'deleted': True}
        return mutate(request, request.query_params.get('campaign'), op)


class SessionViewSet(viewsets.GenericViewSet):
    serializer_class = SessionSerializer
    queryset = GameSession.objects.none()

    @extend_schema(request=SessionSerializer, responses=SessionSerializer)
    def partial_update(self, request, *args, **kwargs):
        def op(c):
            obj = get_object_or_404(GameSession, pk=kwargs["pk"], campaign=c)
            if obj.status == "completed":
                raise ValidationError("Завершённая сессия неизменяема")
            form = SessionSerializer(obj, data=request.data, partial=True)
            form.is_valid(raise_exception=True)
            form.save()
            return form.data

        return mutate(request, request.query_params.get("campaign"), op, True)

    @action(detail=True, methods=["post"])
    @extend_schema(request=None, responses=SessionSerializer)
    def start(self, request, pk=None):
        return self.transition(request, pk, "active")

    @action(detail=True, methods=["post"])
    @extend_schema(request=None, responses=SessionSerializer)
    def finish(self, request, pk=None):
        return self.transition(request, pk, "completed")

    def transition(self, request, pk, status):
        def op(c):
            obj = get_object_or_404(GameSession, pk=pk, campaign=c)
            if status == "active":
                if (
                    obj.status != "planned"
                    or GameSession.objects.filter(campaign=c, status="active").exists()
                ):
                    raise ValidationError("Нельзя запустить эту сессию")
                obj.status = "active"
                obj.save()
            else:
                if obj.status != "active":
                    raise ValidationError("Сессия не активна")
                finish_session(obj)
            return SessionSerializer(obj).data

        return mutate(request, request.query_params.get("campaign"), op, True)
