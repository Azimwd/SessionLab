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
let multipleSpells = false;
let activeSession = true;
let mutation: Record<string, unknown> | null = null;
let sheetState: any = null;
let roomHasActors = false;
let roomTableVisible = true;
let roomCharacterVisible = true;
let roomEnemyVisible = false;
let roomUnfiledVisible = false;
const mockFolders = [{id:1,name:'Игроки',is_system:true},{id:2,name:'Противники',is_system:false},{id:3,name:'NPC',is_system:false}];
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
      else if (url.startsWith('/room/table-visibility/')) {
        const payload=JSON.parse(String(init?.body||'{}'));
        if(payload.scope==='table')roomTableVisible=payload.visible;
        if(payload.scope==='character')roomCharacterVisible=payload.visible;
        if(payload.scope==='folder'&&payload.folder===2)roomEnemyVisible=payload.visible;
        if(payload.scope==='folder'&&payload.folder==='unfiled')roomUnfiledVisible=payload.visible;
        data={scope:payload.scope,visible:payload.visible};
      }
      else if (url.startsWith('/room/')) {
        const master=!url.includes('view=player');
        const person={id:1,name:'Мира',owner:1,owner_name:'Мира',kind:'player',folder:1,table_visible:roomCharacterVisible,character_class:'Бард',level:3,hp_current:10,hp_max:15,hp_temp:0,armor_class:14,conditions:[],speed:30,initiative:2,abilities:{str:16,dex:14}};
        const npc={...person,id:2,name:'Гоблин',kind:'npc',folder:2,owner_name:'Мастер',abilities:{str:8,dex:14}};
        const folders=mockFolders.map(f=>({...f,visible_to_players:f.id===1?true:f.id===2?roomEnemyVisible:false}));
        data={revision:1,session:{id:1,name:'Первый шаг'},party:roomHasActors&&(master||roomTableVisible&&roomCharacterVisible)?[person]:[],npcs:roomHasActors&&(master||roomTableVisible&&roomEnemyVisible)?[npc]:[],folders:master?[...folders,{id:'unfiled',name:'Без папки',is_system:false,visible_to_players:roomUnfiledVisible}]:roomTableVisible?folders.filter(f=>f.visible_to_players):[],own_characters:roomHasActors?[{id:1,name:'Мира',owner:1}]:[],table_visible_to_players:roomTableVisible,initiative:{version:0,running:false,round_number:0,current:null,entries:[]}};
      }
      else if (url.startsWith('/character-folders/')) data={count:3,results:mockFolders.map(f=>({...f,owner:1}))};
      else if (url.startsWith('/characters/1/sheet/')) {
        sheetState??={id:1,character:1,version:1,abilities:{str:16,dex:14,con:12,int:10,wis:10,cha:14},skills:{},saves:[],armor_class:14,hp_current:10,hp_max:15,hp_temp:0,speed:30,initiative_bonus:0,spell_ability:'cha',slots:Object.fromEntries(Array.from({length:9},(_,i)=>[String(i+1),{max:2,used:0}])),conditions:[],death_successes:0,death_failures:0,inventory:'',notes:'',background:'',computed:{proficiency:2,modifiers:{str:3,dex:2,con:1,int:0,wis:0,cha:2},skills:{},saves:{str:5,dex:2,con:1,int:0,wis:0,cha:4},initiative:2,spell_attack:4,spell_dc:12}};
        if(init?.method==='PATCH'){const patch=JSON.parse(String(init.body));sheetState={...sheetState,...patch,version:sheetState.version+1};}
        data=sheetState;
      }
      else if (url.startsWith('/characters/1/abilities/')) data=spellAvailable?[{id:9,version:1,kind:'spell',name:'Три искры',description:'Три отдельных луча',ability:'cha',proficient:true,bonus:0,resolution:'attack',dice:'1d6',add_modifier:false,damage_type:'огонь',level:1,upcast_dice:'',roll_count:3,upcast_count:0,save_ability:'dex',casting_time:'1 действие',range:'60 футов',duration:'Мгновенно',concentration:false},...(multipleSpells?Array.from({length:9},(_,i)=>({id:i+20,version:1,kind:'spell',name:i===5?'Огненный шар':`Заклинание ${i}`,description:'Эффект по описанию',level:i===5?3:i%4,upcast_allowed:true,dice:'2d6',damage_type:'огонь',casting_time:'1 действие',range:'60 футов',duration:'Мгновенно'})):[])]:[];
      else if (url.startsWith('/spells/catalog/5/')) data={id:5,name_ru:'Исполнение желаний',level:9,rules:{school:'conjuration',classes:['Wizard'],verified:false,casting_time:'Действие',range:'На себя',duration:'Мгновенная',components:'В',description:'Желание меняет реальность.\n\nМожно повторить заклинание.',source_en:'Wish is the mightiest spell.'}};
      else if (url.startsWith('/spells/catalog/')) data={count:1,results:[{id:5,name_ru:'Огненный шар',name_en:'Fireball',level:3,rules:{school:'evocation',classes:['Wizard'],verified:true,casting_time:'1 действие',range:'150 футов',duration:'Мгновенно',description:'Взрыв огня'}}]};
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
              folder: 1,
              active: true,
            },
          ],
        };
      else if (url.startsWith("/campaigns/1/sessions/"))
        data = activeSession ? [{ id: 1, name: "Первый шаг", status: "active", settings: {} }] : [];
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
  multipleSpells = false;
  activeSession = true;
  mutation = null;
  sheetState = null;
  roomHasActors = false;
  roomTableVisible = true;
  roomCharacterVisible = true;
  roomEnemyVisible = false;
  roomUnfiledVisible = false;
  localStorage.clear();
  sessionStorage.clear();
  mockTransport();
});
afterEach(() => {
  cleanup();
  vi.restoreAllMocks();
});
describe("Connected routes", () => {
  it("shows the complete Russian rules for a spell without automatic calculation", async () => {
    mount('/spells/5');
    await waitFor(()=>expect(screen.getByRole('heading', {name:'Исполнение желаний'})).toBeVisible());
    expect(screen.getByText(/Желание меняет реальность/)).toBeVisible();
    expect(screen.getByText(/Особые эффекты определяются по описанию с мастером/)).toBeVisible();
    expect(screen.getByText('Действие')).toBeVisible();
    expect(screen.getByText('Оригинальный текст SRD 5.1 на английском')).toBeVisible();
  });
  it("loads campaign lobby and lets the player enter the room", async () => {
    mount();
    await screen.findByRole("heading", { name: "Кампании" });
    await waitFor(()=>expect(screen.getByRole('heading',{name:'Тестовая кампания'})).toBeVisible());
    fireEvent.click(screen.getByRole('button',{name:/Войти в игру/}));
    await screen.findByRole('heading',{name:'Игровая комната'});
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
    await screen.findByRole("heading", { name: "Кампании" });
    fireEvent.click(screen.getByRole("link", { name: "Эффекты" }));
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
  await waitFor(()=>expect(screen.getAllByRole('link',{name:'Мой персонаж'})[0]).toBeVisible());
  expect(screen.queryByRole('button',{name:'Следующий ход'})).not.toBeInTheDocument();
});
it('master landing has separate tools and can switch to player view', async()=>{
  campaign.role='dm';mount('/');
  await screen.findByRole('heading',{name:'Кампании'});
  fireEvent.click(screen.getByRole('button',{name:'Управлять'}));
  await screen.findByRole('heading',{name:'Входящие запросы'});
  expect(screen.getByRole('link',{name:'Листы группы'})).toBeVisible();
  const sidebar = screen.getByRole('complementary');
  expect(within(sidebar).queryByRole('link',{name:'Мой профиль'})).not.toBeInTheDocument();
  expect(within(sidebar).queryByText('Панель мастера')).not.toBeInTheDocument();
  expect(within(sidebar).queryByText(/Хорошей истории/)).not.toBeInTheDocument();
  fireEvent.click(screen.getByRole('link',{name:'Посмотреть как игрок'}));
  await screen.findByRole('heading',{name:'Игровая комната'});
  expect(screen.getByRole('link',{name:'Эффекты'})).toBeVisible();
});
it('searches the spell catalog on the server with combined filters',async()=>{
  mount('/spells');
  await screen.findByRole('heading',{name:'Справочник заклинаний'});
  fireEvent.change(screen.getByPlaceholderText(/Например:/),{target:{value:'огненный'}});
  fireEvent.change(screen.getByLabelText('Круг'),{target:{value:'3'}});
  fireEvent.change(screen.getByLabelText('Класс'),{target:{value:'Wizard'}});
  await waitFor(()=>expect(vi.mocked(globalThis.fetch).mock.calls.some(([path])=>String(path).includes('q=%D0%BE%D0%B3%D0%BD%D0%B5%D0%BD%D0%BD%D1%8B%D0%B9')&&String(path).includes('class=Wizard')&&String(path).includes('level=3'))).toBe(true));
});
it('player cannot enter master route by URL', async()=>{
  mount('/master');
  await screen.findByRole('heading',{name:'Игровая комната'});
  await waitFor(()=>expect(screen.getByRole('heading',{name:'Игровая комната'})).toBeVisible());
  expect(screen.queryByRole('link',{name:'Листы группы'})).not.toBeInTheDocument();
});
it('lets a master filter table cards by folder and hide a character without taking away their dice', async()=>{
  campaign.role='dm';roomHasActors=true;
  mount('/master');
  fireEvent.change(await screen.findByRole('combobox',{name:'Папка за столом'}),{target:{value:'2'}});
  expect(screen.getByRole('heading',{name:'Гоблин'})).toBeInTheDocument();
  expect(within(screen.getByRole('heading',{name:'Гоблин'}).closest('.party-card') as HTMLElement).getByText(/Инициатива/)).toBeInTheDocument();
  fireEvent.change(screen.getByRole('combobox',{name:'Папка за столом'}),{target:{value:'1'}});
  fireEvent.click(screen.getByRole('button',{name:'Скрыть Мира игрокам'}));
  await waitFor(()=>expect(mutation).toMatchObject({url:'/room/table-visibility/?campaign=1',body:{scope:'character',character:1,visible:false}}));
  fireEvent.click(screen.getByRole('link',{name:'Посмотреть как игрок'}));
  await screen.findByRole('heading',{name:'Игровая комната'});
  await waitFor(()=>expect(screen.queryByRole('heading',{name:'Мира'})).not.toBeInTheDocument());
  expect(screen.getByRole('combobox',{name:'Папка за столом'})).toHaveValue('1');
  expect(screen.getByRole('option',{name:'Мира'})).toBeInTheDocument();
});
it('lets a master hide the entire table from player view', async()=>{
  campaign.role='dm';roomHasActors=true;
  mount('/master');
  fireEvent.click(await screen.findByRole('button',{name:'Скрыть весь стол'}));
  await waitFor(()=>expect(mutation).toMatchObject({url:'/room/table-visibility/?campaign=1',body:{scope:'table',visible:false}}));
  fireEvent.click(screen.getByRole('link',{name:'Посмотреть как игрок'}));
  expect(await screen.findByText('Мастер скрыл отображение за столом')).toBeInTheDocument();
  expect(screen.queryByRole('heading',{name:'Мира'})).not.toBeInTheDocument();
});
it('lets a master publish a folder, then players can select it without seeing hidden folders', async()=>{
  campaign.role='dm';roomHasActors=true;
  mount('/master');
  const select=await screen.findByRole('combobox',{name:'Папка за столом'});
  fireEvent.change(select,{target:{value:'2'}});
  fireEvent.click(screen.getByRole('button',{name:'Показать папку игрокам'}));
  await waitFor(()=>expect(mutation).toMatchObject({url:'/room/table-visibility/?campaign=1',body:{scope:'folder',folder:2,visible:true}}));
  fireEvent.click(screen.getByRole('link',{name:'Посмотреть как игрок'}));
  const playerSelect=await screen.findByRole('combobox',{name:'Папка за столом'});
  expect(within(playerSelect).getAllByRole('option').map(o=>o.textContent)).toEqual(['Игроки','Противники']);
  fireEvent.change(playerSelect,{target:{value:'2'}});
  expect(await screen.findByRole('heading',{name:'Гоблин'})).toBeInTheDocument();
  expect(screen.queryByRole('button',{name:'Скрыть Гоблин игрокам'})).not.toBeInTheDocument();
});
it('sheet edits use real inputs and preserve a draft', async()=>{
  mount('/sheet');
  await screen.findByRole('tab',{name:'Характеристики'});
  fireEvent.click(screen.getByRole('tab',{name:'Характеристики'}));
  fireEvent.change(screen.getByRole('spinbutton',{name:'Сила'}),{target:{value:'18'}});
  expect(screen.getByText('Сохраним изменения автоматически…')).toBeVisible();
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
it('keeps hit controls visible and casts a spell from the classic overview', async()=>{
  spellAvailable=true;
  mount('/sheet');
  await screen.findByRole('tab',{name:'Обзор'});
  expect(screen.getByRole('button',{name:'Урон'})).toBeVisible();
  expect(screen.getByRole('button',{name:'Лечение'})).toBeVisible();
  expect(screen.getByRole('button',{name:'Временные хиты'})).toBeVisible();
  expect(screen.getByRole('tab',{name:'Атаки'})).toBeVisible();
  expect(screen.getByRole('tab',{name:'Заклинания'})).toBeVisible();
  fireEvent.click(await screen.findByRole('button',{name:'Применить Три искры'}));
  await waitFor(()=>expect(mutation).toMatchObject({url:'/abilities/9/use/?campaign=1',body:{slot_level:1}}));
  fireEvent.click(screen.getByRole('button',{name:'Продолжить'}));
  fireEvent.click(screen.getByRole('tab',{name:'Заклинания'}));
  expect(screen.getByRole('button',{name:'Урон'})).toBeVisible();
});
it('edits scores, saves, skill expertise and combat resources directly on the overview', async()=>{
  mount('/sheet');
  const rail=await screen.findByLabelText('Характеристики персонажа');
  expect(within(rail).getByText('Навыки').closest('details')).toHaveAttribute('open');
  const skill=within(rail).getByRole('button',{name:'Владение навыком: Внимательность — нет'});
  fireEvent.click(skill);
  fireEvent.click(within(rail).getByRole('button',{name:'Владение навыком: Внимательность — владение'}));
  expect(within(rail).getByRole('button',{name:'Владение навыком: Внимательность — экспертиза'})).toBeVisible();
  fireEvent.click(within(rail).getByRole('checkbox',{name:'Владение спасброском: Сила'}));
  fireEvent.change(within(rail).getByRole('spinbutton',{name:'Значение: Сила'}),{target:{value:'18'}});
  fireEvent.change(screen.getByRole('spinbutton',{name:'Класс доспеха на обзоре'}),{target:{value:'16'}});
  expect(within(rail).getByRole('button',{name:'Бросить проверку: Сила'})).toBeDisabled();
  await waitFor(()=>expect(mutation).toMatchObject({url:'/characters/1/sheet/?campaign=1',method:'PATCH',body:{abilities:{str:18},saves:['str'],skills:{perception:2},armor_class:16}}));
  await waitFor(()=>expect(within(rail).getByRole('button',{name:'Бросить проверку: Сила'})).toBeEnabled());
});
it('edits conditions and notes on the overview and saves them automatically', async()=>{
  mount('/sheet');
  expect(await screen.findByRole('link',{name:'Комната'})).toHaveAttribute('href','/room');
  await screen.findByRole('spinbutton',{name:'Класс доспеха на обзоре'});
  expect(screen.queryByText('Можно изменить здесь')).not.toBeInTheDocument();
  const conditionsSection=screen.getByText('Состояния').closest('details')!;
  fireEvent.click(within(conditionsSection).getByText('Состояния'));
  fireEvent.click(within(conditionsSection).getByRole('checkbox',{name:'Ослеплён'}));
  fireEvent.change(screen.getByRole('textbox',{name:'Инвентарь на обзоре'}),{target:{value:'Верёвка'}});
  fireEvent.change(screen.getByRole('textbox',{name:'Заметки на обзоре'}),{target:{value:'Найти проводника'}});
  expect(screen.queryByRole('button',{name:'Сохранить'})).not.toBeInTheDocument();
  await waitFor(()=>expect(mutation).toMatchObject({url:'/characters/1/sheet/?campaign=1',body:{conditions:['Ослеплён'],inventory:'Верёвка',notes:'Найти проводника'}}));
  await waitFor(()=>expect(within(conditionsSection).getAllByText('Ослеплён').length).toBeGreaterThan(0));
});
it('keeps newer edits made while an automatic save is in flight', async()=>{
  const original=vi.mocked(globalThis.fetch).getMockImplementation()!;
  let release:(()=>void)|undefined;
  vi.mocked(globalThis.fetch).mockImplementation((input,init)=>{
    if(String(input).includes('/characters/1/sheet/')&&init?.method==='PATCH'&&!release)
      return new Promise<Response>(resolve=>{release=()=>{void original(input,init).then(resolve);};});
    return original(input,init);
  });
  mount('/sheet');
  fireEvent.change(await screen.findByRole('textbox',{name:'Инвентарь на обзоре'}),{target:{value:'Факел'}});
  await waitFor(()=>expect(release).toBeTypeOf('function'));
  fireEvent.change(screen.getByRole('textbox',{name:'Заметки на обзоре'}),{target:{value:'Проверить склад'}});
  release!();
  await waitFor(()=>expect(mutation).toMatchObject({url:'/characters/1/sheet/?campaign=1',body:{version:2,inventory:'Факел',notes:'Проверить склад'}}));
  await waitFor(()=>expect(screen.queryByText('Сохраним изменения автоматически…')).not.toBeInTheDocument());
});
it('restores spell slots from the overview with confirmation', async()=>{
  mount('/sheet');
  fireEvent.click(await screen.findByRole('button',{name:'Сбросить ячейки'}));
  expect(screen.getByRole('dialog',{name:'Восстановить все ячейки?'})).toBeInTheDocument();
  fireEvent.click(screen.getByRole('button',{name:'Подтвердить'}));
  await waitFor(()=>expect(mutation).toMatchObject({url:'/characters/1/resources/?campaign=1',method:'POST',body:{action:'restore_slots'}}));
});
it('keeps all spells in a compact searchable list with details and editing on the overview', async()=>{
  spellAvailable=true;multipleSpells=true;
  mount('/sheet');
  const list=await screen.findByLabelText('Заклинания персонажа');
  await waitFor(()=>expect(within(list).getAllByRole('button',{name:/^Применить /})).toHaveLength(10));
  fireEvent.change(screen.getByRole('textbox',{name:'Поиск заклинаний на обзоре'}),{target:{value:'огненный'}});
  expect(within(list).getAllByRole('button',{name:/^Применить /})).toHaveLength(1);
  expect(within(list).getAllByText('3 круг').length).toBeGreaterThan(0);
  fireEvent.click(within(list).getByRole('button',{name:'Подробнее: Огненный шар'}));
  expect(screen.getByRole('dialog',{name:'Огненный шар'})).toHaveTextContent('Эффект по описанию');
  fireEvent.click(screen.getByRole('button',{name:'Редактировать'}));
  expect(screen.getByRole('dialog',{name:'Редактировать действие'})).toBeInTheDocument();
});
it('opens existing creation and deletion flows from the overview', async()=>{
  spellAvailable=true;
  mount('/sheet');
  fireEvent.click(await screen.findByRole('button',{name:'Добавить'}));
  expect(screen.getByRole('dialog',{name:'Новая атака'})).toBeInTheDocument();
  fireEvent.keyDown(document,{key:'Escape'});
  fireEvent.click(screen.getByRole('button',{name:'Из каталога'}));
  expect(screen.getByRole('dialog',{name:'Добавить заклинание'})).toBeInTheDocument();
  fireEvent.keyDown(document,{key:'Escape'});
  fireEvent.click(screen.getByRole('button',{name:'Удалить Три искры'}));
  expect(screen.getByRole('dialog',{name:'Удалить «Три искры»?'})).toBeInTheDocument();
  fireEvent.click(screen.getByRole('button',{name:'Подтвердить'}));
  await waitFor(()=>expect(mutation).toMatchObject({url:'/abilities/9/?campaign=1',method:'PATCH',body:{active:false,version:1}}));
});
it('explains why a spell cannot be applied without an active session', async()=>{
  spellAvailable=true;
  activeSession=false;
  mount('/sheet');
  fireEvent.click(await screen.findByRole('tab',{name:'Заклинания'}));
  await screen.findByRole('heading',{name:'Три искры'});
  expect(screen.getByRole('button',{name:'Применить'})).toBeDisabled();
  expect(screen.getByText('В кампании нет активной сессии. Мастер должен начать сессию.')).toBeVisible();
});
