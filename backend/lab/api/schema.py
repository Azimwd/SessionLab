from drf_spectacular.extensions import OpenApiAuthenticationExtension


class SessionAuthScheme(OpenApiAuthenticationExtension):
    target_class = "lab.api.common.CsrfSessionAuthentication"
    name = "SessionCookie"

    def get_security_definition(self, auto_schema):
        return {
            "type": "apiKey",
            "in": "cookie",
            "name": "sessionid",
            "description": "Django session; unsafe requests additionally require X-CSRFToken.",
        }


def envelope_hook(result, generator, request, public):
    """Document the actual JSON envelope and campaign/idempotency headers."""
    for path, operations in result.get("paths", {}).items():
        for method, op in operations.items():
            if method not in ["get", "post", "patch", "delete", "put"]:
                continue
            params = op.setdefault("parameters", [])
            if not path.startswith(("/api/auth/", "/api/campaigns/")) and path not in [
                "/api/schema/",
                "/api/docs/",
            ]:
                params.append(
                    {
                        "in": "query",
                        "name": "campaign",
                        "required": True,
                        "schema": {"type": "integer"},
                        "description": "Campaign ID, membership checked server-side.",
                    }
                )
            if method != "get":
                params.append(
                    {
                        "in": "header",
                        "name": "X-CSRFToken",
                        "required": True,
                        "schema": {"type": "string"},
                        "description": "Masked token from GET /api/auth/csrf/.",
                    }
                )
                if not path.startswith("/api/auth/") and path not in [
                    "/api/campaigns/",
                    "/api/campaigns/join/",
                ]:
                    params.append(
                        {
                            "in": "header",
                            "name": "Idempotency-Key",
                            "required": True,
                            "schema": {
                                "type": "string",
                                "minLength": 8,
                                "maxLength": 100,
                            },
                            "description": "Reuse the same key and payload after network failure; a different payload is rejected.",
                        }
                    )
            for code, response in op.get("responses", {}).items():
                content = response.get("content", {}).get("application/json")
                if content is not None:
                    original = content.get("schema", {})
                    content["schema"] = {
                        "type": "object",
                        "required": ["data", "error"],
                        "properties": {
                            "data": original
                            if str(code).startswith("2")
                            else {"nullable": True},
                            "error": {"nullable": True}
                            if str(code).startswith("2")
                            else original,
                        },
                    }
    result["paths"]["/api/campaigns/{id}/stream/"] = {
        "get": {
            "operationId": "campaigns_stream",
            "summary": "Committed room changes via Server-Sent Events",
            "description": "Authenticated campaign members only. Events: change with {revision}, revoked with {}. No private game content is streamed. Re-fetch scoped REST resources after change. Heartbeat every second; reconnect after the bounded stream ends.",
            "parameters": [
                {
                    "in": "path",
                    "name": "id",
                    "required": True,
                    "schema": {"type": "integer"},
                },
                {
                    "in": "header",
                    "name": "Last-Event-ID",
                    "required": False,
                    "schema": {"type": "integer"},
                },
            ],
            "security": [{"SessionCookie": []}],
            "responses": {
                "200": {
                    "description": "SSE event stream",
                    "content": {"text/event-stream": {"schema": {"type": "string"}}},
                },
                "403": {"description": "Session expired or campaign access denied"},
            },
        }
    }
    return result
