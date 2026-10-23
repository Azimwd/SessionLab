import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import {
  cleanup,
  fireEvent,
  render,
  screen,
  waitFor,
  within,
} from "@testing-library/react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { MemoryRouter } from "react-router-dom";
import App from "./app";
const settings = {
  edition: "5e-2024",
  effect_limit: 1,
  quest_limit: 2,
  category_weights: { gift: 45, complication: 25, paradox: 30 },
  casino_enabled: true,
  initial_balance: 100,
};
const user = {
  id: 1,
  email: "qa@sessionlab.test",
  first_name: "Мира",
  theme: "light",
  reduced_motion: true,
};
const campaign = {
  id: 1,
  name: "Тестовая кампания",
  owner: 1,
  role: "dm",
  settings,
  invite_code: "local-test-code",
};
let authenticated = true;
let activeRound = false;
let spellAvailable = false;
let mutation: Record<string, unknown> | null = null;
function mockTransport() {
  return vi
    .spyOn(globalThis, "fetch")
    .mockImplementation(async (input, init) => {
      const url = String(input).replace("/api", "");
      let data: any = {};
      if (url === "/auth/csrf/") data = { csrfToken: "token" };
      else if (url === "/auth/me/") {
        if (!authenticated)
          return new Response(
            JSON.stringify({ error: { detail: "Authentication required" } }),
            { status: 403 },
          );
        data = user;
      } else if (url === "/campaigns/")
        data = { count: 1, results: [campaign] };
      else if (url.startsWith('/room/events/')) data={count:0,results:[]};
      else if (url.startsWith('/room/')) data={revision:1,session:{id:1,name:'Первый шаг'},party:[],initiative:{version:0,running:false,round_number:0,current:null,entries:[]}};
      else if (url.startsWith('/characters/1/sheet/')) data={id:1,character:1,version:1,abilities:{str:16,dex:14,con:12,int:10,wis:10,cha:14},skills:{},saves:[],armor_class:14,hp_current:10,hp_max:15,hp_temp:0,speed:30,initiative_bonus:0,spell_ability:'cha',slots:Object.fromEntries(Array.from({length:9},(_,i)=>[String(i+1),{max:2,used:0}])),conditions:[],death_successes:0,death_failures:0,inventory:'',notes:'',background:'',computed:{proficiency:2,modifiers:{str:3,dex:2,con:1,int:0,wis:0,cha:2},skills:{},saves:{str:5,dex:2,con:1,int:0,wis:0,cha:4},initiative:2,spell_attack:4,spell_dc:12}};
      else if (url.startsWith('/characters/1/abilities/')) data=spellAvailable?[{id:9,version:1,kind:'spell',name:'Три искры',description:'Три отдельных луча',ability:'cha',proficient:true,bonus:0,resolution:'attack',dice:'1d6',add_modifier:false,damage_type:'огонь',level:1,upcast_dice:'',roll_count:3,upcast_count:0,save_ability:'dex',casting_time:'1 действие',range:'60 футов',duration:'Мгновенно',concentration:false}]:[];
      else if (url.startsWith('/abilities/9/use/')) data={id:100,kind:'ability',character:1,actor_name:'Мира',created_at:new Date().toISOString(),visibility:'public',payload:{label:'Три искры',character_name:'Мира',kind:'spell',slot_level:1,resolution:'attack',damage_type:'огонь',parts:[1,2,3].map(n=>({roll:{formula:'1d20+4',values:[n],chosen:n,modifier:4,total:n+4,mode:'normal'},damage:{formula:'1d6',terms:[{sign:1,sides:6,values:[n]}],total:n}})),total_damage:6}};
      else if (url.startsWith("/characters/"))
        data = {
          count: 1,
          results: [
            {
              id: 1,
              owner: 1,
              campaign: 1,
              name: "Мира",
              character_class: "Бард",
              level: 3,
              active: true,
            },
          ],
        };
      else if (url.startsWith("/campaigns/1/sessions/"))
        data = [{ id: 1, name: "Первый шаг", status: "active", settings: {} }];
      else if (url.startsWith("/casino/wallet/"))
        data = { id: 1, balance: "100.00" };
      else if (url.startsWith("/casino/games/"))
        data = [
          "roulette",
          "slots",
          "blackjack",
          "dice",
          "coin",
          "higher-lower",
          "lucky-wheel",
        ].map((game) => ({
          game,
          enabled: true,
          min_bet: 1,
          max_bet: 100,
          rules: {},
          math: {},
        }));
      else if (url.startsWith("/casino/rounds/") && !url.includes("/actions/"))
        data = {
          count: activeRound ? 1 : 0,
          results: activeRound
            ? [
                {
                  id: 8,
                  game: "blackjack",
                  status: "active",
                  stake: "5.00",
                  payout: "0.00",
                  rules: {},
                  created_at: new Date().toISOString(),
                  result: {
                    player: [
                      { rank: 10, suit: "♠" },
                      { rank: 5, suit: "♥" },
                    ],
                    dealer: [{ rank: 7, suit: "♣" }],
                    hidden: true,
                    player_score: 15,
                    dealer_score: 7,
                  },
                },
              ]
            : [],
        };
      else if (url.startsWith("/casino/stats/")) data = [];
      else if (
        url.startsWith("/history/") ||
        url.startsWith("/casino/transactions/")
      )
        data = { count: 0, results: [] };
      else if (url.startsWith("/feed/"))
        data = { events: [], achievements: [] };
      else if (url.startsWith("/dm/overview/"))
        data = {
          members: [],
          wallets: [],
          effects: [],
          quests: [],
          approvals: [],
          exchanges: [],
          content_stats: [],
        };
      else if (url.startsWith("/exchanges/")) data = [];
      if (init?.method && init.method !== "GET")
        mutation = {
          url,
          body: JSON.parse(String(init.body || "{}")),
          method: init.method,
        };
      return new Response(JSON.stringify({ data, error: null }), {
        status: 200,
      });
    });
}
function mount(path = "/") {
  const qc = new QueryClient({
    defaultOptions: {
      queries: { retry: false, gcTime: 0 },
      mutations: { retry: false },
    },
  });
  return render(
    <QueryClientProvider client={qc}>
      <MemoryRouter initialEntries={[path]}>
        <App />
      </MemoryRouter>
    </QueryClientProvider>,
  );
}
beforeEach(() => {
  authenticated = true;
  campaign.role = "player";
  activeRound = false;
  spellAvailable = false;
  mutation = null;
  localStorage.clear();
  sessionStorage.clear();
  mockTransport();
});
afterEach(() => {
  cleanup();
  vi.restoreAllMocks();
});
describe("Connected routes", () => {
  it("loads dashboard with server campaign, character and wallet", async () => {
    mount();
    await screen.findByRole("heading", { name: "Привет, Мира 👋" });
    await waitFor(() =>
      expect(
        screen.getByRole("heading", { name: "Привет, Мира 👋" }),
      ).toBeVisible(),
    );
    expect(
      await screen.findByText("Тестовая кампания", {
        selector: ".context-strip strong",
      }),
    ).toBeVisible();
    expect(screen.getAllByText("100").length).toBeGreaterThan(0);
  });
  it("renders auth after session denial", async () => {
    authenticated = false;
    mount();
    expect(
      await screen.findByRole("heading", { name: "С возвращением" }),
    ).toBeVisible();
    expect(
      screen.queryByRole("link", { name: "Панель мастера" }),
    ).not.toBeInTheDocument();
  });
  it("navigates into effects through router", async () => {
    mount();
    await screen.findByRole("heading", { name: "Привет, Мира 👋" });
    fireEvent.click(screen.getByRole("link", { name: "Эффекты 120" }));
    expect(
      await screen.findByRole("heading", { name: "Пусть случится история." }),
    ).toBeVisible();
    expect(
      screen.getByRole("button", { name: "Открыть мою карточку" }),
    ).toBeEnabled();
  });
  it("saves theme and reduced motion using profile API", async () => {
    mount("/profile");
    await screen.findByRole("heading", { name: "Мой профиль" });
    const main = screen.getByRole("main");
    fireEvent.click(
      within(main).getByRole("button", { name: "Переключить тему" }),
    );
    expect(document.documentElement.dataset.theme).toBe("dark");
    fireEvent.click(
      screen.getByRole("button", { name: "Сохранить настройки" }),
    );
    await waitFor(() =>
      expect(mutation).toMatchObject({
        url: "/auth/me/",
        method: "PATCH",
        body: { theme: "dark", reduced_motion: true },
      }),
    );
  });
  it("restores unfinished blackjack from server after a fresh mount", async () => {
    activeRound = true;
    mount("/casino/blackjack");
    expect(
      await screen.findByRole("button", { name: "Взять карту" }),
    ).toBeVisible();
    expect(screen.getByRole("button", { name: "Остановиться" })).toBeEnabled();
    expect(
      screen.getByRole("button", { name: "Удвоить ставку" }),
    ).toBeEnabled();
    expect(
      screen.queryByRole("button", { name: "Начать раунд" }),
    ).not.toBeInTheDocument();
  });
  it("opens a campaign DM panel when role is dm", async () => {
    campaign.role = "dm";
    mount("/dm");
    expect(
      await screen.findByRole("heading", { name: "Входящие запросы" }),
    ).toBeVisible();
    expect(screen.getByRole("button", { name: "Ручная выдача" })).toBeEnabled();
  });
});

