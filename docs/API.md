# REST API SessionLab

Интерактивная схема: `/api/docs/`. Снимок OpenAPI: `backend/openapi.yaml`. Базовый путь `/api/`. Ответы обёрнуты в `{ "data": ..., "error": null }`; ошибки — `{ "data": null, "error": { ... } }` или список ошибок. Неподходящий запрос не является успешным игровым действием.

## Авторизация и повтор запросов

1. `GET /api/auth/csrf/` возвращает `data.csrfToken` и устанавливает HttpOnly CSRF cookie.
2. `POST /api/auth/register/` или `/login/`: JSON с email/password, для регистрации допустим first_name. Отправьте токен как `X-CSRFToken`. Cookies передаются автоматически с `credentials: include`.
3. После входа Django ротирует CSRF. Получите новый токен через `/csrf/` перед последующей мутацией.
4. `GET /api/auth/me/`; `PATCH /api/auth/me/` разрешает first_name, theme (light/dark), reduced_motion. `POST /api/auth/logout/` завершает сессию.
5. Все остальные endpoints требуют активного членства. Для предметных операций передайте `?campaign=ID`. Nested `/campaigns/{id}/...` берут кампанию из path.
6. Все игровые/DM мутации требуют `Idempotency-Key` (8–100 символов). Рекомендуется UUID. Если сеть прервалась, повторите **тот же method/path/body/campaign и тот же ключ**. Ответ сохранён в той же транзакции, что и действие. Другой body с занятым ключом возвращает 400. Права проверяются даже при повторе.

Авторизация на анонимных unsafe endpoints также проверяет CSRF, включая register/login. Запрет по аутентификации/правам — 403, отсутствие объекта — 404, валидация и состояние — 400, throttling/блокировка — 429. API не использует JWT. Недоступный чужой объект никогда не возвращает его данные.

## Экспериментальный экспорт событий в DMHub

`GET /dm/integrations/dmhub/?campaign=ID` возвращает состояние моста только мастеру кампании. `POST` на тот же URL с `{"action":"rotate"}` создаёт новый ключ и показывает его один раз; `{"action":"revoke"}` отключает ключ. Управление защищено Django session и CSRF. Эти два действия не сохраняют секрет в idempotency log: после сбоя ответа повторный rotate выдаёт новый ключ.

`GET /integrations/dmhub/events/?cursor=latest` требует отдельного `Authorization: Bearer <ключ>` и возвращает `{events:[],cursor:<id>}`. При числовом cursor сервер отдаёт до 50 последующих публичных событий `roll`/`ability` только привязанной кампании: `{events:[{id,session,text}],cursor:<последний id>}`. Секретные броски и сырой payload не выдаются. [Установка локального моста и ограничения](DMHUB.md).

## Кампании, персонажи, сессии

| Method/path | Назначение |
|---|---|
| GET/POST `/campaigns/` | Список доступных кампаний / создать `{name, description?, settings?}` |
| GET/PATCH `/campaigns/{id}/` | Прочитать / мастер меняет правила и описание |
| POST `/campaigns/join/` | Вступить по `{code}`; отключённое членство не восстанавливается самим игроком |
| GET `/campaigns/{id}/members/` | Участники; email и отключённые участники доступны только мастеру |
| GET/POST `/characters/?campaign=ID` | Список / создать собственного персонажа |
| GET/PATCH `/characters/{id}/?campaign=ID` | Прочитать / владелец или мастер меняет поля |
| GET/POST `/campaigns/{id}/sessions/` | Сессии / мастер создаёт `{name, date?, settings?}` |
| PATCH `/sessions/{id}/?campaign=ID` | Мастер меняет незавершённую сессию |
| POST `/sessions/{id}/start/` | Начать planned-сессию; только одна active в кампании |
| POST `/sessions/{id}/finish/` | Закончить, истечь неиспользованные результаты и запросы |

