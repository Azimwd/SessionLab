"""Scene combatants and DM-approved damage from immutable server roll snapshots."""
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


def part_for(source, index):
    parts = source.payload.get('parts') or [source.payload]
    integer(index, 'Часть броска', 0, len(parts)-1)
    part = parts[index]
    damage = part.get('damage')
    if not isinstance(damage, dict) or type(damage.get('total')) is not int or damage['total'] < 0:
        raise ValidationError('В этой части результата нет применимого урона')
    if str(source.payload.get('damage_type', '')).lower() in ('healing', 'лечение'):
        raise ValidationError('Это лечение, а не урон')
    return part


def application_data(row, dm=False):
    result = {'id': row.id, 'target': row.target_id, 'target_name': row.target.name,
              'source_event': row.source_event_id, 'label': row.source_event.payload.get('label', ''),
              'requester_name': row.requester.first_name or row.requester.email,
              'part_index': row.part_index, 'status': row.status}
    if dm:
        part = part_for(row.source_event, row.part_index)
        key = damage_key(row.source_event.payload.get('damage_type'))
        result.update(effective_defense=row.target.defenses.get(key, row.target.defenses.get('all', 'normal')),
                      recognized_damage_type=key in DAMAGE_TYPES, part=part, damage_type=row.source_event.payload.get('damage_type', ''),
                      target_detail=target_data(row.target, True), resolution=row.resolution)
    return result


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
        def op(c):
            s = active_session(c)
            source = get_object_or_404(Character, campaign=c, active=True, pk=integer(request.data.get('source'), 'Лист', 1, 9223372036854775807))
            count = integer(request.data.get('count', 1), 'Количество', 1, 20)
            linked = source.kind == 'player'
            if linked and (count != 1 or SceneTarget.objects.filter(session=s, source=source, linked_sheet=True, active=True).exists()):
                raise ValidationError('Персонаж игрока уже в сцене или выбрано несколько экземпляров')
            if SceneTarget.objects.filter(session=s, active=True).count()+count > 200:
                raise ValidationError('В сцене может быть не более 200 целей')
            sh = sheet_for(source)
            protection = defenses(request.data.get('defenses', {}))
            base = str(request.data.get('name') or source.name).strip()
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
        return mutate(request, c.id, op, dm=True)


class SceneTargetDetail(APIView):
    def patch(self, request, pk):
        c = campaign_for(request, dm=True)
        def op(c):
            t = get_object_or_404(SceneTarget.objects.select_for_update(), pk=pk, session=active_session(c), source__campaign=c)
            require_version(t, request.data)
            for key in ('visible', 'targetable', 'active'):
                if key in request.data:
                    if type(request.data[key]) is not bool:
                        raise ValidationError(f'{key}: boolean')
                    setattr(t, key, request.data[key])
            if 'name' in request.data:
                name = str(request.data['name']).strip()
                if not name or len(name)>100:
                    raise ValidationError('Имя цели: от 1 до 100 символов')
                t.name = name
            if 'defenses' in request.data:
                t.defenses = defenses(request.data['defenses'])
            if 'conditions' in request.data:
                from lab.services.sheets import CONDITIONS
                values = request.data['conditions']
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
            if any(k in request.data for k in ('hp_current', 'hp_max', 'hp_temp')):
                old, maximum, temp = hp(t)
                maximum = integer(request.data.get('hp_max', maximum), 'Максимум ХП', 1)
                current = integer(request.data.get('hp_current', old), 'ХП', 0, maximum)
                temp = integer(request.data.get('hp_temp', temp), 'Временные ХП')
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
        return mutate(request, c.id, op, dm=True)


