from unittest.mock import patch

import pytest

from lab.api.scene import target_sheet
from lab.models import CharacterAbility, DamageApplication, DMHubTokenBinding, RoomEvent, SceneTarget, SpellCatalogEntry
from lab.services.sheets import sheet_for

from .test_api import client, post, scoped, world
from .test_dmhub_dice import personal
from .test_scene import targets


ROOT = '/api/integrations/dmhub/token-scene/'
GAME = 'dmhub-game'


def test_map_initiative_uses_independent_npc_sheets_and_keeps_active_turn(world):
    dm, player, _, campaign, hero, session = world
    guard, _ = targets(world)
    master = personal(dm, campaign)
    master_body = {'command': 'enroll-initiative', 'game': GAME, 'session': session.pk, 'tokens': [
        {'token': 'guard-a', 'sheet': guard.pk},
        {'token': 'guard-b', 'sheet': guard.pk, 'hidden': True},
    ]}
    with patch('lab.services.dice.secrets.randbelow', side_effect=[4, 8]):
        response = post(master, ROOT, master_body, key='map-initiative-once')
    assert response.status_code == 200, response.json()
    assert post(master, ROOT, master_body, key='map-initiative-once').json() == response.json()
    rows = response.json()['data']['initiative']
    assert [(row['name'], row['total'], row['rolled']) for row in rows] == [
        ('Стражник № 1', 5, True), ('Стражник № 2', 9, True),
    ]
    tracker = session.initiative
    assert tracker.entries.count() == 2 and not tracker.running and tracker.round_number == 0
    assert tracker.entries.values_list('character_id', flat=True).distinct().count() == 2
    assert list(RoomEvent.objects.filter(session=session).order_by('pk').values_list('visibility', flat=True)) == ['public', 'dm']
    assert not any(row['rolled'] for row in post(master, ROOT, master_body).json()['data']['initiative'])
    room = '/api/integrations/dmhub/room/'
    player_api = personal(player, campaign)
    player_rows = player_api.get(room).json()['data']['initiative']['entries']
    assert [row['name'] for row in player_rows] == ['Стражник № 1']
    assert player_api.get('/api/integrations/dmhub/dice/events/?cursor=0').json()['data']['events'][0]['actor'] == 'Стражник № 1'
    start = {'command': 'initiative', 'action': 'start', 'session': session.pk, 'version': tracker.version}
    assert post(master, room + 'commands/', start).status_code == 200
    tracker.refresh_from_db()
    current, round_number = tracker.current_id, tracker.round_number
    assert post(master, ROOT, {**master_body, 'command': 'enroll', 'tokens': [
        {'token': 'hero-a', 'sheet': hero.pk},
    ]}).status_code == 200
    player_body = {'command': 'initiative', 'game': GAME, 'session': session.pk, 'tokens': [{'token': 'hero-a'}]}
    assert post(player_api, ROOT, master_body).status_code == 403
    assert post(player_api, ROOT, {**player_body, 'tokens': [{'token': 'guard-a'}]}).status_code == 403
    assert post(player_api, ROOT, {**player_body, 'tokens': [{'token': 'hero-a'}, {'token': 'guard-b'}]}).status_code == 403
    assert tracker.entries.count() == 2
    sheet = sheet_for(hero)
    sheet.initiative_bonus = 4
    sheet.save(update_fields=['initiative_bonus'])
    with patch('lab.services.dice.secrets.randbelow', return_value=14):
        own = post(player_api, ROOT, player_body)
    assert own.status_code == 200, own.json()
    assert own.json()['data']['initiative'][0]['total'] == 19
    assert not post(player_api, ROOT, player_body).json()['data']['initiative'][0]['rolled']
    tracker.refresh_from_db()
    assert tracker.running and (tracker.current_id, tracker.round_number) == (current, round_number)
    assert tracker.entries.count() == 3 and RoomEvent.objects.filter(session=session).count() == 3
    tracker.entries.filter(player_slot=hero).update(hidden=True)
    assert post(player_api, ROOT, player_body).status_code == 403


