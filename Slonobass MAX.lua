-- Slonobass MAX — скрипт для SandFly.
--
-- Версия 1.0: при открытии приложения фокус встаёт на первый чат в списке
-- чатов. Дальше можно сразу идти по чатам свайпом, не отыскивая список
-- вручную. В открытом чате, звонках, настройках и на других экранах скрипт
-- фокус не трогает: признак внутреннего экрана — кнопка «Назад» вверху, а
-- экран чатов узнаётся по вкладкам папок или по шапке «Чаты» с нижней
-- панелью.
--
-- Списков чатов в дереве несколько: по одному на каждую папку, а папки лежат
-- в переключателе страниц. Видимая только одна страница, поэтому список
-- выбирается по видимости и площади — самый большой видимый прокручиваемый
-- список на экране и есть список чатов. Если фокус уже стоит внутри списка,
-- скрипт его не отбирает: иначе он дёргал бы фокус при каждом возврате на
-- экран чатов и при каждом обновлении списка.
--
-- В настройках скрипта переключатель «Фокус на первый чат». В меню команд —
-- «Перейти к первому чату»: тот же переход вручную, если фокус уехал.

local manifest = {
  id = 'wam.max-actions',
  name = 'Slonobass MAX',
  version = '1.0',
  author = 'Алёшка',
  minApiVersion = 2,
  testedApiVersion = 5,
  description = 'При открытии приложения фокус встаёт на первый чат в списке чатов: дальше можно сразу идти по чатам свайпом. В открытом чате и на других экранах фокус не трогает. В настройках — переключатель «Фокус на первый чат», в меню команд — «Перейти к первому чату».',
  apps = { 'ru.oneme.app' },
  permissions = { 'screen', 'speech', 'input', 'actions' },
  commands = {
    { id = 'focus_first_chat', title = 'Перейти к первому чату', menu = true },
  },
  settings = {
    {
      key = 'focusFirstChat',
      type = 'switch',
      title = 'Фокус на первый чат',
      summary = 'При открытии приложения и при входе на экран чатов фокус встаёт на первый чат в списке',
      default = true,
    },
  },
}

-- ── Экран чатов ──

-- Площадь элемента по границам: из нескольких списков на экране главный —
-- самый большой.
local function area(item)
  local b = item and item.bounds
  if not b then
    return 0
  end
  local w = b.right - b.left
  local h = b.bottom - b.top
  if w <= 0 or h <= 0 then
    return 0
  end
  return w * h
end

-- Самый крупный видимый прокручиваемый список на экране: список чатов.
-- Скрытые списки — истории над чатами и списки соседних папок в переключателе
-- страниц — не в счёт, даже если они больше по размеру.
local function findMainList(timeout)
  local first = sf.screen.waitFor({ scrollable = true }, timeout or 8000, 300)
  if not first then
    return nil
  end
  local best = nil
  local bestArea = 0
  local function consider(item)
    if item and item.visible then
      local a = area(item)
      if a > bestArea then
        best = item
        bestArea = a
      end
    end
  end
  consider(first)
  local lists = sf.screen.findAll({ scrollable = true }, 30)
  if lists then
    for _, item in ipairs(lists) do
      consider(item)
    end
  end
  -- Видимых списков нет: отдаём первый найденный, строк в нём всё равно не
  -- будет и фокус останется на месте.
  if not best then
    return first
  end
  return best
end

-- Кнопка «Назад» вверху — признак открытого чата, звонков, настроек или
-- другого внутреннего экрана. На экране чатов её нет.
local function insideSubScreen()
  local queries = {
    { contentDescription = 'Назад' },
    { contentDescription = 'Back' },
    { className = 'ImageButton', textContains = 'назад' },
    { className = 'ImageButton', textContains = 'back' },
    { text = 'Назад' },
  }
  for _, query in ipairs(queries) do
    if sf.screen.find(query) then
      return true
    end
  end
  return false
end

-- Надпись на экране: вкладки папок и шапку приложение может отдавать и
-- текстом, и описанием.
local function seenLabel(label)
  return sf.screen.find({ text = label }) ~= nil
    or sf.screen.find({ contentDescription = label }) ~= nil
end

-- Экран чатов. Надёжнее всего его выдают вкладки папок: «Все», «Личные»,
-- «Каналы». Если папок нет, остаются шапка «Чаты» и нижняя панель с
-- «Настройками».
local function onChatsScreen()
  if insideSubScreen() then
    return false
  end
  local tabs = 0
  for _, label in ipairs({ 'Все', 'Личные', 'Каналы' }) do
    if seenLabel(label) then
      tabs = tabs + 1
    end
  end
  if tabs >= 2 then
    return true
  end
  return seenLabel('Чаты') and sf.screen.find({ contentDescription = 'Настройки' }) ~= nil
