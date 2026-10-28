from importlib import import_module
from unittest.mock import patch
from django.apps import apps
from lab.models import CharacterAbility
from lab.services.sheets import sheet_for, use_ability
from .test_api import world


def test_main_spell_stat_controls_attack_save_and_healing_without_overriding_custom(world):
    _,p,_,c,ch,_=world
    sh=sheet_for(ch);sh.abilities={**sh.abilities,'int':10,'dex':18,'cha':16};sh.spell_ability='dex';sh.save()
    attack=CharacterAbility.objects.create(character=ch,kind='spell',name='Ray',level=0,ability='int',use_spell_ability=True,resolution='attack',dice='1d4',add_modifier=True)
    save=CharacterAbility.objects.create(character=ch,kind='spell',name='Save',level=0,ability='int',use_spell_ability=True,resolution='save',dice='1d4')
    custom=CharacterAbility.objects.create(character=ch,kind='spell',name='Custom',level=0,ability='cha',use_spell_ability=False,resolution='attack')
    with patch('lab.services.dice.secrets.randbelow',return_value=2):
        a=use_ability(c,p,attack.pk,{'slot_level':0}).payload
        b=use_ability(c,p,save.pk,{'slot_level':0}).payload
        d=use_ability(c,p,custom.pk,{'slot_level':0}).payload
    assert a['casting_ability']=='dex' and a['spell_attack_bonus']==6 and a['damage']['total']==7
    assert b['save']['dc']==14
    assert d['casting_ability']=='cha' and d['spell_attack_bonus']==5
    sh.refresh_from_db();sh.spell_ability='cha';sh.save()
    assert use_ability(c,p,attack.pk,{'slot_level':0}).payload['casting_ability']=='cha'


def test_migration_links_matching_legacy_spells_but_preserves_custom_stats(world):
    *_,ch,s=world
    sh=sheet_for(ch);sh.spell_ability='int';sh.save()
    default=CharacterAbility.objects.create(character=ch,kind='spell',name='Default',ability='int')
    custom=CharacterAbility.objects.create(character=ch,kind='spell',name='Custom',ability='cha')
    attack=CharacterAbility.objects.create(character=ch,kind='attack',name='Weapon',ability='int')
    import_module('lab.migrations.0017_characterability_use_spell_ability').inherit_matching_stat(apps,None)
    default.refresh_from_db();custom.refresh_from_db();attack.refresh_from_db()
    assert default.use_spell_ability and not custom.use_spell_ability and not attack.use_spell_ability