def test_enroll_reuses_scene_rows_and_remembers_templates_across_sessions(world):
    dm, player, _, campaign, hero, session = world
    guard, existing = targets(world, {'fire': 'resistance'})
    master, player_api = personal(dm, campaign), personal(player, campaign)
    query = f'{ROOT}?game={GAME}&roster=1'
    assert player_api.get(query).status_code == 403
    assert len(master.get(query).json()['data']['enrollment']['characters']) == 2
    body = {'command': 'enroll', 'game': GAME, 'session': session.pk, 'tokens': {
        '1': {'token': 'guard-a', 'sheet': guard.pk},
        '2': {'token': 'guard-b', 'sheet': guard.pk},
        '3': {'token': 'guard-c', 'sheet': guard.pk, 'hidden': True},
    }}
    assert post(player_api, ROOT, body).status_code == 403
    response = post(master, ROOT, body, key='enroll-selected-once')
    assert response.status_code == 200, response.json()
    assert post(master, ROOT, body, key='enroll-selected-once').json() == response.json()
    result = response.json()['data']['targets']
    assert [row['id'] for row in result[:2]] == [row['id'] for row in existing]
    rows = list(session.scene_targets.filter(active=True).order_by('scene_number'))
    assert [row.name for row in rows] == ['Стражник № 1', 'Стражник № 2', 'Стражник № 3']
    assert rows[0].sheet_character.pk == guard.pk
    assert len({row.sheet_character.pk for row in rows}) == 3
    assert rows[1].defenses == {'fire': 'resistance'}
    assert not rows[2].visible
    sheet = target_sheet(rows[1])
    sheet.hp_current = 4
    sheet.save(update_fields=['hp_current'])
    repeated = post(master, ROOT, body).json()['data']['targets']
    assert all(not row['added'] for row in repeated)
    assert [target_sheet(row).hp_current for row in session.scene_targets.order_by('scene_number')] == [40, 4, 40]
    assert {row['token'] for row in player_api.get(f'{ROOT}?game={GAME}').json()['data']['targets']} == {'guard-a', 'guard-b'}
    assert post(client(dm), scoped(f'/api/sessions/{session.pk}/finish/', campaign), {}).status_code == 200
    assert not session.scene_targets.filter(active=True).exists()
    assert master.get(query).json()['data']['enrollment']['bindings'] == {
        'guard-a': guard.pk, 'guard-b': guard.pk, 'guard-c': guard.pk,
    }
    body.update(session=0, session_name='  Новый бой  ', tokens=[{'token': 'guard-c'}, {'token': 'guard-a'}])
    new = post(master, ROOT, body, key='create-and-enroll')
    assert new.status_code == 200, new.json()
    assert post(master, ROOT, body, key='create-and-enroll').json() == new.json()
    next_session = campaign.sessions.get(status='active')
    assert next_session.name == 'Новый бой'
    assert list(next_session.scene_targets.order_by('scene_number').values_list('name', 'dmhub_token')) == [
        ('Стражник № 1', 'guard-c'), ('Стражник № 2', 'guard-a'),
    ]
    assert post(master, ROOT, body).status_code == 400


