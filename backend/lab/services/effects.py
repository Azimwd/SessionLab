from django.db.models import Q
from rest_framework.exceptions import ValidationError
from lab.models import *
from .casino_math import weighted


def snapshot(obj):
    fields = (
        [
            "id",
            "code",
            "title",
            "description",
            "mechanic",
            "category",
            "rarity",
            "duration",
            "use_limit",
            "requires_approval",
            "mechanic_type",
            "parameters",
            "color",
            "icon",
            "animation",
            "homebrew",
            "activation",
            "secret",
        ]
        if isinstance(obj, EffectDefinition)
        else ["id", "code", "title", "description", "category", "difficulty", "reward"]
    )
    return {k: getattr(obj, k) for k in fields}


def available(campaign):
    qs = EffectDefinition.objects.filter(
        Q(campaign=campaign) | Q(campaign=None),
        active=True,
        archived=False,
        weight__gt=0,
    )
    pools = EffectPool.objects.filter(campaign=campaign, active=True)
    if pools.exists():
        entries = EffectPoolEntry.objects.filter(pool__in=pools, weight__gt=0)
        weights = {}
        for entry in entries:
            weights[entry.effect_id] = weights.get(entry.effect_id, 0) + entry.weight
        return [(e, weights[e.pk]) for e in qs.filter(pk__in=weights)]
    return [(e, e.weight) for e in qs]


def draw(campaign, candidates, settings):
    weights = settings.get("category_weights", campaign.settings["category_weights"])
    categories = [
        c
        for c in ["gift", "complication", "paradox"]
        if any(e.category == c for e, w in candidates) and weights.get(c, 0) > 0
    ]
    if not categories:
        raise ValidationError("Нет доступных карточек с положительным весом")
    category = weighted(categories, [weights[c] for c in categories])
    filtered = [(e, w) for e, w in candidates if e.category == category]
    return weighted([e for e, w in filtered], [w for e, w in filtered])


def roll_effect(session, character, definition=None, bonus=False):
    if session.status != "active":
        raise ValidationError("Сессия не активна")
    settings = {**session.campaign.settings, **session.settings}
    if (
        not bonus
        and EffectRoll.objects.filter(
            session=session, issued_to=character, bonus=False
        ).count()
        >= settings["effect_limit"]
    ):
        raise ValidationError("Лимит эффектов на эту сессию исчерпан")
    grant = (
        ChoiceGrant.objects.filter(character=character, consumed_by=None)
        .order_by("pk")
        .first()
    )
    if grant and definition is None:
        candidates = [
            (e, w)
            for e, w in available(session.campaign)
            if e.mechanic_type != "choice3"
        ]
        if len(candidates) < 3:
            raise ValidationError("Для выбора нужны три доступных эффекта")
        chosen = []
        for _ in range(3):
            e = draw(session.campaign, candidates, settings)
            chosen.append(snapshot(e))
            candidates = [(o, w) for o, w in candidates if o.pk != e.pk]
        roll = EffectRoll.objects.create(
            session=session,
            character=character,
            issued_to=character,
            status="rolled",
            choices=chosen,
            bonus=bonus,
        )
        grant.consumed_by = roll
        grant.save()
        return roll
    effect = definition or draw(session.campaign, available(session.campaign), settings)
    return EffectRoll.objects.create(
        session=session,
        character=character,
        issued_to=character,
        definition=effect,
        snapshot=snapshot(effect),
        bonus=bonus,
    )


def choose(roll, index):
    if (
        roll.status != "rolled"
        or type(index) is not int
        or not 0 <= index < len(roll.choices)
    ):
        raise ValidationError("Выбор недоступен")
    roll.snapshot = roll.choices[index]
    roll.definition_id = roll.snapshot["id"]
    roll.choices = []
    roll.status = "active"
    roll.save()
    return roll


