from rest_framework.test import APIClient

from lab.models import Campaign, CharacterAbility, DMHubBridge, DMHubSheetAccess, Membership, RoomEvent
from lab.services.sheets import event
from .test_api import client, post, scoped, world


def test_dmhub_bridge_only_public_scoped_saved_events(world):
    dm, player, outsider, campaign, character, session = world
    config = scoped('/api/dm/integrations/dmhub/', campaign)
    assert client(player).get(config).status_code == 403
    assert post(client(player), config, {'action': 'rotate'}).status_code == 403
    result = post(client(dm), config, {'action': 'rotate'})
    assert result.status_code == 200
    token = result.json()['data']['token']
    assert len(token) >= 32
    assert token not in str(DMHubBridge.objects.get(campaign=campaign).__dict__)
    assert token not in str(client(dm).get(config).json())

    feed = '/api/integrations/dmhub/events/'
    outsider_client = APIClient()
    assert outsider_client.get(feed + '?cursor=0').status_code == 401
    assert outsider_client.get(feed + '?cursor=0', HTTP_AUTHORIZATION='Bearer incorrect').status_code == 401
    consumer = APIClient(HTTP_AUTHORIZATION='Bearer ' + token)
    assert consumer.get(feed + '?cursor=latest').json()['data'] == {'events': [], 'cursor': 0}
    other = Campaign.objects.create(name='Other', owner=dm)
    Membership.objects.create(campaign=other, user=dm, role='dm')
    other_session = other.sessions.create(name='Other', status='active')
    event(other, other_session, dm, None, 'roll', {'label': 'Other', 'roll': {'total': 100}})
    first = event(campaign, session, player, character, 'ability', {
        'label': 'Огненный шар', 'kind': 'spell', 'slot_level': 4,
        'damage': {'total': 29}, 'save': {'ability': 'dex', 'dc': 15,
                                        'failed_damage': 29, 'success_damage': 14},
    })
    event(campaign, session, dm, None, 'roll', {'label': 'Секрет', 'roll': {'total': 20}}, 'dm')
    second = event(campaign, session, player, character, 'roll', {
        'label': 'Восприятие', 'roll': {'total': 18, 'formula': '1d20+3'}
    })
    description = 'Дубинка становится живым деревом. ' + 'Его ветви удерживают врагов. ' * 18
    third = event(campaign, session, player, character, 'ability', {
        'label': 'Пробуждение дерева', 'description': description,
    })
    batch = consumer.get(feed + '?cursor=0').json()['data']
    assert [e['id'] for e in batch['events']] == [first.pk, second.pk, third.pk]
    assert 'Огненный шар' in batch['events'][0]['text']
    assert 'СЛ 15' in batch['events'][0]['text']
    assert 'провал 29, успех 14' in batch['events'][0]['text']
    assert batch['events'][0]['title'] == 'Огненный шар'
    assert batch['events'][0]['actor'] == character.name
    assert batch['events'][0]['summary'].startswith('Ячейка 4 · ')
    assert batch['events'][0]['display'] == {
        'primary': {'label': 'Урон', 'value': 29},
        'secondary': {'label': 'СЛ спасброска', 'value': 15},
        'detail': 'Ячейка 4 · Провал 29 · успех 14',
    }
    assert batch['events'][1]['summary'] == '18 (1d20+3)'
    assert batch['events'][1]['display'] == {
        'primary': {'label': 'Бросок', 'value': 18},
        'secondary': None, 'detail': '1d20+3',
    }
    assert len(batch['events'][2]['summary']) < len(description)
    assert batch['events'][2]['display']['description'] == description.strip()
    assert 'Секрет' not in str(batch)
    assert consumer.get(feed + '?cursor=' + str(batch['cursor'])).json()['data']['events'] == []
    assert consumer.get(feed + '?cursor=-1').status_code == 400
    rotated = post(client(dm), config, {'action': 'rotate'}).json()['data']['token']
    assert rotated != token
    assert consumer.get(feed + '?cursor=0').status_code == 401
    assert APIClient(HTTP_AUTHORIZATION='Bearer ' + rotated).get(feed + '?cursor=0').status_code == 200
    assert post(client(dm), config, {'action': 'revoke'}).status_code == 200
    assert APIClient(HTTP_AUTHORIZATION='Bearer ' + rotated).get(feed + '?cursor=0').status_code == 401


def test_lua_chat_message_is_code_safe():
    import importlib.util
    from pathlib import Path
    script = Path(__file__).resolve().parents[3] / 'scripts' / 'dmhub_bridge.py'
    spec = importlib.util.spec_from_file_location('sessionlab_dmhub_bridge', script)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    code = module.chat_lua('Маг "); os.execute("bad")')
    assert code.startswith('chat.Send(string.char(')
    assert 'os.execute' not in code
    assert 'bad' not in code


