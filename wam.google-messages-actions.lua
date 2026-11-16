-- Действия с разговором в Google Messages.
-- Русская версия скрипта google-messages-actions.lua (автор Surendra) из
-- github.com/aaron-gh/sandfly-scripts, лицензия Apache License 2.0.
-- Добавляет в меню действий каждого разговора в списке Google Messages пункты:
-- закрепить, пометить как непрочитанное, архивировать, удалить, отложить,
-- заблокировать и добавить контакт.
-- Тексты для поиска кнопок даны и по-русски, и по-английски: скрипт работает
-- при любом языке интерфейса приложения.

local manifest = {
  id = 'wam.google-messages-actions',
  name = 'Google Messages: действия с разговором',
  version = '1.0.0-ru',
  author = 'Surendra, русская версия',
  minApiVersion = 1,
  testedApiVersion = 1,
  description = 'В меню действий каждого разговора в списке Google Messages добавляет пункты: закрепить, пометить как непрочитанное, архивировать, удалить, отложить, заблокировать и добавить контакт.',
  apps = { 'com.google.android.apps.messaging' },
  permissions = { 'screen', 'actions', 'speech', 'input' },
}

local ROW_ID = 'swipeableContainer'

local MORE = {
  { contentDescription = 'Ещё' },
  { contentDescription = 'Дополнительные параметры' },
  { contentDescription = 'Другие действия' },
  { contentDescription = 'Дополнительные действия' },
  { textContains = 'More options' },
  { textContains = 'Дополнительные параметры' },
}
local DONE = { { id = 'action_mode_close_button' } }

-- "bar": кнопка на панели, которая появляется, когда разговор выделен.
-- "menu": пункт в меню «Ещё», а это отдельное окно.
local ACTIONS = {
  {
    title = 'Закрепить или открепить разговор',
    where = 'bar',
    queries = {
      { id = 'action_pin_to_top' },
      { textContains = 'Открепить' },
      { textContains = 'Отменить закрепление' },
      { textContains = 'Unpin' },
    },
  },
  {
    title = 'Пометить как непрочитанное или прочитанное',
    where = 'menu',
    queries = {
      { textContains = 'Пометить как непрочитанное' },
      { textContains = 'Отметить как непрочитанное' },
      { textContains = 'Пометить как прочитанное' },
      { textContains = 'Отметить как прочитанное' },
      { textContains = 'Mark as unread' },
      { textContains = 'Mark as read' },
    },
  },
  {
    title = 'Архивировать разговор',
    where = 'bar',
    queries = {
      { id = 'action_archive' },
      { textContains = 'Разархивировать' },
      { textContains = 'Вернуть из архива' },
      { textContains = 'Unarchive' },
    },
  },
  {
    title = 'Удалить разговор',
    where = 'bar',
    queries = { { id = 'action_delete' } },
  },
  {
    title = 'Отложить уведомления',
    where = 'bar',
    queries = {
      { id = 'action_snooze' },
      { textContains = 'Отложить' },
      { textContains = 'Snooze' },
    },
  },
  {
    title = 'Заблокировать',
    where = 'menu',
    queries = {
      { textContains = 'Заблокировать' },
      { textContains = 'Block' },
    },
  },
  {
    title = 'Добавить контакт',
    where = 'menu',
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
    sf.speak('Не получилось выделить разговор')
    return
  end
  local target = nil
  if action.where == 'bar' then
    target = waitFor(action.queries)
  else
    local more = waitFor(MORE)
    if more then
      more:click()
      target = waitFor(action.queries)
    end
  end
  if target then
    target:click()
    return
  end
  sf.speak(action.title .. ': пункт не найден')
  -- Выйти из режима выделения, чтобы список снова работал как обычно.
  local done = locate(DONE)
  if done then done:click() end
end

sf.onActions(function(item)
  if shortId(item) ~= ROW_ID then return nil end
  local list = {}
  for _, action in ipairs(ACTIONS) do
    list[#list + 1] = { title = action.title, run = function() perform(item, action) end }
  end
  return list
end)
