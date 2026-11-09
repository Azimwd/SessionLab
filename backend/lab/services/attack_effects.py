"""Declarative, snapshotted attack riders. No executable user rules."""
import re
from django.shortcuts import get_object_or_404
from rest_framework.exceptions import ValidationError
from lab.models import RoomEvent, DamageApplication, SceneTarget, InitiativeTracker
from .dice import parse_formula, roll_formula

TYPES = {'base','acid','bludgeoning','cold','fire','force','lightning','necrotic','piercing','poison','psychic','radiant','slashing','thunder'}
FIELDS = {'id','name','dice','damage_type','sign','frequency','below_half_type','critical_upgrade','scaling','enabled','target_required','advantage_first','group','min_level'}


def formula(value):
    if not isinstance(value,str): raise ValidationError('Кубики эффекта: строка')
    terms=parse_formula(value)
    if any(sign<0 for sign,_,_ in terms) or sum(count for _,count,sides in terms if sides)>5:
        raise ValidationError('До 5 кубиков в эффекте; уменьшение задаётся отдельным знаком')
    return value


def validate_effects(value):
    if not isinstance(value,list) or len(value)>6: raise ValidationError('Можно настроить до 6 дополнительных эффектов')
    ids=set()
    for e in value:
        if not isinstance(e,dict) or set(e)-FIELDS: raise ValidationError('Некорректные поля эффекта')
        if not isinstance(e.get('id'),str) or not re.fullmatch(r'[a-zA-Z0-9_-]{1,64}',e['id']) or e['id'] in ids: raise ValidationError('Нужен уникальный ID эффекта')
        ids.add(e['id'])
        if not isinstance(e.get('name'),str) or not 1<=len(e['name'].strip())<=80: raise ValidationError('Имя эффекта: 1–80 символов')
        formula(e.get('dice'))
        if not isinstance(e.get('damage_type','base'),str) or not isinstance(e.get('below_half_type',''),str) or e.get('damage_type','base') not in TYPES or e.get('below_half_type','') not in TYPES|{''}: raise ValidationError('Неизвестный тип урона эффекта')
        if type(e.get('sign',1)) is not int or e.get('sign',1) not in (-1,1): raise ValidationError('Знак эффекта: +1 или -1')
        if not isinstance(e.get('frequency','all'),str) or e.get('frequency','all') not in ('all','action','turn'): raise ValidationError('Ограничение: all, action или turn')
        for key in ('critical_upgrade','enabled','target_required','advantage_first'):
            if key in e and type(e[key]) is not bool: raise ValidationError(f'{key}: boolean')
        if type(e.get('min_level',1)) is not int or not 1<=e.get('min_level',1)<=30: raise ValidationError('Уровень эффекта: 1–30')
        if not isinstance(e.get('group',''),str) or len(e.get('group',''))>40: raise ValidationError('Группа эффекта: до 40 символов')
        levels=e.get('scaling',[])
        if not isinstance(levels,list) or len(levels)>8: raise ValidationError('До 8 ступеней роста эффекта')
        seen=set()
        for step in levels:
            if not isinstance(step,dict) or set(step)!={'level','dice'} or type(step['level']) is not int or not 1<=step['level']<=30 or step['level'] in seen: raise ValidationError('Укажите разные уровни роста от 1 до 30')
            formula(step['dice']);seen.add(step['level'])
    return value


def turn_key(session,sheet):
    tracker=InitiativeTracker.objects.filter(session=session,running=True).first()
    if tracker and tracker.current_id:
        return f'initiative:{tracker.pk}:{tracker.round_number}:{tracker.current_id}'
    return f'manual:{sheet.combat_turn}'


def next_turn(campaign,sheet):
    session=campaign.sessions.filter(status='active').first()
    if session and InitiativeTracker.objects.filter(session=session,running=True).exists():
        raise ValidationError('В бою ход переключается через инициативу')
    sheet.combat_turn+=1


