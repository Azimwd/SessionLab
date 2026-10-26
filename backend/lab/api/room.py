import json
import time

from django.contrib.sessions.models import Session
from django.db import close_old_connections
from django.http import JsonResponse, StreamingHttpResponse
from django.shortcuts import get_object_or_404
from django.utils import timezone
from django.views.decorators.http import require_GET
from drf_spectacular.types import OpenApiTypes
from drf_spectacular.utils import extend_schema
from rest_framework.exceptions import ValidationError
from rest_framework.pagination import PageNumberPagination
from rest_framework.response import Response
from rest_framework.views import APIView

from lab.models import (
    AuditLog,
    Character,
    CharacterSheet,
    InitiativeEntry,
    InitiativeTracker,
    Membership,
    RoomEvent,
)
from lab.services.sheets import (
    active_session,
    computed,
    controlled_character,
    sheet_for,
    event,
)
from lab.services.dice import d20

from .common import campaign_for, is_dm, mutate
from .sheets import EventSerializer, require_version


def tracker_data(tracker, dm=False):
    if not tracker:
        return {
            "version": 0,
            "running": False,
            "round_number": 0,
            "current": None,
            "entries": [],
        }
    entries = tracker.entries.select_related("character")
    if not dm:
        entries = entries.filter(hidden=False)
    rows = [
        {
            "id": e.id,
            "character": e.character_id,
            "kind": e.character.kind if e.character_id else 'npc',
            "name": e.name,
            "initiative": e.initiative,
            "hidden": e.hidden,
        }
        for e in entries
    ]
    visible = any(e["id"] == tracker.current_id for e in rows)
    return {
        "version": tracker.version,
        "running": tracker.running,
        "round_number": tracker.round_number,
        "current": tracker.current_id if visible else None,
        "hidden_turn": bool(tracker.running and not visible),
        "entries": rows,
    }


def revision(campaign_id):
    return (
        AuditLog.objects.filter(campaign_id=campaign_id)
        .order_by("-id")
        .values_list("id", flat=True)
        .first()
        or 0
    )


class RoomView(APIView):
    @extend_schema(responses=OpenApiTypes.OBJECT)
    def get(self, request):
        c = campaign_for(request)
        dm = is_dm(c, request.user) and request.query_params.get("view") != "player"
        s = c.sessions.filter(status="active").first()
        party = []
        npcs = []
        own_characters = []
        for char in (
            Character.objects.filter(
                campaign=c,
                active=True,
                owner__membership__campaign=c,
                owner__membership__active=True,
            )
            .select_related("sheet", "owner", "folder")
            .order_by("name")
        ):
            try:
                sh = char.sheet
            except CharacterSheet.DoesNotExist:
                sh = None
            if char.kind == 'player' and char.owner_id == request.user.id:
                own_characters.append({'id': char.id, 'name': char.name, 'owner': char.owner_id})
            if not dm and (not c.table_visible_to_players or not char.table_visible):
                continue
            details = {
                'kind': char.kind,
                'folder': char.folder_id,
                'table_visible': char.table_visible,
                'speed': sh.speed if sh else 30,
                'initiative': computed(sh)['initiative'] if sh else 0,
                'abilities': sh.abilities if sh else {},
            } if dm else {}
            (npcs if char.kind == 'npc' else party).append(
                {
                    "id": char.id,
                    "name": char.name,
                    "owner": char.owner_id,
                    "owner_name": char.owner.first_name or "Участник",
                    "character_class": char.character_class,
                    "level": char.level,
                    "hp_current": sh.hp_current if sh else 10,
                    "hp_max": sh.hp_max if sh else 10,
                    "hp_temp": sh.hp_temp if sh else 0,
                    "armor_class": sh.armor_class if sh else 10,
                    "conditions": sh.conditions if sh else [],
                    **details,
                }
            )
        tracker = InitiativeTracker.objects.filter(session=s).first() if s else None
        return Response(
            {
                "revision": revision(c.id),
                "session": {"id": s.id, "name": s.name} if s else None,
                "party": party,
                "npcs": npcs if dm else [],
                "own_characters": own_characters,
                "table_visible_to_players": c.table_visible_to_players,
                "initiative": tracker_data(tracker, dm),
                "role": "dm" if is_dm(c, request.user) else "player",
            }
        )