end

-- Элемент внутри этого списка: поднимаемся по родителям.
local function isInside(parent, item)
  local cur = item
  for _ = 1, 12 do
    if not cur then
      return false
    end
    cur = cur:parent()
    if not cur then
      return false
    end
    if cur == parent then
      return true
    end
  end
  return false
end

-- Первый чат списка — первая живая строка. У строки чата заполнено описание:
-- имя, начало последнего сообщения, время и пометка о непрочитанном.
local function firstChatRow(list)
  local rows = list:findAll({ focusable = true }, 60)
  if not rows then
    return nil
  end
  local fallback = nil
  for _, row in ipairs(rows) do
    if row.visible then
      local label = row.contentDescription
      if label == nil or label == '' then
        label = row.text
      end
      if label ~= nil and label ~= '' then
        if not fallback then
          fallback = row
        end
        -- Строка списка: у неё заполнено collectionItem.
        if row.collectionItem then
          return row
        end
      end
    end
  end
  return fallback
end

-- Фокус внутри этого списка. Сам контейнер считается тоже: SandFly отдаёт
-- фокус контейнеру, когда строки его не берут.
local function focusedInList(list, cur)
  if not cur then
    return false
  end
  if cur == list then
    return true
  end
  return isInside(list, cur)
end

-- Одного перевода мало: приложение дорисовывает список уже после нас и может
-- увести фокус на шапку. Поэтому после каждой попытки смотрим, где фокус
-- оказался, и, если он не в списке, переводим снова.
local FOCUS_TRIES = 3
local FOCUS_STEP = 350

-- Переводит фокус на первый чат и убеждается, что он остался в списке.
-- Возвращает признак успеха; список к концу может быть уже другим узлом.
local function placeFocus(list)
  if focusedInList(list, sf.screen.focused()) then
    return true
  end
  for _ = 1, FOCUS_TRIES do
    local row = firstChatRow(list)
    if row then
      pcall(function()
        row:focus()
      end)
    end
    sf.sleep(FOCUS_STEP)
    if focusedInList(list, sf.screen.focused()) then
      return true
    end
    -- Пользователь мог сам открыть чат — тогда больше не лезем.
    if not onChatsScreen() then
      return false
    end
    -- Экран перерисовался: список берём заново, старый узел мог устареть.
    local again = findMainList(500)
    if again then
      list = again
    end
  end
  return false
end

-- ── Автоматический переход ──

-- Поколение окна: при смене окна и при входе в приложение попытка делается
-- заново, а в пределах одного экрана — один раз, чтобы не дёргать фокус.
local generation = 0
local handledGeneration = -1
local attemptRunning = false

local function maybeFocus()
  if sf.settings.get('focusFirstChat') == false then
    return
  end
  if handledGeneration == generation then
    return
  end
  local myGeneration = generation
  sf.run(function()
    if attemptRunning then
      return
    end
    attemptRunning = true
    local list = findMainList(6000)
    -- Пока ждали список, мог открыться чат или другой экран.
    if list and onChatsScreen() then
      if placeFocus(list) and myGeneration == generation then
        handledGeneration = myGeneration
      end
    end
    attemptRunning = false
  end)
end

sf.onAppEnter(function()
  generation = generation + 1
  maybeFocus()
end)

sf.onWindowChange(function()
  generation = generation + 1
  maybeFocus()
end)

-- Список чатов при входе может дорисоваться позже окна. Пока переход ещё не
-- сделан, изменение содержимого — повод попробовать снова; после успеха
-- скрипт молчит до следующей смены окна.
sf.onContentChange(function()
  if handledGeneration ~= generation then
    maybeFocus()
  end
end)

-- ── Ручной переход ──

-- SandFly → Команды → «Перейти к первому чату».
sf.onCommand('focus_first_chat', function()
  local list = findMainList(3000)
  if not list or not onChatsScreen() then
    sf.speak('Список чатов не найден')
    return
  end
  if not placeFocus(list) then
    if not onChatsScreen() then
      sf.speak('Открыт не список чатов')
    else
      sf.speak('Первый чат не найден')
    end
  end
end)

print('MAX: фокус на первый чат, версия 1.0 загружена')
