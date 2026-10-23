"""Pure deterministic evaluators; payouts are GROSS, including the stake."""

from collections import Counter
from decimal import Decimal, ROUND_DOWN
from fractions import Fraction
from itertools import product
import secrets

RED = {1, 3, 5, 7, 9, 12, 14, 16, 18, 19, 21, 23, 25, 27, 30, 32, 34, 36}
WHEEL_ORDER = [
    0,
    32,
    15,
    19,
    4,
    21,
    2,
    25,
    17,
    34,
    6,
    27,
    13,
    36,
    11,
    30,
    8,
    23,
    10,
    5,
    24,
    16,
    33,
    1,
    20,
    14,
    31,
    9,
    22,
    18,
    29,
    7,
    28,
    12,
    35,
    3,
    26,
]
GAMES = [
    "roulette",
    "slots",
    "blackjack",
    "dice",
    "coin",
    "higher-lower",
    "lucky-wheel",
]
DEFAULT_RULES = {
    "roulette": {
        "payouts": {
            "number": 36,
            "red": 2,
            "black": 2,
            "even": 2,
            "odd": 2,
            "low": 2,
            "high": 2,
            "dozen": 3,
        }
    },
    "slots": {
        "symbols": [
            {"label": "◆", "weight": 30, "multiplier": 3},
            {"label": "✦", "weight": 25, "multiplier": 5},
            {"label": "●", "weight": 20, "multiplier": 8},
            {"label": "✿", "weight": 15, "multiplier": 15},
            {"label": "7", "weight": 10, "multiplier": 50},
        ],
        "pair_multiplier": 1,
    },
    "blackjack": {"blackjack_profit": 1.5, "hit_soft_17": False},
    "dice": {
        "exact_enabled": True,
        "payouts": {"low": 2.2, "seven": 5.5, "high": 2.2},
        "exact_payouts": {
            str(s): round(34 / (6 - abs(7 - s)), 2) for s in range(2, 13)
        },
    },
    "coin": {"multiplier": 1.9},
    "higher-lower": {"ace": "high", "tie": "push", "edge": 0.05},
    "lucky-wheel": {
        "sectors": [
            {
                "label": label,
                "color": color,
                "multiplier": m,
                "weight": w,
                "active": True,
            }
            for label, color, m, w in [
                ("Мимо", "#969BAB", 0, 25),
                ("Ещё раз", "#B0A9EF", 1, 20),
                ("×1.2", "#80CBBB", 1.2, 15),
                ("×1.5", "#695CF5", 1.5, 12),
                ("×2", "#9085FF", 2, 10),
                ("×0", "#969BAB", 0, 10),
                ("×3", "#24A88A", 3, 5),
                ("×5", "#DCA85C", 5, 3),
            ]
        ]
    },
}


def money(value):
    return Decimal(str(value)).quantize(Decimal(".01"), rounding=ROUND_DOWN)


def gross(stake, multiplier):
    return money(Decimal(stake) * Decimal(str(multiplier)))


def weighted(items, weights):
    total = sum(weights)
    if total <= 0:
        raise ValueError("Нет доступных исходов")
    pick = secrets.randbelow(total)
    for item, w in zip(items, weights):
        if pick < w:
            return item
        pick -= w
    raise AssertionError("Invalid weights")


def roulette_win(n, kind, value=None):
    if kind == "number":
        return n == int(value)
    if n == 0:
        return False
    return {
        "red": n in RED,
        "black": n not in RED,
        "even": n % 2 == 0,
        "odd": n % 2 == 1,
        "low": 1 <= n <= 18,
        "high": 19 <= n <= 36,
        "dozen": (n - 1) // 12 + 1 == int(value or 0),
    }.get(kind, False)


def dice_win(total, choice):
    return (
        total <= 6
        if choice == "low"
        else total == 7
        if choice == "seven"
        else total >= 8
        if choice == "high"
        else total == int(choice)
    )


def deck():
    cards = [{"rank": r, "suit": s} for s in ["♠", "♥", "♦", "♣"] for r in range(2, 15)]
    secrets.SystemRandom().shuffle(cards)
    return cards


