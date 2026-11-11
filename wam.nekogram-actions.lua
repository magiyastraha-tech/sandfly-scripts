-- Nekogram: кнопки «Поделиться» и расшифровки — в Actions сообщения.
--
-- В каналах у каждого сообщения есть кнопка «Поделиться» (ImageButton с
-- описанием Share) — отдельная остановка свайпа посреди текста. У голосовых
-- сообщений к ней добавляется кнопка расшифровки. Скрипт убирает обе из свайпа
-- и добавляет их в меню Actions самого сообщения: кнопки не пропадают, а
-- переезжают туда.
--
-- Дерево Nekogram: сообщение — это ViewGroup с focusable и действиями Reply,
-- Copy, Forward…; «Поделиться» и расшифровка лежат внутри него отдельными
-- элементами. Поэтому правила для Actions навешиваются на сообщение, у
-- которого внутри есть нужная кнопка: SandFly сначала ищет цель действия
-- внутри сообщения, в котором открыто меню, и попадает в его собственную
-- кнопку, а не в первую на экране.
--
-- Действия из всех подошедших правил складываются в один список. Поэтому здесь
-- одно правило на одно действие: у голосового сообщения подходят оба правила и
-- в меню оказывается по одному пункту каждого. Нельзя писать два правила, где
-- списки пересекаются, — «Поделиться» задвоится.
--
-- Правила скрытия расшифровки ограничены className = 'Button'. Без этого
-- ограничения SandFly считает текстом элемента и текст самого сообщения — и
-- сообщение целиком, где встречалось слово «расшифровка», пропадало из свайпа.
-- По той же причине и в действиях цель ищется как Button, а не по одному тексту.
--
-- Надпись кнопки зависит и от языка, и от состояния: до расшифровки
-- «Открыть расшифровку», после — «Показать расшифровку» / «Скрыть расшифровку»,
-- в английском — Open Voice Transcription / Show transcript. Поэтому ищем по
-- обрывку слова, а не по точному тексту.
--
-- Версия 1.1: при входе в любой чат, если в нём есть заголовок «Непрочитанные
-- сообщения», фокус встаёт на него — дальше можно идти свайпом по непрочитанному.
-- Если заголовка нет, фокус остаётся там, где его поставил SandFly.
--
-- Версия 1.0: при открытии приложения фокус встаёт на список чатов.
-- В чате, настройках и других внутренних экранах скрипт фокус не трогает:
-- признак внутреннего экрана — кнопка «Назад» вверху.

local manifest = {
  id = 'wam.nekogram-actions',
  name = 'Nekogram: кнопки сообщений в Actions',
  version = '1.1',
  author = 'Алёшка',
  minApiVersion = 2,
  testedApiVersion = 4,
  description = 'Убирает «Поделиться» и кнопку расшифровки из свайпа по сообщениям Nekogram и добавляет их в Actions сообщения. При открытии приложения фокус встаёт на список чатов, а при входе в чат — на заголовок «Непрочитанные сообщения».',
  apps = { 'tw.nekomimi.nekogram' },
  permissions = { 'screen', 'speech', 'actions', 'input' },
  commands = {
    { id = 'focus_chats', title = 'Перейти к списку чатов', menu = true },
  },
  settings = {
    {
      key = 'focusChats',
      type = 'switch',
      title = 'Фокус на список чатов',
      summary = 'При открытии приложения фокус встаёт на список чатов',
      default = true,
    },
    {
      key = 'focusUnread',
      type = 'switch',
      title = 'Фокус на непрочитанные',
      summary = 'При входе в чат фокус встаёт на заголовок «Непрочитанные сообщения»',
      default = true,
    },
  },
  rules = {
    -- Скрываем сами кнопки: из свайпа они уходят, но остаются в дереве, так
    -- что действия ниже могут их нажать.
    {
      match = {
        className = 'ImageButton',
        contentDescription = 'Share',
        inside = { role = 'list' },
      },
      hide = true,
    },
    {
      match = {
        className = 'ImageButton',
        contentDescription = 'Поделиться',
        inside = { role = 'list' },
      },
      hide = true,
    },
    -- Только Button: иначе правило задевает само сообщение, в тексте которого
    -- встретилось слово «расшифровка».
    {
      match = {
        className = 'Button',
        textContains = 'асшифров',
        inside = { role = 'list' },
      },
      hide = true,
    },
    {
      match = {
        className = 'Button',
        textContains = 'transcri',
        inside = { role = 'list' },
      },
      hide = true,
    },

    -- Голосовое сообщение: расшифровка.
    {
      match = {
        className = 'ViewGroup',
        focusable = true,
        has = { className = 'Button', textContains = 'асшифров' },
      },
      actions = {
        { title = 'Показать расшифровку', click = { className = 'Button', textContains = 'асшифров' } },
      },
    },
    {
      match = {
        className = 'ViewGroup',
        focusable = true,
        has = { className = 'Button', textContains = 'transcri' },
      },
      actions = {
        { title = 'Show transcript', click = { className = 'Button', textContains = 'transcri' } },
      },
    },

    -- Любое сообщение с «Поделиться», голосовое в том числе.
    {
      match = {
        className = 'ViewGroup',
        focusable = true,
        has = { className = 'ImageButton', contentDescription = 'Share' },
      },
      actions = {
        { title = 'Поделиться', click = { className = 'ImageButton', contentDescription = 'Share' } },
      },
    },
    {
      match = {
        className = 'ViewGroup',
        focusable = true,
        has = { className = 'ImageButton', contentDescription = 'Поделиться' },
      },
      actions = {
        { title = 'Поделиться', click = { className = 'ImageButton', contentDescription = 'Поделиться' } },
      },
    },
  },
}

