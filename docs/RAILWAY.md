# Развёртывание SessionLab на Railway без Docker

Один Git-репозиторий, один проект Railway и три сервиса: **frontend**, **backend**, **Postgres**. В продакшене база только PostgreSQL. SQLite (`TEST_SQLITE=1`) остаётся для локальной разработки. Пользователь открывает лишь публичный адрес frontend; cookies Django, CSRF и поток событий идут через него.

## Подготовка репозитория

Поместите содержимое папки `sessionlab/` в корень Git-репозитория: рядом должны находиться `frontend/` и `backend/`. Отправьте изменения в нужную ветку GitHub. Docker не запускается. Старые файлы Compose сохранены, а их образы теперь называются `Dockerfile.compose`: Railway не обнаруживает их как автоматические Dockerfile.

## Сервисы Railway

1. Создайте проект и добавьте PostgreSQL. Оставьте его без публичного доступа.
2. Создайте сервис **backend** из того же Git-репозитория. В Settings → Source задайте **Root Directory: `/backend`**. Публичный домен ему не нужен. В Settings → Build используйте Railpack. В Settings → Deploy установите **Start Command: `sh railway-start.sh`** и **Pre-deploy Command: `sh railway-predeploy.sh`**. Для сборки задайте **Build Command: `python manage.py collectstatic --noinput`**. Railpack автоматически установит зафиксированные зависимости из `requirements.txt`, который подключает `requirements.lock.txt`.
3. Создайте сервис **frontend** из того же репозитория. Задайте **Root Directory: `/frontend`**, сборку Railpack, **Build Command: `npm run build`** и **Start Command: `npm run start`**. Railpack установит npm-зависимости из `package-lock.json`. Сгенерируйте для него публичный домен или подключите свой. Node-сервер отдаёт Vite `dist` и проксирует `/api/`, `/admin/`, `/static/` на backend, в том числе SSE.

Railway задаёт публичному сервису `PORT` автоматически. Для backend задайте `PORT=8000`, чтобы адрес приватной сети был постоянным. Если вы назвали сервис иначе, чем `backend`, исправьте его имя в `BACKEND_URL`.

### Variables сервиса backend

Вставляйте значения в интерфейс Railway как переменные сервиса. **Не задавайте `RAILPACK_INSTALL_CMD`**: она заменяет стандартную установку Railpack и может оставить сборку без `/app/.venv`. Если переменная уже добавлена, удалите её и пересоберите сервис.

```dotenv
PORT=8000
DATABASE_URL=${{Postgres.DATABASE_URL}}
DJANGO_SECRET_KEY=<уникальный длинный случайный ключ>
DJANGO_DEBUG=0
COOKIE_SECURE=1
FORCE_HTTPS=1
DJANGO_ALLOWED_HOSTS=<домен frontend без https://>
CSRF_TRUSTED_ORIGINS=https://<домен frontend>
```

`Postgres` в ссылке должен совпадать с именем сервиса базы в вашем Railway. Для ключа выполните локально `python -c "import secrets; print(secrets.token_urlsafe(50))"` и сохраните значение только в Variables. `TEST_SQLITE` **не задавайте**. Если позднее назначите собственный домен, добавьте его в `DJANGO_ALLOWED_HOSTS` (через запятую, без схемы) и `CSRF_TRUSTED_ORIGINS` (через запятую, с `https://`). После этого обновите сервис.

### Variables сервиса frontend

```dotenv
BACKEND_URL=http://backend.railway.internal:8000
PUBLIC_SCHEME=https
```

Сервис frontend обращается к Django по внутренней сети Railway. В браузере запросы используют относительные адреса `/api/...` и тот же публичный домен: отдельный публичный домен API и CORS не требуются. Не задавайте `BACKEND_URL` через `https://` для внутреннего домена Railway. Важна точная пара `PORT` backend и порт в `BACKEND_URL`.

## Первый запуск и проверка

1. Дождитесь готовности Postgres и backend. Предварительная команда backend применит миграции и повторно загрузит стандартные 120 эффектов, 42 квеста и 319 названий заклинаний. Команда идемпотентна, но записи стандартной библиотеки обновляются при каждом деплое.
2. Откройте `https://<домен frontend>/api/health/`: ожидается успешный JSON-ответ.
3. Откройте `https://<домен frontend>/api/docs/` и `https://<домен frontend>/admin/`: должны загружаться CSS и интерфейсы.
4. Создайте обычного пользователя через страницу регистрации. Для доступа к Django Admin создайте суперпользователя **один раз** через Railway shell для сервиса backend: `python manage.py createsuperuser`. Не добавляйте пароль администратора в репозиторий или переменные запуска.
5. Проверьте вход, обновление страницы `/sheet`, действие в комнате в двух браузерах, получение эффекта, расход ячейки и повторный запрос после обновления страницы.

Если frontend показывает `Backend unavailable`, проверьте имя внутреннего сервиса, `BACKEND_URL` и `PORT`. Если Django отвечает `DisallowedHost`, добавьте публичный домен frontend в `DJANGO_ALLOWED_HOSTS`. Если POST отвечает 403 CSRF, проверьте `CSRF_TRUSTED_ORIGINS`, HTTPS, cookie и публичный адрес сайта. Если CSS Admin отсутствует, проверьте завершение `collectstatic` в сборке backend.

Текущий production Node-прокси рассчитан на один публичный frontend и один внутренний backend в одной среде Railway. База должна храниться в сервисе PostgreSQL; файловое хранилище не требуется для текущих аватаров по URL.
