from unittest.mock import patch
import pytest
from django.test import Client
from lab.models import *
from lab.services.dice import parse_formula, roll_formula, d20
from lab.services.sheets import sheet_for
from lab.api.room import revision
from .test_api import world, client, post, scoped


def patch_api(api, path, data, key="sheet-patch-test"):
    return api.patch(path, data, format="json", HTTP_IDEMPOTENCY_KEY=key)


@pytest.mark.parametrize(
    "formula",
    [
        '__import__("os")',
        "2d6*100",
        "0d20",
        "51d6",
        "1d7",
        "2d6d4",
        "1d6+",
        "10001",
        "1d6 1d6",
        "",
    ],
)
def test_bad_formula(formula):
    from rest_framework.exceptions import ValidationError

    with pytest.raises(ValidationError):
        parse_formula(formula)


def test_dice_math():
    with patch("lab.services.dice.secrets.randbelow", return_value=2):
        assert roll_formula("2d6+3-1d4")["total"] == 6
        r = roll_formula("2d6+3", critical=True)
        assert r["total"] == 15 and len(r["terms"][0]["values"]) == 4
    with patch("lab.services.dice.secrets.randbelow", side_effect=[1, 18]):
        assert d20(4, "advantage")["total"] == 23
    with patch("lab.services.dice.secrets.randbelow", side_effect=[1, 18]):
        assert d20(4, "disadvantage")["total"] == 6


def test_folders_permissions_and_archived_character(world):
    dm, player, outsider, campaign, char, session = world
    url = scoped('/api/character-folders/', campaign)
    folder = post(client(player), url, {'name': 'Важное'}).json()['data']
    assert folder['owner'] == player.id
    assert client(outsider).get(url).status_code == 403
    assert post(client(dm), scoped('/api/characters/', campaign), {'name': 'NPC', 'kind': 'npc', 'folder': folder['id']}).status_code == 200
    updated = patch_api(client(player), scoped(f'/api/characters/{char.id}/', campaign), {'folder': folder['id']}, 'move-folder-1')
    assert updated.status_code == 200 and updated.json()['data']['folder'] == folder['id']
    deleted = client(player).delete(scoped(f'/api/characters/{char.id}/', campaign), format='json', HTTP_IDEMPOTENCY_KEY='archive-char-1')
    assert deleted.status_code == 200
    char.refresh_from_db()
    assert not char.active and client(player).get(scoped(f'/api/characters/{char.id}/', campaign)).status_code == 404


def test_master_room_folders_and_private_table_visibility(world):
    dm, player, outsider, campaign, char, session = world
    Membership.objects.create(campaign=campaign, user=outsider)
    npcs = CharacterFolder.objects.create(campaign=campaign, owner=dm, name='NPC')
    enemies = CharacterFolder.objects.create(campaign=campaign, owner=dm, name='Противники')
    goblin = Character.objects.create(campaign=campaign, owner=dm, name='Гоблин', kind='npc', folder=enemies)
    Character.objects.create(campaign=campaign, owner=dm, name='Торговец', kind='npc', folder=npcs)
    sheet_for(goblin).save()
    url = scoped('/api/room/', campaign)
    table = scoped('/api/room/table-visibility/', campaign)
    master = client(dm).get(url).json()['data']
    assert {row['folder'] for row in master['npcs']} == {npcs.id, enemies.id}
    assert master['npcs'][0]['abilities'] and master['party'][0]['id'] == char.id
    public = client(outsider).get(url).json()['data']
    assert public['npcs'] == [] and len(public['party']) == 1
    assert 'abilities' not in public['party'][0] and 'folder' not in public['party'][0]
    assert post(client(player), table, {'scope':'table','visible':False}).status_code == 403
    assert post(client(outsider), table, {'scope':'character','character':char.id,'visible':False}).status_code == 403

    key = 'hide-entire-table-1'
    response = post(client(dm), table, {'scope':'table','visible':False}, key)
    assert response.status_code == 200
    assert post(client(dm), table, {'scope':'table','visible':False}, key).json() == response.json()
    assert client(outsider).get(url).json()['data']['party'] == []
    assert client(dm).get(url).json()['data']['party'][0]['id'] == char.id
    assert client(dm).get(url+'&view=player').json()['data']['party'] == []
    assert post(client(dm), table, {'scope':'table','visible':True}).status_code == 200

    assert post(client(dm), table, {'scope':'character','character':char.id,'visible':False}).status_code == 200
    assert client(outsider).get(url).json()['data']['party'] == []
    owned = client(player).get(url).json()['data']
    assert owned['party'] == [] and owned['own_characters'] == [{'id':char.id,'name':char.name,'owner':player.id}]
    assert client(dm).get(url).json()['data']['party'][0]['table_visible'] is False
    assert post(client(dm), table, {'scope':'character','character':goblin.id,'visible':'false'}).status_code == 400
    assert post(client(dm), table, {'scope':'character','character':char.id,'visible':True}).status_code == 200
    assert len(client(outsider).get(url).json()['data']['party']) == 1


