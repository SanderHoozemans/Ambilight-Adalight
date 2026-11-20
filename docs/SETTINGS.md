# Settings file format

*Export…* writes a JSON file; *Import…* reads it. The same file works on macOS and Windows.

```json
{
  "app": "Ambilight",
  "format": 1,
  "settings": {
    "top": 49, "right": 21, "bottom": 50, "left": 21,
    "offset": 0, "reversed": false,
    "colorOrder": "RGB", "baud": 1000000,
    "brightness": 1.0, "saturation": 1.25, "gamma": 1.3, "boost": 1.5, "vivid": 0.6,
    "smoothing": 0.2, "antiFlicker": 0.6, "blackLevel": 0.06, "depth": 0.12,
    "wbR": 1.0, "wbG": 1.0, "wbB": 1.0,
    "kind": "ambi", "staticR": 1.0, "staticG": 0.55, "staticB": 0.15,
    "anim": "Regenboog", "animSpeed": 1.0, "ignoreBars": true,
    "followNightShift": true, "nsAmount": 1.0
  }
}
```

| Key | Meaning |
|-----|---------|
| `top/right/bottom/left` | LEDs per side (look at the front of the screen) |
| `offset`, `reversed` | Where LED 1 sits and in which direction the strip runs |
| `colorOrder`, `baud` | Hardware: colour order sent to the Arduino, serial speed |
| `brightness`, `saturation`, `gamma`, `boost`, `vivid` | Picture look (0–1 / 0–2 / …) |
| `smoothing`, `antiFlicker`, `blackLevel`, `depth` | Responsiveness, flicker suppression, black threshold, zone depth |
| `wbR/G/B` | White balance (1.0 = full) |
| `kind` | `off`, `ambi`, `static`, `anim` |
| `anim` | `Regenboog`, `Kleurwissel`, `Ademen`, `Looplicht`, `Vuur` (rainbow, colour fade, breathing, chase, fire) |
| `followNightShift`, `nsAmount` | macOS only; ignored on Windows |

Not exported: the serial `port` (differs per computer) and the Windows-only `display` index. Missing keys fall back
to defaults, so hand-edited and older files keep working.
