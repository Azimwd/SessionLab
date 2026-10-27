from lab.models import CharacterFolder, Character, InitiativeTracker, RoomEvent, Campaign, Membership, DMHubSheetAccess
from .test_api import world, post as api_post
from .test_dmhub_dice import personal
ROOT='/api/integrations/dmhub/room/'


def post(api, path, body, **kwargs):
    if body.get('command') == 'initiative' and 'session' not in body:
        body = {**body, 'session': api.get(ROOT).json()['data']['session']['id']}
    return api_post(api, path, body, **kwargs)



def test_native_room_visibility_and_preview(world):
    dm, player, outsider, c, char, session=world
    master,user=personal(dm,c),personal(player,c)
    folder=CharacterFolder.objects.create(campaign=c,owner=dm,name='Secret',visible_to_players=False)
    npc=Character.objects.create(campaign=c,owner=dm,kind='npc',name='Hidden boss',folder=folder)
    assert any(x['id']==npc.pk for x in master.get(ROOT).json()['data']['npcs'])
    assert not user.get(ROOT).json()['data']['npcs']
    assert not master.get(ROOT+'?view=player').json()['data']['master_view']
    cmd={'command':'visibility','scope':'folder','folder':float(folder.pk),'visible':True}
    assert post(user,ROOT+'commands/',cmd).status_code==403
    result=post(master,ROOT+'commands/',cmd,key='show-folder-once')
    assert result.status_code==200
    assert post(master,ROOT+'commands/',cmd,key='show-folder-once').json()==result.json()
    assert any(x['id']==npc.pk for x in user.get(ROOT).json()['data']['npcs'])
    assert post(master,ROOT+'commands/',{'command':'visibility','scope':'character','character':npc.pk,'visible':False}).status_code==200
    assert not user.get(ROOT).json()['data']['npcs']
    assert 'own_characters' not in user.get(ROOT).json()['data']
    assert user.get(ROOT)['Cache-Control']=='no-store'


def test_native_initiative_versions_retries_hidden_turns(world):
    dm,player,outsider,c,char,session=world
    master,user=personal(dm,c),personal(player,c)
    cmd={'command':'initiative','action':'start','version':0,'participants':[{'character':char.pk},{'name':'Goblin','count':2,'bonus':3}]}
    assert post(user,ROOT+'commands/',cmd).status_code==403
    result=post(master,ROOT+'commands/',cmd,key='native-start-once')
    assert result.status_code==200,result.content
    t=result.json()['data']
    assert t['running'] and len(t['entries'])==3
    assert post(master,ROOT+'commands/',cmd,key='native-start-once').json()==result.json()
    assert RoomEvent.objects.filter(campaign=c,kind='roll').count()==3
    assert post(master,ROOT+'commands/',{'command':'initiative','action':'next','version':0}).status_code==409
    for i in range(3):
        result=post(master,ROOT+'commands/',{'command':'initiative','action':'next','version':t['version']})
        assert result.status_code==200
        t=result.json()['data']
    assert t['round_number']==2
    tracker=InitiativeTracker.objects.get(session=session)
    entry=tracker.entries.get(pk=tracker.current_id);entry.hidden=True;entry.save()
    public=user.get(ROOT).json()['data']['initiative']
    assert public['current'] is None and public['hidden_turn']
    assert entry.pk not in [e['id'] for e in public['entries']]
    assert post(master,ROOT+'commands/',{'command':'initiative','action':'reset','version':t['version']}).status_code==200
    assert not user.get(ROOT).json()['data']['initiative']['entries']


def test_native_room_scope_and_revocation(world):
    dm,player,outsider,c,char,session=world
    other=Campaign.objects.create(owner=outsider,name='Foreign')
    Membership.objects.create(campaign=other,user=outsider,role='dm')
    folder=CharacterFolder.objects.create(campaign=other,owner=outsider,name='Private')
    master=personal(dm,c)
    assert post(master,ROOT+'commands/',{'command':'visibility','scope':'folder','folder':folder.pk,'visible':True}).status_code==404
    assert post(master,ROOT+'commands/',{'command':'initiative','action':'start','version':0,'participants':[{'character':999999}]}).status_code==404
    assert not InitiativeTracker.objects.filter(session=session).exists()
    assert post(master,ROOT+'commands/',{'command':'initiative','action':'start','version':0,'session':999999}).status_code==400
    DMHubSheetAccess.objects.filter(campaign=c,user=dm).update(enabled=False)
    assert master.get(ROOT).status_code==401
