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
} from "../components/ui";
import type { Json } from "../api/client";
export default function Profile() {
  const a = useApp();
  const [modal, setModal] = useState(""),
    [edit, setEdit] = useState<Json | null>(null),
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
            <div className="avatar huge">
              {(a.user.first_name || a.user.email).slice(0, 1).toUpperCase()}
            </div>
            <div>
              <h2>{a.user.first_name || "Игрок"}</h2>
              <p>{a.user.email}</p>
              <Badge>SESSIONLAB MEMBER</Badge>
            </div>
          </div>
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
            <Button onClick={() => setModal("campaign")}>
              <Plus size={16} />
              Создать
            </Button>
            <Button variant="secondary" onClick={() => setModal("join")}>
              Присоединиться
            </Button>
          </div>
        </Card>
      </div>
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
          .filter((c) => c.owner === a.user.id)
          .map((c) => (
            <Card key={c.id}>
              <div className="card-heading">
                <span className="avatar">{c.name.slice(0, 1)}</span>
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
              </div>
            </Card>
          ))}
      </div>
      {!a.characters.some((c) => c.owner === a.user.id) && (
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
              const f = Object.fromEntries(new FormData(e.currentTarget));
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
                  onSuccess: (r) => {
                    if (modal !== "character") a.selectCampaign(String(r.id));
                    else a.selectCharacter(String(r.id));
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
                    <Field label="URL аватара">
                      <input
                        name="avatar"
                        type="url"
                        defaultValue={edit?.avatar}
                      />
                    </Field>
                  </div>
                )}
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
    </>
  );
}
