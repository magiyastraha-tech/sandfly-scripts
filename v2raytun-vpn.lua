-- v2RayTun (com.v2raytun.android): доступность главного экрана.
--
-- Один переключатель ВПН. Фокус встаёт на него при открытии приложения и сразу
-- называет состояние: «ВПН отключён, кнопка». Двойное касание переключает,
-- а когда состояние меняется, скрипт говорит об этом сам — неважно, нажали
-- переключатель, пункт меню действий или приложение подключилось само.
--
-- Остальной экран тоже причёсан: строки серверов читаются одной фразой без
-- флагов и «v2RayTun», трафик подписки произносится словами, дата обновления —
-- с месяцем, иконки подписки названы по-русски, а у строки сервера в меню
-- действий появились «Подключиться», «Показать QR-код» и «Изменить».

local manifest = {
  id = 'v2raytun-vpn',
  name = 'v2RayTun: доступность',
  version = '1.0',
  author = 'magiyastraha',
  minApiVersion = 5,
  testedApiVersion = 5,
  description = 'Один переключатель ВПН, который сам называет состояние и говорит о подключении и отключении. Строки серверов читаются одной фразой без флагов, трафик подписки произносится словами, иконки подписки названы по-русски, в меню действий строки есть подключение, QR-код и изменение.',
  apps = { 'com.v2raytun.android' },
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
    -- Лампочка внутри переключателя: описание у неё «v2RayTun», толку ноль.
    { id = 'image_power', hide = true },

    -- Состояние теперь живёт на самом переключателе, отдельная строка лишняя.
    { id = 'text_status', hide = true },

    -- Сам переключатель: у RelativeLayout нет ни имени, ни роли.
    { id = 'btn_switch', label = 'ВПН', role = 'button', group = true },

    -- «Время подключения» — подпись к секундомеру; её работу делает onFocus.
    { match = { text = 'Время подключения' }, hide = true },

    -- Картинка в карточке подписки — декоративная, с описанием «v2RayTun».
    { id = 'tv_image', hide = true },

    -- Иконки подписки: у обеих описание «v2RayTun».
    { id = 'btn_reload', label = 'Обновить подписку', role = 'button' },
    { id = 'btn_expand_sub', label = 'Развернуть или свернуть список серверов', role = 'button' },
    { id = 'btn_sub', role = 'button' },

    -- Полоска заполнения дублирует текст рядом и обновляется постоянно.
    { id = 'progress_sub_info', hide = true, silence = true },

    -- Подсказка про кнопку обновления: сама кнопка уже названа, текст лишний.
    { id = 'tv_sub_announce', hide = true },

    -- Строка сервера: одно имя, один элемент, одно нажатие.
    {
      id = 'info_container',
      group = true,
      hint = 'Двойное касание подключает к серверу. Меню действий: QR-код и изменение',
    },

    -- Сам список: без подписи это была бы остановка без единого слова.
    { id = 'recycler_view', label = 'Список серверов' },

    -- Строка «КОНФИГУРАЦИИ» со стрелкой — одна кнопка.
    { id = 'layout_conf_tab', label = 'Конфигурации', role = 'button', group = true },

    -- Вкладки внизу.
    { id = 'tab_first', label = 'Вкладка Подключение', role = 'button' },
    { id = 'tab_second', label = 'Вкладка Настройки', role = 'button' },
  },
  commands = {
    { id = 'vpn-toggle', title = 'ВПН: подключить или отключить', menu = true },
    { id = 'vpn-status', title = 'ВПН: сообщить состояние', menu = true },
    { id = 'vpn-servers', title = 'ВПН: перейти к списку серверов', menu = true },
    { id = 'vpn-refresh-sub', title = 'Подписка: обновить', menu = true },
  },
  navigation = {
    { title = 'ВПН: переключатель', id = 'btn_switch' },
    { title = 'ВПН: список серверов', id = 'recycler_view' },
    { title = 'ВПН: подписка', id = 'btn_sub' },
  },
}

local TOGGLE_ID = 'btn_switch'
local POWER_ID = 'image_power'
local STATUS_ID = 'text_status'
local CHRONO_ID = 'chronometer'
local ROW_ID = 'info_container'
local SUB_HEADER_ID = 'btn_sub'
local SUB_INFO_ID = 'tv_sub_info'
local SUB_EXPIRE_ID = 'tv_sub_expire'
local SUB_EXT_ID = 'tv_ext'
local RELOAD_ID = 'btn_reload'
local EXPAND_ID = 'btn_expand_sub'
local LIST_ID = 'recycler_view'
local CONF_TAB_ID = 'layout_conf_tab'
local QR_ID = 'btn_share_qr'
local EDIT_ID = 'btn_edit'

