from unittest.mock import patch
import pytest
from lab.models import CharacterAbility, SceneTarget, RoomEvent, DamageApplication, InitiativeTracker, InitiativeEntry
from lab.services.sheets import sheet_for
from .test_api import world, client, post, scoped
from .test_scene import targets


def effect(**values):
    return {'id':'judgment','name':'Удар Суда','dice':'1d8','damage_type':'radiant','frequency':'turn','enabled':True,**values}


def attack(w, effects, count=1, dice='1', level=15):
    ch=w[4];ch.level=level;ch.save()
    return CharacterAbility.objects.create(character=ch,kind='attack',name='Sword',resolution='attack',roll_count=count,dice=dice,damage_type='slashing',attack_effects=effects)


def cast(w,a,data=None):
    r=post(client(w[1]),scoped(f'/api/abilities/{a.pk}/use/',w[3]),data or {})
    assert r.status_code==200,r.content
    return r.json()['data']


def apply(w,event,target,index=0,key=None):
    return post(client(w[1]),scoped('/api/scene/damage/',w[3]),{'source_event':event['id'],'part_index':index,'targets':[target],'outcomes':{str(target):{'hit':True}}},key)


@pytest.mark.parametrize('level,dice',[(3,'1d8'),(7,'1d10'),(10,'1d12'),(15,'2d10')])
def test_growth_is_snapshotted_and_critical_adds_upgraded_dice(world,level,dice):
    rules=effect(critical_upgrade=True,scaling=[{'level':7,'dice':'1d10'},{'level':10,'dice':'1d12'},{'level':15,'dice':'2d10'}])
    a=attack(world,[rules],level=level)
    with patch('lab.services.sheets.d20',return_value={'chosen':20,'total':22,'mode':'normal','values':[20],'modifier':2,'formula':'1d20+2'}):
        with patch('lab.services.dice.secrets.randbelow',return_value=0):e=cast(world,a)
    component=e['payload']['effects'][0]
    assert component['dice']==dice
    assert component['roll']['critical'] is True
    assert component['critical_bonus']['formula']=={'1d8':'1d10','1d10':'1d12','1d12':'1d20','2d10':'2d12'}[dice]
    assert component['roll']['total']==(6 if level==15 else 3)


def test_half_health_type_and_independent_defenses_without_hp_leak(world):
    _,ts=targets(world,{'slashing':'resistance','radiant':'immunity','necrotic':'vulnerability'})
    t=SceneTarget.objects.get(pk=ts[0]['id']);t.hp_current=10;t.save()
    a=attack(world,[effect(below_half_type='necrotic')],dice='10')
    with patch('lab.services.dice.secrets.randbelow',return_value=1):e=cast(world,a)
    # Editing the definition after casting must not change stored components.
    a.attack_effects=[];a.save()
    r=apply(world,e,t.pk,0,'typed-effect-once')
    assert r.status_code==200,r.content
    assert apply(world,e,t.pk,key='typed-effect-once').json()==r.json()
    t.refresh_from_db();assert t.hp_current==1 # 10/2 + 2*2
    resolution=DamageApplication.objects.get(source_event_id=e['id']).resolution
    assert [c['damage_type'] for c in resolution['components']]==['slashing','necrotic']
    assert 'resolution' not in str(r.json()) and 'hp_current' not in str(r.json())


def test_once_per_turn_shared_across_weapons_and_manual_reset(world):
    _,ts=targets(world);t=ts[0]['id']
    a=attack(world,[effect()]);b=attack(world,[effect()])
    with patch('lab.services.dice.secrets.randbelow',return_value=1):first=cast(world,a);second=cast(world,b)
    assert apply(world,first,t).status_code==200
    assert apply(world,second,t).status_code==200
    assert SceneTarget.objects.get(pk=t).hp_current==36 # (1+2)+1
    sh=sheet_for(world[4])
    reset=post(client(world[1]),scoped(f'/api/characters/{world[4].pk}/resources/',world[3]),{'action':'next_turn','version':sh.version})
    assert reset.status_code==200,reset.content
    with patch('lab.services.dice.secrets.randbelow',return_value=1):third=cast(world,a)
    assert apply(world,third,t).status_code==200
    assert SceneTarget.objects.get(pk=t).hp_current==33


def test_seal_first_attack_and_first_hit_are_independent_and_target_locked(world):
    _,ts=targets(world);t=ts[0]['id']
    tracker=InitiativeTracker.objects.create(session=world[5],running=True,round_number=1)
    entry=InitiativeEntry.objects.create(tracker=tracker,character=world[4],name='Hero',initiative=10)
    tracker.current=entry;tracker.save()
    a=attack(world,[effect(id='seal',damage_type='necrotic',target_required=True,advantage_first=True)],count=3)
    first=cast(world,a,{'effect_target':t})
    assert [p['roll']['mode'] for p in first['payload']['parts']]==['advantage','normal','normal']
    second=cast(world,a,{'effect_target':t})
    assert all(p['roll']['mode']=='normal' for p in second['payload']['parts'])
    assert apply(world,first,ts[1]['id'],2).status_code==400
    # First two attacks missed: apply only the third. The first-hit bonus remains.
    assert apply(world,first,t,2).status_code==200
    used=DamageApplication.objects.get(source_event_id=first['id']).resolution
    assert used['effect_keys']==[f'seal:{t}']
    assert apply(world,second,t,0).status_code==200
    assert DamageApplication.objects.get(source_event_id=second['id']).resolution['effect_keys']==[]
    sh=sheet_for(world[4])
    assert post(client(world[1]),scoped(f'/api/characters/{world[4].pk}/resources/',world[3]),{'action':'next_turn','version':sh.version}).status_code==400
    tracker.round_number=2;tracker.save()
    third=cast(world,a,{'effect_target':t})
    assert third['payload']['parts'][0]['roll']['mode']=='advantage'