it('player navigation excludes campaign management and master sheets', async()=>{
  mount('/room');
  await screen.findByRole('heading',{name:'Игровая комната'});
  expect(screen.queryByRole('link',{name:'Управление кампанией'})).not.toBeInTheDocument();
  expect(screen.getAllByRole('link',{name:'Мой персонаж'})[0]).toBeVisible();
  expect(screen.queryByRole('button',{name:'Следующий ход'})).not.toBeInTheDocument();
});
it('master landing has separate tools and can switch to player view', async()=>{
  campaign.role='dm';mount('/');
  await screen.findByRole('heading',{name:'Стол мастера'});
  expect(screen.getByRole('link',{name:'Листы группы'})).toBeVisible();
  expect(screen.queryByRole('link',{name:'Эффекты 120'})).not.toBeInTheDocument();
  fireEvent.click(screen.getByRole('link',{name:'Перейти в вид игрока'}));
  await screen.findByRole('heading',{name:'Привет, Мира 👋'});
  await waitFor(()=>expect(screen.getByRole('heading',{name:'Привет, Мира 👋'})).toBeVisible());
  expect(screen.getByRole('link',{name:'Эффекты 120'})).toBeVisible();
});
it('player cannot enter master route by URL', async()=>{
  mount('/master');
  await screen.findByRole('heading',{name:'Игровая комната'});
  await waitFor(()=>expect(screen.getByRole('heading',{name:'Игровая комната'})).toBeVisible());
  expect(screen.queryByRole('link',{name:'Листы группы'})).not.toBeInTheDocument();
});
it('sheet edits use real inputs and preserve a draft', async()=>{
  mount('/sheet');
  await screen.findByRole('tab',{name:'Характеристики'});
  fireEvent.click(screen.getByRole('tab',{name:'Характеристики'}));
  fireEvent.change(screen.getByRole('spinbutton',{name:'Сила'}),{target:{value:'18'}});
  expect(screen.getByText('Есть несохранённые изменения. Сохраните их перед броском.')).toBeVisible();
  expect(screen.getAllByRole('button',{name:'Проверка'})[0]).toBeDisabled();
  await waitFor(()=>expect(JSON.parse(sessionStorage.getItem('sl:sheet-draft:1:1:1')!).abilities.str).toBe(18));
});
it('uses a saved spell through the API with one click and renders separate rolls', async()=>{
  spellAvailable=true;
  mount('/sheet');
  fireEvent.click(await screen.findByRole('tab',{name:'Заклинания'}));
  expect(await screen.findByRole('heading',{name:'Три искры'})).toBeVisible();
  fireEvent.click(screen.getByRole('button',{name:'Применить'}));
  await waitFor(()=>expect(mutation).toMatchObject({url:'/abilities/9/use/?campaign=1',method:'POST',body:{slot_level:1,mode:'normal',visibility:'public'}}));
  await waitFor(()=>expect(screen.getByText('Сумма результатов: 6')).toBeVisible());
  expect(screen.getAllByText(/Бросок [123]/)).toHaveLength(3);
});
