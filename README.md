# SessionLab

Работающая первая версия платформы для настольных ролевых игр: React SPA и Django REST API. Результаты игр, эффекты, квесты и деньги определяет и сохраняет сервер. Стандартная библиотека: **120 эффектов, 42 мини-квеста, 7 игр**. Добавлены общая комната с живыми обновлениями, отдельные пространства мастера и игрока, листы персонажей, инициатива и серверные броски проверок, атак и заклинаний. Решения о попадании и повествовательных последствиях остаются за столом.

## Стек и структура

React 19 / TypeScript / Vite / React Router / Tailwind 4 / TanStack Query / Motion. Manrope поставляется локально. Python 3.12–3.14 / Django 5.2.18 LTS / DRF / PostgreSQL 17 / drf-spectacular / django-axes / Gunicorn / Nginx. Версии зависимостей зафиксированы в `frontend/package-lock.json` и `backend/requirements.lock.txt`.

```text
sessionlab/
├── backend/
│   ├── config/                  # settings, urls, WSGI
│   ├── lab/
│   │   ├── api/                 # auth, campaigns, play, DM, serializers, OpenAPI
│   │   ├── services/            # effects, quests, wallet, casino, pure casino math
│   │   ├── data/                # исходные 120 эффектов и 42 квеста
│   │   ├── management/commands/ # seed_initial_data
│   │   ├── migrations/          # схема и перенос данных
│   │   ├── tests/               # API, математика, транзакции
│   │   ├── models.py            # нормализованные сущности
│   │   └── admin.py             # системное администрирование
│   ├── manage.py
│   ├── openapi.yaml
│   ├── Dockerfile.compose       # только для необязательного Docker Compose
│   └── requirements.lock.txt
├── frontend/
│   ├── src/
│   │   ├── api/client.ts        # CSRF, sessions, безопасный повтор запросов
│   │   ├── components/          # UI, игровые визуализации, тесты
│   │   ├── pages/               # Dashboard, Effects, Quests, Casino, Game, Profile, DM
│   │   ├── app.tsx              # маршруты, контекст, навигация
│   │   └── styles.css           # темы, адаптивность, CSS 3D
│   ├── deploy/nginx.conf
│   ├── Dockerfile.compose       # только для необязательного Docker Compose
│   ├── server.mjs               # production SPA + same-origin proxy без Docker
│   └── package-lock.json
├── docs/
│   ├── API.md
│   ├── OPERATIONS.md
│   ├── RAILWAY.md                # Railway без Docker
│   └── TESTING.md
├── .github/workflows/test.yml
├── start-backend.bat
├── start-frontend.bat
├── .env.local.example         # SQLite, запуск без Docker
├── .env.example
├── docker-compose.yml
└── docker-compose.dev.yml
```

## Запуск без Docker: Windows CMD и SQLite

Для развёртывания на Railway без Docker: [docs/RAILWAY.md](docs/RAILWAY.md). Один репозиторий содержит два сервиса Railpack и отдельный PostgreSQL; `/api/`, `/admin/` и SSE обслуживаются на домене frontend.

Docker и отдельный PostgreSQL для локальной работы не нужны. SQLite создаётся автоматически в `backend/development.sqlite3`. Django читает `.env.local` из корня проекта; переменные, заданные в консоли, имеют приоритет. Нужны установленный Python и Node.js с npm.

