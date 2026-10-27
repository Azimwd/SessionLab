import pytest
from rest_framework.test import APIClient

from lab.models import CharacterAbility, CharacterFolder, RoomEvent, SpellCatalogEntry
from .test_api import client, post, scoped, world


@pytest.fixture
def native(world):
    _, player, _, campaign, character, _ = world
    token = post(client(player), scoped('/api/integrations/dmhub/sheet-access/', campaign),
                 {'action': 'rotate'}).json()['data']['token']
    return APIClient(HTTP_AUTHORIZATION='Bearer ' + token), f'/api/integrations/dmhub/sheets/{character.pk}/'


def test_native_edit_all_sheet_sections_and_stale_version(world, native):
    _, _, _, _, character, _ = world
    api, root = native
    current = api.get(root).json()['data']['sheet']
    slots = {str(n): {'max': 2.0 if n == 8 else 0.0, 'used': 1.0 if n == 8 else 0.0} for n in range(1, 10)}
    body = {'version': float(current['version']), 'abilities': {**current['abilities'], 'str': 18.0},
            'saves': ['dex'], 'skills': {'arcana': 2.0}, 'slots': slots, 'spell_ability': 'wis',
            'hp_max': 40.0, 'hp_current': 30.0, 'hp_temp': 5.0, 'armor_class': 17.0,
            'speed': 35.0, 'initiative_bonus': 3.0, 'proficiency_override': 4.0,
            'conditions': ['Очарован'], 'inventory': 'Верёвка\nФонарь', 'notes': 'Личные заметки',
            'background': 'История', 'death_successes': 1.0, 'death_failures': 0.0}
    response = post(api, root + 'edit/', body, key='native-edit-all')
    assert response.status_code == 200, response.json()
    saved = response.json()['data']
    assert saved['version'] == current['version'] + 1
    assert saved['computed']['modifiers']['str'] == 4
    assert saved['skills']['arcana'] == 2 and saved['slots']['8'] == {'max': 2, 'used': 1}
    assert api.get(root).json()['data']['sheet']['notes'] == 'Личные заметки'
    assert post(api, root + 'edit/', body, key='native-edit-all').json() == response.json()
    assert post(api, root + 'edit/', body).status_code == 409
    reset = post(api, root + 'resources/', {'action': 'restore_slots', 'version': float(saved['version'])}, key='native-rest')
    assert reset.status_code == 200 and reset.json()['data']['slots']['8']['used'] == 0
    assert post(api, root + 'resources/', {'action': 'restore_slots', 'version': float(saved['version'])}, key='native-rest').json() == reset.json()
    assert post(api, root + 'resources/', {'action': 'restore_slots', 'version': saved['version']}).status_code == 409
    latest = reset.json()['data']
    clear = post(api, root + 'edit/', {'version': latest['version'], 'saves': {}, 'conditions': {}, 'auto_proficiency': True})
    assert clear.status_code == 200
    assert clear.json()['data']['saves'] == [] and clear.json()['data']['proficiency_override'] is None
    # The ordinary website reads the same row, without exposing private notes in room events.
    assert client(world[1]).get(scoped(f'/api/characters/{character.pk}/sheet/', world[3])).json()['data']['inventory'] == 'Верёвка\nФонарь'
    assert 'Личные заметки' not in str(list(RoomEvent.objects.values('payload')))


def test_native_action_create_edit_archive_and_idempotency(world, native):
    api, root = native
    body = {'kind': 'attack', 'name': 'Копьё', 'dice': '1d6', 'ability': 'str', 'add_modifier': True}
    first = post(api, root + 'abilities/', body, key='native-new-action')
    assert first.status_code == 200, first.json()
    action = first.json()['data']
    assert post(api, root + 'abilities/', body, key='native-new-action').json() == first.json()
    assert CharacterAbility.objects.filter(character=world[4], name='Копьё').count() == 1
    path = root + f'abilities/{action["id"]}/edit/'
    updated = post(api, path, {'version': float(action['version']), 'name': 'Копьё +1', 'bonus': 1.0})
    assert updated.status_code == 200, updated.json()
    assert post(api, path, {'version': action['version'], 'name': 'Stale'}).status_code == 409
    assert post(api, path, {'version': updated.json()['data']['version'], 'active': False}).status_code == 200
    assert api.get(root).json()['data']['actions'] == []
    assert CharacterAbility.objects.get(pk=action['id']).active is False
    assert post(api, root + f'abilities/{action["id"]}/use/', {'slot_level': 0}).status_code == 404


