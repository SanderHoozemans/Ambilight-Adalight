using System.Diagnostics;

namespace Ambilight;

public enum Mode { Off, Ambi, Sides, Chase, White, Static, Anim, Single }

public static class Layout
{
    public static readonly string[] AnimNames = { "Regenboog", "Kleurwissel", "Ademen", "Looplicht", "Vuur" };

    public static int PerimeterIndex(int i, int n, Config c)
    {
        int step = c.Reversed ? -i : i;
        return (((c.Offset + step) % n) + n) % n;
    }

    public static (int side, int k, int cnt) Locate(int p, Config c)
    {
        int[] counts = { c.Top, c.Right, c.Bottom, c.Left };
        int q = p;
        for (int s = 0; s < 4; s++)
        {
            if (q < counts[s]) return (s, q, counts[s]);
            q -= counts[s];
        }
        return (0, 0, Math.Max(1, c.Top));
    }

    // Zone (in schermpixels van een w×h-beeld) voor perimeter-index p, hetzelfde als bij de opname.
    public static (int x0, int y0, int x1, int y1) Zone(int p, Config c, int w, int h, int ox = 0, int oy = 0, int cw = -1, int ch = -1)
    {
        if (cw < 0) cw = w;
        if (ch < 0) ch = h;
        int d = Math.Max(1, (int)(c.Depth * ch));
        var (s, k, cnt) = Locate(p, c);
        int x0, x1, y0, y1;
        switch (s)
        {
            case 0: x0 = ox + k * cw / cnt; x1 = ox + (k + 1) * cw / cnt; y0 = oy; y1 = oy + d; break;
            case 1: x0 = ox + cw - d; x1 = ox + cw; y0 = oy + k * ch / cnt; y1 = oy + (k + 1) * ch / cnt; break;
            case 2: x0 = ox + cw - (k + 1) * cw / cnt; x1 = ox + cw - k * cw / cnt; y0 = oy + ch - d; y1 = oy + ch; break;
            default: x0 = ox; x1 = ox + d; y0 = oy + ch - (k + 1) * ch / cnt; y1 = oy + ch - k * ch / cnt; break;
        }
        x0 = Math.Max(0, Math.Min(w - 1, x0)); y0 = Math.Max(0, Math.Min(h - 1, y0));
        x1 = Math.Max(x0 + 1, Math.Min(w, x1)); y1 = Math.Max(y0 + 1, Math.Min(h, y1));
        return (x0, y0, x1, y1);
    }
}

public sealed class Engine
{
    public static readonly Engine Shared = new();

    readonly object _lock = new();
    Config _cfg = ConfigStore.Load();
    Mode _mode = Mode.Ambi;
    int _single;
    int _frames;
    float[] _target = Array.Empty<float>();
    byte[] _disp = Array.Empty<byte>();

    public string ArduinoStatus = L.T("Searching…","Zoeken…");
    public string CaptureStatus = L.T("Starting…","Starten…");
    public event Action ConfigChanged;

    readonly SerialLink _serial = new();
    readonly List<int>[] _barHist = { new(), new(), new(), new() };
    float[] _cur = Array.Empty<float>();
    float[] _held = Array.Empty<float>();
    DateTime _openedAt = DateTime.MinValue, _lastTry = DateTime.MinValue;
    readonly Stopwatch _clock = Stopwatch.StartNew();
    volatile bool _quit;
    Thread _outThread, _capThread;
    int _sentFrames;
    System.Threading.Timer _saveTimer;

    public Config Cfg
    {
        get { lock (_lock) return _cfg.Clone(); }
    }

    public void Update(Action<Config> f)
    {
        lock (_lock) { f(_cfg); }
        ScheduleSave();
        ConfigChanged?.Invoke();
    }

    public void Replace(Config c)
    {
        lock (_lock) _cfg = c;
        ScheduleSave();
        RestoreMode();
        ConfigChanged?.Invoke();
    }

    void ScheduleSave()
    {
        _saveTimer?.Dispose();
        _saveTimer = new System.Threading.Timer(_ => ConfigStore.Save(Cfg), null, 400, Timeout.Infinite);
    }

    public Mode CurrentMode { get { lock (_lock) return _mode; } }
    public int SingleLed { get { lock (_lock) return _single; } }
    public int Frames { get { lock (_lock) return _frames; } }
    public byte[] DisplayColors() { lock (_lock) return _disp; }

