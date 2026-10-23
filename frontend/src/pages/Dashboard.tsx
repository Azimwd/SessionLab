import { Link } from "react-router-dom";
import {
  Sparkles,
  ArrowRight,
  ArrowUpRight,
  Flag,
  Coins,
  Layers,
  Activity,
  Clock,
  Disc3,
  CheckCircle2,
} from "lucide-react";
import { useApp, useData, Scoped } from "../app";
import {
  Card,
  Header,
  Badge,
  Count,
  Status,
  categoryLabel,
  Empty,
} from "../components/ui";
export default function Dashboard() {
  const a = useApp();
  const effects = useData<any>(
    `/history/effects/?campaign=${a.cid}${a.sid && a.charId ? "&session=" + a.sid + "&character=" + a.charId : ""}`,
    !!a.cid,
  );
  const quests = useData<any>(
    `/history/quests/?campaign=${a.cid}${a.sid && a.charId ? "&session=" + a.sid + "&character=" + a.charId : ""}`,
    !!a.cid,
  );
  const feed = useData<any>(`/feed/?campaign=${a.cid}`, !!a.cid);
  const rolls = (effects.data?.results || []).filter(
    (r: any) => r.session === a.session?.id && r.character === a.character?.id,
  );
  const active = (quests.data?.results || []).filter(
    (q: any) =>
      q.session === a.session?.id &&
      q.character === a.character?.id &&
      ["active", "pending_verification"].includes(q.status),
  );
  const latest = rolls[0];
  return (
    <>
      <Header
        eyebrow="ВАША ИСТОРИЯ ПРОДОЛЖАЕТСЯ"
        title={`Привет, ${a.user.first_name || "путешественник"} 👋`}
        subtitle="Хорошая сессия начинается с маленькой неожиданности."
        action={
          <Link className="button secondary" to="/profile">
            Мои персонажи <ArrowUpRight size={16} />
          </Link>
        }
      />
      <Scoped>
        <div className="dashboard-top">
          <section className="hero">
            <div className="hero-dots" />
            <div className="hero-text">
              <Badge tone="glass">
                <i className="status-dot" />
                {a.session ? a.session.name : "Следующее приключение"}
              </Badge>
              <h2>
                Добавим истории
                <br />
                <span>элемент случайности.</span>
              </h2>
              <p>
                Одна карточка может изменить ход сессии.
                <br />
                Откройте свою — и посмотрите, куда она приведёт.
              </p>
              <Link to="/effects" className="button white">
                <Sparkles size={17} />
                {latest ? "Посмотреть мой эффект" : "Получить эффект"}
                <ArrowRight size={17} />
              </Link>
              <small>
                {a.session
                  ? "Сессия активна · Результаты сохраняются"
                  : "Мастер скоро начнёт новую сессию"}
              </small>
            </div>
            <div className="hero-deck" aria-hidden="true">
              <div className="mini-card back-one" />
              <div className="mini-card back-two" />
              <div className="mini-card face">
                <div className="card-logo">S / L</div>
                <div className="orbit-art">
                  <div />
                  <Sparkles size={47} strokeWidth={1.1} />
                </div>
                <small>ЧТО ПОДГОТОВИЛ СЛУЧАЙ?</small>
                <strong>
                  Всё начинается
                  <br />с одной карточки.
                </strong>
                <span>
                  SESSION EFFECTS <ArrowUpRight size={16} />
                </span>
              </div>
              <span className="floating-star star-one">✦</span>
              <span className="floating-star star-two">✧</span>
            </div>
          </section>
          <Card className="wallet-card">
            <div className="section-label">
              <span>
                <Coins size={17} />
                МОЙ КОШЕЛЁК
              </span>
              <Badge>ST</Badge>
            </div>
            <div className="balance">
              <Count value={a.wallet.balance} />
              <small>Session Tokens</small>
            </div>
            <p>
              Немного удачи.
              <br />
              Никаких реальных денег.
            </p>
            <div className="wallet-decoration">
              <i />
              <i />
              <i />
            </div>
            <Link className="button secondary full" to="/casino">
              Зайти в казино <ArrowUpRight size={17} />
            </Link>
          </Card>
        </div>
        <div className="context-strip">
          <div>
            <span className="small-symbol">◈</span>
            <div>
              <small>КАМПАНИЯ</small>
              <strong>{a.campaign?.name}</strong>
            </div>
          </div>
          <div>
            <span className="avatar tiny">
              {a.character?.name?.slice(0, 1) || "?"}
            </span>
            <div>
              <small>АКТИВНЫЙ ПЕРСОНАЖ</small>
              {a.character ? (
                <select
                  aria-label="Активный персонаж"
                  value={a.charId}
                  onChange={(e) => a.selectCharacter(e.target.value)}
                >
                  {a.characters
                    .filter((c) => c.owner === a.user.id && c.active)
                    .map((c) => (
                      <option key={c.id} value={c.id}>
                        {c.name} · {c.level} ур.
                      </option>
                    ))}
                </select>
              ) : (
                <Link to="/profile">Создать персонажа →</Link>
              )}
            </div>
          </div>
          <div>
            <Clock size={20} />
            <div>
              <small>ТЕКУЩАЯ СЕССИЯ</small>
              <strong>{a.session?.name || "Ожидает начала"}</strong>
            </div>
          </div>
          <Badge tone={a.session ? "green" : ""}>
            {a.session ? "Всё готово к игре" : "Между приключениями"}
          </Badge>
        </div>
        <div className="section-title">
          <h2>
            Перед началом сессии <span>01 — PREPARE</span>
          </h2>
        </div>
        <div className="grid two">
          <Card className="prep-card">
            <div className="card-heading">
              <span className="feature-icon purple">
                <Layers size={21} />
              </span>
              <Badge>
                {latest ? "Карточка получена" : "Ваш следующий поворот"}
              </Badge>
            </div>
            <h3>{latest?.snapshot?.title || "У истории есть сюрприз"}</h3>
            <p>
              {latest?.snapshot?.description ||
                "Дар, осложнение или парадокс. Случайный эффект добавит вашему персонажу новую грань."}
            </p>
            <div className="card-bottom">
              {latest ? (
                <Status status={latest.status} />
              ) : (
                <span className="muted">120 карточек · 3 категории</span>
              )}
              <Link to="/effects">
                {latest ? "Открыть карточку" : "Открыть эффект"}
                <ArrowRight size={16} />
              </Link>
            </div>
          </Card>
          <Card className="prep-card">
            <div className="card-heading">
              <span className="feature-icon green">
                <Flag size={21} />
              </span>
              <Badge tone="green">
                {active.length} / {a.campaign?.settings.quest_limit ?? 2}{" "}
                активных
              </Badge>
            </div>
            <h3>Маленькая цель. Своя история.</h3>
            <p>
              {active[0]?.snapshot?.description ||
                "Вспомните прошлое, поддержите союзника или узнайте местную легенду. За хорошую историю полагается награда."}
            </p>
            <div className="card-bottom">
              <span className="muted">Награды за отыгрыш</span>
              <Link to="/quests">
                Мои мини-квесты
                <ArrowRight size={16} />
              </Link>
            </div>
          </Card>
        </div>
        <div className="dashboard-bottom">
          <Card>
            <div className="section-title">
              <h2>Последние события</h2>
              <Activity size={18} />
            </div>
            {feed.data?.events?.length ? (
              <div className="event-list">
                {feed.data.events.slice(0, 5).map((e: any) => (
                  <div key={e.id}>
                    <span className="event-dot">
                      <CheckCircle2 size={16} />
                    </span>
                    <div>
                      <strong>{eventLabel(e.action)}</strong>
                      <small>
                        {new Date(e.created_at).toLocaleString("ru-RU")}
                      </small>
                    </div>
                    <Badge>Сохранено</Badge>
                  </div>
                ))}
              </div>
            ) : (
              <Empty
                title="Всё ещё впереди"
                text="Здесь появятся события вашей кампании."
              />
            )}
          </Card>
          <div className="explore-card">
            <Disc3 size={28} />
            <div className="eyebrow">THE LUCKY BREAK</div>
            <h3>
              Между большими
              <br />
              приключениями.
            </h3>
            <p>
              Семь способов испытать удачу.
              <br />И ни одного реального риска.
            </p>
            <Link to="/casino">
              Выбрать игру <ArrowUpRight size={18} />
            </Link>
            <div className="explore-orbit" />
          </div>
        </div>
      </Scoped>
    </>
  );
}
function eventLabel(s: string) {
  if (s.includes("/roll/"))
    return s.includes("effects")
      ? "Открыта карточка эффекта"
      : "Получен новый мини-квест";
  if (s.includes("/rounds/")) return "Сохранён игровой раунд";
  if (s.includes("/submit/")) return "Квест отправлен на проверку";
  if (s.includes("/dm/")) return "Мастер обновил кампанию";
  if (s.includes("characters")) return "Обновлён персонаж";
  if (s.includes("sessions")) return "Обновлена игровая сессия";
  return "Изменения в кампании";
}
