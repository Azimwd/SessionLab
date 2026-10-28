from lab.models import DamageApplication, RoomEvent, SceneTarget
from .test_api import world, client, scoped
from .test_scene import targets, event


def test_history_pages_are_bounded_private_and_stable_when_new_events_arrive(world):
    dm,p,_,c,_,s=world
    _,ts=targets(world)
    target=SceneTarget.objects.get(pk=ts[0]['id'])
    def append(requester=p):
        return DamageApplication.objects.create(target=target,source_event=event(world),requester=requester,status='applied')
    rows=[append() for _ in range(23)]
    append(dm)  # Other authors are not included in a player's history.
    url=scoped('/api/scene/damage/',c)+'&status=applied&page_size=10'
    api=client(p)
    r=api.get(url);assert r.status_code==200,r.content
    first=r.json()['data'];assert len(first['results'])==10
    assert 'hp_current' not in str(first) and 'resolution' not in str(first)
    newest=append()
    second=api.get(url+f"&before={first['next_cursor']}").json()['data']
    third=api.get(url+f"&before={second['next_cursor']}").json()['data']
    assert len(second['results'])==10 and len(third['results'])==3
    assert third['next_cursor'] is None
    ids=[row['id'] for page in [first,second,third] for row in page['results']]
    assert ids==[row.id for row in reversed(rows)] and newest.pk not in ids
    # Older integrations retain their array response; pagination is opt-in.
    assert isinstance(api.get(scoped('/api/scene/damage/',c)).json()['data'],list)
    SceneTarget.objects.filter(pk=target.pk).update(visible=False)
    assert api.get(url).json()['data']=={'results':[],'next_cursor':None}
    assert len(client(dm).get(url).json()['data']['results'])==10


def test_history_rejects_invalid_page_parameters(world):
    api=client(world[1]);url=scoped('/api/scene/damage/',world[3])
    for query in ['page_size=0','page_size=51','page_size=no','page_size=1.5','page_size=-1','before=0','before=oops','before='+'9'*100]:
        assert api.get(url+'&'+query).status_code==400,query
