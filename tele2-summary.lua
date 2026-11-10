-- Скрипт для SandFly: приложение «Мой Теле2» (ru.tele2.mytele2).
--
-- Что делает:
--   * одной командой читает номер, баланс, остатки гигабайт, минут и SMS,
--     тариф и число подключённых услуг;
--   * нижние вкладки называет коротко, только именем раздела;
--   * верхний ряд (профиль, уведомления, поиск) сводит в один пункт,
--     переключение между ними — через меню действий;
--   * блок с номером и остатками тоже сводит в один пункт: в меню действий
--     «Пополнить баланс», «Гигабайты», «Минуты», «SMS»;
--   * рекламный баннер пропускает при листании;
--   * при входе в приложение фокус сам встаёт на блок с номером.

local manifest = {
  id = 'wam.tele2-summary',
  name = 'Теле2: сводка по счёту',
  author = 'Лия, WAM Agents',
  version = '1.5',
  minApiVersion = 2,
  testedApiVersion = 3,
  description = 'Читает номер, баланс, остатки гигабайт, минут и SMS, тариф и услуги одной командой. Собирает верхний ряд и блок с остатками в короткие пункты с действиями, называет вкладки коротко, пропускает рекламный баннер. При каждом входе в приложение фокус всегда встаёт на блок с номером. Остатки во всех пунктах читаются одинаково: подписи экрана, затем снимок, затем честное «не озвучивает».',
  apps = { 'ru.tele2.mytele2' },
  permissions = { 'screen', 'speech', 'input', 'actions' },
  settings = {
    {
      key = 'ocr',
      type = 'switch',
      title = 'Распознавать цифры по картинке',
      summary = 'Для остатка гигабайт, которого приложение не отдаёт диктору. Добавляет около секунды.',
      default = true,
    },
    {
      key = 'focusPhone',
      type = 'switch',
      title = 'Фокус на блок с номером',
      summary = 'При входе в приложение фокус встаёт на блок с номером и остатками',
      default = true,
    },
  },
  rules = {
    -- Верхний ряд: профиль и уведомления лежат в общей области, поиск —
    -- отдельной областью рядом. Сводим профиль и уведомления в один пункт
    -- (group), а поиск прячем целиком и оставляем действием в меню.
    {
      match = { clickable = true, has = { textContains = 'Личный кабинет' } },
      group = true,
      activate = { textContains = 'Личный кабинет' },
      actions = {
        { title = 'Профиль', click = { textContains = 'Личный кабинет' } },
        { title = 'Уведомления', click = { textContains = 'Уведомления' } },
        { title = 'Поиск', click = { clickable = true, has = { contentDescription = 'Поиск' } } },
      },
    },
    -- Сама строка поиска безымянная, а внутри неё только значок «Поиск».
    {
      match = { clickable = true, has = { contentDescription = 'Поиск' } },
      hide = 'all',
    },
    -- Блок с номером: строки остатков уходят из листания, а их действия
    -- собирает хук onActions ниже — в названиях он показывает остатки.
    { match = { textContains = 'Пополнить баланс на балансе' }, hide = true },
    { match = { clickable = true, has = { text = 'Гигабайты' } }, hide = true },
    { match = { clickable = true, has = { text = 'Минуты' } }, hide = true },
    { match = { clickable = true, has = { text = 'SMS' } }, hide = true },
    -- Рекламный баннер с историями: при листании пропускается.
    { match = { textContains = 'Персональное предложение' }, hide = true },
    -- Нижние вкладки: вместо «Выбрано. Главный экран. 1 из 5» — имя раздела.
    { match = { inside = { id = 'navbarHolder' }, textContains = 'Главный экран' }, speak = 'Главный экран' },
    { match = { inside = { id = 'navbarHolder' }, textContains = 'Подписка Микс' }, speak = 'Подписка Микс' },
    { match = { inside = { id = 'navbarHolder' }, textContains = 'Дом и семья' }, speak = 'Дом и семья' },
    { match = { inside = { id = 'navbarHolder' }, textContains = 'Финсервисы' }, speak = 'Финсервисы' },
    { match = { inside = { id = 'navbarHolder' }, textContains = 'Программа лояльности' }, speak = 'Программа лояльности' },
  },
  commands = {
    { id = 'summary', title = 'Сводка по счёту', keys = 'sf+s', menu = true },
    { id = 'focus_phone', title = 'Перейти к блоку с номером', menu = true },
  },
}

-- Схлопывает повторы пробелов: приложение иногда склеивает текст с двойными
-- пробелами и пустыми кусками. Заодно меняет неразрывные пробелы на обычные:
-- в дереве Tele2 они попадаются в номере и в суммах, а диктор и поиск по
-- шаблону их за пробел не считают.
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
  return clean(item.contentDescription) or clean(item.text) or clean(item.stateDescription)
