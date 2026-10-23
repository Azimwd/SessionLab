import { motion } from "motion/react";
import { Sparkles } from "lucide-react";
import type { Json } from "../api/client";
const order = [
  0, 32, 15, 19, 4, 21, 2, 25, 17, 34, 6, 27, 13, 36, 11, 30, 8, 23, 10, 5, 24,
  16, 33, 1, 20, 14, 31, 9, 22, 18, 29, 7, 28, 12, 35, 3, 26,
];
const red = new Set([
  1, 3, 5, 7, 9, 12, 14, 16, 18, 19, 21, 23, 25, 27, 30, 32, 34, 36,
]);
export default function GameVisual({
  game,
  round,
  animating,
  rules,
}: {
  game: string;
  round: Json | null;
  animating: boolean;
  rules: Json;
}) {
  const r = round?.result || {};
  const duration = animating ? 3.4 : 0;
  if (game === "roulette")
    return (
      <Wheel
        key={round?.id || "idle"}
        labels={order.map(String)}
        colors={order.map((n) =>
          n === 0 ? "#24A88A" : red.has(n) ? "#CB6377" : "#333747",
        )}
        index={r.wheel_index ?? 0}
        duration={duration}
        roulette
      />
    );
  if (game === "lucky-wheel") {
    const s = round?.rules?.sectors || rules.sectors || [];
    return (
      <Wheel
        key={round?.id || "idle"}
        labels={s.map((s: Json) => s.label)}
        colors={s.map((s: Json) => s.color)}
        index={r.index ?? 0}
        duration={duration}
      />
    );
  }
  if (game === "slots") {
    const symbols = (round?.rules?.symbols || rules.symbols || []).map(
      (s: Json) => s.label,
    );
    return (
      <div className="slot-machine">
        <div className="slot-label">SESSION / SLOTS</div>
        <div className="slot-window">
          {[0, 1, 2].map((i) => (
            <div
              className={`reel ${round && Number(round.payout) > 0 && !animating ? "won" : ""}`}
              key={`${round?.id}-${i}`}
            >
              <motion.div
                initial={{ y: 0 }}
                animate={{
                  y:
                    -(
                      symbols.length * 3 +
                      (r.indices?.[i] ?? i % symbols.length)
                    ) * 84,
                }}
                transition={{
                  duration: duration ? duration - 0.6 + i * 0.3 : 0,
                  ease: [0.1, 0.7, 0.1, 1],
                }}
              >
                {Array.from({ length: 4 }, () => symbols)
                  .flat()
                  .map((s: string, j: number) => (
                    <span key={j}>{s}</span>
                  ))}
              </motion.div>
            </div>
          ))}
        </div>
        <div className="slot-bottom">ONE LINE. ALL POSSIBILITIES.</div>
      </div>
    );
  }
  if (game === "dice")
    return (
      <div className="dice-surface">
        <div className="dice-pair">
          {(r.dice || [1, 6]).map((value: number, i: number) => (
            <Die value={value} duration={duration} key={`${round?.id}-${i}`} />
          ))}
        </div>
        <span>
          {round && !animating ? `Сумма: ${r.total}` : "THE NEXT ROLL"}
        </span>
      </div>
    );
  if (game === "coin")
    return (
      <div className="coin-stage">
        <motion.div
          key={round?.id || "idle"}
          className="coin3d"
          initial={{ rotateY: 0, y: 0 }}
          animate={{
            rotateY: r.side === "tails" ? 1260 : 1080,
            y: animating ? [0, -75, 0] : 0,
          }}
          transition={{ duration, ease: [0.1, 0.7, 0.2, 1] }}
        >
          <div className="coin-face front">
            <span>SL</span>
            <small>ОРЁЛ</small>
          </div>
          <div className="coin-face back">
            <Sparkles size={44} />
            <small>РЕШКА</small>
          </div>
        </motion.div>
        <div className="coin-shadow" />
        <span>
          {round && !animating
            ? r.side === "heads"
              ? "Орёл"
              : "Решка"
            : "TWO SIDES. ONE CHANCE."}
        </span>
      </div>
    );
  if (game === "blackjack")
    return (
      <div className="blackjack-table">
        <div className="table-hand">
          <small>
            ДИЛЕР {round ? `· ${r.dealer_score}` : ""}
            {r.hidden ? " + ?" : ""}
          </small>
          <div className="playing-hand">
            {(r.dealer || [null, null]).map((c: Json | null, i: number) => (
              <PlayingCard
                card={c}
                key={`${i}-${c?.rank}`}
                index={i}
                duration={animating ? 0.4 : 0}
              />
            ))}
            {r.hidden && <PlayingCard card={null} index={1} duration={0} />}
          </div>
        </div>
        <div className="table-wordmark">
          SESSIONLAB <span>BLACKJACK PAYS 3:2 BY DEFAULT</span>
        </div>
        <div className="table-hand">
          <div className="playing-hand">
            {(r.player || [null, null]).map((c: Json | null, i: number) => (
              <PlayingCard
                card={c}
                key={`${i}-${c?.rank}`}
                index={i}
                duration={animating ? 0.4 : 0}
              />
            ))}
          </div>
          <small>ВАША РУКА {round ? `· ${r.player_score}` : ""}</small>
        </div>
      </div>
    );
  return (
    <div className="higher-table">
      <div>
        <small>ОТКРЫТАЯ КАРТА</small>
        <PlayingCard card={r.current || null} index={0} duration={0} />
      </div>
      <span className="higher-divider">→</span>
      <div>
        <small>СЛЕДУЮЩАЯ</small>
        <PlayingCard
          key={r.next?.rank + "-" + round?.id}
          card={r.next || null}
          index={0}
          duration={animating ? 0.8 : 0}
        />
      </div>
    </div>
  );
}
function Wheel({
  labels,
  colors,
  index,
  duration,
  roulette = false,
}: {
  labels: string[];
  colors: string[];
  index: number;
  duration: number;
  roulette?: boolean;
}) {
  const n = labels.length || 8;
  const step = 360 / n;
  const point = (angle: number, r: number) => [
    180 + Math.cos((angle * Math.PI) / 180) * r,
    180 + Math.sin((angle * Math.PI) / 180) * r,
  ];
  return (
    <div className="wheel-scene">
      <div className="wheel-pointer" />
      <motion.svg
        viewBox="0 0 360 360"
        className="spin-wheel"
        initial={{ rotate: 0 }}
        animate={{ rotate: 1800 - index * step }}
        transition={{ duration, ease: [0.1, 0.7, 0.08, 1] }}
      >
        <circle cx="180" cy="180" r="177" fill="#282E3B" />
        {labels.map((l, i) => {
          const a = i * step - 90 - step / 2,
            b = a + step;
          const p = point(a, 167),
            q = point(b, 167),
            t = point(i * step - 90, roulette ? 147 : 126);
          return (
            <g key={i}>
              <path
                d={`M180 180 L${p[0]} ${p[1]} A167 167 0 ${step > 180 ? 1 : 0} 1 ${q[0]} ${q[1]} Z`}
                fill={colors[i]}
                stroke="#FFFFFF28"
                strokeWidth="1"
              />
              <text
                x={t[0]}
                y={t[1]}
                fill="white"
                fontSize={roulette ? "10" : "14"}
                fontWeight="700"
                textAnchor="middle"
                dominantBaseline="central"
                transform={`rotate(${i * step},${t[0]},${t[1]})`}
              >
                {l}
              </text>
            </g>
          );
        })}
        <circle
          cx="180"
          cy="180"
          r={roulette ? 116 : 60}
          fill="#242939"
          stroke="#ffffff25"
          strokeWidth="2"
        />
        <circle cx="180" cy="180" r="32" fill="#F8F8FC" />
        <text
          x="180"
          y="186"
          textAnchor="middle"
          fontSize="18"
          fontWeight="800"
          fill="#695CF5"
        >
          SL
        </text>
      </motion.svg>
      {roulette && (
        <motion.div
          className="ball-orbit"
          initial={{ rotate: 0 }}
          animate={{ rotate: -1800 }}
          transition={{ duration, ease: [0.1, 0.7, 0.1, 1] }}
        >
          <i />
        </motion.div>
      )}
    </div>
  );
}
export function PlayingCard({
  card,
  index = 0,
  duration = 0.4,
}: {
  card: Json | null;
  index?: number;
  duration?: number;
}) {
  const label = card
    ? ({ 11: "J", 12: "Q", 13: "K", 14: "A" } as Record<number, string>)[
        card.rank
      ] || card.rank
    : "";
  return (
    <motion.div
      className={`playing-card ${card ? (["♥", "♦"].includes(card.suit) ? "red" : "black") : "card-back"}`}
      initial={{
        rotateY: duration ? 90 : 0,
        y: duration ? -20 : 0,
        opacity: duration ? 0 : 1,
      }}
      animate={{ rotateY: 0, y: 0, opacity: 1 }}
      transition={{ duration, delay: duration ? index * 0.13 : 0 }}
    >
      {card ? (
        <>
          <span>
            {label}
            <small>{card.suit}</small>
          </span>
          <strong>{card.suit}</strong>
          <span className="corner-bottom">
            {label}
            <small>{card.suit}</small>
          </span>
        </>
      ) : (
        <div className="card-back-mark">S / L</div>
      )}
    </motion.div>
  );
}
function Die({ value, duration }: { value: number; duration: number }) {
  const turns: Record<number, [number, number]> = {
    1: [0, 0],
    2: [0, -90],
    3: [-90, 0],
    4: [90, 0],
    5: [0, 90],
    6: [0, 180],
  };
  const [x, y] = turns[value];
  return (
    <div className="die-perspective">
      <motion.div
        className="die"
        initial={{ rotateX: 0, rotateY: 0, y: 0 }}
        animate={{
          rotateX: 720 + x,
          rotateY: 1080 + y,
          y: duration ? [0, -55, 8, -15, 0] : 0,
        }}
        transition={{ duration, ease: [0.12, 0.65, 0.15, 1] }}
      >
        {[1, 2, 3, 4, 5, 6].map((n) => (
          <div className={`die-face face-${n}`} key={n}>
            {Array.from({ length: 9 }, (_, i) => (
              <i key={i} className={pip(n, i) ? "pip" : "no-pip"} />
            ))}
          </div>
        ))}
      </motion.div>
    </div>
  );
}
function pip(n: number, i: number) {
  const positions: Record<number, number[]> = {
    1: [4],
    2: [0, 8],
    3: [0, 4, 8],
    4: [0, 2, 6, 8],
    5: [0, 2, 4, 6, 8],
    6: [0, 2, 3, 5, 6, 8],
  };
  return positions[n].includes(i);
}
