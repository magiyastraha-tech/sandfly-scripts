-- Действия с записью журнала вызовов Samsung.
-- В меню действий каждой строки журнала добавляет пункты: позвонить,
-- сведения, добавить контакт, сообщение, видеовызов и воспроизвести запись.
-- Свёрнутую строку скрипт сначала разворачивает сам, развёрнутую не трогает:
-- действия работают в обоих состояниях. Развёрнутую строку при чтении
-- помечает словами «Строка развёрнута».

local manifest = {
  id = 'wam.samsung-call-log-actions',
  name = 'Телефон Samsung: действия с вызовом',
  version = '1.0',
  author = 'Алёшка',
  minApiVersion = 1,
  testedApiVersion = 2,
  description = 'В меню действий каждой строки журнала вызовов добавляет пункты: позвонить, сведения, добавить контакт, сообщение, видеовызов и воспроизвести запись. Свёрнутую строку скрипт сначала разворачивает сам, развёрнутую не трогает, поэтому действия работают в обоих состояниях. Развёрнутую строку при чтении помечает словами «Строка развёрнута». Если запись вызова не велась, говорит об этом отдельно.',
  apps = { 'com.samsung.android.dialer' },
  permissions = { 'screen', 'actions', 'speech', 'input' },
}

-- Строка журнала: контейнер с именем или номером, временем и значками.
local ROW_ID = 'container_call_log_content'
local MAIN_ID = 'text_call_log_main'

-- Признаки развёрнутой строки: блок с номером и фото контакта появляются
-- только у раскрытой записи.
local EXPANDED_MARKERS = {
  { id = 'expand_photo_layout' },
  { id = 'container_expand_multi_number' },
  { textContains = 'Изображение профиля' },
}

-- Номера стандартных действий доступности: ACTION_EXPAND и ACTION_COLLAPSE.
-- Кроме чисел, проверяются имена: SandFly может отдавать их так.
local EXPAND_ACTIONS = { 'expand', 1048576 }
local COLLAPSE_ACTIONS = { 'collapse', 524288 }

local ACTIONS = {
  {
    title = 'Позвонить',
    queries = {
      { id = 'layout_expand_one' },
      { contentDescription = 'Вызов' },
      { contentDescription = 'Call' },
    },
  },
  {
    title = 'Сведения',
    queries = {
      { id = 'expand_photo_layout' },
      { textContains = 'сведениям о контакте' },
      { textContains = 'View contact' },
    },
  },
  {
    title = 'Добавить контакт',
    -- Для знакомого номера пункт только сообщает, что контакт уже есть.
    kind = 'add',
    queries = {
      { textContains = 'Добавить контакт' },
      { textContains = 'Создать контакт' },
      { textContains = 'Добавить в контакты' },
      { textContains = 'Add contact' },
      { textContains = 'Create contact' },
      { id = 'expand_photo_layout' },
    },
  },
  {
    title = 'Сообщение',
    queries = {
      { id = 'layout_expand_two' },
      { contentDescription = 'Сообщение' },
      { contentDescription = 'Message' },
    },
  },
  {
    title = 'Видеовызов',
    queries = {
      { id = 'layout_expand_three' },
      { contentDescription = 'Видеовызов' },
      { contentDescription = 'Video call' },
    },
  },
  {
    title = 'Воспроизвести запись',
    queries = {
      { id = 'image_view_record' },
      { contentDescription = 'Воспроизвести запись вызова' },
      { contentDescription = 'Play call recording' },
    },
    -- Значок записи стоит в свёрнутой строке, если вызов записывался.
    presence = { { id = 'image_call_log_indicator_icon' } },
    absentText = 'Записи этого вызова нет',
  },
}

local function shortId(item)
  return string.match(item and item.id or '', '[^/]*$')
end

-- Нажимает элемент. Обычное нажатие, а если элемент его не принял — тычок
-- пальцем: так срабатывают кнопки, которые не понимают программное нажатие.
local function press(item)
  local ok, clicked = pcall(function() return item:click() end)
  if ok and clicked then return true end
  local tappedOk, tapped = pcall(function() return item:tap() end)
  return tappedOk and tapped == true
end

local function hasAction(item, names)
  local actions = item.actions
  if type(actions) ~= 'table' then return false end
  for _, action in ipairs(actions) do
    for _, name in ipairs(names) do
      if action.id == name then return true end
    end
  end
  return false
end

-- Состояние строки по её же действиям доступности: развернуть или свернуть.
-- Если приложение отдаёт оба действия сразу, этот признак не годится.
local function actionState(row)
  local expand = hasAction(row, EXPAND_ACTIONS)
  local collapse = hasAction(row, COLLAPSE_ACTIONS)
  if collapse and not expand then return true end
  if expand and not collapse then return false end
  return nil
end

-- Быстрая проверка для хука чтения: только поля самой строки, без поиска
-- по экрану — у хука на всё про всё тридцать миллисекунд.
local function markedExpanded(row)
  for _, query in ipairs(EXPANDED_MARKERS) do
    local ok, found = pcall(function() return row:find(query) end)
    if ok and found then return true end
  end
  return nil
end

