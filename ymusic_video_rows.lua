-- YMusic: в строке видео только название и время.
-- Остальное (канал, просмотры, дата публикации) и кнопка «Ещё» — в меню действий.

local manifest = {
  id = 'ymusic.video_rows',
  name = 'YMusic: название и время',
  author = 'Алёшка',
  version = '1.2',
  minApiVersion = 1,
  testedApiVersion = 4,
  description = 'В списках видео строка читает только название и время. Канал, просмотры, дата публикации и кнопка «Ещё» переезжают в меню действий. При запуске фокус сам встаёт на раздел «Новые».',
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
    -- Кнопку «Ещё» внутри строки видео прячем: она уходит в меню действий.
    -- Только match, без id: id вместе с match требует совпадения и по id, и по запросу.
    {
      match = { className = 'Button', contentDescription = 'Ещё', inside = { textContains = 'Видео' } },
      hide = true,
    },
    {
      match = { className = 'Button', contentDescription = 'More', inside = { textContains = 'Video' } },
      hide = true,
    },
  },
}

local function trim(s)
  return (s:gsub('^%s+', ''):gsub('%s+$', ''))
end

-- Позиция последнего вхождения sep в строке, или nil.
local function lastPos(s, sep)
  local pos, from = nil, 1
  while true do
    local a = string.find(s, sep, from, true)
    if not a then return pos end
    pos = a
    from = a + #sep
  end
end

-- Разбирает строку YMusic вида:
--   Видео, <название>, <длительность>, <канал> · <просмотры> · <когда>
-- Название может содержать запятые, поэтому режем с конца.
local function parseVideoRow(text)
  if type(text) ~= 'string' or text == '' then return nil end

  local sep = ' · '

  local pubPos = lastPos(text, sep)
  if not pubPos then return nil end
  local published = trim(text:sub(pubPos + #sep))
  local rest1 = text:sub(1, pubPos - 1)

  local viewsPos = lastPos(rest1, sep)
  if not viewsPos then return nil end
  local views = trim(rest1:sub(viewsPos + #sep))
  local head = rest1:sub(1, viewsPos - 1)

  local parts, start = {}, 1
  while true do
    local comma = string.find(head, ',', start, true)
    if not comma then
      parts[#parts + 1] = trim(head:sub(start))
      break
    end
    parts[#parts + 1] = trim(head:sub(start, comma - 1))
    start = comma + 1
  end

  if #parts < 4 then return nil end

  local kind = parts[1]
  if kind ~= 'Видео' and string.lower(kind) ~= 'video' then return nil end

  local channel = parts[#parts]
  local duration = parts[#parts - 1]
  local titleParts = {}
  for i = 2, #parts - 2 do
    titleParts[#titleParts + 1] = parts[i]
  end
  local title = table.concat(titleParts, ', ')

  if title == '' or channel == '' or duration == '' or views == '' then return nil end

  return {
    title = title,
    duration = duration,
    channel = channel,
    views = views,
    published = published,
  }
end

local function lineTime(row)
  local mode = sf.settings.get('lineTime') or 'duration'
  if mode == 'published' then return row.published end
  if mode == 'both' then return row.duration .. ', ' .. row.published end
  return row.duration
end

local function restText(row)
  local mode = sf.settings.get('lineTime') or 'duration'
  local parts = {}
  if mode == 'published' then parts[#parts + 1] = row.duration end
  parts[#parts + 1] = row.views
  if mode == 'duration' then parts[#parts + 1] = row.published end
  return table.concat(parts, ', ')
end

-- Строка видео говорит только название и время.
sf.onFocus(function(item, text)
  local row = item and parseVideoRow(item.text)
  if not row and text then row = parseVideoRow(text) end
  if not row then return nil end
  if sf.settings.get('shorten') == false then return nil end
  return { speak = row.title .. ', ' .. lineTime(row) }
end)

-- Действия: канал, остальная информация и кнопка «Ещё».
sf.onActions(function(item)
  local row = item and parseVideoRow(item.text)
  if not row then return nil end

  local actions = {
    {
      title = 'Канал: ' .. row.channel,
      run = function()
        sf.speak('Канал: ' .. row.channel)
      end,
    },
  }

  local rest = restText(row)
  if rest ~= '' then
    actions[#actions + 1] = {
      title = 'Остальное: ' .. rest,
      run = function()
        sf.speak(rest)
      end,
    }
  end

  actions[#actions + 1] = {
    title = 'Ещё',
    run = function(it)
      local button = it and it:find({ className = 'Button', contentDescription = 'Ещё' })
      if not button and it then button = it:find({ className = 'Button', contentDescription = 'More' }) end
      if not button and it then button = it:find({ className = 'Button', text = 'Ещё' }) end
      if not button and it then button = it:find({ className = 'Button' }) end
      if button then
        button:click()
      else
        sf.speak('Кнопка «Ещё» не найдена')
      end
    end,
  }

  return actions
end)

-- ── Фокус на разделе «Новые» ──

-- Заголовок раздела «Новые» на экране подписок. Разметку списка
-- приложение строит не сразу, поэтому ждём: до 15 секунд при запуске
-- ищем именно заголовок, потом на всякий случай — любой текст «Новые».
local function findNewHeading(timeout)
  local heading = sf.screen.waitFor({ text = 'Новые', heading = true }, timeout or 15000, 300)
  if not heading then
    heading = sf.screen.waitFor({ text = 'Новые' }, 1500, 300)
  end
  return heading
end

-- Не перебиваем фокус, если человек уже ушёл в список видео.
local function focusIsInList()
  local cur = sf.screen.focused()
  if not cur then return false end
  return parseVideoRow(cur.text) ~= nil
end

local focusGen = 0

local function focusNewSection()
  if sf.settings.get('focusNew') == false then return end
  focusGen = focusGen + 1
  local mine = focusGen
  sf.run(function()
    local heading = findNewHeading(15000)
    -- Пока ждали, экран сменился ещё раз — работает более поздний вызов.
    if not heading or mine ~= focusGen then return end
    if focusIsInList() then return end
    heading:focus()
  end)
end

sf.onAppEnter(function()
  focusNewSection()
end)

sf.onWindowChange(function()
  focusNewSection()
end)

-- Ручной переход: SandFly → Команды → «Перейти к разделу «Новые»».
sf.onCommand('focus_new', function()
  local heading = findNewHeading(3000)
  if heading then
    heading:focus()
  else
    sf.speak('Раздел «Новые» не найден')
  end
end)
