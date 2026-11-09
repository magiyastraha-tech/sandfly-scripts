-- Яркость при защите экрана для SandFly
-- Следит за штатным затемнением SandFly («Защитить экран»): когда SandFly
-- объявляет, что экран затемнён, ставит системную яркость в ноль, а когда
-- затемнение отменяют — возвращает выбранную яркость. Пунктов в меню нет.

local manifest = {
  id = 'aleksei.brightness',
  name = 'Яркость при защите экрана',
  author = 'Алёшка',
  version = '1.1',
  minApiVersion = 1,
  testedApiVersion = 3,
  description = 'Следит за штатной защитой экрана SandFly: гасит яркость вместе с затемнением и возвращает её при отмене. Пунктов в меню SandFly не добавляет.',
  permissions = { 'speech', 'java' },
  settings = {
    { key = 'follow', type = 'switch', title = 'Следовать за защитой экрана', default = true,
      summary = 'Гасить яркость, когда SandFly затемняет экран, и возвращать её при отмене' },
    { key = 'percent', type = 'list', title = 'Яркость после отмены', default = '40',
      summary = 'Какая яркость возвращается, когда защита экрана выключается',
      options = {
        { value = '10', label = '10%' },
        { value = '20', label = '20%' },
        { value = '30', label = '30%' },
        { value = '40', label = '40%' },
        { value = '50', label = '50%' },
        { value = '60', label = '60%' },
        { value = '70', label = '70%' },
        { value = '80', label = '80%' },
        { value = '90', label = '90%' },
        { value = '100', label = '100%' },
      } },
    { key = 'manualMode', type = 'switch', title = 'Переводить адаптивную яркость в ручной режим', default = true,
      summary = 'Иначе система сама меняет яркость и выбранное значение не держится' },
    { key = 'toggle', type = 'button', title = 'Затемнить или вернуть яркость' },
    { key = 'grant', type = 'button', title = 'Открыть разрешение на изменение настроек' },
  },
}

-- Ключи системных настроек Android.
local KEY_BRIGHTNESS = 'screen_brightness'
local KEY_MODE = 'screen_brightness_mode'
local MODE_AUTOMATIC = 1
local DEFAULT_PERCENT = 40

-- Объявления SandFly при включении и выключении защиты экрана.
local DIM_ON = { 'Экран затемнён', 'Screen hidden' }
local DIM_OFF = { 'Затемнение экрана выключено', 'Showing screen' }

local follow = true
local percent = DEFAULT_PERCENT
local forceManual = true

-- Класс android.provider.Settings.System через LuaJava.
local function settingsSystem()
  return java.import('android.provider.Settings$System')
end

-- Контекст приложения: скрипт работает внутри процесса SandFly.
local function getContext()
  local ok, ctx = pcall(function()
    local ActivityThread = java.import('android.app.ActivityThread')
    local app = ActivityThread.currentApplication()
    if app ~= nil then
      return app
    end
    local AppGlobals = java.import('android.app.AppGlobals')
    return AppGlobals.getInitialApplication()
  end)
  if ok then
    return ctx
  end
  return nil
end

-- Открывает экран разрешения «Изменение системных настроек» для SandFly.
local function openWriteSettings(ctx)
  pcall(function()
    local Uri = java.import('android.net.Uri')
    local intent = java.new('android.content.Intent', 'android.settings.action.MANAGE_WRITE_SETTINGS')
    intent:setData(Uri.parse('package:' .. ctx:getPackageName()))
    intent:addFlags(0x10000000) -- FLAG_ACTIVITY_NEW_TASK
    ctx:startActivity(intent)
  end)
end

-- Процент в системное значение 1..255 по кривой системного ползунка
-- (та же кривая, что у SandFly и Android).
local function percentToSetting(p)
  if p <= 0 then
    return 0
  end
  local g = p / 100
  local scaled
  if g <= 0.5 then
    scaled = (g / 0.5) ^ 2
  else
    scaled = math.exp((g - 0.55991073) / 0.17883277) + 0.28466892
  end
  local s = math.floor(1 + scaled * 254 / 12 + 0.5)
  if s < 1 then
    s = 1
  end
  if s > 255 then
    s = 255
  end
  return s
end