def score(cards):
    total = sum(11 if c["rank"] == 14 else min(c["rank"], 10) for c in cards)
    aces = sum(c["rank"] == 14 for c in cards)
    while total > 21 and aces:
        total -= 10
        aces -= 1
    return total, bool(aces)


def blackjack_gross(player, dealer, stake, rules):
    p, _ = score(player)
    d, _ = score(dealer)
    pn = p == 21 and len(player) == 2
    dn = d == 21 and len(dealer) == 2
    if p > 21:
        return money(0)
    if pn and dn:
        return money(stake)
    if dn:
        return money(0)
    if pn:
        return gross(stake, Decimal("1") + Decimal(str(rules["blackjack_profit"])))
    if d > 21 or p > d:
        return gross(stake, 2)
    if p == d:
        return money(stake)
    return money(0)


def higher_odds(current, cards, choice, rules):
    wins = sum(
        c["rank"] > current["rank"]
        if choice == "higher"
        else c["rank"] < current["rank"]
        for c in cards
    )
    ties = sum(c["rank"] == current["rank"] for c in cards)
    total = len(cards)
    if not wins:
        return {
            "win_probability": 0,
            "tie_probability": ties / total,
            "gross_multiplier": 0,
            "rtp": 0,
        }
    push = ties if rules["tie"] == "push" else 0
    multiplier = (total - push) / wins * (1 - rules["edge"])
    return {
        "win_probability": wins / total,
        "tie_probability": ties / total,
        "gross_multiplier": multiplier,
        "rtp": wins / total * multiplier + push / total,
    }


def statistics(game, rules):
    """Exact combinatorics, before cent rounding. Blackjack needs a strategy model."""
    if game == "roulette":
        return {
            "rtp": {
                k: (1 if k == "number" else 12 if k == "dozen" else 18) / 37 * v
                for k, v in rules["payouts"].items()
            },
            "zero_probability": 1 / 37,
        }
    if game == "coin":
        return {
            "rtp": 0.5 * rules["multiplier"],
            "probabilities": {"heads": 0.5, "tails": 0.5},
        }
    if game == "dice":
        counts = Counter(a + b for a, b in product(range(1, 7), repeat=2))
        return {
            "probabilities": {str(k): v / 36 for k, v in sorted(counts.items())},
            "rtp": {
                **{
                    k: (6 if k == "seven" else 15) / 36 * v
                    for k, v in rules["payouts"].items()
                },
                **{
                    k: counts[int(k)] / 36 * v
                    for k, v in rules["exact_payouts"].items()
                },
            },
        }
    if game == "lucky-wheel":
        sectors = [s for s in rules["sectors"] if s["active"]]
        total = sum(s["weight"] for s in sectors)
        return {
            "rtp": sum(s["weight"] * s["multiplier"] for s in sectors) / total,
            "probabilities": [s["weight"] / total for s in sectors],
            "visualization": "Equal sectors visualize a weighted server draw. Published weights determine probability.",
        }
    if game == "slots":
        symbols = rules["symbols"]
        total = sum(s["weight"] for s in symbols)
        rtp = 0
        for combo in product(range(len(symbols)), repeat=3):
            p = 1
            for i in combo:
                p *= symbols[i]["weight"] / total
            multiplier = (
                symbols[combo[0]]["multiplier"]
                if len(set(combo)) == 1
                else rules["pair_multiplier"]
                if len(set(combo)) == 2
                else 0
            )
            rtp += p * multiplier
        return {
            "rtp": rtp,
            "symbol_probabilities": [s["weight"] / total for s in symbols],
        }
    if game == "blackjack":
        return {
            "rtp": None,
            "note": "RTP depends on player strategy. One shuffled 52-card deck per round, no split or insurance, dealer peeks for natural blackjack.",
        }
    return {
        "rtp": None,
        "note": "Ace high (14); probabilities and gross multiplier are calculated from the remaining 51 cards for each visible card. Ties follow campaign rules.",
    }
