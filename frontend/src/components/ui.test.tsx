import { describe, it, expect, vi, afterEach } from "vitest";
import { useState } from "react";
import { render, screen, fireEvent, cleanup } from "@testing-library/react";
import { MemoryRouter } from "react-router-dom";
import { Button, Modal, Status, Pagination, ErrorBox } from "./ui";
import GameVisual from "./GameVisual";
import Auth from "../pages/Auth";
import { RollResult } from "../features/room/RollResult";
import { request, clearCsrf } from "../api/client";
afterEach(() => {
  cleanup();
  vi.restoreAllMocks();
  sessionStorage.clear();
  clearCsrf();
});
describe("UI behavior", () => {
  it("blocks pending button", () => {
    const click = vi.fn();
    render(
      <Button disabled onClick={click}>
        Играть
      </Button>,
    );
    fireEvent.click(screen.getByText("Играть"));
    expect(click).not.toHaveBeenCalled();
  });
  it("closes dialog with Escape and exposes accessible name", () => {
    const close = vi.fn();
    render(
      <Modal title="Мой эффект" onClose={close}>
        Результат
      </Modal>,
    );
    expect(
      screen.getByRole("dialog", { name: "Мой эффект" }),
    ).toBeInTheDocument();
    fireEvent.keyDown(document, { key: "Escape" });
    expect(close).toHaveBeenCalledOnce();
  });
  it("keeps focus while editing controlled fields with an inline close callback", () => {
    function TemporaryOpponent() {
      const [name, setName] = useState("");
      const [bonus, setBonus] = useState(0);
      const [count, setCount] = useState(1);
      return <Modal title="Временные противники" onClose={() => {}}>
        <input aria-label="Имя" value={name} onChange={e => setName(e.target.value)} />
        <input aria-label="Бонус инициативы" type="number" value={bonus} onChange={e => setBonus(Number(e.target.value))} />
        <input aria-label="Количество" type="number" value={count} onChange={e => setCount(Number(e.target.value))} />
      </Modal>;
    }
    render(<TemporaryOpponent />);
    for (const [label, value] of [["Имя", "Гоблин"], ["Бонус инициативы", "12"], ["Количество", "15"]]) {
      const input = screen.getByLabelText(label) as HTMLInputElement;
      input.focus();
      for (let index = 1; index <= value.length; index++) {
        fireEvent.change(input, { target: { value: value.slice(0, index) } });
        expect(document.activeElement).toBe(input);
      }
      expect(input.value).toBe(value);
    }
  });
  it("shows the spell DC and both damage outcomes without deciding the target's save", () => {
    render(<RollResult event={{ id: 1, actor_name: "Маг", created_at: new Date().toISOString(), kind: "ability", visibility: "public", payload: { label: "Огненный шар", kind: "spell", slot_level: 4, spell_save_dc: 15, save: { ability: "dex", dc: 15, failed_damage: 33, success_damage: 16 }, damage: { formula: "8d6", terms: [], total: 33 } } }} />);
    expect(screen.getByText(/Спасбросок:/)).toHaveTextContent("СЛ 15");
    expect(screen.getByText(/Если успешен/)).toHaveTextContent("16 урона; если провален — 33 урона");
  });
  it("renders pending quest state", () => {
    render(<Status status="pending_verification" />);
    expect(screen.getByText("На проверке")).toBeVisible();
  });
  it("paginates without out of range actions", () => {
    const fn = vi.fn();
    render(<Pagination count={65} page={1} setPage={fn} />);
    expect(screen.getByText("Назад")).toBeDisabled();
    fireEvent.click(screen.getByText("Далее"));
    expect(fn).toHaveBeenCalledWith(2);
  });
  it("exposes actionable network errors", () => {
    const retry = vi.fn();
    render(<ErrorBox error={new Error("Нет связи")} retry={retry} />);
    fireEvent.click(screen.getByText("Повторить"));
    expect(retry).toHaveBeenCalledOnce();
    expect(screen.getByRole("alert")).toHaveTextContent("Нет связи");
  });
  it("switches auth forms and password requirements", () => {
    render(
      <MemoryRouter>
        <Auth onSuccess={vi.fn()} />
      </MemoryRouter>,
    );
    expect(
      screen.getByRole("heading", { name: "С возвращением" }),
    ).toBeVisible();
    fireEvent.click(screen.getByRole("button", { name: "Создать аккаунт" }));
    expect(screen.getByLabelText("Как к вам обращаться")).toBeRequired();
    expect(
      screen.getByRole("heading", { name: "Начнём историю" }),
    ).toBeVisible();
  });
  it("renders only supplied blackjack dealer data and a hidden back", () => {
    const r = {
      id: 1,
      game: "blackjack",
      result: {
        player: [
          { rank: 10, suit: "♠" },
          { rank: 8, suit: "♥" },
        ],
        dealer: [{ rank: 7, suit: "♣" }],
        hidden: true,
        player_score: 18,
        dealer_score: 7,
      },
    };
    const { container } = render(
      <GameVisual game="blackjack" round={r} animating={false} rules={{}} />,
    );
    expect(container.querySelectorAll(".card-back")).toHaveLength(1);
    expect(container.querySelectorAll(".playing-card")).toHaveLength(4);
  });
  it("wheel labels match European wheel and has a fixed pointer", () => {
    const { container } = render(
      <GameVisual
        game="roulette"
        round={{ id: 1, result: { number: 0, wheel_index: 0 } }}
        animating={false}
        rules={{}}
      />,
    );
    expect(container.querySelectorAll("svg text")).toHaveLength(38);
    expect(container.querySelector(".wheel-pointer")).toBeInTheDocument();
  });
  it("renders exact server dice values", () => {
    const { container } = render(
      <GameVisual
        game="dice"
        round={{ id: 1, result: { dice: [2, 5], total: 7 } }}
        animating={false}
        rules={{}}
      />,
    );
    expect(screen.getByText("Сумма: 7")).toBeVisible();
    expect(container.querySelectorAll(".die")).toHaveLength(2);
  });
});
describe("API transport", () => {
  it("sends CSRF, cookies and same idempotency key after network failure", async () => {
    const fetcher = vi.spyOn(globalThis, "fetch");
    let key = "";
    fetcher.mockResolvedValueOnce(
      new Response(JSON.stringify({ data: { csrfToken: "masked-token" } }), {
        status: 200,
      }),
    );
    fetcher.mockImplementationOnce(async (_input, init) => {
      key = (init!.headers as Record<string, string>)["Idempotency-Key"];
      throw new Error("Network");
    });
    await expect(
      request("/casino/coin/rounds/?campaign=1", "POST", {
        stake: 5,
        choice: "heads",
      }),
    ).rejects.toThrow("Связь прервалась");
    fetcher.mockImplementationOnce(async (_input, init) => {
      expect((init!.headers as Record<string, string>)["Idempotency-Key"]).toBe(
        key,
      );
      expect((init!.headers as Record<string, string>)["X-CSRFToken"]).toBe(
        "masked-token",
      );
      expect(init!.credentials).toBe("include");
      return new Response(JSON.stringify({ data: { id: 12 } }), {
        status: 200,
      });
    });
    expect(
      await request("/casino/coin/rounds/?campaign=1", "POST", {
        stake: 5,
        choice: "heads",
      }),
    ).toEqual({ id: 12 });
  });
  it("surfaces structured errors and clears invalid token", async () => {
    vi.spyOn(globalThis, "fetch")
      .mockResolvedValueOnce(
        new Response(JSON.stringify({ data: { csrfToken: "token" } })),
      )
      .mockResolvedValueOnce(
        new Response(
          JSON.stringify({ error: { detail: "Недостаточно жетонов" } }),
          { status: 400 },
        ),
      );
    await expect(request("/play/", "POST", {})).rejects.toThrow(
      "Недостаточно жетонов",
    );
  });
});
