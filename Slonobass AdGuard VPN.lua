-- Slonobass AdGuard VPN — скрипт для SandFly.
--
-- Что меняет на главном экране AdGuard VPN:
--
-- 1. Верхнюю промо-плашку «Как сохранить соединение?» прячет целиком:
--    и сам бейдж, и прокручиваемую область, в которой он лежит.
-- 2. Статус защиты (protection_status) и строку страны (preview) убирает
--    из листания. Из трёх отдельных пунктов — статус, кнопка
--    «Подключить» и страна — остаётся один: кнопка. При свайпе на неё
--    звучит «Отключено, Италия, Рим, 82 мс, кнопка»; после подключения —
--    «Подключено, Италия, Рим, 82 мс, кнопка».
-- 3. Двойной тап по этой кнопке подключает и отключает ВПН, как и раньше.
-- 4. В меню действий на этой же кнопке два пункта: «Подключить» или
--    «Отключить» — по текущему состоянию, и «Страна: Италия, Рим» —
--    открывает выбор сервера.
--
-- Состояние и страну скрипт запоминает заранее, а не ищет по экрану
-- в момент озвучивания: в хуке onFocus на поиск нет времени (30 мс).
-- Обновляет он их при входе в приложение, при смене содержимого
-- и при смене окна.
--
-- В настройках скрипта — переключатель «Упростить главный экран»:
-- снять его — все правки снимаются, приложение снова как есть.

local manifest = {
  id = 'wam.adguard-vpn-home',
  name = 'Slonobass AdGuard VPN',
  version = '2.0',
  author = 'Алёшка',
  minApiVersion = 6,
  testedApiVersion = 6,
  description = 'Прячет верхнюю промо-плашку «Как сохранить соединение?». Сводит статус защиты, кнопку подключения и строку страны в один пункт: при свайпе читает «Подключено» или «Отключено» вместе со страной, двойной тап переключает ВПН. В меню действий — подключить или отключить и выбрать страну. В настройках — переключатель.',
  apps = { 'com.adguard.vpn' },
  permissions = { 'screen', 'actions', 'speech', 'input' },
  settings = {
    {
      key = 'enabled',
      type = 'switch',
      title = 'Упростить главный экран',
      summary = 'Скрыть промо-плашку и статус, свести статус, кнопку и страну в один пункт',
      default = true,
    },
  },
}

local SETTING = 'enabled'
local PACKAGE = 'com.adguard.vpn'

-- id элементов главного экрана AdGuard VPN.
local PROMO_ID = 'background_permission_badge'
local STATUS_ID = 'protection_status'
local BUTTON_ID = 'button'
local COUNTRY_ID = 'preview'
local SHEET_ID = 'locations_bottom_sheet'

local function enabled()
  return sf.settings.get(SETTING) ~= false
end

-- Схлопывает повторы пробелов и меняет неразрывные пробелы на обычные:
-- в деревьях приложений они попадаются в названиях стран и за пробел
-- не считаются.
local function clean(text)
  if type(text) ~= 'string' then
    return nil
  end
  text = text:gsub('\194\160', ' ')
  text = text:gsub('\226\128\175', ' ')
  text = text:gsub('%s+', ' ')
  text = text:gsub('^ ', ''):gsub(' $', '')
  if text == '' then
    return nil
  end
  return text
end

local function textOf(item)
  if not item then
    return nil
  end
  return clean(item.text) or clean(item.contentDescription)
end

