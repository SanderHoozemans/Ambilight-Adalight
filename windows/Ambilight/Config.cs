using System.Text.Json;

namespace Ambilight;

// Zelfde velden en namen als de macOS-versie, zodat instellingenbestanden uitwisselbaar zijn.
public sealed class Config
{
    public int Top { get; set; }
    public int Right { get; set; }
    public int Bottom { get; set; }
    public int Left { get; set; }
    public int Offset { get; set; }
    public bool Reversed { get; set; }
    public string ColorOrder { get; set; } = "RGB";
    public int Baud { get; set; } = 115200;
    public string Port { get; set; } = "";          // leeg = automatisch
    public double Brightness { get; set; } = 1.0;
    public double Saturation { get; set; } = 1.0;
    public double Gamma { get; set; } = 1.8;
    public double Smoothing { get; set; } = 0.2;
    public double Depth { get; set; } = 0.12;
    public bool Enabled { get; set; } = true;
    public double Boost { get; set; } = 1.5;
    public double WbR { get; set; } = 1.0;
    public double WbG { get; set; } = 1.0;
    public double WbB { get; set; } = 1.0;
    public string Kind { get; set; } = "ambi";      // off, ambi, static, anim
    public double StaticR { get; set; } = 1.0;
    public double StaticG { get; set; } = 0.55;
    public double StaticB { get; set; } = 0.15;
    public string Anim { get; set; } = "Regenboog";
    public double AnimSpeed { get; set; } = 1.0;
    public bool IgnoreBars { get; set; } = true;
    public double Vivid { get; set; } = 0.6;
    public double AntiFlicker { get; set; } = 0.6;
    public bool FollowNightShift { get; set; } = true;   // alleen macOS; hier genegeerd
    public double NsAmount { get; set; } = 1.0;          // alleen macOS; hier genegeerd
    public double BlackLevel { get; set; } = 0.06;
    public int CfgVersion { get; set; } = 3;
    public int Display { get; set; } = 0;                // alleen Windows: welk scherm (0 = hoofdscherm)

    public int Total => Top + Right + Bottom + Left;

    public Config Clone() => (Config)MemberwiseClone();
}

public sealed class SettingsFile
{
    public string App { get; set; } = "Ambilight";
    public int Format { get; set; } = 1;
    public Config Settings { get; set; } = new();
}

public static class ConfigStore
{
    public static readonly JsonSerializerOptions Json = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        PropertyNameCaseInsensitive = true,
        WriteIndented = true,
    };

    static string Dir => Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "Ambilight");
    static string FilePath => Path.Combine(Dir, "config.json");

    public static Config Load()
    {
        try
        {
            if (File.Exists(FilePath))
                return JsonSerializer.Deserialize<Config>(File.ReadAllText(FilePath), Json) ?? new Config();
        }
        catch { }
        return new Config();
    }

    public static void Save(Config c)
    {
        try
        {
            Directory.CreateDirectory(Dir);
            File.WriteAllText(FilePath, JsonSerializer.Serialize(c, Json));
        }
        catch { }
    }

    // ----- Importeren / exporteren (zelfde bestand als op macOS) -----

    public static string Export(Config c)
    {
        var copy = c.Clone();
        copy.Port = "";                                   // poortnamen verschillen per computer
        return JsonSerializer.Serialize(new SettingsFile { Settings = copy }, Json);
    }

    public static Config Import(string text, Config current)
    {
        var f = JsonSerializer.Deserialize<SettingsFile>(text, Json);
        if (f == null || f.App != "Ambilight" || f.Settings == null) throw new InvalidDataException("Geen Ambilight-instellingenbestand");
        var c = f.Settings;
        c.Port = current.Port;
        c.Display = current.Display;
        return c;
    }
}
