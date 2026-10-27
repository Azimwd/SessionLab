from rest_framework.test import APIClient

from lab.models import Campaign, DMHubBridge, Membership, RoomEvent
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
