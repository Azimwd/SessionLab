import { useState } from "react";
import {
  Plus,
  Check,
  X,
  Copy,
  Archive,
  Download,
  Upload,
  Play,
  Square,
  SlidersHorizontal,
  ArrowRight,
  Search,
} from "lucide-react";
import { useApp, useData, useAction } from "../app";
import { request, type Json } from "../api/client";
import {
  Header,
  Card,
  Button,
  Badge,
  Status,
  Modal,
  Field,
  Empty,
  Pagination,
  Loading,
  ErrorBox,
  Confirm,
} from "../components/ui";
import { gameInfo } from "./Casino";
export default function DM() {
  const a = useApp();
  const [tab, setTab] = useState("overview");
  const tabs = [
    ["overview", "Обзор"],
    ["sessions", "Сессии"],
    ["effects", "Эффекты"],
    ["quests", "Квесты"],
    ["casino", "Казино"],
    ["members", "Участники"],
    ["settings", "Настройки"],
    ["pools", "Наборы"],
    ["audit", "Журнал"],
  ];
  return (
    <>
      <Header
        eyebrow="DUNGEON MASTER / CONTROL ROOM"
        title="Всё для вашей истории."
        subtitle={`${a.campaign?.name} · Управляйте миром, оставляя место неожиданностям.`}
        action={<Badge tone="green">Мастер кампании</Badge>}
      />
      <div className="tabs dm-tabs">
        {tabs.map(([id, l]) => (
          <button
            className={tab === id ? "active" : ""}
            key={id}
            onClick={() => setTab(id)}
          >
            {l}
          </button>
        ))}
      </div>
      {tab === "overview" ? (
        <Overview />
      ) : tab === "sessions" ? (
        <Sessions />
      ) : tab === "effects" || tab === "quests" ? (
        <Content kind={tab} />
      ) : tab === "casino" ? (
        <CasinoSettings />
      ) : tab === "members" ? (
        <Members />
      ) : tab === "settings" ? (
        <Settings />
      ) : tab === "pools" ? (
        <Pools />
      ) : (
        <Journal />
      )}
    </>
  );
}
function Overview() {
  const a = useApp();
  const q = useData<Json>(`/dm/overview/?campaign=${a.cid}`);
  const action = useAction("Решение сохранено");
  const [manual, setManual] = useState(false),
    [decision, setDecision] = useState<Json | null>(null);
  if (q.isPending) return <Loading />;
  if (q.error) return <ErrorBox error={q.error} />;
  const d = q.data!;
  const pending = d.quests.filter(
    (r: Json) => r.status === "pending_verification",
  );
  const decide = (kind: string, id: number, approve: boolean) =>
    setDecision({ kind, id, approve });
  return (
    <>
      <div className="grid three dm-metrics">
        {[
          ["Участников", d.members.filter((m: Json) => m.active).length],
          [
            "Ожидают решения",
            pending.length + d.approvals.length + d.exchanges.length,
          ],
          ["Активная сессия", a.session?.name || "Нет"],
        ].map(([l, v]) => (
          <Card key={l}>
            <small>{l}</small>
            <strong>{v}</strong>
          </Card>
        ))}
      </div>
      <div className="section-title spacer">
        <h2>Входящие запросы</h2>
        <Button variant="secondary" onClick={() => setManual(true)}>
          <Plus size={16} />
          Ручная выдача
        </Button>
      </div>
      <div className="grid two">
        {pending.map((r: Json) => (
          <Card key={"q" + r.id}>
            <Badge>МИНИ-КВЕСТ</Badge>
            <h3>{r.snapshot.title}</h3>
            <p>
              {r.character_name} · +{r.snapshot.reward} ST
            </p>
            <blockquote>{r.evidence}</blockquote>
            <div className="actions">
              <Button
                disabled={action.isPending}
                onClick={() => decide("quest", r.id, true)}
              >
                <Check size={16} />
                Подтвердить
              </Button>
              <Button
                variant="secondary"
                onClick={() => decide("quest", r.id, false)}
              >
                Отклонить
              </Button>
            </div>
          </Card>
        ))}
        {d.approvals.map((r: Json) => {
          const effect = d.effects.find((e: Json) => e.id === r.effect_id);
          return (
            <Card key={"e" + r.id}>
              <Badge>СЮЖЕТНЫЙ ЭФФЕКТ</Badge>
              <h3>{effect?.snapshot.title || `Карточка #${r.effect_id}`}</h3>
              <p>{effect?.character_name}</p>
              <blockquote>{r.description}</blockquote>
              {effect?.snapshot.secret && (
                <p className="secret">Секрет: {effect.snapshot.secret}</p>
              )}
              <div className="actions">
                <Button onClick={() => decide("effect", r.id, true)}>
                  <Check size={16} />
                  Подтвердить
                </Button>
                <Button
                  variant="secondary"
                  onClick={() => decide("effect", r.id, false)}
                >
                  Отклонить
                </Button>
              </div>
            </Card>
          );
        })}
        {d.exchanges.map((r: Json) => (
          <Card key={"x" + r.id}>
            <Badge>ОБМЕН · СОГЛАСИЕ ПОЛУЧЕНО</Badge>
            <h3>Передача → {r.target__name}</h3>
            <p>
              Карточка #{r.offered_id}
              {r.requested_id ? ` ↔ #${r.requested_id}` : ""}
            </p>
            <div className="actions">
              <Button onClick={() => decide("exchange", r.id, true)}>
                Подтвердить
              </Button>
              <Button
                variant="secondary"
                onClick={() => decide("exchange", r.id, false)}
              >
                Отклонить
              </Button>
            </div>
          </Card>
        ))}
      </div>
      {!pending.length && !d.approvals.length && !d.exchanges.length && (
        <Empty
          title="Всё под контролем"
          text="Новые запросы игроков появятся здесь."
        />
      )}
      <div className="section-title spacer">
        <h2>Выданные эффекты</h2>
        <small>Последние 100</small>
      </div>
      <Card className="table-wrap">
        <table>
          <thead>
            <tr>
              <th>Персонаж</th>
              <th>Эффект</th>
              <th>Статус</th>
              <th />
            </tr>
          </thead>
          <tbody>
            {d.effects.map((r: Json) => (
              <tr key={r.id}>
                <td>{r.character_name}</td>
                <td>
                  #{r.id} · {r.snapshot.title || "Выбор из трёх"}
                  {r.snapshot.secret && (
                    <small>Секрет: {r.snapshot.secret}</small>
                  )}
                </td>
                <td>
                  <Status status={r.status} />
                </td>
                <td>
                  {["active", "rolled"].includes(r.status) && (
                    <Button
                      variant="ghost"
                      disabled={action.isPending}
                      onClick={() => decide("cancel-effect", r.id, true)}
                    >
                      Отменить
                    </Button>
                  )}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </Card>
      <div className="section-title spacer">
        <h2>Квесты игроков</h2>
      </div>
      <Card className="table-wrap">
        <table>
          <thead>
            <tr>
              <th>Персонаж</th>
              <th>Квест</th>
              <th>Статус</th>
              <th />
            </tr>
          </thead>
          <tbody>
            {d.quests.map((r: Json) => (
              <tr key={r.id}>
                <td>{r.character_name}</td>
                <td>{r.snapshot.title}</td>
                <td>
                  <Status status={r.status} />
                </td>
                <td>
                  {!["completed", "cancelled"].includes(r.status) && (
                    <Button
                      variant="ghost"
                      onClick={() => decide("cancel-quest", r.id, true)}
                    >
                      Отменить
                    </Button>
                  )}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </Card>
      <div className="section-title spacer">
        <h2>Статистика получения карточек</h2>
      </div>
      <Card className="table-wrap">
        <table>
          <tbody>
            {d.content_stats.map((r: Json, i: number) => (
              <tr key={i}>
                <td>{r.snapshot__title || "Выбор из трёх"}</td>
                <td>{r.count} получений</td>
              </tr>
            ))}
          </tbody>
        </table>
      </Card>
      {decision && (
        <Modal
          title={decision.approve ? "Подтвердить действие" : "Отклонить запрос"}
          onClose={() => setDecision(null)}
        >
          <form
            onSubmit={(e) => {
              e.preventDefault();
              const note = new FormData(e.currentTarget).get("note");
              action.mutate(
                {
                  path: `/dm/actions/${decision.kind}/${decision.id}/?campaign=${a.cid}`,
                  body: { approve: decision.approve, note },
                },
                { onSuccess: () => setDecision(null) },
              );
            }}
          >
            <Field label="Комментарий мастера">
              <textarea name="note" maxLength={3000} />
            </Field>
            <Button disabled={action.isPending}>Сохранить решение</Button>
          </form>
        </Modal>
      )}
      {manual && (
        <Modal title="Ручная выдача" onClose={() => setManual(false)}>
          <p>
            Повторный эффект выдаётся как дополнительный и не меняет историю
            прежнего. Лимит квестов сохраняется.
          </p>
          <form
            onSubmit={(e) => {
              e.preventDefault();
              const f = Object.fromEntries(new FormData(e.currentTarget));
              action.mutate(
                {
                  path: `/dm/actions/${f.kind}/${Number(f.definition) || 0}/?campaign=${a.cid}`,
                  body: {
                    character: Number(f.character),
                    session: Number(f.session),
                  },
                },
                { onSuccess: () => setManual(false) },
              );
            }}
          >
            <Field label="Операция">
              <select name="kind">
                <option value="reroll">Дополнительный случайный эффект</option>
                <option value="assign-effect">Выдать эффект по ID</option>
                <option value="assign-quest">Назначить квест по ID</option>
              </select>
            </Field>
            <Field label="Сессия">
              <select name="session" required>
                {a.sessions
                  .filter((s) => s.status === "active")
                  .map((s) => (
                    <option value={s.id} key={s.id}>
                      {s.name}
                    </option>
                  ))}
              </select>
            </Field>
            <Field label="Персонаж">
              <select name="character" required>
                {a.characters
                  .filter((c) => c.active)
                  .map((c) => (
                    <option key={c.id} value={c.id}>
                      {c.name}
                    </option>
                  ))}
              </select>
            </Field>
            <Field label="ID определения (для конкретной выдачи)">
              <input type="number" name="definition" min={1} />
            </Field>
            <Button disabled={action.isPending || !a.session}>Выдать</Button>
          </form>
        </Modal>
      )}
    </>
  );
}
function Sessions() {
  const a = useApp();
  const [edit, setEdit] = useState<Json | null>(null),
    [confirm, setConfirm] = useState<Json | null>(null);
  const action = useAction("Сессия обновлена");
  return (
    <>
      <div className="section-title">
        <h2>Игровые сессии</h2>
        <Button onClick={() => setEdit({})}>
          <Plus size={16} />
          Новая сессия
        </Button>
      </div>
      <div className="grid two">
        {a.sessions.map((s) => (
          <Card key={s.id}>
            <Badge>СЕССИЯ #{s.id}</Badge>
            <h3>{s.name}</h3>
            <p>
              {s.date
                ? new Date(s.date).toLocaleString("ru-RU")
                : "Дата не указана"}
            </p>
            <Status status={s.status} />
            <div className="actions">
              {s.status === "planned" && (
                <Button onClick={() => setConfirm({ ...s, verb: "start" })}>
                  <Play size={15} />
                  Начать
                </Button>
              )}
              {s.status === "active" && (
                <Button onClick={() => setConfirm({ ...s, verb: "finish" })}>
                  <Square size={15} />
                  Завершить
                </Button>
              )}
              {s.status !== "completed" && (
                <Button variant="secondary" onClick={() => setEdit(s)}>
                  Настройки
                </Button>
              )}
            </div>
          </Card>
        ))}
      </div>
      {!a.sessions.length && <Empty title="Спланируйте первую встречу" />}
      {edit && (
        <Modal
          title={edit.id ? "Настройки сессии" : "Новая сессия"}
          onClose={() => setEdit(null)}
        >
          <form
            onSubmit={(e) => {
              e.preventDefault();
              const f = Object.fromEntries(new FormData(e.currentTarget));
              try {
                const settings = JSON.parse(String(f.settings));
                action.mutate(
                  {
                    path: edit.id
                      ? `/sessions/${edit.id}/?campaign=${a.cid}`
                      : `/campaigns/${a.cid}/sessions/`,
                    method: edit.id ? "PATCH" : "POST",
                    body: {
                      name: f.name,
                      date: f.date
                        ? new Date(String(f.date)).toISOString()
                        : null,
                      settings,
                    },
                  },
                  { onSuccess: () => setEdit(null) },
                );
              } catch {
                a.notify("Проверьте JSON настроек");
              }
            }}
          >
            <Field label="Название">
              <input
                name="name"
                required
                defaultValue={edit.name}
                maxLength={120}
              />
            </Field>
            <Field label="Дата">
              <input
                name="date"
                type="datetime-local"
                defaultValue={edit.date?.slice(0, 16)}
              />
            </Field>
            <Field
              label="Настройки сессии (переопределяют кампанию)"
              hint='Например: {"effect_limit":1,"quest_limit":2,"casino_enabled":true}'
            >
              <textarea
                name="settings"
                className="code"
                defaultValue={JSON.stringify(edit.settings || {}, null, 2)}
              />
            </Field>
            <Button disabled={action.isPending}>Сохранить</Button>
          </form>
        </Modal>
      )}
      {confirm && (
        <Confirm
          title={
            confirm.verb === "start" ? "Начать сессию?" : "Завершить сессию?"
          }
          text={
            confirm.verb === "start"
              ? "Игрокам откроются эффекты и квесты."
              : "Неиспользованные эффекты, задания и ожидающие запросы истекут. Открытые карточные раунды необходимо завершить."
          }
          onClose={() => setConfirm(null)}
          busy={action.isPending}
          onConfirm={() =>
            action.mutate(
              {
                path: `/sessions/${confirm.id}/${confirm.verb}/?campaign=${a.cid}`,
                body: {},
              },
              { onSuccess: () => setConfirm(null) },
            )
          }
        />
      )}
    </>
  );
}
function Content({ kind }: { kind: string }) {
  const a = useApp();
  const [page, setPage] = useState(1),
    [search, setSearch] = useState(""),
    [edit, setEdit] = useState<Json | null>(null),
    [arch, setArch] = useState<Json | null>(null),
    [imp, setImp] = useState(false);
  const data = useData<any>(
    `/dm/${kind}/?campaign=${a.cid}&page=${page}&search=${encodeURIComponent(search)}`,
  );
  const action = useAction("Контент сохранён");
  const exportFile = async (fmt: string) => {
    try {
      const r = await request(
        `/dm/${kind}/export/?campaign=${a.cid}&file_format=${fmt}`,
      );
      const url = URL.createObjectURL(
        new Blob(
          [fmt === "csv" ? r.content : JSON.stringify(r.content, null, 2)],
          { type: fmt === "csv" ? "text/csv" : "application/json" },
        ),
      );
      const el = document.createElement("a");
      el.href = url;
      el.download = `sessionlab-${kind}.${fmt}`;
      el.click();
      URL.revokeObjectURL(url);
    } catch (e) {
      a.notify((e as Error).message);
    }
  };
  const initial =
    kind === "effects"
      ? {
          title: "",
          description: "",
          category: "gift",
          rarity: "common",
          weight: 100,
          use_limit: 1,
          requires_approval: true,
          mechanic_type: "narrative",
          parameters: {},
          secret: "",
          homebrew: true,
          active: true,
        }
      : {
          title: "",
          description: "",
          category: "Отыгрыш персонажа",
          difficulty: "normal",
          reward: 10,
          active: true,
        };
  return (
    <>
      <div className="filters">
        <div className="search">
          <Search size={17} />
          <input
            placeholder="Найти в библиотеке…"
            value={search}
            onChange={(e) => {
              setSearch(e.target.value);
              setPage(1);
            }}
          />
        </div>
        <Button variant="secondary" onClick={() => exportFile("json")}>
          <Download size={16} />
          JSON
        </Button>
        <Button variant="secondary" onClick={() => exportFile("csv")}>
          CSV
        </Button>
        <Button variant="secondary" onClick={() => setImp(true)}>
          <Upload size={16} />
          Импорт
        </Button>
        <Button onClick={() => setEdit(initial)}>
          <Plus size={16} />
          Создать
        </Button>
      </div>
      <p className="muted">
        Стандартная библиотека общая и защищена от изменений мастерами. Создайте
        копию для своей кампании или включите нужные карточки в собственный
        набор.
      </p>
      {data.isPending ? (
        <Loading />
      ) : data.error ? (
        <ErrorBox error={data.error} />
      ) : (
        <Card className="table-wrap">
          <table>
            <thead>
              <tr>
                <th>ID / название</th>
                <th>Категория</th>
                <th>{kind === "effects" ? "Вес" : "Награда"}</th>
                <th>Статус</th>
                <th>Действия</th>
              </tr>
            </thead>
            <tbody>
              {data.data?.results?.map((r: Json) => (
                <tr key={r.id}>
                  <td>
                    #{r.id} · {r.title}
                    <small>
                      {r.campaign
                        ? "Контент кампании"
                        : "Стандартная библиотека"}
                    </small>
                  </td>
                  <td>{r.category}</td>
                  <td>{r.weight ?? `${r.reward} ST`}</td>
                  <td>
                    <Badge>
                      {r.archived
                        ? "Архив"
                        : r.active
                          ? "Включено"
                          : "Отключено"}
                    </Badge>
                  </td>
                  <td>
                    <div className="actions">
                      <Button
                        variant="icon ghost"
                        title="Создать копию"
                        aria-label="Создать копию"
                        disabled={action.isPending}
                        onClick={() =>
                          action.mutate({
                            path: `/dm/${kind}/${r.id}/copy/?campaign=${a.cid}`,
                            body: {},
                          })
                        }
                      >
                        <Copy size={16} />
                      </Button>
                      {r.campaign && (
                        <>
                          <Button variant="ghost" onClick={() => setEdit(r)}>
                            Изменить
                          </Button>
                          <Button
                            variant="icon ghost"
                            aria-label="Архивировать"
                            title="Архивировать"
                            onClick={() => setArch(r)}
                          >
                            <Archive size={16} />
                          </Button>
                        </>
                      )}
                    </div>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
          <Pagination
            page={page}
            setPage={setPage}
            count={data.data?.count || 0}
          />
        </Card>
      )}
      {edit && (
        <Modal
          title={edit.id ? "Изменить контент" : "Создать контент"}
          onClose={() => setEdit(null)}
          wide
        >
          <form
            onSubmit={(e) => {
              e.preventDefault();
              try {
                const payload = JSON.parse(
                  String(new FormData(e.currentTarget).get("json")),
                );
                action.mutate(
                  {
                    path: edit.id
                      ? `/dm/${kind}/${edit.id}/?campaign=${a.cid}`
                      : `/dm/${kind}/?campaign=${a.cid}`,
                    method: edit.id ? "PATCH" : "POST",
                    body: payload,
                  },
                  { onSuccess: () => setEdit(null) },
                );
              } catch {
                a.notify("Некорректный JSON");
              }
            }}
          >
            <p>
              Все поля доступны для редактирования. Поле secret видит только
              мастер. Статистику ранее выданных карточек изменения не
              затрагивают.
            </p>
            <Field label="Определение контента">
              <textarea
                name="json"
                className="code editor"
                defaultValue={JSON.stringify(edit, null, 2)}
                required
              />
            </Field>
            <Button disabled={action.isPending}>Сохранить</Button>
          </form>
        </Modal>
      )}
      {arch && (
        <Confirm
          title="Архивировать контент?"
          text={
            arch.title + " останется в истории, но больше не будет выдаваться."
          }
          onClose={() => setArch(null)}
          busy={action.isPending}
          onConfirm={() =>
            action.mutate(
              {
                path: `/dm/${kind}/${arch.id}/?campaign=${a.cid}`,
                method: "DELETE",
              },
              { onSuccess: () => setArch(null) },
            )
          }
        />
      )}{" "}
      {imp && (
        <Modal title="Импорт контента" onClose={() => setImp(false)}>
          <form
            onSubmit={(e) => {
              e.preventDefault();
              const f = new FormData(e.currentTarget);
              try {
                const format = String(f.get("format"));
                const content =
                  format === "json"
                    ? JSON.parse(String(f.get("content")))
                    : f.get("content");
                action.mutate(
                  {
                    path: `/dm/${kind}/import/?campaign=${a.cid}`,
                    body: { format, content },
                  },
                  { onSuccess: () => setImp(false) },
                );
              } catch {
                a.notify("Некорректный JSON");
              }
            }}
          >
            <Field label="Формат">
              <select name="format">
                <option>json</option>
                <option>csv</option>
              </select>
            </Field>
            <Field label="Содержимое экспортированного файла">
              <textarea name="content" className="code editor" required />
            </Field>
            <Button disabled={action.isPending}>Импортировать</Button>
          </form>
        </Modal>
      )}
    </>
  );
}
function CasinoSettings() {
  const a = useApp();
  const data = useData<Json[]>(`/casino/games/?campaign=${a.cid}`);
  const [edit, setEdit] = useState<Json | null>(null);
  const action = useAction(
    "Правила обновлены. Открытые раунды сохраняют прежнюю версию.",
  );
  return (
    <>
      <div className="grid two">
        {data.data?.map((g) => (
          <Card key={g.game}>
            <div className="card-heading">
              <h3>{gameInfo[g.game].name}</h3>
              <Badge>{g.enabled ? "Включено" : "Отключено"}</Badge>
            </div>
            <p>
              Ставки {g.min_bet}–{g.max_bet} ST · Правила v{g.version}
            </p>
            <Button variant="secondary" onClick={() => setEdit(g)}>
              <SlidersHorizontal size={16} />
              Настроить
            </Button>
          </Card>
        ))}
      </div>
      {edit && (
        <Modal
          title={gameInfo[edit.game].name + " · настройки"}
          onClose={() => setEdit(null)}
          wide
        >
          <form
            onSubmit={(e) => {
              e.preventDefault();
              const f = new FormData(e.currentTarget);
              try {
                action.mutate(
                  {
                    path: `/dm/config/${edit.game}/?campaign=${a.cid}`,
                    method: "PATCH",
                    body: {
                      min_bet: Number(f.get("min")),
                      max_bet: Number(f.get("max")),
                      enabled: f.get("enabled") === "on",
                      rules: JSON.parse(String(f.get("rules"))),
                    },
                  },
                  { onSuccess: () => setEdit(null) },
                );
              } catch {
                a.notify("Некорректный JSON правил");
              }
            }}
          >
            <label className="check-field">
              <input
                name="enabled"
                type="checkbox"
                defaultChecked={edit.enabled}
              />
              Игра доступна
            </label>
            <div className="grid two">
              <Field label="Минимальная ставка">
                <input
                  name="min"
                  type="number"
                  min={1}
                  defaultValue={edit.min_bet}
                  required
                />
              </Field>
              <Field label="Максимальная ставка">
                <input
                  name="max"
                  type="number"
                  min={1}
                  max={100000}
                  defaultValue={edit.max_bet}
                  required
                />
              </Field>
            </div>
            <Field label="Правила и выплаты (gross, со ставкой)">
              <textarea
                name="rules"
                className="code editor"
                defaultValue={JSON.stringify(edit.rules, null, 2)}
              />
            </Field>
            <h4>Текущая математика</h4>
            <pre>{JSON.stringify(edit.math, null, 2)}</pre>
            <Button disabled={action.isPending}>Сохранить новую версию</Button>
          </form>
        </Modal>
      )}
      <Journal initial="rounds" />
    </>
  );
}
function Members() {
  const a = useApp();
  const d = useData<Json>(`/dm/overview/?campaign=${a.cid}`);
  const [confirm, setConfirm] = useState<Json | null>(null),
    [wallet, setWallet] = useState<Json | null>(null);
  const action = useAction("Сохранено");
  return (
    <>
      <Card className="invite-card">
        <h3>Пригласить в кампанию</h3>
        <p>
          Передайте код другу. Он введёт его в разделе «Мой профиль →
          Присоединиться».
        </p>
        <code>{a.campaign?.invite_code}</code>
        <Button
          variant="secondary"
          onClick={() => {
            navigator.clipboard
              .writeText(a.campaign?.invite_code || "")
              .then(() => a.notify("Код скопирован"))
              .catch(() => a.notify("Выделите и скопируйте код вручную"));
          }}
        >
          <Copy size={15} />
          Копировать
        </Button>
      </Card>
      <div className="spacer" />
      <Card className="table-wrap">
        <table>
          <thead>
            <tr>
              <th>Участник</th>
              <th>Роль / доступ</th>
              <th>Баланс</th>
              <th />
            </tr>
          </thead>
          <tbody>
            {d.data?.members.map((m: Json) => {
              const w = d.data?.wallets.find(
                (w: Json) => w.user_id === m.user_id,
              );
              return (
                <tr key={m.id}>
                  <td>
                    {m.user__first_name || m.user__email}
                    <small>{m.user__email}</small>
                  </td>
                  <td>
                    <Badge>
                      {m.role} · {m.active ? "Активен" : "Отключён"}
                    </Badge>
                  </td>
                  <td>{w?.balance || 0} ST</td>
                  <td>
                    <div className="actions">
                      {w && (
                        <Button variant="ghost" onClick={() => setWallet(w)}>
                          Жетоны
                        </Button>
                      )}
                      {m.user_id !== a.campaign?.owner && (
                        <>
                          <Button
                            variant="ghost"
                            onClick={() =>
                              setConfirm({
                                ...m,
                                body: {
                                  role: m.role === "dm" ? "player" : "dm",
                                },
                              })
                            }
                          >
                            Сменить роль
                          </Button>
                          <Button
                            variant="ghost"
                            onClick={() =>
                              setConfirm({ ...m, body: { active: !m.active } })
                            }
                          >
                            {m.active ? "Отключить" : "Вернуть доступ"}
                          </Button>
                        </>
                      )}
                    </div>
                  </td>
                </tr>
              );
            })}
          </tbody>
        </table>
      </Card>
      {confirm && (
        <Confirm
          title="Изменить права участника?"
          text="Изменение вступит в силу на сервере сразу после подтверждения."
          busy={action.isPending}
          onClose={() => setConfirm(null)}
          onConfirm={() =>
            action.mutate(
              {
                path: `/dm/actions/member/${confirm.id}/?campaign=${a.cid}`,
                body: confirm.body,
              },
              { onSuccess: () => setConfirm(null) },
            )
          }
        />
      )}{" "}
      {wallet && (
        <Modal title="Корректировка жетонов" onClose={() => setWallet(null)}>
          <p>
            Текущий баланс: {wallet.balance} ST. Отрицательная сумма списывает
            жетоны.
          </p>
          <form
            onSubmit={(e) => {
              e.preventDefault();
              const f = Object.fromEntries(new FormData(e.currentTarget));
              action.mutate(
                {
                  path: `/dm/actions/wallet/${wallet.id}/?campaign=${a.cid}`,
                  body: f,
                },
                { onSuccess: () => setWallet(null) },
              );
            }}
          >
            <Field label="Изменение баланса">
              <input
                name="amount"
                type="number"
                step="0.01"
                min={-1000000}
                max={1000000}
                required
              />
            </Field>
            <Field label="Причина (будет видна в истории)">
              <textarea name="note" required maxLength={1000} />
            </Field>
            <Button disabled={action.isPending}>
              Подтвердить корректировку
            </Button>
          </form>
        </Modal>
      )}
    </>
  );
}
function Settings() {
  const a = useApp();
  const action = useAction("Настройки кампании сохранены");
  return (
    <Card>
      <h2>Правила вашего пространства</h2>
      <form
        onSubmit={(e) => {
          e.preventDefault();
          const f = new FormData(e.currentTarget);
          try {
            action.mutate({
              path: `/campaigns/${a.cid}/`,
              method: "PATCH",
              body: {
                name: f.get("name"),
                description: f.get("description"),
                settings: JSON.parse(String(f.get("settings"))),
              },
            });
          } catch {
            a.notify("Некорректный JSON");
          }
        }}
      >
        <Field label="Название кампании">
          <input
            name="name"
            defaultValue={a.campaign?.name}
            required
            maxLength={120}
          />
        </Field>
        <Field label="Описание">
          <textarea name="description" defaultValue={a.campaign?.description} />
        </Field>
        <Field
          label="Настройки"
          hint="initial_balance применяется только к новым кошелькам. Веса категорий автоматически нормализуются; доступны 5e-2014, 5e-2024 и custom."
        >
          <textarea
            name="settings"
            className="code editor"
            defaultValue={JSON.stringify(a.campaign?.settings, null, 2)}
          />
        </Field>
        <Button disabled={action.isPending}>Сохранить настройки</Button>
      </form>
    </Card>
  );
}
function Pools() {
  const a = useApp();
  const data = useData<Json[]>(`/dm/pools/?campaign=${a.cid}`);
  const action = useAction("Набор сохранён");
  const [edit, setEdit] = useState<Json | null>(null);
  return (
    <>
      <div className="section-title">
        <h2>Коллекции эффектов</h2>
        <Button
          onClick={() =>
            setEdit({ name: "Новый набор", active: true, entries: [] })
          }
        >
          <Plus size={16} />
          Создать набор
        </Button>
      </div>
      <p className="muted">
        Если есть активные наборы, разыгрываются только карточки из них. Веса
        повторяющихся карточек суммируются. Отключённые и архивные карточки
        исключаются.
      </p>
      <div className="grid two">
        {data.data?.map((p) => (
          <Card key={p.id}>
            <Badge>{p.active ? "Активен" : "Отключён"}</Badge>
            <h3>{p.name}</h3>
            <p>{p.entries.length} карточек</p>
            <Button variant="secondary" onClick={() => setEdit(p)}>
              Изменить
            </Button>
          </Card>
        ))}
      </div>
      {edit && (
        <Modal title="Набор эффектов" onClose={() => setEdit(null)}>
          <form
            onSubmit={(e) => {
              e.preventDefault();
              try {
                const body = JSON.parse(
                  String(new FormData(e.currentTarget).get("json")),
                );
                action.mutate(
                  { path: `/dm/pools/?campaign=${a.cid}`, body },
                  { onSuccess: () => setEdit(null) },
                );
              } catch {
                a.notify("Проверьте JSON");
              }
            }}
          >
            <Field
              label="Определение набора"
              hint='entries: [{"effect_id":1,"weight":100}]'
            >
              <textarea
                name="json"
                className="code editor"
                defaultValue={JSON.stringify(edit, null, 2)}
              />
            </Field>
            <Button disabled={action.isPending}>Сохранить</Button>
          </form>
        </Modal>
      )}
    </>
  );
}
function Journal({ initial = "audit" }: { initial?: string }) {
  const a = useApp();
  const [kind, setKind] = useState(initial),
    [page, setPage] = useState(1);
  const data = useData<any>(
    `/dm/history/${kind}/?campaign=${a.cid}&page=${page}`,
  );
  return (
    <>
      <div className="section-title spacer">
        <h2>Журнал кампании</h2>
        <select
          aria-label="Тип журнала"
          value={kind}
          onChange={(e) => {
            setKind(e.target.value);
            setPage(1);
          }}
        >
          <option value="audit">Аудит</option>
          <option value="rounds">Казино-раунды</option>
          <option value="transactions">Операции кошельков</option>
        </select>
      </div>
      {data.isPending ? (
        <Loading />
      ) : data.error ? (
        <ErrorBox error={data.error} />
      ) : (
        <Card className="journal">
          {data.data?.results.map((row: Json) => (
            <details key={row.id}>
              <summary>
                #{row.id} · {row.action || row.game || row.kind} ·{" "}
                {new Date(row.created_at).toLocaleString("ru-RU")}
              </summary>
              <pre>{JSON.stringify(row, null, 2)}</pre>
            </details>
          ))}
          {!data.data?.count && <Empty title="Журнал пока пуст" />}
          <Pagination
            page={page}
            setPage={setPage}
            count={data.data?.count || 0}
          />
        </Card>
      )}
    </>
  );
}
