// FastAdalight – fast Adalight firmware for Arduino Uno/Nano (ATmega328P, 16 MHz) + WS2812B.
// Works with this Ambilight app (macOS + Windows) and with Prismatik / Hyperion / any Adalight host.
//
// - Accepts BOTH 1,000,000 and 115,200 baud automatically: without a valid frame it flips
//   between the two speeds every ~1.2 s until one works.
// - Reads the UART registers directly (no Serial buffer) so 1 Mbaud is reliable.
// - Colour order is handled here (WS2812B = GRB); the host should send plain RGB.
//
// !! Set NUM_LEDS, DATA_PIN and MAX_MA for YOUR strip and power supply before flashing. !!
#include <FastLED.h>

#define NUM_LEDS   141       // total number of LEDs on the strip
#define DATA_PIN   8         // Arduino pin connected to DIN
#define MAX_MA     2000      // current limit in mA. Raise ONLY if your 5 V supply can deliver it
                             // (rule of thumb: ~60 mA per LED at full white; 90% of your supply rating)
#define IDLE_MS    10000     // no data for 10 s: LEDs off

CRGB leds[NUM_LEDS];
static uint8_t rx[NUM_LEDS * 3];
static uint32_t lastFrame = 0;
static uint32_t lastGood = 0;   // last valid frame (used for baud selection)

static bool fast = true;   // true = 1.000.000, false = 115200

static void uartInit() {
  // 16 MHz, U2X: UBRR = 16e6 / (8 * baud) - 1   -> 1 = 1 Mbaud, 16 = 115200 (2% error, fine)
  UCSR0B = 0;
  UCSR0A = _BV(U2X0);
  UBRR0H = 0;
  UBRR0L = fast ? 1 : 16;
  UCSR0C = _BV(UCSZ01) | _BV(UCSZ00);   // 8N1
  UCSR0B = _BV(RXEN0) | _BV(TXEN0);
  while (UCSR0A & _BV(RXC0)) { (void)UDR0; }   // discard stale bytes
}

static void uartPut(uint8_t c) { while (!(UCSR0A & _BV(UDRE0))) {} UDR0 = c; }

// Read one byte; -1 on timeout (us).
static int uartGet(uint32_t timeoutUs) {
  uint32_t t0 = micros();
  while (!(UCSR0A & _BV(RXC0))) {
    if ((uint32_t)(micros() - t0) > timeoutUs) return -1;
  }
  return UDR0;
}

void setup() {
  FastLED.addLeds<WS2812B, DATA_PIN, GRB>(leds, NUM_LEDS);
  FastLED.setMaxPowerInVoltsAndMilliamps(5, MAX_MA);
  FastLED.setDither(DISABLE_DITHER);   // dithering causes flicker on static pictures
  FastLED.clear(true);
  uartInit();
  const char *hello = "Ada\n";
  while (*hello) uartPut(*hello++);
}

void loop() {
  // No valid frame for 1.2 s? Try the other speed.
  if (millis() - lastGood > 1200) { fast = !fast; uartInit(); lastGood = millis(); }
  // Wait for the "Ada" header
  int c = uartGet(100000);
  if (c < 0) {
    if (lastFrame && millis() - lastFrame > IDLE_MS) { FastLED.clear(true); lastFrame = 0; }
    return;
  }
  if (c != 'A') return;
  if (uartGet(2000) != 'd') return;
  if (uartGet(2000) != 'a') return;
  int hi = uartGet(2000), lo = uartGet(2000), chk = uartGet(2000);
  if (hi < 0 || lo < 0 || chk < 0) return;
  if (chk != (hi ^ lo ^ 0x55)) return;

  uint16_t count = ((uint16_t)hi << 8 | lo) + 1;
  // Read into a separate buffer first. Bytes of one frame arrive back to back;
  // a gap of >2 ms means something was lost -> drop the frame (no flash).
  for (uint16_t i = 0; i < count; i++) {
    for (uint8_t j = 0; j < 3; j++) {
      int v = uartGet(2000);
      if (v < 0) return;
      if (i < NUM_LEDS) rx[i * 3 + j] = (uint8_t)v;
    }
  }
  if (count != NUM_LEDS) return;       // wrong LED count: do not show
  memcpy(leds, rx, sizeof(rx));        // CRGB = r,g,b in geheugen
  FastLED.show();
  lastGood = millis();
  lastFrame = millis();
  if (!lastFrame) lastFrame = 1;
}