def test_master_starts_bulk_initiative_and_broadcasts_rolls(world):
    dm, player, outsider, campaign, char, session = world
    npc = Character.objects.create(campaign=campaign, owner=dm, name='Гоблин', kind='npc')
    url = scoped('/api/room/initiative/', campaign)
    payload = {'action':'start', 'version':0, 'participants':[{'character':char.id}, {'character':npc.id,'count':3}, {'name':'Скелет','bonus':2,'count':2}]}
    with patch('lab.services.dice.secrets.randbelow', return_value=9):
        response = post(client(dm), url, payload, 'bulk-initiative-key')
    assert response.status_code == 200, response.content
    data = response.json()['data']
    assert len(data['entries']) == 6
    assert [e['initiative'] for e in data['entries']] == sorted((e['initiative'] for e in data['entries']), reverse=True)
    assert set(e['name'] for e in data['entries'] if e['name'].startswith('Гоблин')) == {'Гоблин 1','Гоблин 2','Гоблин 3'}
    assert RoomEvent.objects.filter(campaign=campaign, kind='roll').count() == 6
    assert client(player).get(scoped('/api/room/events/', campaign)).json()['data']['count'] == 6
    assert post(client(dm), url, payload, 'bulk-initiative-key').json()['data'] == data
    assert post(client(dm), url, payload, 'another-bulk-key').status_code == 409
    renamed = post(client(dm), url, {'action':'edit','version':data['version'],'entry':data['entries'][0]['id'],'name':'Начальник'})
    assert renamed.status_code == 200 and any(e['name']=='Начальник' for e in renamed.json()['data']['entries'])
    stopped = post(client(dm), url, {'action':'stop','version':renamed.json()['data']['version']}).json()['data']
    first = stopped['entries'][0]
    edited = post(client(dm), url, {'action':'edit','version':stopped['version'],'entry':first['id'],'name':'Босс','initiative':21})
    assert edited.status_code == 200 and any(e['name']=='Босс' for e in edited.json()['data']['entries'])


def test_verified_fireball_upcast_save_damage(world):
    dm, player, outsider, campaign, char, session = world
    from lab.models import SpellCatalogEntry
    entry = SpellCatalogEntry.objects.get(code='srd51-fireball')
    sheet = sheet_for(char)
    sheet.slots['4'] = {'max':1, 'used':0}
    sheet.save()
    action = CharacterAbility.objects.create(character=char, catalog_entry=entry, kind='spell', name='Огненный шар', ability='int', level=3, resolution='save', save_ability='dex', dice='8d6', upcast_dice='1d6')
    with patch('lab.services.dice.secrets.randbelow', return_value=2):
        r = post(client(player), scoped(f'/api/abilities/{action.id}/use/',campaign), {'slot_level':4})
    assert r.status_code == 200, r.content
    p = r.json()['data']['payload']
    assert p['save']['dc'] == 10 and p['damage']['total'] == 27 and p['save']['success_damage'] == 13


def test_sheet_permissions_party_and_version(world):
    dm, p, o, c, char, s = world
    sh = sheet_for(char)
    sh.notes = "secret note"
    sh.inventory = "private inventory"
    sh.save()
    url = scoped(f"/api/characters/{char.pk}/sheet/", c)
    assert client(p).get(url).status_code == 200
    assert client(dm).get(url).status_code == 200
    assert client(o).get(url).status_code == 403
    Membership.objects.create(campaign=c, user=o)
    assert client(o).get(url).status_code == 403
    public = client(o).get(scoped("/api/room/", c))
    assert public.status_code == 200
    assert (
        b"secret note" not in public.content
        and b"private inventory" not in public.content
    )
    assert public.json()["data"]["party"][0]["hp_current"] == 10
    r = patch_api(
        client(p),
        url,
        {
            "version": sh.version,
            "abilities": {**default_abilities(), "str": 18},
            "skills": {"athletics": 2},
        },
    )
    assert (
        r.status_code == 200
        and r.json()["data"]["computed"]["skills"]["athletics"] == 8
    )
    assert (
        patch_api(
            client(p), url, {"version": sh.version, "hp_current": 5}, "other-patch"
        ).status_code
        == 409
    )


def test_roll_shared_persisted_and_retry(world):
    dm, p, o, c, char, s = world
    url = scoped("/api/room/rolls/", c)
    body = {"character": char.id, "kind": "ability", "key": "str", "total": 999}
    with patch("lab.services.dice.secrets.randbelow", return_value=9):
        r = post(client(p), url, body, "fixed-roll-key")
    assert r.status_code == 200 and r.json()["data"]["payload"]["roll"]["total"] == 10
    assert post(client(p), url, body, "fixed-roll-key").json() == r.json()
    assert RoomEvent.objects.count() == 1 and revision(c.id) > 0
    assert client(dm).get(scoped("/api/room/events/", c)).json()["data"]["count"] == 1
    assert post(client(o), url, body).status_code == 403


