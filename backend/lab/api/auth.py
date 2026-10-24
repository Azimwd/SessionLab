from django.contrib.auth import authenticate, login, logout
from django.contrib.auth.password_validation import validate_password
from django.middleware.csrf import get_token
from django.db import transaction
from rest_framework.views import APIView
from rest_framework.permissions import AllowAny
from rest_framework.response import Response
from rest_framework.exceptions import ValidationError
from drf_spectacular.utils import extend_schema, inline_serializer
from rest_framework import serializers
from lab.models import User
from .serializers import UserSerializer

Credentials = inline_serializer(
    name="Credentials",
    fields={
        "email": serializers.EmailField(max_length=254),
        "password": serializers.CharField(write_only=True, max_length=4096),
        "first_name": serializers.CharField(required=False, max_length=80),
        "account_role": serializers.ChoiceField(choices=['dm', 'player'], required=False),
    },
)


class CsrfView(APIView):
    permission_classes = [AllowAny]

    @extend_schema(responses={200: dict})
    def get(self, request):
        return Response({"csrfToken": get_token(request)})


class RegisterView(APIView):
    permission_classes = [AllowAny]

    @extend_schema(request=Credentials, responses=UserSerializer)
    def post(self, request):
        form = Credentials.__class__(data=request.data)
        form.is_valid(raise_exception=True)
        data = form.validated_data
        email = data["email"].strip().lower()
        import secrets

        user = User(
            email=email,
            username="u_" + secrets.token_hex(24),
            first_name=data.get("first_name", ""),
            account_role=data.get("account_role", "player"),
        )
        validate_password(data["password"], user)
        if User.objects.filter(email=email).exists():
            raise ValidationError("Этот email уже зарегистрирован")
        with transaction.atomic():
            user.set_password(data["password"])
            user.save()
        login(request, user, backend="django.contrib.auth.backends.ModelBackend")
        return Response(UserSerializer(user).data)


class LoginView(APIView):
    permission_classes = [AllowAny]

    @extend_schema(request=Credentials, responses=UserSerializer)
    def post(self, request):
        form = Credentials.__class__(data=request.data)
        form.is_valid(raise_exception=True)
        data = form.validated_data
        user = authenticate(
            request=request._request,
            username=data["email"].strip().lower(),
            password=data["password"],
        )
        if user is None:
            raise ValidationError(
                "Неверный email или пароль. После 5 ошибок вход временно блокируется."
            )
        login(request, user)
        return Response(UserSerializer(user).data)


class LogoutView(APIView):
    @extend_schema(request=None, responses=dict)
    def post(self, request):
        logout(request)
        return Response({"logged_out": True})


class MeView(APIView):
    @extend_schema(responses=UserSerializer)
    def get(self, request):
        return Response(UserSerializer(request.user).data)

    @extend_schema(request=UserSerializer, responses=UserSerializer)
    def patch(self, request):
        if set(request.data) - {"first_name", "theme", "reduced_motion"}:
            raise ValidationError("Эти поля нельзя изменить")
        form = UserSerializer(request.user, data=request.data, partial=True)
        form.is_valid(raise_exception=True)
        form.save()
        return Response(form.data)


def lockout_response(request, credentials=None, *args, **kwargs):
    from django.http import JsonResponse

    return JsonResponse(
        {
            "data": None,
            "error": {
                "detail": "Слишком много неудачных попыток. Повторите вход через час."
            },
        },
        status=429,
    )
