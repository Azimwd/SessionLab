import secrets
from django.db import models
from django.contrib.auth.models import AbstractUser
from django.db.models import Q


def invite_code():
    return secrets.token_urlsafe(16)


def default_settings():
    return {
        "edition": "5e-2024",
        "effect_limit": 1,
        "quest_limit": 2,
        "category_weights": {"gift": 45, "complication": 25, "paradox": 30},
        "casino_enabled": True,
        "initial_balance": 100,
    }


class User(AbstractUser):
    email = models.EmailField(unique=True)
    account_role = models.CharField(max_length=10, choices=[('dm', 'Master'), ('player', 'Player')], default='dm')
    theme = models.CharField(max_length=10, default="light")
    reduced_motion = models.BooleanField(default=False)
    avatar_image = models.BinaryField(null=True, blank=True)
    avatar_mime = models.CharField(max_length=20, blank=True)
    avatar_updated_at = models.DateTimeField(null=True, blank=True)
    USERNAME_FIELD = "email"
    REQUIRED_FIELDS = ["username"]


class Timestamped(models.Model):
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        abstract = True


class Campaign(Timestamped):
    deleted_at = models.DateTimeField(null=True, blank=True)
    name = models.CharField(max_length=120)
    description = models.TextField(blank=True)
    owner = models.ForeignKey(
        User, on_delete=models.PROTECT, related_name="owned_campaigns"
    )
    invite_code = models.CharField(max_length=64, unique=True, default=invite_code)
    settings = models.JSONField(default=default_settings)
    table_visible_to_players = models.BooleanField(default=True)
    unfiled_visible_to_players = models.BooleanField(default=False)

    def __str__(self):
        return self.name


class Membership(Timestamped):
    campaign = models.ForeignKey(
        Campaign, on_delete=models.CASCADE, related_name="memberships"
    )
    user = models.ForeignKey(User, on_delete=models.PROTECT)
    role = models.CharField(
        max_length=10, choices=[("dm", "DM"), ("player", "Player")], default="player"
    )
    active = models.BooleanField(default=True)

    class Meta:
        constraints = [
            models.UniqueConstraint(fields=["campaign", "user"], name="one_membership")
        ]


class DMHubBridge(Timestamped):
    campaign = models.OneToOneField(Campaign, on_delete=models.CASCADE, related_name="dmhub_bridge")
    token_hash = models.CharField(max_length=64)
    enabled = models.BooleanField(default=True)


class DMHubSheetAccess(Timestamped):
    """One revocable device credential per member and campaign."""
    campaign = models.ForeignKey(Campaign, on_delete=models.CASCADE)
    user = models.ForeignKey(User, on_delete=models.CASCADE)
    token_hash = models.CharField(max_length=64, unique=True)
    enabled = models.BooleanField(default=True)

    class Meta:
        constraints = [
            models.UniqueConstraint(fields=["campaign", "user"], name="one_dmhub_sheet_access")
        ]


class CharacterFolder(Timestamped):
    campaign = models.ForeignKey(Campaign, on_delete=models.PROTECT, related_name='character_folders')
    owner = models.ForeignKey(User, on_delete=models.PROTECT)
    name = models.CharField(max_length=80)
    is_system = models.BooleanField(default=False)
    visible_to_players = models.BooleanField(default=False)

    class Meta:
        constraints = [
            models.UniqueConstraint(fields=['campaign', 'owner', 'name'], name='unique_character_folder_name'),
            models.UniqueConstraint(fields=['campaign'], condition=Q(is_system=True), name='unique_campaign_players_folder'),
        ]
        ordering = ['name', 'id']


class Character(Timestamped):
    campaign = models.ForeignKey(Campaign, on_delete=models.PROTECT)
    owner = models.ForeignKey(User, on_delete=models.PROTECT)
    kind = models.CharField(max_length=10, choices=[('player', 'Player'), ('npc', 'NPC')], default='player')
    name = models.CharField(max_length=100)
    character_class = models.CharField(max_length=60, blank=True)
    level = models.PositiveSmallIntegerField(default=1)
    species = models.CharField(max_length=60, blank=True)
    description = models.TextField(blank=True)
    avatar = models.URLField(blank=True)
    avatar_image = models.BinaryField(null=True, blank=True)
    avatar_mime = models.CharField(max_length=20, blank=True)
    avatar_updated_at = models.DateTimeField(null=True, blank=True)
    active = models.BooleanField(default=True)
    table_visible = models.BooleanField(default=True)
    folder = models.ForeignKey('CharacterFolder', on_delete=models.SET_NULL, null=True, blank=True, related_name='characters')

    class Meta:
        constraints = [
            models.CheckConstraint(
                condition=Q(level__gte=1) & Q(level__lte=30),
                name="character_level_range",
            )
        ]