-- id элемента может прийти коротким («button») или полным
-- («com.adguard.vpn:id/button») — сверяем оба вида.
local function isId(item, short)
  local id = item and item.id
  if id == short then
    return true
  end
  return type(id) == 'string' and id:sub(-(#short + 1)) == '/' .. short
end

-- Состояние из текста статуса: «Отключён» / «Подключён».
local function stateFromStatus(text)
  text = clean(text)
  if not text then
    return nil
  end
  if text:find('Отключ', 1, true) then
    return 'Отключено'
  end
  if text:find('Подключ', 1, true) then
    return 'Подключено'
  end
  return nil
end

-- Состояние из текста кнопки: на ней написано действие, а не состояние —
-- «Подключить» значит «сейчас отключено».
local function stateFromButton(text)
  text = clean(text)
  if not text then
    return nil
  end
  if text:find('Отключить', 1, true) then
    return 'Подключено'
  end
  if text:find('Подключить', 1, true) then
    return 'Отключено'
  end
  return nil
end

-- Запомненное состояние: текст статуса и строка страны.
local statusText = nil
local countryText = nil

-- Страна: preview — строка внизу карточки, внутри неё три подписи
-- (страна, город, пинг). Собираем их через запятую: «Италия, Рим, 82 мс».
local function readCountry()
  local preview = sf.screen.find({ id = COUNTRY_ID })
  if not preview then
    return nil
  end
  local parts = {}
  local count = preview.childCount or 0
  for i = 1, count do
    local part = textOf(preview:child(i))
    if part then
      parts[#parts + 1] = part
    end
  end
  if #parts > 0 then
    return table.concat(parts, ', ')
  end
  return textOf(preview)
end

local function refreshState()
  if not enabled() then
    return
  end
  local ok, item = pcall(function()
    return sf.screen.find({ id = STATUS_ID })
  end)
  if ok then
    statusText = textOf(item) or statusText
  end
  local okCountry, country = pcall(readCountry)
  if okCountry and country then
    countryText = country
  end
end

-- ── Правила ──

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
  if not enabled() then
    return
  end

  -- 1. Промо-плашка: сам бейдж и прокручиваемая область, в которой он
  --    лежит (у неё нет id, ищем по классу и по бейджу внутри).
  --    hide = 'all' убирает и подписи внутри.
  addRule({ match = { className = 'HorizontalScrollView', has = { id = PROMO_ID } }, hide = 'all' })
  addRule({ id = PROMO_ID, hide = 'all' })

  -- 2. Статус и страна из листания убраны, но остаются на экране:
  --    скрипт находит их и может нажать.
  addRule({ id = STATUS_ID, hide = 'all' })
  addRule({ id = COUNTRY_ID, hide = 'all' })
end

-- ── Действия ──

local function toggleVpn()
  local button = sf.screen.find({ id = BUTTON_ID })
  if not button then
    return
  end
  button:click()
  sf.setTimeout(refreshState, 600)
end

local function openCountry()
  local preview = sf.screen.find({ id = COUNTRY_ID })
  if preview and preview:click() then
    return
  end
  -- Запасной путь: развернуть карточку локаций её собственным действием.
  local sheet = sf.screen.find({ id = SHEET_ID })
  if sheet then
    pcall(function()
      sheet:perform('Развернуть наполовину')
    end)
  end
end

-- ── Хуки ──

-- При свайпе на кнопку читаем состояние и страну вместо «Подключить, кнопка».
sf.onFocus(function(item, text)
  if not enabled() or not isId(item, BUTTON_ID) then
    return nil
  end
  local state = stateFromButton(text) or stateFromStatus(statusText)
  if not state and not countryText then
    return nil
  end
  local parts = {}
  if state then
    parts[#parts + 1] = state
  end
  if countryText then
    parts[#parts + 1] = countryText
  end
  parts[#parts + 1] = 'кнопка'
  return table.concat(parts, ', ')
end)

-- Меню действий на кнопке: подключить или отключить и выбрать страну.
sf.onActions(function(item)
  if not enabled() or not isId(item, BUTTON_ID) then
    return nil
  end
  local state = stateFromButton(item.text) or stateFromStatus(statusText)
  local toggle
  if state == 'Подключено' then
    toggle = 'Отключить'
  elseif state == 'Отключено' then
    toggle = 'Подключить'
  else
    toggle = 'Подключить или отключить'
  end
  return {
    { title = toggle, first = true, run = toggleVpn },
    { title = countryText and ('Страна: ' .. countryText) or 'Страна', first = true, run = openCountry },
  }
end)

-- Состояние меняется после подключения и после выбора сервера.
-- Обновляем не чаще пяти раз в секунду: содержимое экрана меняется
-- часто (пинг тикает), а поиск по дереву не бесплатный.
local lastRefresh = 0

sf.onContentChange(function(event)
  if not enabled() then
    return
  end
  if event and event.package and event.package ~= PACKAGE then
    return
  end
  local now = sf.clock()
  if now - lastRefresh < 200 then
    return
  end
  lastRefresh = now
  refreshState()
end)

sf.onWindowChange(function(event)
  if not enabled() then
    return
  end
  if event and event.package and event.package ~= PACKAGE then
    return
  end
  sf.setTimeout(refreshState, 150)
end)

sf.onAppEnter(function(event)
  if event and event.package and event.package ~= PACKAGE then
    return
  end
  applyRules()
  sf.setTimeout(refreshState, 300)
end)

sf.onSettingChange(function(key)
  if key ~= SETTING then
    return
  end
  applyRules()
  if enabled() then
    sf.setTimeout(refreshState, 200)
  end
end)

-- Правила ставим сразу при загрузке: скрипт для приложения грузится,
-- когда приложение выходит вперёд.
applyRules()

print('AdGuard VPN: главный экран упрощён, версия 2.0 загружена')