def test_enrollment_is_atomic_and_players_never_get_copies(world):
    dm, player, _, campaign, hero, session = world
    guard, _ = targets(world)
    master = personal(dm, campaign)
    session.status = 'completed'
    session.save(update_fields=['status'])
    body = {'command': 'enroll', 'game': GAME, 'session': 0, 'session_name': 'Новая сцена', 'tokens': [
        {'token': 'guard-a', 'sheet': guard.pk},
        {'token': 'hero-a', 'sheet': hero.pk},
        {'token': 'hero-b', 'sheet': hero.pk},
    ]}
    assert post(master, ROOT, body).status_code == 400
    assert not campaign.sessions.filter(status='active').exists()
    assert not DMHubTokenBinding.objects.exists()
    bind = {'command': 'bind', 'game': GAME, 'token': 'hero-a', 'sheet': hero.pk}
    assert post(personal(player, campaign), ROOT, bind).status_code == 403
    assert post(master, ROOT, bind).status_code == 200
    assert master.get(f'{ROOT}?game={GAME}&token=hero-a').json()['data']['binding']['sheet'] == hero.pk
    body['tokens'] = [{'token': 'hero-a'}]
    assert post(master, ROOT, body).status_code == 200
    assert campaign.sessions.get(status='active').scene_targets.get().sheet_character.pk == hero.pk
    assert post(master, ROOT, {**bind, 'sheet': 0}).status_code == 400


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


@pytest.mark.parametrize(('die', 'immune', 'visible_radiant'), [
    (17, False, True), (0, False, False), (17, True, False),
])
def test_map_animation_marks_only_applied_radiant_bonus(world, die, immune, visible_radiant):
    target, _, cast, player, _ = setup_spell(world, 'attack')
    attack = CharacterAbility.objects.get(pk=cast['spell'])
    attack.kind, attack.level = 'attack', 0
    attack.attack_effects = [{
        'id': 'smite', 'name': 'Божественная кара', 'dice': '1d8',
        'damage_type': 'radiant', 'frequency': 'turn', 'enabled': True,
    }]
    attack.save(update_fields=['kind', 'level', 'attack_effects'])
    if immune:
        target.defenses = {**target.defenses, 'radiant': 'immunity'}
        target.save(update_fields=['defenses'])
    with patch('lab.services.dice.secrets.randbelow', return_value=die):
        response = post(player, ROOT, {
            'command': 'act', 'session': cast['session'], 'game': GAME,
            'caster': cast['caster'], 'action': attack.pk, 'action_version': attack.version,
            'slot_level': 0, 'distance_ft': 5, 'targets': [{'id': target.pk, 'token': cast['token']}],
        })
    assert response.status_code == 200, response.json()
    summary = response.json()['data']['event']['payload']['token_target']
    assert (summary.get('visual_radiant') is True) == visible_radiant
    assert 'components' not in summary and 'final_damage' not in summary


