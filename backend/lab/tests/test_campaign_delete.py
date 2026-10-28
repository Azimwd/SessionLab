from lab.models import Campaign, Membership, DMHubBridge, DMHubSheetAccess, AuditLog, Character
from lab.api.dmhub import bridge_hash
from .test_api import world, client, scoped, post


def delete(api, campaign, name=None):
    return api.delete(f'/api/campaigns/{campaign.pk}/', {'confirm_name': campaign.name if name is None else name}, format='json')


def test_only_owner_can_delete_and_name_must_match(world):
    dm, player, outsider, campaign, char, session = world
    for user in [player, outsider]:
        assert delete(client(user), campaign).status_code == 403
    Membership.objects.filter(campaign=campaign, user=player).update(role='dm')
    assert delete(client(player), campaign).status_code == 403
    assert delete(client(dm), campaign, 'Wrong name').status_code == 400
    campaign.refresh_from_db()
    assert campaign.deleted_at is None
    assert Membership.objects.filter(campaign=campaign, active=True).count() == 2


def test_delete_revokes_everyone_and_retries_safely(world):
    dm, player, outsider, campaign, char, session = world
    bridge = DMHubBridge.objects.create(campaign=campaign, token_hash=bridge_hash('a'*48))
    access = DMHubSheetAccess.objects.create(campaign=campaign, user=player, token_hash=bridge_hash('b'*48))
    other = Campaign.objects.create(name='Other', owner=dm)
    Membership.objects.create(campaign=other, user=dm, role='dm')
    response = delete(client(dm), campaign)
    assert response.status_code == 200, response.content
    campaign.refresh_from_db()
    assert campaign.deleted_at is not None
    assert not Membership.objects.filter(campaign=campaign, active=True).exists()
    bridge.refresh_from_db(); access.refresh_from_db()
    assert not bridge.enabled and not access.enabled
    assert Character.objects.filter(pk=char.pk).exists()
    for user in [dm, player]:
        api = client(user)
        rows = api.get('/api/campaigns/').json()['data']['results']
        assert campaign.pk not in [row['id'] for row in rows]
        assert api.get(f'/api/campaigns/{campaign.pk}/').status_code == 404
        assert api.get(scoped('/api/room/', campaign)).status_code == 404
        assert post(api, '/api/campaigns/join/', {'code': campaign.invite_code}).status_code == 404
    assert delete(client(dm), campaign).status_code == 200
    assert AuditLog.objects.filter(campaign=campaign, action='campaign.delete').count() == 1
    assert client(dm).get(f'/api/campaigns/{other.pk}/').status_code == 200