class RoomTableVisibility(APIView):
    @extend_schema(request=OpenApiTypes.OBJECT, responses=OpenApiTypes.OBJECT)
    def post(self, request):
        def op(c):
            visible = request.data.get('visible')
            if type(visible) is not bool:
                raise ValidationError('visible: boolean')
            scope = request.data.get('scope')
            if scope == 'table':
                c.table_visible_to_players = visible
                c.save(update_fields=['table_visible_to_players', 'updated_at'])
                return {'scope': 'table', 'visible': visible}
            if scope == 'character':
                pk = request.data.get('character')
                if type(pk) is not int:
                    raise ValidationError('Укажите персонажа')
                char = get_object_or_404(Character, pk=pk, campaign=c, active=True)
                char.table_visible = visible
                char.save(update_fields=['table_visible', 'updated_at'])
                return {'scope': 'character', 'character': char.id, 'visible': visible}
            raise ValidationError('Неизвестная настройка стола')

        return mutate(request, None, op, dm=True)


class RoomEvents(APIView):
    @extend_schema(responses=EventSerializer(many=True))
    def get(self, request):
        c = campaign_for(request)
        qs = (
            RoomEvent.objects.filter(campaign=c).select_related("actor").order_by("-id")
        )
        if request.query_params.get("session"):
            try:
                sid = int(request.query_params["session"])
            except (ValueError, TypeError):
                raise ValidationError("Некорректная сессия")
            qs = qs.filter(session_id=sid)
        if not is_dm(c, request.user) or request.query_params.get("view") == "player":
            qs = qs.filter(visibility="public")
        paginator = PageNumberPagination()
        rows = paginator.paginate_queryset(qs, request)
        return paginator.get_paginated_response(EventSerializer(rows, many=True).data)


class InitiativeView(APIView):
    @extend_schema(request=OpenApiTypes.OBJECT, responses=OpenApiTypes.OBJECT)
    def post(self, request):
        def op(c):
            s = active_session(c)
            tracker, _ = InitiativeTracker.objects.get_or_create(session=s)
            # The initial empty state has version 0; accept it only for a new tracker.
            expected = request.data.get("version")
            if (
                expected == 0
                and tracker.version == 1
                and not tracker.entries.exists()
                and not tracker.running
            ):
                expected = 1
            require_version(tracker, {"version": expected})
            verb = request.data.get("action")
            if verb in ["add", "edit", "remove"]:
                if tracker.running and (verb != 'edit' or 'initiative' in request.data or 'hidden' in request.data):
                    raise ValidationError(
                        "Остановите трекер перед изменением порядка участников"
                    )
                if verb == "add":
                    if tracker.entries.count() >= 100:
                        raise ValidationError("Лимит: 100 участников")
                    char = None
                    if request.data.get("character"):
                        char = controlled_character(
                            c, request.user, request.data["character"]
                        )
                        if char.kind == 'player' and tracker.entries.filter(player_slot=char).exists():
                            raise ValidationError('Персонаж уже в инициативе')
                    name = char.name if char else request.data.get("name", "")
                    if not isinstance(name, str) or not 1 <= len(name.strip()) <= 100:
                        raise ValidationError("Укажите имя участника")
                    obj = InitiativeEntry(
                        tracker=tracker, character=char, player_slot=char if char and char.kind == 'player' else None, name=name.strip()
                    )
                else:
                    entry = request.data.get("entry")
                    if type(entry) is not int or entry < 1:
                        raise ValidationError("Некорректный участник")
                    obj = get_object_or_404(InitiativeEntry, pk=entry, tracker=tracker)
                if verb == "remove":
                    obj.delete()
                else:
                    if 'name' in request.data:
                        name = request.data['name']
                        if not isinstance(name, str) or not 1 <= len(name.strip()) <= 100:
                            raise ValidationError('Укажите имя участника')
                        obj.name = name.strip()
                    score = request.data.get("initiative", obj.initiative)
                    if type(score) is not int or not -100 <= score <= 100:
                        raise ValidationError("Инициатива: −100…100")
                    hidden = request.data.get("hidden", obj.hidden)
                    if type(hidden) is not bool:
                        raise ValidationError("hidden: boolean")
                    obj.initiative = score
                    obj.hidden = hidden
                    if obj.character:
                        obj.dexterity = computed(sheet_for(obj.character))["modifiers"][
                            "dex"
                        ]
                    obj.save()
            elif verb == "start":
                if tracker.running:
                    raise ValidationError("Трекер уже запущен")
                participants = request.data.get('participants', [])
                if not isinstance(participants, list) or len(participants) > 100:
                    raise ValidationError('Выберите не более 100 участников')
                if participants and tracker.round_number:
                    raise ValidationError('Для нового состава сначала сбросьте инициативу')
                planned = []
                for item in participants:
                    if not isinstance(item, dict) or type(item.get('count', 1)) is not int or not 1 <= item.get('count', 1) <= 20:
                        raise ValidationError('Количество экземпляров: 1–20')
                    count = item.get('count', 1)
                    if item.get('character') is not None:
                        char = controlled_character(c, request.user, item['character'])
                        if char.kind == 'player' and (count != 1 or tracker.entries.filter(player_slot=char).exists() or any(row[0] == char for row in planned)):
                            raise ValidationError('Персонаж игрока может участвовать только один раз')
                        sheet = sheet_for(char)
                        bonus = computed(sheet)['initiative']
                        dex = computed(sheet)['modifiers']['dex']
                        name = char.name
                    else:
                        char, dex = None, 0
                        name = item.get('name', '')
                        bonus = item.get('bonus', 0)
                        if not isinstance(name, str) or not 1 <= len(name.strip()) <= 100 or type(bonus) is not int or not -30 <= bonus <= 30:
                            raise ValidationError('Для временного участника укажите имя и бонус −30…30')
                        name = name.strip()
                    if len(planned) + count + tracker.entries.count() > 100:
                        raise ValidationError('Лимит: 100 участников')
                    for i in range(count):
                        planned.append((char, f'{name} {i + 1}' if count > 1 else name, bonus, dex))
                for char, name, bonus, dex in planned:
                    result = d20(bonus)
                    InitiativeEntry.objects.create(tracker=tracker, character=char, player_slot=char if char and char.kind == 'player' else None, name=name, initiative=result['total'], dexterity=dex)
                    event(c, s, request.user, char, 'roll', {'label': f'Инициатива · {name}', 'roll': result})
                first = tracker.entries.first()
                if not first:
                    raise ValidationError("Добавьте участников")
                if not tracker.entries.filter(pk=tracker.current_id).exists():
                    tracker.current = first
                tracker.round_number = max(1, tracker.round_number)
                tracker.running = True
            elif verb == "next":
                if not tracker.running:
                    raise ValidationError("Трекер не запущен")
                ids = list(tracker.entries.values_list("id", flat=True))
                if tracker.current_id not in ids:
                    raise ValidationError("Текущий участник отсутствует")
                idx = (ids.index(tracker.current_id) + 1) % len(ids)
                tracker.current_id = ids[idx]
                if idx == 0:
                    tracker.round_number += 1
            elif verb == "stop":
                tracker.running = False
            elif verb == "reset":
                tracker.current = None
                tracker.running = False
                tracker.round_number = 0
                tracker.entries.all().delete()
            else:
                raise ValidationError("Неизвестное действие инициативы")
            tracker.version += 1
            tracker.save()
            return tracker_data(tracker, True)

        return mutate(request, None, op, dm=True)


