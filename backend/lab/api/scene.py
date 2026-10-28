"""Scene combatants and player-resolved damage from immutable server roll snapshots."""
from django.shortcuts import get_object_or_404
from rest_framework.exceptions import ValidationError, PermissionDenied
from rest_framework.response import Response
from rest_framework.views import APIView
from lab.models import Character, CharacterSheet, SceneTarget, DamageApplication, RoomEvent
from lab.services.sheets import active_session, sheet_for, event
from lab.services.dice import d20
from .common import campaign_for, is_dm, mutate
from .sheets import require_version

DAMAGE_TYPES = {'acid': 'Кислота', 'bludgeoning': 'Дробящий', 'cold': 'Холод', 'fire': 'Огонь',
                'force': 'Силовой', 'lightning': 'Молния', 'necrotic': 'Некротический',
                'piercing': 'Колющий', 'poison': 'Яд', 'psychic': 'Психический',
                'radiant': 'Излучение', 'slashing': 'Рубящий', 'thunder': 'Гром'}
ALIASES = {'огненный': 'fire', 'огонь': 'fire', 'холод': 'cold', 'холодом': 'cold',
           'дробящий': 'bludgeoning', 'колющий': 'piercing', 'рубящий': 'slashing',
           'кислота': 'acid', 'кислотный': 'acid', 'яд': 'poison', 'ядом': 'poison',
           'электрический': 'lightning', 'молния': 'lightning', 'некротический': 'necrotic',
           'психический': 'psychic', 'силовой': 'force', 'излучение': 'radiant', 'звуковой': 'thunder', 'гром': 'thunder'}
DEFENSES = {'normal', 'resistance', 'immunity', 'vulnerability'}


def integer(value, name, low=0, high=1000000):
    if type(value) is not int or not low <= value <= high:
        raise ValidationError(f'{name}: целое число от {low} до {high}')
    return value


def damage_key(value):
    value = str(value or "").strip().lower()
    return ALIASES.get(value, value)


def defenses(value):
    if not isinstance(value, dict) or set(value) - (set(DAMAGE_TYPES) | {'all'}):
        raise ValidationError('Некорректные типы урона')
    if any(not isinstance(v, str) or v not in DEFENSES for v in value.values()):
        raise ValidationError('Неизвестная защита от урона')
    return value


def target_sheet(target):
    try:
        return target.source.sheet
    except CharacterSheet.DoesNotExist:
        return sheet_for(target.source)


def hp(target):
    if target.linked_sheet:
        sh = target_sheet(target)
        return sh.hp_current, sh.hp_max, sh.hp_temp
    return target.hp_current, target.hp_max, target.hp_temp


def target_data(t, dm=False):
    # Deliberately no source sheet id, HP, defenses, or inferred health for players.
    result = {'id': t.id, 'name': t.name, 'targetable': t.targetable, 'version': t.version}
    if dm:
        current, maximum, temporary = hp(t)
        result.update(source=t.source_id, visible=t.visible, active=t.active, linked_sheet=t.linked_sheet,
                      hp_current=current, hp_max=maximum, hp_temp=temporary, defenses=t.defenses,
                      conditions=target_sheet(t).conditions if t.linked_sheet else t.conditions)
    return result


def effect_kind(source):
    return 'healing' if str(source.payload.get('damage_type', '')).strip().casefold() in ('healing', 'heal', 'лечение', 'исцеление') else 'damage'


def part_for(source, index):
    parts = source.payload.get('parts') or [source.payload]
    integer(index, 'Часть броска', 0, len(parts)-1)
    part = parts[index]
    damage = part.get('damage')
    if not isinstance(damage, dict) or type(damage.get('total')) is not int or damage['total'] < 0:
        raise ValidationError('В этой части результата нет применимого урона')
    return part


def application_data(row, dm=False):
    result = {'id': row.id, 'target': row.target_id, 'target_name': row.target.name,
              'source_event': row.source_event_id, 'label': row.source_event.payload.get('label', ''),
              'requester_name': row.requester.first_name or row.requester.email,
              'part_index': row.part_index, 'status': row.status, 'effect': effect_kind(row.source_event)}
    if dm:
        part = part_for(row.source_event, row.part_index)
        key = damage_key(row.source_event.payload.get('damage_type'))
        result.update(effective_defense=None if effect_kind(row.source_event)=='healing' else row.target.defenses.get(key, row.target.defenses.get('all', 'normal')),
                      recognized_damage_type=key in DAMAGE_TYPES, part=part, damage_type=row.source_event.payload.get('damage_type', ''),
                      target_detail=target_data(row.target, True), resolution=row.resolution)
    return result


