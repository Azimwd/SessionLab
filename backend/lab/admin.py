from django.contrib import admin
from django.contrib.auth.admin import UserAdmin
from .models import *

admin.site.site_header = "SessionLab · System administration"
admin.site.register(User, UserAdmin)


@admin.register(EffectDefinition)
class EffectAdmin(admin.ModelAdmin):
    list_display = ["code", "title", "category", "rarity", "active", "campaign"]
    list_filter = ["category", "rarity", "active", "archived"]
    search_fields = ["title", "description", "code"]


@admin.register(QuestDefinition)
class QuestAdmin(admin.ModelAdmin):
    list_display = ["code", "title", "category", "reward", "active"]
    list_filter = ["category", "active"]
    search_fields = ["title", "description", "code"]


# Financial and historical records are read-only, including deletes and bulk actions.
class ImmutableAdmin(admin.ModelAdmin):
    def has_add_permission(self, request):
        return False

    def has_change_permission(self, request, obj=None):
        return False

    def has_delete_permission(self, request, obj=None):
        return False


for model in [
    Wallet,
    WalletTransaction,
    CasinoRound,
    CasinoRoundAction,
    EffectRoll,
    QuestAssignment,
    IdempotencyRecord,
    AuditLog,
    EffectApprovalRequest,
    ChoiceGrant,
    EffectExchange,
    Achievement,
    RoomEvent,
]:
    admin.site.register(model, ImmutableAdmin)
for model in [
    Campaign,
    Membership,
    Character,
    CharacterFolder,
    GameSession,
    EffectPool,
    EffectPoolEntry,
    CasinoConfiguration,
    CharacterSheet,
    CharacterAbility,
    SpellCatalogEntry,
    InitiativeTracker,
    InitiativeEntry,
]:
    admin.site.register(model)