-- Состояние ВПН, последнее прочитанное с экрана: «Не подключено», «Подключено»
-- или что-то промежуточное. В onFocus искать нельзя — на ответ тридцать
-- миллисекунд, — поэтому состояние приходит из кэша.
local state = nil

-- Что уже объявлено голосом: чтобы одно и то же не звучало дважды.
local announced = nil

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
-- в конце — тычок пальцем по центру.
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

-- Флаги стран — пары из диапазона regional indicators, по четыре байта на
-- символ; вместе со знаком варианта. Android читает их по-разному, иногда
-- никак, поэтому убираем. Заодно — отдельные эмодзи в названиях серверов.
local EMOJI = {
  '\240\159\167\178',        -- магнит
  '\240\159\143\179',        -- белый флаг
  '\239\184\143',            -- знак варианта
  '\240\159\148\132',        -- стрелки обновления
}

local function stripEmoji(value)
  local out = value:gsub('\240\159\135[\166-\191]', '')
  for _, bytes in ipairs(EMOJI) do
    out = out:gsub(bytes, '')
  end
  return out
end

local COUNT_WORDS = { [1] = 1, [2] = 2, [3] = 4, [4] = 6, [5] = 8, [6] = 10, [7] = 12, [8] = 14, [9] = 16 }

local function plural(number, one, few, many)
  local value = tonumber(number)
  if not value then return many end
  value = math.floor(value)
  local tail = value % 100
  if tail > 10 and tail < 20 then return many end
  local last = value % 10
  if last == 1 then return one end
  if last >= 2 and last <= 4 then return few end
  return many
end

local function hoursWord(number)
  return plural(number, 'час', 'часа', 'часов')
end

local function minutesWord(number)
  return plural(number, 'минута', 'минуты', 'минут')
end

local function secondsWord(number)
  return plural(number, 'секунда', 'секунды', 'секунд')
end

local SIZE_UNITS = {
  B = 'байт', KB = 'килобайт', MB = 'мегабайт', GB = 'гигабайт', TB = 'терабайт',
  ['Б'] = 'байт', ['КБ'] = 'килобайт', ['МБ'] = 'мегабайт', ['ГБ'] = 'гигабайт',
  ['ТБ'] = 'терабайт',
}

-- Названия протоколов в строках серверов. По ним строка режется на имя и
-- тип, чтобы между ними прозвучала запятая.
local PROTOCOLS = {
  'VLESS', 'VMESS', 'TROJAN', 'SHADOWSOCKS', 'HYSTERIA2', 'HYSTERIA',
  'XHTTP', 'GRPC', 'TCP', 'TLS', 'REALITY', 'WS',
}

local MONTHS = {
  [1] = 'января', [2] = 'февраля', [3] = 'марта', [4] = 'апреля',
  [5] = 'мая', [6] = 'июня', [7] = 'июля', [8] = 'августа',
  [9] = 'сентября', [10] = 'октября', [11] = 'ноября', [12] = 'декабря',
}

-- «600,0» → «600»: хвостовой ноль на слух только мешает.
local function numberSpeech(value)
  if not value then return value end
  return (value:gsub('[,%.]0$', ''))
end

-- «16,9 GB/600,0 GB» → «Трафик: 16,9 из 600 гигабайт».
local function subInfoSpeech(text)
  if not text then return nil end
  local used, usedUnit, total, totalUnit =
    text:match('([%d%.,]+)%s*(%a+)%s*/%s*([%d%.,]+)%s*(%a+)')
  if not used then return nil end
  used = numberSpeech(used)
  total = numberSpeech(total)
  local unit = SIZE_UNITS[totalUnit] or totalUnit
  if (SIZE_UNITS[usedUnit] or usedUnit) ~= unit then
    return 'Трафик: ' .. used .. ' ' .. (SIZE_UNITS[usedUnit] or usedUnit) ..
      ' из ' .. total .. ' ' .. unit
  end
  return 'Трафик: ' .. used .. ' из ' .. total .. ' ' .. unit
end

-- «Активна до: 29 ноября 2026 14:00» → «Подписка активна до 29 ноября 2026, 14:00».
local function subExpireSpeech(text)
  if not text or text == '' then return nil end
  local rest = text:gsub('^%s*Активна до:%s*', '')
  if rest == text then return nil end
  rest = rest:gsub('(%d%d%d%d)%s+(%d%d:%d%d)$', '%1, %2')
  return 'Подписка активна до ' .. trim(rest)
end

