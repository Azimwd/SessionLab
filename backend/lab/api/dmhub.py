"""Read-only, campaign-scoped feed for the opt-in DMHub desktop bridge."""
import hashlib
import hmac
import secrets

from django.db import transaction
from django.db.models import Max
from django.http import JsonResponse
from django.views.decorators.cache import never_cache
from django.views.decorators.http import require_GET
from drf_spectacular.types import OpenApiTypes
from drf_spectacular.utils import extend_schema
from rest_framework.exceptions import ValidationError
from rest_framework.response import Response
from rest_framework.views import APIView

from lab.models import AuditLog, Campaign, DMHubBridge, RoomEvent
from .common import campaign_for
from .dmhub_cards import result_card


def bridge_hash(token):
    return hashlib.sha256(token.encode("ascii")).hexdigest()


class BridgeSettings(APIView):
    @extend_schema(responses=OpenApiTypes.OBJECT)
    def get(self, request):
        campaign = campaign_for(request, dm=True)
        bridge = DMHubBridge.objects.filter(campaign=campaign).first()
        return Response({"enabled": bool(bridge and bridge.enabled), "campaign": campaign.pk})

    @extend_schema(request=OpenApiTypes.OBJECT, responses=OpenApiTypes.OBJECT)
    def post(self, request):
        if request.data.get("action") not in ("rotate", "revoke"):
            raise ValidationError("Действие: rotate или revoke")
        with transaction.atomic():
            campaign = campaign_for(request, dm=True, lock=True)
            if request.data["action"] == "rotate":
                token = secrets.token_urlsafe(48)
                DMHubBridge.objects.update_or_create(
                    campaign=campaign,
                    defaults={"token_hash": bridge_hash(token), "enabled": True},
                )
                result = {"enabled": True, "token": token, "campaign": campaign.pk}
            else:
                DMHubBridge.objects.filter(campaign=campaign).update(enabled=False)
                result = {"enabled": False, "campaign": campaign.pk}
            AuditLog.objects.create(
                campaign=campaign, actor=request.user,
                action="dmhub bridge " + request.data["action"], details={},
            )
        # The bearer is shown exactly once and is never written into audit/idempotency logs.
        return Response(result)


def _line(event):
    p = event.payload
    def clean(value, limit):
        return " ".join(str(value).split())[:limit]

    who = clean(p.get("character_name") or "Мастер", 100)
    label = clean(p.get("label") or "Бросок", 120)
    display = {"primary": None, "secondary": None, "detail": ""}
    if event.kind == "roll":
        result = p.get("roll") or {}
        text = f"{who}: {label} — {result.get('total', '?')}"
        display["primary"] = {"label": "Бросок", "value": result.get("total", "?")}
        if result.get("formula"):
            text += f" ({result['formula']})"
            display["detail"] = clean(result["formula"], 100)
    else:
        level = p.get("slot_level")
        level_text = f", ячейка {level}" if p.get("kind") == "spell" and level else ""
        parts = p.get("parts") or [p]
        details = []
        for part in parts:
            fragments = []
            if part.get("roll"):
                fragments.append(f"атака {part['roll'].get('total', '?')}")
            if part.get("damage"):
                damage_type = clean(p.get("damage_type") or "результат", 50)
                fragments.append(f"{damage_type} {part['damage'].get('total', '?')}")
            if part.get("save"):
                save = part["save"]
                fragments.append(f"спасбросок {save.get('ability', '?').upper()} СЛ {save.get('dc', '?')}")
                if "failed_damage" in save:
                    fragments.append(f"провал {save['failed_damage']}, успех {save.get('success_damage', 0)}")
            details.append(", ".join(fragments))
        if not any(details) and p.get("description"):
            # Keep chat messages compact, but let the DMHub panel show the
            # entire public action description in its scrollable card.
            display["description"] = clean(p["description"], 10000)
            details = [display["description"][:220]]
        text = f"{who}: {label}{level_text}" + (" — " + "; ".join(filter(None, details)) if any(details) else "")
        first = parts[0] if parts else {}
        if first.get("roll"):
            display["primary"] = {"label": "Атака", "value": first["roll"].get("total", "?")}
        if first.get("damage"):
            damage = {"label": "Урон", "value": first["damage"].get("total", "?")}
            display["secondary" if display["primary"] else "primary"] = damage
        if first.get("save"):
            save = first["save"]
            dc = {"label": "СЛ спасброска", "value": save.get("dc", "?")}
            display["secondary" if display["primary"] else "primary"] = dc
            if "failed_damage" in save:
                display["detail"] = (
                    f"Провал {save['failed_damage']} · успех {save.get('success_damage', 0)}"
                )
        if len(parts) > 1:
            display["detail"] = f"{len(parts)} бросков · всего урона {p.get('total_damage', '?')}"
        elif level_text:
            display["detail"] = f"Ячейка {level}" + (
                f" · {display['detail']}" if display["detail"] else ""
            )
    # Structured presentation lets the DMHub mod create a titled message while
    # retaining `text` for older bridge versions. Never expose the raw payload.
    summary = text.split(" — ", 1)[1] if " — " in text else ""
    if event.kind == "ability" and p.get("kind") == "spell" and p.get("slot_level"):
        summary = f"Ячейка {p['slot_level']} · {summary}".rstrip(" ·")
    return {
        "id": event.pk, "session": event.session_id, "text": text[:900],
        "actor": who, "title": label, "kind": event.kind,
        "summary": summary[:700], "display": display, "card": result_card(event),
    }


@require_GET
@never_cache
def bridge_events(request):
    header = request.headers.get("Authorization", "")
    scheme, _, token = header.partition(" ")
    if scheme.lower() != "bearer" or not 32 <= len(token) <= 128 or not token.isascii():
        return JsonResponse({"data": None, "error": "Недействительный ключ моста"}, status=401)
    digest = bridge_hash(token)
    # Hash comparison is constant time; an indexed token is never exposed to the browser.
    bridge = DMHubBridge.objects.select_related("campaign").filter(token_hash=digest, enabled=True).first()
    if bridge is None or not hmac.compare_digest(bridge.token_hash, digest):
        return JsonResponse({"data": None, "error": "Недействительный ключ моста"}, status=401)
    events = RoomEvent.objects.filter(
        campaign_id=bridge.campaign_id, visibility="public", kind__in=("roll", "ability")
    )
    latest = events.aggregate(value=Max("id"))["value"] or 0
    cursor_param = request.GET.get("cursor", "latest")
    if cursor_param == "latest":
        return JsonResponse({"data": {"events": [], "cursor": latest}, "error": None})
    try:
        cursor = int(cursor_param)
        if not 0 <= cursor <= 9223372036854775807:
            raise ValueError
    except ValueError:
        return JsonResponse({"data": None, "error": "Некорректный курсор"}, status=400)
    rows = list(events.filter(id__gt=cursor).order_by("id")[:50])
    return JsonResponse({"data": {
        "events": [_line(row) for row in rows],
        "cursor": rows[-1].id if rows else cursor,
    }, "error": None})
