using System.Drawing;
using System.Drawing.Drawing2D;

namespace Ambilight;

// Schermvlakken over het hele scherm (zoals Prismatik): klik een vlak om die LED te laten branden.
public sealed class ZonesForm : Form
{
    readonly Engine _eng = Engine.Shared;
    int _selected = -1;
    readonly System.Windows.Forms.Timer _timer = new() { Interval = 50 };

    public ZonesForm()
    {
        FormBorderStyle = FormBorderStyle.None;
        StartPosition = FormStartPosition.Manual;
        Bounds = ScreenGrabber.ScreenBounds(_eng.Cfg.Display);
        TopMost = true;
        ShowInTaskbar = false;
        BackColor = Color.Black;
        Opacity = 0.9;
        DoubleBuffered = true;
        KeyPreview = true;
        _timer.Tick += (_, _) => Invalidate();
        _timer.Start();
        FormClosed += (_, _) => { _timer.Stop(); _eng.RestoreMode(); };
        KeyDown += OnKey;
        MouseDown += OnMouse;
    }

    void OnKey(object s, KeyEventArgs e)
    {
        int step = e.Shift ? 10 : 1;
        switch (e.KeyCode)
        {
            case Keys.Escape: Close(); break;
            case Keys.Left: _eng.Update(c => c.Offset -= step); break;
            case Keys.Right: _eng.Update(c => c.Offset += step); break;
            case Keys.R: _eng.Update(c => c.Reversed = !c.Reversed); break;
            case Keys.W: _selected = -1; _eng.SetMode(Mode.White); break;
            case Keys.S: _selected = -1; _eng.SetMode(Mode.Sides); break;
            case Keys.L: _selected = -1; _eng.RestoreMode(); break;
        }
        Invalidate();
    }

    void OnMouse(object s, MouseEventArgs e)
    {
        var c = _eng.Cfg; int n = c.Total;
        for (int i = 0; i < n; i++)
            if (ZoneRect(i, c).Contains(e.Location)) { _selected = i; _eng.SetMode(Mode.Single, i); Invalidate(); return; }
        _selected = -1; _eng.RestoreMode();
    }

    Rectangle ZoneRect(int led, Config c)
    {
        int n = c.Total;
        int p = Layout.PerimeterIndex(led, n, c);
        var (x0, y0, x1, y1) = Layout.Zone(p, c, ClientSize.Width, ClientSize.Height);
        return Rectangle.FromLTRB(x0, y0, x1, y1);
    }

    protected override void OnPaint(PaintEventArgs e)
    {
        var g = e.Graphics;
        var c = _eng.Cfg; int n = c.Total;
        g.SmoothingMode = SmoothingMode.AntiAlias;
        using var f = new Font("Segoe UI", 8f);
        var disp = _eng.DisplayColors();
        Color[] sideCols = { Color.FromArgb(70, 120, 255), Color.FromArgb(70, 200, 120), Color.FromArgb(255, 170, 60), Color.FromArgb(200, 90, 200) };
        for (int i = 0; i < n; i++)
        {
            var r = ZoneRect(i, c);
            int side = Layout.Locate(Layout.PerimeterIndex(i, n, c), c).side;
            Color fill = disp.Length >= 3 * n && (disp[3 * i] + disp[3 * i + 1] + disp[3 * i + 2]) > 0
                ? Color.FromArgb(disp[3 * i], disp[3 * i + 1], disp[3 * i + 2]) : sideCols[side];
            using var br = new SolidBrush(Color.FromArgb(i == _selected ? 255 : 150, fill));
            g.FillRectangle(br, r);
            using var pen = new Pen(i == 0 ? Color.White : Color.FromArgb(180, 255, 255, 255), i == 0 ? 3 : 1);
            g.DrawRectangle(pen, r);
            if (r.Width > 18 && r.Height > 14 || n < 60) g.DrawString((i + 1).ToString(), f, Brushes.White, r.X + 2, r.Y + 2);
        }
        string help = L.T("Click a zone to light that LED   ·   ←/→ shift (Shift = 10)   ·   R reverse   ·   S sides test   ·   W all white   ·   L live   ·   Esc close",
                          "Klik een vlak om die LED te laten branden   ·   ←/→ verschuiven (Shift = 10)   ·   R omkeren   ·   S zijden-test   ·   W alles wit   ·   L live   ·   Esc sluiten");
        using var hf = new Font("Segoe UI", 11f, FontStyle.Bold);
        var sz = g.MeasureString(help, hf);
        g.FillRectangle(new SolidBrush(Color.FromArgb(200, 0, 0, 0)), (ClientSize.Width - sz.Width) / 2 - 12, ClientSize.Height / 2 - 20, sz.Width + 24, sz.Height + 20);
        g.DrawString(help, hf, Brushes.White, (ClientSize.Width - sz.Width) / 2, ClientSize.Height / 2 - 10);
        string info = L.T($"Offset: {c.Offset}   Reversed: {(c.Reversed ? "yes" : "no")}   LEDs: {n}", $"Offset: {c.Offset}   Omgekeerd: {(c.Reversed ? "ja" : "nee")}   LEDs: {n}");
        g.DrawString(info, hf, Brushes.White, ClientSize.Width / 2 - 140, ClientSize.Height / 2 + 30);
    }
}