class GameSession(Timestamped):
    campaign = models.ForeignKey(
        Campaign, on_delete=models.PROTECT, related_name="sessions"
    )
    name = models.CharField(max_length=120)
    date = models.DateTimeField(null=True, blank=True)
    status = models.CharField(
        max_length=12,
        default="planned",
        choices=[
            ("planned", "Planned"),
            ("active", "Active"),
            ("completed", "Completed"),
        ],
    )
    settings = models.JSONField(default=dict, blank=True)

    class Meta:
        constraints = [
            models.UniqueConstraint(
                fields=["campaign"],
                condition=Q(status="active"),
                name="one_active_session",
            )
        ]


class EffectDefinition(Timestamped):
    code = models.CharField(max_length=80, unique=True)
    campaign = models.ForeignKey(
        Campaign, on_delete=models.PROTECT, null=True, blank=True
    )
    title = models.CharField(max_length=160)
    summary = models.CharField(max_length=300, blank=True)
    description = models.TextField()
    mechanic = models.TextField(blank=True)
    secret = models.TextField(blank=True)
    category = models.CharField(
        max_length=16,
        choices=[
            ("gift", "Дар"),
            ("complication", "Осложнение"),
            ("paradox", "Парадокс"),
        ],
    )
    rarity = models.CharField(
        max_length=16,
        choices=[(x, x) for x in ["common", "uncommon", "rare", "epic", "special"]],
        default="common",
    )
    weight = models.PositiveIntegerField(default=100)
    duration = models.CharField(max_length=80, default="До конца сессии")
    use_limit = models.PositiveSmallIntegerField(default=1)
    activation = models.TextField(blank=True)
    requires_approval = models.BooleanField(default=True)
    mechanic_type = models.CharField(max_length=40, default="narrative")
    parameters = models.JSONField(default=dict, blank=True)
    color = models.CharField(max_length=20, default="#695CF5")
    icon = models.CharField(max_length=40, default="sparkles")
    animation = models.CharField(max_length=40, default="flip")
    homebrew = models.BooleanField(default=True)
    active = models.BooleanField(default=True)
    archived = models.BooleanField(default=False)

    def __str__(self):
        return self.title


class EffectPool(Timestamped):
    campaign = models.ForeignKey(Campaign, on_delete=models.PROTECT)
    name = models.CharField(max_length=120)
    active = models.BooleanField(default=True)


class EffectPoolEntry(models.Model):
    pool = models.ForeignKey(
        EffectPool, on_delete=models.CASCADE, related_name="entries"
    )
    effect = models.ForeignKey(EffectDefinition, on_delete=models.PROTECT)
    weight = models.PositiveIntegerField(default=100)

    class Meta:
        constraints = [
            models.UniqueConstraint(fields=["pool", "effect"], name="one_pool_effect")
        ]


class EffectRoll(Timestamped):
    issued_to = models.ForeignKey(
        Character, on_delete=models.PROTECT, null=True, related_name="issued_effects"
    )
    session = models.ForeignKey(GameSession, on_delete=models.PROTECT)
    character = models.ForeignKey(Character, on_delete=models.PROTECT)
    definition = models.ForeignKey(
        EffectDefinition, on_delete=models.PROTECT, null=True
    )
    snapshot = models.JSONField(default=dict)
    choices = models.JSONField(default=list)
    status = models.CharField(max_length=24, default="active")
    uses = models.PositiveIntegerField(default=0)
    note = models.TextField(blank=True)
    bonus = models.BooleanField(default=False)


class EffectApprovalRequest(Timestamped):
    effect = models.ForeignKey(
        EffectRoll, on_delete=models.PROTECT, related_name="approvals"
    )
    description = models.TextField()
    status = models.CharField(max_length=16, default="pending")
    decision_note = models.TextField(blank=True)
    decided_by = models.ForeignKey(User, on_delete=models.PROTECT, null=True)


