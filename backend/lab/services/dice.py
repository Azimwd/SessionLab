"""Bounded dice syntax. No eval, no client-supplied outcomes."""

import re
import secrets

from rest_framework.exceptions import ValidationError

DICE = {4, 6, 8, 10, 12, 20, 100}
TERM = re.compile(r"([+-]?)(?:(\d*)d(\d+)|(\d+))")


def parse_formula(formula):
    if not isinstance(formula, str) or len(formula) > 80:
        raise ValidationError("Формула: не более 80 символов")
    formula = formula.lower().replace(" ", "")
    if not formula:
        raise ValidationError("Укажите формулу, например 2d6+3")
    pos, terms, dice_count = 0, [], 0
    for match in TERM.finditer(formula):
        if match.start() != pos or (pos and not match[1]):
            raise ValidationError("Используйте NdM, целые числа, + и −")
        pos = match.end()
        sign = -1 if match[1] == "-" else 1
        if match[3]:
            count, sides = int(match[2] or 1), int(match[3])
            if sides not in DICE or not 1 <= count <= 50:
                raise ValidationError(
                    "Доступны d4/d6/d8/d10/d12/d20/d100, до 50 кубиков"
                )
            dice_count += count
            terms.append((sign, count, sides))
        else:
            number = int(match[4])
            if number > 10000:
                raise ValidationError("Модификатор слишком велик")
            terms.append((sign, number, 0))
    if pos != len(formula) or not terms or dice_count > 50 or len(terms) > 20:
        raise ValidationError("Некорректная или слишком длинная формула")
    return terms


def roll_formula(formula, critical=False):
    terms = parse_formula(formula)
    details, total = [], 0
    for sign, count, sides in terms:
        values = (
            [
                secrets.randbelow(sides) + 1
                for _ in range(count * (2 if critical else 1))
            ]
            if sides
            else []
        )
        subtotal = sign * (sum(values) if sides else count)
        total += subtotal
        details.append(
            {
                "sign": sign,
                "sides": sides,
                "values": values,
                "constant": count if not sides else 0,
            }
        )
    return {"formula": formula, "terms": details, "total": total, "critical": critical}


def d20(bonus=0, mode="normal"):
    if mode not in ["normal", "advantage", "disadvantage"]:
        raise ValidationError("Неизвестный режим броска")
    values = [secrets.randbelow(20) + 1 for _ in range(1 if mode == "normal" else 2)]
    chosen = min(values) if mode == "disadvantage" else max(values)
    return {
        "formula": f"1d20{bonus:+d}",
        "values": values,
        "chosen": chosen,
        "modifier": bonus,
        "total": chosen + bonus,
        "mode": mode,
    }
