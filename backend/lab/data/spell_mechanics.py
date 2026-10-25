"""Audited numerical presets for SRD 5.1 (2014).

These are rolls for one application of the spell, not automatic target selection,
HP changes, concentration checks, or repeated triggers. The Russian source text
remains the authority for conditions and secondary effects.
"""

import re

ABILITIES = {
    'Strength': 'str', 'Dexterity': 'dex', 'Constitution': 'con',
    'Intelligence': 'int', 'Wisdom': 'wis', 'Charisma': 'cha',
}
SAVE_PATTERN = re.compile(r'\b(Strength|Dexterity|Constitution|Intelligence|Wisdom|Charisma) saving throws?\b')


def possible_saves(source):
    """Discover named saves to display as references, never resolve a target's save."""
    return list(dict.fromkeys(ABILITIES[match] for match in SAVE_PATTERN.findall(source)))


def preset(resolution='automatic', dice='', upcast_dice='', *, save='', half=False,
           damage_type='', modifier=False, count=1, count_upcast=0,
           cantrip=False, recurring=False, deferred=False, upcast_every=1,
           trigger_resolution='', note=''):
    return dict(resolution=resolution, dice=dice, upcast_dice=upcast_dice,
                save_ability=save, save_half=half, damage_type=damage_type,
                add_modifier=modifier, roll_count=count,
                upcast_count=count_upcast, cantrip_scaling=cantrip,
                recurring=recurring, deferred=deferred, upcast_every=upcast_every, mechanics_note=note,
                trigger_resolution=trigger_resolution,
                verified=True)