Character: name, character_class, level 1–30, species, description, avatar URL, active. Campaign settings: edition (`5e-2014`, `5e-2024`, `custom`), effect_limit 0–10, quest_limit 0–10, category_weights `{gift,complication,paradox}`, casino_enabled, initial_balance 0–1000000. Настройки сессии — необязательные переопределения тех же полей; initial_balance остаётся настройкой создания кошелька кампании.

## Эффекты и задания

| Method/path | Body / результат |
|---|---|
| GET `/effects/` | Библиотека без secret; category, rarity, search, ordering, page |
| GET `/quests/` | Библиотека; category, difficulty, search, ordering, page |
| POST `/sessions/{id}/effects/roll/` | `{character: ID}` → сохранённый EffectRoll |
| POST `/sessions/{id}/quests/roll/` | `{character: ID}` → QuestAssignment |
| GET `/sessions/{id}/effects/my/` | Свои результаты сессии |
| GET `/sessions/{id}/quests/my/` | Свои задания сессии |
| POST `/active-effects/{id}/use/` | `{note?: string}` → used либо pending_approval |
| POST `/active-effects/{id}/request-approval/` | `{note: string}` — явное согласование |
| POST `/active-effects/{id}/choose/` | `{index: 0..2}` для сохранённого выбора из трёх |
| POST `/quest-assignments/{id}/submit/` | `{evidence: string}` → pending_verification |
| GET `/history/effects/`, `/history/quests/` | Пагинация; дополнительные фильтры session, character |
| GET `/exchanges/` | Свои запросы, входящие согласия; мастер видит все |
| POST `/exchanges/` | `{source: rollID, offered: rollID, target: characterID, requested?: rollID}` |
| POST `/exchanges/{id}/consent/` | Получатель: `{accept: boolean}` |
| GET `/feed/` | Собственные события и достижения; мастер видит аудит кампании |

Эффекты №90 и №91 используют endpoint exchanges. offered/requested должны быть неиспользованными активными карточками одной сессии; для №90 offered — дар. После согласия получателя мастер решает применимость. Поле issued_to сохраняет первоначальную выдачу; передача не восстанавливает лимит розыгрышей.

№119 создаёт право на следующий выбор; после его использования следующая выдача возвращает status rolled и choices. Выбор одной карточки окончателен, №119 и другие choice3-механики исключены из предложений. Secret удаляется рекурсивно из snapshots и choices обычного игрока.

## Казино

- GET `/casino/games/`: 7 конфигураций, версия, лимиты, rules и math.
- GET `/casino/wallet/`: `{id, balance}`.
- GET `/casino/transactions/`: страницы ledger, фильтр kind, ordering.
- GET `/casino/rounds/`: страницы своих раундов; фильтры game, status.
- GET `/casino/stats/`: по каждой игре rounds, stakes, payouts, profit.
- POST `/casino/{game}/rounds/`: создать раунд с обязательным ключом.
- POST `/casino/rounds/{id}/actions/`: серверное действие карточной игры.

Игры: `roulette`, `slots`, `blackjack`, `dice`, `coin`, `higher-lower`, `lucky-wheel`.

Создание простых игр:

```json
{"stake": 5, "choice": "heads"}
```

Coin choice: heads/tails; Dice: low/seven/high либо строка конкретной суммы `"2"`…`"12"`. Slots/Lucky Wheel/Blackjack/Higher or Lower — только stake. Stakes — целые жетоны в заданных лимитах. Баланс и выплаты хранятся с точностью 0,01 ST.

Roulette:

```json
{"bets":[{"kind":"red","amount":5},{"kind":"number","value":17,"amount":5},{"kind":"dozen","value":2,"amount":5}]}
```

Kinds: number/red/black/even/odd/low/high/dozen. Число 0–36, дюжина 1–3. До 40 ставок, общий размер тоже ограничен max_bet. Ноль проигрывает внешним ставкам. Множители по умолчанию: 36 / 2 / 3 gross.

