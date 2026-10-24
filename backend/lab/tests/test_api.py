import secrets
from concurrent.futures import ThreadPoolExecutor
from unittest.mock import patch
import pytest
from django.core.management import call_command
from django.db import transaction, IntegrityError, connection, close_old_connections
from rest_framework.test import APIClient
from rest_framework.exceptions import ValidationError
from lab.models import *
from lab.services import casino, effects


@pytest.fixture
def world(db):
    call_command("seed_initial_data", verbosity=0)
    dm = User.objects.create_user(
        username="dm@example.org", email="dm@example.org", password="StrongPass123!"
    )
    player = User.objects.create_user(
        username="p@example.org", email="p@example.org", password="StrongPass123!"
    )
    outsider = User.objects.create_user(
        username="o@example.org", email="o@example.org", password="StrongPass123!"
    )
    c = Campaign.objects.create(name="Test campaign", owner=dm)
    Membership.objects.create(campaign=c, user=dm, role="dm")
    Membership.objects.create(campaign=c, user=player)
    char = Character.objects.create(campaign=c, owner=player, name="Mira")
    s = GameSession.objects.create(campaign=c, name="Session 1", status="active")
    with transaction.atomic():
        casino.ensure_configs(c)
        casino.wallet_for(c, player)
        casino.wallet_for(c, dm)
    return dm, player, outsider, c, char, s


def client(user):
    c = APIClient()
    c.force_authenticate(user=user)
    return c


def post(c, path, data, key=None):
    return c.post(
        path, data, format="json", HTTP_IDEMPOTENCY_KEY=key or secrets.token_hex(16)
    )


def scoped(path, c):
    return path + f"?campaign={c.pk}"


def test_register_login_and_csrf(db):
    c = APIClient(enforce_csrf_checks=True)
    assert (
        c.post(
            "/api/auth/register/",
            {"email": "r@example.org", "password": "StrongPass123!"},
            format="json",
        ).status_code
        == 403
    )
    token = c.get("/api/auth/csrf/").json()["data"]["csrfToken"]
    r = c.post(
        "/api/auth/register/",
        {"email": "r@example.org", "password": "StrongPass123!", "first_name": "R"},
        format="json",
        HTTP_X_CSRFTOKEN=token,
    )
    assert (
        r.status_code == 200
        and c.get("/api/auth/me/").json()["data"]["email"] == "r@example.org"
    )
    assert c.get('/api/auth/me/').json()['data']['account_role'] == 'player'
    token = c.get('/api/auth/csrf/').json()['data']['csrfToken']
    assert c.post('/api/campaigns/', {'name':'Not allowed'}, format='json', HTTP_X_CSRFTOKEN=token).status_code == 403
    assert c.patch('/api/auth/me/', {'account_role':'dm'}, format='json', HTTP_X_CSRFTOKEN=token).status_code == 400
    token = c.get("/api/auth/csrf/").json()["data"]["csrfToken"]
    assert c.post("/api/auth/logout/", {}, HTTP_X_CSRFTOKEN=token).status_code == 200
    assert c.get("/api/auth/me/").status_code == 403
    token = c.get("/api/auth/csrf/").json()["data"]["csrfToken"]
    assert (
        c.post(
            "/api/auth/login/",
            {"email": "r@example.org", "password": "StrongPass123!"},
            format="json",
            HTTP_X_CSRFTOKEN=token,
        ).status_code
        == 200
    )


def test_seed_exact_and_idempotent(world):
    QuestDefinition.objects.create(
        code="mine", title="Custom", description="x", category="x"
    )
    call_command("seed_initial_data")
    assert EffectDefinition.objects.filter(code__startswith="std-").count() == 120
    assert QuestDefinition.objects.filter(code__startswith="std-").count() == 42
    assert (
        QuestDefinition.objects.filter(code="mine").exists()
        and CasinoConfiguration.objects.count() == 7
    )


def test_campaign_create_join_character_and_isolation(world):
    dm, p, o, c, char, s = world
    oc = client(o)
    r = post(oc, "/api/campaigns/", {"name": "Other"})
    assert r.status_code == 201
    assert oc.get(scoped("/api/characters/", c)).status_code == 403
    assert (
        post(
            oc, scoped(f"/api/sessions/{s.pk}/effects/roll/", c), {"character": char.pk}
        ).status_code
        == 403
    )
    joined = post(oc, "/api/campaigns/join/", {"code": c.invite_code})
    assert joined.status_code == 200
    assert "invite_code" not in joined.json()["data"]
    assert (
        post(
            oc, scoped(f"/api/sessions/{s.pk}/effects/roll/", c), {"character": char.pk}
        ).status_code
        == 403
    )
    assert (
        post(
            oc,
            scoped("/api/characters/", c),
            {"campaign": c.pk, "name": "New", "level": 2},
        ).status_code
        == 200
    )
    assert (
        post(
            oc,
            scoped(
                f"/api/dm/actions/wallet/{Wallet.objects.get(campaign=c, user=p).pk}/",
                c,
            ),
            {"amount": 50, "note": "x"},
        ).status_code
        == 403
    )


