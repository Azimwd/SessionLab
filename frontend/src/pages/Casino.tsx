import { Link } from "react-router-dom";
import {
  ArrowUpRight,
  Coins,
  Disc3,
  Shuffle,
  Spade,
  Dices,
  ArrowUpDown,
  Orbit,
} from "lucide-react";
import { useApp, useData } from "../app";
import {
  Header,
  Card,
  Badge,
  Count,
  Loading,
  ErrorBox,
  Empty,
} from "../components/ui";
export const gameInfo: Record<
  string,
  {
    name: string;
    tag: string;
    description: string;
    icon: any;
    color: string;
    art: string;
  }
> = {
  roulette: {
    name: "Roulette",
    tag: "CLASSIC / 01",
    description: "Один оборот. Тридцать семь возможностей.",
    icon: Disc3,
    color: "purple",
    art: "roulette-art",
  },
  slots: {
    name: "Slot Machine",
    tag: "INSTANT / 02",
    description: "Три барабана. Одна счастливая комбинация.",
    icon: Shuffle,
    color: "green",
    art: "slot-art",
  },
  blackjack: {
    name: "Blackjack",
    tag: "STRATEGY / 03",
    description: "Ближе к 21. На шаг впереди дилера.",
    icon: Spade,
    color: "blue",
    art: "blackjack-art",
  },
  dice: {
    name: "Dice Duel",
    tag: "PROBABILITY / 04",
    description: "Две кости. Двенадцать причин рискнуть.",
    icon: Dices,
    color: "rose",
    art: "dice-art",
  },
  coin: {
    name: "Coin Flip",
    tag: "FIFTY FIFTY / 05",
    description: "Две стороны одной удачи. Какая ваша?",
    icon: Coins,
    color: "amber",
    art: "coin-art",
  },
  "higher-lower": {
    name: "Higher or Lower",
    tag: "PREDICT / 06",
    description: "Следующая карта. Выше или ниже?",
    icon: ArrowUpDown,
    color: "blue",
    art: "higher-art",
  },
  "lucky-wheel": {
    name: "Lucky Wheel",
    tag: "A LITTLE LUCK / 07",
    description: "Ваш следующий поворот может быть удачным.",
    icon: Orbit,
    color: "purple",
    art: "lucky-art",
  },
};
export default function Casino() {
  const a = useApp();
  const unfinished = useData<any>(
    `/casino/rounds/?campaign=${a.cid}&status=active`,
  );
  const games = useData<any[]>(`/casino/games/?campaign=${a.cid}`),
    stats = useData<any[]>(`/casino/stats/?campaign=${a.cid}`);
  return (
    <>
      <Header
        eyebrow="THE LUCKY BREAK"
        title="Немного удачи не помешает."
        subtitle="Семь игр для паузы между приключениями. Только виртуальные жетоны."
        action={<Badge tone="green">Без реальных денег</Badge>}
      />
      <div className="casino-summary">
        <div>
          <span className="feature-icon purple">
            <Coins size={24} />
          </span>
          <div>
            <small>ВАШ БАЛАНС</small>
            <strong>
              <Count value={a.wallet.balance} /> <span>ST</span>
            </strong>
          </div>
        </div>
        <div>
          <small>СЫГРАНО РАУНДОВ</small>
          <strong>{stats.data?.reduce((n, r) => n + r.rounds, 0) || 0}</strong>
        </div>
        <div>
          <small>ЧИСТЫЙ РЕЗУЛЬТАТ</small>
          <strong>
            {stats.data
              ?.reduce((n, r) => n + Number(r.profit), 0)
              .toLocaleString("ru-RU") || 0}{" "}
            <span>ST</span>
          </strong>
        </div>
        <Link to="/profile" className="button secondary">
          История операций <ArrowUpRight size={16} />
        </Link>
      </div>
      {unfinished.data?.results?.map((r: any) => (
        <Card key={r.id} className="resume-round">
          <div>
            <Badge>РАУНД СОХРАНЁН</Badge>
            <h3>
              {gameInfo[r.game].name} · #{r.id}
            </h3>
            <p>Продолжите с того же хода, на котором остановились.</p>
          </div>
          <Link to={`/casino/${r.game}`} className="button">
            Продолжить <ArrowUpRight size={17} />
          </Link>
        </Card>
      ))}
      {!a.campaign?.settings.casino_enabled ? (
        <Empty
          title="В этой кампании казино отключено"
          text="Мастер может включить его в настройках."
        />
      ) : games.isPending ? (
        <Loading />
      ) : games.error ? (
        <ErrorBox error={games.error} />
      ) : (
        <div className="game-grid">
          {games.data?.map((g: any) => {
            const info = gameInfo[g.game];
            const Icon = info.icon;
            return (
              <Link
                key={g.game}
                to={`/casino/${g.game}`}
                className={`game-card ${g.enabled ? "" : "disabled"}`}
                aria-disabled={!g.enabled}
              >
                <div className={`game-art ${info.art}`}>
                  <GameArt game={g.game} />
                  <Badge>
                    {g.enabled ? `${g.min_bet}–${g.max_bet} ST` : "Отключено"}
                  </Badge>
                </div>
                <div className="game-body">
                  <span className="eyebrow">{info.tag}</span>
                  <h2>
                    {info.name}
                    <ArrowUpRight size={20} />
                  </h2>
                  <p>{info.description}</p>
                  <div className="game-meta">
                    <span>
                      <Icon size={14} />
                      Серверный розыгрыш
                    </span>
                    <span>Играть →</span>
                  </div>
                </div>
              </Link>
            );
          })}
        </div>
      )}
      <div className="casino-disclaimer">
        <Coins size={18} />
        <p>
          Session Tokens нельзя купить, вывести или обменять на деньги. Жетоны
          существуют только внутри вашей кампании. Вероятности и выплаты открыты
          в правилах каждой игры.
        </p>
      </div>
    </>
  );
}
function GameArt({ game }: { game: string }) {
  if (game === "roulette" || game === "lucky-wheel")
    return (
      <div
        className={`abstract-wheel ${game === "lucky-wheel" ? "lucky" : ""}`}
      >
        <div />
        <span>✦</span>
      </div>
    );
  if (game === "slots")
    return (
      <div className="abstract-slots">
        <span>◆</span>
        <span>7</span>
        <span>✦</span>
      </div>
    );
  if (game === "blackjack" || game === "higher-lower")
    return (
      <div className="abstract-cards">
        <div>
          8<small>♠</small>
        </div>
        <div>
          {game === "blackjack" ? "A" : "K"}
          <small>♥</small>
        </div>
      </div>
    );
  if (game === "dice")
    return (
      <div className="abstract-dice">
        <div>⚄</div>
        <div>⚂</div>
      </div>
    );
  return (
    <div className="abstract-coin">
      S<span>L</span>
    </div>
  );
}