    public void SetMode(Mode m, int single = 0) { lock (_lock) { _mode = m; _single = single; } }

    public void RestoreMode()
    {
        var k = Cfg.Kind;
        SetMode(k switch { "off" => Mode.Off, "static" => Mode.Static, "anim" => Mode.Anim, _ => Mode.Ambi });
    }

    public void Start()
    {
        RestoreMode();
        _outThread = new Thread(OutputLoop) { IsBackground = true, Name = "ambilight-output", Priority = ThreadPriority.AboveNormal };
        _outThread.Start();
        _capThread = new Thread(CaptureLoop) { IsBackground = true, Name = "ambilight-capture" };
        _capThread.Start();
    }

    public void Shutdown()
    {
        SetMode(Mode.Off);
        Thread.Sleep(300);              // output-thread stuurt nog een zwart frame
        _quit = true;
        ConfigStore.Save(Cfg);
        _serial.Close();
    }

    // ---------------- Schermopname ----------------

    void CaptureLoop()
    {
        using var grab = new ScreenGrabber();
        var sw = new Stopwatch();
        while (!_quit)
        {
            sw.Restart();
            if (CurrentMode != Mode.Ambi)
            {
                CaptureStatus = Cfg.Kind != "ambi" ? L.T("Not needed in this mode","Niet nodig in deze modus") : L.T("Paused","Pauze");
                Thread.Sleep(100);
                continue;
            }
            bool ok = false;
            try { ok = grab.Grab(Cfg.Display); } catch { }
            if (ok)
            {
                Process(grab.Frame, ScreenGrabber.Width, grab.Height);
                CaptureStatus = L.T("ON: receiving picture","AAN: beeld wordt ontvangen");
            }
            else
            {
                CaptureStatus = L.T("No picture (protected or locked screen?)","Geen beeld (beveiligd scherm of vergrendeld?)");
                Thread.Sleep(250);
            }
            int left = 16 - (int)sw.ElapsedMilliseconds;
            if (left > 0) Thread.Sleep(left);
        }
    }

    static bool Dark(byte[] f, int idx) => Math.Max(f[idx], Math.Max(f[idx + 1], f[idx + 2])) <= 24;

    void Process(byte[] f, int w, int h)
    {
        var c = Cfg;
        int n = c.Total;
        if (n <= 0) return;
        int stride = w * 4;
        int ox = 0, oy = 0, cw = w, ch = h;
        if (c.IgnoreBars)
        {
            bool RowDark(int y) { for (int x = 0; x < w; x += 3) if (!Dark(f, y * stride + x * 4)) return false; return true; }
            bool ColDark(int x) { for (int y = 0; y < h; y += 3) if (!Dark(f, y * stride + x * 4)) return false; return true; }
            int t = 0, b = 0, l = 0, r = 0;
            while (t < h / 3 && RowDark(t)) t++;
            while (b < h / 3 && RowDark(h - 1 - b)) b++;
            while (l < w / 3 && ColDark(l)) l++;
            while (r < w / 3 && ColDark(w - 1 - r)) r++;
            if (!(t >= h / 3 && b >= h / 3))
            {
                int[] vals = { t, b, l, r };
                for (int i = 0; i < 4; i++)
                {
                    _barHist[i].Add(vals[i]);
                    if (_barHist[i].Count > 90) _barHist[i].RemoveAt(0);
                }
            }
            int[] bars = _barHist.Select(hh => hh.Count > 0 && hh.Min() >= 2 ? hh.Min() : 0).ToArray();
            oy = bars[0]; ch = Math.Max(8, h - bars[0] - bars[1]);
            ox = bars[2]; cw = Math.Max(8, w - bars[2] - bars[3]);
        }
        var o = new float[3 * n];
        for (int p = 0; p < n; p++)
        {
            var (x0, y0, x1, y1) = Layout.Zone(p, c, w, h, ox, oy, cw, ch);
            long sr = 0, sg = 0, sb = 0;
            for (int y = y0; y < y1; y++)
            {
                int idx = y * stride + x0 * 4;
                for (int x = x0; x < x1; x++, idx += 4) { sb += f[idx]; sg += f[idx + 1]; sr += f[idx + 2]; }
            }
            float cnt = (x1 - x0) * (y1 - y0);
            o[3 * p] = sr / cnt; o[3 * p + 1] = sg / cnt; o[3 * p + 2] = sb / cnt;
        }
        lock (_lock) { _frames++; _target = o; }
    }

