-- КИБЕРПОРТАЛ БС (com.cybportal.bs): доступность главного экрана.
--
-- Один переключатель ВПН. Фокус встаёт на него при открытии приложения и сразу
-- называет состояние: «ВПН подключён, кнопка». Двойное касание переключает,
-- а когда состояние меняется, скрипт говорит об этом сам — неважно, нажали
-- переключатель, кнопку в меню действий или приложение подключилось само.
--
-- Версия 1.1 — под новый интерфейс приложения: нижние вкладки переехали на
-- land_nav_vpn и land_nav_settings, над переключателем появилась надпись
-- «СТАРТ», в заголовке панели — «УЗЕЛ» и пинг узла, а трафика на главном
-- экране больше нет. Причёсано всё остальное: декоративные надписи убраны из
-- обхода, строки выбора сервера читаются целиком, режимы и страны названы
-- по-русски, флаг из названия страны убран, вкладки названы словами.

local manifest = {
  id = 'cyberportal-vpn',
  name = 'КИБЕРПОРТАЛ БС: доступность',
  version = '1.1',
  author = 'magiyastraha',
  minApiVersion = 5,
  testedApiVersion = 5,
  description = 'Один переключатель ВПН, который сам называет состояние и говорит о подключении и отключении. Убирает из обхода декоративные надписи и дублирующие элементы, читает строки списка серверов целиком, называет пинг узла и вкладки по-русски.',
  apps = { 'com.cybportal.bs' },
  permissions = { 'screen', 'actions', 'speech', 'input' },
  settings = {
    {
      key = 'jump',
      type = 'switch',
      title = 'При открытии ставить фокус на переключатель ВПН',
      default = true,
    },
    {
      key = 'announce',
      type = 'switch',
      title = 'Говорить о подключении и отключении',
      default = true,
    },
  },
  rules = {
    -- Декоративные надписи: в обходе они только мешают.
    { match = { text = 'КИБЕРПОРТАЛ // БС' }, hide = true },
    { match = { text = 'CYBERPORTAL // BS' }, hide = true },
    { match = { text = 'КИБЕРПОРТАЛ' }, hide = true },
    { match = { text = 'УЗЕЛ' }, hide = true },
    { id = 'action_panel_label', hide = true },
    { match = { text = 'N' }, hide = true },

    -- Номера режимов выбора сервера: «01» перед названием ничего не добавляет.
    { match = { text = '01' }, hide = true },
    { match = { text = '02' }, hide = true },
    { match = { text = '03' }, hide = true },
    { match = { text = '04' }, hide = true },

    -- Лампочка внутри переключателя дублирует его отдельной остановкой.
    { id = 'power_icon', hide = true },

    -- Состояние теперь живёт на самом переключателе, отдельная строка лишняя.
    { id = 'status_text', hide = true },

    -- Сам переключатель: одно имя, один элемент, одно нажатие.
    { id = 'vpn_toggle', label = 'ВПН', role = 'button', group = true },

    -- Кнопка поддержки: убираем эмодзи из имени.
    { id = 'btn_coffee_tip', label = 'Поддержать проект', role = 'button' },

    -- Панель выбора сервера: заголовок читается целиком и одним элементом.
    { id = 'bottom_sheet', label = 'Панель выбора сервера' },
    { id = 'bottom_sheet_header', label = 'Выбор сервера', group = true },

    -- Заголовки списков — заголовки, чтобы по ним можно было прыгать.
    { match = { text = 'Режим выбора сервера' }, heading = true },
    { id = 'countries_header', heading = true },
    { id = 'servers_header', heading = true },

    -- Строки стран, серверов и режимов: своего текста у них нет, поэтому
    -- читаем строку целиком, а не четыре отдельных куска без контекста.
    {
      activity = 'MainActivity',
      match = {
        className = 'LinearLayout',
        clickable = true,
        focusable = true,
        inside = { className = 'ScrollView' },
      },
      group = true,
    },

    -- Сам список: без подписи это была бы остановка без единого слова.
    {
      activity = 'MainActivity',
      match = { className = 'ScrollView' },
      label = 'Список серверов и стран',
      hint = 'Проведите двумя пальцами, чтобы прокрутить',
    },

    -- Вкладки внизу: сама вкладка названа словами, а картинка и подпись
    -- внутри неё — дубли, их из обхода убираем.
    { id = 'land_nav_vpn', label = 'Вкладка ВПН' },
    { id = 'land_nav_settings', label = 'Вкладка Настройки' },
    { match = { text = 'VPN', inside = { id = 'land_nav_vpn' } }, hide = true },
    { match = { contentDescription = 'VPN', inside = { id = 'land_nav_vpn' } }, hide = true },
    { match = { text = 'НАСТРОЙКИ', inside = { id = 'land_nav_settings' } }, hide = true },
    { match = { contentDescription = 'Настройки', inside = { id = 'land_nav_settings' } }, hide = true },
  },
  commands = {
    { id = 'vpn-toggle', title = 'ВПН: включить или отключить', menu = true },
    { id = 'vpn-status', title = 'ВПН: сообщить состояние', menu = true },
    { id = 'vpn-server', title = 'ВПН: перейти к выбору сервера', menu = true },
  },
  navigation = {
    { title = 'ВПН: переключатель', id = 'vpn_toggle' },
    { title = 'ВПН: выбор сервера', id = 'bottom_sheet_header' },
    { title = 'ВПН: режим выбора', match = { text = 'Режим выбора сервера' } },
    { title = 'ВПН: страны', id = 'countries_header' },
    { title = 'ВПН: серверы', id = 'servers_header' },
  },
}

