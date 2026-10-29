from unittest.mock import patch
import pytest
from lab.models import CharacterAbility, SceneTarget
from .test_api import world, client, post, scoped
from .test_scene import targets


@pytest.mark.parametrize('choice,success',[('none',0),('half',7),('full',15),('rules',0)])
def test_custom_save_success_rule_is_saved_and_snapshotted(world,choice,success):
    dm,p,_,c,ch,_=world
    _,ts=targets(world)
    api=client(p)
    created=post(api,scoped(f'/api/characters/{ch.pk}/abilities/',c),{
        'kind':'spell','name':'Своё заклинание','resolution':'save','save_ability':'dex',
        'dice':'1d20','damage_type':'fire','level':0,'save_success':choice})
    assert created.status_code==200,created.content
    ability=created.json()['data']
    assert ability['save_success']==choice
    with patch('lab.services.dice.secrets.randbelow',return_value=14):
        rolled=post(api,scoped(f'/api/abilities/{ability["id"]}/use/',c),{'slot_level':0})
    assert rolled.status_code==200,rolled.content
    result=rolled.json()['data']
    assert result['payload']['save']['failed_damage']==15
    assert result['payload']['save']['success_damage']==success
    # Editing the action later cannot alter an already rolled snapshot.
    CharacterAbility.objects.filter(pk=ability['id']).update(save_success='none')
    applied=post(api,scoped('/api/scene/damage/',c),{
        'source_event':result['id'],'targets':[t['id'] for t in ts],
        'outcomes':{str(ts[0]['id']):{'save_outcome':'success'},str(ts[1]['id']):{'save_outcome':'failure'}}})
    assert applied.status_code==200,applied.content
    assert SceneTarget.objects.get(pk=ts[0]['id']).hp_current==40-success
    assert SceneTarget.objects.get(pk=ts[1]['id']).hp_current==25


def test_save_success_rejects_unknown_values(world):
    c,ch=world[3],world[4]
    result=post(client(world[1]),scoped(f'/api/characters/{ch.pk}/abilities/',c),{
        'kind':'spell','name':'Bad','resolution':'save','save_success':'double'})
    assert result.status_code==400
