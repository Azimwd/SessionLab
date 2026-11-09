from django.db import migrations, models
import django.db.models.deletion


def backfill_instances(apps, schema_editor):
    # Historical models are passed in, so the clone only copies fields in this migration state.
    from lab.services.scene_instances import clone_scene_npc

    Target = apps.get_model('lab', 'SceneTarget')
    Sheet = apps.get_model('lab', 'CharacterSheet')
    db = schema_editor.connection.alias
    targets = Target.objects.using(db).filter(
        session__status='active', active=True, linked_sheet=False, source__kind='npc'
    ).select_related('source')
    for target in targets.iterator():
        template, _ = Sheet.objects.using(db).get_or_create(character=target.source)
        instance = clone_scene_npc(
            target.source, template, target.source.actions.filter(active=True),
            target.name, target.hp_max, target.hp_current, target.hp_temp, target.conditions, using=db,
        )
        target.instance_id = instance.pk
        target.save(update_fields=['instance'])


def restore_scene_health(apps, schema_editor):
    Target = apps.get_model('lab', 'SceneTarget')
    Character = apps.get_model('lab', 'Character')
    db = schema_editor.connection.alias
    targets = Target.objects.using(db).filter(instance__isnull=False).select_related('instance__sheet')
    for target in targets.iterator():
        sheet = target.instance.sheet
        for field in ('hp_current', 'hp_max', 'hp_temp', 'conditions'):
            setattr(target, field, getattr(sheet, field))
        target.save(update_fields=['hp_current', 'hp_max', 'hp_temp', 'conditions'])
    Character.objects.using(db).filter(scene_copy__isnull=False).update(active=False)


class Migration(migrations.Migration):
    dependencies = [('lab', '0020_attack_effects')]
    operations = [
        migrations.AddField(
            model_name='scenetarget', name='instance',
            field=models.OneToOneField(
                blank=True, null=True, on_delete=django.db.models.deletion.PROTECT,
                related_name='scene_copy', to='lab.character',
            ),
        ),
        migrations.RunPython(backfill_instances, restore_scene_health),
    ]