def test_roll_retries_limit_snapshot_and_secret(world):
    dm, p, o, c, char, s = world
    pc = client(p)
    url = scoped(f"/api/sessions/{s.pk}/effects/roll/", c)
    e = EffectDefinition.objects.first()
    e.secret = "NEVER EXPOSE"
    e.save()
    with patch("lab.services.effects.draw", return_value=e):
        r = post(pc, url, {"character": char.pk}, "same-key-123")
    assert r.status_code == 200
    data = r.json()["data"]
    assert "secret" not in data["snapshot"]
    assert post(pc, url, {"character": char.pk}, "same-key-123").json()["data"] == data
    assert (
        post(pc, url, {"character": char.pk}).status_code == 400
        and EffectRoll.objects.count() == 1
    )
    assert post(pc, url, {"character": 999}, "same-key-123").status_code == 400
    e.description = "Changed"
    e.save()
    assert EffectRoll.objects.get().snapshot["description"] != "Changed"
    assert "NEVER EXPOSE" not in str(pc.get(scoped("/api/history/effects/", c)).json())


def test_effect_approval_expiry_and_choice(world):
    dm, p, o, c, char, s = world
    roll = effects.roll_effect(
        s, char, EffectDefinition.objects.get(code="std-effect-011")
    )
    pc = client(p)
    dc = client(dm)
    r = post(
        pc,
        scoped(f"/api/active-effects/{roll.pk}/use/", c),
        {"note": "Old friend in the market"},
    )
    assert r.status_code == 200 and r.json()["data"]["status"] == "pending_approval"
    approval = EffectApprovalRequest.objects.get()
    assert (
        post(
            pc, scoped(f"/api/dm/actions/effect/{approval.pk}/", c), {"approve": True}
        ).status_code
        == 403
    )
    assert (
        post(
            dc, scoped(f"/api/dm/actions/effect/{approval.pk}/", c), {"approve": False}
        ).status_code
        == 200
    )
    roll.refresh_from_db()
    assert roll.status == "active"
    choice = effects.roll_effect(
        s, char, EffectDefinition.objects.get(code="std-effect-119"), bonus=True
    )
    effects.use_effect(choice)
    effects.finish_session(s)
    s2 = GameSession.objects.create(campaign=c, name="Next", status="active")
    choice_roll = effects.roll_effect(s2, char)
    assert (
        choice_roll.status == "rolled"
        and len(choice_roll.choices) == 3
        and all(e["mechanic_type"] != "choice3" for e in choice_roll.choices)
    )
    assert len({e["id"] for e in choice_roll.choices}) == 3
    effects.choose(choice_roll, 0)
    assert choice_roll.status == "active"
    assert (
        post(
            pc, scoped(f"/api/active-effects/{roll.pk}/use/", c), {"note": "late"}
        ).status_code
        == 400
    )


def test_category_exclusion_and_weights(world):
    dm, p, o, c, char, s = world
    e = EffectDefinition.objects.get(code="std-effect-041")
    assert effects.draw(c, [(e, 100)], c.settings).category == "complication"
    c.settings["category_weights"] = {"gift": 1, "complication": 0, "paradox": 0}
    with pytest.raises(ValidationError):
        effects.draw(c, [(e, 100)], c.settings)


def test_quest_once_reward_and_submit_validation(world):
    dm, p, o, c, char, s = world
    pc = client(p)
    dc = client(dm)
    assert (
        post(
            pc, scoped(f"/api/sessions/{s.pk}/quests/roll/", c), {"character": char.pk}
        ).status_code
        == 200
    )
    q = QuestAssignment.objects.get()
    reward = q.snapshot["reward"]
    assert (
        post(
            pc, scoped(f"/api/quest-assignments/{q.pk}/submit/", c), {"evidence": ""}
        ).status_code
        == 400
    )
    assert (
        post(
            pc,
            scoped(f"/api/quest-assignments/{q.pk}/submit/", c),
            {"evidence": "Helped ally"},
        ).status_code
        == 200
    )
    url = scoped(f"/api/dm/actions/quest/{q.pk}/", c)
    assert post(pc, url, {"approve": True}).status_code == 403
    assert post(dc, url, {"approve": True}, "approve-quest-1").status_code == 200
    assert post(dc, url, {"approve": True}, "approve-quest-1").status_code == 200
    assert post(dc, url, {"approve": True}).status_code == 400
    assert Wallet.objects.get(campaign=c, user=p).balance == 100 + reward
    assert WalletTransaction.objects.filter(reference=f"quest:{q.pk}").count() == 1


