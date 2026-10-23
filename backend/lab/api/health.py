from django.db import connection, DatabaseError
from django.http import JsonResponse
from django.views.decorators.http import require_GET


@require_GET
def health(request):
    """Readiness probe: no authentication, session creation or user rate quota."""
    try:
        with connection.cursor() as cursor:
            cursor.execute("SELECT 1")
            cursor.fetchone()
    except DatabaseError:
        return JsonResponse({"data": None, "error": {"detail": "Unavailable"}}, status=503)
    return JsonResponse({"data": {"status": "ok"}, "error": None})
