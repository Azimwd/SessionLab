"""Create an independent sheet for one NPC in a scene."""
from copy import deepcopy


def clone_record(record, excluded, **overrides):
    fields = {
        field.attname: deepcopy(getattr(record, field.attname))
        for field in record._meta.concrete_fields
        if not field.primary_key and field.name not in {'created_at', 'updated_at', *excluded}
    }
    return type(record)(**(fields | overrides))


def clone_scene_npc(source, template, actions, name, maximum, current, temporary, conditions, *, using=None):
    character = clone_record(
        source, {'avatar_image', 'avatar_mime', 'avatar_updated_at'},
        name=name, folder_id=None, table_visible=False,
    )
    character.save(using=using)
    sheet = clone_record(
        template, set(), character_id=character.pk, version=1,
        hp_max=maximum, hp_current=current, hp_temp=temporary,
        slots={key: {**slot, 'used': 0} for key, slot in template.slots.items()},
        conditions=deepcopy(conditions), combat_turn=1, death_successes=0, death_failures=0,
    )
    sheet.save(using=using)
    copies = [
        clone_record(action, set(), character_id=character.pk, version=1)
        for action in actions
    ]
    if copies:
        type(copies[0]).objects.db_manager(using).bulk_create(copies)
    return character
