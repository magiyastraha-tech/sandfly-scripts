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
-- Версия 1.8: жест одним пальцем вниз с удержанием читает статус контакта в
-- открытом чате: «онлайн», «был(а) в сети …». Статус ищется только в шапке,
-- выше ленты сообщений, — поэтому «был в сети» из текста сообщения за статус
-- не сойдёт. Скрипт ничего не нажимает, только проговаривает. Если статуса нет
-- (группа, канал, скрытая активность), он так и говорит: «Статус не найден».
--
-- Версия 1.7: фокус на список чатов проверяется после перевода. Приложение
-- дорисовывает главный экран уже после нашего фокуса и само уводит его на
-- заголовок сверху — список при этом успевает проговориться, а фокус остаётся
-- наверху. Теперь после каждого перевода скрипт смотрит, где фокус оказался, и,
-- если он ушёл из списка, переводит ещё раз — до четырёх попыток за секунду с
-- небольшим. В чат, открытый пользователем, фокус по-прежнему не лезет.
--
-- Версия 1.6: нажатие на отправку пробуется по очереди — сначала обычный клик,
-- потом касание по центру кнопки и только потом поиск заново. Если ни один
-- способ не сработал, команда говорит «Отправить не получилось», а не молчит.
-- Из нескольких совпадений берётся самое маленькое: у большого контейнера
-- центр может оказаться между кнопками. Ожидание начала записи больше не
-- складывает таймауты всех подписей подряд.
--
-- Версия 1.5: состояние записи распознаётся по паузе, «Отмене» и
-- «Отправить», а не по пропаже микрофона: микрофон из дерева не исчезает, и
-- второй жест начинал вторую запись вместо отправки. Отправка в Nekogram —
-- View с текстом «Отправить», а не кнопка с описанием.
--
-- Версия 1.4: команда «Голосовое: записать или отправить» на жест двумя
-- пальцами дважды. Первый жест начинает запись и удерживает её: палец на
-- микрофоне ведут вверх, до замка, — так запись продолжается после того, как
-- палец отпущен. Второй жест находит появившуюся кнопку отправки и нажимает её.
-- Если кнопки записи не нашлось, команда говорит об этом вслух, а не молчит.
--
-- Версия 1.3: заголовок в дереве есть, но сам он не фокусируемый — фокус
-- ставится на TextView внутри него. Попытка в чате теперь одна: скрипт
-- пробует до трёх раз за первый заход (пока чат дорисовывается), а потом в
-- этом чате фокус больше не трогает — иначе при каждом изменении экрана он
-- отбирал фокус обратно и «дёргал» его.
--
-- Версия 1.2: заголовок ищется по нескольким подписям; если сам заголовок
-- фокус не берёт, он ставится на ближайший элемент, который берёт. Скрипт
-- слушает не только смену окна, но и изменение содержимого экрана — чат в
-- Nekogram открывается внутри одного окна, и смены окна при этом может не быть.
-- Команда «Перейти к непрочитанным» проверяет всё это вручную и говорит, если
-- заголовка нет или он не берёт фокус.
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
  version = '1.8',
  author = 'Алёшка',
  minApiVersion = 2,
  testedApiVersion = 4,
  description = 'Убирает «Поделиться» и кнопку расшифровки из свайпа по сообщениям Nekogram и добавляет их в Actions сообщения. При открытии приложения фокус встаёт на список чатов, а при входе в чат — на заголовок «Непрочитанные сообщения». Жест «два пальца, дважды» записывает голосовое сообщение, он же его отправляет. Жест вниз с удержанием читает статус контакта в открытом чате.',
  apps = { 'tw.nekomimi.nekogram' },
  permissions = { 'screen', 'speech', 'actions', 'input' },
  commands = {
    { id = 'focus_chats', title = 'Перейти к списку чатов', menu = true },
    { id = 'focus_unread', title = 'Перейти к непрочитанным', menu = true },
    {
      id = 'voice_toggle',
      title = 'Голосовое: записать или отправить',
      gesture = 'twoFingerDoubleTap',
      menu = true,
    },
    {
      id = 'chat_status',
      title = 'Статус контакта',
      gesture = 'swipeDownAndHold',
      menu = true,
    },
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
    -- Подпись бывает и длиннее: «Вернуться назад». Кнопка — ImageButton,
    -- чтобы не поймать слово «назад» из текста сообщения.
    { className = 'ImageButton', textContains = 'назад' },
    { className = 'ImageButton', textContains = 'back' },
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

-- Фокус внутри этого списка. Сам контейнер считается тоже: SandFly отдаёт
-- фокус контейнеру, когда строки его не берут.
local function focusedInList(list, cur)
  if not cur then
    return false
  end
  if cur == list then
    return true
  end
  return isInside(list, cur)
end

-- Одного перевода мало: приложение дорисовывает экран уже после нас и уводит
-- фокус на заголовок сверху. Поэтому после каждой попытки смотрим, где фокус
-- оказался, и, если он не в списке, переводим снова.
local FOCUS_TRIES = 4
local FOCUS_STEP = 300

-- Переводит фокус в список и убеждается, что он там остался. Возвращает
-- признак успеха; список к концу может быть уже другим узлом.
local function placeFocus(list)
  if focusedInList(list, sf.screen.focused()) then
    return true
  end
  for _ = 1, FOCUS_TRIES do
    local row = firstRow(list)
    if row then
      pcall(function()
        row:focus()
      end)
    else
      pcall(function()
        list:focus()
      end)
    end
    sf.sleep(FOCUS_STEP)
    if focusedInList(list, sf.screen.focused()) then
      return true
    end
    -- Пользователь мог сам открыть чат — тогда больше не лезем.
    if insideSubScreen() then
      return false
    end
    -- Экран перерисовался: список берём заново, старый узел мог устареть.
    local again = findMainList(500)
    if again then
      list = again
    end
  end
  return false
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
    placeFocus(list)
  end)
