-- Действия с разговором в Google Messages.
-- Основа — скрипт google-messages-actions.lua (автор Surendra) из
-- github.com/aaron-gh/sandfly-scripts, лицензия Apache License 2.0.
-- Добавляет в меню действий каждого разговора в списке Google Messages пункты:
-- отметить как прочитанное, удалить и добавить контакт.
-- Работает так же, как руками: удержание на разговоре, затем «Другие
-- параметры» во всплывшем меню, и уже там нужный пункт. Тексты для поиска
-- даны и по-русски, и по-английски: скрипт работает при любом языке
-- интерфейса приложения.

local manifest = {
  id = 'wam.google-messages-actions',
  name = 'Google Messages: действия с разговором',
  version = '1.8',
  author = 'Алёшка',
  minApiVersion = 1,
  testedApiVersion = 2,
  description = 'В меню действий каждого разговора в списке Google Messages добавляет пункты: отметить как прочитанное, удалить и добавить контакт. Отмечает только прочитанным; если разговор уже прочитан, скрипт говорит «Уже прочитано». После удаления сам жмёт кнопку в диалоге «Отправить чат в корзину?»: ищет её по id android:id/button1, ищет и в остальных окнах и нажимает даже кнопки, которые не понимают программное нажатие. Подтверждение нажимается отдельной короткой задачей, иначе поиск не укладывается в две секунды, отпущенные на действие. Нажатия идут без пауз, как в оригинальном скрипте: меню не успевает зачитаться вслух. Кнопки ищутся и по русским, и по английским подписям.',
  apps = { 'com.google.android.apps.messaging' },
  permissions = { 'screen', 'actions', 'speech', 'input', 'system' },
}

local ROW_ID = 'swipeableContainer'

-- Кнопка «Другие параметры» во всплывшем после удержания меню. У Samsung она
-- называется именно так; остальные варианты — запасные.
local MORE = {
  { textContains = 'Другие параметры' },
  { textContains = 'Дополнительные параметры' },
  { textContains = 'Другие действия' },
  { textContains = 'Дополнительные действия' },
  { textContains = 'More options' },
  { textContains = 'Ещё' },
}

local ACTIONS = {
  {
    title = 'Отметить как прочитанное',
    -- Только чтение: непрочитанным скрипт не помечает никогда.
    queries = {
      { textContains = 'Отметить как прочитанное' },
      { textContains = 'Пометить как прочитанное' },
      { textContains = 'Mark as read' },
    },
    -- Если в меню есть этот пункт, разговор ещё непрочитан; если нет — уже
    -- прочитан, и скрипт так и говорит.
    already = {
      { textContains = 'Отметить как непрочитанное' },
      { textContains = 'Пометить как непрочитанное' },
      { textContains = 'Mark as unread' },
    },
    alreadyText = 'Уже прочитано',
  },
  {
    title = 'Удалить разговор',
    quick = true,
    queries = {
      { textContains = 'Удалить разговор' },
      { textContains = 'Удалить беседу' },
      { id = 'action_delete' },
      { textContains = 'Delete' },
      { textContains = 'Удалить' },
    },
    -- После удаления открывается диалог «Отправить чат в корзину?» с кнопкой
    -- «Отправить в корзину»: её тоже нажимаем, чтобы беседа ушла в корзину
    -- сразу.
    confirm = {
      { id = 'android:id/button1' },
      { textContains = 'Отправить в корзину' },
      { textContains = 'Переместить в корзину' },
      { textContains = 'Удалить в корзину' },
      { textContains = 'Move to trash' },
      -- Последней: эта подпись есть и в заголовке диалога.
      { textContains = 'В корзину' },
    },
  },
  {
    title = 'Добавить контакт',
    queries = {
      { textContains = 'Добавить контакт' },
      { textContains = 'Add contact' },
    },
  },
}

local function shortId(item)
  return string.match(item.id or '', '[^/]*$')
end

-- Текст пункта во всплывающем меню лежит в дочернем элементе, поэтому нажимать
-- нужно тот, который сам умеет нажиматься.
local function clickable(node)
  local current = node
  for _ = 1, 4 do
    if not current then break end
    if current.clickable then return current end
    current = current:parent()
  end
  return node
end

