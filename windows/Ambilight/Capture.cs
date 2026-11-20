using System.Runtime.InteropServices;

namespace Ambilight;

// Schermopname via GDI (StretchBlt naar een klein bitmapje). Werkt op elke Windows 10/11-pc
// zonder toestemming. Beschermde (DRM-)video en sommige exclusieve volledig-scherm-games
// komen zwart binnen; dat omzeilen we niet.
public sealed class ScreenGrabber : IDisposable
{
    [StructLayout(LayoutKind.Sequential)]
    struct BITMAPINFOHEADER
    {
        public uint biSize; public int biWidth; public int biHeight; public ushort biPlanes; public ushort biBitCount;
        public uint biCompression; public uint biSizeImage; public int biXPelsPerMeter; public int biYPelsPerMeter;
        public uint biClrUsed; public uint biClrImportant;
    }

    [DllImport("user32.dll")] static extern IntPtr GetDC(IntPtr hwnd);
    [DllImport("user32.dll")] static extern int ReleaseDC(IntPtr hwnd, IntPtr dc);
    [DllImport("gdi32.dll")] static extern IntPtr CreateCompatibleDC(IntPtr dc);
    [DllImport("gdi32.dll")] static extern bool DeleteDC(IntPtr dc);
    [DllImport("gdi32.dll")] static extern IntPtr CreateDIBSection(IntPtr dc, ref BITMAPINFOHEADER bmi, uint usage, out IntPtr bits, IntPtr section, uint offset);
    [DllImport("gdi32.dll")] static extern IntPtr SelectObject(IntPtr dc, IntPtr obj);
    [DllImport("gdi32.dll")] static extern bool DeleteObject(IntPtr obj);
    [DllImport("gdi32.dll")] static extern int SetStretchBltMode(IntPtr dc, int mode);
    [DllImport("gdi32.dll")] static extern bool StretchBlt(IntPtr dst, int x, int y, int w, int h, IntPtr src, int sx, int sy, int sw, int sh, uint rop);

    const uint SRCCOPY = 0x00CC0020;
    const int COLORONCOLOR = 3;

    public const int Width = 320;
    int _h, _srcW, _srcH, _srcX, _srcY;
    IntPtr _mem, _bmp, _old, _bits;
    public byte[] Frame { get; private set; }
    public int Height => _h;

    public static System.Drawing.Rectangle ScreenBounds(int display)
    {
        var all = Screen.AllScreens;
        return all[Math.Clamp(display, 0, all.Length - 1)].Bounds;
    }

    // true = beeld gelukt
    public bool Grab(int display)
    {
        var b = ScreenBounds(display);
        if (b.Width <= 0 || b.Height <= 0) return false;
        int h = Math.Max(8, (int)Math.Round(Width * (double)b.Height / b.Width));
        if (_bmp == IntPtr.Zero || h != _h || b.Width != _srcW || b.Height != _srcH) Build(h);
        _srcX = b.X; _srcY = b.Y; _srcW = b.Width; _srcH = b.Height;

        var scr = GetDC(IntPtr.Zero);
        if (scr == IntPtr.Zero) return false;
        try
        {
            SetStretchBltMode(_mem, COLORONCOLOR);
            if (!StretchBlt(_mem, 0, 0, Width, _h, scr, _srcX, _srcY, _srcW, _srcH, SRCCOPY)) return false;
        }
        finally { ReleaseDC(IntPtr.Zero, scr); }
        Marshal.Copy(_bits, Frame, 0, Frame.Length);
        return true;
    }

    void Build(int h)
    {
        Free();
        _h = h;
        var scr = GetDC(IntPtr.Zero);
        _mem = CreateCompatibleDC(scr);
        var bi = new BITMAPINFOHEADER
        {
            biSize = (uint)Marshal.SizeOf<BITMAPINFOHEADER>(), biWidth = Width, biHeight = -h, biPlanes = 1, biBitCount = 32,
        };
        _bmp = CreateDIBSection(scr, ref bi, 0, out _bits, IntPtr.Zero, 0);
        ReleaseDC(IntPtr.Zero, scr);
        _old = SelectObject(_mem, _bmp);
        Frame = new byte[Width * h * 4];
    }

    void Free()
    {
        if (_mem != IntPtr.Zero) { if (_old != IntPtr.Zero) SelectObject(_mem, _old); DeleteDC(_mem); }
        if (_bmp != IntPtr.Zero) DeleteObject(_bmp);
        _mem = _bmp = _old = IntPtr.Zero;
    }

    public void Dispose() => Free();
}