// Helder wit scherm om de witbalans te beoordelen, met schuifjes voor R, G en B.
public sealed class WhiteForm : Form
{
    readonly Engine _eng = Engine.Shared;

    public WhiteForm()
    {
        FormBorderStyle = FormBorderStyle.None;
        StartPosition = FormStartPosition.Manual;
        Bounds = ScreenGrabber.ScreenBounds(_eng.Cfg.Display);
        TopMost = true;
        ShowInTaskbar = false;
        BackColor = Color.White;
        KeyPreview = true;
        KeyDown += (_, e) => { if (e.KeyCode == Keys.Escape) Close(); };

        var panel = new Panel { Width = 460, Height = 250, BackColor = Color.FromArgb(235, 235, 240), BorderStyle = BorderStyle.FixedSingle };
        panel.Left = (ClientSize.Width - panel.Width) / 2;
        panel.Top = (ClientSize.Height - panel.Height) / 2;
        Controls.Add(panel);
        var c = _eng.Cfg;
        int y = 12;
        panel.Controls.Add(new Label { Text = L.T("White balance test – compare the LED light to this white screen", "Witbalans-test – vergelijk het LED-licht met dit witte scherm"), Left = 12, Top = y, Width = 430, Height = 34, Font = new Font("Segoe UI", 9.5f, FontStyle.Bold) });
        y += 40;
        TrackBar Row(string name, double v, Action<double> set)
        {
            panel.Controls.Add(new Label { Text = name, Left = 12, Top = y + 6, Width = 20 });
            var tb = new TrackBar { Left = 36, Top = y, Width = 340, Minimum = 20, Maximum = 100, TickStyle = TickStyle.None, Value = (int)Math.Round(Math.Clamp(v, 0.2, 1) * 100) };
            var lab = new Label { Left = 382, Top = y + 6, Width = 60, Text = tb.Value + "%" };
            tb.ValueChanged += (_, _) => { lab.Text = tb.Value + "%"; set(tb.Value / 100.0); };
            panel.Controls.Add(tb); panel.Controls.Add(lab);
            y += 42;
            return tb;
        }
        var r = Row("R", c.WbR, v => _eng.Update(x => x.WbR = v));
        var g = Row("G", c.WbG, v => _eng.Update(x => x.WbG = v));
        var b = Row("B", c.WbB, v => _eng.Update(x => x.WbB = v));
        void Preset(double rr, double gg, double bb) { r.Value = (int)(rr * 100); g.Value = (int)(gg * 100); b.Value = (int)(bb * 100); }
        int x = 12;
        Button Btn(string text, Action a) { var bt = new Button { Text = text, Left = x, Top = y, Width = 100, Height = 28 }; bt.Click += (_, _) => a(); panel.Controls.Add(bt); x += 108; return bt; }
        Btn(L.T("Neutral", "Neutraal"), () => Preset(1, 1, 1));
        Btn(L.T("Warmer", "Warmer"), () => Preset(1, 0.85, 0.6));
        Btn(L.T("Cooler", "Koeler"), () => Preset(0.8, 0.95, 1));
        Btn(L.T("Done", "Klaar"), Close);

        _eng.SetMode(Mode.White);
        FormClosed += (_, _) => _eng.RestoreMode();
    }
}
