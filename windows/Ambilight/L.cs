using System.Globalization;

namespace Ambilight;

// Minimale vertaling: Nederlands als Windows in het Nederlands staat, anders Engels.
public static class L
{
    public static readonly bool Dutch = CultureInfo.CurrentUICulture.TwoLetterISOLanguageName == "nl";
    public static string T(string en, string nl) => Dutch ? nl : en;
}