-- ── Фокус на список чатов ──

-- Площадь элемента по границам: из нескольких списков на экране главный —
-- самый большой.
local function area(item)
  local b = item and item.bounds
  if not b then
    return 0
  end
  local w = b.right - b.left
  local h = b.bottom - b.top
  if w <= 0 or h <= 0 then
    return 0
  end
  return w * h
end

-- Самый крупный видимый прокручиваемый список на экране.
local function findMainList(timeout)
  local first = sf.screen.waitFor({ scrollable = true }, timeout or 8000, 300)
  if not first then
    return nil
  end
  local best = first
  local bestArea = area(first)
  local lists = sf.screen.findAll({ scrollable = true }, 20)
  if lists then
    for _, item in ipairs(lists) do
      if item.visible then
        local a = area(item)
        if a > bestArea then
          best = item
          bestArea = a
        end
      end
    end
  end
  return best
end

-- Кнопка «Назад» вверху — признак того, что открыт чат, настройки или другой
-- внутренний экран. На главном экране её нет: там фокус и переводим.
local function insideSubScreen()
  local queries = {
    { contentDescription = 'Назад' },
    { contentDescription = 'Back' },
    { text = 'Назад' },
  }
  for _, query in ipairs(queries) do
    if sf.screen.find(query) then
      return true
    end
  end
  return false
end

-- Элемент внутри этого списка: поднимаемся по родителям.
local function isInside(parent, item)
  local cur = item
  for _ = 1, 12 do
    if not cur then
      return false
    end
    cur = cur:parent()
    if not cur then
      return false
    end
    if cur == parent then
      return true
    end
  end
  return false
end

-- Первая живая строка списка — первый чат.
local function firstRow(list)
  local rows = list:findAll({ focusable = true }, 40)
  if not rows then
    return nil
  end
  local fallback = nil
  for _, row in ipairs(rows) do
    if row.visible then
      local label = row.text
      if label == nil or label == '' then
        label = row.contentDescription
      end
      if label ~= nil and label ~= '' then
        if not fallback then
          fallback = row
        end
        -- Строка списка: у неё заполнено collectionItem.
        if row.collectionItem then
          return row
        end
      end
    end
  end
  return fallback
end

-- Главный экран Nekogram: ставим фокус на список чатов. Если контейнер
-- фокус не берёт — на первый чат.
local function focusChats()
  if sf.settings.get('focusChats') == false then
    return
  end
  sf.run(function()
    local list = findMainList(8000)
    if not list then
      return
    end
    -- Пока ждали список, мог открыться чат или настройки.
    if insideSubScreen() then
      return
    end
    local cur = sf.screen.focused()
    if cur and isInside(list, cur) then
      return
    end
    local row = firstRow(list)
    if row then
      row:focus()
    else
      list:focus()
    end
  end)
end

sf.onAppEnter(function()
  focusChats()
end)

-- ── Фокус на заголовок «Непрочитанные сообщения» ──

local UNREAD_RU = { textContains = 'епрочитанные сообщения' }
local UNREAD_EN = { textContains = 'nread messages' }

-- Заголовок в Nekogram — точная подпись; обрывок без учёта регистра переживёт
-- другой регистр и лишние пробелы.
local function findUnreadHeader(timeout)
  local header = sf.screen.waitFor(UNREAD_RU, timeout, 250)
  if not header then
    header = sf.screen.waitFor(UNREAD_EN, 700, 250)
  end
  return header
end

-- Один и тот же элемент из двух запросов — это разные объекты, поэтому
-- сравниваем по тексту и классу.
local function sameItem(a, b)
  if not a or not b then
    return false
  end
  return a.text == b.text and a.className == b.className
end

local unreadGen = 0

local function focusUnread()
  if sf.settings.get('focusUnread') == false then
    return
  end
  unreadGen = unreadGen + 1
  local mine = unreadGen
  sf.run(function()
    local header = findUnreadHeader(3000)
    if not header or mine ~= unreadGen then
      return
    end
    -- Заголовок бывает только в чате; на главном экране и в настройках не лезем.
    if not insideSubScreen() then
      return
    end
    if header.visible == false then
      return
    end
    if sameItem(sf.screen.focused(), header) then
      return
    end
    header:focus()
  end)
end

sf.onWindowChange(function()
  focusUnread()
end)

-- Ручной переход: SandFly → Команды → «Перейти к списку чатов».
sf.onCommand('focus_chats', function()
  local list = findMainList(3000)
  if not list then
    sf.speak('Список чатов не найден')
    return
  end
  local row = firstRow(list)
  if row then
    row:focus()
  elseif not list:focus() then
    sf.speak('Список чатов не найден')
  end
end)

print('Nekogram: кнопки сообщений в Actions, версия 1.1 загружена')