def test_reduction_cannot_heal_and_effects_can_be_disabled(world):
    _,ts=targets(world);t=ts[0]['id']
    a=attack(world,[effect(id='innocent',sign=-1,dice='1d4')])
    with patch('lab.services.dice.secrets.randbelow',return_value=3):first=cast(world,a)
    assert apply(world,first,t).status_code==200
    assert SceneTarget.objects.get(pk=t).hp_current==40
    no_effects=cast(world,a,{'effects':[]})
    assert 'effects' not in no_effects['payload']
    assert apply(world,no_effects,t).status_code==200
    assert SceneTarget.objects.get(pk=t).hp_current==39


@pytest.mark.parametrize('bad',[[effect(damage_type={})],[effect(frequency=[])],[effect(dice='-1d8')],[effect(dice='99d8')],[effect(scaling=[{'level':0,'dice':'1d4'}])],[effect(enabled='yes')]])
def test_invalid_effects_are_rejected_cleanly(world,bad):
    r=post(client(world[1]),scoped(f'/api/characters/{world[4].pk}/abilities/',world[3]),{'kind':'attack','name':'Bad','attack_effects':bad})
    assert r.status_code==400,r.content


def test_assessment_choices_are_exclusive_and_unknown_effects_are_rejected(world):
    a=attack(world,[effect(id='sinful',group='assessment',enabled=False),effect(id='innocent',group='assessment',enabled=False,sign=-1)])
    url=scoped(f'/api/abilities/{a.pk}/use/',world[3]);api=client(world[1])
    assert post(api,url,{'effects':['sinful','innocent']}).status_code==400
    assert post(api,url,{'effects':['not-saved']}).status_code==400
    assert not RoomEvent.objects.filter(kind='ability').exists()


def test_exact_half_keeps_original_type_and_multiple_parts_share_first_hit_limit(world):
    _,ts=targets(world,{'radiant':'immunity','necrotic':'vulnerability'})
    t=SceneTarget.objects.get(pk=ts[0]['id']);t.hp_current=20;t.save()
    a=attack(world,[effect(below_half_type='necrotic')],count=2)
    with patch('lab.services.dice.secrets.randbelow',return_value=1):e=cast(world,a)
    response=post(client(world[1]),scoped('/api/scene/damage/',world[3]),{'source_event':e['id'],'parts':[
        {'part_index':i,'targets':[t.pk],'outcomes':{str(t.pk):{'hit':True}}} for i in [0,1]]})
    assert response.status_code==200,response.content
    t.refresh_from_db();assert t.hp_current==18 # first radiant bonus is immune; second is already spent
    assert DamageApplication.objects.filter(source_event_id=e['id']).count()==2


def test_optional_rider_can_wait_for_later_hit_but_not_be_forged(world):
    _,ts=targets(world);t=ts[0]['id']
    a=attack(world,[effect()],count=3)
    with patch('lab.services.dice.secrets.randbelow',return_value=1):e=cast(world,a)
    url=scoped('/api/scene/damage/',world[3]);api=client(world[1])
    wrong=post(api,url,{'source_event':e['id'],'part_index':0,'targets':[t],'outcomes':{str(t):{'hit':True,'effects':['fake']}}})
    assert wrong.status_code==400
    r=post(api,url,{'source_event':e['id'],'parts':[
        {'part_index':i,'targets':[t],'outcomes':{str(t):{'hit':True,'effects':[] if i<2 else ['judgment']}}} for i in range(3)]})
    assert r.status_code==200,r.content
    assert SceneTarget.objects.get(pk=t).hp_current==35 # 1 + 1 + (1+2)
    assert DamageApplication.objects.get(source_event_id=e['id'],part_index=0).resolution['effect_keys']==[]
    assert DamageApplication.objects.get(source_event_id=e['id'],part_index=2).resolution['effect_keys']==['judgment']


def test_native_empty_effect_list_is_normalized_in_nested_outcome(world):
    from .test_dmhub_dice import personal
    _,ts=targets(world);t=ts[0]['id'];a=attack(world,[effect()])
    e=cast(world,a)
    api=personal(world[1],world[3])
    result=post(api,'/api/integrations/dmhub/scene/commands/',{'command':'damage','session':world[5].pk,
        'source_event':e['id'],'targets':[t],'outcomes':{str(t):{'hit':True,'effects':{}}}})
    assert result.status_code==200,result.content
    assert SceneTarget.objects.get(pk=t).hp_current==39
