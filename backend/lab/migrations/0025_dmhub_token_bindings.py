import django.db.models.deletion
from django.db import migrations, models


def remember_active_tokens(apps, schema_editor):
    using = schema_editor.connection.alias
    binding = apps.get_model('lab', 'DMHubTokenBinding')
    target = apps.get_model('lab', 'SceneTarget')
    rows = target.objects.using(using).filter(
        active=True, session__status='active', source__active=True,
    ).exclude(dmhub_game='').exclude(dmhub_token='').values_list(
        'session__campaign_id', 'dmhub_game', 'dmhub_token', 'source_id',
    )
    for campaign, game, token, source in rows.iterator():
        binding.objects.using(using).create(
            campaign_id=campaign, game=game, token=token, source_id=source,
        )


class Migration(migrations.Migration):
    dependencies = [('lab', '0024_characterability_map_settings')]
    operations = [
        migrations.CreateModel(
            name='DMHubTokenBinding',
            fields=[
                ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
                ('game', models.CharField(max_length=128)),
                ('token', models.CharField(max_length=128)),
                ('campaign', models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, to='lab.campaign')),
                ('source', models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, to='lab.character')),
            ],
            options={'constraints': [
                models.UniqueConstraint(fields=('campaign', 'game', 'token'), name='dmhub_game_token_binding'),
            ]},
        ),
        migrations.RunPython(remember_active_tokens, migrations.RunPython.noop),
    ]
