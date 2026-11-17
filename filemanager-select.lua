-- Файловый менеджер + (com.alphainventor.filemanager): выбор файла и действия.
--
-- Кнопка выбора рядом с каждой строкой списка убрана из обхода свайпами: на
-- каждом файле это была лишняя остановка. В меню действий строки добавлены
-- свои пункты, и они стоят выше действий приложения.
--
-- «Выбрать» нажимает ту самую кнопку из строки. Остальные четыре повторяют то,
-- что делают руками: нажатие с удержанием на строке файла, затем кнопка на
-- нижней панели. Удержание делается настоящим касанием — программное удержание
-- строку выделяет, но нижнюю панель приложение не показывает.
--
-- Удержание и поиск панели разнесены по задачам через таймер: у действия около
-- двух секунд, а касание с ожиданием панели в них не укладывается.

local manifest = {
  id = 'filemanager-select',
  name = 'Файловый менеджер +: действия с файлом',
  version = '5.0',
  author = 'lawx',
  minApiVersion = 5,
  testedApiVersion = 5,
  description = 'Убирает кнопку выбора из обхода свайпами. В меню действий файла и папки добавляет «Выбрать», «Удалить», «Переименовать», «Копировать» и «Переместить», выше действий приложения. Все, кроме выбора, сами удерживают строку касанием, дожидаются нижней панели и нажимают в ней нужную кнопку; после «Переименовать» курсор сразу встаёт в поле с именем.',
  apps = { 'com.alphainventor.filemanager' },
  permissions = { 'screen', 'actions', 'speech', 'input' },
  rules = {
    {
      match = { id = 'icon_container', inside = { id = 'item_container' } },
      hide = true,
    },
  },
}

-- Строка списка: контейнер, в котором лежат подписи файла и кнопка выбора.
local ROW_ID = 'item_container'

-- Кнопка выбора в строке. Скрыта правилом из обхода, но нажать её скрипт может.
local TOGGLE_ID = 'icon_container'

-- Признак открытой нижней панели: кнопка удаления есть на любой её версии.
local PANEL_ID = 'bottom_menu_delete'

-- Сколько держим палец на строке. Короткое касание — обычное нажатие, длинное
-- открывает панель; шестьсот миллисекунд — середина между ними.
local HOLD_MS = 600

-- Сколько ждём панель и поле имени: двенадцать проверок по 250 мс — три секунды.
local STEP_MS = 250
local STEPS = 12

-- Центр элемента на экране. Если границы не отдались, касание невозможно.
local function pointIn(item)
  local bounds = item and item.bounds
  if not bounds then return nil end
  local left, right = bounds.left or 0, bounds.right or 0
  local top, bottom = bounds.top or 0, bounds.bottom or 0
  if right - left <= 0 or bottom - top <= 0 then return nil end
  return math.floor((left + right) / 2), math.floor((top + bottom) / 2)
end

-- Свежий снимок элемента: после закрытия меню действий старый снимок ещё помнит
-- прежний экран, и касание по нему может уйти мимо.
local function fresh(item)
  local ok, refreshed = pcall(function() return item:refresh() end)
  if ok and refreshed then return refreshed end
  return item
end

-- Ищет элемент в активном окне, а если там нет — во всех остальных: нижняя
-- панель может оказаться в отдельном окне и обычным поиском не находиться.
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

-- Нажимает элемент: обычное нажатие, затем касание средствами доступности, в
-- конце — тычок пальцем по центру. Кнопки нижней панели понимают не всякое из
-- трёх, поэтому пробуем по очереди.
local function press(item)
  local ok, clicked = pcall(function() return item:click() end)
  if ok and clicked then return true end
  local tapOk, tapped = pcall(function() return item:tap() end)
  if tapOk and tapped == true then return true end
  local x, y = pointIn(item)
  if x and y then
    local touchOk = pcall(function() return sf.touch.tap(x, y) end)
    if touchOk then return true end
  end
  return false
end