-- Ближайшие 10%, в пределах 10..100.
local function clampPercent(p)
  p = tonumber(p) or DEFAULT_PERCENT
  p = math.floor(p / 10 + 0.5) * 10
  if p < 10 then
    p = 10
  end
  if p > 100 then
    p = 100
  end
  return p
end

local function loadSettings()
  local ok, v = pcall(sf.settings.get, 'follow')
  if ok and v ~= nil then
    follow = (v == true or v == 'true')
  end
  ok, v = pcall(sf.settings.get, 'percent')
  if ok and v ~= nil then
    percent = clampPercent(v)
  end
  ok, v = pcall(sf.settings.get, 'manualMode')
  if ok and v ~= nil then
    forceManual = (v == true or v == 'true')
  end
end

loadSettings()

sf.onSettingChange(function(key, value)
  if key == 'follow' then
    follow = (value == true or value == 'true')
  elseif key == 'percent' then
    percent = clampPercent(value)
  elseif key == 'manualMode' then
    forceManual = (value == true or value == 'true')
  end
end)

-- Говорит о нехватке разрешения один раз за загрузку, чтобы не повторяться.
local warned = false
local function warnOnce(text)
  if warned then
    return
  end
  warned = true
  pcall(sf.speak, text, { interrupt = true })
end

-- Готовит контекст и класс настроек; без разрешения объясняет и молчит.
local function access()
  local ctx = getContext()
  if ctx == nil then
    warnOnce('Скрипт яркости не смог получить доступ к настройкам экрана')
    return nil, nil
  end
  local s
  local ok = pcall(function()
    s = settingsSystem()
  end)
  if not ok or s == nil then
    warnOnce('Скрипт яркости не смог получить доступ к настройкам экрана')
    return nil, nil
  end
  local can
  local okc, res = pcall(function()
    return s.canWrite(ctx)
  end)
  if okc then
    can = res
  end
  if can ~= true then
    warnOnce('Разрешите SandFly изменять системные настройки: в настройках скрипта «Яркость при защите экрана» нажмите «Открыть разрешение на изменение настроек»')
    return nil, nil
  end
  return ctx, s
end

local function setBrightness(ctx, s, value)
  local ok, res = pcall(function()
    return s.putInt(ctx:getContentResolver(), KEY_BRIGHTNESS, value)
  end)
  return ok and res == true
end

local function currentBrightness(ctx, s)
  local ok, value = pcall(function()
    return s.getInt(ctx:getContentResolver(), KEY_BRIGHTNESS, 255)
  end)
  if ok then
    return tonumber(value)
  end
  return nil
end

local function autoDim()
  local ctx, s = access()
  if not ctx then
    return
  end
  if forceManual then
    local r = ctx:getContentResolver()
    local ok, mode = pcall(function()
      return s.getInt(r, KEY_MODE, 0)
    end)
    if ok and tonumber(mode) == MODE_AUTOMATIC then
      pcall(function()
        s.putInt(r, KEY_MODE, 0)
      end)
    end
  end
  setBrightness(ctx, s, 0)
end

local function autoRestore()
  local ctx, s = access()
  if not ctx then
    return
  end
  setBrightness(ctx, s, percentToSetting(percent))
end

local function containsAny(text, list)
  for i = 1, #list do
    if string.find(text, list[i], 1, true) ~= nil then
      return true
    end
  end
  return false
end

-- Слушаем объявления SandFly: они проходят через общую озвучку, поэтому
-- скрипт узнаёт и о включении защиты экрана, и о её отмене.
sf.onSpeech(function(text)
  if not follow or type(text) ~= 'string' then
    return
  end
  if containsAny(text, DIM_ON) then
    sf.run(autoDim)
  elseif containsAny(text, DIM_OFF) then
    sf.run(autoRestore)
  end
end)

-- Ручное управление и разрешение — кнопками на странице настроек скрипта,
-- чтобы не занимать пункты в меню SandFly.
sf.onButton(function(key)
  if key == 'toggle' then
    local ctx, s = access()
    if not ctx then
      return
    end
    if currentBrightness(ctx, s) == 0 then
      autoRestore()
    else
      autoDim()
    end
  elseif key == 'grant' then
    local ctx = getContext()
    if ctx ~= nil then
      openWriteSettings(ctx)
    end
  end
end)