def test_hidden_roll(world):
    dm, p, o, c, char, s = world
    post(
        client(p),
        scoped("/api/room/rolls/", c),
        {"character": char.id, "formula": "2d6", "visibility": "dm"},
    )
    assert client(p).get(scoped("/api/room/events/", c)).json()["data"]["count"] == 0
    assert client(dm).get(scoped("/api/room/events/", c)).json()["data"]["count"] == 1
    assert (
        client(dm)
        .get(scoped("/api/room/events/", c) + "&view=player")
        .json()["data"]["count"]
        == 0
    )


def spell(char, **kw):
    return CharacterAbility.objects.create(
        character=char,
        kind="spell",
        name="Fire",
        ability="int",
        level=1,
        dice="2d6",
        upcast_dice="1d6",
        **kw,
    )


def test_slots_upcast_and_retry(world):
    dm, p, o, c, char, s = world
    sh = sheet_for(char)
    sh.slots["2"] = {"max": 1, "used": 0}
    sh.save()
    action = spell(char, resolution="save")
    url = scoped(f"/api/abilities/{action.pk}/use/", c)
    with patch("lab.services.dice.secrets.randbelow", return_value=2):
        r = post(client(p), url, {"slot_level": 2}, "spell-fixed-key")
    assert r.status_code == 200
    data = r.json()["data"]["payload"]
    assert data["damage"]["total"] == 9 and data["save"]["dc"] == 10
    sh.refresh_from_db()
    assert sh.slots["2"]["used"] == 1
    assert post(client(p), url, {"slot_level": 2}, "spell-fixed-key").json() == r.json()
    assert post(client(p), url, {"slot_level": 2}).status_code == 400
    assert RoomEvent.objects.count() == 1


def test_spell_rollback(world):
    dm, p, o, c, char, s = world
    sh = sheet_for(char)
    sh.slots["1"] = {"max": 1, "used": 0}
    sh.save()
    action = spell(char, resolution="automatic")
    with patch("lab.services.sheets.event", side_effect=RuntimeError("failed commit")):
        with pytest.raises(RuntimeError):
            post(client(p), scoped(f"/api/abilities/{action.id}/use/", c), {})
    sh.refresh_from_db()
    assert sh.slots["1"]["used"] == 0
    assert not RoomEvent.objects.exists()


def test_critical_attack(world):
    dm, p, o, c, char, s = world
    sh = sheet_for(char)
    sh.abilities["str"] = 18
    sh.save()
    action = CharacterAbility.objects.create(
        character=char, kind="attack", name="Sword", dice="1d8", add_modifier=True
    )
    with patch("lab.services.dice.secrets.randbelow", side_effect=[19, 3, 3]):
        r = post(client(p), scoped(f"/api/abilities/{action.id}/use/", c), {})
    assert r.status_code == 200
    data = r.json()["data"]["payload"]
    assert (
        data["roll"]["total"] == 26
        and data["damage"]["total"] == 12
        and data["damage"]["critical"]
    )


def test_hp_temp_and_retry(world):
    dm, p, o, c, char, s = world
    sh = sheet_for(char)
    sh.hp_temp = 5
    sh.save()
    url = scoped(f"/api/characters/{char.id}/resources/", c)
    r = post(client(p), url, {"action": "damage", "amount": 8}, "damage-fixed-key")
    assert r.json()["data"]["hp_current"] == 7 and r.json()["data"]["hp_temp"] == 0
    post(client(p), url, {"action": "damage", "amount": 8}, "damage-fixed-key")
    sh.refresh_from_db()
    assert sh.hp_current == 7
    assert (
        post(client(p), url, {"action": "heal", "amount": 100}).json()["data"][
            "hp_current"
        ]
        == 10
    )


def test_initiative_permissions_hidden_and_stale_next(world):
    dm, p, o, c, char, s = world
    url = scoped("/api/room/initiative/", c)
    assert (
        post(client(p), url, {"action": "add", "version": 0, "name": "NPC"}).status_code
        == 403
    )
    r = post(
        client(dm),
        url,
        {
            "action": "add",
            "version": 0,
            "name": "Secret monster",
            "initiative": 30,
            "hidden": True,
        },
    )
    assert r.status_code == 200
    tr = r.json()["data"]
    tr = post(
        client(dm),
        url,
        {
            "action": "add",
            "version": tr["version"],
            "character": char.id,
            "initiative": 10,
        },
    ).json()["data"]
    tr = post(client(dm), url, {"action": "start", "version": tr["version"]}).json()[
        "data"
    ]
    public = client(p).get(scoped("/api/room/", c))
    assert (
        b"Secret monster" not in public.content
        and public.json()["data"]["initiative"]["hidden_turn"]
    )
    version = tr["version"]
    tr = post(client(dm), url, {"action": "next", "version": version}).json()["data"]
    assert tr["round_number"] == 1
    assert (
        post(client(dm), url, {"action": "next", "version": version}).status_code == 409
    )
    assert (
        post(client(dm), url, {"action": "next", "version": tr["version"]}).json()[
            "data"
        ]["round_number"]
        == 2
    )