def create_targets(c, user, data):
    s = active_session(c)
    source = get_object_or_404(Character, campaign=c, active=True, pk=integer(data.get('source'), 'Лист', 1, 9223372036854775807))
    count = integer(data.get('count', 1), 'Количество', 1, 20)
    linked = source.kind == 'player'
    if linked and (count != 1 or SceneTarget.objects.filter(session=s, source=source, linked_sheet=True, active=True).exists()):
        raise ValidationError('Персонаж игрока уже в сцене или выбрано несколько экземпляров')
    if SceneTarget.objects.filter(session=s, active=True).count()+count > 200:
        raise ValidationError('В сцене может быть не более 200 целей')
    sh = sheet_for(source)
    protection = defenses(data.get('defenses', {}))
    base = str(data.get('name') or source.name).strip()
    if not base or len(base)>85:
        raise ValidationError('Имя цели: от 1 до 85 символов')
    existing = SceneTarget.objects.filter(session=s, source=source).count()
    created = []
    for i in range(count):
        name = base if linked else f'{base} № {existing+i+1}'
        t = SceneTarget.objects.create(session=s, source=source, name=name, linked_sheet=linked,
            hp_max=sh.hp_max, hp_current=sh.hp_max, defenses=protection)
        created.append(target_data(t, True))
    return {'targets': created}


class SceneTargets(APIView):
    def get(self, request):
        c = campaign_for(request)
        dm = is_dm(c, request.user) and request.query_params.get('view') != 'player'
        s = c.sessions.filter(status='active').first()
        targets = SceneTarget.objects.filter(session=s, active=True).select_related('source__sheet') if s else []
        if not dm and s:
            targets = targets.filter(visible=True)
        return Response({'targets': [target_data(t, dm) for t in targets], 'damage_types': DAMAGE_TYPES})

    def post(self, request):
        c = campaign_for(request, dm=True)
        return mutate(request, c.id, lambda c: create_targets(c, request.user, request.data), dm=True)


def update_target(c, user, pk, data):
    t = get_object_or_404(SceneTarget.objects.select_for_update(), pk=pk, session=active_session(c), source__campaign=c)
    require_version(t, data)
    for key in ('visible', 'targetable', 'active'):
        if key in data:
            if type(data[key]) is not bool:
                raise ValidationError(f'{key}: boolean')
            setattr(t, key, data[key])
    if 'name' in data:
        name = str(data['name']).strip()
        if not name or len(name)>100:
            raise ValidationError('Имя цели: от 1 до 100 символов')
        t.name = name
    if 'defenses' in data:
        t.defenses = defenses(data['defenses'])
    if 'conditions' in data:
        from lab.services.sheets import CONDITIONS
        values = data['conditions']
        if not isinstance(values, list) or any(not isinstance(v, str) or v not in CONDITIONS for v in values):
            raise ValidationError('Неизвестные состояния')
        values = list(dict.fromkeys(values))
        if t.linked_sheet:
            sh = target_sheet(t)
            sh.conditions = values
            sh.version += 1
            sh.save()
        else:
            t.conditions = values
    if any(k in data for k in ('hp_current', 'hp_max', 'hp_temp')):
        old, maximum, temp = hp(t)
        maximum = integer(data.get('hp_max', maximum), 'Максимум ХП', 1)
        current = integer(data.get('hp_current', old), 'ХП', 0, maximum)
        temp = integer(data.get('hp_temp', temp), 'Временные ХП')
        if t.linked_sheet:
            sh = target_sheet(t)
            sh.hp_max, sh.hp_current, sh.hp_temp = maximum, current, temp
            sh.version += 1
            sh.save()
        else:
            t.hp_max, t.hp_current, t.hp_temp = maximum, current, temp
    t.version += 1
    t.save()
    return target_data(t, True)


class SceneTargetDetail(APIView):
    def patch(self, request, pk):
        c = campaign_for(request, dm=True)
        return mutate(request, c.id, lambda c: update_target(c, request.user, pk, request.data), dm=True)


