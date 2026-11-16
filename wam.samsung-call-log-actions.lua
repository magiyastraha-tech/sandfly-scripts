-- Действия со строкой в штатном телефоне Samsung: журнал вызовов и контакты.
-- В меню действий каждой строки добавляет пункты: позвонить, сведения,
-- сообщение, видеовызов, а в журнале ещё «Добавить контакт» и «Воспроизвести
-- запись». Свёрнутую строку скрипт сначала разворачивает сам, развёрнутую не
-- трогает: действия работают в обоих состояниях. Развёрнутую строку при
-- чтении помечает словами «Строка развёрнута», в контактах — «Контакт
-- развёрнут». Имя файла осталось прежним, чтобы уже установленный скрипт
-- обновился сам и не задвоил пункты меню.

local manifest = {
  id = 'wam.samsung-call-log-actions',
  name = 'Телефон Samsung: действия в списках',
  version = '1.1',
  author = 'Алёшка',
  minApiVersion = 1,
  testedApiVersion = 2,
  description = 'В меню действий каждой строки журнала вызовов и каждой строки вкладки «Контакты» добавляет пункты. В журнале: позвонить, сведения, добавить контакт, сообщение, видеовызов и воспроизвести запись. В контактах: позвонить, сообщение, видеовызов и сведения. Свёрнутую строку скрипт сначала разворачивает сам, развёрнутую не трогает, поэтому действия работают в обоих состояниях. Развёрнутую строку при чтении помечает словами «Строка развёрнута», в контактах — «Контакт развёрнут». Если запись вызова не велась, говорит об этом отдельно.',
  apps = { 'com.samsung.android.dialer' },
  permissions = { 'screen', 'actions', 'speech', 'input' },
}

-- Номера стандартных действий доступности: ACTION_EXPAND и ACTION_COLLAPSE.
-- Кроме чисел, проверяются имена: SandFly может отдавать их так.
local EXPAND_ACTIONS = { 'expand', 1048576 }
local COLLAPSE_ACTIONS = { 'collapse', 524288 }

-- Два списка одного приложения устроены одинаково: строка с именем, а под
-- развёрнутой строкой — блок с номером и кнопками. Отличаются идентификаторы.
local KINDS = {
  {
    rowId = 'container_call_log_content',
    mainId = 'text_call_log_main',
    expandedText = 'Строка развёрнута',
    -- У развёрнутой записи журнала блок с номером и фото появляется внутри
    -- строки: это самый дешёвый и надёжный признак.
    markers = {
      { id = 'expand_photo_layout' },
      { id = 'container_expand_multi_number' },
      { textContains = 'Изображение профиля' },
    },
    -- Кнопки развёрнутой записи — соседи строки, сразу под ней.
    below = {
      { id = 'container_expand_call_type' },
      { id = 'layout_expand_one' },
    },
    actions = {
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
    },
  },
  {
    rowId = 'container_contact_list_item_content',
    mainId = 'contact_list_item_main',
    expandedText = 'Контакт развёрнут',
    -- Внутри строки контакта ничего не меняется, поэтому признак только один:
    -- блок с номером и кнопками под строкой.
    markers = {},
    below = {
      { id = 'expand_item_call' },
      { id = 'expand_item_phone_container' },
    },
    actions = {
      {
        title = 'Позвонить',
        queries = {
          { id = 'expand_item_call' },
          { contentDescription = 'Вызов, Кнопка' },
        },
      },
      {
        title = 'Сообщение',
        queries = {
          { id = 'expand_item_msg' },
          { contentDescription = 'Сообщение, Кнопка' },
        },
      },
      {
        title = 'Видеовызов',
        queries = {
          { id = 'expand_item_vcall' },
          { contentDescription = 'Видеовызов, Кнопка' },
        },
      },
      {
        title = 'Сведения',
        queries = {
          { id = 'expand_item_detail' },
          { contentDescription = 'Сведения, Кнопка' },
        },
      },
    },
  },
}

local function shortId(item)
  return string.match(item and item.id or '', '[^/]*$')
end

local function kindFor(item)
  local id = shortId(item)
  for _, kind in ipairs(KINDS) do
    if kind.rowId == id then return kind end
  end
  return nil
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

-- Признаки развёрнутой строки внутри неё самой. Дешёвая проверка: только
-- поддерево строки, без поиска по экрану.
local function markedExpanded(kind, row)
  for _, query in ipairs(kind.markers) do
    local ok, found = pcall(function() return row:find(query) end)
    if ok and found then return true end
  end
  return nil
end