end

sf.onAppEnter(function()
  focusChats()
end)

-- ── Фокус на заголовок «Непрочитанные сообщения» ──

local UNREAD_QUERIES = {
  { textContains = 'епрочитанные сообщения' },
  { textContains = 'епрочитанное сообщение' },
  { textContains = 'nread messages' },
  { textContains = 'nread message' },
}

-- Заголовок в Nekogram — точная подпись; обрывок без учёта регистра переживёт
-- другой регистр и лишние пробелы.
local function findUnreadHeader(timeout)
  for _, query in ipairs(UNREAD_QUERIES) do
    local header = sf.screen.waitFor(query, timeout, 250)
    if header then
      return header
    end
  end
  return nil
end

-- Быстрая проверка без ожидания — чтобы не поднимать задачу на каждое
-- изменение экрана.
local function unreadOnScreen()
  for _, query in ipairs(UNREAD_QUERIES) do
    if sf.screen.find(query) then
      return true
    end
  end
  return false
end

-- Один и тот же элемент из двух запросов — это разные объекты, поэтому
-- сравниваем по тексту и классу.
local function sameItem(a, b)
  if not a or not b then
    return false
  end
  if a == b then
    return true
  end
  return a.text == b.text and a.className == b.className
end

-- Заголовок обычно не фокусируемый сам: фокус переводим на него, а если не
-- вышло — на ближайшего родителя, который фокус берёт.
local function focusItem(item)
  pcall(function()
    item:showOnScreen()
  end)
  item:focus()
  if sameItem(sf.screen.focused(), item) then
    return true
  end
  local cur = item:parent()
  for _ = 1, 6 do
    if not cur then
      break
    end
    if cur.focusable then
      cur:focus()
      if sameItem(sf.screen.focused(), cur) then
        return true
      end
    end
    cur = cur:parent()
  end
  return false
