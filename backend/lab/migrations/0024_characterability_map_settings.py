from django.db import migrations, models


class Migration(migrations.Migration):
    dependencies = [('lab', '0023_dmhub_scene_tokens')]

    operations = [
        migrations.AddField(
            model_name='characterability',
            name='map_settings',
            field=models.JSONField(blank=True, default=dict),
        ),
    ]
