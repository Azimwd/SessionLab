import {
  createContext,
  useContext,
  useState,
  useEffect,
  lazy,
  Suspense,
  type ReactNode,
  useCallback,
} from "react";
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import {
  Routes,
  Route,
  Navigate,
  NavLink,
  Link,
  useLocation,
} from "react-router-dom";
import { MotionConfig, motion } from "motion/react";
import {
  LayoutDashboard,
  Layers,
  Flag,
  Disc3,
  UserRound,
  SlidersHorizontal,
  Sun,
  Moon,
  LogOut,
  ChevronDown,
  ArrowUpRight,
  FlaskConical,
  Coins,
  Menu,
  X,
  Radio,
  BookOpen,
  ShieldCheck,
} from "lucide-react";
import { request, list, clearCsrf, ApiError, type Json } from "./api/client";
import {
  Button,
  Loading,
  ErrorBox,
  Toast,
  Empty,
  Modal,
  Field,
  Badge,
  Count,
} from "./components/ui";
import Auth from "./pages/Auth";
import Campaigns from "./pages/Campaigns";
import Dashboard from "./pages/Dashboard";
import { useRoomSync } from "./features/room/useRoomSync";
import SpellCatalog, { SpellDetails } from './features/sheets/SpellCatalog';
const Room = lazy(() => import("./pages/Room"));
const Sheets = lazy(() => import("./pages/Sheets"));
const Effects = lazy(() => import("./pages/Effects"));
const Quests = lazy(() => import("./pages/Quests"));
const Casino = lazy(() => import("./pages/Casino"));
const Game = lazy(() => import("./pages/Game"));
const Profile = lazy(() => import("./pages/Profile"));
const DM = lazy(() => import("./pages/DM"));
interface Ctx {
  masterMode: boolean;
  connection: string;
  user: Json;
  campaign: Json | null;
  campaigns: Json[];
  characters: Json[];
  character: Json | null;
  sessions: Json[];
  session: Json | null;
  wallet: Json;
  cid: string;
  sid: string;
  charId: string;
  selectCampaign: (id: string) => void;
  selectCharacter: (id: string) => void;
  notify: (s: string) => void;
  refresh: () => void;
  theme: string;
  toggleTheme: () => void;
  reduced: boolean;
  setReduced: (v: boolean) => void;
}
const Context = createContext<Ctx>(null!);
export const useApp = () => useContext(Context);
export function useData<T = any>(path: string, enabled = true) {
  return useQuery<T>({
    queryKey: [path],
    queryFn: () => request<T>(path),
    enabled,
    retry: 1,
  });
}
export function useAction(success = "Сохранено") {
  const { notify, refresh } = useApp();
  return useMutation({
    mutationFn: ({
      path,
      body,
      method = "POST",
    }: {
      path: string;
      body?: any;
      method?: string;
    }) => request(path, method, body),
    onSuccess: () => {
      refresh();
      if (success) notify(success);
    },
    onError: (e) => notify(e.message),
  });
}
export function Scoped({ children }: { children: ReactNode }) {
  const { campaign } = useApp();
  return campaign ? (
    <>{children}</>
  ) : (
    <Empty
      title="Присоединитесь к кампании"
      text="Введите код приглашения от мастера на странице кампаний. Мастер также может создать собственную игру."
      action={
        <Link className="button" to="/">
          К кампаниям <ArrowUpRight size={16} />
        </Link>
      }
    />
  );
}
export default function App() {
  const qc = useQueryClient();
  const location = useLocation();
  const me = useQuery({
    queryKey: ["me"],
    queryFn: () => request("/auth/me/"),
    retry: false,
  });
  const campaigns = useQuery({
    queryKey: ["campaigns"],
    queryFn: () => list("/campaigns/"),
    enabled: !!me.data,
  });
  const [selected, setSelected] = useState(
    localStorage.getItem("sl:campaign") || "",
  );
  const cs = campaigns.data?.results || [];
  const campaign = cs.find((c) => String(c.id) === selected) || cs[0] || null;
  const cid = String(campaign?.id || "");
  const masterRoute = /^\/(master|dm)(\/|$)/.test(location.pathname);
  const masterMode = campaign?.role === "dm" && masterRoute;
  const connection = useRoomSync(cid, !!me.data);
  const chars = useData<any>(`/characters/?campaign=${cid}`, !!cid);
  const sessions = useData<Json[]>(`/campaigns/${cid}/sessions/`, !!cid);
  const [charId, setCharId] = useState(
    localStorage.getItem("sl:character") || "",
  );
  const own = (chars.data?.results || []).filter(
    (c: Json) => c.owner === me.data?.id && c.active && c.kind !== 'npc',
  );
  const character =
    own.find((c: Json) => String(c.id) === charId) || own[0] || null;
  const session = sessions.data?.find((s) => s.status === "active") || null;
  const wallet = useData<Json>(`/casino/wallet/?campaign=${cid}`, !!cid);
  const [theme, setTheme] = useState(
    localStorage.getItem("sl:theme") || "light",
  );
  const [reduced, setReducedState] = useState(
    localStorage.getItem("sl:reduced") === "true",
  );
  const [toast, setToast] = useState("");
  useEffect(() => {
    document.documentElement.dataset.theme = theme;
    document.documentElement.dataset.reduced = String(reduced);
    localStorage.setItem("sl:theme", theme);
    localStorage.setItem("sl:reduced", String(reduced));
  }, [theme, reduced]);
  useEffect(() => {
    if (me.data) {
      setTheme(me.data.theme);
      setReducedState(me.data.reduced_motion);
    }
  }, [me.data?.id]);
  const refresh = () => {
    qc.invalidateQueries();
  };
  const clear = useCallback(() => setToast(""), []);
  if (me.isPending)
    return (
      <div className="boot">
        <FlaskConical size={32} />
        <span>SessionLab</span>
      </div>
    );
  if (me.error && (!(me.error instanceof ApiError) || me.error.status !== 403))
    return (
      <div className="auth-form">
        <ErrorBox error={me.error} retry={() => me.refetch()} />
      </div>
    );
  if (!me.data)
    return (
      <Auth
        onSuccess={() => {
          clearCsrf();
          qc.invalidateQueries({ queryKey: ["me"] });
        }}
      />
    );
  const ctx: Ctx = {
    masterMode, connection,
    user: me.data,
    campaign,
    campaigns: cs,
    characters: chars.data?.results || [],
    character,
    sessions: sessions.data || [],
    session,
    wallet: wallet.data || { balance: 0 },
    cid,
    sid: String(session?.id || ""),
    charId: String(character?.id || ""),
    selectCampaign: (id) => {
      setSelected(id);
      localStorage.setItem("sl:campaign", id);
    },
    selectCharacter: (id) => {
      setCharId(id);
      localStorage.setItem("sl:character", id);
    },
    notify: setToast,
    refresh,
    theme,
    toggleTheme: () => setTheme((t) => (t === "dark" ? "light" : "dark")),
    reduced,
    setReduced: setReducedState,
  };
  return (
    <Context.Provider value={ctx}>
      <MotionConfig reducedMotion={reduced ? "always" : "user"}>
        <Shell>
          {campaigns.isPending ? (
            <Loading />
          ) : campaigns.isError ? (
            <ErrorBox
              error={campaigns.error}
              retry={() => campaigns.refetch()}
            />
          ) : (
            <Suspense fallback={<Loading />}>
              <Routes>
                <Route path="/" element={<Campaigns/>} />
                <Route path="/player" element={<Dashboard/>}/>
                <Route path="/games" element={<Campaigns/>}/>
                <Route path="/room" element={<Scoped><Room/></Scoped>}/>
                <Route path="/sheet" element={<Scoped><Sheets/></Scoped>}/>
                <Route path="/spells" element={<Scoped><SpellCatalog/></Scoped>}/>
                <Route path="/spells/:id" element={<Scoped><SpellDetails/></Scoped>}/>
                <Route path="/master" element={campaign?.role === "dm" ? <Room/> : <Navigate to="/room" replace/>}/>
                <Route path="/master/sheets" element={campaign?.role === "dm" ? <Sheets/> : <Navigate to="/sheet" replace/>}/>
                <Route
                  path="/effects"
                  element={
                    <Scoped>
                      <Effects />
                    </Scoped>
                  }
                />
                <Route
                  path="/quests"
                  element={
                    <Scoped>
                      <Quests />
                    </Scoped>
                  }
                />
                <Route
                  path="/casino"
                  element={
                    <Scoped>
                      <Casino />
                    </Scoped>
                  }
                />
                <Route
                  path="/casino/:game"
                  element={
                    <Scoped>
                      <Game />
                    </Scoped>
                  }
                />
                <Route path="/profile" element={<Profile />} />
                <Route
                  path="/dm"
                  element={
                    campaign?.role === "dm" ? <DM /> : <Navigate to="/" />
                  }
                />
                <Route
                  path="*"
                  element={
                    <Empty
                      title="Страница не найдена"
                      action={
                        <Link to="/" className="button">
                          На главную
                        </Link>
                      }
                    />
                  }
                />
              </Routes>
            </Suspense>
          )}
        </Shell>
        <Toast message={toast} clear={clear} />
      </MotionConfig>
    </Context.Provider>
  );
}
function Shell({ children }: { children: ReactNode }) {
  const a = useApp();
  const qc = useQueryClient();
  const loc = useLocation();
  const [menu, setMenu] = useState(false);
  const nav = (a.masterMode ? [
    ["/master", "Стол мастера", Radio],
    ["/master/sheets", "Листы группы", BookOpen],
    ["/dm", "Управление кампанией", SlidersHorizontal],
    ["/profile", "Мой профиль", UserRound],
  ] : [
    ["/", "Кампании", LayoutDashboard],
    ["/room", "Игровая комната", Radio],
    ["/sheet", "Мой персонаж", BookOpen],
    ["/spells", "Справочник заклинаний", FlaskConical],
    ["/profile", "Мой профиль", UserRound],
  ]) as [string, string, typeof Radio][];
  return (
    <div className={`app-shell ${a.masterMode?'master-layout':'player-layout'}`}>
      {a.masterMode && <aside className={`sidebar ${menu ? "open" : ""}`}>
        <Link to="/" className="brand">
          <span className="brand-icon">
            <FlaskConical size={21} />
          </span>
          session<span>lab</span>
          <Badge>beta</Badge>
        </Link>
        <button
          className="mobile-close"
          aria-label="Закрыть меню"
          onClick={() => setMenu(false)}
        >
          <X />
        </button>
        <div className="workspace-switch">
          <span className="workspace-avatar">
            {a.campaign?.name?.slice(0, 1) || "S"}
          </span>
          <div>
            <small>ВАШЕ ПРОСТРАНСТВО</small>
            <select
              aria-label="Кампания"
              value={a.cid}
              onChange={(e) => a.selectCampaign(e.target.value)}
            >
              {!a.campaign && <option value="">Нет кампании</option>}
              {a.campaigns.map((c) => (
                <option key={c.id} value={c.id}>
                  {c.name}
                </option>
              ))}
            </select>
          </div>
          <ChevronDown size={14} />
        </div>
        <div className="role-space"><ShieldCheck size={16}/><strong>Панель мастера</strong></div>
        <Link className="view-switch" to="/room" onClick={() => setMenu(false)}>Посмотреть как игрок</Link>
        <div className="nav-label">{a.masterMode ? "ВАША КАМПАНИЯ" : "МОИ ИНСТРУМЕНТЫ"}</div>
        <nav>
          {nav.map(([to, label, Icon]) => (
            <NavLink
              key={to}
              to={to}
              end={to === "/" || to === "/master"}
              onClick={() => setMenu(false)}
            >
              <Icon size={19} />
              <span>{label}</span>
            </NavLink>
          ))}
        </nav>
        <div className="sidebar-bottom">
          <div className="sidebar-note">
            <div className="tiny-orbit">✦</div>
            <strong>
              Хорошей истории
              <br />
              нужен только повод.
            </strong>
            <p>Остальное создадите вы.</p>
            <Link to={a.masterMode ? "/master" : "/room"}>
              Открыть комнату <ArrowUpRight size={14} />
            </Link>
          </div>
          <div className="theme-control">
            <span>Оформление</span>
            <button aria-label="Переключить тему" onClick={a.toggleTheme}>
              {a.theme === "dark" ? <Moon size={16} /> : <Sun size={16} />}
            </button>
          </div>
          <Link to="/profile" className="user-block">
            <div className="avatar">
              {(a.user.first_name || a.user.email).slice(0, 1).toUpperCase()}
            </div>
            <div>
              <strong>{a.user.first_name || "Игрок"}</strong>
              <small>
                {a.campaign?.role === "dm"
                  ? "Dungeon Master"
                  : "Участник кампании"}
              </small>
            </div>
            <ArrowUpRight size={16} />
          </Link>
        </div>
      </aside>}
      {menu && <div className="menu-backdrop" onClick={() => setMenu(false)} />}
      <div className="main-shell">
        <header className="topbar">
          {a.masterMode ? <button
            className="mobile-menu"
            aria-label="Открыть меню"
            onClick={() => setMenu(true)}
          >
            <Menu />
          </button>:<Link className="brand player-brand" to="/"><span className="brand-icon"><FlaskConical size={19}/></span> session<span>lab</span></Link>}
          <div className="breadcrumb">
            {a.masterMode ? 'Панель управления' : <select aria-label="Текущая кампания" value={a.cid} onChange={e=>a.selectCampaign(e.target.value)}>{!a.campaign&&<option value="">Нет игры</option>}{a.campaigns.map(c=><option key={c.id} value={c.id}>{c.name}</option>)}</select>}
          </div>
          <nav className="header-nav" aria-label="Навигация по игре"><NavLink to="/" end>Игры</NavLink><NavLink to="/room">Комната</NavLink><NavLink to="/sheet">Лист</NavLink><NavLink to="/spells">Заклинания</NavLink><NavLink to="/effects">Эффекты</NavLink><NavLink to="/quests">Квесты</NavLink><NavLink to="/casino">Казино</NavLink>{a.campaign?.role==='dm'&&<NavLink to="/dm">Панель управления</NavLink>}</nav>
          <div className="topbar-right">
            {a.session && (
              <span className="session-live">
                <i />
                Сессия активна
              </span>
            )}
            <Link className="token-pill" to="/casino">
              <Coins size={16} />
              <Count value={a.wallet.balance} />
              <small>ST</small>
            </Link>
            {!a.masterMode&&<Link className="header-profile" to="/profile" aria-label="Мой профиль"><UserRound size={18}/></Link>}
            <button
              aria-label="Выйти"
              title="Выйти"
              onClick={async () => {
                try {
                  await request("/auth/logout/", "POST", {});
                  clearCsrf();
                  qc.clear();
                  for (const k of Object.keys(sessionStorage))
                    if (k.startsWith("sl:")) sessionStorage.removeItem(k);
                  qc.invalidateQueries();
                } catch (e) {
                  a.notify((e as Error).message);
                }
              }}
            >
              <LogOut size={17} />
            </button>
          </div>
        </header>
        <main key={a.cid} className="content">
          <motion.div
            key={loc.pathname}
            initial={{ opacity: 0, y: 10 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ duration: 0.22 }}
          >
            {children}
          </motion.div>
          <footer className="page-footer">
            <span>SESSIONLAB</span>
            <p>Маленькие события. Большие истории.</p>
            <span>Только игровая валюта · ST</span>
          </footer>
        </main>
      </div>
    </div>
  );
}