end

-- Чат, в котором уже ставили фокус: окно плюс подпись заголовка.
local function headerKey(header)
  local app = sf.app()
  local window = app and app.window or ''
  return tostring(window) .. '|' .. tostring(header.text or header.contentDescription or '')
end

local lastKey = nil
local pending = false

-- Одна попытка на чат: до трёх заходов с паузой, пока чат дорисовывается.
-- После этого lastKey запомнен и в этом чате фокус больше не трогается.
local function attemptFocus(key)
  lastKey = key
  for round = 1, 3 do
    local header = findUnreadHeader(round == 1 and 1500 or 700)
    if not header then
      return
    end
    if header.visible == false then
      return
    end
    if not insideSubScreen() then
      return
    end
    if sameItem(sf.screen.focused(), header) then
      return
    end
    focusItem(header)
    sf.sleep(400)
  end
end

local function focusUnread()
  if sf.settings.get('focusUnread') == false then
    return
  end
  if pending then
    return
  end
  -- На главном экране и в настройках заголовка быть не может. Возврат в
  -- список чатов сбрасывает память о прошлом чате.
  if not insideSubScreen() then
    lastKey = nil
    return
  end
  if not unreadOnScreen() then
    return
  end
  pending = true
  sf.run(function()
    local ok, err = pcall(function()
      local header = findUnreadHeader(1500)
      if not header then
        return
      end
      if not insideSubScreen() then
        return
      end
      if header.visible == false then
        return
      end
      local key = headerKey(header)
      if key == lastKey then
        return
      end
      if sameItem(sf.screen.focused(), header) then
        lastKey = key
        return
      end
      attemptFocus(key)
    end)
    pending = false
    if not ok then
      print('Nekogram: фокус на непрочитанные — ' .. tostring(err))
    end
  end)
end

sf.onWindowChange(function()
  focusUnread()
end)

-- Чат открывается внутри того же окна, поэтому смены окна при этом может не
-- быть. Изменение содержимого экрана ловит вход в чат и без неё.
sf.onContentChange(function()
  focusUnread()
end)

-- Ручной переход: SandFly → Команды → «Перейти к непрочитанным».
sf.onCommand('focus_unread', function()
  local header = findUnreadHeader(1500)
  if not header then
    sf.speak('Заголовок непрочитанных не найден')
    return
  end
  if focusItem(header) then
    lastKey = headerKey(header)
    return
  end
  sf.speak('Заголовок непрочитанных не берёт фокус')
end)

-- ── Голосовое сообщение по жесту ──

-- Микрофон в поле ввода: пока поле пустое, там кнопка записи.
local MIC_QUERIES = {
  { contentDescription = 'Голосовое сообщение' },
  { contentDescription = 'Записать голосовое сообщение' },
  { contentDescription = 'Voice message' },
  { contentDescription = 'Record voice message' },
  { textContains = 'олосовое сообщение' },
  { textContains = 'oice message' },
}

-- Отправка во время записи. В Nekogram это View с текстом «Отправить», а не
-- кнопка с описанием, — поэтому ищем прежде всего по тексту. Поиск по описанию
-- идёт следом: такое же описание бывает у обычной кнопки отправки в поле ввода.
local SEND_TEXTS = {
  { text = 'Отправить' },
  { text = 'Send' },
}

local SEND_QUERIES = {
  { text = 'Отправить' },
  { text = 'Send' },
  { contentDescription = 'Отправить' },
  { contentDescription = 'Send' },
}

-- Признаки идущей записи: «Пауза» и «Отмена» — они есть на экране только во
-- время записи. Микрофон при этом из дерева не пропадает (он лишь уезжает за
-- экран), поэтому по нему состояние не определить — второй жест начинал
-- вторую запись вместо отправки.
local RECORDING_MARKERS = {
  { text = 'Пауза' },
  { text = 'Отмена' },
  { contentDescription = 'Пауза' },
  { contentDescription = 'Отмена' },
}

