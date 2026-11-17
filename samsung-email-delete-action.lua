-- Действия с письмом в штатной почте Samsung.
-- В меню действий каждого письма в списке добавляет пункт удаления. Работает
-- так же, как руками: нажатие с удержанием на строке письма, затем кнопка
-- «Удалить» на нижней панели. Если в списке осталось одно письмо, кнопка в
-- приложении называется «Удалить все», и скрипт называет пункт так же.
-- Удержание делается настоящим касанием: палец ставится в центр строки и
-- держится. Программное нажатие с удержанием выделяет письмо, но нижнюю панель
-- не показывает — она появляется только от касания. Поэтому касание основное,
-- а программное удержание осталось запасным путём.

local manifest = {
  id = 'samsung-email-delete-action',
  name = 'Почта Samsung: удаление письма',
  version = '1.2',
  author = 'Алёшка',
  minApiVersion = 1,
  testedApiVersion = 5,
  description = 'В меню действий каждого письма в списке почты Samsung добавляет удаление. Скрипт сам удерживает строку письма касанием, чтобы открылась нижняя панель с кнопкой удаления, и нажимает её. Если в списке осталось одно письмо, пункт называется «Удалить всё», как и кнопка в самом приложении. Если на экране уже идёт режим выбора, скрипт не трогает чужие письма и говорит об этом.',
  apps = { 'com.samsung.android.email.provider' },
  permissions = { 'screen', 'actions', 'speech', 'input', 'system' },
}

-- Признак строки письма в дереве доступности: в тексте строки лежит служебный
-- набор полей, и первое поле — type msg_item. У остальных строк приложения
-- такого текста нет.
local ROW_MARKER = 'msg_item'

-- Сколько держим палец. Короткое касание — обычное нажатие, длинное открывает
-- панель; шестьсот миллисекунд — середина между ними и проверенный срок.
local HOLD_MS = 600

-- Кнопка удаления на нижней панели. Сначала по короткому id, потом полным, в
-- конце — по подписи: у неё два вида, «Удалить» и «Удалить все», и оба содержат
-- это слово.
local DELETE = {
  { id = 'delete_item' },
  { id = 'com.samsung.android.email.provider:id/delete_item' },
  { textContains = 'Удалить все' },
  { textContains = 'Удалить' },
}

-- Флажок режима выбора: он появляется внутри строки, пока режим включён, и его
-- нет в обычном списке. По нему видно, что письмо уже отмечено.
local CHECKBOX = { id = 'list_checkbox' }

-- Положительная кнопка системного диалога. Приложение спрашивает
-- подтверждение не всегда, поэтому ищем её необязательно: нет диалога — и
-- нажимать нечего.
local CONFIRM = { { id = 'android:id/button1' } }

-- Центр элемента на экране. Если границы не отдались, касание невозможно —
-- тогда работает только программное нажатие.
local function pointIn(item)
  local bounds = item and item.bounds
  if not bounds then return nil end
  local left, right = bounds.left or 0, bounds.right or 0
  local top, bottom = bounds.top or 0, bounds.bottom or 0
  if right - left <= 0 or bottom - top <= 0 then return nil end
  return math.floor((left + right) / 2), math.floor((top + bottom) / 2)
end

-- Нажимает элемент: обычное нажатие, затем действие доступности «нажать», в
-- конце — тычок пальцем по центру. Кнопки нижней панели понимают не всякое из
-- трёх, поэтому пробуем по очереди.
local function press(item)
  local ok, clicked = pcall(function() return item:click() end)
  if ok and clicked then return true end
  local tappedOk, tapped = pcall(function() return item:tap() end)
  if tappedOk and tapped == true then return true end
  local x, y = pointIn(item)
  if x and y and sf.touch and sf.touch.tap then
    local touchOk = pcall(function() return sf.touch.tap(x, y) end)
    if touchOk then return true end
  end
  return false
end

-- Подпись кнопки лежит во вложенном элементе, а нажимать надо тот, который сам
-- умеет нажиматься: поднимаемся к нему по родителям.
local function clickable(node)
  local current = node
  for _ = 1, 4 do
    if not current then break end
    if current.clickable then return current end
    local ok, parent = pcall(function() return current:parent() end)
    if not ok then break end
    current = parent
  end
  return node
end

-- Свежий снимок строки: после закрытия меню действий старый снимок ещё помнит
-- прежний экран, и касание по нему может уйти мимо.
local function fresh(item)
  local ok, refreshed = pcall(function() return item:refresh() end)
  if ok and refreshed then return refreshed end
  return item
end

