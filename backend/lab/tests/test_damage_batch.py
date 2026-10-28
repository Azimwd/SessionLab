from lab.models import SceneTarget, DamageApplication
from .test_api import world, client, post, scoped
from .test_scene import targets, event


def multi(world,attack=True):
    e=event(world)
    e.payload={'damage_type':'fire','parts':[{'damage':{'total':v},**({'roll':{'total':18}} if attack else {})} for v in [11,7,6]]}
    e.save()
    return e


def payload(e,t):
    return {'source_event':e.pk,'parts':[{'part_index':i,'targets':[t],'outcomes':{str(t):{'hit':True}}} for i in range(3)]}


def send_batch(world,data,key=None):
    return post(client(world[1]),scoped('/api/scene/damage/',world[3]),data,key)


def test_attack_batch_uses_each_roll_and_defense_and_replays_once(world):
    _,ts=targets(world,{'fire':'resistance'});e=multi(world);t=ts[0]['id'];data=payload(e,t)
    data['parts'][2]['outcomes'][str(t)]={'hit':False}
    r=send_batch(world,data,'batch-damage-once')
    assert r.status_code==200,r.content
    assert len(r.json()['data'])==3
    assert SceneTarget.objects.get(pk=t).hp_current==32 # floor(11/2)+floor(7/2)+miss
    assert DamageApplication.objects.filter(source_event=e).count()==3
    assert send_batch(world,data,'batch-damage-once').json()==r.json()
    assert SceneTarget.objects.get(pk=t).hp_current==32
    assert 'resolution' not in str(r.json()) and 'hp_current' not in str(r.json())
    assert send_batch(world,data).status_code==400


def test_batch_is_atomic_when_last_part_has_invalid_outcome(world):
    _,ts=targets(world);e=multi(world);t=ts[0]['id'];data=payload(e,t)
    data['parts'][2]['outcomes']={}
    assert send_batch(world,data).status_code==400
    assert not DamageApplication.objects.filter(source_event=e).exists()
    assert SceneTarget.objects.get(pk=t).hp_current==40
    data['parts'][2]['outcomes']={str(t):{'hit':True}}
    assert send_batch(world,data).status_code==200
    assert SceneTarget.objects.get(pk=t).hp_current==16


def test_duplicate_or_invalid_batch_parts_do_not_apply_anything(world):
    _,ts=targets(world);e=multi(world);t=ts[0]['id'];data=payload(e,t)
    data['parts'][1]['part_index']=0
    assert send_batch(world,data).status_code==400
    data['parts'][1]['part_index']=19
    assert send_batch(world,data).status_code==400
    assert SceneTarget.objects.get(pk=t).hp_current==40
    assert not DamageApplication.objects.filter(source_event=e).exists()


def test_automatic_damage_batch_requires_no_hit_and_uses_selected_parts_only(world):
    _,ts=targets(world);e=multi(world,attack=False);t=ts[0]['id']
    data={'source_event':e.pk,'parts':[{'part_index':i,'targets':[t],'outcomes':{}} for i in [0,2]]}
    r=send_batch(world,data);assert r.status_code==200,r.content
    assert SceneTarget.objects.get(pk=t).hp_current==23
    assert set(DamageApplication.objects.filter(source_event=e).values_list('part_index',flat=True))=={0,2}
