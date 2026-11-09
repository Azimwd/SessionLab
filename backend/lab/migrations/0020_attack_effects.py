from django.db import migrations, models

class Migration(migrations.Migration):
    dependencies = [('lab','0019_characterability_roll_modes')]
    operations = [
        migrations.AddField(model_name='characterability',name='attack_effects',field=models.JSONField(default=list,blank=True)),
        migrations.AddField(model_name='charactersheet',name='combat_turn',field=models.PositiveIntegerField(default=1)),
    ]
