from copy import deepcopy
from decimal import Decimal
import secrets
from rest_framework.exceptions import ValidationError
from lab.models import (
    CasinoConfiguration,
    CasinoRound,
    CasinoRoundAction,
    Wallet,
    WalletTransaction,
    GameSession,
)
from .casino_math import *


def ensure_configs(campaign):
    for game in GAMES:
        CasinoConfiguration.objects.get_or_create(
            campaign=campaign,
            game=game,
            defaults={"rules": deepcopy(DEFAULT_RULES[game])},
        )


def wallet_for(campaign, user):
    # Caller holds Campaign FOR UPDATE for every write, including initial grant.
    wallet, created = Wallet.objects.get_or_create(campaign=campaign, user=user)
    if created:
        move(
            wallet,
            money(campaign.settings.get("initial_balance", 100)),
            "initial",
            f"initial:{wallet.pk}",
            actor=user,
        )
    return wallet


def move(wallet, amount, kind, reference, actor=None, note=""):
    amount = money(amount)
    wallet = Wallet.objects.select_for_update().get(pk=wallet.pk)
    if wallet.balance + amount < 0:
        raise ValidationError("Недостаточно жетонов")
    if wallet.balance + amount > Decimal("99999999999999"):
        raise ValidationError("Превышен допустимый баланс")
    wallet.balance += amount
    wallet.save(update_fields=["balance", "updated_at"])
    WalletTransaction.objects.create(
        wallet=wallet,
        amount=amount,
        balance_after=wallet.balance,
        kind=kind,
        reference=reference,
        actor=actor,
        note=note,
    )
    return wallet


def validate_rules(game, rules):
    import math

    def numeric(v, lo=0, hi=1000):
        return type(v) in (int, float) and math.isfinite(v) and lo <= v <= hi

    def positive_weights(items):
        return (
            all(
                type(s.get("weight")) is int and 0 <= s["weight"] <= 1000000
                for s in items
            )
            and sum(s["weight"] for s in items) > 0
        )

    try:
        assert game in GAMES and isinstance(rules, dict)
        if game == "roulette":
            assert set(rules["payouts"]) == set(DEFAULT_RULES[game]["payouts"]) and all(
                numeric(v) for v in rules["payouts"].values()
            )
        if game == "coin":
            assert numeric(rules["multiplier"])
        if game == "slots":
            sy = rules["symbols"]
            assert 2 <= len(sy) <= 12 and positive_weights(sy)
            assert all(
                isinstance(s["label"], str)
                and 1 <= len(s["label"]) <= 12
                and numeric(s["multiplier"])
                for s in sy
            ) and numeric(rules["pair_multiplier"])
        if game == "dice":
            assert set(rules["payouts"]) == {"low", "seven", "high"} and set(
                rules["exact_payouts"]
            ) == {str(s) for s in range(2, 13)}
            assert (
                all(
                    numeric(v)
                    for v in [
                        *rules["payouts"].values(),
                        *rules["exact_payouts"].values(),
                    ]
                )
                and type(rules["exact_enabled"]) is bool
            )
        if game == "blackjack":
            assert (
                numeric(rules["blackjack_profit"], 0, 10)
                and type(rules["hit_soft_17"]) is bool
            )
        if game == "higher-lower":
            assert (
                rules["ace"] == "high"
                and rules["tie"] in ["push", "lose"]
                and numeric(rules["edge"], 0, 0.25)
            )
        if game == "lucky-wheel":
            import re

            sy = rules["sectors"]
            assert 8 <= len(sy) <= 12
            assert all(
                type(s["active"]) is bool
                and isinstance(s["label"], str)
                and 1 <= len(s["label"]) <= 40
                and re.fullmatch(r"#[0-9A-Fa-f]{6}", s["color"])
                and numeric(s["multiplier"])
                for s in sy
            )
            assert positive_weights([s for s in sy if s["active"]])
    except (KeyError, TypeError, AssertionError, AttributeError):
        raise ValidationError("Некорректная конфигурация игры")


def validate_stake(value, config):
    try:
        if type(value) not in (int, str):
            raise ValueError()
        amount = int(value)
        if str(amount) != str(value):
            raise ValueError()
    except (ValueError, TypeError):
        raise ValidationError("Ставка должна быть целым числом")
    if not config.min_bet <= amount <= config.max_bet:
        raise ValidationError(f"Ставка: {config.min_bet}–{config.max_bet}")
    return money(amount)


