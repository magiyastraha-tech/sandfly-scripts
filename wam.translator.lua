local manifest = {
  id = 'wam.translator',
  name = 'Переводчик',
  version = '2.1',
  author = 'Slonobass',
  minApiVersion = 4,
  testedApiVersion = 4,
  description = 'Переводит текст в фокусе на любой язык из списка переводчика. Через меню команд → избранные языки или все языки с поиском → перевод в окне либо прямо в поле ввода.',
  permissions = { 'input', 'screen', 'actions', 'speech', 'dialogs', 'network', 'clipboard' },
  settings = {
    { key = 'replace', type = 'switch', title = 'Вставлять перевод обратно в поле ввода', default = true },
    { key = 'copy', type = 'switch', title = 'Копировать перевод в буфер обмена', default = true },
  },
  commands = {
    { id = 'translate', title = 'Перевести текст на выбранный язык', menu = true },
  },
}

-- Языки Google Cloud Translation (список SandFly.TranslationLanguages.ALL),
-- подписи по-русски. Служба в настройках SandFly переводит теги в свои коды.
local LANGUAGES = [[
af=Африкаанс
ak=Акан
am=Амхарский
ar=Арабский
as=Ассамский
ay=Аймара
az=Азербайджанский
be=Белорусский
bg=Болгарский
bho=Бходжпури
bm=Бамбара
bn=Бенгальский
bs=Боснийский
ca=Каталанский
ceb=Себуанский
ckb=Курдский (сорани)
co=Корсиканский
cs=Чешский
cy=Валлийский
da=Датский
de=Немецкий
doi=Догри
dv=Мальдивский
ee=Эве
el=Греческий
en=Английский
eo=Эсперанто
es=Испанский
et=Эстонский
eu=Баскский
fa=Персидский
fi=Финский
fil=Филиппинский
fr=Французский
fy=Фризский
ga=Ирландский
gd=Шотландский гэльский
gl=Галисийский
gn=Гуарани
gom=Конкани
gu=Гуджарати
ha=Хауса
haw=Гавайский
he=Иврит
hi=Хинди
hmn=Хмонг
hr=Хорватский
ht=Гаитянский креольский
hu=Венгерский
hy=Армянский
id=Индонезийский
ig=Игбо
ilo=Илоканский
is=Исландский
it=Итальянский
ja=Японский
jv=Яванский
ka=Грузинский
kk=Казахский
km=Кхмерский
kn=Каннада
ko=Корейский
kri=Крио
ku=Курдский
ky=Киргизский
la=Латинский
lb=Люксембургский
lg=Луганда
ln=Лингала
lo=Лаосский
lt=Литовский
lus=Мизо
lv=Латышский
mai=Майтхили
mg=Малагасийский
mi=Маори
mk=Македонский
ml=Малаялам
mn=Монгольский
mni=Манипури
mr=Маратхи
ms=Малайский
mt=Мальтийский
my=Бирманский
ne=Непальский
nl=Нидерландский
no=Норвежский
nso=Сепеди
ny=Ньянджа
om=Оромо
or=Ория
pa=Панджаби
pl=Польский
ps=Пушту
pt=Португальский
qu=Кечуа
ro=Румынский
ru=Русский
rw=Киньяруанда
sa=Санскрит
sd=Синдхи
si=Сингальский
sk=Словацкий
sl=Словенский
sm=Самоанский
sn=Шона
so=Сомалийский
sq=Албанский
sr=Сербский
st=Сесото
su=Сунданский
sv=Шведский
sw=Суахили
ta=Тамильский
te=Телугу
tg=Таджикский
th=Тайский
ti=Тигринья
tk=Туркменский
tr=Турецкий
ts=Тсонга
tt=Татарский
ug=Уйгурский
uk=Украинский
ur=Урду
uz=Узбекский
vi=Вьетнамский
xh=Коса
yi=Идиш
yo=Йоруба
zh-Hans=Китайский (упрощённый)
zh-Hant=Китайский (традиционный)
zu=Зулу
]]

local NAME, ALL = {}, {}