def test_one_initial_grant_and_insufficient_funds(world):
    dm, p, o, c, char, s = world
    with transaction.atomic():
        casino.wallet_for(c, p)
        casino.wallet_for(c, p)
    assert WalletTransaction.objects.filter(kind="initial", wallet__user=p).count() == 1
    pc = client(p)
    with patch("lab.services.casino.secrets.choice", return_value="tails"):
        assert (
            post(
                pc,
                scoped("/api/casino/coin/rounds/", c),
                {"stake": 100, "choice": "heads"},
            ).status_code
            == 200
        )
        assert (
            post(
                pc,
                scoped("/api/casino/coin/rounds/", c),
                {"stake": 100, "choice": "heads"},
            ).status_code
            == 400
        )
    assert (
        Wallet.objects.get(campaign=c, user=p).balance == 0
        and CasinoRound.objects.count() == 1
    )


def test_idempotency_round_and_ledger_consistency(world):
    dm, p, o, c, char, s = world
    pc = client(p)
    url = scoped("/api/casino/coin/rounds/", c)
    with patch("lab.services.casino.secrets.choice", return_value="heads"):
        r = post(pc, url, {"stake": 10, "choice": "heads"}, "game-key-111")
    assert (
        r.status_code == 200
        and r.json()["data"]["payout"] == "19.00"
        and r.json()["data"]["profit"] == "9.00"
    )
    assert (
        post(pc, url, {"stake": 10, "choice": "heads"}, "game-key-111").json()
        == r.json()
    )
    assert (
        CasinoRound.objects.count() == 1
        and Wallet.objects.get(campaign=c, user=p).balance == 109
    )
    assert (
        sum(
            WalletTransaction.objects.filter(wallet__user=p).values_list(
                "amount", flat=True
            )
        )
        == 109
    )
    assert (
        post(pc, url, {"stake": 11, "choice": "heads"}, "game-key-111").status_code
        == 400
    )


def test_transaction_rollback_after_write_failure(world):
    dm, p, o, c, char, s = world
    with patch("lab.services.casino.settle", side_effect=RuntimeError("disk failure")):
        with pytest.raises(RuntimeError):
            post(
                client(p),
                scoped("/api/casino/coin/rounds/", c),
                {"stake": 10, "choice": "heads"},
            )
    assert (
        CasinoRound.objects.count() == 0
        and Wallet.objects.get(campaign=c, user=p).balance == 100
    )
    assert WalletTransaction.objects.filter(kind="stake").count() == 0


@pytest.mark.parametrize(
    "game,payload",
    [
        (
            "roulette",
            {
                "bets": [
                    {"kind": "number", "value": 0, "amount": 5},
                    {"kind": "red", "amount": 5},
                ]
            },
        ),
        ("slots", {"stake": 5}),
        ("dice", {"stake": 5, "choice": "seven"}),
        ("coin", {"stake": 5, "choice": "heads"}),
        ("lucky-wheel", {"stake": 5}),
        ("blackjack", {"stake": 5}),
        ("higher-lower", {"stake": 5}),
    ],
)
def test_all_games_server_rounds(world, game, payload):
    dm, p, o, c, char, s = world
    pc = client(p)
    r = post(pc, scoped(f"/api/casino/{game}/rounds/", c), payload)
    assert r.status_code == 200, r.content
    round = CasinoRound.objects.get()
    public = r.json()["data"]
    assert "private_state" not in public
    if round.status == "active":
        if game == "blackjack":
            assert len(public["result"]["dealer"]) == 1 and "deck" not in str(public)
            act = "stand"
        else:
            act = "higher" if public["result"]["current"]["rank"] < 14 else "lower"
        assert (
            post(
                pc,
                scoped(f"/api/casino/rounds/{round.pk}/actions/", c),
                {"action": act},
            ).status_code
            == 200
        )
    round.refresh_from_db()
    assert round.status == "completed"
    assert (
        Wallet.objects.get(campaign=c, user=p).balance
        == 100 - round.stake + round.payout
    )
    assert (
        post(
            pc,
            scoped(f"/api/casino/rounds/{round.pk}/actions/", c),
            {"action": "stand"},
        ).status_code
        == 400
    )