def use_effect(roll, note="", request_approval=False):
    if roll.session.status != "active" or roll.status != "active":
        raise ValidationError("Эффект недоступен")
    if roll.snapshot.get("parameters", {}).get("standard_index") in [90, 91]:
        raise ValidationError("Для передачи или обмена используйте запрос обмена")
    if roll.snapshot.get("requires_approval") or request_approval:
        if not note.strip():
            raise ValidationError("Опишите применение эффекта")
        EffectApprovalRequest.objects.create(effect=roll, description=note)
        roll.status = "pending_approval"
    else:
        roll.uses += 1
        roll.status = (
            "used" if roll.uses >= roll.snapshot.get("use_limit", 1) else "active"
        )
        if roll.snapshot.get("mechanic_type") == "choice3":
            ChoiceGrant.objects.get_or_create(character=roll.character, source=roll)
    roll.note = note
    roll.save()
    return roll


def decide_effect(approval, actor, approved, note):
    roll = approval.effect
    if (
        approval.status != "pending"
        or roll.status != "pending_approval"
        or roll.session.status != "active"
    ):
        raise ValidationError("Запрос больше недоступен")
    approval.status = "approved" if approved else "rejected"
    approval.decided_by = actor
    approval.decision_note = note
    approval.save()
    if approved:
        roll.uses += 1
        roll.status = (
            "used" if roll.uses >= roll.snapshot.get("use_limit", 1) else "active"
        )
        if roll.snapshot.get("mechanic_type") == "choice3":
            ChoiceGrant.objects.get_or_create(character=roll.character, source=roll)
    else:
        roll.status = "active"
    roll.save()
    return roll


def finish_session(session):
    if CasinoRound.objects.filter(session=session, status="active").exists():
        raise ValidationError("Игроки должны завершить открытые карточные раунды")
    session.status = "completed"
    session.save()
    EffectApprovalRequest.objects.filter(
        effect__session=session, status="pending"
    ).update(status="expired")
    EffectExchange.objects.filter(
        source__session=session, status__in=["pending_consent", "pending_approval"]
    ).update(status="expired")
    EffectRoll.objects.filter(
        session=session, status__in=["active", "rolled", "pending_approval"]
    ).update(status="expired")
    QuestAssignment.objects.filter(
        session=session,
        status__in=["active", "pending_verification", "rejected", "assigned"],
    ).update(status="expired")


def request_exchange(source, offered, target, requested=None):
    index = source.snapshot.get("parameters", {}).get("standard_index")
    if (
        index not in [90, 91]
        or source.status != "active"
        or source.session.status != "active"
    ):
        raise ValidationError("Нужна активная карточка передачи или обмена")
    if (
        source.character_id != offered.character_id
        or offered.status != "active"
        or offered.uses != 0
        or source.pk == offered.pk
        or offered.session_id != source.session_id
    ):
        raise ValidationError("Предлагаемая карточка недоступна")
    if (
        target.campaign_id != source.session.campaign_id
        or target.pk == source.character_id
        or not target.active
    ):
        raise ValidationError("Неверный получатель")
    if index == 90 and offered.snapshot.get("category") != "gift":
        raise ValidationError("Передавать можно только дар")
    if index == 91 and (
        not requested
        or requested.status != "active"
        or requested.uses != 0
        or requested.character_id != target.pk
        or requested.session_id != source.session_id
    ):
        raise ValidationError("Выберите активную карточку союзника")
    source.status = "pending_approval"
    source.save()
    offered.status = "pending_approval"
    offered.save()
    if requested:
        requested.status = "pending_approval"
        requested.save()
    return EffectExchange.objects.create(
        source=source, offered=offered, target=target, requested=requested
    )


def decide_exchange(exchange, approved):
    if (
        exchange.status != "pending_approval"
        or not exchange.consented
        or exchange.source.session.status != "active"
    ):
        raise ValidationError("Нужно согласие получателя")
    source, offered, requested = exchange.source, exchange.offered, exchange.requested
    if approved:
        original = offered.character
        offered.character = exchange.target
        if requested:
            requested.character = original
        source.status = "used"
        source.uses += 1
    else:
        source.status = "active"
    source.save()
    offered.status = "active"
    offered.save()
    if requested:
        requested.status = "active"
        requested.save()
    exchange.status = "approved" if approved else "rejected"
    exchange.save()
