using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Media;
using System.Net;
using System.Security.Cryptography;
using System.Text;
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
            Text = "OpenCode — чат";
            StartPosition = FormStartPosition.CenterScreen;
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
            transcript.DetectUrls = false;
            transcript.ShortcutsEnabled = true;
            transcript.AccessibleName = "Переписка";
            transcript.KeyDown += TranscriptKeyDown;
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

            Controls.Add(main);

            tick = new System.Windows.Forms.Timer();
            tick.Interval = 1000;
            tick.Tick += delegate
            {
                elapsed++;
                if (loadingOffline)
                    statusLabel.Text = "Загружаю офлайн-модель… " + elapsed.ToString() + " с";
                else
                    statusLabel.Text = "OpenCode отвечает… " + elapsed.ToString() + " с";
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
                    "Не найден движок engine\\opencode.exe.\r\nРаспакуйте архив целиком в одну папку и запускайте OpenCode-Chat.exe из неё.",
                    "OpenCode — чат", MessageBoxButtons.OK, MessageBoxIcon.Error);
                Close();
                return;
            }
            Log.Write("START", "Движок: " + exePath + "; рабочая папка: " + projectsDir + "; Загрузки: " + downloadsDir
                + "; профиль DeepSeek: " + (Profile.HasKey ? "подключён " + Profile.Hint : "нет"));
            if (Profile.HasKey && statusLabel.Text == "Готов") statusLabel.Text = "Готов. Мой профиль DeepSeek подключён: " + Profile.Hint;
            input.Focus();
            LoadModels();
        }

        protected override void OnFormClosing(FormClosingEventArgs e)
        {
            if (busy)
            {
                DialogResult r = MessageBox.Show(this,
                    "OpenCode ещё отвечает. Закрыть окно?",
                    "OpenCode — чат", MessageBoxButtons.YesNo, MessageBoxIcon.Question);
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

        // ---------- hotkeys ----------

        private void FormKeyDown(object sender, KeyEventArgs e)
        {
            if (e.KeyCode == Keys.F1)
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
            if (e.Control || e.Shift || e.Alt) return;
            if (e.KeyCode == Keys.Home)
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
                statusLabel.Text = "OpenCode ещё отвечает. Подождите.";
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
                    "OpenCode — чат", MessageBoxButtons.OK, MessageBoxIcon.Information);
                input.Focus();
                return;
            }

            if (model.StartsWith("deepseek/", StringComparison.OrdinalIgnoreCase) && !Profile.HasKey)
            {
                statusLabel.Text = "Для модели из «Мой профиль» нужен ключ DeepSeek.";
                MessageBox.Show(this,
                    "Выбрана модель из раздела «Мой профиль», но ключ DeepSeek ещё не подключён.\r\n"
                    + "Нажмите кнопку «Мой профиль…» и вставьте свой ключ, либо выберите бесплатную модель.",
                    "OpenCode — чат", MessageBoxButtons.OK, MessageBoxIcon.Information);
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

            input.Text = "";
            SetBusy(true);
            statusLabel.Text = "OpenCode отвечает… 0 с";
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

                    Log.Write("RUN", "opencode " + psi.Arguments.Replace("\r\n", "\\n").Replace("\n", "\\n")
                        + " [профиль: " + (Profile.HasKey ? "свой ключ" : "бесплатные") + "]");

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

                string attemptErrors;
                lock (eb) { attemptErrors = eb.ToString(); }
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
            SetBusy(false);
            if (sessionId == null && sid != null) sessionId = sid;

            string time = DateTime.Now.ToString("HH:mm");
            string answerText = answer.Trim();
            if (answerText.Length == 0)
            {
                answerText = "(ответа нет)";
                if (exit != 0)
                {
                    answerText = "Не получилось получить ответ.";
                }
                if (errors.Trim().Length > 0)
                {
                    answerText += "\r\nПодробности: " + Shorten(errors.Trim(), 1200);
                }
            }

            int start = transcript.TextLength;
            string who = "OpenCode";
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

            transcript.SelectionStart = FirstText(start);
            transcript.SelectionLength = 0;
            transcript.ScrollToCaret();
            transcript.Focus();
            try { SystemSounds.Asterisk.Play(); } catch { }
        }

        private void SetBusy(bool value)
        {
            busy = value;
            detachBtn.Enabled = !value && pending.Count > 0;
            newChatBtn.Enabled = !value;
            // Выбор модели не отключаем: отключённый элемент экранный диктор
            // пропускает, и кажется, что список моделей исчез.
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
                try { SystemSounds.Asterisk.Play(); } catch { }
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
                    + "; профиль DeepSeek: " + (Profile.HasKey ? "подключён " + Profile.Hint : "нет"));
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
            List<string> free = new List<string>();
            for (int i = 0; i < found.Count; i++)
            {
                // Провайдер offline движок показывает в своём списке, но пункты
                // для офлайн-файлов строим сами: у движка это одна модель без файла.
                if (found[i].StartsWith("offline/", StringComparison.OrdinalIgnoreCase)) continue;
                if (found[i].StartsWith("deepseek/", StringComparison.OrdinalIgnoreCase)) mine.Add(found[i]);
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

        private void WriteOfflineConfig()
        {
            try
            {
                string path = Path.Combine(projectsDir, "opencode.json");
                string url = "http://127.0.0.1:" + OfflinePort.ToString() + "/v1";
                StringBuilder sb = new StringBuilder();
                sb.AppendLine("{");
                sb.AppendLine("  \"$schema\": \"https://opencode.ai/config.json\",");
                sb.AppendLine("  \"model\": \"opencode/deepseek-v4.1-flash-free\",");
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
                sb.AppendLine("          \"limit\": { \"context\": 16384, \"output\": 1024 }");
                sb.AppendLine("        }");
                sb.AppendLine("      }");
                sb.AppendLine("    }");
                sb.AppendLine("  }");
                sb.AppendLine("}");
                File.WriteAllText(path, sb.ToString(), new UTF8Encoding(false));
                Log.Write("OFFLINE", "Конфиг движка записан: " + path);
            }
            catch (Exception ex)
            {
                Log.Exception("Конфиг движка", ex);
            }
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
            if (alive && OfflineReady()) return true;
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

            SetStatusSafe("Запускаю офлайн-модель…");
            ProcessStartInfo psi = new ProcessStartInfo(exe);
            psi.Arguments = "-m " + Quote(gguf)
                + " --host 127.0.0.1 --port " + OfflinePort.ToString()
                + " -c 16384 --parallel 1 --alias local --jinja";
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
                    SetStatusSafe("Офлайн-модель готова, отправляю запрос…");
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
                    "OpenCode — чат", MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
            catch
            {
            }
        }
    }
}