-- Блок развёрнутой записи — не внутри строки, а рядом с ней, сразу под ней.
-- Поэтому смотрим строки списка по порядку и проверяем, что кнопки лежат
-- между этой строкой и следующей.
local function expandedBelow(row)
  local ok, rows = pcall(function() return sf.screen.findAll({ id = ROW_ID }, 50) end)
  if not ok or type(rows) ~= 'table' or #rows == 0 then return false end
  local index
  for i, candidate in ipairs(rows) do
    if candidate == row then
      index = i
      break
    end
  end
  if not index and row.bounds then
    for i, candidate in ipairs(rows) do
      local b = candidate.bounds
      if b and b.top == row.bounds.top and b.left == row.bounds.left then
        index = i
        break
      end
    end
  end
  if not index then return false end
  local nextRow = rows[index + 1]
  local limit = nextRow and nextRow.bounds and nextRow.bounds.top
  local bottom = row.bounds and row.bounds.bottom or 0
  for _, query in ipairs({ { id = 'container_expand_call_type' }, { id = 'layout_expand_one' } }) do
    local foundOk, found = pcall(function() return sf.screen.findAll(query, 10) end)
    if foundOk and type(found) == 'table' then
      for _, item in ipairs(found) do
        local top = item.bounds and item.bounds.top
        if top and top >= bottom - 120 and (not limit or top <= limit) then
          return true
        end
      end
    end
  end
  return false
end

local function expandedFor(row)
  local state = actionState(row)
  if state ~= nil then return state end
  if markedExpanded(row) then return true end
  local ok, below = pcall(expandedBelow, row)
  return ok and below or false
end

-- Разворачивает строку. Если у строки есть отдельное действие «развернуть»,
-- пользуемся им: оно не переключатель, повторный вызов ничего не свернёт.
local function ensureExpanded(row)
  if expandedFor(row) then return true end
  if hasAction(row, EXPAND_ACTIONS) then
    local ok, done = pcall(function() return row:perform('expand') end)
    if ok and done then
      sf.sleep(350)
      return true
    end
  end
  if not press(row) then return false end
  sf.sleep(450)
  return true
end

-- Находит пункт рядом с этой строкой: сначала внутри неё, потом на экране,
-- выбирая ближайший по вертикали. Так кнопки соседней развёрнутой записи
-- не перепутаются с нашими.
local function near(row, queries, tries)
  local ok, refreshed = pcall(function() return row:refresh() end)
  if ok and refreshed then row = refreshed end
  local bounds = row.bounds
  for attempt = 1, tries or 4 do
    for _, query in ipairs(queries) do
      local insideOk, inside = pcall(function() return row:find(query) end)
      if insideOk and inside then return inside end
    end
    for _, query in ipairs(queries) do
      local foundOk, found = pcall(function() return sf.screen.findAll(query, 20) end)
      if foundOk and type(found) == 'table' and #found > 0 then
        local best, bestDistance
        for _, candidate in ipairs(found) do
          local b = candidate.bounds
          if not bounds then
            best = candidate
            break
          end
          if b and b.top and b.top >= (bounds.top or 0) then
            local distance = b.top - (bounds.bottom or bounds.top)
            if distance >= -1000 and (bestDistance == nil or distance < bestDistance) then
              best, bestDistance = candidate, distance
            end
          end
        end
        if best then return best end
      end
    end
    if attempt < (tries or 4) then sf.sleep(150) end
  end
  return nil
end

local function rowName(row)
  local ok, item = pcall(function() return row:find({ id = MAIN_ID }) end)
  if ok and item then return item.text end
  return nil
end

-- Строка с незнакомым номером: в ней вместо имени стоит сам номер.
local function looksLikeNumber(text)
  if not text or text == '' then return false end
  return string.match(text, '^%+?[%d%s%-%(%)]+$') ~= nil
end

-- Выполняется, когда выбран пункт меню действий. Здесь можно ждать, поэтому
-- sf.sleep разрешён.
local function perform(row, action)
  local name = rowName(row)

  if action.kind == 'add' and name and not looksLikeNumber(name) then
    sf.speak('Номер уже в контактах')
    return
  end

  local expanded = expandedFor(row)

  -- Значка записи нет — и разворачивать строку незачем.
  if not expanded and action.presence then
    local present = false
    for _, query in ipairs(action.presence) do
      local ok, found = pcall(function() return row:find(query) end)
      if ok and found then
        present = true
        break
      end
    end
    if not present then
      sf.speak(action.absentText or (action.title .. ': пункт не найден'))
      return
    end
  end

  if not expanded and not ensureExpanded(row) then
    sf.speak('Не получилось развернуть строку')
    return
  end

  local target = near(row, action.queries, expanded and 4 or 5)
  if target then
    press(target)
    return
  end
  sf.speak(action.absentText or (action.title .. ': пункт не найден'))
end

sf.onActions(function(item)
  if shortId(item) ~= ROW_ID then return nil end
  local list = {}
  for _, action in ipairs(ACTIONS) do
    list[#list + 1] = {
      title = action.title,
      run = function(row) perform(row or item, action) end,
    }
  end
  return list
end)

-- Когда фокус встаёт на развёрнутую строку, добавляем в её чтение два слова:
-- иначе свёрнутая и развёрнутая строка звучат одинаково.
sf.onFocus(function(item, text)
  if shortId(item) ~= ROW_ID then return nil end
  local ok, expanded = pcall(function()
    local state = actionState(item)
    if state ~= nil then return state end
    return markedExpanded(item) == true
  end)
  if ok and expanded then
    return { after = 'Строка развёрнута' }
  end
  return nil
end)
