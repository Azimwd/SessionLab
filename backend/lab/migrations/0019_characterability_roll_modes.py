from django.db import migrations, models


class Migration(migrations.Migration):
    dependencies = [('lab', '0018_characterability_save_success')]
    operations = [migrations.AddField(
        model_name='characterability', name='roll_modes',
        field=models.JSONField(default=list, blank=True),
    )]
