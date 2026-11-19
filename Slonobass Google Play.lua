-- Google Play: фокус сразу на строке обновлений.
-- На экране «Управление устройством и приложениями» первая живая строка после
-- баннера Play Защиты — состояние обновлений: «Все приложения обновлены» или
-- «Доступны обновления» со счётом. Своего id у строки нет, поэтому ищем её по
-- подписи и поднимаемся к фокусируемому родителю: подпись лежит во вложенном
-- TextView, а фокус берёт строка-контейнер.

local manifest = {
  id = 'wam.google-play-updates-focus',
  name = 'Slonobass Google Play',
  author = 'Алёшка',
  version = '1.0',
  minApiVersion = 2,
  testedApiVersion = 5,
  description = 'При открытии экрана обновлений Google Play фокус сразу встаёт на строку, где видно состояние: «Все приложения обновлены» или «Доступны обновления» со счётом. Работает на экране «Управление устройством и приложениями», где эта строка появляется. В меню команд есть ручной переход «Перейти к обновлениям».',
  apps = { 'com.android.vending' },
  permissions = { 'screen', 'actions', 'speech', 'input' },
  commands = {
    { id = 'focus_updates', title = 'Перейти к обновлениям', menu = true },
  },
  settings = {
    {
      key = 'focusUpdates',
      type = 'switch',
      title = 'Фокус на обновления',
      summary = 'При открытии экрана фокус встаёт на строку обновлений',
      default = true,
    },
  },
}

-- Подписи строки обновлений. Точные варианты идут первыми, дальше — похожие
-- состояния на случай другой версии Play: во время загрузки строка называется
-- иначе, а смысл тот же.
local TITLE_QUERIES = {
  { text = 'Все приложения обновлены' },
  { textContains = 'приложения обновлены' },
  { text = 'Доступны обновления' },
  { textContains = 'Доступно обновление' },
  { textContains = 'Обновление приложений' },
  { textContains = 'Загрузка обновлений' },
}

-- Вторая строка блока: счёт обновлений или время последнего. Она и есть то,
-- ради чего фокус сюда ставится, поэтому её добавляем к тому, что читается.
local SUBTITLE_QUERIES = {
  { textContains = 'ожидают скачивания' },
  { textContains = 'ожидает скачивания' },
  { textContains = 'Последнее обновление' },
  { textContains = 'скачива' },
  { textContains = 'загружа' },
}

-- Сколько ждём строку: при входе дольше, при появлении на уже открытом экране
-- меньше — экран к этому времени обычно дорисован.
local ENTER_TIMEOUT = 15000
local APPEAR_TIMEOUT = 8000

local function parentOf(node)
  local ok, parent = pcall(function() return node:parent() end)
  if ok then return parent end
  return nil
end

-- Совпадение текста с запросом из списка выше. Регистр не трогаем: подписи
-- Play всегда в одном и том же виде, а string.lower не понижает кириллицу.
local function matches(text, query)
  if type(text) ~= 'string' or text == '' then return false end
  if query.text then return text == query.text end
  if query.textContains then
    return text:find(query.textContains, 1, true) ~= nil
  end
  return false
end

local function trim(text)
  if type(text) ~= 'string' then return '' end
  return (text:gsub('^%s+', ''):gsub('%s+$', ''))
end

-- Длина в символах, а не в байтах: кириллица занимает по два байта на букву, и
-- по байтам короткая подпись выглядела бы вдвое длиннее.
local function charLen(text)
  if type(text) ~= 'string' then return 0 end
  if utf8 and utf8.len then
    local ok, count = pcall(utf8.len, text)
    if ok and count then return count end
  end
  return #text
end

local function withoutDot(text)
  return (text:gsub('%.%s*$', ''))
end

-- Подпись строки: либо сам элемент и есть подпись, либо она лежит внутри.
-- Длинный текст не берём: у большого контейнера это склейка всех строк, и
-- заголовком она не является.
local function titleText(item)
  if not item then return nil end
  local own = item.text
  if type(own) == 'string' and charLen(own) > 0 and charLen(own) <= 30 then
    for _, query in ipairs(TITLE_QUERIES) do
      if matches(own, query) then return own end
    end
  end
  for _, query in ipairs(TITLE_QUERIES) do
    local ok, found = pcall(function() return item:find(query) end)
    if ok and found and type(found.text) == 'string' and found.text ~= '' then
      return found.text
    end
  end
  return nil
end

-- Вторая строка блока — внутри строки, на уровень выше подписи её искать не
-- нужно, но на всякий случай смотрим и родителя.
local function subtitleText(item)
  local cur = item
  for _ = 1, 2 do
    if not cur then return nil end
    local own = cur.text
    if type(own) == 'string' and charLen(own) > 0 and charLen(own) <= 80 then
      for _, query in ipairs(SUBTITLE_QUERIES) do
        if matches(own, query) then return own end
      end
    end
    for _, query in ipairs(SUBTITLE_QUERIES) do
      local ok, found = pcall(function() return cur:find(query) end)
      if ok and found and type(found.text) == 'string' and found.text ~= '' then
        return found.text
      end
    end
    cur = parentOf(cur)
  end
  return nil
