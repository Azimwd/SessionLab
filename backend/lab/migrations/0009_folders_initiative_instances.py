from django.conf import settings
from django.db import migrations, models
import django.db.models.deletion


def backfill_player_slots(apps, schema_editor):
    Entry = apps.get_model('lab', 'InitiativeEntry')
    for entry in Entry.objects.select_related('character').filter(character__kind='player').iterator():
        entry.player_slot_id = entry.character_id
        entry.save(update_fields=['player_slot'])


class Migration(migrations.Migration):
    dependencies = [('lab', '0008_alter_characterability_casting_time')]

    operations = [
        migrations.CreateModel(
            name='CharacterFolder',
            fields=[
                ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
                ('created_at', models.DateTimeField(auto_now_add=True)),
                ('updated_at', models.DateTimeField(auto_now=True)),
                ('name', models.CharField(max_length=80)),
                ('campaign', models.ForeignKey(on_delete=django.db.models.deletion.PROTECT, related_name='character_folders', to='lab.campaign')),
                ('owner', models.ForeignKey(on_delete=django.db.models.deletion.PROTECT, to=settings.AUTH_USER_MODEL)),
            ],
            options={'ordering': ['name', 'id']},
        ),
        migrations.AddConstraint(
            model_name='characterfolder',
            constraint=models.UniqueConstraint(fields=('campaign', 'owner', 'name'), name='unique_character_folder_name'),
        ),
        migrations.AddField(
            model_name='character', name='folder',
            field=models.ForeignKey(blank=True, null=True, on_delete=django.db.models.deletion.SET_NULL, related_name='characters', to='lab.characterfolder'),
        ),
        migrations.RemoveConstraint(model_name='initiativeentry', name='one_character_initiative'),
        migrations.AddField(
            model_name='initiativeentry', name='player_slot',
            field=models.ForeignKey(blank=True, null=True, on_delete=django.db.models.deletion.PROTECT, related_name='+', to='lab.character'),
        ),
        migrations.RunPython(backfill_player_slots, migrations.RunPython.noop),
        migrations.AddConstraint(
            model_name='initiativeentry',
            constraint=models.UniqueConstraint(fields=('tracker', 'player_slot'), name='one_player_initiative'),
        ),
    ]
