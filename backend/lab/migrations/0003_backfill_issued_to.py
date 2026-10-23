from django.db import migrations
from django.db.models import F


def backfill(apps, schema_editor):
    apps.get_model("lab", "EffectRoll").objects.filter(issued_to=None).update(
        issued_to_id=F("character_id")
    )


class Migration(migrations.Migration):
    dependencies = [("lab", "0002_effectroll_issued_to")]
    operations = [migrations.RunPython(backfill, migrations.RunPython.noop)]
