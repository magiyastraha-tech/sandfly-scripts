-- Файловый менеджер + (com.alphainventor.filemanager): выбор файла и действия.
--
-- Кнопка выбора рядом с каждой строкой списка убрана из обхода свайпами: на
-- каждом файле это была лишняя остановка. В меню действий строки добавлены
-- свои пункты, и они стоят выше действий приложения.
--
-- Действия идут через ту же кнопку выбора, что и «Выбрать»: она выделяет
-- строку, приложение показывает нижнюю панель, и нужная кнопка нажимается на
-- ней сразу. Так быстрее, чем удержание: не нужно держать палец и ждать панель.
-- Если панели после выбора нет, остаётся старое удержание настоящим касанием.
--
-- «Поделиться», «Сжатие» и «Извлечение» живут во всплывающем меню кнопки
-- «Ещё» на нижней панели. Пункт меню выбирается по подписи, потому что id
-- этих пунктов у приложения могут меняться от версии к версии.

local manifest = {
  id = 'filemanager-select',
  name = 'Slonobass Файловый менеджер',
  version = '6.0',
  author = 'lawx',
  minApiVersion = 5,
  testedApiVersion = 5,
  description = 'Убирает кнопку выбора из обхода свайпами. В меню действий файла и папки добавляет «Выбрать», «Копировать», «Переместить», «Удалить», «Переименовать», «Поделиться» и «Сжатие», а для архивов вместо «Сжатие» — «Извлечение». Выделяет строку кнопкой выбора и нажимает нужную кнопку нижней панели; «Поделиться», «Сжатие» и «Извлечение» открывают меню «Ещё» и выбирают пункт в нём.',
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

-- Сколько держим палец на строке в запасном пути. Короткое касание — обычное
-- нажатие, длинное открывает панель; шестьсот миллисекунд — середина между ними.
local HOLD_MS = 600

-- Сколько ждём панель, кнопку и меню: двенадцать проверок по 250 мс — три секунды.
local STEP_MS = 250
local STEPS = 12

-- Расширения, для которых пункт меню называется «Извлечение», а не «Сжатие».
local ARCHIVE_EXT = {
  zip = true, rar = true, ['7z'] = true, tar = true, gz = true, tgz = true,
  bz2 = true, tbz2 = true, xz = true, txz = true, zst = true, lz = true,
  lzma = true, cab = true, arj = true, ace = true,
}

-- Кнопки нижней панели. id идут первыми, подписи — на случай, если id сменится.
local DELETE_QUERIES = {
  { id = 'bottom_menu_delete' },
  { textContains = 'Удалить' },
  { textContains = 'Delete' },
}
local COPY_QUERIES = {
  { id = 'bottom_menu_copy' },
  { textContains = 'Копировать' },
  { textContains = 'Copy' },
}
local CUT_QUERIES = {
  { id = 'bottom_menu_cut' },
  { textContains = 'Переместить' },
  { textContains = 'Move' },
}

-- Кнопка «Ещё» на нижней панели: она открывает всплывающее меню.
local MORE_QUERIES = {
  { id = 'bottom_menu_more' },
  { id = 'bottom_menu_more_button' },
  { id = 'bottom_menu_option' },
  { id = 'bottom_menu_overflow' },
  { textContains = 'Ещё' },
  { textContains = 'Больше' },
  { textContains = 'More' },
}

-- Пункты всплывающего меню «Ещё». Подписи бывают разными; пробуем все.
local SHARE_QUERIES = {
  { id = 'bottom_menu_share' },
  { textContains = 'Поделиться' },
  { textContains = 'Share' },
}
local SHARE_ENTRY = {
  { textContains = 'Поделиться' },
  { textContains = 'Share' },
}
local COMPRESS_ENTRY = {
  { textContains = 'Сжатие' },
  { textContains = 'Сжать' },
  { textContains = 'Создать архив' },
  { textContains = 'Архивировать' },
  { textContains = 'Compress' },
  { textContains = 'Archive' },
}
local EXTRACT_ENTRY = {
  { textContains = 'Извлечение' },
  { textContains = 'Извлечь' },
  { textContains = 'Распаковать' },
  { textContains = 'Extract' },
}

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

-- Первый из списка запросов, который что-то нашёл.
local function findFirst(queries, root)
  for _, query in ipairs(queries) do
    if root then
      local ok, found = pcall(function() return root:find(query) end)
      if ok and found then return found end
    else
      local found = findAnywhere(query)
      if found then return found end
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
-- Это запасной путь: сначала пробуем выделить строку кнопкой выбора.
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

-- Ждёт элемент и отдаёт его в onFound. Первая проверка идёт сразу: панель к
-- этому моменту обычно уже открыта. Дальше проверки идут таймером: панель и
-- меню появляются уже после того, как действие вернулось.
local function waitForAny(queries, root, onFound, onLost, steps)
  local foundNow = findFirst(queries, root)
  if foundNow then
    onFound(foundNow)
    return
  end
  local left = steps or STEPS
  local function look()
    sf.setTimeout(function()
      local found = findFirst(queries, root)
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

-- Кнопка выбора в строке.
local function toggleOf(row)
  local ok, toggle = pcall(function() return row:find({ id = TOGGLE_ID }) end)
  if ok then return toggle end
  return nil
end

-- Корень нижней панели: поднимаемся от кнопки удаления до контейнера, в котором
-- лежит несколько кнопок. Поиск «Ещё» внутри него не цепляет строки списка.
local function panelRoot()
  local button = findAnywhere({ id = PANEL_ID })
  if not button then return nil end
  local node = button
  for _ = 1, 4 do
    local ok, parent = pcall(function() return node:parent() end)
    if not ok or not parent then break end
    local okCount, count = pcall(function() return parent.childCount end)
    if okCount and type(count) == 'number' and count >= 3 then return parent end
    node = parent
  end
  return button
end

-- Выделяет строку кнопкой выбора и отдаёт управление, когда панель открылась.
-- Если панель уже открыта, ничего не нажимает: файл уже выбран.
local function ensureSelected(item, onReady)
  local row = findRow(item)
  if not row then
    sf.speak('Это не файл и не папка')
    return
  end
  if findAnywhere({ id = PANEL_ID }) then
    onReady(row)
    return
  end

  local current = fresh(row)
  local toggle = toggleOf(current)
  if toggle and press(toggle) then
    local left = 10
    local function look()
      sf.setTimeout(function()
        if findAnywhere({ id = PANEL_ID }) then
          onReady(current)
          return
        end
        left = left - 1
        if left > 0 then
          look()
        elseif hold(current) then
          onReady(current)
        else
          sf.speak('Файл не выделился')
        end
      end, 200)
    end
    look()
    return
  end

  if hold(current) then
    onReady(current)
  else
    sf.speak('Не удалось выделить файл')
  end
end

-- Кнопки панели: «Копировать», «Переместить», «Удалить». Нажимаются сразу после
-- выбора строки, без удержания.
local function barAction(queries, failText)
  return function(item)
    ensureSelected(item, function()
      waitForAny(queries, nil, function(button)
        if not press(button) then
          sf.speak('Кнопка не нажалась')
        end
      end, function()
        sf.speak(failText or 'Кнопка не нашлась')
      end)
    end)
  end
end

-- Всплывающее меню кнопки «Ещё»: нажать «Ещё» и выбрать в нём пункт.
local function moreThenPick(entryQueries, failText)
  local root = panelRoot()
  waitForAny(MORE_QUERIES, root, function(moreButton)
    if not press(moreButton) then
      sf.speak('Кнопка «Ещё» не нажалась')
      return
    end
    waitForAny(entryQueries, nil, function(entry)
      if not press(entry) then
        sf.speak('Пункт не нажался')
      end
    end, function()
      sf.speak(failText)
    end)
  end, function()
    sf.speak('Кнопка «Ещё» не нашлась')
  end)
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
  waitForAny({ { id = 'bottom_menu_rename' } }, nil, function(button)
    if not press(button) then
      sf.speak('Кнопка не нажалась')
      return
    end
    waitForAny({ { className = 'EditText' } }, nil, function(input)
      pcall(function() return input:perform('focusInput') end)
    end)
  end, function()
    sf.speak('Нижняя панель не появилась')
  end)
end

-- «Поделиться»: кнопка бывает прямо на панели, но чаще она спрятана в меню
-- «Ещё». Сначала ищем на панели, потом идём в меню.
local function shareAction(item)
  ensureSelected(item, function()
    local root = panelRoot()
    waitForAny(SHARE_QUERIES, root, function(button)
      if not press(button) then
        sf.speak('Кнопка не нажалась')
      end
    end, function()
      moreThenPick(SHARE_ENTRY, 'Пункт «Поделиться» не нашёлся')
    end, 4)
  end)
end

-- «Сжатие»: выделить файл или папку, открыть «Ещё», выбрать «Сжатие».
local function compressAction(item)
  ensureSelected(item, function()
    moreThenPick(COMPRESS_ENTRY, 'Пункт «Сжатие» не нашёлся')
  end)
end

-- «Извлечение»: то же самое для архивов.
local function extractAction(item)
  ensureSelected(item, function()
    moreThenPick(EXTRACT_ENTRY, 'Пункт «Извлечение» не нашёлся')
  end)
end

-- Выбор файла: та самая кнопка из строки, которую правило убрало из обхода.
local function selectItem(item)
  local row = findRow(item)
  if not row then
    sf.speak('Это не файл и не папка')
    return
  end
  local toggle = toggleOf(fresh(row))
  if not toggle or not press(toggle) then
    sf.speak('Не удалось выбрать')
  end
end

-- Расширение по имени файла. Имя в строке может быть с размером: «a.zip, 2 МБ».
local function extensionOf(name)
  if type(name) ~= 'string' then return nil end
  local lower = name:lower()
  local ext = lower:match('%.([%a%d]+)%s*$')
  if ext then return ext end
  ext = lower:match('%.([%a%d]+)[,;%(]')
  if ext then return ext end
  return lower:match('%.([%a%d]+)%s')
end

-- Архив ли это: смотрим имя в элементе, в строке и в её подписях.
local function isArchive(item)
  local names = {}
  local function add(value)
    if type(value) == 'string' and #value > 0 then names[#names + 1] = value end
  end

  add(item.text)
  add(item.contentDescription)
  add(item.stateDescription)

  local row = findRow(item)
  if row and row ~= item then
    add(row.text)
    add(row.contentDescription)
  end

  local source = row or item
  local ok, children = pcall(function() return source:children() end)
  if ok and type(children) == 'table' then
    local count = #children
    if count > 6 then count = 6 end
    for i = 1, count do
      add(children[i].text)
      add(children[i].contentDescription)
    end
  end

  for _, name in ipairs(names) do
    local ext = extensionOf(name)
    if ext and ARCHIVE_EXT[ext] then return true end
  end
  return false
end

local deleteAction = barAction(DELETE_QUERIES, 'Кнопка «Удалить» не нашлась')
local copyAction = barAction(COPY_QUERIES, 'Кнопка «Копировать» не нашлась')
local cutAction = barAction(CUT_QUERIES, 'Кнопка «Переместить» не нашлась')

-- Меню действий строится на элемент в фокусе. Свои пункты ставим только там,
-- где фокус стоит на файле или папке, и выше действий приложения.
sf.onActions(function(item)
  if not findRow(item) then return nil end
  local archiveAction
  if isArchive(item) then
    archiveAction = { title = 'Извлечение', first = true, run = extractAction }
  else
    archiveAction = { title = 'Сжатие', first = true, run = compressAction }
  end
  return {
    { title = 'Выбрать', first = true, run = selectItem },
    { title = 'Копировать', first = true, run = copyAction },
    { title = 'Переместить', first = true, run = cutAction },
    { title = 'Удалить', first = true, run = deleteAction },
    { title = 'Переименовать', first = true, run = renameAction },
    { title = 'Поделиться', first = true, run = shareAction },
    archiveAction,
  }
end)
