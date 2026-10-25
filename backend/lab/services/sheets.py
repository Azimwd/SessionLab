from django.shortcuts import get_object_or_404
from rest_framework.exceptions import PermissionDenied, ValidationError

from lab.api.common import is_dm
from lab.models import (
    Character,
    CharacterAbility,
    CharacterSheet,
    GameSession,
    InitiativeEntry,
    InitiativeTracker,
    RoomEvent,
)

from .dice import d20, roll_formula

ABILITIES = {
    "str": "Сила",
    "dex": "Ловкость",
    "con": "Телосложение",
    "int": "Интеллект",
    "wis": "Мудрость",
    "cha": "Харизма",
}
SKILLS = {
    "acrobatics": ("Акробатика", "dex"),
    "animal_handling": ("Уход за животными", "wis"),
    "arcana": ("Магия", "int"),
    "athletics": ("Атлетика", "str"),
    "deception": ("Обман", "cha"),
    "history": ("История", "int"),
    "insight": ("Проницательность", "wis"),
    "intimidation": ("Запугивание", "cha"),
    "investigation": ("Анализ", "int"),
    "medicine": ("Медицина", "wis"),
    "nature": ("Природа", "int"),
    "perception": ("Внимательность", "wis"),
    "performance": ("Выступление", "cha"),
    "persuasion": ("Убеждение", "cha"),
    "religion": ("Религия", "int"),
    "sleight_of_hand": ("Ловкость рук", "dex"),
    "stealth": ("Скрытность", "dex"),
    "survival": ("Выживание", "wis"),
}
CONDITIONS = [
    "Ослеплён",
    "Очарован",
    "Оглох",
    "Испуган",
    "Схвачен",
    "Недееспособен",
    "Невидим",
    "Парализован",
    "Окаменел",
    "Отравлен",
    "Сбит с ног",
    "Опутан",
    "Ошеломлён",
    "Без сознания",
    "Концентрация",
]


def controlled_character(campaign, user, pk):
    if type(pk) not in [str, int] or not str(pk).isdigit():
        raise ValidationError("Выберите персонажа")
    char = get_object_or_404(Character, campaign=campaign, pk=int(pk), active=True)
    if char.owner_id != user.pk and not is_dm(campaign, user):
        raise PermissionDenied("Управлять листом может владелец или мастер")
    return char


def sheet_for(char):
    return CharacterSheet.objects.get_or_create(character=char)[0]


def modifier(sheet, key):
    if key not in ABILITIES:
        raise ValidationError("Неизвестная характеристика")
    return (sheet.abilities[key] - 10) // 2


def proficiency(sheet):
    return (
        sheet.proficiency_override
        if sheet.proficiency_override is not None
        else 2 + (sheet.character.level - 1) // 4
    )


def computed(sheet):
    pb = proficiency(sheet)
    mods = {k: modifier(sheet, k) for k in ABILITIES}
    return {
        "modifiers": mods,
        "proficiency": pb,
        "skills": {
            k: mods[ability] + pb * sheet.skills.get(k, 0)
            for k, (_, ability) in SKILLS.items()
        },
        "saves": {k: mods[k] + (pb if k in sheet.saves else 0) for k in ABILITIES},
        "initiative": mods["dex"] + sheet.initiative_bonus,
        "spell_attack": mods[sheet.spell_ability] + pb,
        "spell_dc": 8 + mods[sheet.spell_ability] + pb,
    }


def active_session(campaign):
    session = GameSession.objects.filter(campaign=campaign, status="active").first()
    if not session:
        raise ValidationError("Мастер должен начать игровую сессию")
    return session


def event(campaign, session, actor, character, kind, payload, visibility="public"):
    if visibility not in ["public", "dm"]:
        raise ValidationError("Неизвестная видимость")
    return RoomEvent.objects.create(
        campaign=campaign,
        session=session,
        actor=actor,
        character=character,
        kind=kind,
        visibility=visibility,
        payload={"character_name": character.name if character else "", **payload},
    )


