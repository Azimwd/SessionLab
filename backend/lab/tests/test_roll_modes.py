from unittest.mock import patch
import pytest
from lab.models import CharacterAbility
from lab.services.sheets import sheet_for
from .test_api import world, client, post, scoped
from .test_dmhub_dice import personal


def create(world,kind='attack',modes=None):
    return CharacterAbility.objects.create(character=world[4],kind=kind,name='Three attacks',level=0,
        resolution='attack',roll_count=3,roll_modes=modes or [],dice='')


def cast(world,ability,data=None,api=None,key=None):
    return post(api or client(world[1]),scoped(f'/api/abilities/{ability.pk}/use/',world[3]),data or {'slot_level':0},key)


@pytest.mark.parametrize('kind',['attack','spell'])
def test_independent_saved_roll_modes_and_idempotency(world,kind):
    a=create(world,kind,['advantage','normal','disadvantage'])
    with patch('lab.services.dice.secrets.randbelow',side_effect=[1,18,9,16,3]):
        response=cast(world,a,key='individual-modes-once')
    assert response.status_code==200,response.content
    parts=response.json()['data']['payload']['parts']
    assert [p['roll']['mode'] for p in parts]==['advantage','normal','disadvantage']
    assert [p['roll']['chosen'] for p in parts]==[19,10,4]
    assert cast(world,a,key='individual-modes-once').json()==response.json()


def test_unset_additional_rolls_are_normal_and_override_is_per_cast(world):
    a=create(world,modes=['advantage'])
    result=cast(world,a).json()['data']['payload']['parts']
    assert [p['roll']['mode'] for p in result]==['advantage','normal','normal']
    result=cast(world,a,{'roll_modes':['normal','disadvantage']}).json()['data']['payload']['parts']
    assert [p['roll']['mode'] for p in result]==['normal','disadvantage','normal']
    result=cast(world,a,{'mode':'disadvantage'}).json()['data']['payload']['parts']
    assert all(p['roll']['mode']=='disadvantage' for p in result)
    a.refresh_from_db();assert a.roll_modes==['advantage']
    empty=create(world)
    assert all(p['roll']['mode']=='normal' for p in cast(world,empty).json()['data']['payload']['parts'])


def test_settings_are_editable_and_native_cast_uses_them(world):
    a=create(world)
    saved=client(world[1]).patch(scoped(f'/api/abilities/{a.pk}/',world[3]),
        {'version':a.version,'roll_modes':['advantage','normal','normal']},format='json',HTTP_IDEMPOTENCY_KEY='save-individual-modes')
    assert saved.status_code==200,saved.content
    api=personal(world[1],world[3])
    response=post(api,f'/api/integrations/dmhub/sheets/{world[4].pk}/abilities/{a.pk}/use/',{'slot_level':0})
    assert response.status_code==200,response.content
    assert [p['roll']['mode'] for p in response.json()['data']['payload']['parts']]==['advantage','normal','normal']


@pytest.mark.parametrize('value',[None,{},'normal',['unknown'],[True],['normal']*21])
def test_bad_modes_are_rejected_before_slots_are_spent(world,value):
    a=create(world,'spell')
    response=cast(world,a,{'roll_modes':value})
    assert response.status_code==400,response.content
    invalid=post(client(world[1]),scoped(f'/api/characters/{world[4].pk}/abilities/',world[3]),
        {'kind':'spell','name':'Bad','roll_modes':value})
    assert invalid.status_code==400,invalid.content
