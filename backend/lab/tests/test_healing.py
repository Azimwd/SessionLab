import pytest
from lab.models import SceneTarget, DamageApplication, RoomEvent
from lab.services.sheets import sheet_for
from .test_api import world, client, post, scoped
from .test_scene import event, targets, send
from .test_dmhub_dice import personal


def healing(world, amount=21, alias='лечение'):
    e=event(world,amount=amount)
    e.payload['damage_type']=alias
    e.save()
    return e


@pytest.mark.parametrize('alias',['healing','heal','лечение','исцеление',' HEALING '])
def test_healing_caps_at_max_ignores_defenses_and_keeps_temp_hp(world,alias):
    _, ts=targets(world,{'all':'immunity'})
    t=SceneTarget.objects.get(pk=ts[0]['id']);t.hp_current=35;t.hp_temp=8;t.save()
    e=healing(world,alias=alias)
    r=send(world,e,[t.pk],{})
    assert r.status_code==200,r.content
    t.refresh_from_db();assert (t.hp_current,t.hp_temp)==(40,8)
    assert r.json()['data'][0]['effect']=='healing'
    assert 'hp_current' not in str(r.json()) and 'resolution' not in str(r.json())
    record=DamageApplication.objects.get(source_event=e)
    assert record.resolution['final_healing']==5
    assert record.resolution['base_healing']==21
    assert RoomEvent.objects.filter(kind='healing',campaign=world[3]).count()==1
    assert send(world,e,[t.pk],{}).status_code==400


def test_healing_linked_player_and_native_share_state(world):
    dm,p,_,c,ch,s=world
    sh=sheet_for(ch);sh.hp_current=0;sh.hp_max=30;sh.hp_temp=4;sh.death_failures=2;sh.save()
    r=post(client(dm),scoped('/api/scene/targets/',c),{'source':ch.pk})
    target=r.json()['data']['targets'][0]
    e=healing(world,amount=7)
    api=personal(p,c)
    source=next(v for v in api.get('/api/integrations/dmhub/scene/').json()['data']['sources'] if v['id']==e.pk)
    assert source['effect']=='healing'
    body={'session':s.pk,'command':'damage','source_event':e.pk,'targets':[target['id']],'outcomes':{}}
    r=post(api,'/api/integrations/dmhub/scene/commands/',body,key='healing-native-once')
    assert r.status_code==200,r.content
    assert post(api,'/api/integrations/dmhub/scene/commands/',body,key='healing-native-once').json()==r.json()
    sh.refresh_from_db();assert (sh.hp_current,sh.hp_temp,sh.death_failures)==(7,4,0)
    assert DamageApplication.objects.filter(source_event=e).count()==1


def test_player_cannot_override_effect_or_healing_amount(world):
    _,ts=targets(world)
    e=healing(world)
    assert send(world,e,[ts[0]['id']],{str(ts[0]['id']):{'base_damage':999}}).status_code==400
    assert send(world,e,[ts[0]['id']],{str(ts[0]['id']):{'hit':True}}).status_code==400
    base={'source_event':e.pk,'targets':[ts[0]['id']],'effect':'damage'}
    assert post(client(world[1]),scoped('/api/scene/damage/',world[3]),base).status_code==400
    SceneTarget.objects.filter(pk=ts[0]['id']).update(visible=False)
    assert send(world,e,[ts[0]['id']],{}).status_code==400
    assert not DamageApplication.objects.exists()
