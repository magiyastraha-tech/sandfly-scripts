-- Slonobass AntennaPod — скрипт для SandFly.
--
-- Версия 1.1: кнопка «Отметить как прочитанное» (и «Отметить как проигранное»)
-- у строки выпуска убрана из свайпа: обход идёт только по выпускам. Сама
-- кнопка остаётся в дереве экрана, поэтому нажать её вручную по-прежнему можно.
--
-- Версия 1.0: при открытии AntennaPod фокус встаёт на первый выпуск в списке
-- новостей на вкладке «Выпуски». Дальше можно сразу идти по выпускам свайпом,
-- не отыскивая список вручную.
--
-- Список узнаётся по id recyclerView внутри overview_coordinator_layout.
-- Такой же id AntennaPod отдаёт и на других вкладках, поэтому скрипт
-- срабатывает только когда внизу выбрана вкладка «Выпуски»
-- (bottom_navigation_episodes). На «Подписках», «Очереди», «Загрузках»,
-- в поиске, в карточке выпуска и в проигрывателе фокус не трогает.
--
-- Строка выпуска содержит дату публикации (txtvPubDate): по ней скрипт и
-- выбирает из списка настоящую строку выпуска, а не заголовок или кнопку.
--
-- В настройках скрипта переключатели «Фокус на первый выпуск» и «Скрывать
-- кнопку отметки». В меню команд — «Перейти к первому выпуску»: тот же переход
-- вручную, если фокус уехал.

local manifest = {
  id = 'wam.antennapod-first-episode',
  name = 'Slonobass AntennaPod',
  version = '1.1',
  author = 'Алёшка',
  minApiVersion = 2,
  testedApiVersion = 5,
  description = 'При открытии AntennaPod фокус встаёт на первый выпуск в списке новостей на вкладке «Выпуски»: дальше можно сразу идти по выпускам свайпом. Кнопки «Отметить как прочитанное» и «Отметить как проигранное» убраны из свайпа, обход идёт только по выпускам. На других вкладках, в поиске, в карточке выпуска и в проигрывателе фокус не трогает. В настройках — переключатели «Фокус на первый выпуск» и «Скрывать кнопку отметки», в меню команд — «Перейти к первому выпуску».',
  apps = { 'de.danoeh.antennapod' },
  permissions = { 'screen', 'speech', 'input', 'actions' },
  commands = {
    { id = 'focus_first_episode', title = 'Перейти к первому выпуску', menu = true },
  },
  settings = {
    {
      key = 'focusFirstEpisode',
      type = 'switch',
      title = 'Фокус на первый выпуск',
      summary = 'При открытии приложения фокус встаёт на первый выпуск в списке новостей',
      default = true,
    },
    {
      key = 'hideMarkRead',
      type = 'switch',
      title = 'Скрывать кнопку отметки',
      summary = 'Кнопки «Отметить как прочитанное» и «Отметить как проигранное» уходят из свайпа, обход идёт только по выпускам',
      default = true,
    },
  },
}

local LIST_ID = 'recyclerView'
local CONTAINER_ID = 'overview_coordinator_layout'
local EPISODES_TAB_ID = 'bottom_navigation_episodes'
local DATE_ID = 'txtvPubDate'
local ACTION_ID = 'secondaryActionButton'

-- Подписи кнопки отметки: у выпуска без звука — «прочитанное», со звуком —
-- «проигранное». Английские варианты — на случай другой локали приложения.
local MARK_LABELS = {
  'Отметить как прочитанное',
  'Отметить как проигранное',
  'Mark as read',
  'Mark as played',
}

-- ── Правила ──

-- Кнопка отметки у строки выпуска кликабельна, но не фокусируема; SandFly
-- всё равно может ставить на неё фокус при свайпе. hide = true убирает её
-- из обхода, но оставляет в дереве — ручное нажатие по-прежнему работает.
local ruleIds = {}

local function clearRules()
  for i = 1, #ruleIds do
    pcall(sf.rules.remove, ruleIds[i])
  end
  ruleIds = {}
end