def perform_roll(campaign, user, data):
    if (
        data.get("character") is None
        and data.get("kind", "custom") == "custom"
        and is_dm(campaign, user)
    ):
        if data.get("mode", "normal") != "normal":
            raise ValidationError("Для произвольной формулы доступен обычный бросок")
        return event(
            campaign,
            active_session(campaign),
            user,
            None,
            "roll",
            {
                "label": "Бросок мастера",
                "roll": roll_formula(data.get("formula", "1d20")),
            },
            data.get("visibility", "public"),
        )
    char = controlled_character(campaign, user, data.get("character"))
    sheet = sheet_for(char)
    session = active_session(campaign)
    kind, key, mode = (
        data.get("kind", "custom"),
        data.get("key", ""),
        data.get("mode", "normal"),
    )
    stats = computed(sheet)
    if kind == "ability":
        result, label = d20(modifier(sheet, key), mode), ABILITIES[key]
    elif kind == "save":
        if key not in ABILITIES:
            raise ValidationError("Неизвестный спасбросок")
        result, label = d20(stats["saves"][key], mode), "Спасбросок: " + ABILITIES[key]
    elif kind == "skill":
        if key not in SKILLS:
            raise ValidationError("Неизвестный навык")
        result, label = d20(stats["skills"][key], mode), SKILLS[key][0]
    elif kind == "initiative":
        tracker, _ = InitiativeTracker.objects.get_or_create(session=session)
        if tracker.running or tracker.entries.filter(character=char).exists():
            raise ValidationError(
                "Инициатива уже брошена или бой начат. Для переброса обратитесь к мастеру."
            )
        result, label = d20(stats["initiative"], mode), "Инициатива"
        InitiativeEntry.objects.create(
            tracker=tracker,
            character=char,
            player_slot=char if char.kind == 'player' else None,
            name=char.name,
            initiative=result["total"],
            dexterity=stats["modifiers"]["dex"],
        )
        tracker.version += 1
        tracker.save()
    elif kind == "custom":
        if mode != "normal":
            raise ValidationError("Для произвольной формулы доступен обычный бросок")
        result, label = roll_formula(data.get("formula", "1d20")), "Бросок кубиков"
    elif kind == "death":
        if (
            sheet.hp_current != 0
            or sheet.death_failures >= 3
            or sheet.death_successes >= 3
        ):
            raise ValidationError("Спасбросок от смерти сейчас недоступен")
        result, label = d20(0, mode), "Спасбросок от смерти"
        if result["chosen"] == 20:
            sheet.hp_current, sheet.death_successes, sheet.death_failures = 1, 0, 0
        elif result["chosen"] >= 10:
            sheet.death_successes = min(3, sheet.death_successes + 1)
        else:
            sheet.death_failures = min(
                3, sheet.death_failures + (2 if result["chosen"] == 1 else 1)
            )
        sheet.version += 1
        sheet.save()
    else:
        raise ValidationError("Неизвестный тип броска")
    return event(
        campaign,
        session,
        user,
        char,
        "roll",
        {"label": label, "roll": result},
        data.get("visibility", "public"),
    )


def use_ability(campaign, user, pk, data):
    ability = get_object_or_404(
        CharacterAbility, pk=pk, character__campaign=campaign, active=True
    )
    char = controlled_character(campaign, user, ability.character_id)
    session, sheet = active_session(campaign), sheet_for(char)
    level = data.get("slot_level", ability.level)
    if type(level) is not int or not ability.level <= level <= 9:
        raise ValidationError("Некорректный уровень ячейки")
    if ability.kind == "attack" or ability.level == 0:
        if level != ability.level:
            raise ValidationError("Эта способность не использует повышенную ячейку")
    elif ability.kind == "spell":
        if level > ability.level and not ability.upcast_allowed:
            raise ValidationError("Правила этого заклинания не разрешают повышенную ячейку")
        slot = sheet.slots[str(level)]
        if slot["used"] >= slot["max"]:
            raise ValidationError("Нет свободных ячеек этого уровня")
        sheet.slots = {**sheet.slots, str(level): {**slot, "used": slot["used"] + 1}}
    bonus = (
        modifier(sheet, ability.ability)
        + (proficiency(sheet) if ability.proficient else 0)
        + ability.bonus
    )
    payload = {
        "label": ability.name,
        "kind": ability.kind,
        "description": ability.description,
        "ability_id": ability.pk,
        "ability_version": ability.version,
        "slot_level": level,
        "damage_type": ability.damage_type,
        "resolution": ability.resolution,
        "concentration": ability.concentration,
    }
    if ability.catalog_entry_id:
        # Snapshot rules before a future seed or administrator edit changes them.
        payload["verified_rules"] = bool(ability.catalog_entry.template.get("verified"))
        payload["components"] = ability.catalog_entry.template.get("components", "")
        if not payload["verified_rules"]:
            payload["adjudication"] = "Эффект требует сверки с правилами и решения мастера. Автоматические броски этой записи не подтверждены."
    steps = (
        sum(char.level >= n for n in [5, 11, 17])
        if ability.kind == "spell" and ability.level == 0 and ability.cantrip_scaling
        else level - ability.level
    )
    count = ability.roll_count + steps * ability.upcast_count
    if count > 20:
        raise ValidationError("Слишком много отдельных бросков: максимум 20")
    parts = []
    for index in range(count):
        part = {}
        critical = False
        if ability.resolution == "attack":
            part["roll"] = d20(bonus, data.get("mode", "normal"))
            critical = part["roll"]["chosen"] == 20
        elif ability.resolution == "save":
            part["save"] = {"ability": ability.save_ability, "dc": 8 + bonus}
        if ability.dice:
            part["damage"] = roll_formula(ability.dice, critical=critical)
            if ability.add_modifier:
                mod = modifier(sheet, ability.ability)
                part["damage"]["total"] += mod
                part["damage"]["ability_modifier"] = mod
            if steps and ability.upcast_dice:
                extras = [
                    roll_formula(ability.upcast_dice, critical=critical)
                    for _ in range(steps)
                ]
                part["upcast"] = extras
                part["damage"]["total"] += sum(r["total"] for r in extras)
        parts.append(part)
    if len(parts) == 1:
        payload.update(parts[0])
    else:
        payload["parts"] = parts
        payload["total_damage"] = sum(
            p.get("damage", {}).get("total", 0) for p in parts
        )
    if ability.resolution == 'save' and ability.catalog_entry_id and ability.catalog_entry.template.get('save_half'):
        for part in parts:
            if 'damage' in part:
                part['save']['success_damage'] = part['damage']['total'] // 2
        if len(parts) == 1 and parts[0].get('save'):
            payload['save'] = parts[0]['save']
    if ability.concentration and "Концентрация" not in sheet.conditions:
        sheet.conditions = [*sheet.conditions, "Концентрация"]
    sheet.version += 1
    sheet.save()
    return event(
        campaign,
        session,
        user,
        char,
        "ability",
        payload,
        data.get("visibility", "public"),
    )