def select_effects(ability,char,session,sheet,data):
    definitions=validate_effects(ability.attack_effects)
    ids=data.get('effects', [e['id'] for e in definitions if e.get('enabled',True)] if ability.resolution=='attack' else [])
    if not isinstance(ids,list) or any(not isinstance(k,str) for k in ids) or len(set(ids))!=len(ids) or set(ids)-{e['id'] for e in definitions}: raise ValidationError('Выберите настроенные эффекты атаки')
    effects=[e for e in definitions if e['id'] in ids]
    if effects and ability.resolution!='attack': raise ValidationError('Дополнительные эффекты доступны для бросков атаки')
    if effects and str(ability.damage_type).strip().casefold() in ('heal','healing','лечение','исцеление'): raise ValidationError('Эффекты атаки не применяются к лечению')
    groups=set()
    for e in effects:
        if char.level<e.get('min_level',1): raise ValidationError(f"{e['name']}: требуется уровень {e['min_level']}")
        group=e.get('group','')
        if group and group in groups: raise ValidationError('Выберите только один вариант оценки цели')
        if group: groups.add(group)
    if not effects: return [],None,'',[]
    target=None
    if effects and any(e.get('target_required') for e in effects):
        target_id=data.get('effect_target')
        if type(target_id) is not int: raise ValidationError('Выберите цель метки до броска атаки')
        target=get_object_or_404(SceneTarget,pk=target_id,session=session,active=True,visible=True,targetable=True)
    turn=turn_key(session,sheet)
    previous=RoomEvent.objects.filter(session=session,character=char,kind='ability',payload__effect_turn=turn).values_list('payload',flat=True)
    claimed=set()
    for payload in previous: claimed.update(payload.get('advantage_effects',[]))
    first=[e['id'] for e in effects if e.get('advantage_first') and f"{e['id']}:{target.pk if target else ''}" not in claimed]
    return effects, target, turn, first


def upgraded(formula_text):
    ladder={4:6,6:8,8:10,10:12,12:20,20:100,100:100}
    return '+'.join(f'{count}d{ladder[sides]}' for _,count,sides in parse_formula(formula_text) if sides)


def roll_effects(effects,level,critical):
    result=[]
    for e in effects:
        dice=e['dice']
        for step in sorted(e.get('scaling',[]),key=lambda v:v['level']):
            if level>=step['level']: dice=step['dice']
        positive=e.get('sign',1)>0
        roll=roll_formula(dice,critical=critical and positive)
        bonus=None
        if critical and positive and e.get('critical_upgrade') and upgraded(dice):
            bonus=roll_formula(upgraded(dice));roll['total']+=bonus['total']
        result.append({**e,'dice':dice,'roll':roll,'critical_bonus':bonus})
    return result


def component_damage(row,part,base_amount,damage_type,base_defense,health,maximum):
    source=row.source_event
    turn=source.payload.get('effect_turn','')
    rows=DamageApplication.objects.filter(source_event__session=source.session,source_event__character_id=source.character_id,status='applied').filter(source_event__payload__effect_turn=turn).values('source_event_id','resolution')
    turn_used=set();action_used=set()
    for previous in rows:
        keys=previous['resolution'].get('effect_keys',[]);turn_used.update(keys)
        if previous['source_event_id']==source.pk: action_used.update(keys)
    additions=[];reductions=0;keys=[];details=[]
    for e in part.get('effects',[]):
        key=e['id']+(f":{row.target_id}" if e.get('target_required') else '')
        frequency=e.get('frequency','all')
        if (frequency=='turn' and key in turn_used) or (frequency=='action' and key in action_used):
            continue
        value=max(0,e['roll']['total'])
        keys.append(key)
        if e.get('sign',1)<0:
            reductions+=value;details.append({'name':e['name'],'reduction':value});continue
        dtype=e.get('damage_type','base')
        if dtype=='base': dtype=damage_type
        if e.get('below_half_type') and health*2<maximum:
            dtype=e['below_half_type']
            if dtype=='base':dtype=damage_type
        additions.append((dtype,value,e['name']))
    base_amount=max(0,base_amount-reductions)
    components=[(damage_type,base_amount,'Основной урон')]+additions
    final=0
    for index,(dtype,value,name) in enumerate(components):
        defense=base_defense if index==0 else row.target.defenses.get(dtype,row.target.defenses.get('all','normal'))
        actual=0 if defense=='immunity' else value//2 if defense=='resistance' else value*2 if defense=='vulnerability' else value
        final+=actual
        details.append({'name':name,'damage_type':dtype,'base_damage':value,'defense':defense,'final_damage':actual})
    return final,keys,details
