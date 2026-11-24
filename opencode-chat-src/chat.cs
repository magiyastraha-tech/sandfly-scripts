using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Media;
using System.Net;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;
using System.Windows.Forms;

namespace OpenCodeChat
{
    internal sealed class FileItem
    {
        public string Path;
        public string Name;
        public long Size;
        public DateTime Modified;
    }

    internal sealed class ModelItem
    {
        public string Id;
        public string Display;
        public bool Mine;
        public bool Offline;
        public string Gguf;

        public ModelItem(string id)
        {
            Id = id;
        }

        public ModelItem(string id, string display, bool mine)
        {
            Id = id;
            Display = display;
            Mine = mine;
        }

        public override string ToString()
        {
            if (Display != null && Display.Length > 0) return Display;
            int slash = Id.IndexOf('/');
            if (slash >= 0 && slash + 1 < Id.Length) return Id.Substring(slash + 1);
            return Id;
        }
    }

    internal sealed class ChatForm : Form
    {
        private readonly string root;
        private readonly string projectsDir;
        private readonly string exePath;
        private readonly string downloadsDir;
        private readonly string userName = "Алёшка";

        private RichTextBox transcript;
        private TextBox input;
        private Button detachBtn;
        private Button newChatBtn;
        private Button logBtn;
        private Button profileBtn;
        private Button serviceBtn;
        private Button addModelBtn;
        private ComboBox modelBox;
        private Label startedLabel;
        private Label attachedLabel;
        private Label statusLabel;
        private ListView filesView;
        private System.Windows.Forms.Timer tick;
        private int elapsed;

        private Font headerFont;
        private Font bodyFont;

        private readonly List<FileItem> pending = new List<FileItem>();
        private string sessionId = null;
        private DateTime startedAt = DateTime.Now;
        private bool busy = false;

        // «Стоп»: пока движок отвечает, здесь лежит его процесс.
        private Button stopBtn;
        private Button copyBtn;
        private Process activeProc;
        private volatile bool stopRequested;
        private string lastAnswer = "";

        // Озвучка: скрытая метка с ролью «предупреждение» — экранный диктор
        // читает её текст целиком, как только он меняется.
        private Label announcer;
        private System.Windows.Forms.Timer announceTimer;
        private string pendingAnnounce = "";

        // Границы сообщений в переписке и кэш, чтобы не пересчитывать зря.
        private List<int[]> blocks = new List<int[]>();
        private List<string> blocksAuthors = new List<string>();
        private string blocksText = null;

        private readonly string historyRtf;
        private readonly string historyState;
        private string preferredModel = "";

        // Офлайн-модели: файлы .gguf и сервер llama.cpp рядом с программой.
        private readonly string modelsFile;
        private readonly string llamaDir;
        private readonly object llamaLock = new object();
        private Process llamaProc;
        private string llamaLoaded = null;
        private string offlineError = "";
        private bool loadingOffline = false;
        private List<string> lastFound = new List<string>();
        private const int OfflinePort = 8099;

        private static readonly string[] FallbackModels = new string[]
        {
            "opencode/deepseek-v4.1-flash-free",
            "opencode/nemotron-3.5-super-vl-free",
            "opencode/big-pickle",
            "opencode/hy4-flash-free",
            "opencode/mimo-v2.6-flash-free",
            "opencode/iceman-free",
            "opencode/tidepool-alpha-free",
            "opencode/flint-40b-free",
            "opencode/beam-free",
            "opencode/nemotron-3.5-lightning-free"
        };

        private static readonly string[] ApiModels = new string[]
        {
            "deepseek/deepseek-flash",
            "deepseek/deepseek-v4-pro"
        };

        public ChatForm()
        {
            root = AppDomain.CurrentDomain.BaseDirectory;
            projectsDir = Path.Combine(root, "projects");
            exePath = Path.Combine(root, "engine", "opencode.exe");
            if (!File.Exists(exePath)) exePath = Path.Combine(root, "opencode.exe");
            downloadsDir = FindDownloads();
            string stateDir = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "OpenCodeChat");
            historyRtf = Path.Combine(stateDir, "chat.rtf");
            historyState = Path.Combine(stateDir, "chat.ini");
            modelsFile = Path.Combine(stateDir, "models.txt");
            llamaDir = Path.Combine(root, "engine", "llama");

            if (!Directory.Exists(projectsDir)) Directory.CreateDirectory(projectsDir);
            WriteOfflineConfig();

            headerFont = new Font("Segoe UI", 11f, FontStyle.Bold);
            bodyFont = new Font("Segoe UI", 11f, FontStyle.Regular);

            BuildUi();
            BuildMenus();
            if (!LoadHistory()) StartChat(false);

            transcript.Font = bodyFont;
        }