-- Строка списка, в которой лежит элемент. Дальше пяти уровней вверх не идём,
-- чтобы не уехать в список целиком.
local function findRow(item)
  local current = item
  for _ = 1, 5 do
    if not current then return nil end
    local id = current.id
    if type(id) == 'string' and id:find(ROW_ID, 1, true) then return current end
    local ok, parent = pcall(function() return current:parent() end)
    if not ok then return nil end
    current = parent
  end
  return nil
end

-- Удержание строки настоящим касанием: палец ставится в центр строки и держится
-- HOLD_MS миллисекунд. Если касание недоступно, остаётся программное удержание.
local function hold(row)
  pcall(function() return row:showOnScreen() end)
  row = fresh(row)

  local x, y = pointIn(row)
  if x and y then
    local ok = pcall(function() return sf.touch.longPress(x, y, HOLD_MS) end)
    if ok then return true end
  end

  local clickOk, held = pcall(function() return row:longClick() end)
  if clickOk and held then return true end
  return false
end

-- Ждёт элемент и отдаёт его в onFound. Проверки идут таймером: панель
-- появляется уже после того, как действие вернулось.
local function waitForItem(query, onFound, onLost)
  local left = STEPS
  local function look()
    sf.setTimeout(function()
      local found = findAnywhere(query)
      if found then
        onFound(found)
        return
      end
      left = left - 1
      if left > 0 then
        look()
      elseif onLost then
        onLost()
      end
    end, STEP_MS)
  end
  look()
end

-- Общая часть действий с нижней панелью: удержать строку, если панель ещё не
-- открыта, дождаться своей кнопки и нажать её.
local function bottomAction(buttonId)
  return function(item)
    local row = findRow(item)
    if not row then
      sf.speak('Это не файл и не папка')
      return
    end
    if not findAnywhere({ id = PANEL_ID }) then
      pcall(function() sf.sleep(150) end)
      hold(row)
    end
    waitForItem({ id = buttonId }, function(button)
      if not press(button) then
        sf.speak('Кнопка не нажалась')
      end
    end, function()
      sf.speak('Нижняя панель не появилась')
    end)
  end
end

-- Переименование: та же панель, но после неё ставим курсор в поле с именем,
-- чтобы можно было печатать сразу, не отыскивая поле свайпами.
local function renameAction(item)
  local row = findRow(item)
  if not row then
    sf.speak('Это не файл и не папка')
    return
  end
  if not findAnywhere({ id = PANEL_ID }) then
    pcall(function() sf.sleep(150) end)
    hold(row)
  end
  waitForItem({ id = 'bottom_menu_rename' }, function(button)
    if not press(button) then
      sf.speak('Кнопка не нажалась')
      return
    end
    waitForItem({ className = 'EditText' }, function(input)
      pcall(function() return input:perform('focusInput') end)
    end)
  end, function()
    sf.speak('Нижняя панель не появилась')
  end)
end

-- Выбор файла: та самая кнопка из строки, которую правило убрало из обхода.
local function selectItem(item)
  local row = findRow(item)
  if not row then
    sf.speak('Это не файл и не папка')
    return
  end
  local toggle = row:find({ id = TOGGLE_ID })
  if not toggle or not press(toggle) then
    sf.speak('Не удалось выбрать')
  end
end

local deleteAction = bottomAction('bottom_menu_delete')
local copyAction = bottomAction('bottom_menu_copy')
local cutAction = bottomAction('bottom_menu_cut')

-- Меню действий строится на элемент в фокусе. Свои пункты ставим только там,
-- где фокус стоит на файле или папке, и выше действий приложения.
sf.onActions(function(item)
  if not findRow(item) then return nil end
  return {
    { title = 'Выбрать', first = true, run = selectItem },
    { title = 'Удалить', first = true, run = deleteAction },
    { title = 'Переименовать', first = true, run = renameAction },
    { title = 'Копировать', first = true, run = copyAction },
    { title = 'Переместить', first = true, run = cutAction },
  }
end)