local function locate(queries)
  for _, query in ipairs(queries) do
    local found = sf.screen.find(query)
    if found then return clickable(found) end
  end
  return nil
end

local function waitFor(queries, tries)
  for _ = 1, tries or 8 do
    local found = locate(queries)
    if found then return found end
    sf.sleep(150)
  end
  return nil
end

-- Кнопка «Готово» режима выбора — как в оригинальном скрипте.
local DONE = { { id = 'action_mode_close_button' } }

-- Нажимает элемент. Обычное нажатие, а если элемент его не принял — тычок
-- пальцем по нему: так срабатывают кнопки, которые не понимают программное
-- нажатие.
local function press(item)
  local ok, clicked = pcall(function() return item:click() end)
  if ok and clicked then return true end
  local tapped = pcall(function() return item:tap() end)
  return tapped
end

-- Диалог подтверждения может оказаться не в том окне, что открытое меню:
-- меню ещё не закрылось, а диалог уже открыт. Поэтому ищем кнопку и в
-- активном окне, и во всех остальных.
local function anyWindow(queries)
  for _, query in ipairs(queries) do
    local found = sf.screen.find(query)
    if found then return clickable(found) end
  end
  local ok, windows = pcall(function() return sf.screen.windows() end)
  if ok and type(windows) == 'table' then
    for _, win in ipairs(windows) do
      if win.root then
        for _, query in ipairs(queries) do
          local foundOk, found = pcall(function() return win.root:find(query) end)
          if foundOk and found then return clickable(found) end
        end
      end
    end
  end
  return nil
end

local function waitAnywhere(queries, tries)
  for _ = 1, tries or 4 do
    local found = anyWindow(queries)
    if found then return found end
    sf.sleep(150)
  end
  return nil
end

-- Нажимает кнопку подтверждения удаления. Это отдельная задача-таймер: у
-- каждого вызова в скрипт свои две секунды, поэтому долгий поиск здесь не
-- обрывает основной вызов действия.
local function pressConfirm(queries)
  local ok, item = pcall(function()
    return sf.screen.waitFor({ id = 'android:id/button1' }, 800, 100)
  end)
  if ok and item then
    press(clickable(item))
    return true
  end
  local found = waitAnywhere(queries, 3)
  if found then
    press(found)
    return true
  end
  return false
end

-- Пробует нажать подтверждение через delay миллисекунд, и ещё несколько раз,
-- если диалог не успел открыться: он появляется не мгновенно.
local function confirmLater(queries, delay, attempts)
  sf.setTimeout(function()
    if pressConfirm(queries) then return end
    if attempts > 1 then confirmLater(queries, 900, attempts - 1) end
  end, delay)
end

-- Выполняется, когда выбран пункт меню действий. Здесь можно ждать, поэтому
-- sf.sleep разрешён.
local function perform(row, action)
  sf.sleep(400)
  if not row:longClick() then
    sf.speak('Не получилось удержать разговор')
    return
  end
  -- Как в оригинале: сразу нужный пункт, и только если его нет — «Другие
  -- параметры». Без долгих поисков и пауз, чтобы меню закрылось раньше, чем
  -- диктор успеет его зачитать.
  local target
  if action.quick then target = waitFor(action.queries, 2) end
  if not target then
    local more = waitFor(MORE, 4)
    if more then press(more) end
    target = waitFor(action.queries, 6)
  end
  if target then
    press(target)
    -- Удаление подтверждаем сами: диалог «Отправить чат в корзину?» и его
    -- кнопку жмём отдельной задачей. У вызова действия всего две секунды, и
    -- поиск кнопки в них не укладывался — скрипт молча обрывался.
    if action.confirm then confirmLater(action.confirm, 350, 3) end
    return
  end
  if action.already and waitFor(action.already, 2) then
    sf.speak(action.alreadyText)
  else
    sf.speak(action.title .. ': пункт не найден')
  end
  -- Выйти из режима выбора, как в оригинале: «Готово», иначе «назад».
  local done = locate(DONE)
  if done then press(done) else pcall(sf.system.back) end
end

sf.onActions(function(item)
  if shortId(item) ~= ROW_ID then return nil end
  local list = {}
  for _, action in ipairs(ACTIONS) do
    list[#list + 1] = { title = action.title, run = function() perform(item, action) end }
  end
  return list
end)