class QuestDefinition(Timestamped):
    code = models.CharField(max_length=80, unique=True)
    campaign = models.ForeignKey(
        Campaign, on_delete=models.PROTECT, null=True, blank=True
    )
    title = models.CharField(max_length=160)
    description = models.TextField()
    category = models.CharField(max_length=80)
    difficulty = models.CharField(max_length=20, default="normal")
    reward = models.PositiveSmallIntegerField(default=10)
    active = models.BooleanField(default=True)
    archived = models.BooleanField(default=False)

    def __str__(self):
        return self.title


class QuestAssignment(Timestamped):
    session = models.ForeignKey(GameSession, on_delete=models.PROTECT)
    character = models.ForeignKey(Character, on_delete=models.PROTECT)
    definition = models.ForeignKey(QuestDefinition, on_delete=models.PROTECT)
    snapshot = models.JSONField()
    status = models.CharField(max_length=24, default="active")
    evidence = models.TextField(blank=True)
    decision_note = models.TextField(blank=True)
    decided_by = models.ForeignKey(User, on_delete=models.PROTECT, null=True)


class Wallet(Timestamped):
    campaign = models.ForeignKey(Campaign, on_delete=models.PROTECT)
    user = models.ForeignKey(User, on_delete=models.PROTECT)
    balance = models.DecimalField(max_digits=16, decimal_places=2, default=0)

    class Meta:
        constraints = [
            models.UniqueConstraint(fields=["campaign", "user"], name="one_wallet"),
            models.CheckConstraint(
                condition=Q(balance__gte=0), name="nonnegative_balance"
            ),
        ]


class WalletTransaction(Timestamped):
    wallet = models.ForeignKey(
        Wallet, on_delete=models.PROTECT, related_name="transactions"
    )
    amount = models.DecimalField(max_digits=16, decimal_places=2)
    balance_after = models.DecimalField(max_digits=16, decimal_places=2)
    kind = models.CharField(max_length=24)
    reference = models.CharField(max_length=140, unique=True)
    note = models.TextField(blank=True)
    actor = models.ForeignKey(User, on_delete=models.PROTECT, null=True)


class CasinoConfiguration(Timestamped):
    campaign = models.ForeignKey(Campaign, on_delete=models.PROTECT)
    game = models.CharField(max_length=24)
    enabled = models.BooleanField(default=True)
    min_bet = models.PositiveIntegerField(default=1)
    max_bet = models.PositiveIntegerField(default=100)
    rules = models.JSONField(default=dict)
    version = models.PositiveIntegerField(default=1)

    class Meta:
        constraints = [
            models.UniqueConstraint(fields=["campaign", "game"], name="one_game_config")
        ]


class CasinoRound(Timestamped):
    campaign = models.ForeignKey(Campaign, on_delete=models.PROTECT)
    user = models.ForeignKey(User, on_delete=models.PROTECT)
    session = models.ForeignKey(GameSession, on_delete=models.PROTECT, null=True)
    game = models.CharField(max_length=24)
    stake = models.DecimalField(max_digits=16, decimal_places=2)
    payout = models.DecimalField(max_digits=16, decimal_places=2, default=0)
    status = models.CharField(max_length=16, default="active")
    result = models.JSONField(default=dict)
    private_state = models.JSONField(default=dict)
    rules_snapshot = models.JSONField()


class CasinoRoundAction(Timestamped):
    round = models.ForeignKey(
        CasinoRound, on_delete=models.PROTECT, related_name="actions"
    )
    action = models.CharField(max_length=20)
    payload = models.JSONField(default=dict)


class IdempotencyRecord(Timestamped):
    user = models.ForeignKey(User, on_delete=models.PROTECT)
    campaign = models.ForeignKey(Campaign, on_delete=models.PROTECT)
    key = models.CharField(max_length=100)
    fingerprint = models.CharField(max_length=64)
    response = models.JSONField()

    class Meta:
        constraints = [
            models.UniqueConstraint(
                fields=["user", "campaign", "key"], name="unique_request"
            )
        ]


class AuditLog(Timestamped):
    campaign = models.ForeignKey(Campaign, on_delete=models.PROTECT)
    actor = models.ForeignKey(User, on_delete=models.PROTECT)
    action = models.CharField(max_length=80)
    details = models.JSONField(default=dict)


class Achievement(Timestamped):
    user = models.ForeignKey(User, on_delete=models.PROTECT)
    campaign = models.ForeignKey(Campaign, on_delete=models.PROTECT)
    code = models.CharField(max_length=80)
    title = models.CharField(max_length=160)

    class Meta:
        constraints = [
            models.UniqueConstraint(
                fields=["user", "campaign", "code"], name="unique_achievement"
            )
        ]


