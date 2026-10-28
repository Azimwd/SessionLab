import hashlib, json
from django.db import transaction
from django.core.serializers.json import DjangoJSONEncoder
from rest_framework.authentication import SessionAuthentication
from rest_framework.exceptions import ValidationError, PermissionDenied, NotFound
from rest_framework.renderers import JSONRenderer
from rest_framework.response import Response
from lab.models import Campaign, Membership, IdempotencyRecord, AuditLog


class CsrfSessionAuthentication(SessionAuthentication):
    def authenticate(self, request):
        # Enforce for anonymous login/registration too, avoiding DRF's anonymous exemption.
        self.enforce_csrf(request)
        return super().authenticate(request)


class EnvelopeRenderer(JSONRenderer):
    def render(self, data, accepted_media_type=None, renderer_context=None):
        response = (renderer_context or {}).get("response")
        if response and response.status_code >= 400:
            data = {"data": None, "error": data}
        else:
            data = {"data": data, "error": None}
        return super().render(data, accepted_media_type, renderer_context)


def exception_handler(exc, context):
    from rest_framework.views import exception_handler as drf_exception_handler
    from django.core.exceptions import ValidationError as DjangoValidationError
    from django.db import IntegrityError

    if isinstance(exc, DjangoValidationError):
        exc = ValidationError(exc.messages)
    if isinstance(exc, IntegrityError):
        exc = ValidationError("Операция нарушает ограничение данных")
    return drf_exception_handler(exc, context)


def campaign_for(request, pk=None, dm=False, lock=False):
    pk = pk or request.query_params.get("campaign") or request.data.get("campaign")
    try:
        campaign = (
            Campaign.objects.select_for_update() if lock else Campaign.objects
        ).get(pk=int(pk), deleted_at__isnull=True)
    except (Campaign.DoesNotExist, ValueError, TypeError):
        raise NotFound("Кампания не найдена")
    member = Membership.objects.filter(
        campaign=campaign, user=request.user, active=True
    ).first()
    if not member or (dm and (member.role != "dm" or request.user.account_role != 'dm')):
        raise PermissionDenied("Недостаточно прав в этой кампании")
    return campaign


def is_dm(campaign, user):
    return user.account_role == 'dm' and Membership.objects.filter(
        campaign=campaign, user=user, active=True, role="dm"
    ).exists()


def mutate(request, campaign_id, operation, dm=False):
    if not isinstance(request.data, dict):
        raise ValidationError("Тело запроса должно быть JSON-объектом")
    key = request.headers.get("Idempotency-Key", "")
    if not 8 <= len(key) <= 100:
        raise ValidationError("Нужен Idempotency-Key длиной 8–100 символов")
    fingerprint = hashlib.sha256(
        json.dumps(
            {"path": request.path, "method": request.method, "data": request.data},
            sort_keys=True,
            default=str,
        ).encode()
    ).hexdigest()
    with transaction.atomic():
        campaign = campaign_for(request, campaign_id, dm=dm, lock=True)
        record = IdempotencyRecord.objects.filter(
            user=request.user, campaign=campaign, key=key
        ).first()
        if record:
            if record.fingerprint != fingerprint:
                raise ValidationError("Этот ключ уже использован для другого запроса")
            return Response(record.response)
        data = operation(campaign)
        data = json.loads(json.dumps(data, cls=DjangoJSONEncoder))
        IdempotencyRecord.objects.create(
            user=request.user,
            campaign=campaign,
            key=key,
            fingerprint=fingerprint,
            response=data,
        )
        AuditLog.objects.create(
            campaign=campaign,
            actor=request.user,
            action=f"{request.method} {request.path}",
            details={"key": key},
        )
        return Response(data)


def clean_snapshot(data, dm=False):
    if isinstance(data, dict):
        return {
            k: clean_snapshot(v, dm) for k, v in data.items() if dm or k != "secret"
        }
    if isinstance(data, list):
        return [clean_snapshot(v, dm) for v in data]
    return data
