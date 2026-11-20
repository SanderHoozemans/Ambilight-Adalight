using System.Drawing;
using System.IO.Ports;

namespace Ambilight;

public sealed class SettingsForm : Form
{
    readonly Engine _eng = Engine.Shared;
    readonly FlowLayoutPanel _flow;
    readonly Label _capLabel = new() { AutoSize = true };
    readonly Label _ardLabel = new() { AutoSize = true };
    readonly Label _totalLabel = new() { AutoSize = true };
    readonly System.Windows.Forms.Timer _timer = new() { Interval = 500 };
    bool _building;

    public SettingsForm()
    {
        Text = "Ambilight";
        Icon = Program.AppIcon;
        StartPosition = FormStartPosition.CenterScreen;
        ClientSize = new Size(560, 780);
        MinimumSize = new Size(480, 400);
        Font = new Font("Segoe UI", 9f);
        _flow = new FlowLayoutPanel { Dock = DockStyle.Fill, FlowDirection = FlowDirection.TopDown, WrapContents = false, AutoScroll = true, Padding = new Padding(16) };
        Controls.Add(_flow);
        Build();
        _timer.Tick += (_, _) => RefreshStatus();
        _timer.Start();
        FormClosed += (_, _) => { _timer.Stop(); _eng.RestoreMode(); };
    }

    // ---------- bouwstenen ----------

    void Header(string text)
    {
        _flow.Controls.Add(new Label { Text = text, AutoSize = true, Font = new Font(Font, FontStyle.Bold), Margin = new Padding(0, 14, 0, 4) });
    }

    Control Row(string title, Control c, int labelWidth = 190)
    {
        var p = new FlowLayoutPanel { AutoSize = true, FlowDirection = FlowDirection.LeftToRight, WrapContents = false, Margin = new Padding(0, 1, 0, 1) };
        p.Controls.Add(new Label { Text = title, Width = labelWidth, TextAlign = ContentAlignment.MiddleLeft, Height = 28 });
        p.Controls.Add(c);
        _flow.Controls.Add(p);
        return p;
    }

    void Slider(string title, double lo, double hi, double value, Action<Config, double> set)
    {
        var tb = new TrackBar { Width = 250, Height = 32, Minimum = 0, Maximum = 1000, TickStyle = TickStyle.None, Value = ToTb(value, lo, hi) };
        var val = new Label { Width = 56, TextAlign = ContentAlignment.MiddleLeft, Height = 28, Text = value.ToString("0.00") };
        tb.ValueChanged += (_, _) =>
        {
            double v = lo + (hi - lo) * tb.Value / 1000.0;
            val.Text = v.ToString("0.00");
            if (!_building) _eng.Update(c => set(c, v));
        };
        var p = new FlowLayoutPanel { AutoSize = true, WrapContents = false, Margin = new Padding(0) };
        p.Controls.Add(tb); p.Controls.Add(val);
        Row(title, p);
    }

    static int ToTb(double v, double lo, double hi) => (int)Math.Round(Math.Clamp((v - lo) / (hi - lo), 0, 1) * 1000);

    void Num(string title, int value, int max, Action<Config, int> set)
    {
        var n = new NumericUpDown { Minimum = 0, Maximum = max, Value = Math.Clamp(value, 0, max), Width = 80 };
        n.ValueChanged += (_, _) => { if (!_building) { _eng.Update(c => set(c, (int)n.Value)); UpdateTotal(); } };
        Row(title, n);
    }

    Button Btn(string text, Action a, int w = 150)
    {
        var b = new Button { Text = text, Width = w, Height = 28, Margin = new Padding(0, 2, 8, 2) };
        b.Click += (_, _) => a();
        return b;
    }

    void Buttons(params Button[] bs)
    {
        var p = new FlowLayoutPanel { AutoSize = true, WrapContents = true, Width = 520, Margin = new Padding(0) };
        p.Controls.AddRange(bs);
        _flow.Controls.Add(p);
    }