# Only formulas whose base and slot scaling were checked against SRD 5.1.
# Choice-dependent modes and repeated triggers remain visible in the description.
EXTRA = {
    'Acid Splash': preset('save', '1d6', '1d6', save='dex', damage_type='кислота', cantrip=True),
    'Chill Touch': preset('attack', '1d8', '1d8', damage_type='некротический', cantrip=True),
    'Shocking Grasp': preset('attack', '1d8', '1d8', damage_type='электричество', cantrip=True),
    'Vicious Mockery': preset('save', '1d4', '1d4', save='wis', damage_type='психический', cantrip=True),
    'Eldritch Blast': preset('attack', '1d10', count=1, count_upcast=1, damage_type='силовое поле', cantrip=True,
                            note='Каждый луч требует отдельной атаки. Распределите попадания по целям.'),
    'Guiding Bolt': preset('attack', '4d6', '1d6', damage_type='излучение'),
    'Inflict Wounds': preset('attack', '3d10', '1d10', damage_type='некротический'),
    'Hellish Rebuke': preset('save', '2d10', '1d10', save='dex', half=True, damage_type='огонь'),
    'Shatter': preset('save', '3d8', '1d8', save='con', half=True, damage_type='звук'),
    'Sleep': preset(dice='5d8', upcast_dice='2d8', damage_type='пул хитов для усыпления',
                    note='Результат — доступный пул хитов, не урон. Учитывайте порядок целей и иммунитеты.'),
    'Color Spray': preset(dice='6d10', upcast_dice='2d10', damage_type='пул хитов для ослепления',
                          note='Результат — доступный пул хитов, не урон. Учитывайте порядок целей.'),
    'False Life': preset(dice='1d4+4', upcast_dice='5', damage_type='временные хиты'),
    'Prayer of Healing': preset(dice='2d8', upcast_dice='1d8', modifier=True, damage_type='лечение',
                                note='Восстановление каждому подходящему существу (до шести).'),
    'Mass Healing Word': preset(dice='1d4', upcast_dice='1d4', modifier=True, damage_type='лечение',
                                note='Восстановление каждому подходящему существу (до шести).'),
    'Mass Cure Wounds': preset(dice='3d8', upcast_dice='1d8', modifier=True, damage_type='лечение',
                               note='Восстановление каждому подходящему существу (до шести).'),
    'Heal': preset(dice='70', upcast_dice='10', damage_type='лечение'),
    'Regenerate': preset(dice='4d8+15', damage_type='лечение',
                         note='Кроме начального лечения: 1 хит в начале каждого хода цели.'),
    'Heat Metal': preset(dice='2d8', upcast_dice='1d8', damage_type='огонь', recurring=True,
                         note='Урон при контакте с нагретым предметом. Удерживающий предмет может совершить спасбросок Телосложения.'),
    'Moonbeam': preset('save', '2d10', '1d10', save='con', half=True, damage_type='излучение', recurring=True, deferred=True,
                       note='Бросайте урон при входе цели в область или в начале её хода, не при создании луча.'),
    'Call Lightning': preset('save', '3d10', '1d10', save='dex', half=True, damage_type='электричество', recurring=True,
                             note='На открытом воздухе в грозу базовый урон увеличивается на 1d10.'),
    'Spirit Guardians': preset('save', '3d8', '1d8', save='wis', half=True, damage_type='излучение/некротический', recurring=True,
                               note='Бросайте урон при входе цели в область или в начале её хода; тип зависит от заклинателя.'),
    'Vampiric Touch': preset('attack', '3d6', '1d6', damage_type='некротический', recurring=True,
                             note='При попадании заклинатель восстанавливает половину фактически нанесённого некротического урона.'),
    'Blight': preset('save', '8d8', '1d8', save='con', half=True, damage_type='некротический',
                     note='На растения действуют особые условия, описанные в тексте.'),
    'Ice Storm': preset('save', '2d8+4d6', '1d8', save='dex', half=True, damage_type='дробящий + холод',
                        note='Первые 2d8 — дробящий, следующие 4d6 — холод; усиление добавляет дробящий.'),
    'Cloudkill': preset('save', '5d8', '1d8', save='con', half=True, damage_type='яд', recurring=True, deferred=True,
                        note='Бросайте урон при входе цели в область или в начале её хода.'),
    'Circle of Death': preset('save', '8d6', '2d6', save='con', half=True, damage_type='некротический'),
    'Finger of Death': preset('save', '7d8+30', save='con', half=True, damage_type='некротический'),
    'Fire Storm': preset('save', '7d10', save='dex', half=True, damage_type='огонь'),
    'Sunburst': preset('save', '12d6', save='con', half=True, damage_type='излучение'),
    'Meteor Swarm': preset('save', '20d6+20d6', save='dex', half=True, damage_type='огонь + дробящий',
                           note='Первая группа 20d6 — огонь, вторая — дробящий; перекрывающиеся области не складываются.'),
    'Freezing Sphere': preset('save', '10d6', '1d6', save='con', half=True, damage_type='холод',
                              note='При отложенном броске сферы урон возникает только при взрыве.'),
    'Flame Strike': preset('save', '4d6+4d6', '1d6', save='dex', half=True, damage_type='огонь + излучение',
                           note='Выберите, к какому из двух типов отнести добавочные кубы усиления.'),
    'Insect Plague': preset('save', '4d10', '1d10', save='con', half=True, damage_type='колющий', recurring=True),
    'Sunbeam': preset('save', '6d8', save='con', half=True, damage_type='излучение', recurring=True),
    'Spiritual Weapon': preset('attack', '1d8', '1d8', modifier=True, damage_type='силовое поле', recurring=True,
                               upcast_every=2, note='Усиление на 1d8 за каждые ДВА уровня ячейки выше второго.'),
    'Cone of Cold': preset('save', '8d8', '1d8', save='con', half=True, damage_type='холод'),
    'Chain Lightning': preset('save', '10d8', save='dex', half=True, damage_type='электричество',
                              note='Ячейка выше шестого уровня добавляет одну цель, а не кубы урона.'),
    'Disintegrate': preset('save', '10d6+40', '3d6', save='dex', damage_type='силовое поле',
                           note='При успешном спасброске урон равен нулю. Предметы обрабатываются отдельно по описанию.'),
    'Feeblemind': preset('save', '4d6', save='int', damage_type='психический',
                         note='Урон наносится до спасброска; эффект снижения характеристик только при его провале.'),
    'Harm': preset('save', '14d6', save='con', half=True, damage_type='некротический',
                   note='Урон не опускает хиты ниже 1; уменьшение максимума хитов только при провале.'),
    'Blade Barrier': preset('save', '6d10', save='dex', half=True, damage_type='рубящий', recurring=True, deferred=True,
                            note='Бросайте урон при входе в стену или в начале хода внутри неё.'),
    'Wind Wall': preset('save', '3d8', save='str', half=True, damage_type='дробящий'),
    'Flaming Sphere': preset('save', '2d6', '1d6', save='dex', half=True, damage_type='огонь', recurring=True, deferred=True,
                             note='При создании сферы урона нет: бросайте при таране или в конце хода рядом.'),
    'Spike Growth': preset(dice='2d4', damage_type='колющий', recurring=True, deferred=True,
                            note='Урон за каждые 5 футов движения через область, без спасброска.'),
    'Wall of Fire': preset('save', '5d8', '1d8', save='dex', half=True, damage_type='огонь', recurring=True,
                           trigger_resolution='automatic',
                           note='Спасбросок при появлении стены; последующий урон с опасной стороны без спасброска.'),
    'Wall of Thorns': preset('save', '7d8', '1d8', save='dex', half=True, damage_type='колющий/рубящий', recurring=True,
                             note='Бросок при появлении стены — колющий; последующие срабатывания — рубящий.'),
    'Incendiary Cloud': preset('save', '10d8', save='dex', half=True, damage_type='огонь', recurring=True),
    'Weird': preset('save', '4d10', save='wis', damage_type='психический', recurring=True, deferred=True,
                     note='При создании — только спасбросок от испуга. Урон возможен в конце хода испуганной цели.'),
    'Time Stop': preset(dice='1d4+1', damage_type='дополнительные ходы',
                         note='Результат — число последовательных ходов, не урон.'),
    'Arcane Sword': preset('attack', '3d10', damage_type='силовое поле', recurring=True,
                           note='Атака при появлении и повторная бонусным действием на следующих ходах.'),
    'Black Tentacles': preset('save', '3d6', save='dex', damage_type='дробящий', recurring=True, deferred=True,
                              note='При создании стены урона нет; при входе/начале хода цель может быть опутана.'),
    'Faithful Hound': preset('attack', '4d8', damage_type='колющий', recurring=True, deferred=True,
                            note='При создании урона нет: укус возможен в начале ваших следующих ходов.'),
    'Fire Shield': preset(dice='2d8', damage_type='огонь/холод', recurring=True, deferred=True,
                          note='Урон наносится атакующему в 5 футах, когда он попадает по вам в ближнем бою.'),
    'Phantasmal Killer': preset('save', '4d10', '1d10', save='wis', damage_type='психический', recurring=True, deferred=True,
                                note='При создании — спасбросок от испуга; урон только в конце хода цели при новом провале.'),
}