def settle(round, wallet, payout):
    if round.status != "active":
        raise ValidationError("Раунд уже завершён")
    round.payout = money(payout)
    round.status = "completed"
    move(wallet, round.payout, "payout", f"round:{round.pk}:payout", actor=round.user)
    round.save()


def public_round(round):
    return {
        "id": round.pk,
        "game": round.game,
        "status": round.status,
        "stake": str(round.stake),
        "payout": str(round.payout),
        "profit": str(round.payout - round.stake)
        if round.status == "completed"
        else None,
        "result": round.result,
        "rules": round.rules_snapshot,
        "created_at": round.created_at.isoformat(),
    }


def update_blackjack_result(round):
    state = round.private_state
    complete = round.status == "completed"
    dealer = state["dealer"] if complete else state["dealer"][:1]
    round.result = {
        "player": state["player"],
        "dealer": dealer,
        "hidden": not complete,
        "player_score": score(state["player"])[0],
        "dealer_score": score(dealer)[0],
    }


def create_round(campaign, user, game, payload):
    if not campaign.settings.get("casino_enabled", True):
        raise ValidationError("Казино отключено мастером")
    session = GameSession.objects.filter(campaign=campaign, status="active").first()
    if session and not session.settings.get("casino_enabled", True):
        raise ValidationError("Казино отключено в этой сессии")
    ensure_configs(campaign)
    if game not in GAMES:
        raise ValidationError("Неизвестная игра")
    cfg = CasinoConfiguration.objects.get(campaign=campaign, game=game)
    if not cfg.enabled:
        raise ValidationError("Игра отключена")
    if CasinoRound.objects.filter(
        campaign=campaign, user=user, status="active"
    ).exists():
        raise ValidationError("Завершите предыдущий карточный раунд")
    rules = deepcopy(cfg.rules)
    validate_rules(game, rules)
    bets = []
    if game == "roulette":
        bets = payload.get("bets", [])
        if not isinstance(bets, list) or not 1 <= len(bets) <= 40:
            raise ValidationError("Укажите 1–40 ставок")
        for b in bets:
            if (
                not isinstance(b, dict)
                or not isinstance(b.get("kind"), str)
                or b.get("kind") not in rules["payouts"]
            ):
                raise ValidationError("Некорректный вид ставки")
            if b["kind"] == "number" and (
                type(b.get("value")) is not int or not 0 <= b["value"] <= 36
            ):
                raise ValidationError("Число: 0–36")
            if b["kind"] == "dozen" and (
                type(b.get("value")) is not int or b.get("value") not in [1, 2, 3]
            ):
                raise ValidationError("Дюжина: 1–3")
            b["amount"] = str(validate_stake(b.get("amount"), cfg))
            if b["kind"] not in ["number", "dozen"]:
                b["value"] = None
        # Sum can include decimal strings produced above; total must be whole tokens.
        stake = validate_stake(int(sum(Decimal(b["amount"]) for b in bets)), cfg)
    else:
        stake = validate_stake(payload.get("stake"), cfg)
    choice = payload.get("choice")
    if game == "coin" and choice not in ["heads", "tails"]:
        raise ValidationError("Выберите сторону")
    if game == "dice" and choice not in ["low", "seven", "high"]:
        if not rules["exact_enabled"] or str(choice) not in rules["exact_payouts"]:
            raise ValidationError("Некорректная сумма")
    wallet = wallet_for(campaign, user)
    round = CasinoRound.objects.create(
        campaign=campaign,
        user=user,
        session=session,
        game=game,
        stake=stake,
        rules_snapshot={"version": cfg.version, **rules},
    )
    move(wallet, -stake, "stake", f"round:{round.pk}:stake", actor=user)
    if game == "blackjack":
        cards = deck()
        round.private_state = {
            "deck": cards[4:],
            "player": cards[:2],
            "dealer": cards[2:4],
        }
        if score(cards[:2])[0] == 21 or score(cards[2:4])[0] == 21:
            settle(round, wallet, blackjack_gross(cards[:2], cards[2:4], stake, rules))
        update_blackjack_result(round)
        round.save()
        return public_round(round)
    if game == "higher-lower":
        cards = deck()
        current = cards.pop()
        round.private_state = {"deck": cards, "current": current}
        round.result = {
            "current": current,
            "odds": {
                c: higher_odds(current, cards, c, rules) for c in ["higher", "lower"]
            },
        }
        round.save()
        return public_round(round)
    payout = money(0)
    if game == "roulette":
        number = secrets.randbelow(37)
        wins = [b for b in bets if roulette_win(number, b["kind"], b.get("value"))]
        payout = sum(
            (gross(Decimal(b["amount"]), rules["payouts"][b["kind"]]) for b in wins),
            money(0),
        )
        round.result = {
            "number": number,
            "color": "green" if number == 0 else "red" if number in RED else "black",
            "bets": bets,
            "winning_bets": wins,
            "wheel_index": WHEEL_ORDER.index(number),
        }
    elif game == "slots":
        symbols = rules["symbols"]
        indices = [
            weighted(list(range(len(symbols))), [s["weight"] for s in symbols])
            for _ in range(3)
        ]
        m = (
            symbols[indices[0]]["multiplier"]
            if len(set(indices)) == 1
            else rules["pair_multiplier"]
            if len(set(indices)) == 2
            else 0
        )
        payout = gross(stake, m)
        round.result = {
            "indices": indices,
            "symbols": [symbols[i]["label"] for i in indices],
            "multiplier": m,
        }
    elif game == "dice":
        values = [secrets.randbelow(6) + 1, secrets.randbelow(6) + 1]
        total = sum(values)
        won = dice_win(total, str(choice))
        m = rules["payouts"].get(
            str(choice), rules["exact_payouts"].get(str(choice), 0)
        )
        payout = gross(stake, m) if won else money(0)
        round.result = {"dice": values, "total": total, "choice": choice, "won": won}
    elif game == "coin":
        side = secrets.choice(["heads", "tails"])
        won = choice == side
        payout = gross(stake, rules["multiplier"]) if won else money(0)
        round.result = {"side": side, "choice": choice, "won": won}
    elif game == "lucky-wheel":
        sectors = rules["sectors"]
        indices = [i for i, s in enumerate(sectors) if s["active"]]
        index = weighted(indices, [sectors[i]["weight"] for i in indices])
        selected = sectors[index]
        payout = gross(stake, selected["multiplier"])
        round.result = {"index": index, "sector": selected}
    settle(round, wallet, payout)
    return public_round(round)


