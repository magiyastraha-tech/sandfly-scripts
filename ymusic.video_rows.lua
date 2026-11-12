-- YMusic: в строке видео, клипа и трансляции только название и время.
-- Остальное (канал, просмотры, дата публикации) — в меню действий строки.
-- Кнопка «Ещё» спрятана в любой строке списка и открывается из меню действий.

local manifest = {
  id = 'ymusic.video_rows',
  name = 'YMusic: название и время',
  author = 'Алёшка',
  version = '1.7',
  minApiVersion = 1,
  testedApiVersion = 4,
  description = 'Видео, клип и трансляция в списке читают только название и время. Канал, просмотры и дата публикации переезжают в меню действий — у видео, клипов, трансляций, миксов и плейлистов. Кнопка «Ещё» скрыта в любой строке списка — и в «Подписках», и на главной — и открывается из меню действий. При входе в приложение и при каждом открытии вкладки «Подписки» фокус всегда встаёт на раздел «Новые».',
  apps = { 'io.ymusic.android' },
  permissions = { 'screen', 'speech', 'input', 'actions' },
  commands = {
    { id = 'focus_new', title = 'Перейти к разделу «Новые»', menu = true },
  },
  settings = {
    {
      key = 'focusNew',
      type = 'switch',
      title = 'Фокус на «Новые»',
      summary = 'При входе в приложение фокус встаёт на раздел «Новые»',
      default = true,
    },
    {
      key = 'shorten',
      type = 'switch',
      title = 'Короткая строка',
      summary = 'Только название и время',
      default = true,
    },
    {
      key = 'lineTime',
      type = 'list',
      title = 'Что считать временем',
      options = {
        { value = 'duration', label = 'Длительность' },
        { value = 'published', label = 'Когда опубликовано' },
        { value = 'both', label = 'И то и другое' },
      },
      default = 'duration',
    },
  },
  rules = {
    -- Кнопку «Ещё» прячем в любой строке списка, не только в «Подписках».
    -- Строку выдаёт разделитель « · » между данными: он есть у видео, клипов,
    -- миксов, подкастов и плейлистов, поэтому перечислять типы не нужно.
    -- Только match, без id: id вместе с match требует совпадения и по id, и по запросу.
    {
      match = { className = 'Button', contentDescription = 'Ещё', inside = { textContains = ' · ' } },
      hide = true,
    },
    {
      match = { className = 'Button', contentDescription = 'More', inside = { textContains = ' · ' } },
      hide = true,
    },
  },
}

local function trim(s)
  return (s:gsub('^%s+', ''):gsub('%s+$', ''))
end