@require_GET
def room_stream(request, pk):
    """Commit-backed change notifications; data is fetched through permissioned REST.

    A bounded synchronous stream works with Django runserver and Gunicorn gthread.
    PostgreSQL is shared by workers; no process-local event bus or Redis required.
    """
    if (
        not request.user.is_authenticated
        or not Membership.objects.filter(
            campaign_id=pk, user=request.user, active=True
        ).exists()
    ):
        return JsonResponse(
            {"data": None, "error": {"detail": "Нет доступа к комнате"}}, status=403
        )
    user_id, session_key = request.user.pk, request.session.session_key
    try:
        last = int(request.headers.get("Last-Event-ID", request.GET.get("after", "-1")))
    except ValueError:
        last = -1

    def stream():
        nonlocal last
        try:
            yield "retry: 1500\n\n"
            for tick in range(25):
                close_old_connections()
                if (
                    not Session.objects.filter(
                        session_key=session_key, expire_date__gt=timezone.now()
                    ).exists()
                    or not Membership.objects.filter(
                        campaign_id=pk,
                        user_id=user_id,
                        active=True,
                        user__is_active=True,
                    ).exists()
                ):
                    yield "event: revoked\ndata: {}\n\n"
                    return
                current = revision(pk)
                if current != last:
                    last = current
                    yield f"id: {current}\nevent: change\ndata: {json.dumps({'revision': current})}\n\n"
                else:
                    yield ": heartbeat\n\n"
                time.sleep(1)
        finally:
            close_old_connections()

    response = StreamingHttpResponse(stream(), content_type="text/event-stream")
    response["Cache-Control"] = "no-cache, no-store"
    response["X-Accel-Buffering"] = "no"
    return response