end

-- Что сказать про строку обновлений: подпись и счёт одной фразой.
local function describe(item)
  local title = trim(titleText(item))
  if title == '' then return nil end
  local sub = trim(subtitleText(item))
  if sub == '' or sub == title then return title end
  return withoutDot(title) .. '. ' .. withoutDot(sub)
end

-- Фокусируемая строка вокруг подписи. Если фокусируемого родителя нет, отдаём
-- саму подпись: иногда SandFly ставит фокус и на неё.
local function rowOf(label)
  local cur = label
  for _ = 1, 4 do
    if not cur then break end
    if cur.focusable then return cur end
    cur = parentOf(cur)
  end
  return label
end

-- Строка обновлений на экране прямо сейчас.
local function labelNow()
  for _, query in ipairs(TITLE_QUERIES) do
    local ok, found = pcall(function() return sf.screen.find(query) end)
    if ok and found and found.visible ~= false then return found end
  end
  return nil
end

-- Ждём строку. Вызывается только из задачи (sf.run, команда): здесь можно
-- спать между попытками.
local function findRow(timeout)
  local step = 300
  local rounds = math.max(1, math.floor((timeout or 0) / step))
  for round = 1, rounds do
    local label = labelNow()
    if label then return rowOf(label), label end
    if round < rounds then sf.sleep(step) end
  end
  return nil
end

-- Один и тот же элемент из разных снимков: сравниваем по границам, а если их
-- нет — по тексту и классу.
local function sameItem(a, b)
  if not a or not b then return false end
  if a == b then return true end
  local ab, bb = a.bounds, b.bounds
  if ab and bb then
    return ab.left == bb.left and ab.right == bb.right
      and ab.top == bb.top and ab.bottom == bb.bottom
  end
  return a.text ~= nil and a.text == b.text and a.className == b.className
end

-- Ставит фокус на строку и проверяет, что он там оказался. Если строка фокус
-- не берёт, пробуем саму подпись.
local function focusNow(row, label)
  pcall(function() row:showOnScreen() end)
  pcall(function() row:focus() end)
  if sameItem(sf.screen.focused(), row) then return true end
  if label and label ~= row then
    pcall(function() label:focus() end)
    if sameItem(sf.screen.focused(), label) then return true end
  end
  return false
end

-- Строка появилась на экране впервые: запоминаем и переводим фокус. Повторные
-- изменения содержимого (идёт загрузка, меняется счёт) фокус не трогают —
-- иначе он отбирался бы при каждом обновлении экрана.
local shown = false
local checkPending = false

-- Номер попытки: пока ждали строку, экран мог смениться, и тогда работает
-- только последний вызов.
local generation = 0

local function focusUpdates(force)
  if sf.settings.get('focusUpdates') == false then return end
  generation = generation + 1
  local mine = generation
  sf.run(function()
    local ok, err = pcall(function()
      local row, label = findRow(force and ENTER_TIMEOUT or APPEAR_TIMEOUT)
      if not row or mine ~= generation then return end
      -- Строка уже в фокусе: запоминаем, что она на экране есть, и не трогаем
      -- фокус дальше, даже если человек уйдёт с неё вниз.
      if sameItem(sf.screen.focused(), row) then
        shown = true
        return
      end
      if focusNow(row, label) then
        shown = true
        return
      end
      local text = describe(label or row)
      if text then sf.speak(text) end
    end)
    if not ok then print('Google Play: фокус — ' .. tostring(err)) end
  end)
end

local function checkAppeared()
  if checkPending then return end
  checkPending = true
  sf.setTimeout(function()
    checkPending = false
    local label = labelNow()
    if not label then
      shown = false
      return
    end
    local row = rowOf(label)
    if sameItem(sf.screen.focused(), row) then
      shown = true
      return
    end
    if shown then return end
    shown = true
    focusUpdates(false)
  end, 600)
end

sf.onAppEnter(function()
  shown = false
  focusUpdates(true)
end)

sf.onWindowChange(checkAppeared)
sf.onContentChange(checkAppeared)

-- Своя подача строки: только подпись и счёт, без кнопок «Обновить все» и
-- «Подробнее» в конце. Если не успели за отведённое время, SandFly прочитает
-- строку как обычно — это не ошибка.
sf.onFocus(function(item)
  if not item then return nil end
  local own = item.text
  if type(own) == 'string' and charLen(own) > 80 then return nil end
  local text = describe(item)
  if text then return { speak = text } end
  return nil
end)

-- Ручной переход: SandFly → Команды → «Перейти к обновлениям».
sf.onCommand('focus_updates', function()
  local row, label = findRow(5000)
  if not row then
    sf.speak('Строка обновлений не найдена')
    return
  end
  if focusNow(row, label) then return end
  local text = describe(label or row)
  if text then
    sf.speak(text)
  else
    sf.speak('Строка обновлений не берёт фокус')
  end
end)