class ChoiceGrant(Timestamped):
    character = models.ForeignKey(Character, on_delete=models.PROTECT)
    source = models.OneToOneField(
        EffectRoll, on_delete=models.PROTECT, related_name="choice_grant"
    )
    consumed_by = models.OneToOneField(
        EffectRoll,
        on_delete=models.PROTECT,
        null=True,
        blank=True,
        related_name="consumed_grant",
    )


class EffectExchange(Timestamped):
    source = models.ForeignKey(
        EffectRoll, on_delete=models.PROTECT, related_name="exchange_requests"
    )
    offered = models.ForeignKey(
        EffectRoll, on_delete=models.PROTECT, related_name="offered_exchanges"
    )
    target = models.ForeignKey(Character, on_delete=models.PROTECT)
    requested = models.ForeignKey(
        EffectRoll,
        on_delete=models.PROTECT,
        null=True,
        blank=True,
        related_name="requested_exchanges",
    )
    consented = models.BooleanField(default=False)
    status = models.CharField(max_length=20, default="pending_consent")


def default_abilities():
    return {k: 10 for k in ["str", "dex", "con", "int", "wis", "cha"]}


def default_slots():
    return {str(n): {"max": 0, "used": 0} for n in range(1, 10)}


class CharacterSheet(Timestamped):
    character = models.OneToOneField(
        Character, on_delete=models.CASCADE, related_name="sheet"
    )
    version = models.PositiveIntegerField(default=1)
    abilities = models.JSONField(default=default_abilities)
    skills = models.JSONField(default=dict, blank=True)
    saves = models.JSONField(default=list, blank=True)
    proficiency_override = models.PositiveSmallIntegerField(null=True, blank=True)
    armor_class = models.PositiveSmallIntegerField(default=10)
    hp_max = models.PositiveIntegerField(default=10)
    hp_current = models.PositiveIntegerField(default=10)
    hp_temp = models.PositiveIntegerField(default=0)
    speed = models.PositiveSmallIntegerField(default=30)
    initiative_bonus = models.SmallIntegerField(default=0)
    spell_ability = models.CharField(max_length=3, default="int")
    slots = models.JSONField(default=default_slots)
    conditions = models.JSONField(default=list, blank=True)
    death_successes = models.PositiveSmallIntegerField(default=0)
    death_failures = models.PositiveSmallIntegerField(default=0)
    inventory = models.TextField(blank=True)
    notes = models.TextField(blank=True)
    background = models.TextField(blank=True)

    class Meta:
        constraints = [
            models.CheckConstraint(
                condition=Q(hp_current__lte=models.F("hp_max")),
                name="sheet_hp_within_max",
            )
        ]


class SpellCatalogEntry(Timestamped):
    code = models.SlugField(max_length=120, unique=True)
    name_ru = models.CharField(max_length=120)
    name_en = models.CharField(max_length=120, blank=True)
    edition = models.CharField(max_length=20, default="5e-2014")
    level = models.PositiveSmallIntegerField()
    template = models.JSONField(default=dict)
    source = models.CharField(max_length=200, default="SRD 5.1 CC BY 4.0")
    active = models.BooleanField(default=True)

    class Meta:
        ordering = ["level", "name_ru"]


class CharacterAbility(Timestamped):
    character = models.ForeignKey(
        Character, on_delete=models.CASCADE, related_name="actions"
    )
    catalog_entry = models.ForeignKey(SpellCatalogEntry, on_delete=models.PROTECT, null=True, blank=True)
    version = models.PositiveIntegerField(default=1)
    kind = models.CharField(
        max_length=10, choices=[("attack", "Attack"), ("spell", "Spell")]
    )
    name = models.CharField(max_length=100)
    description = models.TextField(blank=True)
    ability = models.CharField(max_length=3, default="str")
    proficient = models.BooleanField(default=True)
    bonus = models.SmallIntegerField(default=0)
    resolution = models.CharField(
        max_length=10,
        choices=[("attack", "Attack"), ("save", "Save"), ("automatic", "Automatic")],
        default="attack",
    )
    dice = models.CharField(max_length=80, default="1d6")
    add_modifier = models.BooleanField(default=False)
    damage_type = models.CharField(max_length=50, blank=True)
    level = models.PositiveSmallIntegerField(default=0)
    upcast_dice = models.CharField(max_length=80, blank=True)
    upcast_allowed = models.BooleanField(default=True)
    roll_count = models.PositiveSmallIntegerField(default=1)
    upcast_count = models.PositiveSmallIntegerField(default=0)
    cantrip_scaling = models.BooleanField(default=False)
    save_ability = models.CharField(max_length=3, default="dex")
    casting_time = models.CharField(max_length=255, default="1 действие")
    range = models.CharField(max_length=80, blank=True)
    duration = models.CharField(max_length=80, blank=True)
    concentration = models.BooleanField(default=False)
    active = models.BooleanField(default=True)