local TOGGLE_ID = 'vpn_toggle'
local POWER_ID = 'power_icon'
local STATUS_ID = 'status_text'
local HEADER_ID = 'bottom_sheet_header'
local SERVER_NAME_ID = 'selected_server_name'
local SERVER_COUNT_ID = 'selected_server_count'
local PING_ID = 'exit_node_ping'
local EXIT_HINT_ID = 'connection_instruction'
local TRAFFIC_ID = 'traffic_stats_text'

-- Состояние ВПН, последнее прочитанное с экрана: «Подключено», «Отключено»
-- или что-то промежуточное вроде «Подключение». В onFocus искать нельзя —
-- на ответ тридцать миллисекунд, — поэтому состояние приходит из кэша.
local state = nil

-- Что уже объявлено голосом: чтобы одно и то же не звучало дважды.
local announced = nil

local serverName = nil
local serverCount = nil
local ping = nil
local country = nil

-- Сколько ждём, пока приложение поменяет состояние на экране.
local STEP_MS = 300
local STEPS = 12

local function trim(text)
  if not text then return '' end
  return (text:gsub('^%s+', ''):gsub('%s+$', ''))
end

local function hasId(item, name)
  local id = item and item.id
  return id ~= nil and id:find(name, 1, true) ~= nil
end

local function findById(id)
  local ok, item = pcall(function() return sf.screen.find({ id = id }) end)
  if ok then return item end
  return nil
end

local function textOf(id)
  local item = findById(id)
  if item and item.text and item.text ~= '' then return item.text end
  return nil
end

-- Нажимает элемент: обычное нажатие, затем касание средствами доступности,
-- в конце — тычок пальцем по центру. Не всякий самодельный переключатель
-- понимает все три, поэтому пробуем по очереди.
local function press(item)
  local ok, clicked = pcall(function() return item:click() end)
  if ok and clicked then return true end
  local tapOk, tapped = pcall(function() return item:tap() end)
  if tapOk and tapped == true then return true end
  local bounds = item.bounds
  if bounds then
    local x = math.floor(((bounds.left or 0) + (bounds.right or 0)) / 2)
    local y = math.floor(((bounds.top or 0) + (bounds.bottom or 0)) / 2)
    if x > 0 and y > 0 then
      local touchOk = pcall(function() return sf.touch.tap(x, y) end)
      if touchOk then return true end
    end
  end
  return false
end

