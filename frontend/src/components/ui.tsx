import {
  useEffect,
  useRef,
  useState,
  type ReactNode,
  type ButtonHTMLAttributes,
} from "react";
import { createPortal } from "react-dom";
import { motion, AnimatePresence } from "motion/react";
import {
  X,
  ArrowUpRight,
  LoaderCircle,
  Check,
  AlertCircle,
  Sparkles,
} from "lucide-react";
export function Button({
  children,
  variant = "",
  className = "",
  ...props
}: ButtonHTMLAttributes<HTMLButtonElement> & { variant?: string }) {
  return (
    <button className={`button ${variant} ${className}`} {...props}>
      {children}
    </button>
  );
}
export function Card({
  children,
  className = "",
}: {
  children: ReactNode;
  className?: string;
}) {
  return <section className={`card ${className}`}>{children}</section>;
}
export function Badge({
  children,
  tone = "",
}: {
  children: ReactNode;
  tone?: string;
}) {
  return <span className={`badge ${tone}`}>{children}</span>;
}
export function Header({
  eyebrow,
  title,
  subtitle,
  action,
}: {
  eyebrow?: string;
  title: string;
  subtitle?: string;
  action?: ReactNode;
}) {
  return (
    <header className="page-heading">
      <div>
        <div className="eyebrow">{eyebrow || "YOUR NEXT CHAPTER"}</div>
        <h1>{title}</h1>
        {subtitle && <p>{subtitle}</p>}
      </div>
      {action}
    </header>
  );
}
export function Empty({
  title = "Здесь начинается история",
  text,
  action,
}: {
  title?: string;
  text?: string;
  action?: ReactNode;
}) {
  return (
    <div className="empty">
      <div className="empty-icon">
        <Sparkles size={25} />
      </div>
      <h3>{title}</h3>
      <p>{text}</p>
      {action}
    </div>
  );
}
export function Loading() {
  return (
    <div className="loading" aria-label="Загрузка">
      <div className="skeleton tall" />
      <div className="grid three">
        {[1, 2, 3].map((i) => (
          <div className="skeleton" key={i} />
        ))}
      </div>
    </div>
  );
}
export function ErrorBox({
  error,
  retry,
}: {
  error: unknown;
  retry?: () => void;
}) {
  return (
    <div role="alert" className="error">
      <AlertCircle size={18} />
      <span>
        {error instanceof Error ? error.message : "Не удалось загрузить данные"}
      </span>
      {retry && (
        <Button variant="ghost" onClick={retry}>
          Повторить
        </Button>
      )}
    </div>
  );
}
export function Field({
  label,
  children,
  hint,
}: {
  label: string;
  children: ReactNode;
  hint?: string;
}) {
  return (
    <label className="field">
      <span>{label}</span>
      {children}
      {hint && <small>{hint}</small>}
    </label>
  );
}
export function Modal({
  title,
  children,
  onClose,
  wide = false,
}: {
  title: string;
  children: ReactNode;
  onClose: () => void;
  wide?: boolean;
}) {
  const panel = useRef<HTMLDivElement>(null);
  const closeRef = useRef(onClose);
  closeRef.current = onClose;
  useEffect(() => {
    const old = document.activeElement as HTMLElement;
    const overflow = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    panel.current?.focus();
    const key = (e: KeyboardEvent) => {
      if (e.key === "Escape") closeRef.current();
      if (e.key === "Tab") {
        const nodes = panel.current?.querySelectorAll<HTMLElement>(
          "button:not([disabled]),input,textarea,select,a[href]",
        );
        if (!nodes?.length) return;
        const first = nodes[0],
          last = nodes[nodes.length - 1];
        if (
          e.shiftKey &&
          (document.activeElement === first ||
            document.activeElement === panel.current)
        ) {
          e.preventDefault();
          last.focus();
        } else if (!e.shiftKey && document.activeElement === last) {
          e.preventDefault();
          first.focus();
        }
      }
    };
    document.addEventListener("keydown", key);
    return () => {
      document.body.style.overflow = overflow;
      document.removeEventListener("keydown", key);
      old?.focus();
    };
  }, []);
  return createPortal(
    <div
      className="overlay"
      onMouseDown={(e) => {
        if (e.target === e.currentTarget) onClose();
      }}
    >
      <motion.div
        initial={{ opacity: 0, y: 18, scale: 0.98 }}
        animate={{ opacity: 1, y: 0, scale: 1 }}
        className={`modal ${wide ? "wide" : ""}`}
        role="dialog"
        aria-modal="true"
        aria-labelledby="dialog-title"
        tabIndex={-1}
        ref={panel}
      >
        <div className="modal-top">
          <h2 id="dialog-title">{title}</h2>
          <Button variant="icon ghost" aria-label="Закрыть" onClick={onClose}>
            <X size={20} />
          </Button>
        </div>
        {children}
      </motion.div>
    </div>,
    document.body,
  );
}
export function Confirm({
  title,
  text,
  onConfirm,
  onClose,
  busy,
}: {
  title: string;
  text: string;
  onConfirm: () => void;
  onClose: () => void;
  busy?: boolean;
}) {
  return (
    <Modal title={title} onClose={onClose}>
      <p>{text}</p>
      <div className="actions end">
        <Button variant="secondary" onClick={onClose}>
          Отмена
        </Button>
        <Button disabled={busy} onClick={onConfirm}>
          {busy ? <LoaderCircle className="spin" size={16} /> : null}Подтвердить
        </Button>
      </div>
    </Modal>
  );
}
export function Pagination({
  page,
  setPage,
  count,
}: {
  page: number;
  setPage: (n: number) => void;
  count: number;
}) {
  if (count <= 30) return null;
  return (
    <div className="pagination">
      <Button
        variant="secondary"
        disabled={page === 1}
        onClick={() => setPage(page - 1)}
      >
        Назад
      </Button>
      <span>
        {page} / {Math.ceil(count / 30)}
      </span>
      <Button
        variant="secondary"
        disabled={page * 30 >= count}
        onClick={() => setPage(page + 1)}
      >
        Далее
      </Button>
    </div>
  );
}
export function Count({ value }: { value: string | number }) {
  const [display, setDisplay] = useState(value);
  useEffect(() => setDisplay(value), [value]);
  return (
    <motion.span
      key={value}
      initial={{ opacity: 0.4, y: 4 }}
      animate={{ opacity: 1, y: 0 }}
    >
      {Number(display).toLocaleString("ru-RU", { maximumFractionDigits: 2 })}
    </motion.span>
  );
}
export function Arrow() {
  return <ArrowUpRight size={18} />;
}
export const statusLabel: Record<string, string> = {
  active: "Активно",
  rolled: "Выберите карточку",
  used: "Использовано",
  pending_approval: "Ожидает мастера",
  pending_verification: "На проверке",
  completed: "Завершено",
  expired: "Истекло",
  cancelled: "Отменено",
  rejected: "Отклонено",
  planned: "Запланирована",
  pending_consent: "Ожидает согласия",
};
export const categoryLabel: Record<string, string> = {
  gift: "Дар",
  complication: "Осложнение",
  paradox: "Парадокс",
};
export function Status({ status }: { status: string }) {
  return (
    <Badge
      tone={
        ["completed", "used"].includes(status)
          ? "green"
          : status.startsWith("pending")
            ? "amber"
            : ""
      }
    >
      {statusLabel[status] || status}
    </Badge>
  );
}
export function Toast({
  message,
  clear,
}: {
  message: string;
  clear: () => void;
}) {
  useEffect(() => {
    if (message) {
      const t = setTimeout(clear, 4500);
      return () => clearTimeout(t);
    }
  }, [message, clear]);
  return (
    <AnimatePresence>
      {message && (
        <motion.div
          className="toast"
          role="status"
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          exit={{ opacity: 0, y: 10 }}
        >
          <Check size={18} />
          {message}
          <button onClick={clear} aria-label="Закрыть уведомление">
            <X size={16} />
          </button>
        </motion.div>
      )}
    </AnimatePresence>
  );
}
