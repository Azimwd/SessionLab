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
