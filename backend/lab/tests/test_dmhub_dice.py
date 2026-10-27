from rest_framework.test import APIClient

from lab.models import Campaign, DMHubBridge, Membership, RoomEvent
from lab.api.dmhub import bridge_hash
from .test_api import client, post, scoped, world


def personal(user, campaign):
    token = post(client(user), scoped('/api/integrations/dmhub/sheet-access/', campaign),
                 {'action': 'rotate'}).json()['data']['token']
    return APIClient(HTTP_AUTHORIZATION='Bearer ' + token)


def test_native_dice_mix_identity_idempotency_and_limits(world):
    dm, player, outsider, campaign, character, session = world
    api = personal(player, campaign)
    root = '/api/integrations/dmhub/dice/'
    body = {'character': float(character.pk), 'formula': '2d20+1d4+3', 'visibility': 'public'}
    first = post(api, root, body, key='native-combined-roll')
    assert first.status_code == 200, first.json()
    ev = RoomEvent.objects.get(pk=first.json()['data']['id'])
    assert ev.actor == player and ev.character == character and ev.visibility == 'public'
    assert ev.payload['roll']['formula'] == '2d20+1d4+3'
    terms = ev.payload['roll']['terms']
    assert len(terms[0]['values']) == 2 and terms[0]['sides'] == 20
    assert len(terms[1]['values']) == 1 and terms[1]['sides'] == 4
    assert first.json()['data']['actor'] == character.name
    assert post(api, root, body, key='native-combined-roll').json() == first.json()
    assert RoomEvent.objects.filter(campaign=campaign, kind='roll').count() == 1
    other = campaign.character_set.create(owner=dm, name='GM character')
    assert post(api, root, {**body, 'character': other.pk}).status_code == 403
    assert post(api, root, {**body, 'character': None}).status_code == 400
    for formula in ('51d20', '1d3', '__import__("os")', ''):
        assert post(api, root, {**body, 'formula': formula}).status_code == 400
    assert post(api, root, {**body, 'visibility': 'unknown'}).status_code == 400
    master = personal(dm, campaign)
    result = post(master, root, {'formula': '1d100', 'visibility': 'public'})
    assert result.status_code == 200 and result.json()['data']['actor'] == 'Мастер'
    assert master.get('/api/integrations/dmhub/sheets/').json()['data']['is_dm'] is True
    assert api.get('/api/integrations/dmhub/sheets/').json()['data']['is_dm'] is False


def test_native_private_dice_only_go_to_master_feed(world):
    dm, player, outsider, campaign, character, session = world
    api, master = personal(player, campaign), personal(dm, campaign)
    campaign.memberships.create(user=outsider)
    viewer = personal(outsider, campaign)
    response = post(api, '/api/integrations/dmhub/dice/', {
        'character': character.pk, 'formula': '2d20+1d4', 'visibility': 'dm',
    })
    assert response.status_code == 200, response.json()
    private = response.json()['data']
    assert private['visibility'] == 'dm' and 'Только мастеру' in private['card']['tags']
    feed = '/api/integrations/dmhub/dice/events/?cursor=0'
    assert api.get(feed).json()['data']['events'] == []
    assert viewer.get(feed).json()['data']['events'] == []
    gm_events = master.get(feed)
    assert [row['id'] for row in gm_events.json()['data']['events']] == [private['id']]
    assert gm_events['Cache-Control'] == 'no-store'
    public_token = 'campaign-bridge-token-12345678901234567890'
    DMHubBridge.objects.create(campaign=campaign, enabled=True, token_hash=bridge_hash(public_token))
    public = APIClient(HTTP_AUTHORIZATION='Bearer ' + public_token)
    assert public.get('/api/integrations/dmhub/events/?cursor=0').json()['data']['events'] == []
    assert post(public, '/api/integrations/dmhub/dice/', {'formula': '1d20'}).status_code in (401, 403)
    assert public.get(feed).status_code in (401, 403)
    web = scoped('/api/room/events/', campaign)
    assert client(player).get(web).json()['data']['results'] == []
    assert client(dm).get(web).json()['data']['results'][0]['id'] == private['id']


def test_native_dice_session_and_cross_campaign_scope(world):
    dm, player, outsider, campaign, character, session = world
    api = personal(player, campaign)
    session.status = 'finished'
    session.save()
    response = post(api, '/api/integrations/dmhub/dice/', {'character': character.pk, 'formula': '1d20'})
    assert response.status_code == 400
    assert not RoomEvent.objects.filter(campaign=campaign, kind='roll').exists()
    assert api.get('/api/integrations/dmhub/dice/events/?cursor=-1').status_code == 400
    other = Campaign.objects.create(owner=outsider, name='Foreign')
    Membership.objects.create(campaign=other, user=outsider, role='dm')
    foreign = other.character_set.create(owner=outsider, name='Secret')
    other_session = other.sessions.create(name='Other', status='active')
    RoomEvent.objects.create(campaign=other, session=other_session, actor=outsider, character=foreign,
                            kind='roll', visibility='public', payload={'label': 'Do not leak'})
    assert post(api, '/api/integrations/dmhub/dice/', {'character': foreign.pk, 'formula': '1d20'}).status_code == 404
    assert api.get('/api/integrations/dmhub/dice/events/?cursor=0').json()['data']['events'] == []