end

local function hasDigit(text)
  return type(text) == 'string' and text:find('%d') ~= nil
end

-- Собирает все подписи внутри элемента, без повторов. Глубина ограничена
-- шестью уровнями: глубже в дереве Tele2 уже только служебные слои.
local function textsInside(item, maxDepth)
  maxDepth = maxDepth or 6
  local out = {}
  local function walk(node, depth)
    if not node or depth > maxDepth then
      return
    end
    local text = textOf(node)
    if text then
      local duplicate = false
      for i = 1, #out do
        if out[i] == text then
          duplicate = true
          break
        end
      end
      if not duplicate then
        out[#out + 1] = text
      end
    end
    local count = node.childCount or 0
    for i = 1, count do
      local child = node:child(i)
      if child then
        walk(child, depth + 1)
      end
    end
  end
  walk(item, 0)
  return out
end

-- Цифры, которых нет в дереве доступности, пробуем прочитать со снимка
-- экрана. Работает с Android 11 и новее.
local function recognizeNumber(item)
  if not sf.settings.get('ocr') then
    return nil
  end
  local ok, result = pcall(function()
    return item:recognizeText()
  end)
  if not ok or type(result) ~= 'table' or type(result.text) ~= 'string' then
    return nil
  end
  local digits = result.text:gsub('[^%d%.,]', ' ')
  digits = clean(digits)
  if hasDigit(digits) then
    return digits
  end
  return nil
end

-- Номер телефона из описания блока «Мой номер»: он всегда идёт в виде
-- «+7 908 240 25 19», поэтому ищем его по ведущему плюсу, а не по подписям.
local function phoneNumber(item)
  local text = textOf(item)
  if not text then
    return nil
  end
  return clean(text:match('%+%d[%d%s%(%)%-]*'))
end

-- Баланс. Приложение отдаёт кнопку с описанием «Пополнить баланс на балансе
-- <сумма> <дата> спишем <сумма> ₽», но на деле сумма баланса из этого текста
-- пропадает — остаётся только остаток долга и дата списания. Не придумываем
-- цифру: говорим, что суммы нет, и называем ближайшее списание.
local function balanceLine(item)
  local text = textOf(item)
  if not text then
    return nil
  end
  local rest = text:match('на балансе(.*)')
  rest = clean(rest)
  if not rest then
    return text
  end
  if rest:find('спишем', 1, true) then
    return 'Баланс: сумму приложение не озвучивает, ' .. rest
  end
  return 'Баланс: ' .. rest
end

-- Строки остатков: все три пункта на экране (гигабайты, минуты, SMS) читаются
-- и называются одним и тем же порядком, поэтому и функция одна.
local GB_QUERY = { clickable = true, has = { text = 'Гигабайты' } }
local MINUTES_QUERY = { clickable = true, has = { text = 'Минуты' } }
local SMS_QUERY = { clickable = true, has = { text = 'SMS' } }

-- Один счётчик: «Минуты 4598», «SMS 592», «Гигабайты …». Порядок такой:
-- подписи из дерева экрана; если цифр в них нет — распознавание по снимку;
-- если и там пусто — честная строка вместо выдуманной цифры.
-- readNumber передаётся снаружи: в команде снимок читается на месте, а в меню
-- действий ждать нельзя, поэтому там берётся значение, прочитанное заранее.
local function counterLine(query, name, readNumber, empty)
  local row = sf.screen.find(query)
  if not row then
    return nil
  end
  local line = clean(table.concat(textsInside(row), ' '))
  if hasDigit(line) then
    return line
  end
  local number = readNumber and readNumber(row)
  if number then
    return name .. ': ' .. number
  end
  return name .. ': ' .. (empty or 'значение приложение не озвучивает')
end

-- Гигабайты приложение не отдаёт диктору: при безлимитном интернете в строке
-- нет ни цифры, ни слова — только подпись «Гигабайты». Снимок этой строки
-- читаем заранее, при обновлении экрана: в меню действий ждать нельзя.
-- Если приложение когда-нибудь покажет остаток цифрами, эти цифры сами
-- перекроют заранее прочитанное — дерево проверяется первым.
local gbOcr = nil
local gbTree = false
local gbTries = 0

sf.onContentChange(function()
  if gbTree or gbOcr or gbTries >= 3 then
    return
  end
  local row = sf.screen.find(GB_QUERY)
  if not row then
    return
  end
  local line = clean(table.concat(textsInside(row), ' '))
  if line and hasDigit(line) then
    gbTree = true
    return
  end
  if not sf.settings.get('ocr') then
    return
  end
  gbTries = gbTries + 1
  sf.run(function()
    local number = recognizeNumber(row)
    if number then
      gbOcr = number
    end
  end)
end)

local function gbNumber()
  return gbOcr
end

-- Пункт с номером в дереве идёт длинной подписью «Информация о номере.
-- Текущий. Основной. Мой номер. +7 …». На фокусе оставляем только номер.
sf.onFocus(function(item, text)
  if not text or not text:find('Мой номер', 1, true) then
    return nil
  end
  local plain = clean(text)
  local number = plain and clean(plain:match('%+%d[%d%s%(%)%-]*'))
  if number then
    return 'Номер: ' .. number
  end
  return nil
end)

local function clickQuery(query)
  return function()
    local target = sf.screen.find(query)
    if target then
      target:click()
    end
  end
end

-- Действия пункта с номером собираем в момент открытия меню: только тогда
-- в названиях можно показать свежие остатки. Все три счётчика идут через
-- counterLine — тем же порядком, что и в команде сводки.
sf.onActions(function(item)
  local text = item and textOf(item)
  if not text or not text:find('Мой номер', 1, true) then
    return nil
  end
  return {
    { title = 'Пополнить баланс', run = clickQuery({ textContains = 'Пополнить баланс на балансе' }) },
    { title = counterLine(GB_QUERY, 'Гигабайты', gbNumber, 'безлимит') or 'Гигабайты', run = clickQuery(GB_QUERY) },
    { title = counterLine(MINUTES_QUERY, 'Минуты') or 'Минуты', run = clickQuery(MINUTES_QUERY) },
    { title = counterLine(SMS_QUERY, 'SMS') or 'SMS', run = clickQuery(SMS_QUERY) },
  }
end)

sf.onCommand('summary', function()
  local parts = {}
  local function add(value)
    if value and value ~= '' then
      parts[#parts + 1] = value
    end
  end

  local phone = sf.screen.find({ textContains = 'Мой номер' })
  local number = phoneNumber(phone)
  add(number and ('Номер: ' .. number))

  local balance = sf.screen.find({ textContains = 'Пополнить баланс' })
  add(balanceLine(balance))

  add(counterLine(GB_QUERY, 'Гигабайты', recognizeNumber, 'безлимит'))
  add(counterLine(MINUTES_QUERY, 'Минуты', recognizeNumber))
  add(counterLine(SMS_QUERY, 'SMS', recognizeNumber))

  local plan = sf.screen.find({ textContains = 'Подключен тариф' })
  add(plan and textOf(plan))

  local services = sf.screen.find({ textContains = 'Подключенные услуги' })
  add(services and textOf(services))

  if #parts == 0 then
    sf.speak('Сводка есть только на главном экране приложения. Переключитесь на него и повторите.', { interrupt = true })
    return
  end

  sf.speak(table.concat(parts, '. '), { interrupt = true })
end)

-- ── Фокус на блоке с номером ──

local PHONE_QUERY = { textContains = 'Мой номер' }

-- Верхний ряд (профиль, уведомления, поиск) после схлопывания — один пункт.
-- Всё, что ниже него, считаем экраном, по которому человек уже пошёл.
local function isTopRow(item)
  local text = textOf(item)
  if not text then
    return true
  end
  if text:find('Мой номер', 1, true) then
    return false
  end
  return text:find('Личный кабинет', 1, true) ~= nil
    or text:find('Уведомления', 1, true) ~= nil
    or text:find('Поиск', 1, true) ~= nil
end

local focusGen = 0

-- force = true — вход в приложение: ставим фокус на блок с номером всегда,
-- где бы фокус ни остался с прошлого раза.
local function focusPhoneBlock(force)
  if sf.settings.get('focusPhone') == false then
    return
  end
  focusGen = focusGen + 1
  local mine = focusGen
  sf.run(function()
    local block = sf.screen.waitFor(PHONE_QUERY, 12000, 300)
    -- Пока ждали, экран сменился ещё раз — работает более поздний вызов.
    if not block or mine ~= focusGen then
      return
    end
    local cur = sf.screen.focused()
    -- Смена окна фокуса не отбирает, пока он на верхнем ряду или его ещё нет:
    -- если человек уже листает экран, назад не дёргаем.
    if not force and cur and not isTopRow(cur) then
      return
    end
    block:focus()
  end)
end

sf.onAppEnter(function()
  focusPhoneBlock(true)
end)

sf.onWindowChange(function()
  focusPhoneBlock(false)
end)

-- Ручной переход: SandFly → Команды → «Перейти к блоку с номером».
sf.onCommand('focus_phone', function()
  local block = sf.screen.waitFor(PHONE_QUERY, 3000, 200)
  if block then
    block:focus()
  else
    sf.speak('Блок с номером не найден. Он есть на главном экране приложения.')
  end
end)