Blackjack actions: `{action:"hit"}`, `{action:"stand"}`, `{action:"double"}`. После раздачи сервер проверяет natural blackjack у обеих сторон. Удвоение требует двух карт и дополнительного баланса, после чего выдаётся ровно одна карта и ход заканчивается. Дилер по умолчанию стоит на soft 17. Пока раунд активен, клиент получает только открытую карту дилера; deck/private_state не сериализуются. Колода на раунд: 52 карты без повторов.

Higher or Lower создаётся в два этапа: начальная ставка фиксируется и открывается current; ответ содержит odds для higher/lower. Затем `{action:"higher"}` или `{action:"lower"}` открывает следующую карту. Туз = 14. Невозможное направление запрещено. Колода новая на каждый раунд; при выборе остаётся 51 карта.

При push-равенстве множитель выигрыша равен `(N − ties) / wins × (1 − edge)`. Ожидаемая полная выплата до округления: `(1 − edge) × (1 − p_tie) + p_tie`; при lose-равенстве — `1 − edge`. В серверном ответе сохранены реальные вероятности и использованный множитель. Выбор не меняет состав колоды или вероятность конкретного игрока.

Одновременно у пользователя в кампании допускается один открытый карточный раунд. Игру можно отключить для новых ставок; существующий раунд разрешено завершить. Завершение сессии и отключение участника запрещены, пока у него есть незавершённый раунд.

Каждый public round содержит id, game, status, stake, payout (полная выплата), profit (только завершённые раунды), result, rules snapshot, created_at. Множители gross включают первоначальную ставку; payout − stake = profit. Округление вниз до 0,01 ST. Private_state, включая будущие карты, не возвращается даже мастеру через журнальный API.

Lucky Wheel: одинаковые размеры секторов служат визуализацией, вероятность определяется опубликованными весами. Slots: три независимых взвешенных выбора; три одинаковых символа дают их multiplier; ровно два одинаковых — pair_multiplier. Одна линия. Математика определяется этими же правилами, не имитацией исходов.

## Панель мастера

Все endpoints под `/dm/` проверяют роль dm в выбранной кампании:

- GET `/dm/overview/`: участники, кошельки, последние 100 эффектов/квестов, ожидающие запросы, статистика карточек.
- GET/POST/PATCH/DELETE `/dm/effects/` и `/dm/quests/`: CRUD собственного контента; DELETE архивирует. Базовая библиотека доступна только для чтения и копирования.
- POST `/dm/{effects|quests}/{id}/copy/`: независимая копия в кампании.
- GET `/dm/{effects|quests}/export/?file_format=json|csv`: `{format, content}`. Это JSON-ответ; content для CSV — строка.
- POST `/dm/{effects|quests}/import/`: `{format, content}`; до 500 объектов, импорт целиком атомарен. Повторные стабильные codes обновляют только контент текущей кампании. Глобальная библиотека и чужие записи неизменяемы.
- PATCH `/dm/config/{game}/`: enabled, min_bet, max_bet, rules. Версия увеличивается; открытые раунды используют прежний snapshot.
- GET/POST `/dm/pools/`: `{id?,name,active,entries:[{effect_id,weight}]}`.
- GET `/dm/history/{audit|rounds|transactions}/`: страницы истории.
- POST `/dm/actions/{kind}/{id}/`: операции ниже.

| Kind | ID | Body |
|---|---|---|
| quest | Assignment ID | `{approve:boolean,note?:string}` |
| effect | Approval request ID | `{approve:boolean,note?:string}` |
| exchange | Exchange ID | `{approve:boolean}` после согласия получателя |
| member | Membership ID | `{role?:"dm"|"player",active?:boolean}` |
| wallet | Wallet ID | `{amount:string,note:string}`; отрицательная сумма списывает |
| assign-effect | Definition ID | `{character,session}`; дополнительная выдача |
| reroll | 0 (не используется) | `{character,session}`; дополнительная случайная карточка |
| assign-quest | Definition ID | `{character,session}`; лимит заданий сохраняется |
| cancel-effect | Roll ID | `{}`; только active/rolled |
| cancel-quest | Assignment ID | `{}`; завершённое задание не отменяется |

