from lab.models import Character, CharacterSheet, SceneTarget, DamageApplication, RoomEvent, GameSession, Campaign, Membership
from .test_api import world, post, client, scoped
from .test_dmhub_dice import personal
from .test_scene import event, targets
ROOT = '/api/integrations/dmhub/scene/'


def command(api, session, data, key=None):
    return post(api, ROOT+'commands/', {'session':session.pk, **data}, key)


def test_native_scene_private_projection_and_own_rolls(world):
    dm, player, outsider, c, char, session = world
    npc, ts = targets(world, {'fire':'resistance'})
    own = event(world, save=True)
    own.payload['resources']={'hp_current':777}
    own.save()
    foreign = RoomEvent.objects.create(campaign=c,session=session,actor=dm,kind='ability',payload=own.payload)
    SceneTarget.objects.filter(pk=ts[1]['id']).update(visible=False)
    user, master = personal(player,c), personal(dm,c)
    data = user.get(ROOT).json()['data']
    assert len(data['targets'])==1
    assert set(data['targets'][0])=={'id','name','targetable','version'}
    assert [s['id'] for s in data['sources']]==[own.pk]
    assert 'resources' not in str(data) and 'hp_current' not in str(data)
    full = master.get(ROOT).json()['data']
    assert len(full['targets'])==2 and full['targets'][0]['defenses']=={'fire':'resistance'}
    assert {s['id'] for s in full['sources']}=={own.pk,foreign.pk}
    preview = master.get(ROOT+'?view=player').json()['data']
    assert not preview['master_view'] and len(preview['targets'])==1
    assert 'hp_current' not in str(preview)
    assert user.get(ROOT)['Cache-Control']=='no-store'


def test_native_damage_shared_hp_defenses_and_idempotency(world):
    dm, player, _, c, char, session = world
    _, ts = targets(world, {'fire':'resistance'})
    e = event(world, save=True)
    user = personal(player,c)
    data = {'command':'damage','source_event':e.pk,'part_index':0,'targets':[t['id'] for t in ts],
            'outcomes':{str(ts[0]['id']):{'save_outcome':'failure'},str(ts[1]['id']):{'save_outcome':'success'}}}
    r = command(user,session,data,'native-damage-once')
    assert r.status_code==200,r.content
    assert command(user,session,data,'native-damage-once').json()==r.json()
    assert DamageApplication.objects.count()==2
    assert [SceneTarget.objects.get(pk=t['id']).hp_current for t in ts]==[30,35]
    assert 'resolution' not in str(r.json()) and 'hp_current' not in str(r.json())
    assert command(user,session,data).status_code==400
    web = client(dm).get(scoped('/api/scene/targets/',c)).json()['data']['targets']
    assert [t['hp_current'] for t in web]==[30,35]
    assert len(user.get(ROOT).json()['data']['applications'])==2


def test_native_participants_permissions_versions_and_linked_player(world):
    dm, player, _, c, char, session = world
    master, user = personal(dm,c), personal(player,c)
    add = {'command':'add','source':char.pk,'count':1,'defenses':{'all':'immunity'}}
    assert command(user,session,add).status_code==403
    r=command(master,session,add);assert r.status_code==200,r.content
    t=r.json()['data']['targets'][0]
    update={'command':'update','target':t['id'],'version':t['version'],'hp_current':0,'visible':False,'defenses':{'fire':'vulnerability'}}
    assert command(user,session,update).status_code==403
    r=command(master,session,update);assert r.status_code==200,r.content
    char.sheet.refresh_from_db();assert char.sheet.hp_current==0
    assert command(master,session,update).status_code==409
    assert not user.get(ROOT).json()['data']['targets']
    t=r.json()['data']
    assert command(master,session,{'command':'update','target':t['id'],'version':t['version'],'active':False}).status_code==200
    assert not master.get(ROOT).json()['data']['targets']


def test_native_damage_rejects_tampering_and_foreign_events(world):
    dm, player, outsider, c, char, session = world
    _, ts = targets(world)
    e=event(world,attack=True)
    user=personal(player,c)
    base={'command':'damage','source_event':e.pk,'targets':[ts[0]['id']],'outcomes':{str(ts[0]['id']):{'hit':True}}}
    assert command(user,session,{**base,'base_damage':900}).status_code==400
    assert command(user,session,{**base,'outcomes':{str(ts[0]['id']):{'hit':True,'defense':'immunity'}}}).status_code==400
    assert command(user,session,{**base,'session':session.pk+999}).status_code==400
    assert not DamageApplication.objects.exists()
    RoomEvent.objects.filter(pk=e.pk).update(actor=dm)
    assert command(user,session,base).status_code==403
    RoomEvent.objects.filter(pk=e.pk).update(actor=player)
    SceneTarget.objects.filter(pk=ts[0]['id']).update(targetable=False)
    assert command(user,session,base).status_code==400
    SceneTarget.objects.filter(pk=ts[0]['id']).update(targetable=True,visible=False)
    assert command(user,session,base).status_code==400
    other=Campaign.objects.create(name='Other',owner=outsider)
    other_session=GameSession.objects.create(campaign=other,name='Other',status='active')
    foreign=RoomEvent.objects.create(campaign=other,session=other_session,actor=player,kind='ability',payload=e.payload)
    assert command(user,session,{**base,'source_event':foreign.pk}).status_code==404
    assert not DamageApplication.objects.exists()
