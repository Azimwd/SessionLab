import { useState } from "react";
import {
  FlaskConical,
  ArrowRight,
  Layers,
  Flag,
  Disc3,
  Sparkles,
  LoaderCircle,
} from "lucide-react";
import { request } from "../api/client";
import { Button, Field, ErrorBox } from "../components/ui";
export default function Auth({ onSuccess }: { onSuccess: () => void }) {
  const [register, setRegister] = useState(false),
    [error, setError] = useState<unknown>(null),
    [busy, setBusy] = useState(false);
  return (
    <div className="auth-page">
      <div className="auth-art">
        <div className="brand">
          <span className="brand-icon">
            <FlaskConical size={22} />
          </span>
          session<span>lab</span>
        </div>
        <div className="auth-copy">
          <div className="eyebrow">A LITTLE RANDOM. A LOT OF STORIES.</div>
          <h1>
            Следующая сессия.
            <br />
            <em>Новая история.</em>
          </h1>
          <p>
            Неожиданные эффекты, личные задания
            <br />и немного удачи — в одном пространстве.
          </p>
          <div className="auth-deck">
            <div className="auth-card left">
              <Flag size={30} />
              <small>MINI QUEST</small>
              <strong>
                История
                <br />
                из прошлого
              </strong>
              <span>+10 жетонов</span>
            </div>
            <div className="auth-card center">
              <Sparkles size={38} />
              <small>SESSION EFFECT</small>
              <strong>
                Это было
                <br />в моём плане.
              </strong>
              <span>ДАР · UNCOMMON</span>
            </div>
            <div className="auth-card right">
              <Disc3 size={32} />
              <small>PLAY A LITTLE</small>
              <strong>
                Доверься
                <br />
                случаю.
              </strong>
              <span>7 игровых режимов</span>
            </div>
          </div>
        </div>
        <small className="auth-bottom">
          Создано для историй, которые вы расскажете вместе.
        </small>
      </div>
      <div className="auth-form">
        <div className="auth-inner">
          <span className="eyebrow">ВАШЕ МЕСТО ЗА СТОЛОМ</span>
          <h2>{register ? "Начнём историю" : "С возвращением"}</h2>
          <p>
            {register
              ? "Создайте аккаунт и соберите свою группу."
              : "Ваши персонажи и приключения уже ждут."}
          </p>
          <form
            onSubmit={async (e) => {
              e.preventDefault();
              setBusy(true);
              setError(null);
              const data = Object.fromEntries(new FormData(e.currentTarget));
              try {
                await request(
                  register ? "/auth/register/" : "/auth/login/",
                  "POST",
                  data,
                );
                onSuccess();
              } catch (err) {
                setError(err);
              } finally {
                setBusy(false);
              }
            }}
          >
            {register && (
              <Field label="Я буду">
                <select name="account_role" defaultValue="player">
                  <option value="player">Игроком · присоединяться к кампаниям</option>
                  <option value="dm">Мастером · создавать кампании и играть</option>
                </select>
              </Field>
            )}
            {register && (
              <Field label="Как к вам обращаться">
                <input
                  name="first_name"
                  required
                  autoComplete="given-name"
                  maxLength={80}
                  placeholder="Ваше имя"
                />
              </Field>
            )}
            <Field label="Email">
              <input
                name="email"
                type="email"
                required
                autoComplete="email"
                placeholder="you@example.com"
              />
            </Field>
            <Field
              label="Пароль"
              hint={
                register ? "Минимум 8 символов, не только цифры." : undefined
              }
            >
              <input
                name="password"
                type="password"
                required
                minLength={register ? 8 : 1}
                autoComplete={register ? "new-password" : "current-password"}
                placeholder="Введите пароль"
              />
            </Field>
            {!!error && <ErrorBox error={error} />}
            <Button className="full" disabled={busy}>
              {busy ? <LoaderCircle size={18} className="spin" /> : null}
              {register ? "Создать аккаунт" : "Войти в пространство"}
              <ArrowRight size={18} />
            </Button>
          </form>
          <div className="auth-toggle">
            {register ? "Уже есть аккаунт?" : "Первый раз здесь?"}{" "}
            <button
              onClick={() => {
                setRegister(!register);
                setError(null);
              }}
            >
              {register ? "Войти" : "Создать аккаунт"}
            </button>
          </div>
          <div className="auth-trust">
            <Layers size={15} />
            Ваши результаты сохраняются. История продолжается.
          </div>
        </div>
      </div>
    </div>
  );
}