    void UpdateTotal() => _totalLabel.Text = L.T($"Total: {_eng.Cfg.Total} LEDs", $"Totaal: {_eng.Cfg.Total} LEDs");

    // ---------- opbouw ----------

    void Build()
    {
        _building = true;
        _flow.SuspendLayout();
        _flow.Controls.Clear();
        var c = _eng.Cfg;

        Header(L.T("Mode", "Modus"));
        var modes = new ComboBox { DropDownStyle = ComboBoxStyle.DropDownList, Width = 200 };
        string[] kinds = { "off", "ambi", "static", "anim" };
        modes.Items.AddRange(new object[] { L.T("Off", "Uit"), "Ambilight", L.T("Static colour", "Statische kleur"), L.T("Animation", "Animatie") });
        modes.SelectedIndex = Math.Max(0, Array.IndexOf(kinds, c.Kind));
        modes.SelectedIndexChanged += (_, _) => { if (_building) return; _eng.Update(x => x.Kind = kinds[modes.SelectedIndex]); _eng.RestoreMode(); };
        Row(L.T("Mode", "Modus"), modes);

        var colorBtn = new Button { Width = 120, Height = 26, BackColor = Color.FromArgb((int)(c.StaticR * 255), (int)(c.StaticG * 255), (int)(c.StaticB * 255)), Text = "" };
        colorBtn.Click += (_, _) =>
        {
            using var d = new ColorDialog { Color = colorBtn.BackColor, FullOpen = true };
            if (d.ShowDialog(this) != DialogResult.OK) return;
            colorBtn.BackColor = d.Color;
            _eng.Update(x => { x.StaticR = d.Color.R / 255.0; x.StaticG = d.Color.G / 255.0; x.StaticB = d.Color.B / 255.0; });
        };
        Row(L.T("Static colour", "Statische kleur"), colorBtn);

        var anim = new ComboBox { DropDownStyle = ComboBoxStyle.DropDownList, Width = 200 };
        anim.Items.AddRange(LedLayout.AnimNames);
        anim.SelectedItem = c.Anim;
        anim.SelectedIndexChanged += (_, _) => { if (!_building) _eng.Update(x => x.Anim = (string)anim.SelectedItem); };
        Row(L.T("Animation", "Animatie"), anim);
        Slider(L.T("Animation speed", "Animatiesnelheid"), 0.2, 3, c.AnimSpeed, (x, v) => x.AnimSpeed = v);

        Header(L.T("Status", "Status"));
        _flow.Controls.Add(_capLabel);
        _flow.Controls.Add(_ardLabel);

        Header(L.T("1. LEDs per side (as seen from the front of the screen)", "1. Aantal LEDs per zijde (kijk naar de voorkant van het scherm)"));
        Num(L.T("Top", "Boven"), c.Top, 999, (x, v) => x.Top = v);
        Num(L.T("Right", "Rechts"), c.Right, 999, (x, v) => x.Right = v);
        Num(L.T("Bottom", "Onder"), c.Bottom, 999, (x, v) => x.Bottom = v);
        Num(L.T("Left", "Links"), c.Left, 999, (x, v) => x.Left = v);
        _flow.Controls.Add(_totalLabel);
        UpdateTotal();

        Header(L.T("2. Position and test", "2. Positie en test"));
        Buttons(
            Btn(L.T("Show screen zones…", "Schermvlakken tonen…"), () => { var f = new ZonesForm(); f.Show(); f.Activate(); }, 190),
            Btn(L.T("White test screen…", "Wit testscherm…"), () => { var f = new WhiteForm(); f.Show(); f.Activate(); }, 190));
        var single = new TrackBar { Width = 250, Minimum = 0, Maximum = Math.Max(1, c.Total - 1), TickStyle = TickStyle.None };
        var singleLab = new Label { Width = 60, Height = 28, TextAlign = ContentAlignment.MiddleLeft, Text = "–" };
        single.ValueChanged += (_, _) => { singleLab.Text = (single.Value + 1).ToString(); if (!_building) _eng.SetMode(Mode.Single, single.Value); };
        var sp = new FlowLayoutPanel { AutoSize = true, WrapContents = false, Margin = new Padding(0) };
        sp.Controls.Add(single); sp.Controls.Add(singleLab);
        Row(L.T("Light single LED", "Eén LED laten branden"), sp);
        Buttons(
            Btn(L.T("Sides test", "Zijden-test"), () => _eng.SetMode(Mode.Sides), 110),
            Btn(L.T("Chase", "Looplicht"), () => _eng.SetMode(Mode.Chase), 110),
            Btn(L.T("All white", "Alles wit"), () => _eng.SetMode(Mode.White), 110),
            Btn(L.T("Back to normal", "Terug naar normaal"), () => _eng.RestoreMode(), 130));

        Header(L.T("3. Position of LED 1", "3. Positie van LED 1"));
        Num(L.T("Offset (shift)", "Verschuiving"), c.Offset, 999, (x, v) => x.Offset = v);
        var rev = new CheckBox { Text = L.T("Reverse direction", "Richting omkeren"), Checked = c.Reversed, AutoSize = true };
        rev.CheckedChanged += (_, _) => { if (!_building) _eng.Update(x => x.Reversed = rev.Checked); };
        _flow.Controls.Add(rev);

        Header(L.T("4. Hardware", "4. Hardware"));
        var order = new ComboBox { DropDownStyle = ComboBoxStyle.DropDownList, Width = 100 };
        order.Items.AddRange(new object[] { "RGB", "RBG", "GRB", "GBR", "BRG", "BGR" });
        order.SelectedItem = c.ColorOrder;
        order.SelectedIndexChanged += (_, _) => { if (!_building) _eng.Update(x => x.ColorOrder = (string)order.SelectedItem); };
        Row(L.T("Colour order", "Kleurvolgorde"), order);

        var baud = new ComboBox { DropDownStyle = ComboBoxStyle.DropDown, Width = 120 };
        baud.Items.AddRange(new object[] { "115200", "230400", "500000", "1000000" });
        baud.Text = c.Baud.ToString();
        baud.TextChanged += (_, _) => { if (!_building && int.TryParse(baud.Text, out var b) && b >= 1200) _eng.Update(x => x.Baud = b); };
        Row("Baud", baud);

        var port = new ComboBox { DropDownStyle = ComboBoxStyle.DropDownList, Width = 140 };
        void FillPorts()
        {
            port.Items.Clear();
            port.Items.Add(L.T("Automatic", "Automatisch"));
            foreach (var p in SerialLink.AvailablePorts()) port.Items.Add(p);
            var cur = _eng.Cfg.Port;
            port.SelectedIndex = string.IsNullOrEmpty(cur) ? 0 : Math.Max(0, port.Items.IndexOf(cur));
        }
        FillPorts();
        port.DropDown += (_, _) => { var keep = port.SelectedItem; FillPorts(); };
        port.SelectedIndexChanged += (_, _) => { if (!_building) _eng.Update(x => x.Port = port.SelectedIndex <= 0 ? "" : (string)port.SelectedItem); };
        Row(L.T("Serial port", "Seriële poort"), port);

        var scr = new ComboBox { DropDownStyle = ComboBoxStyle.DropDownList, Width = 260 };
        for (int i = 0; i < Screen.AllScreens.Length; i++)
        {
            var b = Screen.AllScreens[i].Bounds;
            scr.Items.Add($"{i + 1}: {b.Width}×{b.Height}" + (Screen.AllScreens[i].Primary ? L.T(" (main)", " (hoofdscherm)") : ""));
        }
        scr.SelectedIndex = Math.Clamp(c.Display, 0, scr.Items.Count - 1);
        scr.SelectedIndexChanged += (_, _) => { if (!_building) _eng.Update(x => x.Display = scr.SelectedIndex); };
        Row(L.T("Display to capture", "Scherm om op te nemen"), scr);

        Header(L.T("Picture", "Beeld"));
        Slider(L.T("Brightness", "Helderheid"), 0, 1, c.Brightness, (x, v) => x.Brightness = v);
        Slider(L.T("Saturation", "Verzadiging"), 0, 2, c.Saturation, (x, v) => x.Saturation = v);
        Slider(L.T("Gamma", "Gamma"), 0.8, 3, c.Gamma, (x, v) => x.Gamma = v);
        Slider(L.T("Colour boost", "Kleurversterking"), 1, 3, c.Boost, (x, v) => x.Boost = v);
        Slider(L.T("Colour intensity", "Kleurintensiteit"), 0, 1, c.Vivid, (x, v) => x.Vivid = v);
        Slider(L.T("Smoothing", "Vloeiendheid"), 0, 1, c.Smoothing, (x, v) => x.Smoothing = v);
        Slider(L.T("Anti-flicker", "Anti-flikker"), 0, 1, c.AntiFlicker, (x, v) => x.AntiFlicker = v);
        Slider(L.T("Black level", "Zwartdrempel"), 0, 0.3, c.BlackLevel, (x, v) => x.BlackLevel = v);
        Slider(L.T("Zone depth", "Diepte van de zone"), 0.03, 0.4, c.Depth, (x, v) => x.Depth = v);
        var bars = new CheckBox { Text = L.T("Ignore black bars (letterbox)", "Zwarte balken negeren"), Checked = c.IgnoreBars, AutoSize = true };
        bars.CheckedChanged += (_, _) => { if (!_building) _eng.Update(x => x.IgnoreBars = bars.Checked); };
        _flow.Controls.Add(bars);

        Header(L.T("White balance", "Witbalans"));
        Slider("R", 0.2, 1, c.WbR, (x, v) => x.WbR = v);
        Slider("G", 0.2, 1, c.WbG, (x, v) => x.WbG = v);
        Slider("B", 0.2, 1, c.WbB, (x, v) => x.WbB = v);

        Header(L.T("Share settings (macOS ↔ Windows)", "Instellingen delen (macOS ↔ Windows)"));
        Buttons(
            Btn(L.T("Export…", "Exporteren…"), ExportSettings, 120),
            Btn(L.T("Import…", "Importeren…"), ImportSettings, 120));

        _flow.ResumeLayout();
        _building = false;
        RefreshStatus();
    }