def apply_healing(row, campaign, user, amount):
    """Healing ignores damage defenses and temporary HP; saved roll is authoritative."""
    t = row.target
    before, maximum, temporary = hp(t)
    after = min(maximum, before + amount)
    if t.linked_sheet:
        sh = target_sheet(t)
        sh.hp_current = after
        if before == 0 and after > 0:
            sh.death_successes = sh.death_failures = 0
        sh.version += 1
        sh.save()
    else:
        t.hp_current = after
    t.version += 1
    t.save()
    row.status = 'applied'
    row.resolution = {'effect': 'healing', 'base_healing': amount, 'final_healing': after-before,
                      'hp_before': before, 'hp_after': after, 'hp_temp': temporary}
    row.resolved_by = user
    row.save()
    event(campaign, active_session(campaign), user, None, 'healing', {'label': 'Лечение применено',
          'target_name': t.name, 'source_event': row.source_event_id},
          row.source_event.visibility if t.visible else 'dm')


def apply_damage(row, campaign, user, data, privileged=False):
    """One atomic application. Callers hold the campaign lock via mutate()."""
    if row.status != 'pending':
        raise ValidationError('Этот урон уже применён или отменён')
    t = row.target
    if not t.active:
        raise ValidationError('Цель удалена из сцены')
    if not is_dm(campaign, user) and (not t.visible or not t.targetable):
        raise PermissionDenied('Цель недоступна')
    if not isinstance(data, dict):
        raise ValidationError('Исход цели должен быть объектом')
    if not privileged and set(data) - {'save_outcome', 'hit'}:
        raise ValidationError('Игрок выбирает только попадание и исход спасброска. Защита задаётся мастером.')
    part = part_for(row.source_event, row.part_index)
    amount = part['damage']['total']
    if effect_kind(row.source_event) == 'healing':
        if data:
            raise ValidationError('Для лечения не нужны попадание, спасбросок или изменение защиты')
        apply_healing(row, campaign, user, amount)
        return
    save_roll = None
    outcome = None
    if 'save' in part:
        outcome = data.get('save_outcome')
        if outcome == 'roll' and privileged:
            from lab.services.sheets import computed
            save_roll = d20(computed(target_sheet(t))['saves'][part['save']['ability']], data.get('save_mode', 'normal'))
            outcome = 'success' if save_roll['total'] >= part['save']['dc'] else 'failure'
        if outcome not in ('success', 'failure'):
            raise ValidationError(f'{t.name}: укажите, прошла ли цель спасбросок')
        if outcome == 'success':
            if 'success_damage' not in part['save'] and not (privileged and 'base_damage' in data):
                raise ValidationError('Урон при успешном спасброске не определён. Мастер должен уточнить действие.')
            amount = part['save'].get('success_damage', 0)
        else:
            amount = part['save'].get('failed_damage', amount)
    if 'roll' in part:
        if type(data.get('hit')) is not bool:
            raise ValidationError(f'{t.name}: укажите попадание или промах')
        if not data['hit']:
            amount = 0
    if privileged and 'base_damage' in data:
        amount = integer(data['base_damage'], 'Урон по решению мастера')
    amount = max(0, amount)
    damage_type = damage_key(row.source_event.payload.get('damage_type'))
    defense = data.get('defense', 'auto') if privileged else 'auto'
    if defense == 'auto':
        defense = t.defenses.get(damage_type, t.defenses.get('all', 'normal'))
    if not isinstance(defense, str) or defense not in DEFENSES:
        raise ValidationError('Неизвестная защита от урона')
    final = 0 if defense == 'immunity' else amount//2 if defense == 'resistance' else amount*2 if defense == 'vulnerability' else amount
    before, _, temporary = hp(t)
    absorbed = min(temporary, final)
    after = max(0, before-(final-absorbed))
    if t.linked_sheet:
        sh = target_sheet(t)
        sh.hp_current, sh.hp_temp = after, temporary-absorbed
        sh.version += 1
        sh.save()
    else:
        t.hp_current, t.hp_temp = after, temporary-absorbed
    t.version += 1
    t.save()
    row.status = 'applied'
    row.resolution = {'base_damage': amount, 'defense': defense, 'final_damage': final,
                      'hp_before': before, 'hp_after': after, 'temp_absorbed': absorbed,
                      'save_outcome': outcome, 'save_roll': save_roll, 'hit': data.get('hit')}
    row.resolved_by = user
    row.save()
    event(campaign, active_session(campaign), user, None, 'damage', {'label': 'Урон применён',
          'target_name': t.name, 'source_event': row.source_event_id},
          row.source_event.visibility if t.visible else 'dm')