def test_player_initiative_once(world):
    dm, p, o, c, char, s = world
    url = scoped("/api/room/rolls/", c)
    body = {"character": char.id, "kind": "initiative"}
    assert post(client(p), url, body).status_code == 200
    assert post(client(p), url, body).status_code == 400
    assert InitiativeEntry.objects.count() == 1


def test_master_resets_initiative_and_player_can_roll_again(world):
    dm, p, o, c, char, s = world
    roll_url = scoped('/api/room/rolls/', c)
    initiative_url = scoped('/api/room/initiative/', c)
    assert post(client(p), roll_url, {'character': char.id, 'kind': 'initiative'}).status_code == 200
    tracker = InitiativeTracker.objects.get(session=s)
    assert post(client(p), initiative_url, {'action': 'reset', 'version': tracker.version}).status_code == 403
    start = post(client(dm), initiative_url, {'action': 'start', 'version': tracker.version})
    assert start.status_code == 200
    reset = post(client(dm), initiative_url, {'action': 'reset', 'version': start.json()['data']['version']})
    assert reset.status_code == 200
    state = reset.json()['data']
    assert state['entries'] == [] and state['round_number'] == 0 and not state['running']
    assert InitiativeEntry.objects.filter(tracker=tracker).count() == 0
    assert post(client(p), roll_url, {'character': char.id, 'kind': 'initiative'}).status_code == 200
    assert InitiativeEntry.objects.filter(tracker=tracker, character=char).count() == 1


def test_ability_crud_and_validation(world):
    dm, p, o, c, char, s = world
    url = scoped(f"/api/characters/{char.id}/abilities/", c)
    assert (
        post(
            client(p), url, {"kind": "spell", "name": "Test", "dice": "__import__(1)"}
        ).status_code
        == 400
    )
    r = post(
        client(p),
        url,
        {"kind": "spell", "name": "Light", "dice": "", "resolution": "automatic"},
    )
    assert r.status_code == 200
    action = r.json()["data"]
    detail = scoped(f"/api/abilities/{action['id']}/", c)
    assert (
        patch_api(client(p), detail, {"version": 1, "active": False}).status_code == 200
    )
    assert client(p).get(url).json()["data"] == []
    assert (
        post(
            client(p), scoped(f"/api/abilities/{action['id']}/use/", c), {}
        ).status_code
        == 404
    )


def test_stream_access_revision_and_revocation(world):
    dm, p, o, c, char, s = world
    browser = Client()
    browser.force_login(p)
    response = browser.get(f"/api/campaigns/{c.id}/stream/")
    assert (
        response.status_code == 200 and response["Content-Type"] == "text/event-stream"
    )
    chunks = iter(response.streaming_content)
    assert b"retry:" in next(chunks)
    assert b"event: change" in next(chunks)
    Membership.objects.filter(campaign=c, user=p).update(active=False)
    with patch("lab.api.room.time.sleep"):
        assert b"event: revoked" in next(chunks)
    response.close()
    assert browser.get(f"/api/campaigns/{c.id}/stream/").status_code == 403
    assert Client().get(f"/api/campaigns/{c.id}/stream/").status_code == 403


def test_master_roll_without_character_and_player_denied(world):
    dm, p, o, c, char, s = world
    url = scoped("/api/room/rolls/", c)
    assert post(client(p), url, {"formula": "1d20"}).status_code == 400
    result = post(client(dm), url, {"formula": "2d6+2"})
    assert result.status_code == 200 and result.json()["data"]["character"] is None
    assert client(p).get(scoped("/api/room/events/", c)).json()["data"]["count"] == 1


def test_multiple_rays_upcast_debits_one_slot(world):
    dm, p, o, c, char, s = world
    sh = sheet_for(char)
    sh.slots["3"] = {"max": 1, "used": 0}
    sh.save()
    action = CharacterAbility.objects.create(
        character=char,
        kind="spell",
        name="Rays",
        ability="int",
        level=2,
        dice="2d6",
        resolution="attack",
        roll_count=3,
        upcast_count=1,
    )
    url = scoped(f"/api/abilities/{action.id}/use/", c)
    with patch("lab.services.dice.secrets.randbelow", return_value=2):
        r = post(client(p), url, {"slot_level": 3}, "multiple-ray-key")
    assert r.status_code == 200
    payload = r.json()["data"]["payload"]
    assert len(payload["parts"]) == 4 and payload["total_damage"] == 24
    assert all(
        p["roll"]["chosen"] == 3 and p["damage"]["total"] == 6 for p in payload["parts"]
    )
    sh.refresh_from_db()
    assert sh.slots["3"]["used"] == 1
    assert (
        post(client(p), url, {"slot_level": 3}, "multiple-ray-key").json() == r.json()
    )
    assert RoomEvent.objects.count() == 1