    void RefreshStatus()
    {
        _capLabel.Text = L.T("Screen capture: ", "Schermopname: ") + _eng.CaptureStatus;
        _ardLabel.Text = "Arduino: " + _eng.ArduinoStatus;
    }

    public void ExportSettings()
    {
        using var d = new SaveFileDialog { Filter = "Ambilight (*.json)|*.json", FileName = "ambilight-settings.json", Title = L.T("Export Ambilight settings", "Ambilight-instellingen exporteren") };
        if (d.ShowDialog(this) != DialogResult.OK) return;
        try { File.WriteAllText(d.FileName, ConfigStore.Export(_eng.Cfg)); }
        catch (Exception ex) { MessageBox.Show(this, ex.Message, "Ambilight", MessageBoxButtons.OK, MessageBoxIcon.Error); }
    }

    public void ImportSettings()
    {
        using var d = new OpenFileDialog { Filter = "Ambilight (*.json)|*.json", Title = L.T("Import Ambilight settings", "Ambilight-instellingen importeren") };
        if (d.ShowDialog(this) != DialogResult.OK) return;
        try
        {
            var c = ConfigStore.Import(File.ReadAllText(d.FileName), _eng.Cfg);
            _eng.Replace(c);
            Build();
        }
        catch
        {
            MessageBox.Show(this, L.T("This is not a valid Ambilight settings file.", "Dit is geen geldig Ambilight-instellingenbestand."), "Ambilight", MessageBoxButtons.OK, MessageBoxIcon.Warning);
        }
    }
}