**Python 3.14 можно использовать:** Django 5.2 поддерживает его начиная с 5.2.8 ([официальные release notes](https://docs.djangoproject.com/en/5.2/releases/5.2.8/)). Здесь закреплён Django 5.2.18. Фактические тесты этого архива выполнены на Python 3.12/Linux; Windows/Python 3.14 отдельно не прогонялись.

Первоначальная установка в CMD, из вашей папки проекта:

```bat
cd /d D:\project\Django\SessionLab
py -3.14 -m venv .venv
call .venv\Scripts\activate.bat
python -m pip install --upgrade pip
python -m pip install -r backend\requirements.lock.txt
if not exist .env.local copy .env.local.example .env.local
python -c "import secrets; print(secrets.token_urlsafe(50))"
notepad .env.local
```

Вставьте сгенерированную строку в `DJANGO_SECRET_KEY` и сохраните файл. Не вставляйте буквально текст «ВАШ_СЕКРЕТНЫЙ_КЛЮЧ». Если `.venv` уже создана и работает, повторно создавать её не нужно. При отсутствии Python launcher используйте `python -m venv .venv`, предварительно проверив `python --version`.

После установки зависимостей:

```bat
python backend\manage.py migrate
python backend\manage.py seed_initial_data
python backend\manage.py createsuperuser
```

`createsuperuser` нужен только для системного `/admin/`. Обычный мастер регистрируется в React и создаёт кампанию. `makemigrations` для запуска готового проекта не нужен: миграции включены в архив. `collectstatic` не нужен при `runserver` с `DJANGO_DEBUG=1`.

**Первая консоль — backend:**

```bat
cd /d D:\project\Django\SessionLab
start-backend.bat
```

**Вторая консоль — frontend:**

```bat
cd /d D:\project\Django\SessionLab\frontend
npm ci
npm run dev -- --port 5173 --strictPort
```

После первого `npm ci` можно запускать `start-frontend.bat` из корня. Откройте **http://localhost:5173**. Vite проксирует API, Admin и SSE на Django, поэтому cookies остаются на одном origin. Swagger: `http://localhost:5173/api/docs/`, админка: `http://localhost:5173/admin/`. Запросы API не нужно вручную направлять на другой порт из браузера.

Ошибка `No module named drf_spectacular` означает отсутствие зависимостей в выбранном Python: сначала создайте `.venv`, активируйте её, затем выполните `python -m pip install -r backend\requirements.lock.txt`. Установка в другой системный Python проблему текущего окружения не решит.

На macOS/Linux аналогично: `python3 -m venv .venv`, `source .venv/bin/activate`, `cp .env.local.example .env.local`, затем те же команды Python и npm. Для backend используйте `python backend/manage.py runserver 8000`.

### Обновление существующего проекта

1. Остановите обе консоли. Сохраните резервную копию `backend/development.sqlite3` и ваших исходных правок.
2. Обновите исходники из архива, сохранив свою БД, `.env.local`/`.env` и `.venv`. Не удаляйте БД для установки новых функций.
3. Из активной `.venv` выполните `python -m pip install -r backend\requirements.lock.txt`, затем `python backend\manage.py migrate`. Новые миграции `0004` и `0005` добавляют листы, заклинания, журнал комнаты и инициативу. Существующие персонажи сохраняются; их лист создаётся при первом открытии.
4. В `frontend` выполните `npm ci`. Запустите обе консоли заново.
5. Повторный `seed_initial_data` нужен при обновлении стандартной библиотеки; он не удаляет custom-контент, но восстанавливает стандартные определения. После обновления каталога заклинаний выполните `migrate` и `seed_initial_data` повторно.

## PostgreSQL и Docker — дополнительный вариант

При переходе на PostgreSQL задайте `TEST_SQLITE=0` и `DATABASE_URL` в `.env.local`, затем выполните миграции. Это другая БД: данные SQLite сами не переносятся. Для многопользовательского production предусмотрен Compose; локальный запуск выше от него не зависит.

```bash
cp .env.example .env
# Замените секрет Django и пароль БД в .env.
docker compose up -d db
docker compose run --rm backend python manage.py migrate
docker compose run --rm backend python manage.py seed_initial_data
docker compose run --rm backend python manage.py collectstatic --noinput
docker compose run --rm backend python manage.py createsuperuser
docker compose up --build -d
```

Открыть `http://localhost:8080`. Для Docker development: `docker compose -f docker-compose.yml -f docker-compose.dev.yml up db backend frontend` после миграций. Для production настройте HTTPS и cookies по `docs/OPERATIONS.md`. Docker-запуск в среде сборки не проверялся.

## Первый игровой сценарий

1. Зарегистрируйтесь. Откройте «Мой профиль» и создайте кампанию. Создатель автоматически получает права мастера и кошелёк.
2. Создайте персонажа в выбранной кампании. В «Управление кампанией → Сессии» создайте и начните сессию.
3. Передайте друзьям код из «Участники». Они создадут аккаунты, присоединятся по коду и создадут своих персонажей.
4. В «Эффекты» получите карточку. Результат сохранён до анимации. Обычный лимит — одна выдача на персонажа за сессию.
5. В «Квесты» получите до двух заданий, отправьте описание выполнения. Мастер подтвердит запрос в обзоре — награда начислится один раз.
6. Откройте казино. Все семь игр работают с серверным кошельком. Незавершённый карточный раунд можно продолжить после перезагрузки.
7. Завершите сессию через панель мастера: неиспользованные эффекты и задания истекут. Сначала игроки должны завершить открытые Blackjack/Higher or Lower.

8. В «Мой персонаж» заполните характеристики, навыки, ресурсы и заклинания. На общем столе видны броски, хиты, состояния и инициатива. Подробности: `docs/ROOMS_AND_SHEETS.md`.

## Что реализовано

- Email/пароль, Django Sessions, HttpOnly session/CSRF cookies, CSRF bootstrap, защита входа django-axes.
- Кампании, приглашения по коду, роли по кампании, отключение участников, персонажи, сессии и переопределение правил сессии.
- Раздельная навигация мастера и игрока; мастер может перейти в вид игрока. Роль проверяется для каждой кампании на сервере.
- Живые комнаты через SSE, переподключение и запасной опрос каждые 5 секунд. Общие хиты, состояния, инициатива, журнал публичных бросков; скрытые NPC и броски мастеру защищены сервером.
- Листы: характеристики, навыки/экспертиза, спасброски, хиты/временные хиты, КД, состояния, ячейки, приватные записи. Черновики и защита от перезаписи другой версии.
- Отдельные разделы атак и заклинаний; все 319 открытых заклинаний SRD 5.1 с русскими названиями и добавлением в лист одним нажатием. Полный перечень заклинаний всех коммерческих книг и редакции 2024 не включён. Проверенные русские параметры и броски настроены для 15 заклинаний; оставшиеся 304 записи помечены как требующие сверки с мастером. Есть отдельный справочник `/spells`. Детали в docs/ROOMS_AND_SHEETS.md.
- Атаки и пользовательские заклинания: формулы кубиков, бонусы, преимущество/помеха, критический урон, усиление ячейкой, несколько лучей, рост заговоров, концентрация. Сервер сохраняет результат и списывает ячейку в одной транзакции.
- Полная стартовая библиотека; категория 45/25/30 с нормализацией доступных категорий; веса карточек и собственные наборы. Выдача, снимки описаний, использование, согласование, истечение, история. «Выбор из трёх» сохраняется на следующую выдачу и исключает самовоспроизведение. Передача/обмен — согласие получателя и решение мастера; исходный лимит выдачи не восстанавливается передачей.
- 42 квеста с наградами 5/10/15, лимит на сессию, подтверждение, отклонение с повторной отправкой, отмена и первое достижение. Завершение задания не открывает бесконечную выдачу новых наград.
- Европейская рулетка с несколькими ставками, слоты, Blackjack с Hit/Stand/Double, Dice Duel, Coin Flip, Higher or Lower, Lucky Wheel. Серверные шансы, правила и снимки конфигураций. RTP рассчитан комбинаторно там, где не зависит от стратегии.
- Кошельки по пользователю и кампании, ledger, стартовый грант один раз, ручные корректировки с причиной, статистика ставок/полных выплат/чистой прибыли.
- React-панель мастера: контент, ручная выдача, подтверждения, участники, роли, кошельки, сессии, вероятность, игры, наборы, JSON/CSV import/export и аудит. Django Admin — отдельно.
- Светлая/тёмная темы, Manrope, мобильная сетка и меню, модальные окна с фокусом/Escape, уведомления, загрузки, пустые и ошибочные состояния. CSS 3D и Motion для колоды, рулетки, монеты, костей и карт; прокрутка барабанов. Пропуск анимаций и reduced motion.

## Команды обслуживания

```bash
# Идемпотентное обновление стандартной библиотеки; custom/import-контент сохраняется
python backend/manage.py seed_initial_data
python backend/manage.py makemigrations --check --dry-run
python backend/manage.py spectacular --file backend/openapi.yaml --validate --fail-on-warn
# После установки PostgreSQL / с DATABASE_URL:
cd backend
python -m pytest -q
# Frontend:
cd ../frontend
npm test
npm run build
```

Команды в контейнере: `docker compose exec backend python manage.py ...`; тесты: `docker compose exec backend python -m pytest -q`. DB-пользователь тестов должен иметь `CREATEDB` (пользователь официального контейнера по умолчанию имеет его).

## Окружение

| Переменная | Назначение |
|---|---|
| `DJANGO_SECRET_KEY` | Секрет Django; длинное случайное значение |
| `DJANGO_DEBUG` | `0` production; `1` только разработка |
| `DJANGO_ALLOWED_HOSTS` | Разрешённые домены через запятую, без схем |
| `DATABASE_URL` | PostgreSQL connection string |
| `POSTGRES_DB`, `POSTGRES_USER`, `POSTGRES_PASSWORD` | Создание БД в Compose; должны совпадать с DATABASE_URL |
| `COOKIE_SECURE` | `1` для HTTPS; `0` только локальный HTTP |
| `CSRF_TRUSTED_ORIGINS` | Разрешённые origins со схемой/портом через запятую |
| `WEB_PORT` | Локальный порт Nginx, по умолчанию 8080 |
| `API_PROXY` | Только dev Vite; адрес Django, по умолчанию http://127.0.0.1:8000 |
| `TEST_SQLITE` | `1` для локальной SQLite; PostgreSQL используется при `0`/отсутствии; не включайте SQLite в production |

## API и администрирование

Swagger: `/api/docs/`, схема: `/api/schema/`, сохранённая схема: `backend/openapi.yaml`. Все игровые мутации требуют `Idempotency-Key` и `X-CSRFToken`, а также выбранной кампании. Подробный контракт с примерами — `docs/API.md`. Инструкции мастера/администратора, безопасность, резервные копии и deployment — `docs/OPERATIONS.md`.

## Проверка и границы версии

Актуальные результаты и непроверенные пункты — в `docs/TESTING.md`. В среде разработки недоступны Docker daemon и PostgreSQL, поэтому фактический Compose-запуск и PostgreSQL-конкуренция здесь не подтверждены. Для этого включён отдельный тест и CI с настоящим PostgreSQL. Полноценный браузерный прогон авторизованных страниц тоже остаётся отдельной приёмкой; автоматические API/React-проверки его не заменяют.

Контент и сложные правила мастера редактируются через рабочий JSON-редактор с серверной валидацией. Это функциональная первая версия интерфейса конструктора; расширенный визуальный редактор полей ещё не добавлен. Источником контента остаётся БД.

Не реализованы необязательные OAuth, split/insurance, звук, магазин косметики, загрузка бинарного аватара (поддержан URL), email-рассылка приглашений, восстановление пароля и автоматический полный движок правил D&D. Приглашения работают через код; живые обновления реализованы через SSE без Redis. Обычная задержка обнаружения изменения около секунды, запасной опрос — раз в 5 секунд. Произвольный текст заклинания не исполняется: бросаются настроенные формулы, цель сама делает спасбросок, применение урона подтверждается за столом. Перезапуск балансов — через аудируемые корректировки мастера, массовый автоматический reset не предусмотрен.

Сериализация операций по кампании сознательно упрощает корректность и достаточна для небольшой группы; крупные кампании потребуют более узких блокировок после нагрузочных измерений. Проверка масштаба и production-нагрузки не выполнена. Игровой баланс стартового Homebrew требует решения мастера и playtesting для выбранной редакции D&D.

SQLite использует IMMEDIATE-транзакции и timeout 20 секунд для коротких локальных записей. Она сериализует записи всей БД, поэтому подходит для разработки и небольшой локальной группы; нагрузочная приёмка не выполнена. SSE на синхронном сервере занимает поток на соединение; production Gunicorn настроен с gthread.
