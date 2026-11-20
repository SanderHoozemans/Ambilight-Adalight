using System.IO.Ports;
using System.Management;
using System.Text.RegularExpressions;

namespace Ambilight;

public sealed class SerialLink
{
    SerialPort _p;
    public string Path { get; private set; }
    public int Baud { get; private set; }
    public bool IsOpen => _p != null && _p.IsOpen;

    public bool Open(string name, int baud)
    {
        Close();
        try
        {
            var p = new SerialPort(name, baud, Parity.None, 8, StopBits.One)
            {
                WriteTimeout = 1000,
                WriteBufferSize = 16384,
                Handshake = Handshake.None,
            };
            p.Open();
            _p = p; Path = name; Baud = baud;
            return true;
        }
        catch { return false; }
    }

    public void Close()
    {
        try { _p?.Close(); } catch { }
        try { _p?.Dispose(); } catch { }
        _p = null; Path = null;
    }

    public void Write(byte[] data)
    {
        if (_p == null) return;
        try { _p.Write(data, 0, data.Length); }
        catch { Close(); }          // kabel eruit
    }

    // ----- poorten zoeken -----

    static DateTime _cacheAt = DateTime.MinValue;
    static List<string> _cache = new();

    // USB-seriële poorten eerst (CH340, Arduino, FTDI …), daarna de rest.
    public static List<string> AvailablePorts()
    {
        if ((DateTime.UtcNow - _cacheAt).TotalMilliseconds < 1500) return _cache;
        var all = SerialPort.GetPortNames().Distinct().OrderBy(p => int.TryParse(Regex.Match(p, @"\d+").Value, out var n) ? n : 0).ToList();
        var usb = new List<string>();
        try
        {
            using var s = new ManagementObjectSearcher("SELECT Name FROM Win32_PnPEntity WHERE Name LIKE '%(COM%)'");
            foreach (var o in s.Get())
            {
                var name = o["Name"]?.ToString() ?? "";
                var m = Regex.Match(name, @"\((COM\d+)\)");
                if (!m.Success || !all.Contains(m.Groups[1].Value)) continue;
                if (Regex.IsMatch(name, "CH340|CH341|USB|Arduino|FTDI|CP210|Serial", RegexOptions.IgnoreCase) &&
                    !Regex.IsMatch(name, "Bluetooth", RegexOptions.IgnoreCase))
                    usb.Add(m.Groups[1].Value);
            }
        }
        catch { }
        _cache = usb.Count > 0 ? usb.Concat(all.Except(usb)).ToList() : all;
        _cacheAt = DateTime.UtcNow;
        return _cache;
    }

    public static string AutoPort() => AvailablePorts().FirstOrDefault();
}