-- В новом интерфейсе перед подсказкой появилась стрелка «◀». В UTF-8 это
-- три байта, и диктор читает их как «треугольник», если не убрать.
local ARROW_LEFT = '\226\151\128'
local ARROW_RIGHT = '\226\150\184'

local function stripArrows(value)
  value = value:gsub('^' .. ARROW_LEFT .. '%s*', '')
  value = value:gsub('^' .. ARROW_RIGHT .. '%s*', '')
  return value
end

-- Флаг страны — два символа подряд из диапазона regional indicators, восемь
-- байт в UTF-8. Android читает их по-разному, иногда никак; убираем.
local function countryOf(text)
  if not text then return nil end
  local value = text
  if value:sub(1, 2) == '\240\159' and value:sub(5, 6) == '\240\159' then
    value = value:sub(9)
  end
  value = trim(stripArrows(value))
  if value == '' then return nil end
  return value
end

-- Поле connection_instruction теперь двуликое: при подключении в нём страна
-- выхода, а при отключении — подсказка «Нажми кнопку слева». Подсказку
-- читаем как есть, без приставки «Страна».
local function isHint(value)
  if not value then return false end
  return value:find('ажми', 1, true) ~= nil
      or value:find('ыбер', 1, true) ~= nil
      or value:find('ыбери', 1, true) ~= nil
end

-- Код сервера вроде «RU017» или «FI1»: рядом с названием он лишний.
local function looksLikeCode(value)
  if not value or value == '' then return false end
  return value:match('^[%u%d%.%-]+$') ~= nil
end

local SIZE_UNITS = {
  B = 'байт', KB = 'килобайт', MB = 'мегабайт', GB = 'гигабайт', TB = 'терабайт',
  ['Б'] = 'байт', ['КБ'] = 'килобайт', ['МБ'] = 'мегабайт', ['ГБ'] = 'гигабайт',
  ['ТБ'] = 'терабайт',
}

local function humanSize(value)
  local number, unit = value:match('^([%d%.,]+)%s*(%S+)$')
  if not number then return value end
  return number .. ' ' .. (SIZE_UNITS[unit] or unit)
end

local function humanSpeed(value)
  local speed = value
  speed = speed:gsub('Gbit/s', ' гигабит в секунду')
  speed = speed:gsub('Mbit/s', ' мегабит в секунду')
  speed = speed:gsub('kbit/s', ' килобит в секунду')
  speed = speed:gsub('bit/s', ' бит в секунду')
  speed = speed:gsub('B/s', ' байт в секунду')
  speed = speed:gsub('%s+', ' ')
  return trim(speed)
end

local function isZero(value)
  return value:match('^0%f[%s%.,]') ~= nil
end