        private static string FindDownloads()
        {
            string user = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
            string d = Path.Combine(user, "Downloads");
            try
            {
                if (!Directory.Exists(d)) Directory.CreateDirectory(d);
            }
            catch
            {
            }
            if (Directory.Exists(d)) return d;
            string desk = Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory);
            return desk;
        }

        private void BuildUi()
        {
            Text = "Slonobass agent";
            StartPosition = FormStartPosition.CenterScreen;
            KeyPreview = true;
            ClientSize = new Size(980, 740);
            MinimumSize = new Size(760, 560);
            Font = new Font("Segoe UI", 10f);
            KeyPreview = true;
            KeyDown += FormKeyDown;

            TableLayoutPanel main = new TableLayoutPanel();
            main.Dock = DockStyle.Fill;
            main.ColumnCount = 1;
            main.RowCount = 7;
            main.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100f));
            main.RowStyles.Add(new RowStyle(SizeType.AutoSize));
            main.RowStyles.Add(new RowStyle(SizeType.Percent, 100f));
            main.RowStyles.Add(new RowStyle(SizeType.AutoSize));
            main.RowStyles.Add(new RowStyle(SizeType.Absolute, 96f));
            main.RowStyles.Add(new RowStyle(SizeType.AutoSize));
            main.RowStyles.Add(new RowStyle(SizeType.Absolute, 190f));
            main.RowStyles.Add(new RowStyle(SizeType.AutoSize));
            main.Padding = new Padding(8);

            // --- header ---
            FlowLayoutPanel header = new FlowLayoutPanel();
            header.AutoSize = true;
            header.WrapContents = true;
            header.Dock = DockStyle.Fill;

            startedLabel = new Label();
            startedLabel.AutoSize = true;
            startedLabel.Padding = new Padding(0, 6, 18, 0);
            startedLabel.AccessibleName = "Начало разговора";
            header.Controls.Add(startedLabel);

            Label modelLabel = new Label();
            modelLabel.Text = "Модель:";
            modelLabel.AutoSize = true;
            modelLabel.Padding = new Padding(0, 8, 4, 0);
            header.Controls.Add(modelLabel);

            modelBox = new ComboBox();
            modelBox.DropDownStyle = ComboBoxStyle.DropDownList;
            modelBox.Width = 300;
            modelBox.Margin = new Padding(0, 3, 12, 3);
            modelBox.AccessibleName = "Модель";
            modelBox.AccessibleDescription = "Список моделей. Сверху раздел «Мой профиль» — модели вашего аккаунта DeepSeek, ниже бесплатные модели.";
            header.Controls.Add(modelBox);

            addModelBtn = new Button();
            addModelBtn.Text = "&Добавить модель…";
            addModelBtn.AutoSize = true;
            addModelBtn.Margin = new Padding(0, 3, 12, 3);
            addModelBtn.AccessibleName = "Добавить модель";
            addModelBtn.AccessibleDescription = "Выбрать файл модели .gguf на этом компьютере и добавить его в список";
            addModelBtn.Click += delegate { AddOfflineModel(); };
            header.Controls.Add(addModelBtn);

            profileBtn = new Button();
            profileBtn.Text = "Мой п&рофиль…";
            profileBtn.AutoSize = true;
            profileBtn.AccessibleName = "Мой профиль DeepSeek";
            profileBtn.AccessibleDescription = "Свой аккаунт DeepSeek, оплаченные токены";
            profileBtn.Click += delegate { OpenProfile(); };
            header.Controls.Add(profileBtn);

            serviceBtn = new Button();
            serviceBtn.Text = "Дру&гие сервисы…";
            serviceBtn.AutoSize = true;
            serviceBtn.AccessibleName = "Другие сервисы";
            serviceBtn.AccessibleDescription = "Polza.ai, AnyModel или свой адрес: ключ и список моделей";
            serviceBtn.Click += delegate { OpenOtherService(); };
            header.Controls.Add(serviceBtn);

            newChatBtn = new Button();
            newChatBtn.Text = "&Новый разговор";
            newChatBtn.AutoSize = true;
            newChatBtn.AccessibleName = "Новый разговор";
            newChatBtn.Click += delegate { NewChat(); };
            header.Controls.Add(newChatBtn);

            logBtn = new Button();
            logBtn.Text = "&Журнал ошибок";
            logBtn.AutoSize = true;
            logBtn.AccessibleName = "Журнал ошибок";
            logBtn.AccessibleDescription = "Папка log с записями об ошибках";
            logBtn.Click += delegate { OpenLogFolder(); };
            header.Controls.Add(logBtn);

            main.Controls.Add(header, 0, 0);

            // --- transcript ---
            transcript = new RichTextBox();
            transcript.Dock = DockStyle.Fill;
            transcript.ReadOnly = true;
            transcript.BorderStyle = BorderStyle.FixedSingle;
            transcript.WordWrap = true;
            transcript.ScrollBars = RichTextBoxScrollBars.Vertical;
            transcript.BackColor = Color.White;
            transcript.ForeColor = Color.Black;
            transcript.HideSelection = false;
            transcript.DetectUrls = true;
            transcript.ShortcutsEnabled = true;
            transcript.AccessibleName = "Переписка";
            transcript.KeyDown += TranscriptKeyDown;
            transcript.LinkClicked += delegate(object s2, LinkClickedEventArgs le) { OpenLink(le.LinkText); };
            main.Controls.Add(transcript, 0, 1);

            // --- attach state (row 2) ---
            attachedLabel = new Label();
            attachedLabel.AutoSize = true;
            attachedLabel.Text = "Файлы к сообщению: нет";
            attachedLabel.AccessibleName = "Файлы к сообщению";
            attachedLabel.Margin = new Padding(0, 4, 0, 2);
            main.Controls.Add(attachedLabel, 0, 2);

            // --- input editor (row 3) ---
            input = new TextBox();
            input.Dock = DockStyle.Fill;
            input.Multiline = true;
            input.ScrollBars = ScrollBars.Vertical;
            input.AcceptsReturn = true;
            input.Margin = new Padding(0, 0, 0, 4);
            input.AccessibleName = "Сообщение";
            input.KeyDown += InputKeyDown;
            main.Controls.Add(input, 0, 3);

            // --- buttons (row 4): только снятие файлов, остальное — сочетания клавиш ---
            FlowLayoutPanel buttons = new FlowLayoutPanel();
            buttons.AutoSize = true;
            buttons.AutoSizeMode = AutoSizeMode.GrowAndShrink;
            buttons.FlowDirection = FlowDirection.LeftToRight;
            buttons.WrapContents = false;
            buttons.Margin = new Padding(0);

            detachBtn = new Button();
            detachBtn.Text = "Снять &файлы";
            detachBtn.Width = 200;
            detachBtn.Height = 28;
            detachBtn.AccessibleName = "Снять прикреплённые файлы";
            detachBtn.Enabled = false;
            detachBtn.Click += delegate { ClearPending(); };
            buttons.Controls.Add(detachBtn);

            stopBtn = new Button();
            stopBtn.Text = "&Стоп";
            stopBtn.Width = 140;
            stopBtn.Height = 28;
            stopBtn.AccessibleName = "Остановить ответ";
            stopBtn.AccessibleDescription = "Обрывает ответ модели; написанное остаётся в переписке";
            stopBtn.Enabled = false;
            stopBtn.Click += delegate { StopAgent(); };
            buttons.Controls.Add(stopBtn);

            copyBtn = new Button();
            copyBtn.Text = "&Копировать ответ";
            copyBtn.Width = 200;
            copyBtn.Height = 28;
            copyBtn.AccessibleName = "Копировать последний ответ";
            copyBtn.AccessibleDescription = "Кладёт последний ответ модели в буфер обмена";
            copyBtn.Click += delegate { CopyLastAnswer(); };
            buttons.Controls.Add(copyBtn);

            main.Controls.Add(buttons, 0, 4);

            // --- files panel (row 5) ---
            GroupBox filesGroup = new GroupBox();
            filesGroup.Text = "Файлы от агента";
            filesGroup.Dock = DockStyle.Fill;
            filesGroup.Padding = new Padding(6);
            filesGroup.Margin = new Padding(0, 6, 0, 0);

            filesView = new ListView();
            filesView.Dock = DockStyle.Fill;
            filesView.View = View.Details;
            filesView.FullRowSelect = true;
            filesView.MultiSelect = false;
            filesView.HideSelection = false;
            filesView.LabelEdit = false;
            filesView.HeaderStyle = ColumnHeaderStyle.Nonclickable;
            filesView.Columns.Add("Имя", 150);
            filesView.Columns.Add("Время", 60);
            filesView.Columns.Add("Размер", 70);
            filesView.AccessibleName = "Файлы от агента";
            filesView.KeyDown += FilesViewKeyDown;
            filesGroup.Controls.Add(filesView);

            main.Controls.Add(filesGroup, 0, 5);

            // --- status (row 6) ---
            statusLabel = new Label();
            statusLabel.Text = "Готов";
            statusLabel.Dock = DockStyle.Fill;
            statusLabel.AutoSize = false;
            statusLabel.MinimumSize = new Size(0, 26);
            statusLabel.TextAlign = ContentAlignment.MiddleLeft;
            statusLabel.AccessibleName = "Состояние";
            main.Controls.Add(statusLabel, 0, 6);

            // Скрытая метка для озвучки ответов целиком.
            announcer = new Label();
            announcer.AutoSize = false;
            announcer.Size = new Size(1, 1);
            announcer.Location = new Point(-3000, -3000);
            announcer.AccessibleRole = AccessibleRole.Alert;
            announcer.AccessibleName = "Оповещение";
            Controls.Add(announcer);

            announceTimer = new System.Windows.Forms.Timer();
            // Пауза нужна, чтобы диктор успел закончить короткую реплику
            // о переходе, прежде чем начнётся чтение сообщения целиком.
            announceTimer.Interval = 700;
            announceTimer.Tick += delegate
            {
                announceTimer.Stop();
                if (pendingAnnounce.Length == 0) return;
                // Только имя доступности: смена Text поднимает ещё одно событие
                // и диктор начинает читать заново с начала, обрывая себя же.
                announcer.AccessibleName = pendingAnnounce;
                try
                {
                    // Одно событие на всё сообщение. Два события подряд
                    // (NAME_CHANGE и ALERT) диктор обрабатывает как два
                    // сообщения и второе обрывает первое на середине.
                    NotifyWinEvent(0x0002, announcer.Handle, -4, 0);
                }
                catch
                {
                }
            };

            Controls.Add(main);
            KeyPress += FormKeyPress;

            tick = new System.Windows.Forms.Timer();
            tick.Interval = 1000;
            tick.Tick += delegate
            {
                elapsed++;
                if (loadingOffline)
                    statusLabel.Text = "Загружаю офлайн-модель… " + elapsed.ToString() + " с";
                else
                    statusLabel.Text = "Агент отвечает… " + elapsed.ToString() + " с";
            };
        }

        private void BuildMenus()
        {
            ContextMenuStrip menu = new ContextMenuStrip();
            ToolStripMenuItem save = new ToolStripMenuItem("Сохранить в Загрузки");
            save.Click += delegate { SaveSelected(); };
            menu.Items.Add(save);
            ToolStripMenuItem open = new ToolStripMenuItem("Открыть файл");
            open.Click += delegate { OpenSelected(); };
            menu.Items.Add(open);
            filesView.ContextMenuStrip = menu;
        }

        protected override void OnShown(EventArgs e)
        {
            base.OnShown(e);
            if (!File.Exists(exePath))
            {
                Log.Write("ERROR", "Не найден движок: " + exePath);
                MessageBox.Show(this,
                    "Не найден движок engine\\opencode.exe.\r\nРаспакуйте архив целиком в одну папку и запускайте Slonobass-Agent.exe из неё.",
                    "Slonobass agent", MessageBoxButtons.OK, MessageBoxIcon.Error);
                Close();
                return;
            }
            Log.Write("START", "Движок: " + exePath + "; рабочая папка: " + projectsDir + "; Загрузки: " + downloadsDir
                + "; профиль DeepSeek: " + (Profile.HasKey ? "подключён " + Profile.Hint : "нет")
                + "; другой сервис: " + (Service.HasProfile ? Service.Label + " " + Service.Hint : "нет"));
            if (Profile.HasKey && statusLabel.Text == "Готов") statusLabel.Text = "Готов. Мой профиль DeepSeek подключён: " + Profile.Hint;
            input.Focus();
            LoadModels();
        }

        protected override void OnFormClosing(FormClosingEventArgs e)
        {
            if (busy)
            {
                DialogResult r = MessageBox.Show(this,
                    "Агент ещё отвечает. Закрыть окно?",
                    "Slonobass agent", MessageBoxButtons.YesNo, MessageBoxIcon.Question);
                if (r != DialogResult.Yes) e.Cancel = true;
            }
            if (!e.Cancel)
            {
                SaveHistory();
                StopOffline();
            }
            base.OnFormClosing(e);
        }

        // ---------- chat flow ----------

        private void StartChat(bool keepScreen)
        {
            startedAt = DateTime.Now;
            sessionId = null;
            startedLabel.Text = "Разговор начат: " + startedAt.ToString("dd.MM.yyyy, HH:mm");
            if (!keepScreen)
            {
                transcript.Clear();
            }
            AppendHeader();
            if (!keepScreen) SaveHistory();
        }

        private bool LoadHistory()
        {
            try
            {
                if (!File.Exists(historyRtf) || !File.Exists(historyState)) return false;
                transcript.LoadFile(historyRtf, RichTextBoxStreamType.RichText);
                string[] lines = File.ReadAllLines(historyState);
                string savedDir = null;
                for (int i = 0; i < lines.Length; i++)
                {
                    string line = lines[i];
                    if (line.StartsWith("dir=", StringComparison.Ordinal))
                    {
                        savedDir = line.Substring(4).Trim();
                    }
                    else if (line.StartsWith("session=", StringComparison.Ordinal))
                    {
                        string v = line.Substring(8).Trim();
                        if (v.Length > 0) sessionId = v;
                    }
                    else if (line.StartsWith("started=", StringComparison.Ordinal))
                    {
                        DateTime dt;
                        if (DateTime.TryParse(line.Substring(8).Trim(), out dt)) startedAt = dt;
                    }
                    else if (line.StartsWith("model=", StringComparison.Ordinal))
                    {
                        preferredModel = line.Substring(6).Trim();
                    }
                }
                // Если программа переехала в другую папку, движок не найдёт
                // сессию по старому пути — начинаем разговор с новой сессии.
                if (sessionId != null && savedDir != null
                    && !string.Equals(NormalizeDir(savedDir), NormalizeDir(projectsDir), StringComparison.OrdinalIgnoreCase))
                {
                    Log.Write("SESSION", "Сессия из другой папки отброшена: " + savedDir);
                    sessionId = null;
                }
                startedLabel.Text = "Разговор начат: " + startedAt.ToString("dd.MM.yyyy, HH:mm");
                if (transcript.TextLength == 0) return false;
                statusLabel.Text = sessionId == null
                    ? "Прошлая переписка восстановлена."
                    : "Прошлый разговор восстановлен, можно продолжать.";
                return true;
            }
            catch (Exception ex)
            {
                Log.Write("ERROR", "Не удалось восстановить переписку: " + ex.Message);
                return false;
            }
        }

        private void SaveHistory()
        {
            try
            {
                string dir = Path.GetDirectoryName(historyRtf);
                if (!Directory.Exists(dir)) Directory.CreateDirectory(dir);
                transcript.SaveFile(historyRtf, RichTextBoxStreamType.RichText);
                ModelItem mi = modelBox.SelectedItem as ModelItem;
                string model = mi != null ? KeyOf(mi) : preferredModel;
                StringBuilder sb = new StringBuilder();
                sb.AppendLine("session=" + (sessionId == null ? "" : sessionId));
                sb.AppendLine("started=" + startedAt.ToString("yyyy-MM-dd HH:mm:ss"));
                sb.AppendLine("model=" + (model == null ? "" : model));
                sb.AppendLine("dir=" + projectsDir);
                File.WriteAllText(historyState, sb.ToString(), Encoding.UTF8);
                if (model != null && model.Length > 0) preferredModel = model;
            }
            catch (Exception ex)
            {
                Log.Write("ERROR", "Не удалось сохранить переписку: " + ex.Message);
            }
        }

        private static string NormalizeDir(string dir)
        {
            if (dir == null) return "";
            return dir.TrimEnd('\\', '/');
        }

        private void AppendHeader()
        {
            transcript.SelectionStart = transcript.TextLength;
            transcript.SelectionLength = 0;
            transcript.SelectionFont = headerFont;
            transcript.SelectionColor = Color.FromArgb(0x40, 0x40, 0x40);
            transcript.AppendText("Разговор начат " + startedAt.ToString("dd.MM.yyyy") + " в " + startedAt.ToString("HH:mm") + "\r\n");
            transcript.AppendText("Файлы, созданные агентом, лежат в папке projects.\r\n\r\n");
            transcript.SelectionFont = bodyFont;
            transcript.SelectionColor = Color.Black;
        }

        private void NewChat()
        {
            if (busy)
            {
                statusLabel.Text = "Сейчас идёт ответ. Подождите.";
                return;
            }
            DialogResult r = MessageBox.Show(this,
                "Начать новый разговор? текущая переписка очистится.",
                "Новый разговор", MessageBoxButtons.YesNo, MessageBoxIcon.Question);
            if (r != DialogResult.Yes) return;
            StartChat(false);
            statusLabel.Text = "Новый разговор";
            input.Focus();
        }

        private void AppendBlock(string header, string body, Color headerColor)
        {
            transcript.SelectionStart = transcript.TextLength;
            transcript.SelectionLength = 0;
            transcript.SelectionFont = headerFont;
            transcript.SelectionColor = headerColor;
            transcript.AppendText(header + "\r\n");
            transcript.SelectionFont = bodyFont;
            transcript.SelectionColor = Color.Black;
            transcript.AppendText(body + "\r\n\r\n");
            blocksText = null;
            SaveHistory();
        }

        private void InputKeyDown(object sender, KeyEventArgs e)
        {
            if (e.KeyCode != Keys.Enter) return;
            if (e.Control)
            {
                // Ctrl+Enter — перенос строки, как в обычных чат-программах.
                e.SuppressKeyPress = true;
                e.Handled = true;
                int pos = input.SelectionStart;
                input.SelectedText = Environment.NewLine;
                input.SelectionStart = pos + Environment.NewLine.Length;
                return;
            }
            // Простой Enter и Shift+Enter отправляют сообщение.
            e.SuppressKeyPress = true;
            e.Handled = true;
            Send();
        }

        // Набор текста в любом месте программы уводит фокус в редактор.
        private void FormKeyPress(object sender, KeyPressEventArgs e)
        {
            char c = e.KeyChar;
            Control a = ActiveControl;
            if (a == input) return;
            // В редакторе переписки текст не набирается — уводим его в поле ввода.
            if (a != null && a is TextBox && !((TextBox)a).ReadOnly) return;
            if (modelBox != null && a == modelBox && modelBox.DroppedDown) return;
            if (c == '\b')
            {
                input.Focus();
                if (input.SelectionLength > 0) input.SelectedText = "";
                else if (input.SelectionStart > 0)
                {
                    int pos = input.SelectionStart;
                    input.Text = input.Text.Remove(pos - 1, 1);
                    input.SelectionStart = pos - 1;
                }
                e.Handled = true;
                return;
            }
            if (c == ' ' && a is ButtonBase) return;
            if (c >= ' ' && c != '\x7f')
            {
                input.Focus();
                input.SelectedText = c.ToString();
                e.Handled = true;
            }
        }

        // ---------- озвучка и переходы по сообщениям ----------

        private void Announce(string text)
        {
            if (text == null) return;
            text = text.Trim();
            if (text.Length == 0) return;
            if (text.Length > 8000) text = text.Substring(0, 8000) + " …";
            pendingAnnounce = text;
            announceTimer.Stop();
            announceTimer.Start();
        }

        // Каждое сообщение начинается со строки «Имя, 12:34» и тянется
        // до следующей такой строки. Заголовок «Разговор начат» сюда не входит.
        private List<int[]> MessageRanges()
        {
            string t = transcript.Text;
            if (blocksText == t) return blocks;
            List<int> starts = new List<int>();
            List<string> authors = new List<string>();
            int pos = 0;
            while (pos <= t.Length)
            {
                int end = t.IndexOf("\n", pos, StringComparison.Ordinal);
                if (end < 0) end = t.Length;
                int lineEnd = end;
                if (lineEnd > pos && t[lineEnd - 1] == '\r') lineEnd--;
                string line = t.Substring(pos, lineEnd - pos);
                Match m = Regex.Match(line, @"^(.+?), (\d{1,2}:\d{2})$");
                if (m.Success && pos > 0)
                {
                    starts.Add(pos);
                    string who = m.Groups[1].Value;
                    int dot = who.IndexOf(" · ", StringComparison.Ordinal);
                    if (dot > 0) who = who.Substring(0, dot);
                    authors.Add(who);
                }
                if (end >= t.Length) break;
                pos = end + 1;
            }
            List<int[]> list = new List<int[]>();
            for (int i = 0; i < starts.Count; i++)
            {
                int from = starts[i];
                int to = i + 1 < starts.Count ? starts[i + 1] : t.Length;
                while (to > from && IsBlankChar(t[to - 1])) to--;
                list.Add(new int[] { from, to });
            }
            blocks = list;
            blocksAuthors = authors;
            blocksText = t;
            return list;
        }

        private void SelectBlock(int[] range)
        {
            // Ставим только курсор, без выделения всего сообщения.
            // Выделенный текст диктор тоже читает сам — и тогда вместе
            // с оповещением получается два чтения подряд: второе обрывает
            // первое, и конец сообщения не слышен. Курсор нужен лишь для
            // того, чтобы следующая стрелка знала, от какого сообщения идти.
            transcript.SelectionLength = 0;
            transcript.SelectionStart = range[0];
            transcript.ScrollToCaret();
            Announce(transcript.Text.Substring(range[0], range[1] - range[0]));
        }

        // Номер сообщения, в котором стоит курсор. После выделения блока
        // курсор стоит на его начале, поэтому «текущее» — последнее уже
        // начавшееся сообщение: иначе стрелки залипали на одном блоке.
        private static int BlockAt(List<int[]> list, int caret)
        {
            int idx = 0;
            for (int i = 0; i < list.Count; i++)
                if (list[i][0] <= caret) idx = i;
            return idx;
        }

        private void MoveBetweenBlocks(int dir)
        {
            List<int[]> list = MessageRanges();
            if (list.Count == 0) return;
            int idx = BlockAt(list, transcript.SelectionStart) + dir;
            if (idx < 0) idx = 0;
            if (idx >= list.Count) idx = list.Count - 1;
            SelectBlock(list[idx]);
        }

        private void MoveBetweenSpeakers(int dir)
        {
            List<int[]> list = MessageRanges();
            if (list.Count == 0) return;
            List<int> firsts = new List<int>();
            for (int i = 0; i < list.Count; i++)
            {
                if (i == 0 || !string.Equals(blocksAuthors[i], blocksAuthors[i - 1], StringComparison.Ordinal))
                    firsts.Add(i);
            }
            int cur = BlockAt(list, transcript.SelectionStart);
            int g = 0;
            for (int i = 0; i < firsts.Count; i++)
            {
                if (firsts[i] <= cur) g = i;
            }
            if (dir > 0)
            {
                if (g >= firsts.Count - 1) return;
                g++;
            }
            else
            {
                if (cur > firsts[g]) { /* сначала к первому сообщению этого собеседника */ }
                else if (g > 0) g--;
                else return;
            }
            SelectBlock(list[firsts[g]]);
        }

        private static bool IsWebLink(string url)
        {
            return url.StartsWith("http://", StringComparison.OrdinalIgnoreCase)
                || url.StartsWith("https://", StringComparison.OrdinalIgnoreCase);
        }

        private void OpenLink(string url)
        {
            if (url == null) return;
            url = url.Trim().TrimEnd('.', ',', ';', ':', ')', ']', '}', '»', '"', '\'');
            if (!IsWebLink(url)) return;
            try
            {
                Process.Start(new ProcessStartInfo(url) { UseShellExecute = true });
                statusLabel.Text = "Открываю ссылку: " + url;
            }
            catch (Exception ex)
            {
                Log.Exception("Открыть ссылку", ex);
                statusLabel.Text = "Не удалось открыть ссылку: " + ex.Message;
            }
        }

        private void OpenLinkAtCaret()
        {
            string t = transcript.Text;
            int caret = transcript.SelectionStart;
            if (caret < 0) caret = 0;
            if (caret > t.Length) caret = t.Length;
            int lineStart = caret > 0 ? t.LastIndexOf('\n', caret - 1) + 1 : 0;
            int lineEnd = t.IndexOf('\n', caret);
            if (lineEnd < 0) lineEnd = t.Length;
            Match m = Regex.Match(t.Substring(lineStart, lineEnd - lineStart), @"https?://[^\s<>""']+");
            if (!m.Success)
            {
                List<int[]> list = MessageRanges();
                for (int i = 0; i < list.Count; i++)
                {
                    if (caret >= list[i][0] && caret <= list[i][1])
                    {
                        m = Regex.Match(t.Substring(list[i][0], list[i][1] - list[i][0]), @"https?://[^\s<>""']+");
                        break;
                    }
                }
            }
            if (m.Success) OpenLink(m.Value);
            else statusLabel.Text = "В этом сообщении нет ссылки.";
        }

        [DllImport("user32.dll")]
        private static extern void NotifyWinEvent(int winEvent, IntPtr hwnd, int objectType, int objectId);

        // ---------- hotkeys ----------

        private void FormKeyDown(object sender, KeyEventArgs e)
        {
            if (e.KeyCode == Keys.Escape && busy)
            {
                e.Handled = true;
                e.SuppressKeyPress = true;
                StopAgent();
            }
            else if (e.KeyCode == Keys.F1)
            {
                e.Handled = true;
                e.SuppressKeyPress = true;
                FocusLastMessage();
            }
            else if (e.KeyCode == Keys.F2)
            {
                e.Handled = true;
                e.SuppressKeyPress = true;
                FocusFiles();
            }
            else if (e.KeyCode == Keys.F3)
            {
                e.Handled = true;
                e.SuppressKeyPress = true;
                modelBox.Focus();
            }
            else if (e.Control && e.KeyCode == Keys.E)
            {
                e.Handled = true;
                e.SuppressKeyPress = true;
                input.Focus();
            }
            else if (e.Control && e.KeyCode == Keys.N)
            {
                e.Handled = true;
                e.SuppressKeyPress = true;
                NewChat();
            }
            else if (e.Alt && e.KeyCode == Keys.F)
            {
                e.Handled = true;
                e.SuppressKeyPress = true;
                if (busy)
                {
                    statusLabel.Text = "Сейчас идёт ответ. Дождитесь его, потом прикрепите файл.";
                    return;
                }
                AttachFiles();
            }
        }

        private static bool IsBlankChar(char c)
        {
            return c == '\r' || c == '\n' || c == ' ' || c == '\t';
        }

        // Первый непробельный символ, начиная с from. TextLength, если текста нет.
        private int FirstText(int from)
        {
            string t = transcript.Text;
            if (from < 0) from = 0;
            int i = from;
            while (i < t.Length && IsBlankChar(t[i])) i++;
            return i;
        }

        // Позиция последнего непробельного символа; чтобы курсор не висел
        // на пустых строках после ответа.
        private int LastText()
        {
            string t = transcript.Text;
            int i = t.Length - 1;
            while (i >= 0 && IsBlankChar(t[i])) i--;
            if (i < 0) return 0;
            return i;
        }

        private void FocusLastMessage()
        {
            transcript.Focus();
            transcript.SelectionStart = LastText();
            transcript.SelectionLength = 0;
            transcript.ScrollToCaret();
        }

        private void FocusFiles()
        {
            filesView.Focus();
            if (filesView.Items.Count > 0)
            {
                int last = filesView.Items.Count - 1;
                filesView.Items[last].Selected = true;
                filesView.Items[last].Focused = true;
                filesView.EnsureVisible(last);
            }
        }

        private void TranscriptKeyDown(object sender, KeyEventArgs e)
        {
            if (e.Shift || e.Alt) return;
            if (e.Control && (e.KeyCode == Keys.Up || e.KeyCode == Keys.Down))
            {
                e.Handled = true;
                e.SuppressKeyPress = true;
                MoveBetweenSpeakers(e.KeyCode == Keys.Down ? 1 : -1);
                return;
            }
            if (e.Control && e.KeyCode == Keys.Enter)
            {
                e.Handled = true;
                e.SuppressKeyPress = true;
                OpenLinkAtCaret();
                return;
            }
            if (e.Control) return;
            if (e.KeyCode == Keys.Up || e.KeyCode == Keys.Down)
            {
                e.Handled = true;
                e.SuppressKeyPress = true;
                MoveBetweenBlocks(e.KeyCode == Keys.Down ? 1 : -1);
            }
            else if (e.KeyCode == Keys.Home)
            {
                e.Handled = true;
                e.SuppressKeyPress = true;
                transcript.SelectionStart = FirstText(0);
                transcript.SelectionLength = 0;
                transcript.ScrollToCaret();
            }
            else if (e.KeyCode == Keys.End)
            {
                e.Handled = true;
                e.SuppressKeyPress = true;
                transcript.SelectionStart = LastText();
                transcript.SelectionLength = 0;
                transcript.ScrollToCaret();
            }
        }

        private void Send()
        {
            if (busy)
            {
                statusLabel.Text = "Агент ещё отвечает. Подождите.";
                return;
            }
            string text = input.Text.Trim();
            if (text.Length == 0 && pending.Count == 0)
            {
                statusLabel.Text = "Введите сообщение или прикрепите файл.";
                return;
            }

            string model = "";
            string gguf = null;
            ModelItem mi = modelBox.SelectedItem as ModelItem;
            if (mi != null)
            {
                model = mi.Id;
                if (mi.Offline) gguf = mi.Gguf;
            }

            if (model.StartsWith("offline/", StringComparison.OrdinalIgnoreCase) && (gguf == null || gguf.Length == 0))
            {
                statusLabel.Text = "Офлайн-модель не выбрана.";
                MessageBox.Show(this,
                    "В списке выбрана офлайн-модель, но её файл не найден.\r\n"
                    + "Нажмите F3, выберите строку «Офлайн — имя файла» или добавьте файл кнопкой «Добавить модель…».",
                    "Slonobass agent", MessageBoxButtons.OK, MessageBoxIcon.Information);
                input.Focus();
                return;
            }

            if (model.StartsWith("deepseek/", StringComparison.OrdinalIgnoreCase) && !Profile.HasKey)
            {
                statusLabel.Text = "Для модели из «Мой профиль» нужен ключ DeepSeek.";
                MessageBox.Show(this,
                    "Выбрана модель из раздела «Мой профиль», но ключ DeepSeek ещё не подключён.\r\n"
                    + "Нажмите кнопку «Мой профиль…» и вставьте свой ключ, либо выберите бесплатную модель.",
                    "Slonobass agent", MessageBoxButtons.OK, MessageBoxIcon.Information);
                return;
            }

            List<FileItem> files = new List<FileItem>(pending);
            pending.Clear();
            UpdatePendingLabel();

            StringBuilder logNames = new StringBuilder();
            for (int i = 0; i < files.Count; i++)
            {
                if (i > 0) logNames.Append("; ");
                logNames.Append(files[i].Path);
            }
            Log.Write("REQUEST", "Модель: " + (model.Length > 0 ? model : "(по умолчанию)")
                + "; сессия: " + (sessionId == null ? "(новая)" : sessionId)
                + "; файлов: " + files.Count.ToString()
                + (files.Count > 0 ? " (" + logNames.ToString() + ")" : "")
                + (gguf == null ? "" : "; офлайн-файл: " + gguf)
                + "; сообщение: " + (text.Length == 0 ? "(без текста)" : text.Replace("\r\n", "\\n").Replace("\n", "\\n")));

            string time = DateTime.Now.ToString("HH:mm");
            string shownText = text.Length == 0 ? "(без текста)" : text;
            AppendBlock(userName + ", " + time, shownText, Color.FromArgb(0x1A, 0x5F, 0x1A));
            if (files.Count > 0)
            {
                StringBuilder sb = new StringBuilder();
                sb.Append("Прикреплено: ");
                for (int i = 0; i < files.Count; i++)
                {
                    if (i > 0) sb.Append(", ");
                    sb.Append(files[i].Name);
                }
                AppendBlock("", sb.ToString(), Color.Black);
            }
            transcript.SelectionStart = transcript.TextLength;
            transcript.SelectionLength = 0;
            transcript.ScrollToCaret();
            Sounds.Outgoing();

            if (gguf != null)
            {
                int ctx = ContextFor(gguf);
                WriteOfflineConfig(ctx);
                Log.Write("OFFLINE", "Модель " + Path.GetFileName(gguf) + ": контекст " + ctx.ToString() + " токенов.");
            }

            input.Text = "";
            SetBusy(true);
            statusLabel.Text = "Агент отвечает… 0 с";
            elapsed = 0;
            tick.Start();

            Dictionary<string, string> before = TakeSnapshot();
            string question = text;
            if (question.Length == 0)
            {
                question = files.Count == 1
                    ? "Посмотри приложенный файл."
                    : "Посмотри приложенные файлы.";
            }
            Thread t = new Thread(delegate() { RunAgentPrepared(question, model, files, before, gguf); });
            t.IsBackground = true;
            t.Start();
        }

        private void RunAgentPrepared(string question, string model, List<FileItem> files,
            Dictionary<string, string> before, string gguf)
        {
            if (gguf == null)
            {
                // Обычная модель: локальный сервер больше не нужен, освобождаем память.
                StopOffline();
            }
            else
            {
                offlineError = "";
                if (!EnsureOffline(gguf))
                {
                    string err = offlineError.Length > 0
                        ? offlineError
                        : "Офлайн-модель не запустилась.";
                    Log.Write("OFFLINE-ERROR", err);
                    string shown = "offline/" + Path.GetFileNameWithoutExtension(gguf);
                    try
                    {
                        BeginInvoke(new Action(delegate()
                        {
                            Finish("", err, -1, new List<FileItem>(), shown, null);
                        }));
                    }
                    catch
                    {
                    }
                    return;
                }
            }
            RunAgent(question, model, files, before);
        }

        private void RunAgent(string question, string model, List<FileItem> files, Dictionary<string, string> before)
        {
            stopRequested = false;
            StringBuilder sb = new StringBuilder();
            StringBuilder eb = new StringBuilder();
            string localSid = null;
            int exit = -1;
            List<string> tail = new List<string>();
            int lineCount = 0;
            bool useSession = sessionId != null && sessionId.Length > 0;

            for (int attempt = 0; attempt < 2; attempt++)
            {
                sb.Length = 0;
                eb.Length = 0;
                tail.Clear();
                lineCount = 0;
                localSid = null;
                exit = -1;

                try
                {
                    ProcessStartInfo psi = new ProcessStartInfo(exePath);
                    psi.Arguments = BuildArgs(question, model, files, useSession);
                    psi.WorkingDirectory = projectsDir;
                    psi.UseShellExecute = false;
                    psi.CreateNoWindow = true;
                    psi.RedirectStandardOutput = true;
                    psi.RedirectStandardError = true;
                    psi.StandardOutputEncoding = Encoding.UTF8;
                    psi.StandardErrorEncoding = Encoding.UTF8;
                    Profile.Apply(psi);
                    Service.Apply(psi);

                    Log.Write("RUN", "opencode " + psi.Arguments.Replace("\r\n", "\\n").Replace("\n", "\\n")
                        + " [профиль: " + (Profile.HasKey ? "свой ключ" : "бесплатные")
                        + (Service.HasProfile ? "; сервис: " + Service.Label : "") + "]");

                    using (Process p = new Process())
                    {
                        p.StartInfo = psi;
                        p.ErrorDataReceived += delegate(object s2, DataReceivedEventArgs e)
                        {
                            if (e.Data != null)
                            {
                                lock (eb) { eb.AppendLine(e.Data); }
                            }
                        };
                        p.Start();
                        activeProc = p;
                        p.BeginErrorReadLine();

                        string line;
                        while ((line = p.StandardOutput.ReadLine()) != null)
                        {
                            lineCount++;
                            tail.Add(line);
                            if (tail.Count > 200) tail.RemoveAt(0);
                            if (line.Length < 5) continue;
                            if (localSid == null)
                            {
                                string sid = JsonValue(line, "sessionID");
                                if (sid != null && sid.Length > 0) localSid = sid;
                            }
                            if (line.StartsWith("{\"type\":\"text\"", StringComparison.Ordinal))
                            {
                                string t = JsonValue(line, "text");
                                if (t != null && t.Length > 0)
                                {
                                    if (sb.Length > 0) sb.Append("\r\n\r\n");
                                    sb.Append(t);
                                }
                            }
                            else if (line.StartsWith("{\"type\":\"error\"", StringComparison.Ordinal))
                            {
                                string em = JsonValue(line, "message");
                                if (em != null && em.Length > 0)
                                {
                                    lock (eb)
                                    {
                                        eb.AppendLine("OpenCode: " + em);
                                        if (em.IndexOf("Authentication Fails", StringComparison.OrdinalIgnoreCase) >= 0
                                            || em.IndexOf("invalid api key", StringComparison.OrdinalIgnoreCase) >= 0
                                            || em.IndexOf("status\":401", StringComparison.Ordinal) >= 0)
                                        {
                                            eb.AppendLine("Похоже, ключ DeepSeek неверный или истёк. Откройте «Мой профиль…» и проверьте ключ.");
                                        }
                                        else if (em.IndexOf("insufficient", StringComparison.OrdinalIgnoreCase) >= 0
                                            || em.IndexOf("balance", StringComparison.OrdinalIgnoreCase) >= 0)
                                        {
                                            eb.AppendLine("Похоже, на балансе аккаунта DeepSeek закончились средства. Пополните баланс на platform.deepseek.com или выберите бесплатную модель.");
                                        }
                                    }
                                }
                            }
                        }
                        p.WaitForExit();
                        exit = p.ExitCode;
                    }
                }
                catch (Exception ex)
                {
                    lock (eb) { eb.AppendLine(ex.Message); }
                    Log.Exception("Запуск движка", ex);
                }
                finally
                {
                    activeProc = null;
                }

                string attemptErrors;
                lock (eb) { attemptErrors = eb.ToString(); }
                if (stopRequested) break;
                if (useSession && attemptErrors.IndexOf("Location not found", StringComparison.OrdinalIgnoreCase) >= 0)
                {
                    // Сессия движка привязана к папке projects. Если программа
                    // переехала в другую папку, движок её не находит — повторяем
                    // запрос с новой сессией.
                    Log.Write("SESSION", "Движок не нашёл папку прошлой сессии — повторяю с новой сессией.");
                    sessionId = null;
                    useSession = false;
                    continue;
                }
                break;
            }

            string answer = sb.ToString();
            string errors = "";
            lock (eb) { errors = eb.ToString(); }

            List<FileItem> produced = DiffSnapshot(before);

            Log.Write("RESULT", "Код выхода: " + exit.ToString()
                + "; строк вывода: " + lineCount.ToString()
                + "; ответ: " + answer.Length.ToString() + " симв."
                + "; новых файлов: " + produced.Count.ToString()
                + "; сессия: " + (localSid == null ? "(нет)" : localSid));
            if (errors.Length > 0) Log.Write("STDERR", errors.Trim());
            if (exit != 0 || answer.Length == 0)
            {
                StringBuilder rawTail = new StringBuilder();
                for (int i = 0; i < tail.Count; i++) rawTail.AppendLine(tail[i]);
                Log.Write("STDOUT-TAIL", rawTail.ToString());
            }

            try
            {
                BeginInvoke(new Action(delegate { Finish(answer, errors, exit, produced, model, localSid); }));
            }
            catch
            {
            }
        }

        private void Finish(string answer, string errors, int exit, List<FileItem> produced, string model, string sid)
        {
            tick.Stop();
            loadingOffline = false;
            bool wasStopped = stopRequested;
            stopRequested = false;
            SetBusy(false);
            if (sessionId == null && sid != null) sessionId = sid;

            string time = DateTime.Now.ToString("HH:mm");
            string answerText = answer.Trim();
            if (answerText.Length == 0)
            {
                answerText = wasStopped ? "(ответ остановлен)" : "(ответа нет)";
                if (exit != 0 && !wasStopped)
                {
                    answerText = "Не получилось получить ответ.";
                }
                if (errors.Trim().Length > 0)
                {
                    answerText += "\r\nПодробности: " + Shorten(errors.Trim(), 1200);
                }
            }
            else if (wasStopped)
            {
                answerText += "\r\n\r\n(остановлено вручную)";
            }
            lastAnswer = answerText;

            int start = transcript.TextLength;
            string who = "Slonobass agent";
            if (model.Length > 0)
            {
                int slash = model.IndexOf('/');
                who += " · " + (slash >= 0 ? model.Substring(slash + 1) : model);
            }
            AppendBlock(who + ", " + time, answerText, Color.FromArgb(0x1F, 0x55, 0x9E));

            if (produced.Count > 0)
            {
                StringBuilder names = new StringBuilder();
                for (int i = 0; i < produced.Count; i++)
                {
                    if (i > 0) names.Append(", ");
                    names.Append(produced[i].Name);
                    AddFileRow(produced[i]);
                }
                AppendBlock("Файлы от агента, " + time,
                    names.ToString() + "\r\nСохранить: выбрать файл в списке внизу и нажать Enter.",
                    Color.FromArgb(0x7A, 0x4A, 0x00));
                statusLabel.Text = "Готово. Новых файлов: " + produced.Count.ToString() + ". Они внизу, в списке файлов.";
            }
            else
            {
                statusLabel.Text = "Готово.";
            }
            if (wasStopped)
            {
                statusLabel.Text = "Остановлено. Что успело прийти — в переписке.";
            }

            // Курсор — на начало ответа: отсюда стрелки продолжают работу,
            // а сам текст читает оповещение целиком (выделение не делаем,
            // иначе диктор читает его вторым разом и обрывает).
            string full = transcript.Text;
            int answerStart = FirstText(start);
            transcript.SelectionLength = 0;
            transcript.SelectionStart = answerStart;
            transcript.ScrollToCaret();
            transcript.Focus();
            Sounds.Incoming();
            Announce((wasStopped ? "Ответ остановлен. " : "Новый ответ. ") + answerText);
        }

        private void SetBusy(bool value)
        {
            busy = value;
            detachBtn.Enabled = !value && pending.Count > 0;
            newChatBtn.Enabled = !value;
            if (stopBtn != null) stopBtn.Enabled = value;
            // Выбор модели не отключаем: отключённый элемент экранный диктор
            // пропускает, и кажется, что список моделей исчез.
        }

        private void StopAgent()
        {
            if (!busy)
            {
                statusLabel.Text = "Сейчас ничего не происходит.";
                return;
            }
            stopRequested = true;
            statusLabel.Text = "Останавливаю ответ…";
            Process p = activeProc;
            if (p == null) return;
            try
            {
                // Движок может запускать дочерние процессы — гасим всё дерево.
                ProcessStartInfo kill = new ProcessStartInfo("taskkill", "/PID " + p.Id.ToString() + " /T /F");
                kill.UseShellExecute = false;
                kill.CreateNoWindow = true;
                Process.Start(kill);
            }
            catch (Exception ex)
            {
                Log.Exception("Остановка ответа", ex);
            }
            try
            {
                if (!p.HasExited) p.Kill();
            }
            catch
            {
            }
        }

        private void CopyLastAnswer()
        {
            if (lastAnswer.Length == 0)
            {
                statusLabel.Text = "Копировать нечего: ответов пока нет.";
                return;
            }
            try
            {
                Clipboard.SetText(lastAnswer);
                statusLabel.Text = "Последний ответ скопирован в буфер обмена.";
            }
            catch (Exception ex)
            {
                Log.Exception("Копирование ответа", ex);
                statusLabel.Text = "Не удалось скопировать: " + ex.Message;
            }
        }

        // ---------- attachments ----------

        private void AttachFiles()
        {
            using (OpenFileDialog dlg = new OpenFileDialog())
            {
                dlg.Title = "Прикрепить файл";
                dlg.Multiselect = true;
                dlg.CheckFileExists = true;
                if (dlg.ShowDialog(this) != DialogResult.OK) return;
                for (int i = 0; i < dlg.FileNames.Length; i++)
                {
                    string f = dlg.FileNames[i];
                    FileItem item = new FileItem();
                    item.Path = f;
                    item.Name = Path.GetFileName(f);
                    try { item.Size = new FileInfo(f).Length; } catch { item.Size = 0; }
                    item.Modified = DateTime.Now;
                    pending.Add(item);
                }
                UpdatePendingLabel();
                statusLabel.Text = "Прикреплено: " + pending.Count.ToString() + " " + FilesWord(pending.Count)
                    + ". Уйдёт вместе с сообщением.";
                input.Focus();
            }
        }

        private void ClearPending()
        {
            pending.Clear();
            UpdatePendingLabel();
            statusLabel.Text = "Прикреплённые файлы сняты";
        }

        private void UpdatePendingLabel()
        {
            if (pending.Count == 0)
            {
                attachedLabel.Text = "Файлы к сообщению: нет";
                if (detachBtn != null) detachBtn.Enabled = !busy;
                return;
            }
            StringBuilder sb = new StringBuilder();
            sb.Append("Прикреплено: ");
            sb.Append(pending.Count.ToString());
            sb.Append(' ');
            sb.Append(FilesWord(pending.Count));
            sb.Append(" — ");
            for (int i = 0; i < pending.Count; i++)
            {
                if (i > 0) sb.Append(", ");
                sb.Append(pending[i].Name);
                sb.Append(" (");
                sb.Append(SizeText(pending[i].Size));
                sb.Append(")");
            }
            attachedLabel.Text = sb.ToString();
            if (detachBtn != null) detachBtn.Enabled = !busy;
        }

        private static string FilesWord(int n)
        {
            int m10 = n % 10;
            int m100 = n % 100;
            if (m10 == 1 && m100 != 11) return "файл";
            if (m10 >= 2 && m10 <= 4 && (m100 < 12 || m100 > 14)) return "файла";
            return "файлов";
        }

        // ---------- produced files ----------

        private Dictionary<string, string> TakeSnapshot()
        {
            Dictionary<string, string> map = new Dictionary<string, string>();
            try
            {
                string[] all = Directory.GetFiles(projectsDir, "*", SearchOption.AllDirectories);
                for (int i = 0; i < all.Length; i++)
                {
                    if (IsHiddenPath(all[i])) continue;
                    try
                    {
                        FileInfo fi = new FileInfo(all[i]);
                        map[all[i]] = fi.Length.ToString() + "|" + fi.LastWriteTimeUtc.Ticks.ToString();
                    }
                    catch
                    {
                    }
                }
            }
            catch
            {
            }
            return map;
        }

        private bool IsHiddenPath(string path)
        {
            string rel = path;
            if (rel.StartsWith(projectsDir, StringComparison.OrdinalIgnoreCase))
            {
                rel = rel.Substring(projectsDir.Length);
            }
            string[] parts = rel.Split('\\', '/');
            for (int i = 0; i < parts.Length - 1; i++)
            {
                string p = parts[i];
                if (p.Length == 0) continue;
                if (p.StartsWith(".", StringComparison.Ordinal)) return true;
                if (string.Equals(p, "node_modules", StringComparison.OrdinalIgnoreCase)) return true;
            }
            string name = Path.GetFileName(path);
            if (string.Equals(name, "opencode.json", StringComparison.OrdinalIgnoreCase)) return true;
            if (string.Equals(name, "opencode.jsonc", StringComparison.OrdinalIgnoreCase)) return true;
            return false;
        }

        private List<FileItem> DiffSnapshot(Dictionary<string, string> before)
        {
            List<FileItem> list = new List<FileItem>();
            Dictionary<string, string> after = TakeSnapshot();
            foreach (KeyValuePair<string, string> kv in after)
            {
                string old;
                if (before.TryGetValue(kv.Key, out old) && old == kv.Value) continue;
                try
                {
                    FileInfo fi = new FileInfo(kv.Key);
                    FileItem item = new FileItem();
                    item.Path = kv.Key;
                    item.Name = Path.GetFileName(kv.Key);
                    item.Size = fi.Length;
                    item.Modified = fi.LastWriteTime;
                    list.Add(item);
                }
                catch
                {
                }
            }
            list.Sort(delegate(FileItem a, FileItem b) { return a.Modified.CompareTo(b.Modified); });
            return list;
        }

        private void AddFileRow(FileItem item)
        {
            for (int i = 0; i < filesView.Items.Count; i++)
            {
                FileItem ex = filesView.Items[i].Tag as FileItem;
                if (ex != null && string.Equals(ex.Path, item.Path, StringComparison.OrdinalIgnoreCase))
                {
                    ex.Size = item.Size;
                    ex.Modified = item.Modified;
                    filesView.Items[i].SubItems[1].Text = item.Modified.ToString("HH:mm");
                    filesView.Items[i].SubItems[2].Text = SizeText(item.Size);
                    return;
                }
            }
            ListViewItem row = new ListViewItem(item.Name);
            row.Tag = item;
            row.SubItems.Add(item.Modified.ToString("HH:mm"));
            row.SubItems.Add(SizeText(item.Size));
            filesView.Items.Add(row);
            row.Selected = true;
        }

        private void FilesViewKeyDown(object sender, KeyEventArgs e)
        {
            if (e.KeyCode == Keys.Enter)
            {
                e.SuppressKeyPress = true;
                SaveSelected();
            }
        }

        private void SaveSelected()
        {
            FileItem item = SelectedFile();
            if (item == null)
            {
                statusLabel.Text = "Сначала выберите файл в списке.";
                return;
            }
            try
            {
                string dest = UniquePath(downloadsDir, item.Name);
                File.Copy(item.Path, dest, false);
                Log.Write("SAVE", item.Path + " -> " + dest);
                statusLabel.Text = "Сохранено в Загрузки: " + Path.GetFileName(dest);
                Sounds.Saved();
            }
            catch (Exception ex)
            {
                Log.Exception("Сохранить " + item.Path, ex);
                statusLabel.Text = "Не удалось сохранить: " + ex.Message;
            }
        }

        private void OpenSelected()
        {
            FileItem item = SelectedFile();
            if (item == null)
            {
                statusLabel.Text = "Сначала выберите файл в списке.";
                return;
            }
            try
            {
                Process.Start(item.Path);
            }
            catch (Exception ex)
            {
                Log.Exception("Открыть файл " + item.Path, ex);
                statusLabel.Text = "Не удалось открыть: " + ex.Message;
            }
        }

        private void OpenLogFolder()
        {
            try
            {
                if (Log.Folder == null)
                {
                    statusLabel.Text = "Папка журнала недоступна.";
                    return;
                }
                Process.Start("explorer.exe", "\"" + Log.Folder + "\"");
                statusLabel.Text = "Открыта папка журнала: " + Log.Folder;
            }
            catch (Exception ex)
            {
                Log.Exception("Открыть журнал", ex);
                statusLabel.Text = "Не удалось открыть журнал: " + ex.Message;
            }
        }

        private void OpenProfile()
        {
            using (ProfileForm f = new ProfileForm())
            {
                DialogResult r = f.ShowDialog(this);
                if (r != DialogResult.OK) return;
                if (Profile.HasKey)
                {
                    statusLabel.Text = "Мой профиль DeepSeek подключён: " + Profile.Hint;
                    Log.Write("PROFILE", "Ключ DeepSeek сохранён (" + Profile.Hint + ")");
                }
                else
                {
                    statusLabel.Text = "Мой профиль DeepSeek отключён. Работают бесплатные модели.";
                    Log.Write("PROFILE", "Ключ DeepSeek удалён");
                }
                LoadModels();
            }
        }

        private void OpenOtherService()
        {
            using (ServiceForm f = new ServiceForm())
            {
                DialogResult r = f.ShowDialog(this);
                if (r != DialogResult.OK) return;
                WriteOfflineConfig();
                if (Service.HasProfile)
                {
                    statusLabel.Text = Service.Label + " подключён: " + Service.Hint
                        + ". Модели в списке моделей.";
                    Log.Write("SERVICE", Service.Label + " сохранён (" + Service.Hint
                        + "), моделей: " + Service.Models.Length.ToString());
                }
                else
                {
                    statusLabel.Text = "Другой сервис отключён.";
                    Log.Write("SERVICE", "Другой сервис отключён");
                }
                LoadModels();
            }
        }

        private FileItem SelectedFile()
        {
            if (filesView.SelectedItems.Count == 0) return null;
            return filesView.SelectedItems[0].Tag as FileItem;
        }

        private static string UniquePath(string dir, string name)
        {
            string full = Path.Combine(dir, name);
            if (!File.Exists(full)) return full;
            string baseName = Path.GetFileNameWithoutExtension(name);
            string ext = Path.GetExtension(name);
            for (int i = 2; i < 1000; i++)
            {
                full = Path.Combine(dir, baseName + " (" + i.ToString() + ")" + ext);
                if (!File.Exists(full)) return full;
            }
            return Path.Combine(dir, baseName + " (" + DateTime.Now.Ticks.ToString() + ")" + ext);
        }

        // ---------- models ----------

        private void LoadModels()
        {
            Thread t = new Thread(delegate()
            {
                List<string> found = new List<string>();
                try
                {
                    ProcessStartInfo psi = new ProcessStartInfo(exePath);
                    psi.Arguments = "models --standalone";
                    psi.WorkingDirectory = projectsDir;
                    psi.UseShellExecute = false;
                    psi.CreateNoWindow = true;
                    psi.RedirectStandardOutput = true;
                    psi.RedirectStandardError = true;
                    psi.StandardOutputEncoding = Encoding.UTF8;
                    psi.StandardErrorEncoding = Encoding.UTF8;
                    Profile.Apply(psi);
                    Service.Apply(psi);
                    using (Process p = Process.Start(psi))
                    {
                        string outp = p.StandardOutput.ReadToEnd();
                        string errp = p.StandardError.ReadToEnd();
                        p.WaitForExit();
                        if (errp.Trim().Length > 0) Log.Write("MODELS-STDERR", errp.Trim());
                        string[] lines = outp.Split('\n');
                        for (int i = 0; i < lines.Length; i++)
                        {
                            string s = lines[i].Trim();
                            if (s.Length == 0) continue;
                            if (s.IndexOf('/') < 0) continue;
                            if (s.IndexOf(' ') >= 0) continue;
                            if (s.IndexOf("embed", StringComparison.OrdinalIgnoreCase) >= 0) continue;
                            if (!found.Contains(s)) found.Add(s);
                        }
                    }
                }
                catch (Exception ex)
                {
                    Log.Exception("Список моделей", ex);
                }
                Log.Write("MODELS", "Найдено моделей: " + found.Count.ToString()
                    + "; профиль DeepSeek: " + (Profile.HasKey ? "подключён " + Profile.Hint : "нет")
                    + "; другой сервис: " + (Service.HasProfile ? Service.Label + " " + Service.Hint : "нет"));
                try
                {
                    BeginInvoke(new Action(delegate { FillModels(found); }));
                }
                catch
                {
                }
            });
            t.IsBackground = true;
            t.Start();
        }

        private static string KeyOf(ModelItem m)
        {
            if (m == null) return "";
            if (m.Offline && m.Gguf != null && m.Gguf.Length > 0) return "offline:" + m.Gguf;
            return m.Id == null ? "" : m.Id;
        }

        private void FillModels(List<string> found)
        {
            if (found == null) found = new List<string>();
            if (found.Count == 0)
            {
                for (int i = 0; i < FallbackModels.Length; i++) found.Add(FallbackModels[i]);
            }
            lastFound = new List<string>(found);

            string keep = "";
            ModelItem cur = modelBox.SelectedItem as ModelItem;
            if (cur != null) keep = KeyOf(cur);
            if (keep.Length == 0) keep = preferredModel;

            List<string> mine = new List<string>();
            List<string> others = new List<string>();
            List<string> free = new List<string>();
            for (int i = 0; i < found.Count; i++)
            {
                // Провайдер offline движок показывает в своём списке, но пункты
                // для офлайн-файлов строим сами: у движка это одна модель без файла.
                if (found[i].StartsWith("offline/", StringComparison.OrdinalIgnoreCase)) continue;
                if (found[i].StartsWith("deepseek/", StringComparison.OrdinalIgnoreCase)) mine.Add(found[i]);
                else if (found[i].StartsWith("other/", StringComparison.OrdinalIgnoreCase)) others.Add(found[i]);
                else free.Add(found[i]);
            }
            if (Profile.HasKey && mine.Count == 0)
            {
                for (int i = 0; i < ApiModels.Length; i++) mine.Add(ApiModels[i]);
            }
            if (!Profile.HasKey) mine.Clear();

            List<string> ggufs = LoadOfflinePaths();

            modelBox.Items.Clear();
            for (int i = 0; i < ggufs.Count; i++)
            {
                ModelItem oi = new ModelItem("offline/local",
                    "Офлайн — " + Path.GetFileName(ggufs[i]), false);
                oi.Offline = true;
                oi.Gguf = ggufs[i];
                modelBox.Items.Add(oi);
            }
            for (int i = 0; i < mine.Count; i++)
            {
                modelBox.Items.Add(new ModelItem(mine[i], "Мой профиль — " + ShortName(mine[i]), true));
            }
            string serviceLabel = Service.HasProfile ? Service.Label : "Другой сервис";
            for (int i = 0; i < others.Count; i++)
            {
                modelBox.Items.Add(new ModelItem(others[i], serviceLabel + " — " + ShortName(others[i]), true));
            }
            for (int i = 0; i < free.Count; i++) modelBox.Items.Add(new ModelItem(free[i]));

            int index = 0;
            bool matched = false;
            if (keep.Length > 0)
            {
                for (int i = 0; i < modelBox.Items.Count; i++)
                {
                    ModelItem m = modelBox.Items[i] as ModelItem;
                    if (m != null && string.Equals(KeyOf(m), keep, StringComparison.Ordinal)) { index = i; matched = true; break; }
                }
            }
            if (!matched)
            {
                index = -1;
                for (int i = 0; i < modelBox.Items.Count; i++)
                {
                    ModelItem m = modelBox.Items[i] as ModelItem;
                    if (m != null && string.Equals(m.Id, "opencode/deepseek-v4.1-flash-free", StringComparison.Ordinal)) { index = i; break; }
                }
                if (index < 0)
                {
                    for (int i = 0; i < modelBox.Items.Count; i++)
                    {
                        ModelItem m = modelBox.Items[i] as ModelItem;
                        if (m != null && !m.Mine && !m.Offline) { index = i; break; }
                    }
                }
                if (index < 0) index = 0;
            }
            if (modelBox.Items.Count > 0) modelBox.SelectedIndex = index;

            StringBuilder desc = new StringBuilder();
            if (ggufs.Count > 0)
                desc.Append("Сверху офлайн-модели (" + ggufs.Count.ToString() + ") — файлы .gguf с этого компьютера. ");
            if (Profile.HasKey)
                desc.Append("Раздел «Мой профиль» — модели вашего аккаунта DeepSeek (" + mine.Count.ToString() + "). ");
            if (others.Count > 0)
                desc.Append("Раздел «" + serviceLabel + "» — модели другого сервиса (" + others.Count.ToString() + "). ");
            desc.Append("Ниже бесплатные модели. Кнопка «Добавить модель» добавляет файл .gguf.");
            modelBox.AccessibleDescription = desc.ToString();
        }

        // ---------- офлайн-модели (.gguf через llama.cpp) ----------

        private List<string> LoadOfflinePaths()
        {
            List<string> res = new List<string>();
            try
            {
                if (!File.Exists(modelsFile)) return res;
                string[] lines = File.ReadAllLines(modelsFile, Encoding.UTF8);
                for (int i = 0; i < lines.Length; i++)
                {
                    string s = lines[i].Trim();
                    if (s.Length == 0) continue;
                    if (!File.Exists(s))
                    {
                        Log.Write("OFFLINE", "Пропущен отсутствующий файл модели: " + s);
                        continue;
                    }
                    bool dup = false;
                    for (int j = 0; j < res.Count; j++)
                    {
                        if (string.Equals(res[j], s, StringComparison.OrdinalIgnoreCase)) { dup = true; break; }
                    }
                    if (!dup) res.Add(s);
                }
            }
            catch (Exception ex)
            {
                Log.Exception("Список офлайн-моделей", ex);
            }
            return res;
        }

        private void SaveOfflinePaths(List<string> paths)
        {
            try
            {
                string dir = Path.GetDirectoryName(modelsFile);
                if (!Directory.Exists(dir)) Directory.CreateDirectory(dir);
                File.WriteAllLines(modelsFile, paths.ToArray(), new UTF8Encoding(false));
            }
            catch (Exception ex)
            {
                Log.Exception("Сохранение офлайн-моделей", ex);
            }
        }

        private void AddOfflineModel()
        {
            using (OpenFileDialog dlg = new OpenFileDialog())
            {
                dlg.Title = "Добавить офлайн-модель";
                dlg.Filter = "Модели GGUF (*.gguf)|*.gguf|Все файлы (*.*)|*.*";
                dlg.Multiselect = true;
                dlg.CheckFileExists = true;
                if (dlg.ShowDialog(this) != DialogResult.OK) return;

                List<string> paths = LoadOfflinePaths();
                int added = 0;
                string last = "";
                for (int i = 0; i < dlg.FileNames.Length; i++)
                {
                    string p = dlg.FileNames[i];
                    bool dup = false;
                    for (int j = 0; j < paths.Count; j++)
                    {
                        if (string.Equals(paths[j], p, StringComparison.OrdinalIgnoreCase)) { dup = true; break; }
                    }
                    if (dup) continue;
                    paths.Add(p);
                    added++;
                    last = p;
                }
                if (added > 0) SaveOfflinePaths(paths);
                Log.Write("OFFLINE", "Добавлено моделей: " + added.ToString()
                    + "; всего в списке: " + paths.Count.ToString());

                if (added > 0)
                {
                    preferredModel = "offline:" + last;
                    modelBox.SelectedIndex = -1;
                }
                FillModels(lastFound);
                if (added > 0) SaveHistory();

                statusLabel.Text = added > 0
                    ? "Добавлено офлайн-моделей: " + added.ToString() + ". Выбрана: " + Path.GetFileName(last)
                    : "Эта модель уже есть в списке.";
                input.Focus();
            }
        }

        private static readonly Dictionary<string, int> ctxCache = new Dictionary<string, int>();

        // Сколько токенов контекста дать модели: берём из её метаданных,
        // ограничиваем обученным контекстом и свободной памятью.
        private static int ContextFor(string gguf)
        {
            lock (ctxCache)
            {
                int known;
                if (ctxCache.TryGetValue(gguf, out known)) return known;
            }
            int ctx = 8192;
            int train;
            long kvPerToken;
            if (Gguf.TryRead(gguf, out train, out kvPerToken))
            {
                long fileSize = 0;
                try { fileSize = new FileInfo(gguf).Length; } catch { }
                long ram = Gguf.TotalRamBytes();
                long budget = ram / 2 - fileSize;
                if (budget < 512L * 1024 * 1024) budget = 512L * 1024 * 1024;
                long byRam = kvPerToken > 0 ? budget / kvPerToken : 32768;
                int[] steps = new int[] { 2048, 4096, 8192, 16384, 32768, 65536, 131072 };
                ctx = 2048;
                for (int i = 0; i < steps.Length; i++)
                {
                    if (steps[i] <= train && steps[i] <= byRam) ctx = steps[i];
                }
                Log.Write("OFFLINE", "Метаданные " + Path.GetFileName(gguf)
                    + ": обученный контекст " + train.ToString()
                    + ", кэш " + (kvPerToken / 1024).ToString() + " КБ на 1000 токенов"
                    + ", оперативной памяти " + (ram / (1024L * 1024L)).ToString() + " МБ"
                    + ", выбран контекст " + ctx.ToString());
            }
            else
            {
                Log.Write("OFFLINE", "Метаданные GGUF прочитать не удалось — беру осторожные 8192 токена: " + gguf);
            }
            lock (ctxCache) { ctxCache[gguf] = ctx; }
            return ctx;
        }

        private void WriteOfflineConfig(int ctx = 8192)
        {
            int limitCtx = Math.Max(1024, ctx - 1024);
            int output = Math.Min(4096, Math.Max(1024, limitCtx / 2));
            try
            {
                string path = Path.Combine(projectsDir, "opencode.json");
                string url = "http://127.0.0.1:" + OfflinePort.ToString() + "/v1";
                StringBuilder sb = new StringBuilder();
                sb.AppendLine("{");
                sb.AppendLine("  \"$schema\": \"https://opencode.ai/config.json\",");
                sb.AppendLine("  \"model\": \"opencode/deepseek-v4.1-flash-free\",");
                // В неинтерактивном запуске движок сам отклоняет всё, что требует
                // подтверждения («Cancelled a request for input this run cannot
                // answer»). Поэтому поиск и загрузка страниц разрешены сразу:
                // иначе веб-поиск молча отменяется, а модель отвечает «не нашёл».
                sb.AppendLine("  \"permission\": {");
                sb.AppendLine("    \"question\": \"deny\",");
                sb.AppendLine("    \"websearch\": \"allow\",");
                sb.AppendLine("    \"webfetch\": \"allow\"");
                sb.AppendLine("  },");
                sb.AppendLine("  \"provider\": {");
                sb.AppendLine("    \"offline\": {");
                sb.AppendLine("      \"npm\": \"@ai-sdk/openai-compatible\",");
                sb.AppendLine("      \"name\": \"Офлайн\",");
                sb.AppendLine("      \"api\": \"" + url + "\",");
                sb.AppendLine("      \"options\": { \"baseURL\": \"" + url + "\", \"apiKey\": \"local\" },");
                sb.AppendLine("      \"models\": {");
                sb.AppendLine("        \"local\": {");
                sb.AppendLine("          \"id\": \"local\",");
                sb.AppendLine("          \"name\": \"Локальная модель\",");
                sb.AppendLine("          \"tool_call\": true,");
                sb.AppendLine("          \"limit\": { \"context\": " + limitCtx.ToString() + ", \"output\": " + output.ToString() + " }");
                sb.AppendLine("        }");
                sb.AppendLine("      }");
                bool other = Service.HasProfile && Service.Models.Length > 0;
                sb.AppendLine(other ? "    }," : "    }");
                if (other)
                {
                    string baseUrl = Service.BaseUrl.TrimEnd('/');
                    sb.AppendLine("    \"other\": {");
                    sb.AppendLine("      \"npm\": \"@ai-sdk/openai-compatible\",");
                    sb.AppendLine("      \"name\": \"" + JsonEscape(Service.Label) + "\",");
                    sb.AppendLine("      \"api\": \"" + JsonEscape(baseUrl) + "\",");
                    sb.AppendLine("      \"options\": { \"baseURL\": \"" + JsonEscape(baseUrl)
                        + "\", \"apiKey\": \"${env:POLZA_API_KEY}\" },");
                    sb.AppendLine("      \"models\": {");
                    string[] ids = Service.Models;
                    for (int i = 0; i < ids.Length; i++)
                    {
                        string id = JsonEscape(ids[i]);
                        sb.AppendLine("        \"" + id + "\": { \"id\": \"" + id
                            + "\", \"name\": \"" + id + "\", \"tool_call\": true }"
                            + (i + 1 < ids.Length ? "," : ""));
                    }
                    sb.AppendLine("      }");
                    sb.AppendLine("    }");
                }
                sb.AppendLine("  }");
                sb.AppendLine("}");
                File.WriteAllText(path, sb.ToString(), new UTF8Encoding(false));
                WriteAgentRules();
                Log.Write("OFFLINE", "Конфиг движка записан: " + path);
            }
            catch (Exception ex)
            {
                Log.Exception("Конфиг движка", ex);
            }
        }

        // Правила для модели. Без них она при недоступном веб-поиске просто
        // отвечает «не нашёл» и перестаёт искать другими способами.
        private void WriteAgentRules()
        {
            const string marker = "<!-- Slonobass agent -->";
            try
            {
                string path = Path.Combine(projectsDir, "AGENTS.md");
                if (File.Exists(path))
                {
                    string head = "";
                    using (StreamReader r = new StreamReader(path, Encoding.UTF8))
                    {
                        char[] buf = new char[200];
                        int n = r.Read(buf, 0, buf.Length);
                        head = new string(buf, 0, n);
                    }
                    if (head.IndexOf(marker, StringComparison.Ordinal) < 0) return;
                }
                StringBuilder sb = new StringBuilder();
                sb.AppendLine(marker);
                sb.AppendLine("# Правила работы");
                sb.AppendLine();
                sb.AppendLine("Ты — помощник внутри программы Slonobass agent. Отвечай по-русски, коротко и по делу.");
                sb.AppendLine();
                sb.AppendLine("## Поиск в интернете");
                sb.AppendLine("1. Сначала попробуй инструмент websearch.");
                sb.AppendLine("2. Если поиск недоступен, вернул ошибку или пустой результат — открой страницу поиска через webfetch:");
                sb.AppendLine("   https://lite.duckduckgo.com/lite/?q=ЗАПРОС (вместо пробелов поставь +)");
                sb.AppendLine("3. Если не открылось — https://www.bing.com/search?q=ЗАПРОС");
                sb.AppendLine("4. Ссылки из выдачи открывай через webfetch и читай текст страницы, а не догадывайся по названию.");
                sb.AppendLine("5. Если в вопросе есть название сервиса или адрес сайта — попробуй сразу открыть этот сайт через webfetch.");
                sb.AppendLine("6. Если не удалось ничего — честно скажи, что поиск сейчас не работает. Не выдумывай факты, цены и ссылки.");
                sb.AppendLine();
                sb.AppendLine("## Файлы");
                sb.AppendLine("Новые файлы создавай только тогда, когда об этом прямо просят.");
                File.WriteAllText(path, sb.ToString(), new UTF8Encoding(false));
            }
            catch (Exception ex)
            {
                Log.Exception("Правила для модели", ex);
            }
        }

        private static string JsonEscape(string s)
        {
            if (s == null) return "";
            StringBuilder sb = new StringBuilder();
            for (int i = 0; i < s.Length; i++)
            {
                char c = s[i];
                if (c == '"') sb.Append("\\\"");
                else if (c == '\\') sb.Append("\\\\");
                else if (c < ' ') sb.Append("\\u").Append(((int)c).ToString("x4"));
                else sb.Append(c);
            }
            return sb.ToString();
        }

        private static bool HttpOk(string url)
        {
            try
            {
                HttpWebRequest req = (HttpWebRequest)WebRequest.Create(url);
                req.Proxy = null;
                req.Timeout = 2500;
                req.ReadWriteTimeout = 2500;
                req.KeepAlive = false;
                using (HttpWebResponse resp = (HttpWebResponse)req.GetResponse())
                {
                    return (int)resp.StatusCode == 200;
                }
            }
            catch
            {
                return false;
            }
        }

        private static string HttpGetText(string url)
        {
            HttpWebRequest req = (HttpWebRequest)WebRequest.Create(url);
            req.Proxy = null;
            req.Timeout = 3000;
            req.ReadWriteTimeout = 3000;
            req.KeepAlive = false;
            using (HttpWebResponse resp = (HttpWebResponse)req.GetResponse())
            using (StreamReader reader = new StreamReader(resp.GetResponseStream(), Encoding.UTF8))
            {
                return reader.ReadToEnd();
            }
        }

        // llama-server отдаёт в /props контекст одного слота (n_ctx).
        private int OfflineSlotContext()
        {
            try
            {
                string body = HttpGetText("http://127.0.0.1:" + OfflinePort.ToString() + "/props");
                Match m = Regex.Match(body, "\"n_ctx\"\\s*:\\s*(\\d+)");
                if (m.Success)
                {
                    int v;
                    if (int.TryParse(m.Groups[1].Value, out v) && v > 0 && v <= 1048576) return v;
                }
            }
            catch
            {
            }
            return 0;
        }

        private bool OfflineReady()
        {
            string b = "http://127.0.0.1:" + OfflinePort.ToString();
            if (HttpOk(b + "/health")) return true;
            return HttpOk(b + "/v1/models");
        }

        private void SetStatusSafe(string text)
        {
            try
            {
                BeginInvoke(new Action(delegate() { statusLabel.Text = text; }));
            }
            catch
            {
            }
        }

        private void StopOffline()
        {
            lock (llamaLock) StopOfflineLocked();
        }

        private void StopOfflineLocked()
        {
            if (llamaProc == null) return;
            try
            {
                if (!llamaProc.HasExited)
                {
                    llamaProc.Kill();
                    llamaProc.WaitForExit(5000);
                }
            }
            catch
            {
            }
            try { llamaProc.Dispose(); } catch { }
            llamaProc = null;
            llamaLoaded = null;
            loadingOffline = false;
            Log.Write("OFFLINE", "Сервер llama остановлен.");
        }

        // Запускает llama-server с выбранным файлом .gguf и ждёт готовности.
        private bool EnsureOffline(string gguf)
        {
            if (gguf == null || !File.Exists(gguf))
            {
                offlineError = "Файл офлайн-модели не найден: "
                    + (gguf == null ? "(путь потерян)" : gguf)
                    + "\r\nДобавьте модель заново кнопкой «Добавить модель…».";
                return false;
            }

            bool alive = false;
            lock (llamaLock)
            {
                if (llamaProc != null && !llamaProc.HasExited
                    && string.Equals(llamaLoaded, gguf, StringComparison.OrdinalIgnoreCase))
                {
                    alive = true;
                }
                else
                {
                    StopOfflineLocked();
                }
            }
            if (alive && OfflineReady())
            {
                int running = OfflineSlotContext();
                if (running > 0) WriteOfflineConfig(Math.Min(ContextFor(gguf), running));
                return true;
            }
            if (alive)
            {
                // Процесс жив, но сервер не отвечает — начинаем заново.
                lock (llamaLock) StopOfflineLocked();
            }

            string exe = Path.Combine(llamaDir, "llama-server.exe");
            if (!File.Exists(exe))
            {
                offlineError = "Рядом с программой нет папки engine\\llama с файлом llama-server.exe."
                    + "\r\nПохоже, архив распакован не полностью. Распакуйте архив заново в отдельную папку.";
                return false;
            }

            int ctx = ContextFor(gguf);
            SetStatusSafe("Запускаю офлайн-модель, контекст " + ctx.ToString() + " токенов…");
            Log.Write("OFFLINE", "Запуск llama-server: контекст " + ctx.ToString() + " токенов, файл " + gguf);
            ProcessStartInfo psi = new ProcessStartInfo(exe);
            psi.Arguments = "-m " + Quote(gguf)
                + " --host 127.0.0.1 --port " + OfflinePort.ToString()
                + " -c " + ctx.ToString() + " --parallel 1 -np 1 --alias local --jinja";
            psi.WorkingDirectory = llamaDir;
            psi.UseShellExecute = false;
            psi.CreateNoWindow = true;
            psi.RedirectStandardOutput = true;
            psi.RedirectStandardError = true;
            psi.StandardOutputEncoding = Encoding.UTF8;
            psi.StandardErrorEncoding = Encoding.UTF8;

            Process p = new Process();
            p.StartInfo = psi;
            p.OutputDataReceived += delegate(object s, DataReceivedEventArgs a)
            {
                if (a.Data != null) Log.Write("LLAMA-OUT", Shorten(a.Data, 500));
            };
            p.ErrorDataReceived += delegate(object s, DataReceivedEventArgs a)
            {
                if (a.Data != null) Log.Write("LLAMA-ERR", Shorten(a.Data, 500));
            };
            try
            {
                p.Start();
                p.BeginOutputReadLine();
                p.BeginErrorReadLine();
            }
            catch (Exception ex)
            {
                offlineError = "Не удалось запустить llama-server.exe: " + ex.Message
                    + "\r\nПодробности — в «Журнале ошибок».";
                Log.Exception("Запуск llama-server", ex);
                try { p.Dispose(); } catch { }
                return false;
            }

            lock (llamaLock)
            {
                llamaProc = p;
                llamaLoaded = gguf;
            }
            loadingOffline = true;
            Log.Write("OFFLINE", "Сервер llama запущен для файла: " + gguf
                + "; порт " + OfflinePort.ToString());

            int waited = 0;
            while (waited < 300)
            {
                if (p.HasExited)
                {
                    int code = p.ExitCode;
                    ReleaseLocal(p);
                    offlineError = "llama-server завершился с кодом " + code.ToString()
                        + ", не дождавшись загрузки модели."
                        + "\r\nЧастые причины: файл модели повреждён или не подходит этой версии llama.cpp,"
                        + " либо не хватает оперативной памяти."
                        + "\r\nПодробности — в «Журнале ошибок», разделы LLAMA.";
                    return false;
                }
                if (OfflineReady())
                {
                    loadingOffline = false;
                    // Сервер мог разделить контекст между слотами: движку
                    // сообщаем реально доступный размер, иначе он ошибётся
                    // «request exceeds the available context size».
                    int slotCtx = OfflineSlotContext();
                    int useCtx = slotCtx > 0 && slotCtx < ctx ? slotCtx : ctx;
                    WriteOfflineConfig(useCtx);
                    Log.Write("OFFLINE", "Контекст слота: " + slotCtx.ToString()
                        + "; движку выставлен " + useCtx.ToString() + ".");
                    SetStatusSafe("Офлайн-модель готова (контекст " + useCtx.ToString() + "), отправляю запрос…");
                    Log.Write("OFFLINE", "Сервер llama готов после " + waited.ToString() + " с.");
                    return true;
                }
                Thread.Sleep(1000);
                waited++;
            }

            ReleaseLocal(p);
            offlineError = "Модель не загрузилась за 5 минут."
                + "\r\nБольшие модели на слабом компьютере грузятся долго; попробуйте файл поменьше (Q4)."
                + "\r\nПодробности — в «Журнале ошибок», разделы LLAMA.";
            return false;
        }

        private void ReleaseLocal(Process p)
        {
            lock (llamaLock)
            {
                if (llamaProc == p)
                {
                    StopOfflineLocked();
                    return;
                }
            }
            try { p.Dispose(); } catch { }
        }

        private static string ShortName(string id)
        {
            int slash = id.IndexOf('/');
            if (slash >= 0 && slash + 1 < id.Length) return id.Substring(slash + 1);
            return id;
        }

        // ---------- process helpers ----------

        private string BuildArgs(string question, string model, List<FileItem> files, bool useSession)
        {
            StringBuilder sb = new StringBuilder();
            sb.Append("run --standalone --auto --format json");
            if (useSession && sessionId != null && sessionId.Length > 0)
            {
                sb.Append(" --session ");
                sb.Append(Quote(sessionId));
            }
            if (model != null && model.Length > 0)
            {
                sb.Append(" --model ");
                sb.Append(Quote(model));
            }
            for (int i = 0; i < files.Count; i++)
            {
                sb.Append(" --file ");
                sb.Append(Quote(files[i].Path));
            }
            sb.Append(' ');
            sb.Append(Quote(question));
            return sb.ToString();
        }

        private static string Quote(string s)
        {
            StringBuilder sb = new StringBuilder();
            sb.Append('"');
            int backslashes = 0;
            for (int i = 0; i < s.Length; i++)
            {
                char c = s[i];
                if (c == '\\')
                {
                    backslashes++;
                    continue;
                }
                if (c == '"')
                {
                    sb.Append('\\', backslashes * 2 + 1);
                    sb.Append('"');
                    backslashes = 0;
                    continue;
                }
                if (backslashes > 0)
                {
                    sb.Append('\\', backslashes);
                    backslashes = 0;
                }
                sb.Append(c);
            }
            if (backslashes > 0) sb.Append('\\', backslashes * 2);
            sb.Append('"');
            return sb.ToString();
        }

        private static string JsonValue(string json, string key)
        {
            string pat = "\"" + key + "\":\"";
            int i = json.IndexOf(pat, StringComparison.Ordinal);
            if (i < 0) return null;
            int p = i + pat.Length;
            StringBuilder sb = new StringBuilder();
            while (p < json.Length)
            {
                char c = json[p];
                if (c == '\\' && p + 1 < json.Length)
                {
                    char n = json[p + 1];
                    p += 2;
                    switch (n)
                    {
                        case 'n': sb.Append('\n'); break;
                        case 'r': sb.Append('\r'); break;
                        case 't': sb.Append('\t'); break;
                        case 'b': sb.Append('\b'); break;
                        case 'f': sb.Append('\f'); break;
                        case 'u':
                            if (p + 4 <= json.Length)
                            {
                                int code;
                                bool ok = int.TryParse(json.Substring(p, 4),
                                    System.Globalization.NumberStyles.HexNumber,
                                    System.Globalization.CultureInfo.InvariantCulture, out code);
                                if (ok) sb.Append((char)code);
                                p += 4;
                            }
                            break;
                        default: sb.Append(n); break;
                    }
                    continue;
                }
                if (c == '"') break;
                sb.Append(c);
                p++;
            }
            return sb.ToString();
        }

        private static string Shorten(string s, int max)
        {
            if (s.Length <= max) return s;
            return s.Substring(0, max) + "…";
        }

        private static string SizeText(long bytes)
        {
            if (bytes < 1024) return bytes.ToString() + " Б";
            if (bytes < 1024L * 1024L) return (bytes / 1024).ToString() + " КБ";
            return (bytes / (1024L * 1024L)).ToString() + " МБ";
        }
    }

    internal static class Profile
    {
        private static string filePath;
        private static string cached;
        private static bool loaded;

        public static string FilePath
        {
            get
            {
                if (filePath == null)
                {
                    string dir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "OpenCodeChat");
                    filePath = Path.Combine(dir, "deepseek.key");
                }
                return filePath;
            }
        }

        public static string Key
        {
            get
            {
                if (!loaded)
                {
                    loaded = true;
                    cached = Read();
                }
                return cached;
            }
        }

        public static bool HasKey
        {
            get { return Key != null && Key.Length > 0; }
        }

        public static string Hint
        {
            get
            {
                string k = Key;
                if (k == null || k.Length == 0) return "ключ не подключён";
                if (k.Length <= 8) return "ключ сохранён";
                return "ключ …" + k.Substring(k.Length - 4);
            }
        }

        public static void Save(string key)
        {
            string dir = Path.GetDirectoryName(FilePath);
            if (!Directory.Exists(dir)) Directory.CreateDirectory(dir);
            byte[] data = Encoding.UTF8.GetBytes(key);
            byte[] prot = ProtectedData.Protect(data, null, DataProtectionScope.CurrentUser);
            File.WriteAllBytes(FilePath, prot);
            cached = key;
            loaded = true;
        }

        public static void Clear()
        {
            try
            {
                if (File.Exists(FilePath)) File.Delete(FilePath);
            }
            catch (Exception ex)
            {
                Log.Exception("Удаление ключа", ex);
            }
            cached = null;
            loaded = true;
        }

        public static void Apply(ProcessStartInfo psi)
        {
            string k = Key;
            if (k != null && k.Length > 0) psi.EnvironmentVariables["DEEPSEEK_API_KEY"] = k;
        }

        private static string Read()
        {
            try
            {
                if (!File.Exists(FilePath)) return null;
                byte[] prot = File.ReadAllBytes(FilePath);
                byte[] data = ProtectedData.Unprotect(prot, null, DataProtectionScope.CurrentUser);
                return Encoding.UTF8.GetString(data).Trim();
            }
            catch (Exception ex)
            {
                Log.Exception("Чтение ключа DeepSeek", ex);
                return null;
            }
        }
    }

    // Другой сервис: Polza.ai, AnyModel или любой адрес, совместимый с OpenAI.
    // Ключ лежит в защищённом файле и передаётся движку переменной окружения.
    internal static class Service
    {
        private static bool loaded;
        private static string key = "";
        private static string baseUrl = "";
        private static string label = "";
        private static string[] models = new string[0];

        private static string Dir
        {
            get
            {
                return Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "OpenCodeChat");
            }
        }

        private static string KeyPath { get { return Path.Combine(Dir, "service.key"); } }
        private static string InfoPath { get { return Path.Combine(Dir, "service.txt"); } }

        public static string Key
        {
            get { Load(); return key; }
        }

        public static string BaseUrl
        {
            get { Load(); return baseUrl; }
        }

        public static string Label
        {
            get { Load(); return label.Length > 0 ? label : "Другой сервис"; }
        }

        public static string[] Models
        {
            get { Load(); return models; }
        }

        public static bool HasProfile
        {
            get { return Key.Length > 0 && BaseUrl.Length > 0; }
        }

        public static string Hint
        {
            get
            {
                string k = Key;
                if (k.Length == 0) return "не подключён";
                if (k.Length <= 8) return "ключ сохранён";
                return "ключ …" + k.Substring(k.Length - 4);
            }
        }

        public static void Save(string serviceLabel, string serviceUrl, string serviceKey, string[] serviceModels)
        {
            Load();
            key = serviceKey == null ? "" : serviceKey.Trim();
            baseUrl = serviceUrl == null ? "" : serviceUrl.Trim().TrimEnd('/');
            label = serviceLabel == null ? "" : serviceLabel.Trim();
            models = serviceModels == null ? new string[0] : serviceModels;
            try
            {
                if (!Directory.Exists(Dir)) Directory.CreateDirectory(Dir);
                byte[] data = Encoding.UTF8.GetBytes(key);
                byte[] prot = ProtectedData.Protect(data, null, DataProtectionScope.CurrentUser);
                File.WriteAllBytes(KeyPath, prot);
                List<string> lines = new List<string>();
                lines.Add(label);
                lines.Add(baseUrl);
                for (int i = 0; i < models.Length; i++) lines.Add(models[i]);
                File.WriteAllLines(InfoPath, lines.ToArray(), new UTF8Encoding(false));
                loaded = true;
            }
            catch (Exception ex)
            {
                Log.Exception("Сохранение другого сервиса", ex);
            }
        }

        public static void Clear()
        {
            try
            {
                if (File.Exists(KeyPath)) File.Delete(KeyPath);
                if (File.Exists(InfoPath)) File.Delete(InfoPath);
            }
            catch (Exception ex)
            {
                Log.Exception("Удаление другого сервиса", ex);
            }
            key = "";
            baseUrl = "";
            label = "";
            models = new string[0];
            loaded = true;
        }

        public static void Apply(ProcessStartInfo psi)
        {
            string k = Key;
            if (k.Length > 0) psi.EnvironmentVariables["POLZA_API_KEY"] = k;
        }

        private static void Load()
        {
            if (loaded) return;
            loaded = true;
            try
            {
                if (File.Exists(KeyPath))
                {
                    byte[] prot = File.ReadAllBytes(KeyPath);
                    byte[] data = ProtectedData.Unprotect(prot, null, DataProtectionScope.CurrentUser);
                    key = Encoding.UTF8.GetString(data).Trim();
                }
                if (File.Exists(InfoPath))
                {
                    string[] lines = File.ReadAllLines(InfoPath, Encoding.UTF8);
                    if (lines.Length > 0) label = lines[0].Trim();
                    if (lines.Length > 1) baseUrl = lines[1].Trim();
                    List<string> list = new List<string>();
                    for (int i = 2; i < lines.Length; i++)
                    {
                        string s = lines[i].Trim();
                        if (s.Length > 0) list.Add(s);
                    }
                    models = list.ToArray();
                }
            }
            catch (Exception ex)
            {
                Log.Exception("Чтение другого сервиса", ex);
            }
        }
    }

    internal sealed class ProfileForm : Form
    {
        private TextBox keyBox;
        private CheckBox showBox;
        private Label stateLabel;
        private Button deleteBtn;

        public ProfileForm()
        {
            Text = "Мой профиль — DeepSeek";
            StartPosition = FormStartPosition.CenterParent;
            FormBorderStyle = FormBorderStyle.FixedDialog;
            MaximizeBox = false;
            MinimizeBox = false;
            ShowInTaskbar = false;
            ClientSize = new Size(640, 372);
            Font = new Font("Segoe UI", 10f);

            Label intro = new Label();
            intro.Text = "Свой аккаунт DeepSeek.\r\n\r\n"
                + "Если вставить сюда ключ, сверху в списке моделей появится раздел «Мой профиль» "
                + "с моделями DeepSeek. Запросы пойдут на ваш аккаунт — на ваши оплаченные токены.\r\n\r\n"
                + "Ключ создаётся на сайте platform.deepseek.com в разделе API keys.";
            intro.Location = new Point(14, 12);
            intro.Size = new Size(612, 118);
            intro.AccessibleName = "Описание";
            Controls.Add(intro);

            stateLabel = new Label();
            stateLabel.Location = new Point(14, 134);
            stateLabel.Size = new Size(612, 24);
            stateLabel.AccessibleName = "Состояние профиля";
            Controls.Add(stateLabel);
            UpdateState();

            Label keyLabel = new Label();
            keyLabel.Text = "&Ключ DeepSeek (начинается с sk-):";
            keyLabel.Location = new Point(14, 162);
            keyLabel.Size = new Size(320, 22);
            Controls.Add(keyLabel);

            keyBox = new TextBox();
            keyBox.Location = new Point(14, 186);
            keyBox.Width = 612;
            keyBox.UseSystemPasswordChar = true;
            keyBox.AccessibleName = "Ключ DeepSeek";
            keyBox.AccessibleDescription = "Ключ DeepSeek";
            keyBox.Text = Profile.Key != null ? Profile.Key : "";
            Controls.Add(keyBox);

            showBox = new CheckBox();
            showBox.Text = "По&казать ключ";
            showBox.Location = new Point(14, 216);
            showBox.Size = new Size(180, 24);
            showBox.CheckedChanged += delegate { keyBox.UseSystemPasswordChar = !showBox.Checked; };
            Controls.Add(showBox);

            LinkLabel link = new LinkLabel();
            link.Text = "&Страница ключей DeepSeek в браузере";
            link.Location = new Point(200, 216);
            link.Size = new Size(420, 24);
            link.AccessibleName = "Открыть страницу ключей DeepSeek в браузере";
            link.LinkClicked += delegate
            {
                try
                {
                    Process.Start("https://platform.deepseek.com/api_keys");
                }
                catch (Exception ex)
                {
                    Log.Exception("Открыть сайт DeepSeek", ex);
                }
            };
            Controls.Add(link);

            Panel bottom = new Panel();
            bottom.Dock = DockStyle.Bottom;
            bottom.Height = 52;

            Button saveBtn = new Button();
            saveBtn.Text = "&Сохранить";
            saveBtn.Width = 130;
            saveBtn.Location = new Point(14, 12);
            saveBtn.AccessibleName = "Сохранить ключ";
            saveBtn.Click += delegate { SaveKey(); };
            bottom.Controls.Add(saveBtn);

            deleteBtn = new Button();
            deleteBtn.Text = "&Удалить ключ";
            deleteBtn.Width = 130;
            deleteBtn.Location = new Point(154, 12);
            deleteBtn.AccessibleName = "Удалить ключ DeepSeek";
            deleteBtn.Enabled = Profile.HasKey;
            deleteBtn.Click += delegate { DeleteKey(); };
            bottom.Controls.Add(deleteBtn);

            Button cancelBtn = new Button();
            cancelBtn.Text = "Отмена";
            cancelBtn.Width = 110;
            cancelBtn.Location = new Point(294, 12);
            cancelBtn.DialogResult = DialogResult.Cancel;
            bottom.Controls.Add(cancelBtn);

            Controls.Add(bottom);
            AcceptButton = saveBtn;
            CancelButton = cancelBtn;
        }

        private void UpdateState()
        {
            stateLabel.Text = "Сейчас: " + Profile.Hint + ".";
        }

        private void SaveKey()
        {
            string k = keyBox.Text.Trim();
            if (k.Length == 0)
            {
                MessageBox.Show(this,
                    "Введите ключ DeepSeek. Чтобы отключить профиль, нажмите «Удалить ключ».",
                    Text, MessageBoxButtons.OK, MessageBoxIcon.Information);
                keyBox.Focus();
                return;
            }
            if (!k.StartsWith("sk-", StringComparison.OrdinalIgnoreCase))
            {
                DialogResult r = MessageBox.Show(this,
                    "Обычно ключ DeepSeek начинается с sk-. Этот не похож. Сохранить всё равно?",
                    Text, MessageBoxButtons.YesNo, MessageBoxIcon.Question);
                if (r != DialogResult.Yes)
                {
                    keyBox.Focus();
                    return;
                }
            }
            try
            {
                Profile.Save(k);
                DialogResult = DialogResult.OK;
                Close();
            }
            catch (Exception ex)
            {
                Log.Exception("Сохранение ключа DeepSeek", ex);
                MessageBox.Show(this, "Не удалось сохранить ключ: " + ex.Message,
                    Text, MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
        }

        private void DeleteKey()
        {
            DialogResult r = MessageBox.Show(this,
                "Удалить сохранённый ключ DeepSeek? Тогда останутся только бесплатные модели.",
                Text, MessageBoxButtons.YesNo, MessageBoxIcon.Question);
            if (r != DialogResult.Yes) return;
            Profile.Clear();
            DialogResult = DialogResult.OK;
            Close();
        }
    }

    internal sealed class ServiceForm : Form
    {
        private static readonly string[] PresetNames = new string[]
        {
            "Polza.ai — polza.ai/api/v1",
            "AnyModel — anymodel.org/v1",
            "Свой адрес…"
        };
        private static readonly string[] PresetUrls = new string[]
        {
            "https://polza.ai/api/v1",
            "https://anymodel.org/v1",
            ""
        };
        private static readonly string[] PresetLabels = new string[]
        {
            "Polza.ai",
            "AnyModel",
            ""
        };

        private ComboBox presetBox;
        private TextBox baseBox;
        private TextBox keyBox;
        private CheckBox showBox;
        private CheckedListBox modelsList;
        private Label stateLabel;
        private Button checkBtn;
        private Button saveBtn;

        public ServiceForm()
        {
            Text = "Другие сервисы";
            StartPosition = FormStartPosition.CenterParent;
            FormBorderStyle = FormBorderStyle.FixedDialog;
            MaximizeBox = false;
            MinimizeBox = false;
            ShowInTaskbar = false;
            ClientSize = new Size(760, 650);
            Font = new Font("Segoe UI", 10f);

            Label intro = new Label();
            intro.Text = "Polza.ai, AnyModel или любой сервис с адресом в стиле OpenAI.\r\n\r\n"
                + "Положите сюда ключ и отметьте нужные модели — они появятся сверху в списке "
                + "моделей отдельным разделом. Запросы пойдут на ваш аккаунт в этом сервисе, "
                + "на ваши оплаченные токены.\r\n\r\n"
                + "Ключ хранится только на этом компьютере и защищён учётной записью Windows.";
            intro.Location = new Point(14, 10);
            intro.Size = new Size(732, 96);
            intro.AccessibleName = "Описание";
            Controls.Add(intro);

            stateLabel = new Label();
            stateLabel.Location = new Point(14, 108);
            stateLabel.Size = new Size(732, 24);
            stateLabel.AccessibleName = "Состояние сервиса";
            Controls.Add(stateLabel);

            Label presetLabel = new Label();
            presetLabel.Text = "&Сервис:";
            presetLabel.Location = new Point(14, 140);
            presetLabel.Size = new Size(200, 22);
            Controls.Add(presetLabel);

            presetBox = new ComboBox();
            presetBox.DropDownStyle = ComboBoxStyle.DropDownList;
            presetBox.Location = new Point(14, 162);
            presetBox.Width = 420;
            presetBox.AccessibleName = "Сервис";
            presetBox.AccessibleDescription = "Polza.ai, AnyModel или свой адрес";
            for (int i = 0; i < PresetNames.Length; i++) presetBox.Items.Add(PresetNames[i]);
            presetBox.SelectedIndexChanged += delegate { ApplyPreset(); };
            Controls.Add(presetBox);

            Label baseLabel = new Label();
            baseLabel.Text = "&Адрес API:";
            baseLabel.Location = new Point(14, 196);
            baseLabel.Size = new Size(200, 22);
            Controls.Add(baseLabel);

            baseBox = new TextBox();
            baseBox.Location = new Point(14, 218);
            baseBox.Width = 732;
            baseBox.AccessibleName = "Адрес API";
            baseBox.AccessibleDescription = "Например https://polza.ai/api/v1";
            Controls.Add(baseBox);

            Label keyLabel = new Label();
            keyLabel.Text = "&Ключ сервиса:";
            keyLabel.Location = new Point(14, 252);
            keyLabel.Size = new Size(300, 22);
            Controls.Add(keyLabel);

            keyBox = new TextBox();
            keyBox.Location = new Point(14, 274);
            keyBox.Width = 540;
            keyBox.UseSystemPasswordChar = true;
            keyBox.AccessibleName = "Ключ сервиса";
            keyBox.AccessibleDescription = "Ключ Polza.ai начинается с pza_";
            Controls.Add(keyBox);

            showBox = new CheckBox();
            showBox.Text = "По&казать ключ";
            showBox.Location = new Point(566, 274);
            showBox.Size = new Size(180, 24);
            showBox.CheckedChanged += delegate { keyBox.UseSystemPasswordChar = !showBox.Checked; };
            Controls.Add(showBox);

            checkBtn = new Button();
            checkBtn.Text = "&Проверить и получить модели";
            checkBtn.Location = new Point(14, 310);
            checkBtn.Size = new Size(260, 30);
            checkBtn.AccessibleName = "Проверить ключ и получить список моделей";
            checkBtn.Click += delegate { CheckModels(); };
            Controls.Add(checkBtn);

            Label modelsLabel = new Label();
            modelsLabel.Text = "Моде&ли сервиса — отметьте нужные (пробел):";
            modelsLabel.Location = new Point(14, 348);
            modelsLabel.Size = new Size(600, 22);
            Controls.Add(modelsLabel);

            modelsList = new CheckedListBox();
            modelsList.Location = new Point(14, 370);
            modelsList.Size = new Size(732, 200);
            modelsList.CheckOnClick = true;
            modelsList.AccessibleName = "Модели сервиса";
            Controls.Add(modelsList);

            Label fetchLabel = new Label();
            fetchLabel.Location = new Point(14, 576);
            fetchLabel.Size = new Size(732, 22);
            fetchLabel.AccessibleName = "Результат проверки";
            fetchLabel.Name = "fetchLabel";
            Controls.Add(fetchLabel);

            Panel bottom = new Panel();
            bottom.Dock = DockStyle.Bottom;
            bottom.Height = 52;

            saveBtn = new Button();
            saveBtn.Text = "&Сохранить";
            saveBtn.Width = 130;
            saveBtn.Location = new Point(14, 12);
            saveBtn.AccessibleName = "Сохранить сервис";
            saveBtn.Click += delegate { SaveProfile(); };
            bottom.Controls.Add(saveBtn);

            Button deleteBtn = new Button();
            deleteBtn.Text = "&Удалить сервис";
            deleteBtn.Width = 130;
            deleteBtn.Location = new Point(154, 12);
            deleteBtn.AccessibleName = "Удалить другой сервис";
            deleteBtn.Enabled = Service.HasProfile;
            deleteBtn.Click += delegate { DeleteProfile(); };
            bottom.Controls.Add(deleteBtn);

            Button cancelBtn = new Button();
            cancelBtn.Text = "Отмена";
            cancelBtn.Width = 110;
            cancelBtn.Location = new Point(294, 12);
            cancelBtn.DialogResult = DialogResult.Cancel;
            bottom.Controls.Add(cancelBtn);

            Controls.Add(bottom);
            AcceptButton = saveBtn;
            CancelButton = cancelBtn;

            LoadExisting();
        }

        private void LoadExisting()
        {
            string url = Service.BaseUrl;
            int preset = PresetUrls.Length - 1;
            for (int i = 0; i < PresetUrls.Length - 1; i++)
            {
                if (PresetUrls[i].Length > 0 && string.Equals(url, PresetUrls[i], StringComparison.OrdinalIgnoreCase))
                {
                    preset = i;
                    break;
                }
            }
            presetBox.SelectedIndex = preset;
            if (url.Length > 0) baseBox.Text = url;
            else baseBox.Text = PresetUrls[0];
            baseBox.ReadOnly = preset != PresetUrls.Length - 1;
            keyBox.Text = Service.Key;
            string[] saved = Service.Models;
            modelsList.Items.Clear();
            for (int i = 0; i < saved.Length; i++) modelsList.Items.Add(saved[i], true);
            UpdateState();
        }

        private void UpdateState()
        {
            if (Service.HasProfile)
                stateLabel.Text = "Сейчас: " + Service.Label + ", " + Service.Hint
                    + ", моделей: " + Service.Models.Length.ToString() + ".";
            else
                stateLabel.Text = "Сейчас: другой сервис не подключён.";
        }

        private void ApplyPreset()
        {
            int i = presetBox.SelectedIndex;
            if (i < 0) return;
            bool own = i == PresetUrls.Length - 1;
            baseBox.ReadOnly = !own;
            if (!own) baseBox.Text = PresetUrls[i];
            keyBox.AccessibleDescription = i == 0 ? "Ключ Polza.ai начинается с pza_" : "Ключ сервиса";
        }

        private string CurrentLabel()
        {
            int i = presetBox.SelectedIndex;
            if (i >= 0 && i < PresetLabels.Length && PresetLabels[i].Length > 0) return PresetLabels[i];
            string url = baseBox.Text.Trim();
            try { return new Uri(url).Host; }
            catch { return "Другой сервис"; }
        }

        private void CheckModels()
        {
            string url = baseBox.Text.Trim().TrimEnd('/');
            string k = keyBox.Text.Trim();
            if (k.Length == 0)
            {
                MessageBox.Show(this, "Введите ключ сервиса.", Text,
                    MessageBoxButtons.OK, MessageBoxIcon.Information);
                keyBox.Focus();
                return;
            }
            if (!url.StartsWith("http://", StringComparison.OrdinalIgnoreCase)
                && !url.StartsWith("https://", StringComparison.OrdinalIgnoreCase))
            {
                MessageBox.Show(this, "Адрес API должен начинаться с http:// или https://.", Text,
                    MessageBoxButtons.OK, MessageBoxIcon.Information);
                baseBox.Focus();
                return;
            }
            stateLabel.Text = "Проверяю ключ и получаю список моделей…";
            checkBtn.Enabled = false;
            saveBtn.Enabled = false;
            Thread t = new Thread(delegate()
            {
                List<string> found = new List<string>();
                string err = null;
                try
                {
                    string body = FetchModels(url + "/models", k);
                    MatchCollection ms = Regex.Matches(body, "\"id\"\\s*:\\s*\"([^\"]+)\"");
                    for (int i = 0; i < ms.Count; i++)
                    {
                        string id = ms[i].Groups[1].Value.Trim();
                        if (id.Length == 0) continue;
                        string low = id.ToLowerInvariant();
                        if (low.IndexOf("embed") >= 0) continue;
                        if (low.IndexOf("whisper") >= 0) continue;
                        if (low.IndexOf("rerank") >= 0) continue;
                        if (low.IndexOf("moderation") >= 0) continue;
                        if (!found.Contains(id)) found.Add(id);
                    }
                }
                catch (Exception ex)
                {
                    err = Describe(ex);
                }
                try
                {
                    BeginInvoke(new Action(delegate { AfterCheck(found, err); }));
                }
                catch
                {
                }
            });
            t.IsBackground = true;
            t.Start();
        }

        private void AfterCheck(List<string> found, string err)
        {
            checkBtn.Enabled = true;
            saveBtn.Enabled = true;
            Label fetchLabel = null;
            for (int i = 0; i < Controls.Count; i++)
            {
                Label l = Controls[i] as Label;
                if (l != null && l.Name == "fetchLabel") { fetchLabel = l; break; }
            }
            if (err != null)
            {
                stateLabel.Text = "Проверка не удалась: " + err;
                if (fetchLabel != null) fetchLabel.Text = "Ключ не проверен. Можно сохранить и попробовать позже.";
                return;
            }
            if (found.Count == 0)
            {
                stateLabel.Text = "Сервис ответил, но моделей в ответе нет.";
                if (fetchLabel != null) fetchLabel.Text = "Проверьте адрес API: список моделей берётся с адреса …/models.";
                return;
            }
            List<string> previous = new List<string>(Service.Models);
            modelsList.Items.Clear();
            for (int i = 0; i < found.Count; i++)
            {
                bool check = previous.Count == 0 || previous.Contains(found[i]);
                modelsList.Items.Add(found[i], check);
            }
            stateLabel.Text = "Ключ принят. Найдено моделей: " + found.Count.ToString() + ".";
            if (fetchLabel != null) fetchLabel.Text = "Отметьте нужные модели и нажмите «Сохранить».";
        }

        private static string Describe(Exception ex)
        {
            WebException we = ex as WebException;
            if (we != null)
            {
                HttpWebResponse resp = we.Response as HttpWebResponse;
                if (resp != null)
                {
                    string body = "";
                    try
                    {
                        using (StreamReader r = new StreamReader(resp.GetResponseStream(), Encoding.UTF8))
                            body = r.ReadToEnd();
                    }
                    catch { }
                    body = body.Trim();
                    if (body.Length > 300) body = body.Substring(0, 300) + "…";
                    string code = ((int)resp.StatusCode).ToString() + " " + resp.StatusDescription;
                    return body.Length > 0 ? code + ": " + body : code;
                }
                return we.Message;
            }
            return ex.Message;
        }

        private static string FetchModels(string url, string key)
        {
            try
            {
                ServicePointManager.SecurityProtocol = ServicePointManager.SecurityProtocol
                    | SecurityProtocolType.Tls12;
            }
            catch
            {
            }
            HttpWebRequest req = (HttpWebRequest)WebRequest.Create(url);
            req.Proxy = null;
            req.Method = "GET";
            req.Timeout = 20000;
            req.ReadWriteTimeout = 20000;
            req.KeepAlive = false;
            req.UserAgent = "SlonobassAgent";
            req.Accept = "application/json";
            req.Headers["Authorization"] = "Bearer " + key;
            using (HttpWebResponse resp = (HttpWebResponse)req.GetResponse())
            using (StreamReader r = new StreamReader(resp.GetResponseStream(), Encoding.UTF8))
            {
                return r.ReadToEnd();
            }
        }

        private void SaveProfile()
        {
            string url = baseBox.Text.Trim().TrimEnd('/');
            string k = keyBox.Text.Trim();
            if (k.Length == 0)
            {
                MessageBox.Show(this, "Введите ключ сервиса. Чтобы отключить сервис, нажмите «Удалить сервис».",
                    Text, MessageBoxButtons.OK, MessageBoxIcon.Information);
                keyBox.Focus();
                return;
            }
            if (!url.StartsWith("http://", StringComparison.OrdinalIgnoreCase)
                && !url.StartsWith("https://", StringComparison.OrdinalIgnoreCase))
            {
                MessageBox.Show(this, "Адрес API должен начинаться с http:// или https://.",
                    Text, MessageBoxButtons.OK, MessageBoxIcon.Information);
                baseBox.Focus();
                return;
            }
            List<string> selected = new List<string>();
            for (int i = 0; i < modelsList.Items.Count; i++)
            {
                if (modelsList.GetItemChecked(i)) selected.Add(modelsList.Items[i].ToString());
            }
            if (selected.Count == 0)
            {
                MessageBox.Show(this,
                    "Не отмечено ни одной модели.\r\n"
                    + "Нажмите «Проверить и получить модели», отметьте нужные пробелом и сохраните.",
                    Text, MessageBoxButtons.OK, MessageBoxIcon.Information);
                checkBtn.Focus();
                return;
            }
            Service.Save(CurrentLabel(), url, k, selected.ToArray());
            Log.Write("SERVICE", "Сохранён сервис " + CurrentLabel() + " (" + url + "), моделей: "
                + selected.Count.ToString());
            DialogResult = DialogResult.OK;
            Close();
        }

        private void DeleteProfile()
        {
            DialogResult r = MessageBox.Show(this,
                "Удалить ключ и список моделей другого сервиса?",
                Text, MessageBoxButtons.YesNo, MessageBoxIcon.Question);
            if (r != DialogResult.Yes) return;
            Service.Clear();
            Log.Write("SERVICE", "Другой сервис удалён");
            DialogResult = DialogResult.OK;
            Close();
        }
    }

    internal static class Log
    {
        private static readonly object gate = new object();
        private static string folder;
        private static string current;

        public static string Folder
        {
            get { return folder; }
        }

        public static void Init(string baseDir)
        {
            try
            {
                folder = Path.Combine(baseDir, "log");
                Directory.CreateDirectory(folder);
                Open(0);
            }
            catch
            {
                try
                {
                    folder = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                        "OpenCodeChat", "log");
                    Directory.CreateDirectory(folder);
                    Open(0);
                }
                catch
                {
                    folder = null;
                    current = null;
                }
            }
            Write("START", "Программа запущена. Папка программы: " + baseDir);
            Write("START", "Windows: " + Environment.OSVersion.VersionString
                + "; .NET: " + Environment.Version.ToString()
                + "; 64-bit: " + Environment.Is64BitProcess.ToString());
        }

        private static void Open(int index)
        {
            string name = "chat-" + DateTime.Now.ToString("yyyy-MM-dd");
            if (index > 0) name = name + "-" + index.ToString();
            string path = Path.Combine(folder, name + ".log");
            if (File.Exists(path) && new FileInfo(path).Length > 8L * 1024L * 1024L)
            {
                Open(index + 1);
                return;
            }
            current = path;
        }

        public static void Write(string category, string text)
        {
            string target = current;
            if (target == null) return;
            StringBuilder sb = new StringBuilder();
            sb.Append(DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss"));
            sb.Append(" [");
            sb.Append(category);
            sb.Append("] ");
            if (text != null) sb.Append(text);
            sb.Append("\r\n");
            lock (gate)
            {
                try
                {
                    File.AppendAllText(target, sb.ToString(), Encoding.UTF8);
                }
                catch
                {
                }
            }
        }

        public static void Exception(string where, Exception ex)
        {
            Write("ERROR", where + ": " + (ex == null ? "(нет описания)" : ex.ToString()));
        }
    }

    [StructLayout(LayoutKind.Sequential)]
    internal struct MemoryStatusEx
    {
        public uint dwLength;
        public uint dwMemoryLoad;
        public ulong ullTotalPhys;
        public ulong ullAvailPhys;
        public ulong ullTotalPageFile;
        public ulong ullAvailPageFile;
        public ulong ullTotalVirtual;
        public ulong ullAvailVirtual;
        public ulong ullAvailExtendedVirtual;
    }

    // Чтение метаданных GGUF: обученный контекст и размер KV-кэша на токен.
    internal static class Gguf
    {
        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern bool GlobalMemoryStatusEx(ref MemoryStatusEx status);

        public static long TotalRamBytes()
        {
            try
            {
                MemoryStatusEx m = new MemoryStatusEx();
                m.dwLength = (uint)Marshal.SizeOf(typeof(MemoryStatusEx));
                if (GlobalMemoryStatusEx(ref m)) return (long)m.ullTotalPhys;
            }
            catch
            {
            }
            return 8L * 1024 * 1024 * 1024;
        }

        private static bool IsIntType(uint t)
        {
            return t == 0 || t == 1 || t == 2 || t == 3 || t == 4 || t == 5 || t == 10 || t == 11;
        }

        private static uint ReadUint(BinaryReader br, uint type)
        {
            switch (type)
            {
                case 0: return br.ReadByte();
                case 1: return (uint)(byte)br.ReadSByte();
                case 2: return br.ReadUInt16();
                case 3: return (uint)(ushort)br.ReadInt16();
                case 4: return br.ReadUInt32();
                case 5: return (uint)br.ReadInt32();
                case 10: { ulong v = br.ReadUInt64(); return v > uint.MaxValue ? uint.MaxValue : (uint)v; }
                case 11: { long v2 = br.ReadInt64(); return v2 < 0 ? 0 : (v2 > uint.MaxValue ? uint.MaxValue : (uint)v2); }
                default: throw new InvalidDataException("не целое");
            }
        }

        private static void Skip(BinaryReader br, uint type)
        {
            switch (type)
            {
                case 0: case 1: case 7: br.ReadByte(); return;
                case 2: case 3: br.ReadUInt16(); return;
                case 4: case 5: case 6: br.ReadUInt32(); return;
                case 10: case 11: case 12: br.ReadUInt64(); return;
                case 8:
                    {
                        ulong len = br.ReadUInt64();
                        if (len > 16UL * 1024UL * 1024UL) throw new InvalidDataException("строка");
                        br.BaseStream.Seek((long)len, SeekOrigin.Current);
                        return;
                    }
                case 9:
                    {
                        uint et = br.ReadUInt32();
                        ulong n = br.ReadUInt64();
                        if (n > 100000000UL) throw new InvalidDataException("массив");
                        for (ulong i = 0; i < n; i++) Skip(br, et);
                        return;
                    }
                default: throw new InvalidDataException("тип " + type.ToString());
            }
        }

        private static string ReadString(BinaryReader br)
        {
            ulong len = br.ReadUInt64();
            if (len > 1024UL * 1024UL) throw new InvalidDataException("ключ");
            byte[] b = br.ReadBytes((int)len);
            if (b.Length != (int)len) throw new EndOfStreamException();
            return Encoding.UTF8.GetString(b);
        }

        public static bool TryRead(string path, out int trainContext, out long kvBytesPerToken)
        {
            trainContext = 0;
            kvBytesPerToken = 0;
            try
            {
                using (FileStream fs = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read))
                using (BinaryReader br = new BinaryReader(fs))
                {
                    if (br.ReadUInt32() != 0x46554747) return false;
                    uint version = br.ReadUInt32();
                    if (version < 2 || version > 3) return false;
                    br.ReadUInt64();
                    ulong count = br.ReadUInt64();
                    if (count == 0 || count > 1000000UL) return false;

                    uint train = 0, blocks = 0, heads = 0, embed = 0, keyLen = 0;
                    uint[] kvHeads = null;

                    for (ulong i = 0; i < count; i++)
                    {
                        if (train > 0 && blocks > 0 && kvHeads != null && (keyLen > 0 || embed > 0)) break;
                        string key = ReadString(br);
                        uint type = br.ReadUInt32();
                        bool isInt = IsIntType(type);
                        if (isInt && key.EndsWith(".context_length", StringComparison.Ordinal)) { train = ReadUint(br, type); continue; }
                        if (isInt && key.EndsWith(".block_count", StringComparison.Ordinal)) { blocks = ReadUint(br, type); continue; }
                        if (isInt && key.EndsWith(".attention.head_count", StringComparison.Ordinal)) { heads = ReadUint(br, type); continue; }
                        if (isInt && key.EndsWith(".attention.key_length", StringComparison.Ordinal)) { keyLen = ReadUint(br, type); continue; }
                        if (isInt && key.EndsWith(".embedding_length", StringComparison.Ordinal)) { embed = ReadUint(br, type); continue; }
                        if (key.EndsWith(".attention.head_count_kv", StringComparison.Ordinal))
                        {
                            if (isInt)
                            {
                                kvHeads = new uint[] { ReadUint(br, type) };
                                continue;
                            }
                            if (type == 9)
                            {
                                uint et = br.ReadUInt32();
                                ulong n = br.ReadUInt64();
                                if (IsIntType(et) && n > 0 && n < 4096)
                                {
                                    kvHeads = new uint[(int)n];
                                    for (ulong k = 0; k < n; k++) kvHeads[k] = ReadUint(br, et);
                                    continue;
                                }
                                if (n > 100000000UL) return false;
                                for (ulong k = 0; k < n; k++) Skip(br, et);
                                continue;
                            }
                        }
                        Skip(br, type);
                    }

                    if (train == 0 || blocks == 0) return false;
                    if (heads == 0 && embed > 0 && keyLen > 0) heads = embed / keyLen;
                    long kvTotal = 0;
                    if (kvHeads != null)
                    {
                        for (int i = 0; i < kvHeads.Length; i++) kvTotal += kvHeads[i];
                    }
                    else
                    {
                        kvTotal = heads;
                    }
                    long headDim = keyLen;
                    if (headDim == 0 && heads > 0 && embed > 0) headDim = embed / heads;
                    if (kvTotal <= 0 || headDim <= 0) return false;
                    trainContext = (int)Math.Min(train, 1048576u);
                    // K и V, по 2 байта (fp16) на слой, голову и измерение.
                    kvBytesPerToken = 2L * blocks * kvTotal * headDim * 2L;
                    return true;
                }
            }
            catch
            {
                return false;
            }
        }
    }

    // Мягкие звуки интерфейса: приходящий ответ, отправка, сохранение.
    internal static class Sounds
    {
        [DllImport("winmm.dll")]
        private static extern bool PlaySound(byte[] sound, IntPtr module, uint flags);

        private const uint SndAsync = 0x0001;
        private const uint SndNoDefault = 0x0002;
        private const uint SndMemory = 0x0004;

        private static readonly byte[] incoming;
        private static readonly byte[] outgoing;
        private static readonly byte[] saved;

        static Sounds()
        {
            int rate = 22050;
            List<short> up = new List<short>();
            Tone(up, rate, 587.0, 0.11, 0.16, 0.02);
            Tone(up, rate, 880.0, 0.16, 0.13, 0.0);
            incoming = Wav(up, rate);
            List<short> down = new List<short>();
            Tone(down, rate, 523.0, 0.09, 0.11, 0.0);
            outgoing = Wav(down, rate);
            List<short> ok = new List<short>();
            Tone(ok, rate, 784.0, 0.08, 0.11, 0.0);
            Tone(ok, rate, 1046.0, 0.10, 0.09, 0.0);
            saved = Wav(ok, rate);
        }

        public static void Incoming() { Play(incoming); }
        public static void Outgoing() { Play(outgoing); }
        public static void Saved() { Play(saved); }

        private static void Play(byte[] wav)
        {
            try { PlaySound(wav, IntPtr.Zero, SndMemory | SndAsync | SndNoDefault); }
            catch
            {
            }
        }

        private static void Tone(List<short> buf, int rate, double freq, double seconds, double volume, double pause)
        {
            int n = (int)(rate * seconds);
            for (int i = 0; i < n; i++)
            {
                double t = (double)i / n;
                double env = Math.Min(1.0, t * 8.0) * Math.Min(1.0, (1.0 - t) * 4.0);
                buf.Add((short)(Math.Sin(2.0 * Math.PI * freq * i / rate) * 32767.0 * volume * env));
            }
            int p = (int)(rate * pause);
            for (int i = 0; i < p; i++) buf.Add(0);
        }

        private static byte[] Wav(List<short> samples, int rate)
        {
            int data = samples.Count * 2;
            byte[] b = new byte[44 + data];
            Encoding.ASCII.GetBytes("RIFF").CopyTo(b, 0);
            BitConverter.GetBytes(36 + data).CopyTo(b, 4);
            Encoding.ASCII.GetBytes("WAVEfmt ").CopyTo(b, 8);
            BitConverter.GetBytes(16).CopyTo(b, 16);
            BitConverter.GetBytes((short)1).CopyTo(b, 20);
            BitConverter.GetBytes((short)1).CopyTo(b, 22);
            BitConverter.GetBytes(rate).CopyTo(b, 24);
            BitConverter.GetBytes(rate * 2).CopyTo(b, 28);
            BitConverter.GetBytes((short)2).CopyTo(b, 32);
            BitConverter.GetBytes((short)16).CopyTo(b, 34);
            Encoding.ASCII.GetBytes("data").CopyTo(b, 36);
            BitConverter.GetBytes(data).CopyTo(b, 40);
            for (int i = 0; i < samples.Count; i++) BitConverter.GetBytes(samples[i]).CopyTo(b, 44 + i * 2);
            return b;
        }
    }

    internal static class Program
    {
        [STAThread]
        private static void Main()
        {
            Log.Init(AppDomain.CurrentDomain.BaseDirectory);

            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);
            Application.SetUnhandledExceptionMode(UnhandledExceptionMode.CatchException);
            Application.ThreadException += new ThreadExceptionEventHandler(OnThreadException);
            AppDomain.CurrentDomain.UnhandledException += new UnhandledExceptionEventHandler(OnUnhandled);

            Application.Run(new ChatForm());
        }

        private static void OnThreadException(object sender, ThreadExceptionEventArgs e)
        {
            ReportFatal(e.Exception);
        }

        private static void OnUnhandled(object sender, UnhandledExceptionEventArgs e)
        {
            ReportFatal(e.ExceptionObject as Exception);
        }

        private static void ReportFatal(Exception ex)
        {
            Log.Write("CRASH", ex == null ? "Неизвестная ошибка" : ex.ToString());
            string where = Log.Folder == null ? "папку программы" : "папку " + Log.Folder;
            try
            {
                MessageBox.Show(
                    "Программа столкнулась с ошибкой."
                    + (ex == null ? "" : "\r\n\r\n" + ex.Message)
                    + "\r\n\r\nЗапись сохранена в " + where
                    + ". Отправьте файл журнала разработчику.",
                    "Slonobass agent", MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
            catch
            {
            }
        }
    }
}