def test_cantrip_scaling_and_slot_independence(world):
    dm, p, o, c, char, s = world
    char.level = 11
    char.save()
    action = CharacterAbility.objects.create(
        character=char,
        kind="spell",
        name="Spark",
        ability="int",
        level=0,
        dice="1d10",
        upcast_dice="1d10",
        resolution="save",
        cantrip_scaling=True,
    )
    with patch("lab.services.dice.secrets.randbelow", return_value=4):
        r = post(client(p), scoped(f"/api/abilities/{action.id}/use/", c), {})
    assert r.status_code == 200
    payload = r.json()["data"]["payload"]
    assert (
        payload["damage"]["total"] == 15
        and len(payload["upcast"]) == 2
        and payload["save"]["dc"] == 12
    )
    assert all(slot["used"] == 0 for slot in sheet_for(char).slots.values())


def test_initiative_pause_preserves_turn_and_validates_id(world):
    dm, p, o, c, char, s = world
    api = client(dm)
    url = scoped("/api/room/initiative/", c)
    tr = post(
        api, url, {"action": "add", "version": 0, "name": "A", "initiative": 10}
    ).json()["data"]
    tr = post(
        api,
        url,
        {"action": "add", "version": tr["version"], "name": "B", "initiative": 5},
    ).json()["data"]
    tr = post(api, url, {"action": "start", "version": tr["version"]}).json()["data"]
    tr = post(api, url, {"action": "next", "version": tr["version"]}).json()["data"]
    current = tr["current"]
    tr = post(api, url, {"action": "stop", "version": tr["version"]}).json()["data"]
    assert (
        post(
            api, url, {"action": "edit", "version": tr["version"], "entry": "oops"}
        ).status_code
        == 400
    )
    tr = post(api, url, {"action": "start", "version": tr["version"]}).json()["data"]
    assert tr["current"] == current and tr["round_number"] == 1


def test_catalog_add_and_protected_upcast(world):
    from django.core.management import call_command
    from lab.models import SpellCatalogEntry
    dm, p, o, c, char, s = world
    call_command('seed_spells', verbosity=0)
    assert SpellCatalogEntry.objects.filter(active=True, code__startswith='srd51-').count() == 319
    assert not SpellCatalogEntry.objects.filter(code='srd51-thorn-whip', active=True).exists()
    fireball = SpellCatalogEntry.objects.get(code='srd51-fireball')
    shield = SpellCatalogEntry.objects.get(code='srd51-shield')
    listing = client(p).get(scoped('/api/spells/catalog/', c) + '&q=Огненный')
    assert listing.status_code == 200
    assert any(row['id'] == fireball.pk for row in listing.json()['data']['results'])
    assert client(o).get(scoped('/api/spells/catalog/', c)).status_code == 403
    url = scoped(f'/api/characters/{char.pk}/spells/catalog/', c)
    first = post(client(p), url, {'spell_id': shield.pk}, 'catalog-add-shield')
    assert first.status_code == 200
    ability = CharacterAbility.objects.get(pk=first.json()['data']['id'])
    assert ability.name == 'Щит' and ability.upcast_allowed
    assert post(client(p), url, {'spell_id': shield.pk}, 'catalog-add-again').json()['data']['id'] == ability.pk
    assert post(client(o), url, {'spell_id': fireball.pk}).status_code == 403
    sheet = sheet_for(char)
    sheet.slots['1'] = {'max': 1, 'used': 0}
    sheet.slots['2'] = {'max': 1, 'used': 0}
    sheet.save()
    use = scoped(f'/api/abilities/{ability.pk}/use/', c)
    assert post(client(p), use, {'slot_level': 2}).status_code == 200
    sheet.refresh_from_db()
    assert sheet.slots['2']['used'] == 1
    blocked = CharacterAbility.objects.create(character=char, kind='spell', name='Домашнее заклинание', level=1, upcast_allowed=False)
    assert post(client(p), scoped(f'/api/abilities/{blocked.pk}/use/', c), {'slot_level': 2}).status_code == 400


