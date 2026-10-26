"""Private, database-backed avatars; no reliance on ephemeral container storage."""
from django.http import HttpResponse
from django.shortcuts import get_object_or_404
from django.utils import timezone
from rest_framework.parsers import MultiPartParser
from rest_framework.response import Response
from rest_framework.views import APIView
from rest_framework.exceptions import NotFound, PermissionDenied, ValidationError
from drf_spectacular.utils import extend_schema, inline_serializer
from rest_framework import serializers

from lab.models import Character
from .common import campaign_for, is_dm
from .campaigns import own_character
from .serializers import UserSerializer, CharacterSerializer


AvatarUpload = inline_serializer('AvatarUpload', fields={'image': serializers.FileField()})


def image_bytes(request):
    upload = request.FILES.get('image')
    if not upload or upload.size > 2 * 1024 * 1024:
        raise ValidationError('Выберите изображение не больше 2 МБ')
    raw = upload.read()
    if raw.startswith(b'\x89PNG\r\n\x1a\n') and raw[12:16] == b'IHDR' and raw.endswith(b'IEND\xaeB`\x82'):
        mime = 'image/png'
    elif raw.startswith(b'\xff\xd8\xff') and raw.endswith(b'\xff\xd9'):
        mime = 'image/jpeg'
    elif raw.startswith(b'RIFF') and raw[8:12] == b'WEBP' and int.from_bytes(raw[4:8], 'little') + 8 == len(raw):
        mime = 'image/webp'
    else:
        raise ValidationError('Допустимы файлы PNG, JPEG или WebP')
    return raw, mime


def serve_avatar(obj):
    if not obj.avatar_image:
        raise NotFound('Аватар не найден')
    response = HttpResponse(bytes(obj.avatar_image), content_type=obj.avatar_mime)
    response['Cache-Control'] = 'private, no-cache'
    response['X-Content-Type-Options'] = 'nosniff'
    return response


class ProfileAvatar(APIView):
    parser_classes = [MultiPartParser]

    def get(self, request):
        return serve_avatar(request.user)

    @extend_schema(request=AvatarUpload, responses=UserSerializer)
    def post(self, request):
        raw, mime = image_bytes(request)
        user = request.user
        user.avatar_image, user.avatar_mime, user.avatar_updated_at = raw, mime, timezone.now()
        user.save(update_fields=['avatar_image', 'avatar_mime', 'avatar_updated_at'])
        return Response(UserSerializer(user).data)

    def delete(self, request):
        user = request.user
        user.avatar_image, user.avatar_mime, user.avatar_updated_at = None, '', None
        user.save(update_fields=['avatar_image', 'avatar_mime', 'avatar_updated_at'])
        return Response(UserSerializer(user).data)


class CharacterAvatar(APIView):
    parser_classes = [MultiPartParser]

    def get(self, request, pk):
        campaign = campaign_for(request)
        char = get_object_or_404(Character, pk=pk, campaign=campaign, active=True)
        if not (is_dm(campaign, request.user) or char.owner_id == request.user.pk or (
            campaign.table_visible_to_players and char.table_visible and
            (char.folder.visible_to_players if char.folder_id else campaign.unfiled_visible_to_players)
        )):
            raise PermissionDenied('Лист скрыт от участников')
        return serve_avatar(char)

    @extend_schema(request=AvatarUpload, responses=CharacterSerializer)
    def post(self, request, pk):
        campaign = campaign_for(request)
        char = own_character(request, campaign, pk, is_dm(campaign, request.user))
        raw, mime = image_bytes(request)
        char.avatar_image, char.avatar_mime, char.avatar_updated_at = raw, mime, timezone.now()
        char.save(update_fields=['avatar_image', 'avatar_mime', 'avatar_updated_at', 'updated_at'])
        return Response(CharacterSerializer(char).data)

    def delete(self, request, pk):
        campaign = campaign_for(request)
        char = own_character(request, campaign, pk, is_dm(campaign, request.user))
        char.avatar_image, char.avatar_mime, char.avatar_updated_at = None, '', None
        char.save(update_fields=['avatar_image', 'avatar_mime', 'avatar_updated_at', 'updated_at'])
        return Response(CharacterSerializer(char).data)
