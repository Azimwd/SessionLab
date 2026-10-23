from collections import Counter
from itertools import product
from decimal import Decimal
import pytest
from lab.services.casino_math import *
from lab.services.casino import validate_rules
from rest_framework.exceptions import ValidationError


def test_roulette_european():
    assert (
        len(WHEEL_ORDER) == 37 and set(WHEEL_ORDER) == set(range(37)) and len(RED) == 18
    )
    for kind in ["red", "black", "even", "odd", "low", "high"]:
        assert sum(roulette_win(n, kind) for n in range(37)) == 18
        assert not roulette_win(0, kind)
    for d in [1, 2, 3]:
        assert sum(roulette_win(n, "dozen", d) for n in range(37)) == 12
    assert sum(roulette_win(n, "number", 0) for n in range(37)) == 1
    assert statistics("roulette", DEFAULT_RULES["roulette"])["rtp"][
        "red"
    ] == pytest.approx(36 / 37)


def test_dice_exact_distribution():
    counts = Counter(sum(t) for t in product(range(1, 7), repeat=2))
    assert [counts[n] for n in range(2, 13)] == [1, 2, 3, 4, 5, 6, 5, 4, 3, 2, 1]
    for choice, expected in [("low", 15), ("seven", 6), ("high", 15)]:
        assert (
            sum(dice_win(sum(t), choice) for t in product(range(1, 7), repeat=2))
            == expected
        )


def cards(*ranks):
    return [{"rank": r, "suit": "♠"} for r in ranks]


@pytest.mark.parametrize(
    "ranks,total,soft",
    [
        ([14, 14, 9], 21, True),
        ([14, 6], 17, True),
        ([14, 6, 10], 17, False),
        ([14, 14, 14, 10], 13, False),
        ([10, 8, 6], 24, False),
    ],
)
def test_blackjack_score(ranks, total, soft):
    assert score(cards(*ranks)) == (total, soft)


@pytest.mark.parametrize(
    "p,d,expected",
    [
        ([14, 10], [9, 10], "25.00"),
        ([14, 10], [14, 10], "10.00"),
        ([10, 8], [14, 10], "0.00"),
        ([10, 8], [10, 7], "20.00"),
        ([10, 8], [10, 8], "10.00"),
        ([10, 9, 4], [10, 9, 5], "0.00"),
    ],
)
def test_blackjack_payouts(p, d, expected):
    assert blackjack_gross(
        cards(*p), cards(*d), money(10), DEFAULT_RULES["blackjack"]
    ) == Decimal(expected)


def test_coin_rtp():
    assert statistics("coin", DEFAULT_RULES["coin"]) == {
        "rtp": 0.95,
        "probabilities": {"heads": 0.5, "tails": 0.5},
    }


def test_slot_exhaustive_rtp():
    rules = DEFAULT_RULES["slots"]
    m = statistics("slots", rules)
    assert sum(m["symbol_probabilities"]) == pytest.approx(1)
    expected = sum(
        (s["weight"] / 100) ** 3 * s["multiplier"] for s in rules["symbols"]
    ) + sum(
        3 * (s["weight"] / 100) ** 2 * (1 - s["weight"] / 100) for s in rules["symbols"]
    )
    assert m["rtp"] == pytest.approx(expected)


def test_higher_lower_actual_deck():
    current = {"rank": 8, "suit": "♠"}
    left = [c for c in deck() if c != current]
    rules = DEFAULT_RULES["higher-lower"]
    above = higher_odds(current, left, "higher", rules)
    below = higher_odds(current, left, "lower", rules)
    assert (
        above["win_probability"] == 24 / 51
        and below["win_probability"] == 24 / 51
        and above["tie_probability"] == 3 / 51
    )
    assert above["rtp"] == pytest.approx(0.95 + 0.05 * 3 / 51)
    assert higher_odds({"rank": 14}, left, "higher", rules)["win_probability"] == 0


def test_lucky_wheel_weights():
    r = DEFAULT_RULES["lucky-wheel"]
    s = statistics("lucky-wheel", r)
    assert sum(s["probabilities"]) == pytest.approx(1)
    assert s["rtp"] == pytest.approx(
        sum(a["weight"] * a["multiplier"] for a in r["sectors"]) / 100
    )


def test_weighted_boundaries(monkeypatch):
    monkeypatch.setattr(secrets, "randbelow", lambda total: 0)
    assert weighted(["a", "b"], [0, 5]) == "b"
    monkeypatch.setattr(secrets, "randbelow", lambda total: total - 1)
    assert weighted(["a", "b"], [2, 3]) == "b"
    with pytest.raises(ValueError):
        weighted(["a"], [0])


def test_weighted_statistical_sanity():
    assert 14500 < sum(weighted([0, 1], [1, 3]) for _ in range(20000)) < 15500


@pytest.mark.parametrize("game", GAMES)
def test_default_configs_valid(game):
    validate_rules(game, DEFAULT_RULES[game])


def test_invalid_config():
    with pytest.raises(ValidationError):
        validate_rules("coin", {"multiplier": float("nan")})