local function addRule(rule)
  local ok, number = pcall(sf.rules.add, rule)
  if ok and number then
    ruleIds[#ruleIds + 1] = number
  end
end

local function applyRules()
  clearRules()
  if sf.settings.get('hideMarkRead') == false then
    return
  end
  for _, label in ipairs(MARK_LABELS) do
    addRule({
      match = {
        id = ACTION_ID,
        contentDescription = label,
        inside = { id = LIST_ID },
      },
      hide = true,
    })
  end
end

-- ── Экран выпусков ──

-- Вкладка «Выпуски» выбрана. Основной признак — выбранный пункт нижнего меню;
-- запасной — кнопка фильтра, которой на других вкладках нет.
local function onEpisodesTab()
  local ok, tab = pcall(function()
    return sf.screen.find({ id = EPISODES_TAB_ID, selected = true })
  end)
  if ok and tab then
    return true
  end
  local filter = sf.screen.find({ id = 'filter_items' })
  local lists = sf.screen.findAll({ id = LIST_ID }, 5)
  return filter ~= nil and lists ~= nil and #lists > 0
end

-- Список выпусков. Основной путь — по id внутри контейнера вкладки.
-- Запасной — по одному id, но только на вкладке «Выпуски», иначе скрипт
-- может схватить чужой список.
local function findEpisodeList(timeout)
  local ok, list = pcall(function()
    return sf.screen.waitFor({ id = LIST_ID, inside = { id = CONTAINER_ID } }, timeout or 8000, 300)
  end)
  if ok and list then
    return list
  end
  if not onEpisodesTab() then
    return nil
  end
  ok, list = pcall(function()
    return sf.screen.waitFor({ id = LIST_ID }, timeout or 1500, 300)
  end)
  if ok and list then
    return list
  end
  return nil
end

-- Строка выпуска содержит дату публикации: этим она отличается от заголовков
-- и служебных строк.
local function hasDate(row)
  local ok, date = pcall(function()
    return row:find({ id = DATE_ID })
  end)
  return ok and date ~= nil
end

-- Первый выпуск списка — первая живая строка. Если дату найти не удалось,
-- берём первую строку коллекции, затем любой фокусируемый объект списка.
local function firstEpisodeRow(list)
  local rows = list:findAll({ focusable = true }, 60)
  if not rows then
    return nil
  end
  local byShape = nil
  local any = nil
  for _, row in ipairs(rows) do
    if row.visible and row ~= list then
      if hasDate(row) then
        return row
      end
      if row.collectionItem and not byShape then
        byShape = row
      end
      if not any then
        any = row
      end
    end
  end
  return byShape or any
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

-- Фокус стоит на этой строке или на её части.
local function onRow(row, cur)
  if not row or not cur then
    return false
  end
  if cur == row then
    return true
  end
  return isInside(row, cur)
end

-- Одного перевода мало: приложение дорисовывает список уже после нас и может
-- увести фокус. Поэтому после каждой попытки смотрим, где фокус оказался,
-- и, если он не на первом выпуске, переводим снова.
local FOCUS_TRIES = 3
local FOCUS_STEP = 350

-- force = true — вход в приложение или команда: ставим фокус на первый
-- выпуск всегда, даже если он остался на другой строке с прошлого раза.
-- Без force фокус переводим только тогда, когда он нигде или на самом
-- списке: человек уже стоит на строке, в поиске или в карточке — не мешаем.
local function placeFocus(list, force)
  local cur = sf.screen.focused()
  if not force then
    if focusedInList(list, cur) then
      return true
    end
    if cur ~= nil and cur ~= list then
      return false
    end
  elseif onRow(firstEpisodeRow(list), cur) then
    return true
  end
  for _ = 1, FOCUS_TRIES do
    local row = firstEpisodeRow(list)
    if row then
      pcall(function()
        row:focus()
      end)
    end
    sf.sleep(FOCUS_STEP)
    cur = sf.screen.focused()
    if onRow(row, cur) then
      return true
    end
    -- Экран перерисовался: список берём заново, старый узел мог устареть.
    local again = findEpisodeList(500)
    if not again then
      return false
    end
    list = again
  end
  return false
end

-- ── Автоматический переход ──

-- Поколение окна: при смене окна и при входе в приложение попытка делается
-- заново, а в пределах одного экрана — один раз, чтобы не дёргать фокус.
local generation = 0
local handledGeneration = -1
local attemptRunning = false

local function maybeFocus(force)
  if sf.settings.get('focusFirstEpisode') == false then
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
    local list = findEpisodeList(force and 12000 or 5000)
    if list then
      local cur = sf.screen.focused()
      local ok
      if force or cur == nil or cur == list then
        ok = placeFocus(list, force)
      else
        -- Фокус уже на строке списка, в поиске или в карточке — не трогаем.
        ok = true
      end
      if ok and myGeneration == generation then
        handledGeneration = myGeneration
      end
    end
    attemptRunning = false
  end)
end

sf.onAppEnter(function()
  generation = generation + 1
  applyRules()
  maybeFocus(true)
end)

sf.onWindowChange(function()
  generation = generation + 1
  local cur = sf.screen.focused()
  local kind = cur and cur.className
  -- Человек печатает в поиске — окно сменилось из-за клавиатуры или
  -- подсказок, фокус не трогаем.
  if kind == 'EditText' or kind == 'AutoCompleteTextView' then
    handledGeneration = generation
    return
  end
  maybeFocus(false)
end)

-- Список выпусков при входе может дорисоваться позже окна. Пока переход ещё
-- не сделан, изменение содержимого — повод попробовать снова; после успеха
-- скрипт молчит до следующей смены окна.
sf.onContentChange(function()
  if handledGeneration ~= generation then
    maybeFocus(false)
  end
end)

-- ── Ручной переход ──

-- SandFly → Команды → «Перейти к первому выпуску».
sf.onCommand('focus_first_episode', function()
  local list = findEpisodeList(3000)
  if not list then
    sf.speak('Список выпусков не найден')
    return
  end
  if not placeFocus(list, true) then
    sf.speak('Первый выпуск не найден')
  end
end)

sf.onSettingChange(function(key)
  if key == 'hideMarkRead' then
    applyRules()
  end
end)

-- Правила ставим сразу при загрузке: скрипт грузится, когда приложение выходит
-- вперёд.
applyRules()

print('AntennaPod: фокус на первый выпуск, кнопка отметки убрана из свайпа, версия 1.1 загружена')