-- Ищет элемент в активном окне, а если там нет — во всех остальных: нижняя
-- панель у почты может оказаться в отдельном окне, и обычный поиск её не
-- видит.
local function findAnywhere(query)
  local ok, found = pcall(function() return sf.screen.find(query) end)
  if ok and found then return found end
  local windowsOk, windows = pcall(function() return sf.screen.windows() end)
  if windowsOk and type(windows) == 'table' then
    for _, win in ipairs(windows) do
      local root = win and win.root
      if root then
        local rootOk, inWindow = pcall(function() return root:find(query) end)
        if rootOk and inWindow then return inWindow end
      end
    end
  end
  return nil
end

local function findDelete()
  for _, query in ipairs(DELETE) do
    local found = findAnywhere(query)
    if found then return clickable(found) end
  end
  return nil
end

local function hasMarker(item)
  local text = item and item.text
  return type(text) == 'string' and text:find(ROW_MARKER, 1, true) ~= nil
end

-- Строка письма — это сама строка или один из её родителей: меню действий
-- можно открыть и на вложенном элементе, а удерживать надо строку целиком.
local function messageRow(item)
  local current = item
  for _ = 1, 3 do
    if not current then return nil end
    if hasMarker(current) then return current end
    local ok, parent = pcall(function() return current:parent() end)
    if not ok then return nil end
    current = parent
  end
  return nil
end

-- Сколько писем видно в списке. Для названия пункта достаточно отличить одно
-- письмо от нескольких, поэтому берём не больше трёх: обход дешевле.
local function onlyOneMessage()
  local ok, rows = pcall(function()
    return sf.screen.findAll({ textContains = ROW_MARKER }, 3)
  end)
  return ok and type(rows) == 'table' and #rows == 1
end

-- Удержание строки настоящим касанием: палец ставится в центр строки и
-- держится HOLD_MS миллисекунд. Если касание недоступно, остаётся программное
-- удержание longClick, а после него — действие доступности ACTION_LONG_CLICK:
-- его имя у разных версий SandFly разное.
local function hold(row)
  pcall(function() return row:showOnScreen() end)
  row = fresh(row)

  local x, y = pointIn(row)
  if x and y then
    local ok = pcall(function()
      sf.touch.gesture({
        { points = { { x = x, y = y } }, start = 0, duration = HOLD_MS },
      })
    end)
    if ok then return true end
  end

  local clickOk, held = pcall(function() return row:longClick() end)
  if clickOk and held then return true end
  for _, name in ipairs({ 'long_click', 'longClick', 'ACTION_LONG_CLICK' }) do
    local performOk, done = pcall(function() return row:perform(name) end)
    if performOk and done then return true end
  end
  return false
end

-- Кнопку удаления ищем отдельной задачей-таймером: на само действие отпущено
-- около двух секунд, а удержание и появление панели занимают больше. Таймер
-- успевает и дождаться панели, и нажать, не обрывая действие.
local function deleteLater(attempts)
  sf.setTimeout(function()
    local button = findDelete()
    if not button then
      if attempts and attempts > 1 then
        deleteLater(attempts - 1)
      else
        sf.speak('Панель с удалением не появилась')
      end
      return
    end
    press(button)
    -- Если приложение всё-таки спросило подтверждение, жмём его тоже.
    -- Диалог открывается не мгновенно, поэтому проверяем с паузой.
    sf.setTimeout(function()
      for _, query in ipairs(CONFIRM) do
        local confirm = findAnywhere(query)
        if confirm then
          press(confirm)
          break
        end
      end
    end, 700)
  end, 250)
end

-- Выполняется, когда выбран пункт меню действий. Здесь можно ждать, поэтому
-- sf.sleep разрешён.
local function perform(item)
  local row = messageRow(item) or item
  -- Уже идёт режим выбора: у строки есть флажок, и удержание сняло бы отметку
  -- с письма вместо того, чтобы открыть панель. Удалять наугад нельзя.
  local inRow, checkbox = pcall(function() return row:find(CHECKBOX) end)
  if (inRow and checkbox) or findDelete() then
    sf.speak('Сначала выйдите из режима выбора')
    return
  end
  -- Само удержание и ожидание панели — отдельной задачей: действие живёт
  -- около двух секунд, а этого мало.
  sf.setTimeout(function()
    if not hold(row) then
      sf.speak('Не получилось удержать письмо')
      return
    end
    deleteLater(10)
  end, 150)
end

sf.onActions(function(item)
  if not messageRow(item) then return nil end
  local title = 'Удалить письмо'
  if onlyOneMessage() then title = 'Удалить всё' end
  return {
    {
      title = title,
      run = function(node) perform(node or item) end,
    },
  }
end)
