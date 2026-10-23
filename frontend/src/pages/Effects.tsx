import { useState, useEffect, type CSSProperties } from "react";
import { motion, useReducedMotion } from "motion/react";
import {
  Sparkles,
  ArrowRight,
  Shuffle,
  Search,
  Layers,
  Check,
  Send,
  ArrowLeftRight,
} from "lucide-react";
import { useApp, useData, useAction } from "../app";
import {
  Button,
  Card,
  Header,
  Badge,
  Status,
  Modal,
  Field,
  Empty,
  ErrorBox,
  Loading,
  Pagination,
  categoryLabel,
} from "../components/ui";
import type { Json } from "../api/client";
export default function Effects() {
  const a = useApp();
  const [tab, setTab] = useState("active"),
    [page, setPage] = useState(1),
    [search, setSearch] = useState(""),
    [category, setCategory] = useState("");
  const history = useData<any>(
    `/history/effects/?campaign=${a.cid}&page=${page}${tab === "active" && a.sid && a.charId ? "&session=" + a.sid + "&character=" + a.charId : ""}`,
  );
  const library = useData<any>(
    `/effects/?campaign=${a.cid}&page=${page}&search=${encodeURIComponent(search)}&category=${category}`,
    tab === "library",
  );
  const [revealed, setRevealed] = useState<Json | null>(null),
    [detail, setDetail] = useState<Json | null>(null),
    [using, setUsing] = useState<Json | null>(null),
    [exchange, setExchange] = useState<Json | null>(null);
  const draw = useAction(""),
    use = useAction("Действие сохранено"),
    ex = useAction("Запрос обмена отправлен");
  const exchanges = useData<Json[]>(`/exchanges/?campaign=${a.cid}`);
  const items =
    tab === "library"
      ? library.data?.results || []
      : (history.data?.results || []).filter(
          (r: Json) =>
            tab === "history" ||
            (r.session === a.session?.id && r.character === a.character?.id),
        );
  const closeReveal = () => setRevealed(null);
  return (
    <>
      <Header
        eyebrow="SESSION EFFECTS"
        title="Пусть случится история."
        subtitle="Небольшая неожиданность, которая сделает эту сессию вашей."
        action={<Badge>120 стартовых карточек</Badge>}
      />
      <section className="effect-stage">
        <div className="stage-copy">
          <Badge tone="glass">45% дары · 25% осложнения · 30% парадоксы*</Badge>
          <h2>
            Что сегодня
            <br />
            подготовил случай?
          </h2>
          <p>
            Дар, лёгкое осложнение или интересная сделка.
            <br />
            Откройте карточку перед началом приключения.
          </p>
          <Button
            disabled={!a.session || !a.character || draw.isPending}
            onClick={() =>
              draw.mutate(
                {
                  path: `/sessions/${a.sid}/effects/roll/?campaign=${a.cid}`,
                  body: { character: a.character?.id },
                },
                { onSuccess: (r) => setRevealed(r) },
              )
            }
          >
            <Shuffle size={18} />
            {draw.isPending ? "Сохраняем результат…" : "Открыть мою карточку"}
            <ArrowRight size={17} />
          </Button>
          <small>
            {a.session
              ? `Лимит: ${a.session.settings.effect_limit ?? a.campaign?.settings.effect_limit} на персонажа · ${a.session.name}`
              : "Для розыгрыша нужна активная сессия и персонаж."}
          </small>
          <small>
            *Текущие веса кампании:{" "}
            {Object.values(
              a.session?.settings.category_weights ||
                a.campaign?.settings.category_weights ||
                {},
            ).join(" / ")}
            . Недоступные категории исключаются.
          </small>
        </div>
        <div className="stage-deck" aria-hidden="true">
          <div className="unopened-card one" />
          <div className="unopened-card two" />
          <div className="unopened-card top">
            <span>S / L</span>
            <div className="orbital-symbol">
              <Sparkles size={45} />
            </div>
            <strong>
              THE NEXT
              <br />
              POSSIBILITY.
            </strong>
            <small>SESSIONLAB · EFFECT 001—120</small>
          </div>
        </div>
      </section>
      <div className="tabs">
        {[
          ["active", "Мои эффекты"],
          ["history", "История"],
          ["library", "Библиотека"],
        ].map(([id, label]) => (
          <button
            className={tab === id ? "active" : ""}
            key={id}
            onClick={() => {
              setTab(id);
              setPage(1);
            }}
          >
            {label}
          </button>
        ))}
      </div>
      {tab === "library" && (
        <div className="filters">
          <div className="search">
            <Search size={17} />
            <input
              value={search}
              onChange={(e) => {
                setSearch(e.target.value);
                setPage(1);
              }}
              placeholder="Найти карточку…"
            />
          </div>
          <select
            value={category}
            onChange={(e) => {
              setCategory(e.target.value);
              setPage(1);
            }}
            aria-label="Категория"
          >
            <option value="">Все категории</option>
            {Object.entries(categoryLabel).map(([k, v]) => (
              <option key={k} value={k}>
                {v}
              </option>
            ))}
          </select>
        </div>
      )}
      {(tab === "library" ? library : history).isPending ? (
        <Loading />
      ) : (tab === "library" ? library : history).isError ? (
        <ErrorBox error={(tab === "library" ? library : history).error} />
      ) : items.length ? (
        <div className="grid three">
          {items.map((r: Json) => {
            const s = tab === "library" ? r : r.snapshot;
            return (
              <Card className={`effect-item ${s.category || ""}`} key={r.id}>
                <div className="card-heading">
                  <span
                    className={`feature-icon ${s.category === "complication" ? "rose" : s.category === "paradox" ? "green" : "purple"}`}
                  >
                    <Sparkles size={20} />
                  </span>
                  <Badge>{categoryLabel[s.category] || "Выбор из трёх"}</Badge>
                </div>
                <small className="eyebrow">
                  {s.rarity || "SPECIAL"} ·{" "}
                  {s.homebrew ? "HOMEBREW" : "SESSION EFFECT"}
                </small>
                <h3>{s.title || "Три версии вашей истории"}</h3>
                <p>
                  {s.description ||
                    "Выберите одну из трёх сохранённых карточек."}
                </p>
                {tab !== "library" && (
                  <>
                    <Status status={r.status} />
                    <small>Карточка #{r.id}</small>
                  </>
                )}
                <div className="actions">
                  <Button variant="secondary" onClick={() => setDetail(r)}>
                    {tab === "library" ? "Читать механику" : "Подробнее"}
                  </Button>
                  {tab !== "library" && r.status === "rolled" && (
                    <Button onClick={() => setRevealed(r)}>Выбрать</Button>
                  )}
                  {tab !== "library" &&
                    r.status === "active" &&
                    r.session === a.session?.id && (
                      <Button
                        onClick={() =>
                          [90, 91].includes(s.parameters?.standard_index)
                            ? setExchange(r)
                            : setUsing(r)
                        }
                      >
                        Применить
                      </Button>
                    )}
                </div>
              </Card>
            );
          })}
        </div>
      ) : (
        <Empty
          title={
            tab === "library"
              ? "Ничего не найдено"
              : "Ваша карточка ещё в колоде"
          }
          text="Получите эффект во время активной сессии."
        />
      )}
      <Pagination
        page={page}
        setPage={setPage}
        count={(tab === "library" ? library.data : history.data)?.count || 0}
      />
      {exchanges.data
        ?.filter(
          (e) =>
            e.target__owner_id === a.user.id && e.status === "pending_consent",
        )
        .map((e) => (
          <Card key={e.id} className="consent-card">
            <p>
              Союзник предлагает передачу или обмен карточками (#{e.offered_id}
              {e.requested_id ? ` ↔ #${e.requested_id}` : ""}).
            </p>
            <Button
              disabled={ex.isPending}
              onClick={() =>
                ex.mutate({
                  path: `/exchanges/${e.id}/consent/?campaign=${a.cid}`,
                  body: { accept: true },
                })
              }
            >
              Согласиться
            </Button>
            <Button
              variant="secondary"
              disabled={ex.isPending}
              onClick={() =>
                ex.mutate({
                  path: `/exchanges/${e.id}/consent/?campaign=${a.cid}`,
                  body: { accept: false },
                })
              }
            >
              Отклонить
            </Button>
          </Card>
        ))}
      {revealed && (
        <Reveal
          roll={revealed}
          close={closeReveal}
          choose={(index) =>
            use.mutate(
              {
                path: `/active-effects/${revealed.id}/choose/?campaign=${a.cid}`,
                body: { index },
              },
              { onSuccess: (r) => setRevealed(r) },
            )
          }
          busy={use.isPending}
        />
      )}{" "}
      {detail && (
        <Modal
          title={
            (tab === "library" ? detail : detail.snapshot).title ||
            "Выбор карточки"
          }
          onClose={() => setDetail(null)}
        >
          <EffectDetails
            effect={tab === "library" ? detail : detail.snapshot}
          />
          {detail.status && <Status status={detail.status} />}
        </Modal>
      )}
      {using && (
        <Modal title="Применить эффект" onClose={() => setUsing(null)}>
          <EffectDetails effect={using.snapshot} />
          <form
            onSubmit={(e) => {
              e.preventDefault();
              const note = String(
                new FormData(e.currentTarget).get("note") || "",
              );
              use.mutate(
                {
                  path: `/active-effects/${using.id}/use/?campaign=${a.cid}`,
                  body: { note },
                },
                { onSuccess: () => setUsing(null) },
              );
            }}
          >
            <Field
              label={
                using.snapshot.requires_approval
                  ? "Как вы хотите применить карточку?"
                  : "Комментарий (необязательно)"
              }
            >
              <textarea
                name="note"
                required={using.snapshot.requires_approval}
                maxLength={3000}
                placeholder="Опишите действие и условия…"
              />
            </Field>
            <Button disabled={use.isPending}>
              <Send size={16} />
              {using.snapshot.requires_approval
                ? "Отправить мастеру"
                : "Отметить использование"}
            </Button>
          </form>
        </Modal>
      )}
      {exchange && (
        <Modal title="Передача или обмен" onClose={() => setExchange(null)}>
          <p>
            Получатель должен согласиться. Затем мастер подтвердит применимость
            карточек.
          </p>
          <form
            onSubmit={(e) => {
              e.preventDefault();
              const f = Object.fromEntries(new FormData(e.currentTarget));
              ex.mutate(
                {
                  path: `/exchanges/?campaign=${a.cid}`,
                  body: {
                    source: exchange.id,
                    offered: Number(f.offered),
                    target: Number(f.target),
                    requested: f.requested ? Number(f.requested) : undefined,
                  },
                },
                { onSuccess: () => setExchange(null) },
              );
            }}
          >
            <Field label="ID вашей активной карточки для передачи">
              <input name="offered" type="number" required min={1} />
            </Field>
            <Field label="Получатель">
              <select name="target" required>
                <option value="">Выберите персонажа</option>
                {a.characters
                  .filter((c) => c.active && c.id !== a.character?.id)
                  .map((c) => (
                    <option key={c.id} value={c.id}>
                      {c.name} · #{c.id}
                    </option>
                  ))}
              </select>
            </Field>
            {exchange.snapshot.parameters.standard_index === 91 && (
              <Field label="ID активной карточки союзника">
                <input name="requested" type="number" min={1} required />
              </Field>
            )}
            <Button disabled={ex.isPending}>
              <ArrowLeftRight size={17} />
              Предложить
            </Button>
          </form>
        </Modal>
      )}
    </>
  );
}
function EffectDetails({ effect: s }: { effect: Json }) {
  return (
    <div className="effect-details">
      <Badge>
        {categoryLabel[s.category] || "Выбор"} · {s.rarity}
      </Badge>
      <p>{s.description}</p>
      {s.mechanic && s.mechanic !== s.description && <p>{s.mechanic}</p>}
      <div className="detail-grid">
        <div>
          <small>ПРОДОЛЖИТЕЛЬНОСТЬ</small>
          <strong>{s.duration || "До конца сессии"}</strong>
        </div>
        <div>
          <small>ПРИМЕНЕНИЙ</small>
          <strong>{s.use_limit || 1}</strong>
        </div>
      </div>
      {s.activation && <p>{s.activation}</p>}
      <p className="muted">
        {s.requires_approval
          ? "Изменение мира требует подтверждения мастера."
          : "Применяется вручную за игровым столом, затем отмечается здесь."}{" "}
        {s.homebrew ? "Домашнее правило (Homebrew)." : ""}
      </p>
    </div>
  );
}
function Reveal({
  roll,
  close,
  choose,
  busy,
}: {
  roll: Json;
  close: () => void;
  choose: (i: number) => void;
  busy: boolean;
}) {
  const a = useApp();
  const system = useReducedMotion();
  const [ready, setReady] = useState(a.reduced || !!system);
  useEffect(() => {
    const t = setTimeout(() => setReady(true), 2200);
    return () => clearTimeout(t);
  }, []);
  return (
    <Modal
      title={ready ? "Ваша новая возможность" : "Случай уже сделал выбор…"}
      onClose={close}
      wide
    >
      <div className="reveal-scene">
        {!ready ? (
          <>
            <motion.div
              className="reveal-back"
              animate={{
                rotateY: [0, 180, 360, 720],
                x: [-30, 30, -15, 0],
                rotate: [-6, 6, -3, 0],
              }}
              transition={{ duration: 2.2, ease: [0.1, 0.65, 0.15, 1] }}
            >
              <Sparkles size={55} />
              <strong>SESSIONLAB</strong>
            </motion.div>
            <Button variant="ghost" onClick={() => setReady(true)}>
              Пропустить анимацию
            </Button>
          </>
        ) : roll.status === "rolled" ? (
          <div className="choice-grid">
            {roll.choices.map((s: Json, i: number) => (
              <Card key={i}>
                <Badge>{categoryLabel[s.category]}</Badge>
                <h3>{s.title}</h3>
                <p>{s.description}</p>
                <Button disabled={busy} onClick={() => choose(i)}>
                  Выбрать эту
                </Button>
              </Card>
            ))}
          </div>
        ) : (
          <motion.div
            className="reveal-result"
            style={
              {
                "--reveal-color": roll.snapshot.color || "#695CF5",
                "--reveal-glow":
                  (
                    {
                      common: "9%",
                      uncommon: "13%",
                      rare: "18%",
                      epic: "25%",
                      special: "30%",
                    } as Record<string, string>
                  )[roll.snapshot.rarity] || "12%",
              } as CSSProperties
            }
            initial={{ rotateY: -80, opacity: 0 }}
            animate={{ rotateY: 0, opacity: 1 }}
          >
            <span
              className={`feature-icon ${roll.snapshot.category === "paradox" ? "green" : roll.snapshot.category === "complication" ? "rose" : "purple"}`}
            >
              <Sparkles size={30} />
            </span>
            <small className="eyebrow">
              {categoryLabel[roll.snapshot.category]} · {roll.snapshot.rarity}
            </small>
            <h2>{roll.snapshot.title}</h2>
            <EffectDetails effect={roll.snapshot} />
            <Badge>Сохранено · карточка #{roll.id}</Badge>
            <Button className="full" onClick={close}>
              <Check size={17} />
              Продолжить историю
            </Button>
          </motion.div>
        )}
      </div>
    </Modal>
  );
}
