import { Link } from "react-router-dom";
import { useState } from "react";
import {
  Plus,
  Users,
  UserRound,
  Coins,
  Sun,
  Moon,
  Check,
  ArrowRight,
  Award,
  Trash2,
} from "lucide-react";
import { useApp, useData, useAction } from "../app";
import {
  Header,
  Button,
  Card,
  Field,
  Modal,
  Badge,
  Empty,
  Pagination,
  ErrorBox,
  Loading,
  Confirm,
} from "../components/ui";
import { request, type Json } from "../api/client";
export default function Profile() {
  const a = useApp();
  const [modal, setModal] = useState(""),
    [edit, setEdit] = useState<Json | null>(null),
    [deleting, setDeleting] = useState<Json | null>(null),
    [page, setPage] = useState(1);
  const action = useAction("Изменения сохранены");
  const tx = useData<any>(
    `/casino/transactions/?campaign=${a.cid}&page=${page}`,
    !!a.cid,
  );
  const feed = useData<any>(`/feed/?campaign=${a.cid}`, !!a.cid);
  return (
    <>
      <Header
        eyebrow="YOUR SPACE"
        title="Мой профиль"
        subtitle="Персонажи, кампании и ваши маленькие достижения."
      />
      <div className="profile-grid">
        <Card>
          <div className="profile-heading">
            {a.user.avatar_url?<img className="avatar huge" src={a.user.avatar_url} alt="Аватар профиля"/>:<div className="avatar huge">{(a.user.first_name || a.user.email).slice(0, 1).toUpperCase()}</div>}
            <div>
              <h2>{a.user.first_name || "Игрок"}</h2>
              <p>{a.user.email}</p>
              <Badge>SESSIONLAB MEMBER</Badge>
            </div>
          </div>
          <div className="avatar-upload"><label>Фото профиля <input type="file" accept="image/png,image/jpeg,image/webp" aria-label="Загрузить фото профиля" disabled={action.isPending} onChange={e=>{const file=e.target.files?.[0];if(file){const data=new FormData();data.append('image',file);action.mutate({path:'/auth/me/avatar/',body:data});e.target.value='';}}}/></label>{a.user.avatar_url&&<Button variant="ghost" disabled={action.isPending} onClick={()=>action.mutate({path:'/auth/me/avatar/',method:'DELETE'})}>Удалить фото</Button>}</div>
          <form
            onSubmit={(e) => {
              e.preventDefault();
              const f = new FormData(e.currentTarget);
              action.mutate({
                path: "/auth/me/",
                method: "PATCH",
                body: {
                  first_name: f.get("name"),
                  theme: a.theme,
                  reduced_motion: a.reduced,
                },
              });
            }}
          >
            <Field label="Имя">
              <input
                name="name"
                defaultValue={a.user.first_name}
                maxLength={80}
              />
            </Field>
            <div className="settings-row">
              <div>
                <strong>Тёмная тема</strong>
                <small>Настройте пространство под себя</small>
              </div>
              <button
                type="button"
                aria-label="Переключить тему"
                className={`toggle ${a.theme === "dark" ? "on" : ""}`}
                onClick={a.toggleTheme}
              >
                <span />
              </button>
            </div>
            <div className="settings-row">
              <div>
                <strong>Меньше анимаций</strong>
                <small>Системная настройка тоже учитывается</small>
              </div>
              <button
                type="button"
                aria-label="Уменьшить анимации"
                aria-pressed={a.reduced}
                className={`toggle ${a.reduced ? "on" : ""}`}
                onClick={() => a.setReduced(!a.reduced)}
              >
                <span />
              </button>
            </div>
            <Button disabled={action.isPending}>
              <Check size={16} />
              Сохранить настройки
            </Button>
          </form>
        </Card>
        <Card>
          <div className="section-title">
            <h2>Кампании</h2>
            <Users size={18} />
          </div>
          <div className="campaign-list">
            {a.campaigns.map((c) => (
              <button
                className={a.cid === String(c.id) ? "selected" : ""}
                key={c.id}
                onClick={() => a.selectCampaign(String(c.id))}
              >
                <span className="workspace-avatar">{c.name.slice(0, 1)}</span>
                <div>
                  <strong>{c.name}</strong>
                  <small>
                    {c.role === "dm" ? "Мастер" : "Игрок"} ·{" "}
                    {c.settings.edition}
                  </small>
                </div>
                {a.cid === String(c.id) && <Check size={17} />}
              </button>
            ))}
          </div>
          {!a.campaigns.length && (
            <p>Ваше первое приключение начинается здесь.</p>
          )}
          <div className="actions">
            {a.user.account_role === 'dm' && <Button onClick={() => setModal("campaign")}>
              <Plus size={16} />
              Создать
            </Button>}
            <Button variant="secondary" onClick={() => setModal("join")}>
              Присоединиться
            </Button>
          </div>
        </Card>
      </div>
      {!!a.cid && <DMHubSheetKey campaign={a.cid}/>}
      <div className="section-title spacer">
        <h2>Мои персонажи</h2>
        <Button
          variant="secondary"
          disabled={!a.campaign}
          onClick={() => {
            setEdit(null);
            setModal("character");
          }}
        >
          <Plus size={17} />
          Новый персонаж
        </Button>
      </div>
      <div className="grid three">
        {a.characters
          .filter((c) => c.owner === a.user.id && c.kind !== 'npc')
          .map((c) => (
            <Card key={c.id}>
              <div className="card-heading">
                {c.avatar_url?<img className="avatar" src={c.avatar_url} alt=""/>:<span className="avatar">{c.name.slice(0, 1)}</span>}
                <Badge>{c.level} УР.</Badge>
              </div>
              <h3>{c.name}</h3>
              <p>
                {c.character_class || "Без класса"} ·{" "}
                {c.species || "Вид не указан"}
              </p>
              <p>{c.description}</p>
              <div className="actions">
                <Link className="button secondary" to={`${a.masterMode ? '/master/sheets' : '/sheet'}?character=${c.id}`}>Открыть лист</Link>
                <Button
                  variant={a.charId === String(c.id) ? "" : "secondary"}
                  onClick={() => a.selectCharacter(String(c.id))}
                >
                  {a.charId === String(c.id) ? "Выбран" : "Выбрать"}
                </Button>
                <Button
                  variant="ghost"
                  onClick={() => {
                    setEdit(c);
                    setModal("character");
                  }}
                >
                  Изменить
                </Button>
                <Button variant="ghost" aria-label={`Удалить ${c.name}`} onClick={()=>setDeleting(c)}><Trash2 size={15}/> Удалить</Button>
              </div>
            </Card>
          ))}
      </div>
      {!a.characters.some((c) => c.owner === a.user.id && c.kind !== 'npc') && (
        <Empty
          title="За каждой историей есть персонаж"
          text="Создайте персонажа и постепенно заполните его характеристики, атаки и заклинания."
        />
      )}
      <div className="section-title spacer">
        <h2>Достижения</h2>
        <Award size={20} />
      </div>
      <div className="achievement-list">
        {feed.data?.achievements?.length ? (
          feed.data.achievements.map((d: Json) => (
            <Card key={d.code}>
              <Award size={24} />
              <strong>{d.title}</strong>
              <small>
                {new Date(d.created_at).toLocaleDateString("ru-RU")}
              </small>
            </Card>
          ))
        ) : (
          <p className="muted">
            Подтвердите первый мини-квест и получите свой первый значок.
          </p>
        )}
      </div>
      {a.cid && (
        <>
          <div className="section-title spacer">
            <h2>История жетонов</h2>
            <Coins size={19} />
          </div>
          {tx.error ? (
            <ErrorBox error={tx.error} />
          ) : tx.isPending ? (
            <Loading />
          ) : (
            <Card className="table-wrap">
              <table>
                <thead>
                  <tr>
                    <th>Операция</th>
                    <th>Изменение</th>
                    <th>Баланс</th>
                    <th>Время</th>
                  </tr>
                </thead>
                <tbody>
                  {tx.data?.results?.map((t: Json) => (
                    <tr key={t.id}>
                      <td>
                        {{
                          initial: "Стартовые жетоны",
                          stake: "Ставка",
                          payout: "Выплата",
                          quest: "Награда за квест",
                          adjustment: "Корректировка мастера",
                        }[t.kind as string] || t.kind}
                        <small>{t.note}</small>
                      </td>
                      <td className={Number(t.amount) > 0 ? "positive" : ""}>
                        {Number(t.amount) > 0 ? "+" : ""}
                        {t.amount} ST
                      </td>
                      <td>{t.balance_after} ST</td>
                      <td>{new Date(t.created_at).toLocaleString("ru-RU")}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
              <Pagination
                page={page}
                setPage={setPage}
                count={tx.data?.count || 0}
              />
            </Card>
          )}
        </>
      )}
      {modal && (
        <Modal
          title={
            modal === "campaign"
              ? "Новое пространство"
              : modal === "join"
                ? "Присоединиться к кампании"
                : edit
                  ? "Изменить персонажа"
                  : "Новый персонаж"
          }
          onClose={() => setModal("")}
        >
          <form
            onSubmit={(e) => {
              e.preventDefault();
              const form = new FormData(e.currentTarget);
              const photo = form.get('image');
              form.delete('image');
              const f = Object.fromEntries(form);
              const body =
                modal === "character"
                  ? { ...f, level: Number(f.level), campaign: a.campaign?.id }
                  : f;
              const path =
                modal === "campaign"
                  ? "/campaigns/"
                  : modal === "join"
                    ? "/campaigns/join/"
                    : edit
                      ? `/characters/${edit.id}/?campaign=${a.cid}`
                      : `/characters/?campaign=${a.cid}`;
              action.mutate(
                {
                  path,
                  body,
                  method: edit && modal === "character" ? "PATCH" : "POST",
                },
                {
                  onSuccess: async (r) => {
                    if (modal !== "character") a.selectCampaign(String(r.id));
                    else {
                      a.selectCharacter(String(r.id));
                      if(photo instanceof File && photo.size){const upload=new FormData();upload.append('image',photo);try{await action.mutateAsync({path:`/characters/${r.id}/avatar/?campaign=${a.cid}`,body:upload});}catch{a.notify('Персонаж сохранён, но фото не загрузилось. Повторите загрузку при редактировании.');}}
                    }
                    setModal("");
                  },
                },
              );
            }}
          >
            {modal === "join" ? (
              <Field label="Код приглашения от мастера">
                <input
                  name="code"
                  required
                  placeholder="Вставьте код кампании"
                />
              </Field>
            ) : (
              <>
                <Field label="Название / имя">
                  <input
                    name="name"
                    required
                    maxLength={100}
                    defaultValue={edit?.name}
                  />
                </Field>
                {modal === "character" && (
                  <div className="grid two">
                    <Field label="Класс">
                      <input
                        name="character_class"
                        defaultValue={edit?.character_class}
                        maxLength={60}
                      />
                    </Field>
                    <Field label="Уровень">
                      <input
                        name="level"
                        type="number"
                        min={1}
                        max={30}
                        defaultValue={edit?.level || 1}
                      />
                    </Field>
                    <Field label="Раса / вид">
                      <input
                        name="species"
                        defaultValue={edit?.species}
                        maxLength={60}
                      />
                    </Field>
                  </div>
                )}
                {modal==='character'&&<Field label="Фото персонажа (PNG, JPEG или WebP, до 2 МБ)"><input type="file" name="image" accept="image/png,image/jpeg,image/webp"/></Field>}
                <Field label="Краткая история">
                  <textarea
                    name="description"
                    defaultValue={edit?.description}
                    maxLength={3000}
                  />
                </Field>
              </>
            )}
            <Button disabled={action.isPending}>
              Сохранить <ArrowRight size={16} />
            </Button>
          </form>
        </Modal>
      )}
      {deleting&&<Confirm title={`Удалить «${deleting.name}»?`} text="Персонаж исчезнет из списка, история останется." busy={action.isPending} onClose={()=>setDeleting(null)} onConfirm={()=>action.mutate({path:`/characters/${deleting.id}/?campaign=${a.cid}`,method:'DELETE'},{onSuccess:()=>{if(a.charId===String(deleting.id))a.selectCharacter('');setDeleting(null);}})}/>}
    </>
  );
}

function DMHubSheetKey({campaign}:{campaign:string}) {
  const a=useApp();
  const status=useData<Json>(`/integrations/dmhub/sheet-access/?campaign=${campaign}`);
  const [token,setToken]=useState('');
  const [busy,setBusy]=useState(false);
  const change=async (action:'rotate'|'revoke')=>{
    setBusy(true);
    try {
      const result=await request<Json>(`/integrations/dmhub/sheet-access/?campaign=${campaign}`,'POST',{action});
      setToken(result.token||'');
      await status.refetch();
      a.notify(action==='rotate'?'Ключ листа создан. Скопируйте его сейчас.':'Ключ листа отключён.');
    } catch(error){a.notify(error instanceof Error?error.message:'Не удалось изменить ключ');}
    finally{setBusy(false);}
  };
  return <Card>
    <h2>Мой лист в DMHub</h2>
    <p className="muted">Отдельный ключ только для ваших листов в выбранной кампании. Мастер с правами кампании может открывать её листы. Ключ показывается один раз; храните его как пароль.</p>
    {status.error?<ErrorBox error={status.error} retry={()=>status.refetch()}/>:<Badge tone={status.data?.enabled?'green':undefined}>{status.data?.enabled?'Подключение разрешено':'Не подключено'}</Badge>}
    <div className="actions">
      <Button disabled={busy} onClick={()=>change('rotate')}>Создать / сменить ключ листа</Button>
      {status.data?.enabled&&<Button variant="secondary" disabled={busy} onClick={()=>change('revoke')}>Отключить ключ</Button>}
    </div>
    {token&&<Field label="Скопируйте в SHEET_TOKEN мода DMHub"><input readOnly type="text" value={token} onFocus={e=>e.currentTarget.select()} autoComplete="off"/></Field>}
    <p className="muted">Ключ чата мастера и ключ листа различаются. Инструкция: docs/DMHUB.md.</p>
  </Card>;
}