def round_action(campaign, user, round_id, payload):
    try:
        round = CasinoRound.objects.select_for_update().get(
            pk=round_id, campaign=campaign, user=user
        )
    except CasinoRound.DoesNotExist:
        raise ValidationError("Раунд не найден")
    if round.status != "active":
        raise ValidationError("Раунд завершён")
    action = payload.get("action")
    rules = round.rules_snapshot
    state = round.private_state
    wallet = wallet_for(campaign, user)
    if round.game == "blackjack":
        if action not in ["hit", "stand", "double"]:
            raise ValidationError("Действие недоступно")
        if action == "double":
            if len(state["player"]) != 2:
                raise ValidationError("Удвоение доступно только сразу после раздачи")
            move(wallet, -round.stake, "stake", f"round:{round.pk}:double", actor=user)
            round.stake *= 2
        if action in ["hit", "double"]:
            state["player"].append(state["deck"].pop())
        if score(state["player"])[0] >= 21 or action in ["stand", "double"]:
            if score(state["player"])[0] <= 21:
                while True:
                    total, soft = score(state["dealer"])
                    if (
                        total > 17
                        or total == 17
                        and not (soft and rules["hit_soft_17"])
                    ):
                        break
                    state["dealer"].append(state["deck"].pop())
            settle(
                round,
                wallet,
                blackjack_gross(state["player"], state["dealer"], round.stake, rules),
            )
        update_blackjack_result(round)
    elif round.game == "higher-lower":
        if action not in ["higher", "lower"]:
            raise ValidationError("Выберите выше или ниже")
        odds = higher_odds(state["current"], state["deck"], action, rules)
        if not odds["win_probability"]:
            raise ValidationError("Выбранное направление невозможно")
        nxt = state["deck"].pop()
        current = state["current"]
        won = (
            nxt["rank"] > current["rank"]
            if action == "higher"
            else nxt["rank"] < current["rank"]
        )
        tie = nxt["rank"] == current["rank"]
        payout = (
            money(round.stake)
            if tie and rules["tie"] == "push"
            else gross(round.stake, odds["gross_multiplier"])
            if won
            else money(0)
        )
        round.result = {
            "current": current,
            "next": nxt,
            "choice": action,
            "won": won,
            "tie": tie,
            "odds": odds,
        }
        settle(round, wallet, payout)
    else:
        raise ValidationError("Одноэтапная игра не поддерживает действия")
    CasinoRoundAction.objects.create(round=round, action=action, payload={})
    round.save()
    return public_round(round)
