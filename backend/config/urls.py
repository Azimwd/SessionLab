from django.contrib import admin
from django.urls import path, include
from rest_framework.routers import DefaultRouter
from drf_spectacular.views import SpectacularAPIView, SpectacularSwaggerView
from lab.api.auth import *
from lab.api.campaigns import *
from lab.api.play import *
from lab.api.dm import *
from lab.api.health import health
from lab.api.scene import SceneTargets, SceneTargetDetail, DamageRequests, ResolveDamage
from lab.api.sheets import SheetView, SheetResource, AbilitiesView, AbilityDetail, RollView, AbilityUse, SpellCatalogView, SpellCatalogDetail, AddCatalogSpell
from lab.api.room import RoomView, RoomEvents, RoomTableVisibility, InitiativeView, room_stream
from lab.api.avatars import ProfileAvatar, CharacterAvatar
from lab.api.dmhub import BridgeSettings, bridge_events
from lab.api.dmhub_sheets import SheetAccessSettings, SheetBridge, SheetBridgeDetail, SheetBridgeRoll, SheetBridgeUse, SheetBridgeResource
from lab.api.dmhub_edit import SheetBridgeEdit, SheetBridgeConditions, SheetBridgeActions, SheetBridgeActionEdit, SheetBridgeCatalog, SheetBridgeCatalogAdd
from lab.api.dmhub_dice import NativeDice, NativeDiceEvents
from lab.api.dmhub_room import NativeRoom, NativeRoomCommand

router = DefaultRouter()
for prefix, view, base in [
    ("campaigns", CampaignViewSet, "campaign"),
    ("characters", CharacterViewSet, "character"),
    ("character-folders", CharacterFolderViewSet, "character-folder"),
    ("sessions", SessionViewSet, "session"),
    ("effects", EffectList, "effect"),
    ("quests", QuestList, "quest"),
    ("casino/transactions", Transactions, "transaction"),
    ("dm/effects", DMEffects, "dm-effect"),
    ("dm/quests", DMQuests, "dm-quest"),
]:
    router.register(prefix, view, basename=base)
urlpatterns = [
    path("api/dm/integrations/dmhub/", BridgeSettings.as_view()),
    path("api/integrations/dmhub/events/", bridge_events),
    path("api/integrations/dmhub/room/", NativeRoom.as_view()),
    path("api/integrations/dmhub/room/commands/", NativeRoomCommand.as_view()),
    path("api/integrations/dmhub/dice/", NativeDice.as_view()),
    path("api/integrations/dmhub/dice/events/", NativeDiceEvents.as_view()),
    path("api/integrations/dmhub/sheet-access/", SheetAccessSettings.as_view()),
    path("api/integrations/dmhub/sheets/", SheetBridge.as_view()),
    path("api/integrations/dmhub/sheets/<int:pk>/", SheetBridgeDetail.as_view()),
    path("api/integrations/dmhub/sheets/<int:pk>/roll/", SheetBridgeRoll.as_view()),
    path("api/integrations/dmhub/sheets/<int:pk>/resources/", SheetBridgeResource.as_view()),
    path("api/integrations/dmhub/sheets/<int:pk>/edit/", SheetBridgeEdit.as_view()),
    path("api/integrations/dmhub/sheets/<int:pk>/conditions/", SheetBridgeConditions.as_view()),
    path("api/integrations/dmhub/sheets/<int:pk>/abilities/", SheetBridgeActions.as_view()),
    path("api/integrations/dmhub/sheets/<int:pk>/abilities/<int:ability_pk>/edit/", SheetBridgeActionEdit.as_view()),
    path("api/integrations/dmhub/catalog/", SheetBridgeCatalog.as_view()),
    path("api/integrations/dmhub/sheets/<int:pk>/catalog-add/", SheetBridgeCatalogAdd.as_view()),
    path("api/integrations/dmhub/sheets/<int:pk>/abilities/<int:ability_pk>/use/", SheetBridgeUse.as_view()),
    path("api/auth/me/avatar/", ProfileAvatar.as_view()),
    path("api/characters/<int:pk>/avatar/", CharacterAvatar.as_view()),
    path("api/scene/targets/", SceneTargets.as_view()),
    path("api/scene/targets/<int:pk>/", SceneTargetDetail.as_view()),
    path("api/scene/damage/", DamageRequests.as_view()),
    path("api/scene/damage/<int:pk>/resolve/", ResolveDamage.as_view()),
    path("api/room/", RoomView.as_view()),
    path("api/room/table-visibility/", RoomTableVisibility.as_view()),
    path("api/room/events/", RoomEvents.as_view()),
    path("api/room/rolls/", RollView.as_view()),
    path("api/room/initiative/", InitiativeView.as_view()),
    path("api/campaigns/<int:pk>/stream/", room_stream),
    path("api/characters/<int:pk>/sheet/", SheetView.as_view()),
    path("api/characters/<int:pk>/resources/", SheetResource.as_view()),
    path("api/characters/<int:pk>/abilities/", AbilitiesView.as_view()),
    path("api/characters/<int:pk>/spells/catalog/", AddCatalogSpell.as_view()),
    path("api/spells/catalog/", SpellCatalogView.as_view()),
    path("api/spells/catalog/<int:pk>/", SpellCatalogDetail.as_view()),
    path("api/abilities/<int:pk>/", AbilityDetail.as_view()),
    path("api/abilities/<int:pk>/use/", AbilityUse.as_view()),
    path("api/health/", health),
    path("admin/", admin.site.urls),
    path("api/auth/csrf/", CsrfView.as_view()),
    path("api/auth/register/", RegisterView.as_view()),
    path("api/auth/login/", LoginView.as_view()),
    path("api/auth/logout/", LogoutView.as_view()),
    path("api/auth/me/", MeView.as_view()),
    path("api/sessions/<int:pk>/<str:module>/roll/", SessionPlay.as_view()),
    path("api/sessions/<int:pk>/<str:module>/my/", SessionPlay.as_view()),
    path("api/active-effects/<int:pk>/<str:verb>/", RollAction.as_view()),
    path("api/quest-assignments/<int:pk>/submit/", QuestSubmit.as_view()),
    path("api/history/<str:module>/", History.as_view()),
    path("api/feed/", Feed.as_view()),
    path("api/exchanges/", ExchangeView.as_view()),
    path("api/exchanges/<int:pk>/consent/", ExchangeConsent.as_view()),
    path("api/casino/games/", CasinoGames.as_view()),
    path("api/casino/wallet/", WalletView.as_view()),
    path("api/casino/rounds/", Rounds.as_view()),
    path("api/casino/stats/", Stats.as_view()),
    path("api/casino/<str:game>/rounds/", RoundCreate.as_view()),
    path("api/casino/rounds/<int:pk>/actions/", RoundAction.as_view()),
    path("api/dm/overview/", DMOverview.as_view()),
    path("api/dm/actions/<str:kind>/<int:pk>/", DMAction.as_view()),
    path("api/dm/config/<str:game>/", DMConfig.as_view()),
    path("api/dm/pools/", DMPools.as_view()),
    path("api/dm/history/<str:kind>/", DMHistory.as_view()),
    path("api/schema/", SpectacularAPIView.as_view(), name="schema"),
    path("api/docs/", SpectacularSwaggerView.as_view(url_name="schema")),
    path("api/", include(router.urls)),
]