def test_native_catalog_search_filters_add_and_cast(world, native):
    api, root = native
    search = '/api/integrations/dmhub/catalog/'
    found = api.get(search, {'q': 'ОГНЕННЫЙ ШАР', 'level': 3, 'class': 'Wizard', 'school': 'evocation'})
    assert found.status_code == 200, found.json()
    result = found.json()['data']
    assert result['count'] == 1
    entry = result['results'][0]
    assert entry['rules']['description'] and entry['name_ru'] == 'Огненный шар'
    response = post(api, root + 'catalog-add/', {'spell_id': float(entry['id'])}, key='native-add-spell')
    assert response.status_code == 200, response.json()
    ability = response.json()['data']
    assert ability['dice'] == '8d6' and ability['description']
    assert post(api, root + 'catalog-add/', {'spell_id': entry['id']}).json()['data']['id'] == ability['id']
    sheet = api.get(root).json()['data']['sheet']
    slots = sheet['slots']
    slots['8'] = {'max': 10.0, 'used': 0.0}
    assert post(api, root + 'edit/', {'version': sheet['version'], 'slots': slots}).status_code == 200
    cast = post(api, root + f'abilities/{ability["id"]}/use/', {'slot_level': 8.0})
    assert cast.status_code == 200, cast.json()
    payload = cast.json()['data']['payload']
    assert payload['slot_level'] == 8 and payload['save']['success_damage'] == payload['damage']['total'] // 2
    assert api.get(root).json()['data']['sheet']['slots']['8']['used'] == 1
    assert api.get(search).json()['data']['count'] == SpellCatalogEntry.objects.filter(active=True).count()


def test_native_edit_permissions_and_validation(world, native):
    api, root = native
    dm, _, outsider, campaign, character, _ = world
    other = campaign.character_set.create(owner=dm, name='Other player')
    foreign = f'/api/integrations/dmhub/sheets/{other.pk}/'
    for path, body in [('edit/', {'version': 1, 'notes': 'hack'}), ('abilities/', {'kind': 'attack', 'name': 'hack'}), ('catalog-add/', {'spell_id': SpellCatalogEntry.objects.first().pk})]:
        assert post(api, foreign + path, body).status_code == 403
    attack = CharacterAbility.objects.create(character=other, kind='attack', name='Private')
    assert post(api, root + f'abilities/{attack.pk}/edit/', {'version': 1, 'active': False}).status_code == 404
    current = api.get(root).json()['data']['sheet']
    for patch in ({'abilities': {'str': 15}}, {'hp_current': 1000}, {'skills': {'arcana': 3}}, {'conditions': ['fake']}, {'slots': {'8': {'max': 1, 'used': 3}}}, {'armor_class': 1.5}):
        assert post(api, root + 'edit/', {'version': current['version'], **patch}).status_code == 400
    assert api.get(root).json()['data']['sheet']['version'] == current['version']
    assert APIClient().get('/api/integrations/dmhub/catalog/').status_code in (401, 403)


def test_native_conditions_delta_preserves_concurrent_edits(world, native):
    api, root = native
    sheet = api.get(root).json()['data']['sheet']
    # A browser changes HP and another condition while the native form is open.
    browser = post(api, root + 'edit/', {'version': sheet['version'], 'hp_current': 7,
                                        'conditions': ['Испуган']})
    assert browser.status_code == 200
    change = {'add': ['Ослеплён'], 'remove': {}}
    saved = post(api, root + 'conditions/', change, key='delta-condition-save')
    assert saved.status_code == 200, saved.json()
    value = saved.json()['data']
    assert set(value['conditions']) == {'Ослеплён', 'Испуган'}
    assert value['hp_current'] == 7
    assert post(api, root + 'conditions/', change, key='delta-condition-save').json() == saved.json()
    assert api.get(root).json()['data']['sheet']['version'] == value['version']
    removed = post(api, root + 'conditions/', {'add': {}, 'remove': ['Ослеплён']})
    assert removed.json()['data']['conditions'] == ['Испуган']
    for bad in ({'add': ['fake']}, {'remove': ['fake']}, {'add': 'Ослеплён'}, {'add': ['Ослеплён'], 'remove': ['Ослеплён']}):
        assert post(api, root + 'conditions/', bad).status_code == 400
    other = world[3].character_set.create(owner=world[0], name='Other')
    assert post(api, f'/api/integrations/dmhub/sheets/{other.pk}/conditions/', change).status_code == 403


def test_native_character_picker_has_real_folders_with_scoped_access(world, native):
    dm, player, _, campaign, character, _ = world
    api, _ = native
    hidden = CharacterFolder.objects.create(campaign=campaign, owner=dm, name='Secret NPC')
    own = CharacterFolder.objects.create(campaign=campaign, owner=player, name='My companions')
    npc = campaign.character_set.create(owner=dm, name='Hidden NPC', kind='npc', folder=hidden)
    companion = campaign.character_set.create(owner=player, name='Companion', kind='npc', folder=own)
    loose = campaign.character_set.create(owner=dm, name='Unfiled', kind='npc')
    root = '/api/integrations/dmhub/sheets/'
    data = api.get(root).json()['data']
    assert {c['id'] for c in data['characters']} == {character.pk, companion.pk}
    assert {f['id'] for f in data['folders']} == {character.folder_id, own.pk}
    assert next(c for c in data['characters'] if c['id'] == companion.pk)['folder'] == own.pk
    token = post(client(dm), scoped('/api/integrations/dmhub/sheet-access/', campaign),
                 {'action': 'rotate'}).json()['data']['token']
    master = APIClient(HTTP_AUTHORIZATION='Bearer ' + token).get(root).json()['data']
    assert hidden.pk in {f['id'] for f in master['folders']}
    assert next(c for c in master['characters'] if c['id'] == npc.pk)['folder'] == hidden.pk
    assert next(c for c in master['characters'] if c['id'] == loose.pk)['folder'] is None