def test_blackjack_double_and_hidden_snapshot(world):
    dm, p, o, c, char, s = world
    pc = client(p)
    cards = [{"rank": r, "suit": "♠"} for r in [5, 6, 10, 7, 10, 8, 2, 3]]
    with patch("lab.services.casino.deck", return_value=cards):
        r = post(pc, scoped("/api/casino/blackjack/rounds/", c), {"stake": 10})
    rid = r.json()["data"]["id"]
    assert r.json()["data"]["result"]["dealer"] == [{"rank": 10, "suit": "♠"}]
    result = post(
        pc, scoped(f"/api/casino/rounds/{rid}/actions/", c), {"action": "double"}
    )
    assert result.status_code == 200
    assert (
        result.json()["data"]["stake"] == "20.00"
        and len(result.json()["data"]["result"]["player"]) == 3
    )


def test_configs_immutable_history_and_cross_campaign(world):
    dm, p, o, c, char, s = world
    dc = client(dm)
    pc = client(p)
    cfg = CasinoConfiguration.objects.get(campaign=c, game="coin")
    assert (
        pc.patch(
            scoped("/api/dm/config/coin/", c),
            {"rules": {"multiplier": 5}},
            format="json",
            HTTP_IDEMPOTENCY_KEY="abcdefghi",
        ).status_code
        == 403
    )
    assert (
        post(
            pc, scoped("/api/casino/coin/rounds/", c), {"stake": 5, "choice": "heads"}
        ).status_code
        == 200
    )
    r = dc.patch(
        scoped("/api/dm/config/coin/", c),
        {"rules": {"multiplier": 2.1}},
        format="json",
        HTTP_IDEMPOTENCY_KEY="abcdefghi",
    )
    assert r.status_code == 200
    assert (
        CasinoRound.objects.get().rules_snapshot["multiplier"] == 1.9
        and CasinoConfiguration.objects.get(pk=cfg.pk).version == 2
    )
    r = post(
        dc,
        scoped("/api/dm/effects/", c),
        {
            "title": "Mine",
            "description": "Story",
            "category": "gift",
            "secret": "hidden",
        },
    )
    assert r.status_code == 200
    eid = r.json()["data"]["id"]
    assert "secret" not in pc.get(scoped(f"/api/effects/{eid}/", c)).json()["data"]
    base = EffectDefinition.objects.get(code="std-effect-001")
    assert (
        dc.patch(
            scoped(f"/api/dm/effects/{base.pk}/", c),
            {"title": "Hack"},
            format="json",
            HTTP_IDEMPOTENCY_KEY="base-patch-1",
        ).status_code
        == 404
    )


def test_db_nonnegative_constraint(world):
    dm, p, o, c, char, s = world
    with pytest.raises(IntegrityError):
        with transaction.atomic():
            Wallet.objects.filter(campaign=c, user=p).update(balance=-1)


def test_exchange_consent_and_dm(world):
    dm, p, o, c, char, s = world
    Membership.objects.create(campaign=c, user=o)
    target = Character.objects.create(campaign=c, owner=o, name="Other")
    src = effects.roll_effect(
        s, char, EffectDefinition.objects.get(code="std-effect-091")
    )
    gift = effects.roll_effect(
        s, char, EffectDefinition.objects.get(code="std-effect-012"), bonus=True
    )
    other = effects.roll_effect(
        s, target, EffectDefinition.objects.get(code="std-effect-021")
    )
    exchange = effects.request_exchange(src, gift, target, other)
    assert (
        post(
            client(dm),
            scoped(f"/api/dm/actions/exchange/{exchange.pk}/", c),
            {"approve": True},
        ).status_code
        == 400
    )
    assert (
        post(
            client(o),
            scoped(f"/api/exchanges/{exchange.pk}/consent/", c),
            {"accept": True},
        ).status_code
        == 200
    )
    assert (
        post(
            client(dm),
            scoped(f"/api/dm/actions/exchange/{exchange.pk}/", c),
            {"approve": True},
        ).status_code
        == 200
    )
    gift.refresh_from_db()
    other.refresh_from_db()
    src.refresh_from_db()
    assert gift.character == target and other.character == char and src.status == "used"