local function areaOf(item)
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

-- Из всех совпадений берём самое маленькое: у большого контейнера центр может
-- оказаться между кнопками, а нам нужна сама кнопка. Элемент без границ
-- отдаётся, только если других нет вовсе.
local function smallestMatch(queries)
  for _, query in ipairs(queries) do
    local ok, list = pcall(sf.screen.findAll, query, 20)
    if ok and list then
      local best, bestArea, fallback
      for _, item in ipairs(list) do
        if item.visible ~= false then
          if not fallback then
            fallback = item
          end
          local area = areaOf(item)
          if area > 0 and (bestArea == nil or area < bestArea) then
            best, bestArea = item, area
          end
        end
      end
      if best or fallback then
        return best or fallback
      end
    end
  end
  return nil
end

local function pointIn(item)
  local b = item and item.bounds
  if not b then
    return nil
  end
  if b.right - b.left <= 0 or b.bottom - b.top <= 0 then
    return nil
  end
  return math.floor((b.left + b.right) / 2), math.floor((b.top + b.bottom) / 2), b
end

-- Отправка по тексту: такое совпадение бывает только во время записи.
local function textSendOnScreen()
  for _, query in ipairs(SEND_TEXTS) do
    if smallestMatch({ query }) then
      return true
    end
  end
  return false
end

local function recordingUi()
  return smallestMatch(RECORDING_MARKERS) ~= nil or textSendOnScreen()
end

-- Ждём, пока признаки записи уйдут с экрана: значит, отправка сработала.
local function waitGone(timeout)
  local left = timeout
  while left > 0 do
    if not recordingUi() then
      return true
    end
    sf.sleep(150)
    left = left - 150
  end
  return not recordingUi()
end

local function waitRecording(timeout)
  local left = timeout
  while left > 0 do
    if recordingUi() then
      return true
    end
    sf.sleep(150)
    left = left - 150
  end
  return recordingUi()
end

-- Нажатие на «Отправить» по очереди разными способами: в Nekogram это обычный
-- View, у которого нет действия клика, и попасть в него можно только касанием
-- по центру.
local function pressSend(send)
  pcall(function()
    send:click()
  end)
  if waitGone(600) then
    return true
  end

  local x, y = pointIn(send)
  if x then
    pcall(function()
      sf.touch.tap(x, y)
    end)
    if waitGone(900) then
      return true
    end
  end

  if x then
    pcall(function()
      sf.touch.gesture({
        { points = { { x = x, y = y } }, start = 0, duration = 60 },
      })
    end)
    if waitGone(900) then
      return true
    end
  end

  if send.text then
    pcall(function()
      sf.screen.click({ text = send.text })
    end)
    if waitGone(900) then
      return true
    end
  end

  return false
end

-- Запись в Telegram начинается с нажатия на микрофон, а чтобы палец можно
-- было отпустить и запись продолжалась, палец ведут вверх до замка. Здесь то
-- же самое одним касанием: пауза на микрофоне и подъём вверх.
local function startRecording(mic)
  pcall(function()
    mic:showOnScreen()
  end)
  local x, y, b = pointIn(mic)
  if not x then
    return false
  end
  local up = (b.bottom - b.top) * 4
  if y - up < 80 then
    up = y - 80
  end
  if up < 40 then
    return false
  end
  return sf.touch.gesture({
    {
      points = { { x = x, y = y }, { x = x, y = y - up } },
      start = 0,
      duration = 900,
    },
  })
end