@pytest.mark.parametrize(('resolution', 'damage_type', 'die', 'starting_hp', 'end_hp', 'outcomes'), [
    ('attack', 'fire', 0, 40, 40, [{'hit': False}]),
    ('save', 'fire', 0, 40, 34, [{'save_outcome': 'failure', 'save_total': 1}]),
    ('save', 'fire', 19, 40, 40, [{'save_outcome': 'success', 'save_total': 20}]),
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
    payload = response.json()['data']['event']['payload']
    if resolution == 'save':
        outcomes = [{**part, 'save_dc': payload['save']['dc']} for part in outcomes]
    assert payload['token_target']['parts'] == outcomes
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


@pytest.mark.parametrize('preset', ['explicit', 'srd51-catalog', 'custom-name', 'description'])
def test_area_roll_spends_one_slot_and_resolves_each_save(world, preset):
    target, sheet, cast, player, master = setup_spell(world, 'save')
    other = SceneTarget.objects.get(session_id=cast['session'], source=target.source, active=True, pk__lt=target.pk)
    assert post(master, ROOT, {
        'command': 'link', 'session': cast['session'], 'game': GAME,
        'token': 'guard-1', 'target': other.pk,
    }).status_code == 200
    action = CharacterAbility.objects.get(pk=cast['spell'])
    if preset == 'explicit':
        action.map_settings = {'shape': 'sphere', 'size_ft': 20, 'range_ft': 150}
    elif preset == 'srd51-catalog':
        action.catalog_entry = SpellCatalogEntry.objects.get(code='srd51-fireball')
        action.range = action.catalog_entry.template['range']
        action.level = cast['slot_level'] = 3
        sheet.slots['3'] = {'max': 1, 'used': 0}
        sheet.save(update_fields=['slots'])
    elif preset == 'custom-name':
        action.name = 'Огненный шар'
    else:
        action.range = 'Дальность: 150 фт. (радиус 20 футов)'
        action.description = 'Взрыв радиусом 20 футов.'
    action.save_success = 'half'
    action.save()
    response = player.get(f"/api/integrations/dmhub/sheets/{cast['caster']}/")
    assert response.status_code == 200
    rules = next(row['map_targeting'] for row in response.json()['data']['actions'] if row['id'] == action.pk)
    assert (rules['shape'], rules['size_ft'], rules['range_ft']) == ('sphere', 20, 150)
    assert post(player, ROOT, cast).status_code == 400
    command = {key: cast[key] for key in ('session', 'game', 'caster', 'slot_level')}
    command.update(command='act', action=action.pk, action_version=action.version, distance_ft=40, targets=[
        {'token': 'guard-2', 'id': target.pk}, {'token': 'guard-1', 'id': other.pk},
    ])
    assert post(player, ROOT, {**command, 'distance_ft': 155}).status_code == 400
    assert post(player, ROOT, {**command, 'action_version': action.version + 1}).status_code == 400
    with patch('lab.services.dice.secrets.randbelow', side_effect=[0, 19]):
        response = post(player, ROOT, command, key='test-area-retry')
    assert response.status_code == 200, response.json()
    payload = response.json()['data']['event']['payload']
    assert payload['map_resolved']
    assert [row['parts'] for row in payload['token_targets']] == [
        [{'save_outcome': 'failure', 'save_total': 1, 'save_dc': payload['save']['dc']}],
        [{'save_outcome': 'success', 'save_total': 20, 'save_dc': payload['save']['dc']}],
    ]
    assert all(key not in str(payload['token_targets']) for key in ('hp_current', 'armor_class', 'final_damage'))
    assert post(player, ROOT, command, key='test-area-retry').json() == response.json()
    sheet.refresh_from_db()
    assert sheet.slots[str(cast['slot_level'])]['used'] == 1
    assert target_sheet(other).hp_current == 34
    assert target_sheet(target).hp_current == 37
    assert post(client(world[1]), scoped('/api/scene/damage/', world[3]), {
        'source_event': response.json()['data']['event']['id'], 'targets': [other.pk],
    }).status_code == 400


def test_weapon_and_damage_free_save_use_saved_action(world):
    target, sheet, cast, player, _ = setup_spell(world, 'attack')
    action = CharacterAbility.objects.get(pk=cast['spell'])
    action.kind = 'attack'
    action.level = 0
    action.dice = ''
    action.roll_modes = ['advantage']
    action.range = '10 футов'
    action.save()
    command = {key: cast[key] for key in ('session', 'game', 'caster')}
    command.update(command='act', action=action.pk, action_version=action.version, slot_level=0, distance_ft=10,
                   targets={'1': {'token': 'guard-2', 'id': target.pk}})
    with patch('lab.services.dice.secrets.randbelow', side_effect=[0, 19]):
        result = post(player, ROOT, command).json()['data']['event']['payload']
    assert result['roll']['mode'] == 'advantage'
    assert result['token_target']['parts'] == [{'hit': True}]
    action.resolution = 'save'
    action.save()
    with patch('lab.services.dice.secrets.randbelow', return_value=0):
        result = post(player, ROOT, command).json()['data']['event']['payload']
    assert result['token_target']['parts'] == [
        {'save_outcome': 'failure', 'save_total': 1, 'save_dc': result['save']['dc']},
    ]
    assert not DamageApplication.objects.exists()
    assert target_sheet(target).hp_current == 40
    sheet.refresh_from_db()
    assert sheet.slots['1']['used'] == 0