Списки DRF пагинированы по 30 и имеют `count,next,previous,results` внутри data. Общие поиск/сортировка доступны на библиотеке, персонажах, кампаниях и ledger; сервер разрешает только перечисленные поля ordering. Небольшие агрегаты (сессии кампании, конфигурации, наборы, overview) возвращаются целиком. UI overview ограничен последними 100 результатами, журнал казино и транзакций — постраничный.

## Readiness

`GET /api/health/` выполняет SELECT 1. Ответ 200: `{ "data": { "status": "ok" }, "error": null }`. При ошибке БД — 503 без внутренних деталей. Не создаёт сессию и не расходует пользовательские лимиты запросов.

## Общая комната, листы и броски

Ниже все REST-запросы получают `?campaign=ID`; изменяющие запросы — CSRF и Idempotency-Key. Роль и принадлежность проверяются внутри транзакции. На лист/способности нужен владелец персонажа либо мастер. Публичная комната не возвращает полный лист и личные записи.

| Method/path | Назначение / body |
|---|---|
| GET `/room/` | `revision`, активная session, party с публичными хитами/КД/состояниями, initiative. `view=player` исключает скрытую информацию даже у мастера |
| GET `/room/events/` | Пагинация журнала; `session=ID`, `view=player`. Обычному игроку только public |
| GET `/characters/{id}/sheet/` | Лист и computed: modifiers, skills, saves, proficiency, initiative, spell_attack, spell_dc |
| PATCH `/characters/{id}/sheet/` | `{version, ...изменённые поля}`; версия обязательна, несовпадение → 409 |
| POST `/characters/{id}/resources/` | `{action, amount?, version?}`: damage, heal, temporary, restore_slots. Для restore_slots обязательна версия листа |
| GET/POST `/characters/{id}/abilities/` | Активные атаки/заклинания / создать действие |
| PATCH `/abilities/{id}/` | `{version,...поля}`; `{version,active:false}` архивирует действие |
| POST `/abilities/{id}/use/` | `{slot_level?, mode?, visibility?}` → сохранённое событие; ячейка и результат атомарны |
| POST `/room/rolls/` | `{character,kind,key?,formula?,mode?,visibility?}` → сохранённое событие |
| POST `/room/initiative/` | Только мастер: `{version,action,...параметры}` → новая версия трекера |

`kind` броска: `ability`, `save`, `skill`, `initiative`, `death`, `custom`. `key`: str/dex/con/int/wis/cha для характеристик и спасбросков; acrobatics, animal_handling, arcana, athletics, deception, history, insight, intimidation, investigation, medicine, nature, perception, performance, persuasion, religion, sleight_of_hand, stealth, survival для навыков. `mode`: normal/advantage/disadvantage. `visibility`: public/dm. Для custom нужен normal. Мастер может передать `character:null` для custom; игрок — нет.

Пример проверки:

```json
{"character":12,"kind":"skill","key":"arcana","mode":"advantage","visibility":"public"}
```

Числа и бонусы вычисляются по сохранённому листу; клиентские `total` и `modifier` не используются. Формулы содержат только сложение/вычитание целых и кубиков d4/d6/d8/d10/d12/d20/d100. Лимит 50 кубиков, 80 символов; Python eval не используется.

Лист: abilities — все шесть значений 1…30; skills — карта ключей со значением 0/1/2 (нет/владение/экспертиза), saves — список характеристик с владением, slots — ключи "1"…"9" с `{max,used}` и `0≤used≤max≤20`. Дополнительные поля: hp_max/current/temp, armor_class, speed, initiative_bonus, proficiency_override (null = по уровню), spell_ability, conditions, death_successes/failures, inventory, background, notes. Полный набор доступен в OpenAPI. PATCH частичный, но переданная abilities или slots должна быть целой картой.

