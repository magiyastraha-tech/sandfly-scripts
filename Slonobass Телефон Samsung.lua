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
  name = 'Slonobass Телефон Samsung',
  version = '1.3',
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
    -- блок с номером и кнопками под строкой. Первым идёт строка с номером:
    -- она стоит вплотную к строке и находится быстрее всего.
    markers = {},
    below = {
      { id = 'expand_item_phone_container' },
      { id = 'expand_item_call' },
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

local function idTail(id)
  return string.match(id or '', '[^/]*$')
end

local function shortId(item)
  return idTail(item and item.id or '')
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

-- Новый снимок строки: после нажатия старый снимок ещё помнит прежний экран.
local function fresh(item)
  local ok, refreshed = pcall(function() return item:refresh() end)
  if ok and refreshed then return refreshed end
  return item
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

-- Развёрнутый блок — это соседи строки в том же списке, до следующей строки
-- или до заголовка группы. Так видно, что блок принадлежит именно этой строке:
-- координаты экрана тут ни при чём, и ошибиться соседом нельзя.
local function blockOf(kind, row)
  local okParent, parent = pcall(function() return row:parent() end)
  if not okParent or not parent then return nil end
  local okKids, kids = pcall(function() return parent:children() end)
  if not okKids or type(kids) ~= 'table' then return nil end
  local top = row.bounds and row.bounds.top
  local index
  for i, child in ipairs(kids) do
    if shortId(child) == kind.rowId then
      local childTop = child.bounds and child.bounds.top
      if top and childTop then
        if math.abs(childTop - top) <= 2 then
          index = i
          break
        end
      elseif child.focused then
        index = i
        break
      end
    end
  end
  if not index then return nil end
  local siblings = {}
  for i = index + 1, #kids do
    local child = kids[i]
    if shortId(child) == kind.rowId or child.heading then break end
    siblings[#siblings + 1] = child
  end
  return siblings
end

-- Запасной путь: верхняя граница поиска по экрану — начало следующей строки
-- того же списка, а если её не нашлось, четыреста точек ниже строки.
local function windowLimit(kind, row)
  local bottom = row.bounds and row.bounds.bottom
  if not bottom then return nil end
  local ok, rows = pcall(function() return sf.screen.findAll({ id = kind.rowId }, 50) end)
  local limit
  if ok and type(rows) == 'table' then
    for _, candidate in ipairs(rows) do
      local top = candidate.bounds and candidate.bounds.top
      if top and top > bottom - 1 and (limit == nil or top < limit) then
        limit = top
      end
    end
  end
  return (limit or bottom + 400) - 1
end

local function blockBelow(row, queries, maxQueries, limit)
  local bounds = row.bounds
  if not bounds or not bounds.bottom then return false end
  local bottom = bounds.bottom
  local reach = limit or (bottom + 400)
  for index, query in ipairs(queries) do
    if index > (maxQueries or #queries) then break end
    local ok, found = pcall(function() return sf.screen.findAll(query, 10) end)
    if ok and type(found) == 'table' then
      for _, item in ipairs(found) do
        local top = item.bounds and item.bounds.top
        if top and top >= bottom - 40 and top <= reach then
          return true
        end
      end
    end
  end
  return false
end

-- cheap — для хука фокуса: без обхода списка и только первый признак, иначе
-- не уложиться в тридцать миллисекунд. Список действий доступности проверяется
-- последним: у старой копии строки он может врать про раскрытие.
local function expandedFor(kind, row, cheap)
  if markedExpanded(kind, row) then return true end
  if not cheap then
    local okBlock, siblings = pcall(blockOf, kind, row)
    if okBlock and type(siblings) == 'table' and #siblings > 0 then return true end
  end
  local state = actionState(row)
  if state ~= nil then return state end
  local bottom = row.bounds and row.bounds.bottom or 0
  local ok, below = pcall(blockBelow, row, kind.below, cheap and 1 or nil, bottom + (cheap and 200 or 150))
  return ok and below or false
end

-- Разворачивает строку. Если у строки есть отдельное действие «развернуть»,
-- пользуемся им: оно не переключатель, повторный вызов ничего не свернёт.
-- После нажатия проверяем, что блок действительно появился: иначе лучше
-- сказать, что не вышло, чем нажать что-то не то.
local function ensureExpanded(kind, row)
  if expandedFor(kind, row) then return true end
  -- Снимок мог устареть: проверяем ещё раз на свежем, прежде чем нажимать.
  -- Иначе уже развёрнутая строка получит нажатие и свернётся обратно.
  row = fresh(row)
  if expandedFor(kind, row) then return true end
  if hasAction(row, EXPAND_ACTIONS) then
    local ok, done = pcall(function() return row:perform('expand') end)
    if ok and done then
      sf.sleep(350)
      if expandedFor(kind, fresh(row)) then return true end
    end
  end
  if not press(row) then return false end
  sf.sleep(450)
  return expandedFor(kind, fresh(row))
end

-- Ищет пункт в блоке под этой строкой. Сначала — среди соседей строки в
-- списке: там блок и лежит, и координаты экрана для этого не нужны. Если
-- соседей не видно, ищет по экрану в окне до следующей строки списка.
local function near(kind, row, queries, tries)
  row = fresh(row)
  local bounds = row.bounds
  local top = bounds and bounds.top or 0
  local bottom = bounds and (bounds.bottom or bounds.top) or 0
  local limit
  if bounds then
    local okLimit, computed = pcall(windowLimit, kind, row)
    if okLimit then limit = computed end
  end
  local reach = limit or (bottom + 400)
  for attempt = 1, tries or 3 do
    local blockOk, siblings = pcall(blockOf, kind, row)
    if blockOk and type(siblings) == 'table' then
      for _, query in ipairs(queries) do
        for _, sibling in ipairs(siblings) do
          if query.id and idTail(query.id) == shortId(sibling) then
            return sibling
          end
          local insideOk, inside = pcall(function() return sibling:find(query) end)
          if insideOk and inside then return inside end
        end
      end
    end
    for _, query in ipairs(queries) do
      local insideOk, inside = pcall(function() return row:find(query) end)
      if insideOk and inside then return inside end
    end
    for _, query in ipairs(queries) do
      local foundOk, found = pcall(function() return sf.screen.findAll(query, 10) end)
      if foundOk and type(found) == 'table' and #found > 0 then
        -- На экране такой элемент один — он и есть: даже если границы
        -- отдались не так, как ожидалось, выбирать не из чего.
        if #found == 1 then return found[1] end
        local best, bestDistance
        for _, candidate in ipairs(found) do
          local candidateTop = candidate.bounds and candidate.bounds.top
          if not bounds then
            best = candidate
            break
          end
          if candidateTop and candidateTop >= top and candidateTop <= reach then
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

  local target
  if expanded then
    target = near(kind, row, action.queries, 4)
  elseif ensureExpanded(kind, row) then
    target = near(kind, row, action.queries, 5)
  end
  -- Блок мог уже появиться, а подтверждение развёрнутости — нет: у контактов
  -- признак берётся по соседям строки, и сразу после нажатия снимок иногда
  -- ещё старый. Если кнопки на месте, работаем с ними, а не говорим об ошибке.
  if not target then
    sf.sleep(300)
    target = near(kind, row, action.queries, 1)
  end
  if target then
    press(target)
    return
  end
  if not expanded and not expandedFor(kind, row) then
    sf.speak('Не получилось развернуть строку')
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
  local ok, expanded = pcall(expandedFor, kind, item, true)
  if not ok or not expanded then return nil end
  -- Текст возвращается целиком, вместе с пометкой: дописывание к чужому
  -- тексту через after в некоторых сборках теряет сам текст строки.
  if text and text ~= '' then
    return { speak = text .. ' ' .. kind.expandedText }
  end
  return { speak = kind.expandedText }
end)
