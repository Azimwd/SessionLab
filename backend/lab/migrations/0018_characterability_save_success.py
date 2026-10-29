from django.db import migrations, models


class Migration(migrations.Migration):
    dependencies = [('lab', '0017_characterability_use_spell_ability')]
    operations = [migrations.AddField(
        model_name='characterability', name='save_success',
        field=models.CharField(max_length=8, default='rules', choices=[
            ('rules', 'По правилам каталога'), ('none', 'Нет урона'),
            ('half', 'Половина урона'), ('full', 'Полный урон'),
        ]),
    )]