local function prettyTraffic(text)
  if not text then return nil end
  local downSpeed, downSize = text:match('↓%s*([^%(]-)%s*%(([^%)]*)%)')
  local upSpeed, upSize = text:match('↑%s*([^%(]-)%s*%(([^%)]*)%)')
  if not downSize and not upSize then return nil end

  local parts = {}
  if downSize then
    local part = 'принято ' .. humanSize(trim(downSize))
    local speed = trim(downSpeed)
    if speed ~= '' and not isZero(speed) then
      part = part .. ', скорость ' .. humanSpeed(speed)
    end
    parts[#parts + 1] = part
  end
  if upSize then
    local part = 'отправлено ' .. humanSize(trim(upSize))
    local speed = trim(upSpeed)
    if speed ~= '' and not isZero(speed) then
      part = part .. ', скорость ' .. humanSpeed(speed)
    end
    parts[#parts + 1] = part
  end
  return 'Трафик: ' .. table.concat(parts, '; ')
end

-- Состояние словами. Промежуточные надписи приложения тоже переводим: пока
-- идёт подключение, полезно слышать, что оно идёт, а не молчание.
local function msgFor(text)
  if not text or text == '' then return nil end
  if text:find('Отключено', 1, true) then return 'ВПН отключён' end
  if text:find('Ошибк', 1, true) then return 'ВПН: ошибка подключения' end
  if text:find('Отключ', 1, true) then return 'ВПН отключается' end
  if text:find('Подключено', 1, true) then return 'ВПН подключён' end
  if text:find('Подключ', 1, true) then return 'ВПН подключается' end
  return nil
end

local function stateSpeech()
  local message = msgFor(state)
  if message then return message end
  if state and state ~= '' then return 'ВПН: ' .. state end
  return 'ВПН'
end

-- Заголовок панели называет выбранный режим или узел: «Надёжно, наиболее
-- стабильный». Если вместо подписи стоит код сервера, он не нужен — название
-- уже сказано.
local function headerSpeech()
  local parts = {}
  if serverName and serverName ~= '' then
    parts[#parts + 1] = serverName
  end
  if serverCount and serverCount ~= '' and serverCount ~= serverName
      and not looksLikeCode(serverCount) then
    parts[#parts + 1] = serverCount
  end
  if ping then
    parts[#parts + 1] = 'пинг ' .. ping
  end
  if #parts == 0 then return nil end
  return 'Выбор сервера: ' .. table.concat(parts, ', ')
end

local function announce(text)
  local message = msgFor(text)
  if not message or message == announced then return end
  announced = message
  if sf.settings.get('announce') == false then return end
  if message == 'ВПН подключён' and country then
    message = message .. ', ' .. country
  end
  sf.speak(message, { interrupt = false })
end

local function noteState(text)
  if not text or text == '' or text == state then return end
  state = text
  announce(text)
end

local function noteExit(text)
  local value = countryOf(text)
  if value and not isHint(value) then country = value end
end

-- Перечитывает всё, что живёт на экране, и запоминает без озвучивания:
-- при открытии приложения пересказывать состояние незачем.
local function refresh()
  local status = textOf(STATUS_ID)
  if status then
    state = status
    announced = msgFor(status)
  end

  local name = countryOf(textOf(SERVER_NAME_ID))
  if name and not isHint(name) then serverName = name end

  local count = trim(textOf(SERVER_COUNT_ID))
  if count ~= '' then serverCount = count end

  local latency = trim(textOf(PING_ID))
  if latency ~= '' and latency ~= '—' then
    ping = latency
  else
    ping = nil
  end

  noteExit(textOf(EXIT_HINT_ID))
end

-- Переключение ВПН. Нажатие идёт сразу, а результат ловится отдельно: пока
-- приложение не поменяло надпись, говорить «включено» нельзя.
local function toggleVpn()
  refresh()

  local toggle = findById(TOGGLE_ID) or findById(POWER_ID)
  if not toggle then
    sf.speak('Переключатель ВПН не найден')
    return
  end

  local before = state
  local beforeAnnounced = announced

  local lead
  if before and before:find('Отключено', 1, true) then
    lead = 'Включаю ВПН'
  elseif before and before:find('Подключено', 1, true) then
    lead = 'Отключаю ВПН'
  else
    lead = 'Переключаю ВПН'
  end
  sf.speak(lead)

  if not press(toggle) then
    sf.speak('Переключатель ВПН не нажался')
    return
  end

  local steps = 0
  local function look()
    sf.setTimeout(function()
      local now = textOf(STATUS_ID)
      if now and now ~= before then
        state = now
        -- Если onContentChange уже объявил, второй раз не повторяем.
        if announced == beforeAnnounced then
          announce(now)
        end
        return
      end
      steps = steps + 1
      if steps < STEPS then
        look()
      else
        sf.speak('Состояние ВПН не изменилось')
      end
    end, STEP_MS)
  end
  look()
end

-- Есть ли у элемента настоящий фокус. У корня окна родителя нет, и его
-- «фокус» — это просто отсутствие фокуса где-либо.
local function hasRealFocus(item)
  if not item then return false end
  local parent = nil
  pcall(function() parent = item:parent() end)
  return parent ~= nil
end

-- При открытии приложение может оставить фокус где угодно или нигде. Если
-- нигде или на скрытой строке состояния — переводим на переключатель, чтобы
-- первое, что слышно, было состояние и способы нажать.
local function focusToggle()
  if sf.settings.get('jump') == false then return end

  local toggle = findById(TOGGLE_ID)
  if not toggle then return end

  local focused = sf.screen.focused()
  if focused and hasRealFocus(focused)
      and not hasId(focused, STATUS_ID)
      and not hasId(focused, TOGGLE_ID)
      and not hasId(focused, POWER_ID) then
    return
  end

  pcall(function() return toggle:focus() end)
end

-- Голос элемента в фокусе. Всё, что здесь нужно, уже лежит в переменных:
-- на ответ у хука тридцать миллисекунд, искать по экрану тут нельзя.
sf.onFocus(function(item, text)
  if hasId(item, TOGGLE_ID) or hasId(item, POWER_ID) then
    return { speak = stateSpeech() .. ', кнопка' }
  end

  if hasId(item, STATUS_ID) then
    return { speak = stateSpeech() }
  end

  if hasId(item, HEADER_ID) then
    local speech = headerSpeech()
    if speech then return { speak = speech } end
    return nil
  end

  if hasId(item, PING_ID) then
    local value = trim(item.text)
    if value ~= '' and value ~= '—' then
      return { speak = 'Пинг: ' .. value }
    end
    return nil
  end

  if hasId(item, EXIT_HINT_ID) then
    local value = countryOf(item.text) or country
    if not value then return nil end
    if isHint(value) then return { speak = value } end
    return { speak = 'Страна: ' .. value }
  end

  if hasId(item, TRAFFIC_ID) then
    local speech = prettyTraffic(item.text)
    if speech then return { speak = speech } end
    return nil
  end

  return nil
end)

-- Приложение меняет надпись состояния само, и это ловит именно здесь: путь
-- неважен — своё нажатие, двойное касание по переключателю или автосоединение.
sf.onContentChange(function(event)
  local node = event and event.node
  if not node then return end

  if hasId(node, STATUS_ID) then
    if node.text then noteState(node.text) end
  elseif hasId(node, SERVER_NAME_ID) then
    local name = countryOf(node.text)
    if name and not isHint(name) then serverName = name end
  elseif hasId(node, SERVER_COUNT_ID) then
    local count = trim(node.text)
    if count ~= '' then serverCount = count end
  elseif hasId(node, PING_ID) then
    local latency = trim(node.text)
    if latency ~= '' and latency ~= '—' then
      ping = latency
    else
      ping = nil
    end
  elseif hasId(node, EXIT_HINT_ID) then
    noteExit(node.text)
  end
end)

-- Действие в меню переключателя: одно, с честным названием по состоянию.
sf.onActions(function(item)
  if not (hasId(item, TOGGLE_ID) or hasId(item, POWER_ID)) then return nil end
  refresh()

  local title
  if state and state:find('Отключено', 1, true) then
    title = 'Включить ВПН'
  elseif state and state:find('Подключено', 1, true) then
    title = 'Отключить ВПН'
  else
    title = 'Переключить ВПН'
  end

  return {
    { title = title, first = true, run = toggleVpn },
  }
end)

sf.onCommand('vpn-toggle', function()
  toggleVpn()
end)

sf.onCommand('vpn-status', function()
  local status = textOf(STATUS_ID)
  if status then state = status end
  local message = stateSpeech()
  if message == 'ВПН подключён' and country then
    message = message .. ', ' .. country
  end
  sf.speak(message)
end)

sf.onCommand('vpn-server', function()
  local header = findById(HEADER_ID)
  if not header then
    sf.speak('Выбор сервера не найден')
    return
  end
  pcall(function() return header:showOnScreen() end)
  pcall(function() return header:focus() end)
end)

-- Приложение ушло на передний план или скрипт только что загрузился: читаем
-- состояние сразу и ещё раз чуть позже, если экран ещё дорисовывался.
sf.onAppEnter(function(event)
  if event and event.package and event.package ~= 'com.cybportal.bs' then return end

  refresh()
  sf.setTimeout(function()
    refresh()
  end, 500)
  sf.setTimeout(function()
    refresh()
    focusToggle()
  end, 900)
  sf.setTimeout(function()
    focusToggle()
  end, 1800)
end)