    // ---------------- Uitvoer naar de Arduino ----------------

    void OutputLoop()
    {
        double last = _clock.Elapsed.TotalSeconds;
        double fpsStart = last;
        while (!_quit)
        {
            double now = _clock.Elapsed.TotalSeconds;
            double dt = Math.Min(0.2, now - last);
            last = now;
            int bytes = Tick(dt);
            if (bytes > 0 && _serial.IsOpen) _sentFrames++;
            double baud = Math.Max(9600, _serial.Baud);
            double minInterval = bytes > 0 ? Math.Max(1.0 / 60, bytes * 10 / baud * 1.03) : 0.05;
            double el = _clock.Elapsed.TotalSeconds - now;
            if (el < minInterval) Thread.Sleep((int)Math.Max(1, (minInterval - el) * 1000));
            if (_clock.Elapsed.TotalSeconds - fpsStart >= 1)
            {
                if (_serial.IsOpen && _serial.Path != null && (_sentFrames > 0 || CurrentMode == Mode.Off))
                    ArduinoStatus = L.T($"Connected ({_serial.Path}) · {_sentFrames} fps", $"Verbonden ({_serial.Path}) · {_sentFrames} fps");
                _sentFrames = 0;
                fpsStart = _clock.Elapsed.TotalSeconds;
            }
        }
    }

    static float[] Hsv(double h, double s = 1, double v = 1)
    {
        double hh = (h - Math.Floor(h)) * 6;
        int i = (int)hh; double f = hh - i;
        double p = v * (1 - s), q = v * (1 - s * f), t = v * (1 - s * (1 - f));
        (double r, double g, double b) = (i % 6) switch
        {
            0 => (v, t, p), 1 => (q, v, p), 2 => (p, v, t), 3 => (p, q, v), 4 => (t, p, v), _ => (v, p, q),
        };
        return new[] { (float)(r * 255), (float)(g * 255), (float)(b * 255) };
    }

    static void Animate(float[] des, int n, Config c, double t)
    {
        double sp = c.AnimSpeed;
        float[] baseC = { (float)(c.StaticR * 255), (float)(c.StaticG * 255), (float)(c.StaticB * 255) };
        void Put(int i, float[] col, float f = 1) { des[3 * i] = col[0] * f; des[3 * i + 1] = col[1] * f; des[3 * i + 2] = col[2] * f; }
        switch (c.Anim)
        {
            case "Regenboog":
                for (int i = 0; i < n; i++) Put(i, Hsv((double)Layout.PerimeterIndex(i, n, c) / n + t * 0.08 * sp));
                break;
            case "Kleurwissel":
                { var col = Hsv(t * 0.05 * sp); for (int i = 0; i < n; i++) Put(i, col); }
                break;
            case "Ademen":
                {
                    float f = (float)(0.5 + 0.5 * Math.Sin(t * sp * 1.5 - Math.PI / 2));
                    for (int i = 0; i < n; i++) Put(i, baseC, 0.04f + 0.96f * f * f);
                }
                break;
            case "Looplicht":
                {
                    double head = t * sp * 20, tail = Math.Max(4.0, n * 0.2);
                    for (int i = 0; i < n; i++)
                    {
                        double p = Layout.PerimeterIndex(i, n, c);
                        double d = (head - p) % n; if (d < 0) d += n;
                        if (d < tail) Put(i, baseC, (float)(1 - d / tail));
                    }
                }
                break;
            default: // Vuur
                for (int i = 0; i < n; i++)
                {
                    double a = Math.Sin(t * sp * (3 + i % 5) + i * 1.7);
                    double b = Math.Sin(t * sp * 7.3 + i * 0.9);
                    float f = (float)Math.Max(0, Math.Min(1, 0.55 + 0.3 * a + 0.15 * b));
                    Put(i, new[] { 255f, 60 + 110 * f, 0f }, 0.25f + 0.75f * f);
                }
                break;
        }
    }