def test_sheet_bridge_bound_to_member_and_idempotent(world):
    dm, player, outsider, campaign, character, session = world
    settings = scoped('/api/integrations/dmhub/sheet-access/', campaign)
    created = post(client(player), settings, {'action': 'rotate'})
    assert created.status_code == 200
    token = created.json()['data']['token']
    assert token not in str(DMHubSheetAccess.objects.get(user=player).__dict__)
    bearer = APIClient(HTTP_AUTHORIZATION='Bearer ' + token)
    root = '/api/integrations/dmhub/sheets/'
    assert bearer.get(root).json()['data']['characters'][0]['id'] == character.pk
    detail = bearer.get(f'{root}{character.pk}/').json()['data']
    assert detail['sheet']['computed']['skills']['perception'] == 0
    assert bearer.get(root, HTTP_AUTHORIZATION='Bearer nonsense').status_code in (401, 403)
    other = Campaign.objects.create(name='Other', owner=outsider)
    Membership.objects.create(campaign=other, user=outsider, role='dm')
    foreign = other.character_set.create(owner=outsider, name='Secret')
    assert bearer.get(f'{root}{foreign.pk}/').status_code == 404

    roll = f'{root}{character.pk}/roll/'
    first = post(bearer, roll, {'kind': 'skill', 'key': 'perception'}, key='same-roll-key')
    assert first.status_code == 200
    again = post(bearer, roll, {'kind': 'skill', 'key': 'perception'}, key='same-roll-key')
    assert again.json() == first.json()
    assert RoomEvent.objects.filter(campaign=campaign, kind='roll').count() == 1
    assert post(bearer, roll, {'kind': 'skill', 'key': 'arcana'}, key='same-roll-key').status_code == 400
    assert post(bearer, roll, {'kind': 'skill', 'key': 'perception'}).status_code == 200

    resource = f'{root}{character.pk}/resources/'
    health = post(bearer, resource, {'action': 'damage', 'amount': 4}, key='same-damage-key')
    assert health.status_code == 200
    assert health.json()['data']['hp_current'] == 6
    assert post(bearer, resource, {'action': 'damage', 'amount': 4}, key='same-damage-key').json() == health.json()
    assert bearer.get(f'{root}{character.pk}/').json()['data']['sheet']['hp_current'] == 6

    spell = CharacterAbility.objects.create(character=character, name='Test spell',
                                            kind='spell', level=1, resolution='save', dice='2d6')
    sheet = character.sheet
    sheet.slots['1']['max'] = 1
    sheet.save()
    use = f'{root}{character.pk}/abilities/{spell.pk}/use/'
    response = post(bearer, use, {'slot_level': 1}, key='one-cast-key')
    assert response.status_code == 200, response.json()
    assert post(bearer, use, {'slot_level': 1}, key='one-cast-key').json() == response.json()
    sheet.refresh_from_db()
    assert sheet.slots['1']['used'] == 1
    assert post(bearer, use, {'slot_level': 1}).status_code == 400
    assert RoomEvent.objects.filter(campaign=campaign, kind='ability').count() == 1

    rotated = post(client(player), settings, {'action': 'rotate'}).json()['data']['token']
    assert bearer.get(root).status_code in (401, 403)
    fresh = APIClient(HTTP_AUTHORIZATION='Bearer ' + rotated)
    assert fresh.get(root).status_code == 200
    Membership.objects.filter(campaign=campaign, user=player).update(active=False)
    assert fresh.get(root).status_code == 403


def test_sheet_key_never_accepts_campaign_chat_key(world):
    dm, player, _, campaign, character, _ = world
    token = post(client(dm), scoped('/api/dm/integrations/dmhub/', campaign),
                 {'action': 'rotate'}).json()['data']['token']
    c = APIClient(HTTP_AUTHORIZATION='Bearer ' + token)
    assert c.get('/api/integrations/dmhub/sheets/').status_code in (401, 403)


def test_sheet_bridge_player_cannot_use_other_members_sheet(world):
    dm, player, outsider, campaign, character, _ = world
    second = campaign.character_set.create(owner=dm, name='Keeper')
    personal = post(client(player), scoped('/api/integrations/dmhub/sheet-access/', campaign),
                    {'action': 'rotate'}).json()['data']['token']
    p = APIClient(HTTP_AUTHORIZATION='Bearer ' + personal)
    root = '/api/integrations/dmhub/sheets/'
    assert [x['id'] for x in p.get(root).json()['data']['characters']] == [character.pk]
    assert p.get(f'{root}{second.pk}/').status_code == 403
    assert post(p, f'{root}{second.pk}/roll/', {'kind':'skill','key':'arcana'}).status_code == 403
    assert post(p, f'{root}{second.pk}/resources/', {'action':'damage','amount':5}).status_code == 403
    spell = CharacterAbility.objects.create(character=second, name='Attack', kind='attack')
    assert post(p, f'{root}{second.pk}/abilities/{spell.pk}/use/', {}).status_code == 403
    master_token = post(client(dm), scoped('/api/integrations/dmhub/sheet-access/', campaign),
                        {'action':'rotate'}).json()['data']['token']
    master = APIClient(HTTP_AUTHORIZATION='Bearer ' + master_token)
    assert {x['id'] for x in master.get(root).json()['data']['characters']} == {character.pk, second.pk}