def test_every_srd_spell_has_russian_full_description_and_casting_facts(world):
    from django.core.management import call_command
    from lab.models import SpellCatalogEntry

    call_command('seed_spells', verbosity=0)
    spells = list(SpellCatalogEntry.objects.filter(active=True, code__startswith='srd51-'))
    assert len(spells) == 319
    from lab.data.spell_mechanics import EXTRA
    assert sum(bool(spell.template['verified']) for spell in spells) == 15 + len(EXTRA)
    for spell in spells:
        rules = spell.template
        assert rules['description_language'] == 'ru'
        assert len(rules['description']) > 35
        assert 'пока не проверены' not in rules['description']
        assert all(rules[key] for key in ('casting_time', 'range', 'components', 'duration'))
        assert rules['casting_time'] != 'Не проверено'
    fireball = next(spell for spell in spells if spell.code == 'srd51-fireball')
    wish = next(spell for spell in spells if spell.code == 'srd51-wish')
    assert '8к6' in fireball.template['description']
    assert '4-го уровня' in fireball.template['description']
    assert '25 000' in wish.template['description']
    assert wish.template['verified'] is False and wish.template['dice'] == ''
    call_command('seed_spells', verbosity=0)
    assert SpellCatalogEntry.objects.filter(active=True, code__startswith='srd51-').count() == 319


def test_catalog_filters_all_pages_and_details(world):
    dm, player, outsider, campaign, char, session = world
    api = client(player)
    base = scoped('/api/spells/catalog/', campaign)
    result = api.get(base + '&class=Wizard&school=evocation&level=3&q=огненный')
    assert result.status_code == 200
    codes = [entry['code'] for entry in result.json()['data']['results']]
    assert 'srd51-fireball' in codes
    assert api.get(base + '&q=20-foot-radius').status_code == 200
    assert api.get(base + '&q=Fireball&offset=300').json()['data']['count'] >= 1
    assert api.get(base + '&class=Barbarian').status_code == 400
    fireball = SpellCatalogEntry.objects.get(code='srd51-fireball')
    detail = api.get(scoped(f'/api/spells/catalog/{fireball.pk}/', campaign))
    assert detail.status_code == 200
    assert '8d6 fire damage' in detail.json()['data']['rules']['source_en']
    assert client(outsider).get(scoped(f'/api/spells/catalog/{fireball.pk}/', campaign)).status_code == 403


def test_npc_sheet_and_initiative_hidden_from_player(world):
    dm, player, outsider, campaign, char, session = world
    dm_api, player_api = client(dm), client(player)
    npc_url = scoped('/api/characters/', campaign)
    assert post(player_api, npc_url, {'name':'Orc','kind':'npc','campaign':campaign.id}).status_code == 403
    created = post(dm_api, npc_url, {'name':'Orc','kind':'npc','campaign':campaign.id})
    assert created.status_code == 200
    npc = Character.objects.get(pk=created.json()['data']['id'])
    assert all(row['id'] != npc.pk for row in player_api.get(npc_url).json()['data']['results'])
    assert dm_api.get(scoped(f'/api/characters/{npc.pk}/sheet/', campaign)).status_code == 200
    roll = post(dm_api, scoped('/api/room/rolls/', campaign), {'character':npc.pk,'kind':'initiative'})
    assert roll.status_code == 200
    assert any(e['kind']=='npc' for e in dm_api.get(scoped('/api/room/',campaign)).json()['data']['initiative']['entries'])
    assert dm_api.get(scoped('/api/room/',campaign)).json()['data']['npcs'][0]['id']==npc.id
    assert player_api.get(scoped('/api/room/',campaign)).json()['data']['npcs']==[]


def test_account_role_blocks_master_promotion(world):
    dm, player, outsider, campaign, char, session = world
    player.account_role='player'
    player.save(update_fields=['account_role'])
    member=Membership.objects.get(campaign=campaign,user=player)
    url=scoped(f'/api/dm/actions/member/{member.id}/',campaign)
    assert post(client(dm),url,{'role':'dm'}).status_code==400
    member.role='dm'
    member.save(update_fields=['role'])
    assert client(player).get(scoped('/api/dm/overview/',campaign)).status_code==403


def test_ray_of_frost_catalog_cantrip_scales_without_slot(world):
    from lab.models import SpellCatalogEntry
    dm, p, o, c, char, s = world
    char.level = 5
    char.save(update_fields=['level'])
    ray = SpellCatalogEntry.objects.get(code='srd51-ray-of-frost')
    added = post(client(p), scoped(f'/api/characters/{char.pk}/spells/catalog/', c), {'spell_id': ray.pk})
    assert added.status_code == 200
    ability = CharacterAbility.objects.get(pk=added.json()['data']['id'])
    assert ability.level == 0 and not ability.upcast_allowed and ability.cantrip_scaling
    sheet = sheet_for(char)
    before = sheet.slots.copy()
    with patch('lab.services.dice.secrets.randbelow', return_value=2):
        cast = post(client(p), scoped(f'/api/abilities/{ability.pk}/use/', c), {'slot_level': 0})
    assert cast.status_code == 200
    assert cast.json()['data']['payload']['damage']['total'] == 6
    sheet.refresh_from_db()
    assert sheet.slots == before