    // Eén beeld berekenen en versturen. Geeft het aantal verstuurde bytes terug (0 = niets verstuurd).
    int Tick(double dt)
    {
        var c = Cfg;
        int n = c.Total;
        if (n <= 0) { ArduinoStatus = L.T("Set your LED counts first","Stel eerst je LEDs in"); return 0; }
        var now = DateTime.UtcNow;
        string want = string.IsNullOrEmpty(c.Port) ? SerialLink.AutoPort() : c.Port;

        if (_serial.IsOpen && (_serial.Path != want || _serial.Baud != c.Baud)) { _serial.Close(); _lastTry = DateTime.MinValue; }
        if (!_serial.IsOpen)
        {
            if ((now - _lastTry).TotalSeconds < 2) return 0;
            _lastTry = now;
            if (want == null || !_serial.Open(want, c.Baud)) { ArduinoStatus = L.T("No Arduino found","Geen Arduino gevonden"); return 0; }
            _openedAt = now;
            ArduinoStatus = L.T("Connected (", "Verbonden (") + want + ")";
        }
        if ((now - _openedAt).TotalSeconds < 2.5) return 0;      // Arduino herstart bij openen

        Mode m; int single;
        lock (_lock) { m = _mode; single = _single; }
        var des = new float[3 * n];
        double t = _clock.Elapsed.TotalSeconds;
        switch (m)
        {
            case Mode.Off: break;
            case Mode.Ambi:
                {
                    float[] tp; lock (_lock) tp = _target;
                    if (tp.Length == 3 * n)
                        for (int i = 0; i < n; i++)
                        {
                            int p = Layout.PerimeterIndex(i, n, c);
                            des[3 * i] = tp[3 * p]; des[3 * i + 1] = tp[3 * p + 1]; des[3 * i + 2] = tp[3 * p + 2];
                        }
                }
                break;
            case Mode.Sides:
                {
                    float[][] cols = { new float[] { 255, 0, 0 }, new float[] { 0, 255, 0 }, new float[] { 0, 0, 255 }, new float[] { 255, 200, 0 } };
                    for (int i = 0; i < n; i++)
                    {
                        int s = Layout.Locate(Layout.PerimeterIndex(i, n, c), c).side;
                        var col = i == 0 ? new float[] { 255, 255, 255 } : cols[s];
                        des[3 * i] = col[0]; des[3 * i + 1] = col[1]; des[3 * i + 2] = col[2];
                    }
                }
                break;
            case Mode.Static:
                for (int i = 0; i < n; i++) { des[3 * i] = (float)(c.StaticR * 255); des[3 * i + 1] = (float)(c.StaticG * 255); des[3 * i + 2] = (float)(c.StaticB * 255); }
                break;
            case Mode.Anim: Animate(des, n, c, t); break;
            case Mode.Chase: { int i = (int)(t * 12) % n; des[3 * i] = des[3 * i + 1] = des[3 * i + 2] = 255; } break;
            case Mode.White: for (int k = 0; k < des.Length; k++) des[k] = 255; break;
            case Mode.Single:
                if (single >= 0 && single < n) des[3 * single] = des[3 * single + 1] = des[3 * single + 2] = 255;
                break;
        }

        if (_cur.Length != 3 * n) _cur = new float[3 * n];
        if (m != Mode.Ambi) _held = Array.Empty<float>();
        if (m == Mode.Ambi)
        {
            // Dode zone: schermopname heeft ruis; een LED volgt pas als het doel echt verschilt.
            if (_held.Length != 3 * n) _held = (float[])des.Clone();
            float thr = (float)(3 + 6 * c.AntiFlicker);
            for (int i = 0; i < n; i++)
            {
                int b = 3 * i;
                float diff = Math.Max(Math.Abs(des[b] - _held[b]), Math.Max(Math.Abs(des[b + 1] - _held[b + 1]), Math.Abs(des[b + 2] - _held[b + 2])));
                bool dark = Math.Max(des[b], Math.Max(des[b + 1], des[b + 2])) < 3;
                if (diff > thr || (dark && diff > 0)) { _held[b] = des[b]; _held[b + 1] = des[b + 1]; _held[b + 2] = des[b + 2]; }
            }
            des = (float[])_held.Clone();
            double tauFast = c.Smoothing * c.Smoothing * 0.6;
            double af = c.AntiFlicker;
            for (int i = 0; i < n; i++)
            {
                int b = 3 * i;
                float diff = Math.Max(Math.Abs(des[b] - _cur[b]), Math.Max(Math.Abs(des[b + 1] - _cur[b + 1]), Math.Abs(des[b + 2] - _cur[b + 2]))) / 255;
                double w = Math.Min(1, Math.Max(0, (diff - 0.12) / 0.3));
                float curL = Math.Max(_cur[b], Math.Max(_cur[b + 1], _cur[b + 2]));
                float desL = Math.Max(des[b], Math.Max(des[b + 1], des[b + 2]));
                float rel = Math.Abs(desL - curL) / Math.Max(Math.Max(curL, desL), 20);
                w = Math.Max(w, Math.Min(1, Math.Max(0, (rel - 0.25) / 0.35)));
                if (desL < curL * 0.6) w = 1;
                double tau = (w >= 1 && desL < curL) ? tauFast * 0.5 : tauFast + af * (0.35 * (1 - w) + 0.06 * w);
                float a = tau < 0.002 ? 1f : (float)(1 - Math.Exp(-dt / tau));
                for (int j = 0; j < 3; j++) _cur[b + j] += (des[b + j] - _cur[b + j]) * a;
            }
        }
        else Array.Copy(des, _cur, des.Length);

        int[] order = c.ColorOrder.Select(ch => ch == 'R' ? 0 : (ch == 'G' ? 1 : 2)).ToArray();
        if (order.Length != 3) order = new[] { 0, 1, 2 };
        var buf = new byte[6 + 3 * n];
        byte hi = (byte)(((n - 1) >> 8) & 0xFF), lo = (byte)((n - 1) & 0xFF);
        buf[0] = 0x41; buf[1] = 0x64; buf[2] = 0x61; buf[3] = hi; buf[4] = lo; buf[5] = (byte)(hi ^ lo ^ 0x55);
        float sat = (float)c.Saturation, gam = (float)c.Gamma, br = (float)c.Brightness;
        float boost = m == Mode.Ambi ? (float)c.Boost : 1;
        float vivid = (float)c.Vivid, blackLvl = (float)c.BlackLevel;
        float[] wb = { (float)c.WbR, (float)c.WbG, (float)c.WbB };
        var disp = new byte[3 * n];
        var rgb = new float[3]; var lin = new float[3];
        for (int i = 0; i < n; i++)
        {
            rgb[0] = _cur[3 * i]; rgb[1] = _cur[3 * i + 1]; rgb[2] = _cur[3 * i + 2];
            float g = 0.299f * rgb[0] + 0.587f * rgb[1] + 0.114f * rgb[2];
            for (int j = 0; j < 3; j++) lin[j] = Math.Max(0, g + (rgb[j] - g) * sat) / 255;
            float mx0 = Math.Max(lin[0], Math.Max(lin[1], lin[2]));
            if (m == Mode.Ambi && blackLvl > 0)
            {
                float f = Math.Min(1, Math.Max(0, (mx0 - blackLvl) / blackLvl));
                for (int j = 0; j < 3; j++) lin[j] *= f;
                mx0 *= f;
            }
            if (mx0 > 0)
            {
                float k = Math.Min(boost, 1 / mx0);
                for (int j = 0; j < 3; j++) lin[j] *= k;
            }
            if (m == Mode.Ambi && vivid > 0)
            {
                float mx = Math.Max(lin[0], Math.Max(lin[1], lin[2]));
                if (mx > 0.05f)
                {
                    float ramp = Math.Min(1, (mx - 0.05f) / 0.25f);
                    float target = mx + (1 - mx) * vivid * ramp;
                    float k = target / mx;
                    for (int j = 0; j < 3; j++) lin[j] = Math.Min(1, lin[j] * k);
                }
            }
            for (int j = 0; j < 3; j++)
            {
                rgb[j] = Math.Min(255, MathF.Pow(lin[j], gam) * br * 255 * wb[j]);
                disp[3 * i + j] = (byte)Math.Max(0, rgb[j] + 0.5f);
            }
            for (int j = 0; j < 3; j++) buf[6 + 3 * i + j] = (byte)Math.Max(0, Math.Min(255, rgb[order[j]] + 0.5f));
        }
        lock (_lock) _disp = disp;
        _serial.Write(buf);
        return buf.Length;
    }
}
