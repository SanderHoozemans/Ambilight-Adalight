using System.Drawing;
using Microsoft.Win32;

namespace Ambilight;

static class Program
{
    public static Icon AppIcon;
    static NotifyIcon _tray;
    static SettingsForm _settings;
    static ToolStripMenuItem _status, _arduino, _login;
    static ToolStripMenuItem[] _modeItems;

    [STAThread]
    static void Main(string[] args)
    {
        using var mutex = new Mutex(true, "Ambilight-single-instance-7c1d", out bool first);
        if (!first) return;

        ApplicationConfiguration.Initialize();
        AppIcon = SystemIcons.Application;
        try { AppIcon = Icon.ExtractAssociatedIcon(Environment.ProcessPath) ?? AppIcon; } catch { }

        Engine.Shared.Start();

        _status = new ToolStripMenuItem { Enabled = false };
        _arduino = new ToolStripMenuItem { Enabled = false };
        var menu = new ContextMenuStrip();
        menu.Items.Add(_status);
        menu.Items.Add(_arduino);
        menu.Items.Add(new ToolStripSeparator());
        string[] kinds = { "off", "ambi", "static", "anim" };
        string[] names = { L.T("Off", "Uit"), "Ambilight", L.T("Static colour", "Statische kleur"), L.T("Animation", "Animatie") };
        _modeItems = new ToolStripMenuItem[4];
        for (int i = 0; i < 4; i++)
        {
            int k = i;
            _modeItems[i] = new ToolStripMenuItem(names[i], null, (_, _) => { Engine.Shared.Update(c => c.Kind = kinds[k]); Engine.Shared.RestoreMode(); });
            menu.Items.Add(_modeItems[i]);
        }
        var bright = new ToolStripMenuItem(L.T("Brightness", "Helderheid"));
        foreach (var pct in new[] { 25, 50, 75, 100 })
        {
            int p = pct;
            bright.DropDownItems.Add(new ToolStripMenuItem(pct + "%", null, (_, _) => Engine.Shared.Update(c => c.Brightness = p / 100.0)));
        }
        menu.Items.Add(bright);
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add(L.T("Settings…", "Instellingen…"), null, (_, _) => ShowSettings());
        menu.Items.Add(L.T("Show screen zones…", "Schermvlakken tonen…"), null, (_, _) => { var f = new ZonesForm(); f.Show(); f.Activate(); });
        menu.Items.Add(L.T("White test screen…", "Wit testscherm…"), null, (_, _) => { var f = new WhiteForm(); f.Show(); f.Activate(); });
        menu.Items.Add(L.T("Export settings…", "Instellingen exporteren…"), null, (_, _) => { ShowSettings(); _settings.ExportSettings(); });
        menu.Items.Add(L.T("Import settings…", "Instellingen importeren…"), null, (_, _) => { ShowSettings(); _settings.ImportSettings(); });
        _login = new ToolStripMenuItem(L.T("Start with Windows", "Starten met Windows"), null, (_, _) => SetAutoStart(!IsAutoStart()));
        menu.Items.Add(_login);
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add(L.T("Quit", "Afsluiten"), null, (_, _) => { Engine.Shared.Shutdown(); _tray.Visible = false; Application.Exit(); });
        menu.Opening += (_, _) =>
        {
            _status.Text = L.T("Screen capture: ", "Schermopname: ") + Engine.Shared.CaptureStatus;
            _arduino.Text = "Arduino: " + Engine.Shared.ArduinoStatus;
            var kind = Engine.Shared.Cfg.Kind;
            for (int i = 0; i < 4; i++) _modeItems[i].Checked = kinds[i] == kind;
            _login.Checked = IsAutoStart();
        };

        _tray = new NotifyIcon { Icon = AppIcon, Text = "Ambilight", Visible = true, ContextMenuStrip = menu };
        _tray.MouseClick += (_, e) => { if (e.Button == MouseButtons.Left) ShowSettings(); };

        // Eerste keer starten (nog geen LEDs ingesteld) of niet automatisch gestart: instellingen tonen.
        if (Engine.Shared.Cfg.Total == 0 || !args.Contains("--auto")) ShowSettings();

        Application.ApplicationExit += (_, _) => { };
        Application.Run();
    }

    static void ShowSettings()
    {
        if (_settings == null || _settings.IsDisposed) _settings = new SettingsForm();
        _settings.Show();
        _settings.WindowState = FormWindowState.Normal;
        _settings.Activate();
    }

    const string RunKey = @"Software\Microsoft\Windows\CurrentVersion\Run";

    static bool IsAutoStart()
    {
        using var k = Registry.CurrentUser.OpenSubKey(RunKey);
        return k?.GetValue("Ambilight") != null;
    }

    static void SetAutoStart(bool on)
    {
        using var k = Registry.CurrentUser.OpenSubKey(RunKey, true) ?? Registry.CurrentUser.CreateSubKey(RunKey);
        if (on) k.SetValue("Ambilight", $"\"{Environment.ProcessPath}\" --auto");
        else k.DeleteValue("Ambilight", false);
    }
}