-- Делит строку на куски по разделителю, не считая его шаблоном Lua.
local function splitBy(text, sep)
  local parts, start = {}, 1
  while true do
    local a = string.find(text, sep, start, true)
    if not a then
      parts[#parts + 1] = text:sub(start)
      return parts
    end
    parts[#parts + 1] = text:sub(start, a - 1)
    start = a + #sep
  end
end

-- Длительность: «11 минут 57 секунд», «2:30», «1 hour». В канале цифры
-- тоже бывают, поэтому мало одной цифры — нужно слово времени или двоеточие.
local function looksLikeDuration(s)
  if type(s) ~= 'string' or s == '' or not string.find(s, '%d') then return false end
  if string.find(s, ':', 1, true) then return true end
  if string.find(s, 'мин', 1, true) or string.find(s, 'сек', 1, true)
     or string.find(s, 'час', 1, true) then
    return true
  end
  local low = s:lower()
  return string.find(low, 'min', 1, true) ~= nil
      or string.find(low, 'sec', 1, true) ~= nil
      or string.find(low, 'hour', 1, true) ~= nil
end

-- Типы строк, у которых есть канал, просмотры и дата: видео, клипы, трансляции.
-- string.lower кириллицу не трогает, поэтому русские типы сравниваем как есть.
local function isVideoKind(kind)
  if kind == 'Видео' or kind == 'Клип' or kind == 'Видеоклип'
     or kind == 'Трансляция' or kind == 'Прямая трансляция'
     or kind == 'Эфир' or kind == 'Прямой эфир' then
    return true
  end
  local low = kind:lower()
  return low == 'video' or low == 'clip' or low == 'live'
      or low == 'live stream' or low == 'stream'
end

-- Разбирает строку YMusic. Видео и клипы:
--   Видео, <название>, <длительность>, <канал> · <просмотры> · <когда>
-- Трансляция бывает без длительности: <тип>, <название>, <канал> · … · …
-- Микс и плейлист короче: <тип>, <название> · Плейлист.
-- Название может содержать запятые, поэтому режем с конца.
local function parseRow(text)
  if type(text) ~= 'string' or text == '' then return nil end

  local segs = splitBy(text, ' · ')
  if #segs < 2 then return nil end

  local head = trim(segs[1])
  local published = trim(segs[#segs])
  local views = nil
  if #segs >= 3 then
    local mid = {}
    for i = 2, #segs - 1 do mid[#mid + 1] = trim(segs[i]) end
    views = table.concat(mid, ', ')
    if views == '' then views = nil end
  end

  local parts = splitBy(head, ',')
  if #parts < 2 then return nil end

  local kind = trim(parts[1])
  local video = isVideoKind(kind)
  local channel, duration = nil, nil
  local titleTo = #parts

  if video and #parts >= 4 and looksLikeDuration(parts[#parts - 1]) then
    channel = trim(parts[#parts])
    duration = trim(parts[#parts - 1])
    titleTo = #parts - 2
  elseif video and #parts >= 3 then
    -- Трансляция без длительности: последняя часть — канал.
    channel = trim(parts[#parts])
    titleTo = #parts - 1
  end

  local titleParts = {}
  for i = 2, titleTo do titleParts[#titleParts + 1] = trim(parts[i]) end
  local title = table.concat(titleParts, ', ')

  if title == '' then return nil end
  if channel == '' then channel = nil end
  if duration == '' then duration = nil end
  -- У микса и плейлиста последний кусок («Плейлист») — тип строки, а не дата.
  if not video then published = nil end

  return {
    kind = kind,
    video = video,
    title = title,
    duration = duration,
    channel = channel,
    views = views,
    published = published,
  }
end

local function lineTime(row)
  local mode = sf.settings.get('lineTime') or 'duration'
  if mode == 'published' then return row.published or row.duration end
  if mode == 'both' then
    if row.duration and row.published then return row.duration .. ', ' .. row.published end
    return row.duration or row.published
  end
  return row.duration or row.published
end

local function restText(row)
  local mode = sf.settings.get('lineTime') or 'duration'
  local parts = {}
  if mode == 'published' and row.duration then parts[#parts + 1] = row.duration end
  if row.views then parts[#parts + 1] = row.views end
  -- Дату не повторяем, если она уже прозвучала временем строки: так бывает
  -- у трансляции, где длительности нет и временем становится статус.
  if mode ~= 'published' and row.published and row.duration then
    parts[#parts + 1] = row.published
  end
  return table.concat(parts, ', ')
end

-- Строка видео, клипа или трансляции говорит только название и время.
sf.onFocus(function(item, text)
  local row = item and parseRow(item.text)
  if not row and text then row = parseRow(text) end
  if not row or not row.video then return nil end
  if sf.settings.get('shorten') == false then return nil end
  local t = lineTime(row)
  if not t then return nil end
  return { speak = row.title .. ', ' .. t }
end)

-- Кнопка «Ещё» в строке: правилом она убрана из обхода, но сам узел
-- остаётся в дереве экрана, поэтому её можно найти и нажать.
local function findMore(it)
  if not it then return nil end
  local button = it:find({ className = 'Button', contentDescription = 'Ещё' })
  if not button then button = it:find({ className = 'Button', contentDescription = 'More' }) end
  if not button then button = it:find({ className = 'Button', text = 'Ещё' }) end
  return button
end

local function clickMore(it)
  local button = findMore(it)
  if not button and it then button = it:find({ className = 'Button' }) end
  if button then
    button:click()
  else
    sf.speak('Кнопка «Ещё» не найдена')
  end
end

-- Действия: канал, остальная информация и кнопка «Ещё».
-- Одна и та же сборка для видео, клипов, трансляций, миксов и плейлистов:
-- каждый пункт появляется, если данные в строке есть.
sf.onActions(function(item)
  if not item then return nil end
  local row = parseRow(item.text)
  local actions = {}

  if row then
    if row.channel then
      actions[#actions + 1] = {
        title = 'Канал: ' .. row.channel,
        run = function()
          sf.speak('Канал: ' .. row.channel)
        end,
      }
    end

    local rest = restText(row)
    if rest ~= '' then
      actions[#actions + 1] = {
        title = 'Остальное: ' .. rest,
        run = function()
          sf.speak(rest)
        end,
      }
    end
  end

  -- Спрятанную кнопку «Ещё» возвращаем в меню на любой строке: иначе её
  -- собственное меню было бы недоступно.
  if findMore(item) then
    actions[#actions + 1] = {
      title = 'Ещё',
      run = function(it)
        clickMore(it)
      end,
    }
  end

  if #actions == 0 then return nil end
  return actions
end)

-- ── Фокус на разделе «Новые» ──

-- Заголовок раздела «Новые» на экране подписок. Разметку списка
-- приложение строит не сразу, поэтому ждём: до 15 секунд при запуске
-- ищем именно заголовок, потом на всякий случай — любой текст «Новые».
local NEW_HEADING = { text = 'Новые', heading = true }
local NEW_ANY = { text = 'Новые' }

local function findNewHeading(timeout)
  local heading = sf.screen.waitFor(NEW_HEADING, timeout or 15000, 300)
  if not heading then
    heading = sf.screen.waitFor(NEW_ANY, 1500, 300)
  end
  return heading
end

-- Не перебиваем фокус, если человек уже ушёл в список видео.
local function focusIsInList()
  local cur = sf.screen.focused()
  if not cur then return false end
  local row = cur and parseRow(cur.text)
  return row ~= nil and row.video
end

-- Фокус уже стоит на заголовке — второй раз не дёргаем.
local function focusIsOnHeading()
  local cur = sf.screen.focused()
  return cur ~= nil and cur.text == 'Новые'
end

local focusGen = 0

-- Ставит фокус на заголовок «Новые».
-- force = true — вход в приложение: ставим фокус всегда, даже если он
-- остался на строке видео с прошлого раза.
local function focusNewSection(force)
  if sf.settings.get('focusNew') == false then return end
  focusGen = focusGen + 1
  local mine = focusGen
  sf.run(function()
    local heading = findNewHeading(force and 15000 or 6000)
    -- Пока ждали, экран сменился ещё раз — работает более поздний вызов.
    if not heading or mine ~= focusGen then return end
    if focusIsOnHeading() then return end
    -- Смена окна фокуса не отбирает: если человек уже листает список видео,
    -- оставляем его там, где он есть.
    if not force and focusIsInList() then return end
    heading:focus()
  end)
end

sf.onAppEnter(function()
  focusNewSection(true)
end)

sf.onWindowChange(function()
  focusNewSection(false)
end)

-- Вкладка «Подписки»: после переключения на неё фокус всегда на «Новые».
-- Ловим нажатие по самой вкладке, а потом убеждаемся, что на экране правда
-- есть раздел «Новые»: если фокус ушёл на другую вкладку, ничего не трогаем.
-- Название проверяем с ограничением длины: общий контейнер нижней панели,
-- в подписи которого перечислены все вкладки, так не совпадёт.
if sf.onClick then
  sf.onClick(function(event)
    if sf.settings.get('focusNew') == false then return end
    local node = event and event.node
    local label = node and (node.text or node.contentDescription) or ''
    if label == '' or #label > 40 then return end
    -- string.lower в Lua не трогает кириллицу, поэтому проверяем оба варианта.
    if not label:find('Подписк', 1, true) and not label:find('подписк', 1, true) then
      return
    end
    sf.run(function()
      local heading = sf.screen.waitFor(NEW_ANY, 5000, 300)
      if heading and not focusIsOnHeading() then
        heading:focus()
      end
    end)
  end)
end

-- Следим, когда заголовок «Новые» появляется на экране: открыли вкладку
-- «Подписки» из другой вкладки, приложение вернулось в раздел и так далее.
-- Раньше его не было, теперь есть — переводим фокус. Если он просто
-- уехал из видимой части списка, фокус не отбираем: он на строке видео.
local headingShown = false
local checkScheduled = false

local function scheduleHeadingCheck()
  if checkScheduled then return end
  checkScheduled = true
  sf.setTimeout(function()
    checkScheduled = false
    local heading = sf.screen.find(NEW_HEADING) or sf.screen.find(NEW_ANY)
    if not heading then
      headingShown = false
      return
    end
    if headingShown then return end
    headingShown = true
    focusNewSection(false)
  end, 500)
end

sf.onContentChange(scheduleHeadingCheck)

-- Ручной переход: SandFly → Команды → «Перейти к разделу «Новые»».
sf.onCommand('focus_new', function()
  local heading = findNewHeading(3000)
  if heading then
    heading:focus()
  else
    sf.speak('Раздел «Новые» не найден')
  end
end)