-- Одно и то же сочетание: запись идёт — отправить, не идёт — начать её.
sf.onCommand('voice_toggle', function()
  if recordingUi() then
    local send = smallestMatch(SEND_QUERIES)
    if not send then
      sf.speak('Кнопка отправки не найдена')
    elseif not pressSend(send) then
      sf.speak('Отправить не получилось')
    end
    return
  end

  local mic = smallestMatch(MIC_QUERIES)
  if not mic then
    sf.speak('Кнопка записи не найдена')
    return
  end
  if not startRecording(mic) then
    sf.speak('Не получилось начать запись')
    return
  end
  -- Замок срабатывает не всегда: если отправки не появилось, запись уже
  -- ушла коротким сообщением либо не началась.
  if not waitRecording(2500) then
    sf.speak('Запись не началась')
  end
end)

-- ── Статус контакта по жесту ──

-- Шапка чата показывает присутствие: «онлайн», «был(а) в сети 5 минут назад»,
-- «печатает…». Ищем по обрывкам подписи, в русском и английском. textContains
-- проверяет и текст, и contentDescription.
local STATUS_MARKERS = {
  'онлайн',
  'в сети',
  'печатает',
  'записывает',
  'online',
  'last seen',
  'typing',
  'recording',
}

-- Верх ленты сообщений: самый крупный видимый прокручиваемый список. Всё, что
-- выше него, — шапка чата.
local function messageListTop()
  local lists = sf.screen.findAll({ scrollable = true }, 20)
  if not lists then
    return nil
  end
  local best, bestArea = nil, 0
  for _, item in ipairs(lists) do
    if item.visible ~= false then
      local a = area(item)
      if a > bestArea then
        best, bestArea = item, a
      end
    end
  end
  local b = best and best.bounds
  if b and b.top > 0 then
    return b.top
  end
  return nil
end

-- Граница шапки по вертикали. Обычно это верх ленты сообщений; если списка
-- почему-то нет — верхняя четверть экрана. За границей статус не ищем, иначе
-- «был в сети» поймается из текста сообщения.
local function headerLimit()
  local limit = nil
  local root = sf.screen.root()
  local b = root and root.bounds
  if b and b.bottom > b.top then
    limit = b.top + math.floor((b.bottom - b.top) / 4)
  end
  local top = messageListTop()
  if top and (limit == nil or top < limit) then
    limit = top
  end
  return limit
end

-- Из совпадений в шапке берём самое маленькое — это сама подпись статуса, а не
-- контейнер вокруг неё. При равной площади — то, что выше.
local function statusOnScreen()
  local limit = headerLimit()
  local best, bestTop, bestArea = nil, nil, nil
  for _, marker in ipairs(STATUS_MARKERS) do
    local ok, list = pcall(sf.screen.findAll, { textContains = marker }, 30)
    if ok and list then
      for _, item in ipairs(list) do
        local b = item.bounds
        if item.visible ~= false and b and (limit == nil or b.top < limit) then
          local a = area(item)
          if bestArea == nil or a < bestArea or (a == bestArea and b.top < bestTop) then
            best, bestTop, bestArea = item, b.top, a
          end
        end
      end
    end
  end
  return best
end

local function statusText(item)
  local text = item.text
  if text == nil or text == '' then
    text = item.contentDescription
  end
  return text
end

-- Только проговаривает статус: никаких нажатий, чтобы не открыть профиль
-- вместо чтения.
sf.onCommand('chat_status', function()
  if not insideSubScreen() then
    sf.speak('Чат не открыт')
    return
  end
  local status = statusOnScreen()
  local text = status and statusText(status)
  if text == nil or text == '' then
    sf.speak('Статус не найден')
    return
  end
  sf.speak(text, { interrupt = true })
end)

-- Ручной переход: SandFly → Команды → «Перейти к списку чатов».
sf.onCommand('focus_chats', function()
  local list = findMainList(3000)
  if not list then
    sf.speak('Список чатов не найден')
    return
  end
  if not placeFocus(list) and not insideSubScreen() then
    sf.speak('Список чатов не найден')
  end
end)

print('Nekogram: кнопки сообщений в Actions, версия 1.8 загружена')
