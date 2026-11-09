from unittest.mock import patch

import pytest

from lab.api.scene import target_sheet
from lab.models import CharacterAbility, DamageApplication, SceneTarget
from lab.services.sheets import sheet_for

from .test_api import client, post, scoped, world
from .test_dmhub_dice import personal
from .test_scene import targets


ROOT = '/api/integrations/dmhub/token-scene/'
GAME = 'dmhub-game'


def setup_spell(world, resolution, damage_type='fire'):
    dm, player, _, campaign, caster, session = world
    _, rows = targets(world, {'fire': 'resistance'})
    target = SceneTarget.objects.get(pk=rows[1]['id'])
    sheet = sheet_for(caster)
    sheet.slots['1'] = {'max': 2, 'used': 0}
    sheet.save()
    spell = CharacterAbility.objects.create(
        character=caster, kind='spell', name='Test spell', level=1, dice='12',
        resolution=resolution, ability='int', save_ability='dex', damage_type=damage_type,
    )
    player_api, dm_api = personal(player, campaign), personal(dm, campaign)
    link = {'command': 'link', 'session': session.pk, 'game': GAME, 'token': 'guard-2', 'target': target.pk}
    assert post(player_api, ROOT, link).status_code == 403
    assert post(dm_api, ROOT, link).status_code == 200
    cast = {**link, 'command': 'cast', 'caster': caster.pk, 'spell': spell.pk, 'slot_level': 1}
    return target, sheet, cast, player_api, dm_api


def test_targeted_attack_updates_copy_once_without_disclosing_vitals(world):
    target, sheet, cast, player, master = setup_spell(world, 'attack')
    query = f'{ROOT}?game={GAME}'
    assert player.get(query).json()['data']['targets'] == [
        {'id': target.pk, 'name': target.name, 'targetable': True, 'token': 'guard-2'},
    ]
    rows = master.get(query).json()['data']['targets']
    assert next(row for row in rows if row['id'] == target.pk)['hp_current'] == 40
    assert not player.get(f'{ROOT}?game=another-game').json()['data']['targets']

    with patch('lab.services.dice.secrets.randbelow', return_value=17):
        first = post(player, ROOT, cast, key='targeted-spell-once')
    assert first.status_code == 200, first.json()
    result = first.json()['data']
    assert result['event']['payload']['token_target']['parts'] == [{'hit': True}]
    assert all(key not in str(result) for key in ('hp_current', 'armor_class', 'final_damage'))
    assert post(player, ROOT, cast, key='targeted-spell-once').json() == first.json()
    sheet.refresh_from_db()
    assert sheet.slots['1']['used'] == 1
    assert DamageApplication.objects.count() == 1
    assert target_sheet(target).hp_current == 34
    assert sheet_for(target.source).hp_current == 40
    assert post(client(world[1]), scoped('/api/scene/damage/', world[3]), {
        'source_event': result['event']['id'], 'targets': [target.pk], 'outcomes': {'1': {'hit': True}},
    }).status_code == 400


@pytest.mark.parametrize(('resolution', 'damage_type', 'die', 'starting_hp', 'end_hp', 'outcomes'), [
    ('attack', 'fire', 0, 40, 40, [{'hit': False}]),
    ('save', 'fire', 0, 40, 34, [{'save_outcome': 'failure'}]),
    ('save', 'fire', 19, 40, 40, [{'save_outcome': 'success'}]),
    ('automatic', 'healing', 0, 22, 34, [{}]),
])
def test_targeted_cast_resolves_attack_save_and_healing(world, resolution, damage_type, die, starting_hp, end_hp, outcomes):
    target, _, cast, player, _ = setup_spell(world, resolution, damage_type)
    health = target_sheet(target)
    health.hp_current = starting_hp
    health.save()
    with patch('lab.services.dice.secrets.randbelow', return_value=die):
        response = post(player, ROOT, cast)
    assert response.status_code == 200, response.json()
    assert response.json()['data']['event']['payload']['token_target']['parts'] == outcomes
    health.refresh_from_db()
    assert health.hp_current == end_hp


def test_invalid_or_hidden_targets_do_not_spend_slots(world):
    target, sheet, cast, player, _ = setup_spell(world, 'save')
    assert post(player, ROOT, {**cast, 'token': 'wrong-token'}).status_code == 404
    assert post(player, ROOT, {**cast, 'hit': True}).status_code == 400
    target.visible = False
    target.save(update_fields=['visible'])
    assert post(player, ROOT, cast).status_code == 404
    sheet.refresh_from_db()
    assert sheet.slots['1']['used'] == 0
    assert not DamageApplication.objects.exists()