def test_verified_fireball_uses_fourth_level_slot_and_records_rules(world):
    from django.core.management import call_command
    dm, player, outsider, campaign, char, session = world
    call_command('seed_spells', verbosity=0)
    fireball = SpellCatalogEntry.objects.get(code='srd51-fireball')
    unknown = SpellCatalogEntry.objects.get(code='srd51-wish')
    assert fireball.template['verified'] is True
    assert fireball.template['dice'] == '8d6'
    assert fireball.template['upcast_dice'] == '1d6'
    assert unknown.template['verified'] is False and not unknown.template['dice']
    detail = client(player).get(scoped('/api/spells/catalog/', campaign) + '&q=Огненный шар').json()['data']['results'][0]
    assert detail['rules']['description'] and detail['rules']['range'] == '150 футов'
    spell = post(client(player), scoped(f'/api/characters/{char.pk}/spells/catalog/', campaign), {'spell_id': fireball.pk}).json()['data']
    sheet = sheet_for(char)
    sheet.slots['4'] = {'max': 1, 'used': 0}
    sheet.save()
    use = scoped(f'/api/abilities/{spell["id"]}/use/', campaign)
    with patch('lab.services.dice.secrets.randbelow', return_value=2):
        response = post(client(player), use, {'slot_level': 4}, 'fireball-fourth-slot')
    assert response.status_code == 200
    payload = response.json()['data']['payload']
    assert payload['damage']['total'] == 27
    assert payload['slot_level'] == 4 and payload['verified_rules']
    assert 'радиусом 20 футов' in payload['description']
    sheet.refresh_from_db()
    assert sheet.slots['4']['used'] == 1
    retry = post(client(player), use, {'slot_level': 4}, 'fireball-fourth-slot')
    assert retry.status_code == 200 and retry.json()['data']['id'] == response.json()['data']['id']
    sheet.refresh_from_db()
    assert sheet.slots['4']['used'] == 1


def test_extended_spell_presets_and_legacy_catalog_action(world):
    dm, player, outsider, campaign, char, session = world
    from django.core.management import call_command
    from lab.data.spell_mechanics import EXTRA
    from lab.services.dice import parse_formula
    from lab.models import SpellCatalogEntry

    call_command('seed_spells', verbosity=0)
    for name, preset in EXTRA.items():
        entry = SpellCatalogEntry.objects.get(name_en=name)
        assert entry.template['verified'] and entry.template['dice'] == preset['dice']
        parse_formula(preset['dice'])
        if preset['upcast_dice']:
            parse_formula(preset['upcast_dice'])
    entry = SpellCatalogEntry.objects.get(name_en='Spiritual Weapon')
    legacy = CharacterAbility.objects.create(
        character=char, catalog_entry=entry, kind='spell', name=entry.name_ru,
        level=2, resolution='automatic', dice='', ability='int',
    )
    call_command('seed_spells', verbosity=0)
    legacy.refresh_from_db()
    assert legacy.resolution == 'attack' and legacy.dice == '1d8'
    sheet = sheet_for(char)
    sheet.slots['3'] = {'max': 1, 'used': 0}
    sheet.slots['4'] = {'max': 1, 'used': 0}
    sheet.spell_ability = 'wis'
    sheet.abilities['wis'] = 16
    sheet.save()
    with patch('lab.services.dice.secrets.randbelow', return_value=2):
        result = post(client(player), scoped(f'/api/abilities/{legacy.pk}/use/', campaign), {'slot_level': 4})
    assert result.status_code == 200, result.content
    payload = result.json()['data']['payload']
    assert payload['spell_save_dc'] == 13 and payload['spell_attack_bonus'] == 5
    assert payload['roll']['total'] == 8
    assert payload['damage']['total'] == 9  # 1d8 + modifier 3 + 1d8 every two levels
    assert payload['slot_level'] == 4


def test_catalog_reference_cast_has_dc_and_expends_slot(world):
    dm, player, outsider, campaign, char, session = world
    from lab.models import SpellCatalogEntry
    entry = SpellCatalogEntry.objects.get(code='srd51-bane')
    spell = post(client(player), scoped(f'/api/characters/{char.pk}/spells/catalog/', campaign), {'spell_id': entry.pk}).json()['data']
    sheet = sheet_for(char)
    sheet.slots['1'] = {'max': 1, 'used': 0}
    sheet.save()
    result = post(client(player), scoped(f'/api/abilities/{spell["id"]}/use/', campaign), {'slot_level': 1})
    assert result.status_code == 200, result.content
    payload = result.json()['data']['payload']
    assert payload['spell_save_dc'] == 10 and payload['spell_attack_bonus'] == 2
    assert payload['possible_saves'] == ['cha']
    assert 'damage' not in payload and 'adjudication' in payload
    sheet.refresh_from_db()
    assert sheet.slots['1']['used'] == 1


