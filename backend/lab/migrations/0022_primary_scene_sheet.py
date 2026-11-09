from collections import defaultdict
from itertools import count

from django.db import migrations, models


COMBAT_FIELDS = (
    'hp_current', 'hp_max', 'hp_temp', 'conditions', 'slots',
    'death_successes', 'death_failures', 'combat_turn',
)


def link_primary_sheets(apps, schema_editor):
    db = schema_editor.connection.alias
    Target = apps.get_model('lab', 'SceneTarget')
    Sheet = apps.get_model('lab', 'CharacterSheet')
    Character = apps.get_model('lab', 'Character')
    Ability = apps.get_model('lab', 'CharacterAbility')
    groups = defaultdict(list)
    discarded = set()
    rows = Target.objects.using(db).filter(source__kind='npc').select_related(
        'session', 'instance__sheet'
    ).order_by('id')
    for target in rows.iterator():
        if target.active and target.session.status == 'active':
            groups[target.session_id, target.source_id].append(target)
        elif target.instance_id:
            sheet = target.instance.sheet
            for field in ('hp_current', 'hp_max', 'hp_temp', 'conditions'):
                setattr(target, field, getattr(sheet, field))
            target.active = False
            target.save(update_fields=['active', 'hp_current', 'hp_max', 'hp_temp', 'conditions'])
            discarded.add(target.instance_id)

    for targets in groups.values():
        slots = {}
        for target in targets:
            _, sep, suffix = target.name.rpartition(' № ')
            if sep and suffix.isascii() and suffix.isdigit() and 1 <= len(suffix) <= 3:
                number = int(suffix)
                if number and number not in slots:
                    slots[number] = target
        numbered = {target.pk for target in slots.values()}
        next_slot = (n for n in count(1) if n not in slots)
        for target in targets:
            if target.pk not in numbered:
                slots[next(next_slot)] = target
        for number, target in slots.items():
            target.scene_number = number
            if number == 1:
                template, _ = Sheet.objects.using(db).get_or_create(character_id=target.source_id)
                if target.instance_id:
                    sheet = target.instance.sheet
                    for field in COMBAT_FIELDS:
                        setattr(template, field, getattr(sheet, field))
                    discarded.add(target.instance_id)
                elif not target.linked_sheet:
                    for field in ('hp_current', 'hp_max', 'hp_temp', 'conditions'):
                        setattr(template, field, getattr(target, field))
                template.version += 1
                template.save(update_fields=[*COMBAT_FIELDS, 'version'])
                target.linked_sheet = True
                target.instance_id = None
            target.save(update_fields=['scene_number', 'linked_sheet', 'instance'])

    Character.objects.using(db).filter(pk__in=discarded).update(active=False)
    Ability.objects.using(db).filter(character_id__in=discarded).delete()
    Sheet.objects.using(db).filter(character_id__in=discarded).delete()


class Migration(migrations.Migration):
    dependencies = [('lab', '0021_scene_target_instance')]
    operations = [
        migrations.AddField(
            model_name='scenetarget', name='scene_number',
            field=models.PositiveSmallIntegerField(null=True, blank=True),
        ),
        migrations.RunPython(link_primary_sheets),
    ]