class DamageRequests(APIView):
    def get(self, request):
        c = campaign_for(request)
        dm = is_dm(c, request.user) and request.query_params.get('view') != 'player'
        s = c.sessions.filter(status='active').first()
        rows = DamageApplication.objects.filter(target__session=s).select_related('target__source__sheet', 'source_event', 'requester').order_by('-id')
        if not dm:
            rows = rows.filter(requester=request.user, target__visible=True)
        if request.query_params.get('status') == 'pending':
            rows = rows.filter(status='pending')
        return Response([application_data(r, dm) for r in rows[:100]])

    def post(self, request):
        c = campaign_for(request)
        def op(c):
            s = active_session(c)
            dm = is_dm(c, request.user)
            source = get_object_or_404(RoomEvent, pk=integer(request.data.get('source_event'), 'Результат броска', 1, 9223372036854775807), campaign=c, session=s, kind='ability')
            if not dm and source.actor_id != request.user.id:
                raise PermissionDenied('Можно применять только свой результат броска')
            index = request.data.get('part_index', 0)
            part = part_for(source, index)
            ids = request.data.get('targets')
            if not isinstance(ids, list) or not 1<=len(ids)<=50 or any(type(i) is not int for i in ids) or len(set(ids))!=len(ids):
                raise ValidationError('Выберите от 1 до 50 разных целей')
            attack = 'roll' in part
            if attack and len(ids)!=1:
                raise ValidationError('Каждому броску атаки назначается одна цель')
            if attack and DamageApplication.objects.filter(source_event=source, part_index=index, status__in=['pending','applied']).exists():
                raise ValidationError('Этот бросок атаки уже назначен цели')
            targets = SceneTarget.objects.filter(id__in=ids, session=s, active=True)
            if not dm:
                targets = targets.filter(visible=True, targetable=True)
            if targets.count()!=len(ids):
                raise ValidationError('Одна из целей недоступна')
            if DamageApplication.objects.filter(source_event=source, part_index=index, target_id__in=ids, status__in=['pending','applied']).exists():
                raise ValidationError('Для этой цели урон уже запрошен или применён')
            return [application_data(DamageApplication.objects.create(target=t, source_event=source, requester=request.user,
                    part_index=index, is_attack=attack), dm) for t in targets]
        return mutate(request, c.id, op)


class ResolveDamage(APIView):
    def post(self, request, pk):
        c = campaign_for(request, dm=True)
        def op(c):
            s = active_session(c)
            row = get_object_or_404(DamageApplication.objects.select_for_update().select_related('target__source__sheet', 'source_event', 'requester'),
                                     pk=pk, target__session=s, source_event__campaign=c)
            if row.status != 'pending':
                raise ValidationError('Запрос уже обработан')
            data = request.data
            if data.get('action') == 'reject':
                row.status='rejected'
            else:
                if data.get('action') != 'apply':
                    raise ValidationError('Выберите apply или reject')
                t = row.target
                if not t.active:
                    raise ValidationError('Цель удалена из сцены')
                part = part_for(row.source_event, row.part_index)
                amount = part['damage']['total']
                save_roll = None
                if 'save' in part:
                    outcome = data.get('save_outcome')
                    if outcome == 'roll':
                        from lab.services.sheets import computed
                        ability = part['save']['ability']
                        save_roll = d20(computed(target_sheet(t))['saves'][ability], data.get('save_mode', 'normal'))
                        outcome = 'success' if save_roll['total'] >= part['save']['dc'] else 'failure'
                    if outcome not in ('success', 'failure'):
                        raise ValidationError('Укажите результат спасброска для цели')
                    if outcome == 'success':
                        if 'success_damage' not in part['save']:
                            raise ValidationError('Для этого действия успешный урон не определён. Укажите его вручную.')
                        amount = part['save']['success_damage']
                    else:
                        amount = part['save'].get('failed_damage', amount)
                else:
                    outcome = None
                if 'roll' in part:
                    if type(data.get('hit')) is not bool:
                        raise ValidationError('Подтвердите попадание или промах')
                    if not data['hit']:
                        amount=0
                if 'base_damage' in data:
                    amount = integer(data['base_damage'], 'Урон по решению мастера')
                amount = max(0, amount)
                damage_type = damage_key(row.source_event.payload.get('damage_type'))
                defense = data.get('defense', 'auto')
                if defense == 'auto':
                    defense = t.defenses.get(damage_type, t.defenses.get('all', 'normal'))
                if not isinstance(defense, str) or defense not in DEFENSES:
                    raise ValidationError('Неизвестная защита от урона')
                final = 0 if defense=='immunity' else amount//2 if defense=='resistance' else amount*2 if defense=='vulnerability' else amount
                before, maximum, temporary = hp(t)
                absorbed = min(temporary, final)
                after = max(0, before - (final-absorbed))
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
                # Source visibility is retained. Never broadcast health or secret defenses.
                event(c, s, request.user, None, 'damage', {'label': 'Урон применён', 'target_name': t.name,
                       'source_event': row.source_event_id}, row.source_event.visibility if t.visible else 'dm')
            row.resolved_by=request.user
            row.save()
            return application_data(row, True)
        return mutate(request, c.id, op, dm=True)
