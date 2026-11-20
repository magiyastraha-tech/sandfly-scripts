-- Slonobass TeamTalk — скрипт для SandFly.
--
-- Версия 1.0: при открытии TeamTalk фокус встаёт на первый сервер в списке
-- серверов. Дальше можно сразу идти по серверам свайпом, не отыскивая список
-- вручную. Внутри сервера, в поиске и в диалогах скрипт фокус не трогает.
--
-- Список серверов узнаётся по id servers_recycler_view: он один на всём
-- экране ServerListActivity. Строка сервера — фокусируемый объект внутри
-- списка, у которого есть имя сервера (server_name). Если сборка не отдаст
-- id, список ищется рядом с кнопкой «НОВЫЙ СЕРВЕР», чтобы не спутать его
-- с чужим списком — например, со списком каналов внутри сервера.
--
-- В настройках скрипта переключатель «Фокус на первый сервер». В меню команд —
-- «Перейти к первому серверу»: тот же переход вручную, если фокус уехал.

local manifest = {
  id = 'wam.teamtalk-first-server',
  name = 'Slonobass TeamTalk',
  version = '1.0',
  author = 'Алёшка',
  minApiVersion = 2,
  testedApiVersion = 5,
  description = 'При открытии TeamTalk фокус встаёт на первый сервер в списке серверов: дальше можно сразу идти по серверам свайпом. Внутри сервера, в поиске и в диалогах фокус не трогает. В настройках — переключатель «Фокус на первый сервер», в меню команд — «Перейти к первому серверу».',
  apps = { 'dk.bearware.gui' },
  permissions = { 'screen', 'speech', 'input', 'actions' },
  commands = {
    { id = 'focus_first_server', title = 'Перейти к первому серверу', menu = true },
  },
  settings = {
    {
      key = 'focusFirstServer',
      type = 'switch',
      title = 'Фокус на первый сервер',
      summary = 'При открытии приложения фокус встаёт на первый сервер в списке',
      default = true,
    },
  },
}

local LIST_ID = 'servers_recycler_view'
local NAME_ID = 'server_name'

-- ── Экран списка серверов ──

-- Площадь элемента по границам: нужна только запасному поиску списка.
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

-- Список серверов. Основной путь — по id. Если query с id в этой сборке не
-- работает, список ищем только на экране с кнопкой «НОВЫЙ СЕРВЕР»: одного
-- прокручиваемого списка на экране мало, внутри сервера он тоже есть.
local function findServerList(timeout)
  local ok, list = pcall(function()
    return sf.screen.waitFor({ id = LIST_ID }, timeout or 8000, 300)
  end)
  if ok and list then
    return list
  end
  local marker = sf.screen.find({ textContains = 'НОВЫЙ СЕРВЕР' })
    or sf.screen.find({ textContains = 'NEW SERVER' })
  if not marker then
    return nil
  end
  local best = nil
  local bestArea = 0
  local lists = sf.screen.findAll({ scrollable = true }, 20)
  if lists then
    for _, item in ipairs(lists) do
      if item.visible then
        local a = area(item)
        if a > bestArea then
          best = item
          bestArea = a
        end
      end
    end
  end
  return best
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

-- Строка сервера содержит имя сервера. Проверка по id — самая надёжная:
-- у строки в дереве есть server_name и server_summary.
local function hasServerName(row)
  local ok, name = pcall(function()
    return row:find({ id = NAME_ID })
  end)
  return ok and name ~= nil
end

-- Первый сервер списка — первая живая строка. Если имя сервера найти не
-- удалось, берём первую строку-элемент коллекции, затем первую похожую на
-- строку по типу, и в последнюю очередь — любой фокусируемый объект списка.
local function firstServerRow(list)
  local rows = list:findAll({ focusable = true }, 60)
  if not rows then
    return nil
  end
  local byShape = nil
  local any = nil
  for _, row in ipairs(rows) do
    if row.visible and row ~= list then
      if hasServerName(row) then
        return row
      end
      if row.collectionItem and not byShape then
        byShape = row
      end
      if row.className == 'RelativeLayout' and not byShape then
        byShape = row
      end
      if not any then
        any = row
      end
    end
  end
  return byShape or any
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
-- и, если он не на первом сервере, переводим снова.
local FOCUS_TRIES = 3
local FOCUS_STEP = 350

-- force = true — вход в приложение: ставим фокус на первый сервер всегда,
-- даже если он остался на другой строке с прошлого раза.
-- Без force фокус переводим только тогда, когда он нигде или на самом
-- списке: человек уже стоит на строке, в поиске или в диалоге — не мешаем.
local function placeFocus(list, force)
  local cur = sf.screen.focused()
  if not force then
    if focusedInList(list, cur) then
      return true
    end
    if cur ~= nil and cur ~= list then
      return false
    end
  elseif onRow(firstServerRow(list), cur) then
    return true
  end
  for _ = 1, FOCUS_TRIES do
    local row = firstServerRow(list)
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
    local again = findServerList(500)
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
  if sf.settings.get('focusFirstServer') == false then
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
    local list = findServerList(force and 12000 or 5000)
    if list then
      local cur = sf.screen.focused()
      local ok
      if force or cur == nil or cur == list then
        ok = placeFocus(list, force)
      else
        -- Фокус уже на строке списка, в поиске или в диалоге — не трогаем.
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

-- Список серверов при входе может дорисоваться позже окна. Пока переход ещё
-- не сделан, изменение содержимого — повод попробовать снова; после успеха
-- скрипт молчит до следующей смены окна.
sf.onContentChange(function()
  if handledGeneration ~= generation then
    maybeFocus(false)
  end
end)

-- ── Ручной переход ──

-- SandFly → Команды → «Перейти к первому серверу».
sf.onCommand('focus_first_server', function()
  local list = findServerList(3000)
  if not list then
    sf.speak('Список серверов не найден')
    return
  end
  if not placeFocus(list, true) then
    sf.speak('Первый сервер не найден')
  end
end)

print('TeamTalk: фокус на первый сервер, версия 1.0 загружена')
