from pathlib import Path
from django.core.management.base import BaseCommand
from django.db import transaction
from django.core.management import call_command
from lab.models import EffectDefinition, QuestDefinition, Campaign
from lab.services.casino import ensure_configs


class Command(BaseCommand):
    help = "Idempotently create/update exactly 120 standard effects and 42 quests; never touch custom codes."

    @transaction.atomic
    def handle(self, *args, **options):
        root = Path(__file__).resolve().parents[2] / "data"
        effects = (root / "effects.txt").read_text().strip().splitlines()
        quests = (root / "quests.txt").read_text().strip().splitlines()
        assert len(effects) == 120 and len(quests) == 42
        mechanical = set(range(21, 31)) | {
            12,
            17,
            38,
            62,
            81,
            82,
            88,
            92,
            93,
            96,
            97,
            100,
            104,
            109,
            110,
            114,
            117,
            119,
        }
        for i, line in enumerate(effects, 1):
            title, description = line.split("|", 1)
            category = ["gift", "complication", "paradox"][(i - 1) // 40]
            EffectDefinition.objects.update_or_create(
                code=f"std-effect-{i:03}",
                defaults={
                    "title": title,
                    "summary": description[:297],
                    "description": description,
                    "mechanic": description,
                    "category": category,
                    "rarity": "rare"
                    if i in {1, 11, 31, 81, 91, 119, 120}
                    else "uncommon"
                    if i % 4 == 0
                    else "common",
                    "requires_approval": i not in mechanical,
                    "mechanic_type": "choice3"
                    if i == 119
                    else "table"
                    if i in mechanical
                    else "narrative",
                    "parameters": {"standard_index": i},
                    "color": {
                        "gift": "#695CF5",
                        "complication": "#E16C77",
                        "paradox": "#24A88A",
                    }[category],
                },
            )
        for i, line in enumerate(quests, 1):
            title, description = line.split("|", 1)
            category = (
                "Отыгрыш персонажа"
                if i <= 12
                else "Взаимодействие с союзниками"
                if i <= 22
                else "Исследование мира"
                if i <= 32
                else "Социальные задания"
                if i <= 37
                else "Боевые и тактические задания"
            )
            QuestDefinition.objects.update_or_create(
                code=f"std-quest-{i:03}",
                defaults={
                    "title": title,
                    "description": description,
                    "category": category,
                    "reward": 5
                    if i in {6, 9, 22, 27, 37}
                    else 15
                    if i in {7, 18, 21, 30, 38, 42}
                    else 10,
                    "difficulty": "easy"
                    if i in {6, 9, 22, 27, 37}
                    else "hard"
                    if i in {7, 18, 21, 30, 38, 42}
                    else "normal",
                },
            )
        call_command("seed_spells")
        for campaign in Campaign.objects.all():
            ensure_configs(campaign)
        self.stdout.write(
            self.style.SUCCESS(
                "120 effects · 42 quests · 7 game defaults per campaign."
            )
        )
