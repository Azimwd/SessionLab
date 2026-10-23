import { useState } from "react";
import { motion } from "motion/react";
import { Flag, Plus, Coins, Send, CheckCircle2 } from "lucide-react";
import { useApp, useData, useAction } from "../app";
import {
  Header,
  Button,
  Card,
  Badge,
  Status,
  Empty,
  Modal,
  Field,
  Loading,
  ErrorBox,
  Pagination,
} from "../components/ui";
import type { Json } from "../api/client";
export default function Quests() {
  const a = useApp();
  const [tab, setTab] = useState("active"),
    [page, setPage] = useState(1),
    [submit, setSubmit] = useState<Json | null>(null);
  const data = useData<any>(
      `/history/quests/?campaign=${a.cid}&page=${page}${tab === "active" && a.sid && a.charId ? "&session=" + a.sid + "&character=" + a.charId : ""}`,
    ),
    draw = useAction("Получен новый мини-квест"),
    action = useAction("Отправлено мастеру");
  const rows = (data.data?.results || []).filter(
    (q: Json) =>
      tab === "history" ||
      (q.session === a.session?.id &&
        q.character === a.character?.id &&
        !["expired", "cancelled"].includes(q.status)),
  );
  return (
    <>
      <Header
        eyebrow="MINI QUESTS"
        title="Своя маленькая миссия."
        subtitle="Отыгрывайте, исследуйте, помогайте. Даже небольшое действие меняет историю."
        action={
          <Button
            disabled={!a.session || !a.character || draw.isPending}
            onClick={() =>
              draw.mutate({
                path: `/sessions/${a.sid}/quests/roll/?campaign=${a.cid}`,
                body: { character: a.character?.id },
              })
            }
          >
            <Plus size={17} />
            {draw.isPending ? "Выбираем…" : "Получить квест"}
          </Button>
        }
      />
      <div className="quest-banner">
        <div className="feature-icon green">
          <Flag size={26} />
        </div>
        <div>
          <h3>Не побочная история. Часть вашей.</h3>
          <p>
            До {a.campaign?.settings.quest_limit ?? 2} заданий за сессию ·
            Подтверждение мастера · Награды от 5 ST
          </p>
        </div>
        <div className="quest-banner-art">
          +<strong>10</strong>
          <small>SESSION TOKENS</small>
        </div>
      </div>
      <div className="tabs">
        {[
          ["active", "Мои задания"],
          ["history", "История заданий"],
        ].map(([id, label]) => (
          <button
            key={id}
            className={tab === id ? "active" : ""}
            onClick={() => {
              setTab(id);
              setPage(1);
            }}
          >
            {label}
          </button>
        ))}
      </div>
      {data.isPending ? (
        <Loading />
      ) : data.error ? (
        <ErrorBox error={data.error} />
      ) : rows.length ? (
        <div className="grid two">
          {rows.map((q: Json) => (
            <motion.div
              key={q.id}
              initial={{ opacity: 0, y: 15 }}
              animate={{ opacity: 1, y: 0 }}
            >
              <Card
                className={`quest-card ${q.status === "completed" ? "complete" : ""}`}
              >
                <div className="card-heading">
                  <Badge>{q.snapshot.category}</Badge>
                  <motion.span
                    className="quest-reward"
                    animate={
                      q.status === "completed"
                        ? { scale: [1, 1.13, 1] }
                        : { scale: 1 }
                    }
                  >
                    <Coins size={16} />+{q.snapshot.reward} ST
                  </motion.span>
                </div>
                <div className="quest-number">
                  QUEST / {String(q.id).padStart(3, "0")}
                </div>
                <h2>{q.snapshot.title}</h2>
                <p>{q.snapshot.description}</p>
                <div className="card-bottom">
                  <Status status={q.status} />
                  {["active", "rejected"].includes(q.status) &&
                  q.session === a.session?.id ? (
                    <Button variant="secondary" onClick={() => setSubmit(q)}>
                      <CheckCircle2 size={16} />Я выполнил
                    </Button>
                  ) : (
                    <Flag size={18} />
                  )}
                </div>
                {q.decision_note && (
                  <p className="muted">Мастер: {q.decision_note}</p>
                )}
              </Card>
            </motion.div>
          ))}
        </div>
      ) : (
        <Empty
          title="У вашей истории ещё нет задания"
          text={
            a.session
              ? "Получите мини-квест и найдите повод для хорошего отыгрыша."
              : "Дождитесь начала сессии и выберите своего персонажа."
          }
        />
      )}
      <Pagination page={page} setPage={setPage} count={data.data?.count || 0} />
      <div className="how-it-works">
        {[
          ["01", "Получите задание", "Случай выбирает, как проявить себя."],
          ["02", "Создайте момент", "Без спешки и без помех для группы."],
          ["03", "Получите награду", "Мастер подтвердит — жетоны ваши."],
        ].map(([n, t, d]) => (
          <div key={n}>
            <span>{n}</span>
            <div>
              <strong>{t}</strong>
              <p>{d}</p>
            </div>
          </div>
        ))}
      </div>
      {submit && (
        <Modal title="Расскажите, как это было" onClose={() => setSubmit(null)}>
          <Badge>{submit.snapshot.title}</Badge>
          <p>{submit.snapshot.description}</p>
          <form
            onSubmit={(e) => {
              e.preventDefault();
              const evidence = new FormData(e.currentTarget).get("evidence");
              action.mutate(
                {
                  path: `/quest-assignments/${submit.id}/submit/?campaign=${a.cid}`,
                  body: { evidence },
                },
                { onSuccess: () => setSubmit(null) },
              );
            }}
          >
            <Field label="Что произошло за столом?">
              <textarea
                name="evidence"
                required
                maxLength={3000}
                placeholder="Кратко опишите выполнение задания…"
              />
            </Field>
            <Button disabled={action.isPending}>
              <Send size={16} />
              Отправить на подтверждение
            </Button>
          </form>
        </Modal>
      )}
    </>
  );
}