class RoomEvent(Timestamped):
    campaign = models.ForeignKey(Campaign, on_delete=models.PROTECT)
    session = models.ForeignKey(GameSession, on_delete=models.PROTECT)
    actor = models.ForeignKey(User, on_delete=models.PROTECT)
    character = models.ForeignKey(Character, on_delete=models.PROTECT, null=True)
    kind = models.CharField(max_length=30)
    visibility = models.CharField(max_length=10, default="public")
    payload = models.JSONField(default=dict)

    class Meta:
        indexes = [models.Index(fields=["campaign", "session", "-id"])]


class InitiativeTracker(Timestamped):
    session = models.OneToOneField(
        GameSession, on_delete=models.CASCADE, related_name="initiative"
    )
    version = models.PositiveIntegerField(default=1)
    round_number = models.PositiveIntegerField(default=0)
    running = models.BooleanField(default=False)
    current = models.ForeignKey(
        "InitiativeEntry",
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="+",
    )


class InitiativeEntry(Timestamped):
    tracker = models.ForeignKey(
        InitiativeTracker, on_delete=models.CASCADE, related_name="entries"
    )
    character = models.ForeignKey(
        Character, on_delete=models.PROTECT, null=True, blank=True
    )
    player_slot = models.ForeignKey(Character, on_delete=models.PROTECT, null=True, blank=True, related_name='+')
    name = models.CharField(max_length=100)
    initiative = models.SmallIntegerField(default=0)
    dexterity = models.SmallIntegerField(default=0)
    hidden = models.BooleanField(default=False)

    class Meta:
        constraints = [models.UniqueConstraint(fields=['tracker', 'player_slot'], name='one_player_initiative')]
        ordering = ["-initiative", "-dexterity", "id"]


class SceneTarget(Timestamped):
    """An independent combatant; NPC sheets remain reusable templates."""
    session = models.ForeignKey(GameSession, on_delete=models.CASCADE, related_name='scene_targets')
    source = models.ForeignKey(Character, on_delete=models.PROTECT, related_name='scene_instances')
    name = models.CharField(max_length=100)
    visible = models.BooleanField(default=True)
    targetable = models.BooleanField(default=True)
    active = models.BooleanField(default=True)
    linked_sheet = models.BooleanField(default=False)
    hp_max = models.PositiveIntegerField(default=10)
    hp_current = models.PositiveIntegerField(default=10)
    hp_temp = models.PositiveIntegerField(default=0)
    conditions = models.JSONField(default=list, blank=True)
    defenses = models.JSONField(default=dict, blank=True)
    version = models.PositiveIntegerField(default=1)

    class Meta:
        constraints = [
            models.CheckConstraint(condition=Q(hp_current__lte=models.F('hp_max')), name='scene_hp_within_max'),
            models.UniqueConstraint(fields=['session', 'source'], condition=Q(linked_sheet=True, active=True), name='one_linked_scene_player'),
        ]


class DamageApplication(Timestamped):
    target = models.ForeignKey(SceneTarget, on_delete=models.PROTECT, related_name='damage_requests')
    source_event = models.ForeignKey(RoomEvent, on_delete=models.PROTECT, related_name='damage_requests')
    requester = models.ForeignKey(User, on_delete=models.PROTECT, related_name='damage_requests')
    part_index = models.PositiveSmallIntegerField(default=0)
    is_attack = models.BooleanField(default=False)
    status = models.CharField(max_length=12, default='pending')
    resolution = models.JSONField(default=dict, blank=True)
    resolved_by = models.ForeignKey(User, on_delete=models.PROTECT, null=True, related_name='+')

    class Meta:
        constraints = [
            models.UniqueConstraint(fields=['source_event', 'part_index', 'target'], condition=Q(status__in=['pending', 'applied']), name='one_damage_per_target_part'),
            models.UniqueConstraint(fields=['source_event', 'part_index'], condition=Q(is_attack=True, status__in=['pending', 'applied']), name='one_target_per_attack_part'),
        ]
