from unittest.mock import patch
import pytest
from lab.models import Character, CharacterAbility, CharacterSheet, SceneTarget, RoomEvent, Campaign, GameSession, DamageApplication
from lab.services.sheets import sheet_for
from .test_api import world, client, post, scoped


def targets(world, protection=None):
    dm,_,_,c,_,_=world
    npc=Character.objects.create(campaign=c,owner=dm,kind='npc',name='Стражник')
    CharacterSheet.objects.create(character=npc,hp_max=40,hp_current=40)
    r=post(client(dm),scoped('/api/scene/targets/',c),{'source':npc.id,'count':2,'defenses':protection or {}})
    assert r.status_code==200,r.content
    return npc,r.json()['data']['targets']


def event(world,save=False,attack=False,amount=21):
    _,p,_,c,ch,s=world
    payload={'label':'Тест','damage_type':'fire','damage':{'total':amount}}
    if save:payload['save']={'ability':'dex','dc':15,'failed_damage':amount,'success_damage':amount//2}
    if attack:payload['roll']={'total':18,'chosen':12,'mode':'normal'}
    return RoomEvent.objects.create(campaign=c,session=s,actor=p,character=ch,kind='ability',payload=payload)


def send(w,e,ids,outcomes=None,key=None):
    if outcomes is None:
        value={'save_outcome':'failure'} if 'save' in e.payload else {'hit':True} if 'roll' in e.payload else {}
        outcomes={str(i):value for i in ids}
    return post(client(w[1]),scoped('/api/scene/damage/',w[3]),{'source_event':e.id,'targets':ids,'outcomes':outcomes},key)


def test_immediate_instances_and_hidden_hp(world):
    npc,ts=targets(world)
    assert ts[0]['name']!=ts[1]['name']
    public=client(world[1]).get(scoped('/api/scene/targets/',world[3])).json()['data']['targets']
    assert all(set(t)=={'id','name','targetable','version'} for t in public)
    r=send(world,event(world),[ts[0]['id']]);assert r.status_code==200,r.content
    row=r.json()['data'][0]
    assert row['status']=='applied' and 'resolution' not in row and 'part' not in row
    assert SceneTarget.objects.get(pk=ts[0]['id']).hp_current==19
    assert SceneTarget.objects.get(pk=ts[1]['id']).hp_current==40
    npc.sheet.refresh_from_db();assert npc.sheet.hp_current==40
    own=client(world[1]).get(scoped('/api/scene/damage/',world[3])+'&status=applied').json()['data'][0]
    assert own['status']=='applied' and 'resolution' not in own
    assert not DamageApplication.objects.filter(status='pending').exists()


@pytest.mark.parametrize('defense,hp',[('normal',30),('resistance',35),('immunity',40),('vulnerability',20)])
def test_save_before_saved_defense(world,defense,hp):
    _,ts=targets(world,{'fire':defense})
    r=send(world,event(world,save=True),[ts[0]['id']],{str(ts[0]['id']):{'save_outcome':'success'}})
    assert r.status_code==200,r.content
    assert SceneTarget.objects.get(pk=ts[0]['id']).hp_current==hp


def test_idempotency_temp_hp_and_double_apply(world):
    _,ts=targets(world)
    t=SceneTarget.objects.get(pk=ts[0]['id']);t.hp_temp=7;t.save()
    ev=event(world,amount=15)
    row=send(world,ev,[t.id],key='same-request-123').json()['data'][0]
    assert send(world,ev,[t.id],key='same-request-123').json()['data'][0]['id']==row['id']
    assert send(world,ev,[t.id]).status_code==400
    assert DamageApplication.objects.count()==1
    t.refresh_from_db();assert t.hp_current==32 and t.hp_temp==0
    r=post(client(world[1]),scoped(f"/api/scene/damage/{row['id']}/resolve/",world[3]),{'action':'apply'})
    assert r.status_code==400
    t.refresh_from_db();assert t.hp_current==32


def test_permissions_hidden_and_foreign_targets(world):
    _,ts=targets(world)
    dm,p,o,c,_,_=world
    t=SceneTarget.objects.get(pk=ts[0]['id']);t.visible=False;t.save()
    ev=event(world)
    assert send(world,ev,[t.id]).status_code==400
    assert len(client(p).get(scoped('/api/scene/targets/',c)).json()['data']['targets'])==1
    assert post(client(p),scoped('/api/scene/targets/',c),{'source':t.source_id}).status_code==403
    assert client(o).get(scoped('/api/scene/targets/',c)).status_code==403
    other=Campaign.objects.create(name='Other',owner=dm)
    session=GameSession.objects.create(campaign=other,name='Other',status='active')
    foreign=SceneTarget.objects.create(session=session,source=t.source,name='Foreign')
    assert send(world,ev,[foreign.id]).status_code==400
    ev.actor=dm;ev.save();assert send(world,ev,[ts[1]['id']]).status_code==403


def test_attack_one_target_and_player_miss(world):
    _,ts=targets(world)
    ev=event(world,attack=True)
    assert send(world,ev,[t['id'] for t in ts]).status_code==400
    r=send(world,ev,[ts[0]['id']],{str(ts[0]['id']):{'hit':False}});assert r.status_code==200,r.content
    assert send(world,ev,[ts[1]['id']]).status_code==400
    assert SceneTarget.objects.get(pk=ts[0]['id']).hp_current==40


def test_per_target_save_and_atomic_validation(world):
    _,ts=targets(world)
    ev=event(world,save=True)
    outcomes={str(ts[0]['id']):{'save_outcome':'failure'}}
    r=send(world,ev,[t['id'] for t in ts],outcomes);assert r.status_code==400,r.content
    assert list(SceneTarget.objects.values_list('hp_current',flat=True))==[40,40]
    assert DamageApplication.objects.count()==0
    outcomes[str(ts[1]['id'])]={'save_outcome':'success'}
    assert send(world,ev,[t['id'] for t in ts],outcomes).status_code==200
    assert list(SceneTarget.objects.order_by('id').values_list('hp_current',flat=True))==[19,30]


def test_linked_player(world):
    dm,_,_,c,ch,_=world
    sh=sheet_for(ch);sh.hp_max=30;sh.hp_current=25;sh.save()
    t=post(client(dm),scoped('/api/scene/targets/',c),{'source':ch.id}).json()['data']['targets'][0]
    assert t['hp_current']==25 and t['linked_sheet']
    assert post(client(dm),scoped('/api/scene/targets/',c),{'source':ch.id}).status_code==400
    assert send(world,event(world,amount=9),[t['id']]).status_code==200
    sh.refresh_from_db();assert sh.hp_current==16


@pytest.mark.parametrize('mode,chosen',[('advantage',19),('disadvantage',2)])
def test_spell_attack_modes(world,mode,chosen):
    _,p,_,c,ch,_=world
    ability=CharacterAbility.objects.create(character=ch,kind='spell',name='Луч',level=0,dice='1d4',resolution='attack')
    with patch('lab.services.dice.secrets.randbelow',side_effect=[1,18,1]):
        r=post(client(p),scoped(f'/api/abilities/{ability.id}/use/',c),{'mode':mode,'slot_level':0})
    assert r.status_code==200,r.content
    roll=r.json()['data']['payload']['roll'];assert roll['mode']==mode and roll['chosen']==chosen and roll['values']==[2,19]


def test_conditions_are_independent_and_private(world):
    npc,ts=targets(world);t=ts[0]
    r=client(world[0]).patch(scoped(f"/api/scene/targets/{t['id']}/",world[3]),
        {'version':t['version'],'conditions':['Ослеплён']},format='json',HTTP_IDEMPOTENCY_KEY='conditions-on-target')
    assert r.status_code==200,r.content
    assert SceneTarget.objects.get(pk=t['id']).conditions==['Ослеплён']
    assert SceneTarget.objects.get(pk=ts[1]['id']).conditions==[] and npc.sheet.conditions==[]


def test_hidden_target_log_is_private(world):
    _,ts=targets(world);t=SceneTarget.objects.get(pk=ts[0]['id']);t.visible=False;t.save()
    e=event(world)
    r=post(client(world[0]),scoped('/api/scene/damage/',world[3]),{'source_event':e.id,'targets':[t.id]})
    assert r.status_code==200,r.content
    assert RoomEvent.objects.filter(kind='damage').latest('id').visibility=='dm'


@pytest.mark.parametrize('extra',[{'defense':'normal'},{'base_damage':999999},{'hp_current':0}])
def test_client_cannot_override_protection_or_amount(world,extra):
    _,ts=targets(world,{'fire':'immunity'});e=event(world)
    body={'source_event':e.id,'targets':[ts[0]['id']],**extra}
    assert post(client(world[1]),scoped('/api/scene/damage/',world[3]),body).status_code==400
    assert send(world,e,[ts[0]['id']],{str(ts[0]['id']):extra}).status_code==400
    assert SceneTarget.objects.get(pk=ts[0]['id']).hp_current==40
    assert send(world,e,[ts[0]['id']]).status_code==200
    assert SceneTarget.objects.get(pk=ts[0]['id']).hp_current==40


def test_legacy_pending_author_applies_and_other_player_denied(world):
    _,ts=targets(world,{'fire':'resistance'});e=event(world,save=True)
    row=DamageApplication.objects.create(target_id=ts[0]['id'],source_event=e,requester=world[1])
    from lab.models import Membership
    Membership.objects.create(campaign=world[3],user=world[2])
    path=scoped(f'/api/scene/damage/{row.id}/resolve/',world[3])
    assert post(client(world[2]),path,{'action':'apply','save_outcome':'failure'}).status_code==403
    r=post(client(world[1]),path,{'action':'apply','save_outcome':'failure'})
    assert r.status_code==200,r.content
    assert r.json()['data']['status']=='applied' and 'resolution' not in r.json()['data']
    assert SceneTarget.objects.get(pk=ts[0]['id']).hp_current==30


def test_existing_pending_reused_without_duplicate(world):
    _,ts=targets(world);e=event(world)
    row=DamageApplication.objects.create(target_id=ts[0]['id'],source_event=e,requester=world[1])
    r=send(world,e,[ts[0]['id']]);assert r.status_code==200,r.content
    assert r.json()['data'][0]['id']==row.id and DamageApplication.objects.count()==1


def test_old_attack_reservation_can_be_reassigned(world):
    _,ts=targets(world);e=event(world,attack=True)
    row=DamageApplication.objects.create(target_id=ts[0]['id'],source_event=e,requester=world[1],is_attack=True)
    assert send(world,e,[ts[1]['id']]).status_code==200
    row.refresh_from_db();assert row.status=='rejected'
    assert SceneTarget.objects.get(pk=ts[0]['id']).hp_current==40
    assert SceneTarget.objects.get(pk=ts[1]['id']).hp_current==19


def test_postgres_lock_excludes_nullable_join():
    from django.db.backends.postgresql.base import DatabaseWrapper
    db=DatabaseWrapper({'ENGINE':'django.db.backends.postgresql','NAME':'compile_only','OPTIONS':{},'TIME_ZONE':None},alias='sql_test')
    with patch.object(db,'get_autocommit',return_value=False),patch.object(db,'ensure_connection'):
        query=DamageApplication.objects.select_for_update(of=('self',)).select_related('target__source__sheet','source_event','requester')
        sql,_=query.query.get_compiler(connection=db).as_sql()
    assert 'LEFT OUTER JOIN "lab_charactersheet"' in sql
    assert sql.endswith('FOR UPDATE OF "lab_damageapplication"')


def test_room_history_redacts_foreign_health(world):
    dm,_,_,c,ch,s=world
    RoomEvent.objects.create(campaign=c,session=s,actor=dm,character=ch,kind='resource',payload={'label':'ХП','hp_current':7,'hp_max':30,'hp_temp':4})
    from lab.models import Membership
    Membership.objects.create(campaign=c,user=world[2])
    public=client(world[2]).get(scoped('/api/room/events/',c)).json()['data']['results'][0]
    assert 'hp_current' not in public['payload'] and 'hp_max' not in public['payload']
    assert client(dm).get(scoped('/api/room/events/',c)).json()['data']['results'][0]['payload']['hp_current']==7