Способность: kind attack/spell, name, description, ability, proficient, bonus, resolution attack/save/automatic, dice, add_modifier, damage_type, level, upcast_dice, roll_count (1…20), upcast_count (0…5), cantrip_scaling, save_ability, casting_time, range, duration, concentration, active.

`steps = (slot_level − level) // upcast_every` для заклинания с формулой (обычно `upcast_every=1`, у «Духовного оружия» — 2). Для заговора с cantrip_scaling — количество достигнутых порогов 5/11/17. Итоговое число отдельных бросков `roll_count + steps × upcast_count`, максимум 20. У каждого свои атака/критический результат и базовые dice плюс steps экземпляров upcast_dice. Постоянные значения формулы при критическом попадании не удваиваются. Для каталожных заклинаний в журнале доступны `spell_attack_bonus`, `spell_save_dc`, `possible_saves` и снимок механических примечаний. Для проверенной формулы спасброска поле `save` содержит `ability`, `dc`, `failed_damage` и `success_damage` (половина округляется вниз). При отложенном эффекте первый бросок предварительный: условие его применения видно в `adjudication`. Спасброски целей и применение урона не автоматизированы.

При одном броске payload содержит roll/damage/save/upcast, при нескольких — parts с такими же полями и total_damage. Кроме того сохраняются название, описание, имя персонажа, ability_id, ability_version, slot_level, damage_type, concentration. Полный результат и списание ячейки фиксируются до ответа клиенту. Изменение определения не пересчитывает историю.

Инициатива: add (`character` или `name`, `initiative`, `hidden`), edit (`entry`, `initiative?`, `hidden?`), remove (`entry`), start, next, stop, reset. Изменение списка разрешено на паузе. Для первого пустого трекера используйте version 0; далее — возвращённую version. Повтор ключа не двигает ход повторно; другой ключ со старой версией возвращает 409. Игрок добавляет собственную запись через kind initiative, только один раз до её удаления/сброса мастером.

### SSE

`GET /api/campaigns/{id}/stream/` — отдельный ответ `text/event-stream`, **без JSON envelope**. Требуются session cookie и активное членство. Можно передать `Last-Event-ID` или query `after` с последней ревизией.

```text
id: 123
event: change
data: {"revision":123}
```

Строки разделяются newline, события — пустой строкой. `change` означает перечитать защищённые REST-ресурсы. Событие `revoked` прекращает доступ. Heartbeat раз в секунду; поток ограничен примерно 25 секундами, затем EventSource автоматически переподключается с retry 1500 мс. Номер ревизии берётся из закоммиченного AuditLog, поэтому работает между несколькими процессами. Доступ проверяется также во время потока. Уведомление не содержит скрытых данных.

### Каталог заклинаний

- `GET /api/spells/catalog/?campaign=ID&q=текст&level=0..9&offset=0` — участники кампании; страницы по 30 записей, русский/английский поиск, `count` и `results`.
- `POST /api/characters/{id}/spells/catalog/?campaign=ID` с `{"spell_id": ID}` и `Idempotency-Key` — добавление готового заклинания владельцем или мастером. Повторное добавление той же активной записи возвращает существующее действие.
- В ответе `GET /api/characters/{id}/abilities/` поле `upcast_allowed` сообщает, можно ли выбирать ячейку выше уровня заклинания. `POST /api/abilities/{id}/use/` перепроверяет право и наличие ячейки на сервере. Для повторного срабатывания поддерживаемого заклинания отправьте `{"trigger": true}` на тот же адрес: сервер использует уровень последнего наложения в текущей сессии без нового расхода ячейки. Для концентрационных заклинаний требуется активное состояние «Концентрация» в листе; условия срабатывания контролируются игроком и мастером.
