import secrets
from django.db.models import Q
from rest_framework.exceptions import ValidationError
from lab.models import *
from .effects import snapshot
from .casino import wallet_for, move


def assign(session, character, definition=None):
    if session.status != "active":
        raise ValidationError("Сессия не активна")
    limit = session.settings.get(
        "quest_limit", session.campaign.settings["quest_limit"]
    )
    # Total assignments per session: finishing one does not open an infinite reward loop.
    if (
        QuestAssignment.objects.filter(session=session, character=character)
        .exclude(status="cancelled")
        .count()
        >= limit
    ):
        raise ValidationError("Лимит заданий на сессию исчерпан")
    used = QuestAssignment.objects.filter(
        session=session, character=character
    ).values_list("definition_id", flat=True)
    candidates = list(
        QuestDefinition.objects.filter(
            Q(campaign=session.campaign) | Q(campaign=None), active=True, archived=False
        ).exclude(pk__in=used)
    )
    if not candidates:
        raise ValidationError("Нет доступных квестов")
    definition = definition or secrets.choice(candidates)
    return QuestAssignment.objects.create(
        session=session,
        character=character,
        definition=definition,
        snapshot=snapshot(definition),
    )


def submit(assignment, evidence):
    if assignment.session.status != "active" or assignment.status not in [
        "active",
        "rejected",
    ]:
        raise ValidationError("Квест недоступен для отправки")
    if not evidence.strip():
        raise ValidationError("Опишите выполненное действие")
    assignment.evidence = evidence
    assignment.status = "pending_verification"
    assignment.save()
    return assignment


def decide(assignment, actor, approved, note):
    if (
        assignment.status != "pending_verification"
        or assignment.session.status != "active"
    ):
        raise ValidationError("Квест уже рассмотрен или истёк")
    assignment.status = "completed" if approved else "rejected"
    assignment.decided_by = actor
    assignment.decision_note = note
    assignment.save()
    if approved:
        wallet = wallet_for(assignment.session.campaign, assignment.character.owner)
        move(
            wallet,
            assignment.snapshot["reward"],
            "quest",
            f"quest:{assignment.pk}",
            actor=actor,
        )
        Achievement.objects.get_or_create(
            user=assignment.character.owner,
            campaign=assignment.session.campaign,
            code="first-quest",
            defaults={"title": "Первая история"},
        )
    return assignment
