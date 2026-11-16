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
  version = '1.3',
  author = 'Алёшка',
  minApiVersion = 1,
  testedApiVersion = 1,
  description = 'В меню действий каждого разговора в списке Google Messages добавляет пункты: отметить как прочитанное, удалить и добавить контакт. Скрипт удерживает разговор, открывает «Другие параметры» и нажимает нужный пункт. Кнопки ищутся и по русским, и по английским подписям.',
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
    queries = {
      { textContains = 'Отметить как прочитанное' },
      { textContains = 'Пометить как прочитанное' },
      { textContains = 'Отметить как непрочитанное' },
      { textContains = 'Пометить как непрочитанное' },
      { textContains = 'Mark as read' },
      { textContains = 'Mark as unread' },
    },
  },
  {
    title = 'Удалить разговор',
    queries = {
      { textContains = 'Удалить разговор' },
      { textContains = 'Удалить беседу' },
      { id = 'action_delete' },
      { textContains = 'Delete' },
      { textContains = 'Удалить' },
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

-- Выполняется, когда выбран пункт меню действий. Здесь можно ждать, поэтому
-- sf.sleep разрешён.
local function perform(row, action)
  sf.sleep(400)
  if not row:longClick() then
    sf.speak('Не получилось удержать разговор')
    return
  end
  -- Иногда нужный пункт лежит прямо во всплывшем меню.
  local target = waitFor(action.queries, 4)
  if not target then
    local more = waitFor(MORE, 8)
    if more then more:click() end
    target = waitFor(action.queries, 8)
  end
  if target then
    target:click()
    return
  end
  sf.speak(action.title .. ': пункт не найден')
  -- Закрыть всплывшее меню, чтобы список снова работал как обычно.
  pcall(sf.system.back)
end

sf.onActions(function(item)
  if shortId(item) ~= ROW_ID then return nil end
  local list = {}
  for _, action in ipairs(ACTIONS) do
    list[#list + 1] = { title = action.title, run = function() perform(item, action) end }
  end
  return list
end)