@pytest.mark.django_db(transaction=True)
def test_postgres_parallel_no_overspend():
    if connection.vendor != "postgresql":
        pytest.skip("Requires PostgreSQL row-level locks")
    user = User.objects.create_user(
        username="parallel@example.org", email="parallel@example.org"
    )
    campaign = Campaign.objects.create(
        name="Concurrency",
        owner=user,
        settings={**default_settings(), "initial_balance": 10},
    )
    Membership.objects.create(campaign=campaign, user=user, role="dm")
    with transaction.atomic():
        casino.ensure_configs(campaign)
        casino.wallet_for(campaign, user)

    def run(_):
        close_old_connections()
        try:
            with transaction.atomic():
                c = Campaign.objects.select_for_update().get(pk=campaign.pk)
                casino.create_round(c, user, "coin", {"stake": 10, "choice": "heads"})
            return "ok"
        except ValidationError:
            return "insufficient"
        finally:
            close_old_connections()

    with patch("lab.services.casino.secrets.choice", return_value="tails"):
        with ThreadPoolExecutor(max_workers=2) as pool:
            results = list(pool.map(run, [0, 1]))
    assert (
        sorted(results) == ["insufficient", "ok"]
        and Wallet.objects.get(campaign=campaign, user=user).balance == 0
    )


def test_exchanged_card_does_not_reset_original_roll_limit(world):
    dm, p, o, c, char, s = world
    Membership.objects.create(campaign=c, user=o)
    target = Character.objects.create(campaign=c, owner=o, name="Other")
    original = effects.roll_effect(
        s, char, EffectDefinition.objects.get(code="std-effect-012")
    )
    original.character = target
    original.save()
    with pytest.raises(ValidationError):
        effects.roll_effect(s, char)


def test_import_export_and_pool_scope(world):
    dm, p, o, c, char, s = world
    dc = client(dm)
    exported = dc.get(scoped("/api/dm/effects/export/", c)).json()["data"]["content"]
    assert len(exported) == 120
    assert (
        post(
            dc,
            scoped("/api/dm/effects/import/", c),
            {"content": exported[:2], "format": "json"},
        ).status_code
        == 200
    )
    assert (
        post(
            dc,
            scoped("/api/dm/effects/import/", c),
            {"content": exported[:2], "format": "json"},
        ).status_code
        == 200
    )
    assert EffectDefinition.objects.filter(campaign=c).count() == 2
    e = EffectDefinition.objects.filter(campaign=c).first()
    assert (
        post(
            dc,
            scoped("/api/dm/pools/", c),
            {"name": "Only", "entries": [{"effect_id": e.pk, "weight": 1}]},
        ).status_code
        == 200
    )
    assert [e2.pk for e2, w in effects.available(c)] == [e.pk]


@pytest.mark.django_db(transaction=True)
def test_postgres_parallel_idempotency():
    if connection.vendor != "postgresql":
        pytest.skip("Requires PostgreSQL row-level locks")
    user = User.objects.create_user(
        username="idem@example.org", email="idem@example.org"
    )
    campaign = Campaign.objects.create(name="Idempotency", owner=user)
    Membership.objects.create(campaign=campaign, user=user, role="dm")
    with transaction.atomic():
        casino.ensure_configs(campaign)
        casino.wallet_for(campaign, user)

    def run(_):
        close_old_connections()
        try:
            response = post(
                client(user),
                scoped("/api/casino/coin/rounds/", campaign),
                {"stake": 10, "choice": "heads"},
                "parallel-same-key",
            )
            return response.status_code, response.json()
        finally:
            close_old_connections()

    with patch("lab.services.casino.secrets.choice", return_value="heads"):
        with ThreadPoolExecutor(max_workers=2) as pool:
            results = list(pool.map(run, [0, 1]))
    assert results[0] == results[1] and results[0][0] == 200
    assert CasinoRound.objects.filter(campaign=campaign).count() == 1
    assert (
        WalletTransaction.objects.filter(
            wallet__campaign=campaign, kind="stake"
        ).count()
        == 1
    )
    assert Wallet.objects.get(campaign=campaign, user=user).balance == 109


def test_malformed_game_payloads_are_rejected(world):
    dm, p, o, c, char, s = world
    pc = client(p)
    assert (
        post(
            pc,
            scoped("/api/casino/roulette/rounds/", c),
            {"bets": [{"kind": [], "amount": 1}]},
        ).status_code
        == 400
    )
    assert post(pc, scoped("/api/casino/coin/rounds/", c), [1, 2]).status_code == 400