-- «18.11.2026 17:15» → «Подписка обновлена 18 ноября 2026 в 17:15».
local function subExtSpeech(text)
  if not text then return nil end
  local day, month, year, hour, minute =
    text:match('(%d%d)%.(%d%d)%.(%d%d%d%d)%s+(%d%d):(%d%d)')
  if not day then return nil end
  local name = MONTHS[tonumber(month)]
  if not name then return nil end
  return 'Подписка обновлена ' .. tonumber(day) .. ' ' .. name .. ' ' .. year .. ' в ' .. hour .. ':' .. minute
end

-- «00:12:34» → «Время подключения: 12 минут».
local function chronoSpeech(item)
  local description = item and item.contentDescription
  if description and description ~= '' then
    return 'Время подключения: ' .. description
  end
  local raw = item and item.text
  if not raw then return nil end
  local hours, minutes, seconds = raw:match('^(%d+):(%d+):(%d+)$')
  if not hours then return nil end
  local parts = {}
  local h, m, s = tonumber(hours), tonumber(minutes), tonumber(seconds)
  if h and h > 0 then parts[#parts + 1] = h .. ' ' .. hoursWord(h) end
  if m and m > 0 then parts[#parts + 1] = m .. ' ' .. minutesWord(m) end
  if #parts == 0 then
    parts[1] = (s or 0) .. ' ' .. secondsWord(s or 0)
  end
  return 'Время подключения: ' .. table.concat(parts, ' ')
end

-- Строка сервера: «🇩🇪  LTE  Германия #3 | 0.0/20 ГБ · 24ч  JSON / VLESS / XHTTP
-- v2RayTun» → «LTE Германия номер 3, 0,0 из 20 гигабайт, 24 часа, VLESS, XHTTP».
local function cleanRow(text)
  if not text or text == '' then return nil end
  local value = stripEmoji(text)

  -- Протоколы: «JSON / VLESS / TCP» → «VLESS, TCP».
  value = value:gsub('JSON%s*/%s*([%w%-]+)%s*/%s*([%w%-]+)', '%1, %2')
  value = value:gsub('JSON%s*/%s*([%w%-]+)', '%1')

  -- Номер сервера: «#3» → «номер 3».
  value = value:gsub('%s*#%s*(%d+)', ' номер %1')

  -- Остаток трафика: «0.0/20» → «0 из 20».
  value = value:gsub('(%d+)%.(%d+)%s*/%s*(%d+)', '%1,%2 из %3')
  value = value:gsub('(%d+)%s*/%s*(%d+)', '%1 из %2')

  -- Единицы и время.
  value = value:gsub('ГБ', ' гигабайт')
  value = value:gsub('ТБ', ' терабайт')
  value = value:gsub('МБ', ' мегабайт')
  value = value:gsub('(%d+)%s*ч', function(number)
    return number .. ' ' .. hoursWord(number)
  end)

  -- «0,0 из 20» → «0 из 20»: хвостовой ноль на слух лишний.
  value = value:gsub('(%d+)[,%.]0(%s)', '%1%2')

  -- Разделители и мусор из иконок.
  value = value:gsub('|', ',')
  value = value:gsub('·', ',')
  value = value:gsub('v2RayTun', '')

  -- Имя сервера и протокол — через запятую: «Германия VLESS» → «Германия, VLESS».
  for _, proto in ipairs(PROTOCOLS) do
    local head, tail = value:match('^(.-)%s+(' .. proto .. '.*)$')
    if head and head ~= '' then
      value = head .. ', ' .. tail
      break
    end
  end
  value = value:gsub('%s+', ' ')
  value = value:gsub('^%s*[,;%s]+', '')
  value = value:gsub('[,;%s]+$', '')
  value = value:gsub('%s+,', ',')
  value = trim(value)
  if value == '' then return nil end
  return value
end

-- Состояние словами. Промежуточные надписи приложения тоже переводим: пока
-- идёт подключение, полезно слышать, что оно идёт, а не молчание.
local function msgFor(text)
  if not text or text == '' then return nil end
  if text:find('Не подключено', 1, true) then return 'ВПН отключён' end
  if text:find('Ошибк', 1, true) then return 'ВПН: ошибка подключения' end
  if text:find('Отключено', 1, true) then return 'ВПН отключён' end
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

local function announce(text)
  local message = msgFor(text)
  if not message or message == announced then return end
  announced = message
  if sf.settings.get('announce') == false then return end
  sf.speak(message, { interrupt = false })
end

local function noteState(text)
  if not text or text == '' or text == state then return end
  state = text
  announce(text)
end

-- Перечитывает состояние с экрана и запоминает без озвучивания: при открытии
-- приложения пересказывать состояние незачем.
local function refresh()
  local status = textOf(STATUS_ID)
  if status then
    state = status
    announced = msgFor(status)
  end
end

-- Переключение ВПН. Нажатие идёт сразу, а результат ловится отдельно: пока
-- приложение не поменяло надпись, говорить «включён» нельзя.
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
  if before and (before:find('Не подключено', 1, true) or before:find('Отключено', 1, true)) then
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

-- При открытии приложение ставит фокус на кнопку «Добавить». Переводим его на
-- переключатель, чтобы первое, что слышно, было состояние и способы нажать.
local function focusToggle()
  if sf.settings.get('jump') == false then return end
  local focused = sf.screen.focused()
  if not focused then return end

  local onStatus = hasId(focused, STATUS_ID)
  local onAdd = focused.contentDescription == 'Добавить'
  if not (onStatus or onAdd) then return end

  local toggle = findById(TOGGLE_ID)
  if toggle then
    pcall(function() return toggle:focus() end)
  end
end

-- Голос элемента в фокусе. Всё, что здесь нужно, уже лежит в переменных или
-- в самом элементе: на ответ у хука тридцать миллисекунд.
sf.onFocus(function(item, text)
  if not item then return nil end

  if hasId(item, TOGGLE_ID) or hasId(item, POWER_ID) then
    return { speak = stateSpeech() .. ', кнопка' }
  end

  if hasId(item, STATUS_ID) then
    return { speak = stateSpeech() }
  end

  if hasId(item, CHRONO_ID) then
    local speech = chronoSpeech(item)
    if speech then return { speak = speech } end
    return nil
  end

  if hasId(item, ROW_ID) then
    local speech = cleanRow(item.text) or cleanRow(text)
    if speech then return { speak = speech } end
    return nil
  end

  if hasId(item, SUB_INFO_ID) then
    local speech = subInfoSpeech(item.text)
    if speech then return { speak = speech } end
    return nil
  end

  if hasId(item, SUB_EXPIRE_ID) then
    local speech = subExpireSpeech(item.text)
    if speech then return { speak = speech } end
    return nil
  end

  if hasId(item, SUB_EXT_ID) then
    local speech = subExtSpeech(item.text)
    if speech then return { speak = speech } end
    return nil
  end

  if hasId(item, CONF_TAB_ID) then
    return { speak = 'Конфигурации, кнопка' }
  end

  return nil
end)

-- Приложение меняет надпись состояния само, и это ловит именно здесь: путь
-- неважен — своё нажатие, двойное касание или автоподключение.
sf.onContentChange(function(event)
  local node = event and event.node
  if not node then return end
  if hasId(node, STATUS_ID) and node.text then
    noteState(node.text)
  end
end)

local function childOf(item, id)
  local ok, child = pcall(function() return item:find({ id = id }) end)
  if ok then return child end
  return nil
end

-- Действия в меню. У переключателя одно, с честным названием по состоянию.
-- У строки сервера — подключение, QR-код и изменение.
sf.onActions(function(item)
  if hasId(item, TOGGLE_ID) or hasId(item, POWER_ID) then
    refresh()

    local title
    if state and (state:find('Не подключено', 1, true) or state:find('Отключено', 1, true)) then
      title = 'Включить ВПН'
    elseif state and state:find('Подключено', 1, true) then
      title = 'Отключить ВПН'
    else
      title = 'Переключить ВПН'
    end

    return {
      { title = title, first = true, run = toggleVpn },
    }
  end

  if hasId(item, ROW_ID) then
    local row = item

    local qr = childOf(row, QR_ID)
    local edit = childOf(row, EDIT_ID)

    local list = {
      { title = 'Подключиться к серверу', first = true, run = function() press(row) end },
    }

    if qr then
      list[#list + 1] = {
        title = 'Показать QR-код',
        run = function() press(qr) end,
      }
    end
    if edit then
      list[#list + 1] = {
        title = 'Изменить',
        run = function() press(edit) end,
      }
    end

    return list
  end

  return nil
end)

sf.onCommand('vpn-toggle', function()
  toggleVpn()
end)

sf.onCommand('vpn-status', function()
  local status = textOf(STATUS_ID)
  if status then state = status end
  sf.speak(stateSpeech())
end)

sf.onCommand('vpn-servers', function()
  local list = findById(LIST_ID)
  if not list then
    sf.speak('Список серверов не найден')
    return
  end
  pcall(function() return list:showOnScreen() end)
  pcall(function() return list:focus() end)
end)

sf.onCommand('vpn-refresh-sub', function()
  local reload = findById(RELOAD_ID)
  if not reload then
    sf.speak('Кнопка обновления подписки не найдена')
    return
  end
  sf.speak('Обновляю подписку')
  press(reload)
end)

-- Приложение ушло на передний план или скрипт только что загрузился: читаем
-- состояние сразу и ещё раз чуть позже, если экран ещё дорисовывался.
sf.onAppEnter(function(event)
  if event and event.package and event.package ~= 'com.v2raytun.android' then return end

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
