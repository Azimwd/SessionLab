import { useEffect, useState, lazy, Suspense } from "react";
import { useParams, Link } from "react-router-dom";
import { useReducedMotion } from "motion/react";
import {
  ArrowLeft,
  Play,
  Coins,
  Plus,
  X,
  SkipForward,
  ArrowUp,
  ArrowDown,
} from "lucide-react";
import { useApp, useData, useAction } from "../app";
import {
  Header,
  Button,
  Card,
  Badge,
  Count,
  Field,
  Loading,
  ErrorBox,
  Empty,
  Status,
  Pagination,
} from "../components/ui";
import { gameInfo } from "./Casino";
import type { Json } from "../api/client";
const GameVisual = lazy(() => import("../components/GameVisual"));
export default function Game() {
  const { game = "" } = useParams();
  return gameInfo[game] ? (
    <GameScreen key={game} game={game} />
  ) : (
    <Empty
      title="Игра не найдена"
      action={<Link to="/casino">Вернуться в казино</Link>}
    />
  );
}
function GameScreen({ game }: { game: string }) {
  const a = useApp();
  const system = useReducedMotion();
  const games = useData<Json[]>(`/casino/games/?campaign=${a.cid}`);
  const [page, setPage] = useState(1);
  const rounds = useData<any>(
    `/casino/rounds/?campaign=${a.cid}&game=${game}&page=${page}`,
  );
  const cfg = games.data?.find((g) => g.game === game);
  const [current, setCurrent] = useState<Json | null>(null),
    [animating, setAnimating] = useState(false),
    [stake, setStake] = useState(5),
    [choice, setChoice] = useState(
      game === "coin" ? "heads" : game === "dice" ? "low" : "red",
    ),
    [value, setValue] = useState(0),
    [bets, setBets] = useState<Json[]>([]),
    [rulesOpen, setRulesOpen] = useState(false);
  const action = useAction("");
  const info = gameInfo[game];
  const round = current || rounds.data?.results?.[0] || null;
  const active = round?.status === "active";
  useEffect(() => {
    if (animating) {
      const t = setTimeout(() => setAnimating(false), 3500);
      return () => clearTimeout(t);
    }
  }, [animating, current?.id, current?.result?.player?.length]);
  const startAnimation = (r: Json) => {
    setCurrent(r);
    setAnimating(!a.reduced && !system);
  };
  const play = () =>
    action.mutate(
      {
        path: `/casino/${game}/rounds/?campaign=${a.cid}`,
        body:
          game === "roulette"
            ? { bets: bets.map((b) => ({ ...b })) }
            : { stake, choice },
      },
      {
        onSuccess: (r) => {
          startAnimation(r);
          setPage(1);
        },
      },
    );
  const take = (verb: string) =>
    action.mutate(
      {
        path: `/casino/rounds/${round.id}/actions/?campaign=${a.cid}`,
        body: { action: verb },
      },
      { onSuccess: startAnimation },
    );
  if (games.isPending || rounds.isPending) return <Loading />;
  if (games.error || rounds.error)
    return <ErrorBox error={games.error || rounds.error} />;
  if (!cfg) return <Empty title="Конфигурация пока не создана" />;
  const disabled = !cfg.enabled || !a.campaign?.settings.casino_enabled;
  return (
    <>
      <Link to="/casino" className="back-link">
        <ArrowLeft size={16} />
        Все игры
      </Link>
      <Header
        eyebrow={info.tag}
        title={info.name}
        subtitle={info.description}
        action={
          <div className="token-pill large">
            <Coins size={19} />
            <Count value={a.wallet.balance} />
            <small>ST</small>
          </div>
        }
      />
      {disabled && (
        <div className="error">
          Новые раунды отключены мастером. Открытый раунд можно завершить.
        </div>
      )}
      <div className="game-layout">
        <Card className={`game-table game-${game}`}>
          <div className="table-top">
            <Badge>
              {active
                ? "Ваш ход"
                : animating
                  ? "Результат сохранён · открываем"
                  : "SERVER-SIDE · SECURE RNG"}
            </Badge>
            <small>SESSIONLAB / PLAY</small>
          </div>
          <div className="visual-stage">
            <Suspense fallback={<Loading />}>
              <GameVisual
                game={game}
                round={round}
                animating={animating}
                rules={cfg.rules}
              />
            </Suspense>
          </div>
          {animating ? (
            <Button
              variant="secondary skip"
              onClick={() => setAnimating(false)}
            >
              <SkipForward size={16} />
              Пропустить анимацию
            </Button>
          ) : round?.status === "completed" ? (
            <div
              className={`round-result ${Number(round.profit) > 0 ? "positive" : ""}`}
              role="status"
            >
              <small>
                {Number(round.profit) > 0
                  ? "УДАЧНЫЙ МОМЕНТ"
                  : Number(round.profit) === 0
                    ? "СТАВКА ВЕРНУЛАСЬ"
                    : "УДАЧА ЕЩЁ ВПЕРЕДИ"}
              </small>
              <strong>
                {Number(round.profit) > 0 ? "+" : ""}
                {Number(round.profit).toLocaleString("ru-RU")} ST
              </strong>
              <span>
                Ставка {round.stake} · Выплата {round.payout} (включая возврат
                ставки)
              </span>
            </div>
          ) : (
            <div className="table-caption">
              {active
                ? "Решение за вами. Состояние раунда сохранено."
                : "Выберите ставку. Всё остальное — дело случая."}
            </div>
          )}
        </Card>
        <Card className="bet-panel">
          <div className="section-title">
            <h3>{active ? "Ваш ход" : "Ваша ставка"}</h3>
            <Badge>ST</Badge>
          </div>
          <Field
            label="Количество жетонов"
            hint={`Лимиты: ${cfg.min_bet}–${cfg.max_bet} ST (общая ставка раунда)`}
          >
            <div className="amount-input">
              <input
                type="number"
                value={stake}
                min={cfg.min_bet}
                max={cfg.max_bet}
                step={1}
                disabled={active || action.isPending || animating}
                onChange={(e) => setStake(Number(e.target.value))}
              />
              <span>ST</span>
            </div>
          </Field>
          <div className="chip-options">
            {[5, 10, 25, 50].map((v) => (
              <button
                disabled={
                  active || animating || v < cfg.min_bet || v > cfg.max_bet
                }
                className={stake === v ? "active" : ""}
                key={v}
                onClick={() => setStake(v)}
              >
                {v}
              </button>
            ))}
          </div>
          {game === "coin" && (
            <div className="choice-buttons">
              {[
                ["heads", "Орёл"],
                ["tails", "Решка"],
              ].map(([id, text]) => (
                <button
                  key={id}
                  disabled={animating}
                  className={choice === id ? "active" : ""}
                  onClick={() => setChoice(id)}
                >
                  {text}
                </button>
              ))}
            </div>
          )}
          {game === "dice" && (
            <Field label="Предсказание">
              <select
                value={choice}
                onChange={(e) => setChoice(e.target.value)}
              >
                <option value="low">Низкая · 2–6</option>
                <option value="seven">Семёрка · 7</option>
                <option value="high">Высокая · 8–12</option>
                {cfg.rules.exact_enabled &&
                  Array.from({ length: 11 }, (_, i) => (
                    <option value={i + 2} key={i}>
                      Ровно {i + 2}
                    </option>
                  ))}
              </select>
            </Field>
          )}
          {game === "roulette" && (
            <>
              <Field label="Вид ставки">
                <select
                  value={choice}
                  disabled={animating}
                  onChange={(e) => setChoice(e.target.value)}
                >
                  {[
                    ["number", "Одно число"],
                    ["red", "Красное"],
                    ["black", "Чёрное"],
                    ["even", "Чётное"],
                    ["odd", "Нечётное"],
                    ["low", "1–18"],
                    ["high", "19–36"],
                    ["dozen", "Дюжина"],
                  ].map(([id, l]) => (
                    <option key={id} value={id}>
                      {l}
                    </option>
                  ))}
                </select>
              </Field>
              {["number", "dozen"].includes(choice) && (
                <Field
                  label={choice === "number" ? "Номер (0–36)" : "Дюжина (1–3)"}
                >
                  <input
                    type="number"
                    value={value}
                    min={choice === "number" ? 0 : 1}
                    max={choice === "number" ? 36 : 3}
                    onChange={(e) => setValue(Number(e.target.value))}
                  />
                </Field>
              )}
              <Button
                variant="secondary full"
                disabled={animating || action.isPending || bets.length >= 40}
                onClick={() =>
                  setBets([...bets, { kind: choice, value, amount: stake }])
                }
              >
                <Plus size={16} />
                Добавить на поле
              </Button>
              <div className="bet-list">
                {bets.map((b, i) => (
                  <div key={i}>
                    <span>
                      {b.kind}{" "}
                      {["number", "dozen"].includes(b.kind) ? b.value : ""}
                    </span>
                    <strong>{b.amount} ST</strong>
                    <button
                      disabled={animating || action.isPending}
                      onClick={() => setBets(bets.filter((_, j) => i !== j))}
                      aria-label="Убрать ставку"
                    >
                      <X size={14} />
                    </button>
                  </div>
                ))}
              </div>
              <div className="roulette-grid">
                {Array.from({ length: 37 }, (_, n) => (
                  <button
                    key={n}
                    style={{
                      color:
                        n === 0
                          ? "#24A88A"
                          : [
                                1, 3, 5, 7, 9, 12, 14, 16, 18, 19, 21, 23, 25,
                                27, 30, 32, 34, 36,
                              ].includes(n)
                            ? "#E16C77"
                            : undefined,
                    }}
                    disabled={animating || action.isPending}
                    className={
                      bets.some((b) => b.kind === "number" && b.value === n)
                        ? "selected"
                        : ""
                    }
                    onClick={() =>
                      setBets([
                        ...bets,
                        { kind: "number", value: n, amount: stake },
                      ])
                    }
                  >
                    {n}
                  </button>
                ))}
              </div>
              <div className="bet-total">
                Всего на поле
                <strong>{bets.reduce((s, b) => s + b.amount, 0)} ST</strong>
              </div>
            </>
          )}
          {active && game === "blackjack" ? (
            <div className="game-actions">
              <Button
                disabled={animating || action.isPending}
                onClick={() => take("hit")}
              >
                Взять карту
              </Button>
              <Button
                variant="secondary"
                disabled={animating || action.isPending}
                onClick={() => take("stand")}
              >
                Остановиться
              </Button>
              <Button
                variant="secondary"
                disabled={
                  animating ||
                  action.isPending ||
                  round.result.player.length !== 2
                }
                onClick={() => take("double")}
              >
                Удвоить ставку
              </Button>
            </div>
          ) : active && game === "higher-lower" ? (
            <div className="game-actions">
              {["higher", "lower"].map((dir) => (
                <Button
                  key={dir}
                  disabled={
                    animating ||
                    action.isPending ||
                    !round.result.odds?.[dir]?.win_probability
                  }
                  onClick={() => take(dir)}
                >
                  {dir === "higher" ? (
                    <ArrowUp size={16} />
                  ) : (
                    <ArrowDown size={16} />
                  )}{" "}
                  {dir === "higher" ? "Выше" : "Ниже"}
                  <small>
                    {(round.result.odds?.[dir]?.win_probability * 100).toFixed(
                      1,
                    )}
                    % · ×{round.result.odds?.[dir]?.gross_multiplier.toFixed(2)}
                  </small>
                </Button>
              ))}
            </div>
          ) : (
            <Button
              className="full"
              disabled={
                disabled ||
                action.isPending ||
                animating ||
                !Number.isInteger(stake) ||
                stake < cfg.min_bet ||
                stake > cfg.max_bet ||
                (game === "roulette" && !bets.length)
              }
              onClick={play}
            >
              <Play size={17} />
              {action.isPending
                ? "Фиксируем результат…"
                : game === "blackjack" || game === "higher-lower"
                  ? "Начать раунд"
                  : "Испытать удачу"}
            </Button>
          )}
          <p className="bet-hint">
            Результат определяет сервер. Повторный запрос с тем же ключом не
            списывает ставку повторно.
          </p>
        </Card>
      </div>
      <div className="tabs">
        <button
          className={!rulesOpen ? "active" : ""}
          onClick={() => setRulesOpen(false)}
        >
          История раундов
        </button>
        <button
          className={rulesOpen ? "active" : ""}
          onClick={() => setRulesOpen(true)}
        >
          Правила и вероятности
        </button>
      </div>
      {rulesOpen ? (
        <Card className="rules-card">
          <h3>Открытая математика</h3>
          <p>
            Все множители — полная выплата со ставкой. Чистая прибыль = выплата
            − суммарная ставка. Начисления округляются вниз до 0,01 ST.
            Отображаемый RTP приведён до округления.
          </p>
          {game === "higher-lower" && (
            <p>
              Туз старше короля (14). Каждый раунд использует новую колоду из 52
              карт. После открытия первой карты остаётся 51. Вероятности и
              множители рассчитываются по её составу. Равенство:{" "}
              {cfg.rules.tie === "push" ? "возврат ставки" : "проигрыш"}.
            </p>
          )}
          {game === "blackjack" && (
            <p>
              Одна колода на раунд. Дилер{" "}
              {cfg.rules.hit_soft_17
                ? "берёт на мягких 17"
                : "останавливается на любых 17"}
              . Blackjack: 1 к {cfg.rules.blackjack_profit}. Удвоение только
              после начальной раздачи. Без split и insurance. RTP зависит от
              стратегии.
            </p>
          )}
          {game === "lucky-wheel" && (
            <p>
              Размеры секторов одинаковы для визуализации. Реальные вероятности
              определяют опубликованные веса секторов.
            </p>
          )}
          <div className="grid two">
            <div>
              <h4>Таблица выплат / конфигурация v{cfg.version}</h4>
              <pre>{JSON.stringify(cfg.rules, null, 2)}</pre>
            </div>
            <div>
              <h4>Вероятности и RTP</h4>
              <pre>{JSON.stringify(cfg.math, null, 2)}</pre>
              <p>
                Математическое ожидание чистого результата на 1 ST = RTP − 1.
                Для нескольких ставок вычисляется взвешенная сумма.
              </p>
            </div>
          </div>
        </Card>
      ) : (
        <Card className="table-wrap">
          <table>
            <thead>
              <tr>
                <th>Раунд / время</th>
                <th>Результат</th>
                <th>Ставка</th>
                <th>Выплата</th>
                <th>Прибыль</th>
              </tr>
            </thead>
            <tbody>
              {rounds.data?.results?.map((r: Json) => (
                <tr key={r.id}>
                  <td>
                    #{r.id}
                    <small>
                      {new Date(r.created_at).toLocaleString("ru-RU")}
                    </small>
                  </td>
                  <td>
                    <Status status={r.status} />
                    {r.result.number !== undefined && ` · ${r.result.number}`}
                    {r.result.total && ` · ${r.result.total}`}
                    {r.result.side &&
                      ` · ${r.result.side === "heads" ? "Орёл" : "Решка"}`}
                    {r.result.symbols?.join(" ")}
                    {r.result.sector?.label}
                  </td>
                  <td>{r.stake}</td>
                  <td>{r.payout}</td>
                  <td className={Number(r.profit) > 0 ? "positive" : ""}>
                    {r.profit ?? "—"}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
          {!rounds.data?.results?.length && (
            <Empty title="Первый раунд ещё впереди" />
          )}
          <Pagination
            page={page}
            setPage={setPage}
            count={rounds.data?.count || 0}
          />
        </Card>
      )}
    </>
  );
}