def test_deferred_spell_rolls_only_on_trigger_without_second_slot(world):
    dm, player, outsider, campaign, char, session = world
    entry = SpellCatalogEntry.objects.get(code='srd51-moonbeam')
    spell = post(client(player), scoped(f'/api/characters/{char.pk}/spells/catalog/', campaign), {'spell_id': entry.pk}).json()['data']
    sheet = sheet_for(char)
    sheet.slots['2'] = {'max': 1, 'used': 0}
    sheet.save()
    url = scoped(f'/api/abilities/{spell["id"]}/use/', campaign)
    assert post(client(player), url, {'trigger': True}).status_code == 400
    with patch('lab.services.dice.secrets.randbelow', return_value=2):
        first = post(client(player), url, {'slot_level': 2}).json()['data']['payload']
    assert first['deferred'] and first['damage']['total'] == 6 and first['trigger'] is False
    assert first['save']['success_damage'] == 3 and first['save']['failed_damage'] == 6
    assert 'Предварительный бросок' in first['adjudication']
    with patch('lab.services.dice.secrets.randbelow', return_value=2):
        second = post(client(player), url, {'trigger': True}, 'moonbeam-trigger').json()['data']['payload']
    assert second['damage']['total'] == 6 and second['save']['success_damage'] == 3
    sheet.refresh_from_db()
    assert sheet.slots['2']['used'] == 1
    assert second['source_cast_id'] and second['trigger'] is True
    assert post(client(player), url, {'trigger': True}, 'moonbeam-trigger').json()['data']['payload'] == second
    sheet.conditions = []
    sheet.save()
    assert post(client(player), url, {'trigger': True}, 'new-trigger').status_code == 400


@pytest.mark.parametrize('name,level,formula,save,success_factor', [
    ('Vicious Mockery', 0, '1d4', 'wis', 0),
    ('Fireball', 3, '8d6', 'dex', 0.5),
    ('Disintegrate', 6, '10d6+40', 'dex', 0),
    ('Feeblemind', 8, '4d6', 'int', 1),
])
def test_save_spell_reports_both_damage_outcomes(world, name, level, formula, save, success_factor):
    dm, player, outsider, campaign, char, session = world
    entry = SpellCatalogEntry.objects.get(name_en=name)
    spell = post(client(player), scoped(f'/api/characters/{char.pk}/spells/catalog/', campaign), {'spell_id': entry.pk}).json()['data']
    sheet = sheet_for(char)
    if level:
        sheet.slots[str(level)] = {'max':1,'used':0}
        sheet.save()
    with patch('lab.services.dice.secrets.randbelow', return_value=2):
        response = post(client(player), scoped(f'/api/abilities/{spell["id"]}/use/', campaign), {'slot_level': level})
    assert response.status_code == 200, response.content
    payload = response.json()['data']['payload']
    failed = payload['damage']['total']
    assert payload['damage']['formula'] == formula
    assert payload['save'] == {'ability':save,'dc':10,'failed_damage':failed,
                               'success_damage':int(failed * success_factor)}


def test_fixed_dc_and_repeated_spell_save_can_change_ability(world):
    dm, player, outsider, campaign, char, session = world
    sheet = sheet_for(char)
    sheet.slots['5'] = {'max': 1, 'used': 0}
    sheet.slots['7'] = {'max': 1, 'used': 0}
    sheet.save()
    for name, level in [('Contact Other Plane', 5), ('Wall of Ice', 7)]:
        entry = SpellCatalogEntry.objects.get(name_en=name)
        spell = post(client(player), scoped(f'/api/characters/{char.pk}/spells/catalog/', campaign), {'spell_id':entry.pk}).json()['data']
        with patch('lab.services.dice.secrets.randbelow', return_value=2):
            response = post(client(player), scoped(f'/api/abilities/{spell["id"]}/use/', campaign), {'slot_level':level})
        assert response.status_code == 200, response.content
        payload = response.json()['data']['payload']
        if name == 'Contact Other Plane':
            assert payload['save'] == {'ability':'int','dc':15,'failed_damage':18,'success_damage':0}
        else:
            assert payload['save'] == {'ability':'dex','dc':10,'failed_damage':36,'success_damage':18}
            with patch('lab.services.dice.secrets.randbelow', return_value=2):
                triggered = post(client(player), scoped(f'/api/abilities/{spell["id"]}/use/', campaign), {'trigger':True})
            assert triggered.status_code == 200, triggered.content
            repeat = triggered.json()['data']['payload']
            assert repeat['save'] == {'ability':'con','dc':10,'failed_damage':18,'success_damage':9}
    sheet.refresh_from_db()
    assert sheet.slots['5']['used'] == sheet.slots['7']['used'] == 1