local function sortKey(name)
  return (name:gsub('Ё', 'Е'):gsub('ё', 'е'))
end

for line in LANGUAGES:gmatch('[^\r\n]+') do
  local code, name = line:match('^%s*([^=]+)%s*=%s*(.+)$')
  if code then
    NAME[code] = name
    ALL[#ALL + 1] = { code = code, name = name }
  end
end
table.sort(ALL, function(a, b) return sortKey(a.name) < sortKey(b.name) end)

-- Лимит одного запроса к службе перевода — 5000 символов, берём с запасом.
local MAX_CHARS = 4500

local function trim(s)
  return (s:gsub('^%s+', ''):gsub('%s+$', ''))
end

local function shorten(s, n)
  local len = utf8.len(s)
  if not len or len <= n then return s end
  return s:sub(1, utf8.offset(s, n + 1) - 1) .. '…'
end

-- Отрезает от текста кусок не длиннее MAX_CHARS, стараясь резать по абзацу,
-- предложению или слову. Разделитель остаётся в остатке, чтобы куски не склеились.
local function takeChunk(text)
  local len = utf8.len(text)
  if not len or len <= MAX_CHARS then return text, '' end

  local cut = utf8.offset(text, MAX_CHARS + 1) - 1
  local head = text:sub(1, cut)
  local pos = head:match('.*\n()\n')
      or head:match('.*[%.%!%?]()%s')
      or head:match('.*()%s')
  if pos and pos > 1 then
    return text:sub(1, pos - 1), text:sub(pos)
  end
  return text:sub(1, cut), text:sub(cut + 1)
end

local function translate(text, code)
  local parts, rest, guard = {}, text, 0
  while rest ~= '' do
    guard = guard + 1
    if guard > 40 then break end
    local chunk
    chunk, rest = takeChunk(rest)
    local ok, result = pcall(sf.translate, chunk, { to = code })
    if not ok then return nil, result end
    if type(result) ~= 'table' or not result.text then
      return nil, 'служба перевода ничего не вернула'
    end
    parts[#parts + 1] = result.text
  end
  return table.concat(parts, '\n')
end

-- ── Избранные языки ──

local FAVORITES_KEY = 'favorites'

-- Избранное — список кодов в том порядке, в каком языки стоят в окне.
-- По умолчанию список пуст: человек сам наполняет его из полного списка.
local function favorites()
  local saved = sf.storage.get(FAVORITES_KEY, {})
  if type(saved) ~= 'table' then return {} end
  local list = {}
  for _, code in ipairs(saved) do
    if type(code) == 'string' and NAME[code] then list[#list + 1] = code end
  end
  return list
end

local function saveFavorites(list)
  sf.storage.set(FAVORITES_KEY, list)
end

local function isFavorite(code)
  for _, item in ipairs(favorites()) do
    if item == code then return true end
  end
  return false
end

local function favoriteRows()
  local rows = {}
  for _, code in ipairs(favorites()) do
    rows[#rows + 1] = { value = code, label = NAME[code] }
  end
  return rows
end

-- string.lower в Lua не трогает кириллицу, а поиск не должен зависеть от регистра.
local CYRILLIC_LOWER = {}
for cp = 0x0410, 0x042F do
  CYRILLIC_LOWER[utf8.char(cp)] = utf8.char(cp + 0x20)
end
CYRILLIC_LOWER[utf8.char(0x0401)] = utf8.char(0x0451)

local function lower(s)
  s = string.lower(s)
  return (s:gsub('[%z\1-\127\194-\244][\128-\191]*', function(ch)
    return CYRILLIC_LOWER[ch] or ch
  end))
end

-- Полный список: поиск идёт и по названию языка, и по его коду.
local function languageRows(query)
  local needle = lower(trim(query or ''))
  local rows = {}
  for _, entry in ipairs(ALL) do
    if needle == ''
      or lower(entry.name):find(needle, 1, true)
      or lower(entry.code):find(needle, 1, true) then
      rows[#rows + 1] = { value = entry.code, label = entry.name }
    end
  end
  return rows
end

local favoritesWindow = nil

local function refreshFavorites()
  if not favoritesWindow then return end
  pcall(favoritesWindow.set, favoritesWindow, 'favorites', { items = favoriteRows() })
end

local function addFavorite(code)
  local name = NAME[code]
  if not name then return end
  if isFavorite(code) then
    sf.speak('Уже в избранном: ' .. name)
    return
  end
  local list = favorites()
  list[#list + 1] = code
  saveFavorites(list)
  refreshFavorites()
  sf.speak('В избранное добавлено: ' .. name)
end

local function removeFavorite(code, form)
  local list, kept, removed = favorites(), {}, false
  for _, item in ipairs(list) do
    if item == code then removed = true else kept[#kept + 1] = item end
  end
  if not removed then return end
  saveFavorites(kept)
  pcall(form.set, form, 'favorites', { items = favoriteRows() })
  sf.speak('Удалено: ' .. NAME[code])
end

local function moveFavorite(code, delta, form)
  local list, at = favorites(), nil
  for i, item in ipairs(list) do
    if item == code then at = i break end
  end
  if not at then return end
  local target = at + delta
  if target < 1 or target > #list then
    sf.speak(delta < 0 and 'Выше двигать некуда' or 'Ниже двигать некуда')
    return
  end
  list[at], list[target] = list[target], list[at]
  saveFavorites(list)
  pcall(form.set, form, 'favorites', { items = favoriteRows() })
  sf.speak((delta < 0 and 'Выше: ' or 'Ниже: ') .. NAME[code])
end

-- Окно со всеми языками: поиск сверху, список ниже. Двойной удар по языку
-- сразу переводит на него, а в меню действий у каждой строки — «Добавить в избранное».
local function openAllLanguages(onPick)
  sf.ui.window({
    title = 'Все языки',
    items = {
      {
        type = 'edit',
        id = 'search',
        label = 'Поиск',
        hint = 'название или код языка',
        onChange = function(value, form)
          local rows = languageRows(value)
          pcall(form.set, form, 'langs', {
            items = rows,
            label = trim(value) == '' and 'Языки' or ('Найдено: ' .. #rows),
          })
        end,
      },
      {
        type = 'items',
        id = 'langs',
        label = 'Языки',
        items = languageRows(''),
        actions = { 'Добавить в избранное' },
        onSelect = function(code, form)
          pcall(form.close, form)
          onPick(code)
        end,
        onAction = function(action, code)
          if action == 'Добавить в избранное' then addFavorite(code) end
        end,
      },
    },
  })
end

-- Главное окно: избранные языки, следом кнопка «Все языки».
local function openFavorites(onPick)
  local function pick(code)
    if favoritesWindow then
      pcall(favoritesWindow.close, favoritesWindow)
      favoritesWindow = nil
    end
    onPick(code)
  end

  favoritesWindow = sf.ui.window({
    title = 'Куда перевести?',
    items = {
      {
        type = 'items',
        id = 'favorites',
        label = 'Избранные языки',
        items = favoriteRows(),
        empty = 'Избранных языков пока нет. Откройте «Все языки» и добавьте нужные.',
        actions = { 'Переместить выше', 'Переместить ниже', 'Удалить' },
        onSelect = function(code, form)
          pcall(form.close, form)
          favoritesWindow = nil
          onPick(code)
        end,
        onAction = function(action, code, form)
          if action == 'Переместить выше' then
            moveFavorite(code, -1, form)
          elseif action == 'Переместить ниже' then
            moveFavorite(code, 1, form)
          elseif action == 'Удалить' then
            removeFavorite(code, form)
          end
        end,
      },
      {
        type = 'button',
        id = 'all',
        label = 'Все языки',
        onClick = function()
          openAllLanguages(pick)
        end,
      },
      {
        type = 'switch',
        id = 'copy',
        label = 'Копировать в буфер',
        value = sf.settings.get('copy') ~= false,
        onChange = function(value)
          sf.settings.set('copy', value)
        end,
      },
    },
    onClose = function()
      favoritesWindow = nil
    end,
  })
end

-- Поле ввода, в которое можно вставить перевод. Возвращает элемент и его текст.
local function inputField()
  local item = sf.screen.inputFocused()
  if item and item.editable and type(item.text) == 'string' then
    local value = trim(item.text)
    if value ~= '' then return item, value end
  end
end

-- Текст берём из поля ввода, иначе из элемента в фокусе. Если пусто — спрашиваем, откуда взять.
-- Второй результат — поле ввода, если текст взят из него: туда же можно вставить перевод.
local function getText()
  local field, fieldText = inputField()
  if fieldText then return fieldText, field end

  local item = sf.screen.focused()
  if item then
    for _, name in ipairs({ 'text', 'contentDescription' }) do
      local value = item[name]
      if type(value) == 'string' then
        value = trim(value)
        if value ~= '' then return value end
      end
    end
  end

  local options = {}

  local okSpoken, spoken = pcall(sf.speech.last)
  if okSpoken and type(spoken) == 'string' then
    spoken = trim(spoken)
    if spoken ~= '' then
      options[#options + 1] = {
        value = 'spoken',
        label = 'Последнее произнесённое: ' .. shorten(spoken, 60),
      }
    end
  end

  local okClip, clip = pcall(sf.clipboard.get)
  if okClip and type(clip) == 'string' then
    clip = trim(clip)
    if clip ~= '' then
      options[#options + 1] = {
        value = 'clipboard',
        label = 'Из буфера обмена: ' .. shorten(clip, 60),
      }
    end
  end

  options[#options + 1] = { value = 'prompt', label = 'Ввести текст вручную' }

  local choice = sf.ui.choose('В фокусе нет текста. Откуда взять текст?', options)
  if choice == 'spoken' then return spoken end
  if choice == 'clipboard' then return clip end
  if choice == 'prompt' then
    local typed = sf.ui.prompt('Текст для перевода')
    if typed then return trim(typed) end
  end
  return nil
end

-- Вставляет перевод в поле ввода вместо исходного текста. Поле перепроверяем заново:
-- пока шёл выбор языка и перевод, фокус мог уехать. Если текст в поле уже не тот,
-- ничего не меняем — иначе затрём то, что человек успел набрать.
local function replaceInField(original, translated)
  local target = sf.screen.inputFocused()
  if not target or not target.editable then return false, 'поле ввода больше не активно' end
  local current = type(target.text) == 'string' and trim(target.text) or ''
  if current ~= original then return false, 'текст в поле изменился' end
  local ok, done = pcall(target.setText, target, translated)
  if not ok then return false, tostring(done) end
  if done == false then return false, 'поле не принимает текст' end
  return true
end

sf.onCommand('translate', function()
  local text, field = getText()
  if not text or text == '' then return end

  openFavorites(function(code)
    local name = NAME[code] or code

    sf.speak('Перевод: ' .. name)
    local result, err = translate(text, code)
    if not result then
      sf.ui.alert(
        'Перевести не получилось.\n\n' .. tostring(err)
          .. '\n\nЕсли в настройках SandFly → Перевод выбрано «На устройстве», '
          .. 'этот язык может быть не скачан или не поддержан. '
          .. 'Google Cloud Translation понимает все языки из списка.',
        { title = 'Ошибка перевода' }
      )
      return
    end

    -- Копируем до вставки в поле: переключатель «Копировать в буфер» в главном окне
    -- отвечает именно за копирование после перевода, куда бы перевод ни пошёл.
    local copied = false
    if sf.settings.get('copy') ~= false then
      copied = (pcall(sf.clipboard.set, result))
    end

    -- Поле ввода: по умолчанию возвращаем перевод туда же, где был исходный текст.
    if field and sf.settings.get('replace') ~= false then
      local replaced, why = replaceInField(text, result)
      if replaced then
        sf.speak('Перевод вставлен: ' .. name .. (copied and ' (скопировано)' or ''))
        return
      end
      -- Не вышло — показываем перевод в окне и коротко говорим, почему поле не тронуто.
      sf.speak('В поле не вставлено: ' .. why)
    end

    sf.ui.text('Перевод: ' .. name .. (copied and ' (скопировано)' or ''), result)
  end)
end)