def submit_damage(c, user, data):
    s = active_session(c)
    dm = is_dm(c, user)
    if set(data) - {'source_event', 'part_index', 'targets', 'outcomes'}:
        raise ValidationError('Урон и защита определяются сервером, не клиентом')
    source = get_object_or_404(RoomEvent, pk=integer(data.get('source_event'), 'Результат броска', 1, 9223372036854775807), campaign=c, session=s, kind='ability')
    if not dm and source.actor_id != user.id:
        raise PermissionDenied('Можно применять только свой результат броска')
    index = data.get('part_index', 0)
    part = part_for(source, index)
    ids = data.get('targets')
    if not isinstance(ids, list) or not 1 <= len(ids) <= 50 or any(type(i) is not int for i in ids) or len(set(ids)) != len(ids):
        raise ValidationError('Выберите от 1 до 50 разных целей')
    outcomes = data.get('outcomes', {})
    if not isinstance(outcomes, dict) or set(outcomes) - {str(i) for i in ids}:
        raise ValidationError('Исходы должны соответствовать выбранным целям')
    attack = effect_kind(source) == 'damage' and 'roll' in part
    if attack and len(ids) != 1:
        raise ValidationError('Каждому броску атаки назначается одна цель')
    previous = DamageApplication.objects.filter(source_event=source, part_index=index)
    if previous.filter(status='applied', **({} if attack else {'target_id__in': ids})).exists():
        raise ValidationError('Этот результат уже применён')
    targets = SceneTarget.objects.filter(id__in=ids, session=s, active=True).select_related('source__sheet')
    if not dm:
        targets = targets.filter(visible=True, targetable=True)
    if targets.count() != len(ids):
        raise ValidationError('Одна из целей недоступна')
    # Old pending requests no longer require a master review. The author can
    # apply them here; an old attack reservation can also be reassigned.
    if attack:
        previous.filter(status='pending').exclude(target_id__in=ids).update(status='rejected', resolved_by=user)
    result = []
    for t in targets.order_by('id'):
        row = previous.filter(target=t, status='pending').first()
        if row is None:
            row = DamageApplication.objects.create(target=t, source_event=source, requester=user,
                                                   part_index=index, is_attack=attack)
        else:
            row.requester = user
            row.target = t
        apply_damage(row, c, user, outcomes.get(str(t.id), {}))
        result.append(application_data(row, dm))
    return result


class DamageRequests(APIView):
    def get(self, request):
        c = campaign_for(request)
        dm = is_dm(c, request.user) and request.query_params.get('view') != 'player'
        s = c.sessions.filter(status='active').first()
        rows = DamageApplication.objects.filter(target__session=s).select_related('target__source__sheet', 'source_event', 'requester').order_by('-id')
        if not dm:
            rows = rows.filter(requester=request.user, target__visible=True)
        status = request.query_params.get('status')
        if status in ('pending', 'applied', 'rejected'):
            rows = rows.filter(status=status)
        return Response([application_data(r, dm) for r in rows[:100]])

    def post(self, request):
        c = campaign_for(request)
        return mutate(request, c.id, lambda c: submit_damage(c, request.user, request.data))


class ResolveDamage(APIView):
    """Compatibility for already-created pending requests; not a review queue."""
    def post(self, request, pk):
        c = campaign_for(request)
        def op(c):
            s = active_session(c)
            # PostgreSQL must lock ONLY the application, not the nullable sheet
            # joined for presentation. Locking the outer join raised HTTP 500.
            row = get_object_or_404(DamageApplication.objects.select_for_update(of=('self',)).select_related('target__source__sheet', 'source_event', 'requester'),
                                     pk=pk, target__session=s, source_event__campaign=c)
            dm = is_dm(c, request.user)
            if not dm and (row.source_event.actor_id != request.user.id or row.requester_id != request.user.id):
                raise PermissionDenied('Можно применить только свой результат')
            if row.status != 'pending':
                raise ValidationError('Этот результат уже обработан')
            action = request.data.get('action')
            if action == 'reject':
                if not dm:
                    raise PermissionDenied('Отменить старый запрос может только мастер')
                row.status = 'rejected'
                row.resolved_by = request.user
                row.save()
            elif action == 'apply':
                payload = {k: v for k, v in request.data.items() if k != 'action'}
                apply_damage(row, c, request.user, payload, privileged=dm)
            else:
                raise ValidationError('Выберите apply или reject')
            return application_data(row, dm)
        return mutate(request, c.id, op)