-- Блок развёрнутой строки лежит не внутри неё, а сразу под ней. Ищем его
-- элементы в узком окне ниже нижней границы строки: у соседней развёрнутой
-- строки такой блок начинается только после следующей строки и в окно не
-- попадает. Так кнопки соседа не перепутаются с нашими.
local function blockBelow(row, queries, maxQueries)
  local bounds = row.bounds
  if not bounds or not bounds.bottom then return false end
  local bottom = bounds.bottom
  for index, query in ipairs(queries) do
    if index > (maxQueries or #queries) then break end
    local ok, found = pcall(function() return sf.screen.findAll(query, 10) end)
    if ok and type(found) == 'table' then
      for _, item in ipairs(found) do
        local top = item.bounds and item.bounds.top
        if top and top >= bottom - 40 and top <= bottom + 80 then
          return true
        end
      end
    end
  end
  return false
end

local function expandedFor(kind, row, maxQueries)
  local state = actionState(row)
  if state ~= nil then return state end
  if markedExpanded(kind, row) then return true end
  local ok, below = pcall(blockBelow, row, kind.below, maxQueries)
  return ok and below or false
end

-- Разворачивает строку. Если у строки есть отдельное действие «развернуть»,
-- пользуемся им: оно не переключатель, повторный вызов ничего не свернёт.
-- После нажатия проверяем, что блок действительно появился: иначе лучше
-- сказать, что не вышло, чем нажать что-то не то.
local function ensureExpanded(kind, row)
  if expandedFor(kind, row) then return true end
  if hasAction(row, EXPAND_ACTIONS) then
    local ok, done = pcall(function() return row:perform('expand') end)
    if ok and done then
      sf.sleep(350)
      if expandedFor(kind, row) then return true end
    end
  end
  if not press(row) then return false end
  sf.sleep(450)
  return expandedFor(kind, row)
end

-- Находит пункт рядом с этой строкой: сначала внутри неё, потом на экране,
-- выбирая ближайший к её нижней границе. Верхняя граница окна — та же, что
-- у признака развёрнутости, поэтому чужие кнопки не подхватываются.
local function near(row, queries, tries)
  local ok, refreshed = pcall(function() return row:refresh() end)
  if ok and refreshed then row = refreshed end
  local bounds = row.bounds
  local top = bounds and bounds.top or 0
  local bottom = bounds and (bounds.bottom or bounds.top) or 0
  for attempt = 1, tries or 3 do
    for _, query in ipairs(queries) do
      local insideOk, inside = pcall(function() return row:find(query) end)
      if insideOk and inside then return inside end
    end
    for _, query in ipairs(queries) do
      local foundOk, found = pcall(function() return sf.screen.findAll(query, 10) end)
      if foundOk and type(found) == 'table' and #found > 0 then
        local best, bestDistance
        for _, candidate in ipairs(found) do
          local candidateTop = candidate.bounds and candidate.bounds.top
          if not bounds then
            best = candidate
            break
          end
          if candidateTop and candidateTop >= top and candidateTop <= bottom + 80 then
            local distance = candidateTop - bottom
            if bestDistance == nil or distance < bestDistance then
              best, bestDistance = candidate, distance
            end
          end
        end
        if best then return best end
      end
    end
    if attempt < (tries or 3) then sf.sleep(150) end
  end
  return nil
end

local function rowName(kind, row)
  local ok, item = pcall(function() return row:find({ id = kind.mainId }) end)
  if ok and item then return item.text end
  return nil
end

-- Строка журнала с незнакомым номером: в ней вместо имени стоит сам номер.
local function looksLikeNumber(text)
  if not text or text == '' then return false end
  return string.match(text, '^%+?[%d%s%-%(%)]+$') ~= nil
end

-- Выполняется, когда выбран пункт меню действий. Здесь можно ждать, поэтому
-- sf.sleep разрешён.
local function perform(kind, row, action)
  local name = rowName(kind, row)

  if action.kind == 'add' and name and not looksLikeNumber(name) then
    sf.speak('Номер уже в контактах')
    return
  end

  local expanded = expandedFor(kind, row)

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

  if not expanded and not ensureExpanded(kind, row) then
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
  local kind = kindFor(item)
  if not kind then return nil end
  local list = {}
  for _, action in ipairs(kind.actions) do
    list[#list + 1] = {
      title = action.title,
      run = function(row) perform(kind, row or item, action) end,
    }
  end
  return list
end)

-- Когда фокус встаёт на развёрнутую строку, добавляем в её чтение два слова:
-- иначе свёрнутая и развёрнутая строка звучат одинаково. У хука на всё про
-- всё тридцать миллисекунд, поэтому у контактов смотрим только первый
-- признак — одну кнопку развёрнутого блока.
sf.onFocus(function(item, text)
  local kind = kindFor(item)
  if not kind then return nil end
  local ok, expanded = pcall(expandedFor, kind, item, 1)
  if ok and expanded then
    return { after = kind.expandedText }
  end
  return nil
end)
