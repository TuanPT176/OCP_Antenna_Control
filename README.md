# ESP32-C3 Super Mini + PE64906 DTC Control
**Faculty of Computer Engineering — University of Information Technology (TTLab)**

---

## Table of Contents
1. [System Overview](#1-system-overview)
2. [Arduino IDE — Board Setup](#2-arduino-ide--board-setup)
3. [Hardware Wiring — SPI + SEN](#3-hardware-wiring--spi--sen)
4. [SPI Configuration Explained](#4-spi-configuration-explained)
5. [Understanding the Code](#5-understanding-the-code)
6. [Fixed Capacitance State](#6-fixed-capacitance-state)
7. [Sweep Loop — All 32 States](#7-sweep-loop--all-32-states)
8. [Flashing & Troubleshooting](#8-flashing--troubleshooting)

---

## 1. System Overview

### ESP32-C3 Super Mini
- **Architecture:** RISC-V single-core, 160 MHz
- **Flash:** 4 MB (QIO mode)
- **USB:** CDC built-in — no FTDI/CP2102 adapter needed
- **SPI:** Fully remappable to any GPIO via `SPI.begin(CLK, MISO, MOSI, SS)`

### PE64906 — Digitally Tunable Capacitor (DTC)
- **Capacitance range:** ~0.6 pF (state 0) to ~5.4 pF (state 31)
- **Control:** 5-bit digital (32 steps), via SPI
- **Interface:** SPI Mode 0, MSB First, 8-bit transfer
- **SEN pin:** acts as a data-window gate — NOT a standard active-low CS

### Connection Summary

```
ESP32-C3 Super Mini          PE64906
─────────────────────        ──────────────
GPIO 2  ─────────────────►  SEN / LE
GPIO 3  ─────────────────►  CLK
GPIO 4  ─────────────────►  DATA (MOSI)
3.3 V   ─────────────────►  VDD
GND     ─────────────────►  GND
(MISO not connected, set to -1)
```

---

## 2. Arduino IDE — Board Setup

### Step 1 — Add Board URL
1. Open **File → Preferences**
2. Paste into **Additional Boards Manager URLs**:
   ```
   https://espressif.github.io/arduino-esp32/package_esp32_dev_index.json
   https://espressif.github.io/arduino-esp32/package_esp32_index.json
   ```

### Step 2 — Install Board Package
1. **Tools → Board → Boards Manager**
2. Search `esp32` → Install **esp32 by Espressif Systems**
<img width="637" height="337" alt="image" src="https://github.com/user-attachments/assets/dcb85b59-10a2-425c-b029-601f6944309c" />

### Step 3 — Required Tool Settings

| Setting | Value | Reason |
|---------|-------|--------|
| **Board** | ESP32C3 Dev Module | Matches the Super Mini |
| **USB CDC On Boot** | Enabled | Serial Monitor via USB-C |
| **CPU Frequency** | 160 MHz (WiFi) | Full performance |
| **Flash Size** | 4MB (32Mb) | Correct for this module |
| **Flash Mode** | QIO | Fastest flash access |
| **Partition Scheme** | Default 4MB with spiffs | 1.2 MB APP + 1.5 MB SPIFFS |
| **JTAG Adapter** | Disabled | Frees GPIO 11/12 if needed |
<img width="609" height="519" alt="image" src="https://github.com/user-attachments/assets/76a9d7a2-171c-4e9c-b9c1-7ccb8dcd7ae4" />

---

## 3. Hardware Wiring — SPI + SEN

### Pin Mapping

| ESP32-C3 | PE64906 | Signal |
|----------|---------|--------|
| GPIO 2 | SEN / LE | Serial Enable (manual CS) |
| GPIO 3 | CLK | Serial Clock |
| GPIO 4 | DATA | MOSI (data in) |
| 3.3 V | VDD | Power |
| GND | GND | Ground |
| — (−1) | MISO | Not connected |

### SEN Timing — Critical

```
SEN:  ─────┐              ┌───── (held LOW = latch)
           │              │
           └──────────────┘
CLK:           ┌─┐ ┌─┐ ┌─┐
               └─┘ └─┘ └─┘
DATA:       ──[ D7 D6 ... D0 ]──

Sequence:
1. SEN = LOW   (setup / idle)
2. delay(1 ms)
3. SEN = HIGH  (open acceptance window)
4. delay(1 ms)
5. SPI.transfer(state)  ← 8 bits clocked in
6. delay(1 ms)
7. SEN = LOW   ← LATCH — DTC captures the value
```

> **⚠ SEN ≠ standard active-low CS.** Standard CS stays LOW during the entire transfer. PE64906's SEN must go HIGH during the transfer and LOW *after* to latch the data.

### `SPI.begin()` with Custom GPIO

```cpp
SPI.begin(SPICLK, SPIMISO, SPIMOSI, -1);
//        CLK=3,  MISO=-1,  MOSI=4,  SS=-1
```

The ESP32 Arduino core allows SPI on any GPIO — not restricted to default hardware pins.

---

## 4. SPI Configuration Explained

### SPISettings

```cpp
SPISettings dtcSettings(100000, MSBFIRST, SPI_MODE0);
```

| Parameter | Value | Why |
|-----------|-------|-----|
| Speed | 100 kHz | Conservative — eliminates ringing on breadboard wires |
| Bit order | `MSBFIRST` | PE64906 expects MSB first |
| Mode | `SPI_MODE0` | CPOL=0, CPHA=0 — clock idle LOW, sample on rising edge |

### PE64906 Register Map

```
Bit:  7    6    5    4    3    2    1    0
      0    0   STB   d4   d3   d2   d1   d0
```

| Bit | Name | Value | Meaning |
|-----|------|-------|---------|
| 7–6 | — | 0 | Always zero |
| 5 | STB | 0 | Active (normal operation) |
| 5 | STB | 1 | Standby (low-power mode) |
| 4–0 | d4..d0 | 0–31 | Capacitance state |

**Examples:**

| state | Byte sent | Approx. C |
|-------|-----------|-----------|
| 0 | `0x00` | ~0.6 pF |
| 7 | `0x07` | ~1.9 pF |
| 15 | `0x0F` | ~3.0 pF |
| 23 | `0x17` | ~4.2 pF |
| 31 | `0x1F` | ~5.4 pF |
| 15 + standby | `0x2F` | ~3.0 pF, low-power |

---

## 5. Understanding the Code

### Full Annotated Code

```cpp
#include <SPI.h>

#define PIN_SEN     2   // Serial Enable
#define SPICLK      3  // Serial Clock
#define SPIMOSI     4   // Serial Data (MOSI)
#define SPIMISO     -1   // Không dùng
// Cấu hình SPI: 1MHz, MSB First, SPI Mode 0
// PE64906 hoạt động tốt nhất ở Mode 0
SPISettings dtcSettings(100000, MSBFIRST, SPI_MODE0);

void setCapacitance(uint8_t state) {
  // state từ 0 đến 31 (5-bit)
  // Register map: [0][0][STB][d4][d3][d2][d1][d0]
  // STB = 0 là hoạt động, STB = 1 là thấp công suất (standby)
  if (state > 31) state = 31;

   SPI.beginTransaction(dtcSettings);
  digitalWrite(PIN_SEN, LOW);
  delay(1);
  digitalWrite(PIN_SEN, HIGH);
  delay(1);
 
  delay(1);
  // Gửi dữ liệu (DTC sẽ nhận 8 bit, lấy 5 bit cuối làm giá trị điện dung)
  Serial.print("Truyen");
  Serial.println(state);
  SPI.transfer(state);
  Serial.println(" xong.");
  delay(1);
  digitalWrite(PIN_SEN, LOW);
  // Kéo SEN lên cao để "chốt" (latch) dữ liệu vào tụ điện

  SPI.endTransaction();
}

void setup() {
  Serial.begin(115200);
  Serial.println("DTC PE64906 - Arduino Uno Control");

  // Thiết lập chân SEN
  pinMode(PIN_SEN, OUTPUT);
  SPI.begin(SPICLK, SPIMISO, SPIMOSI, -1);
  digitalWrite(PIN_SEN, HIGH);

  Serial.println("Da khoi tao xong!");
  delay(4000);
  //  setCapacitance(1);
}

void loop() {
  
  delay(2000);
  for (int i = 0; i < 21; i++) {
    Serial.print("Dang dat gia tri: ");
    Serial.println(i);
    
    setCapacitance(i);
    
    delay(5000); // Chờ 1 giây để quan sát
  }
}
```

### What Each Part Does

| Section | Purpose |
|---------|---------|
| `SPISettings dtcSettings(...)` | Configures clock speed, bit order, and SPI mode |
| `if (state > 31) state = 31` | Prevents overflow into STB/reserved bits |
| `SEN LOW → HIGH → transfer → LOW` | PE64906-specific latch sequence |
| `SPI.beginTransaction / endTransaction` | Thread-safe SPI bus management |

---

## 6. Fixed Capacitance State

To hold a single capacitance value without sweeping:

```cpp
void setup() {
    Serial.begin(115200);
    pinMode(PIN_SEN, OUTPUT);
    SPI.begin(SPICLK, SPIMISO, SPIMOSI, -1);
    digitalWrite(PIN_SEN, HIGH);
    delay(100);

    // ── SET YOUR DESIRED STATE HERE ──────────────
    setCapacitance(15);   // state 15 ≈ 3.0 pF
    // ─────────────────────────────────────────────

    Serial.println("Capacitance locked.");
}

void loop() {
    // Nothing — value is latched in hardware
}
```

### Standby Mode

```cpp
// Enter standby: set STB bit (bit 5) = 1
setCapacitance(state | 0x20);
// e.g. state=15 in standby: SPI.transfer(0x2F)

// Wake up: send state without STB bit
setCapacitance(15);
```

> **⚠ No NVRAM:** PE64906 has no internal memory. The capacitance value is lost every time power is removed. Always call `setCapacitance()` in `setup()` to restore the desired state.

---

## 7. Sweep Loop — All 32 States

### Basic Sweep (upward)

```cpp
void loop() {
    for (int i = 0; i < 32; i++) {
        Serial.print("State: ");
        Serial.println(i);
        setCapacitance(i);
        delay(5000);   // 5 s per step — adjust as needed
    }
    // loop() is called again automatically → sweep repeats
}
```

### Bi-directional Sweep (triangular)

```cpp
void loop() {
    // Up: 0 → 31
    for (int i = 0; i <= 31; i++) {
        setCapacitance(i);
        delay(200);
    }
    // Down: 31 → 0
    for (int i = 31; i >= 0; i--) {
        setCapacitance(i);
        delay(200);
    }
}
```

### One-shot Sweep (run once only)

```cpp
void loop() {
    for (int i = 0; i < 32; i++) {
        setCapacitance(i);
        delay(200);
    }
    while (1);   // Stop after one full sweep
}
```

### delay() guidance

| delay per step | Use case |
|---------------|----------|
| 5000 ms | Manual visual observation |
| 200 ms | Automated VNA / oscilloscope measurement |
| 10–50 ms | Fast scan / software-controlled |

---

## 8. Flashing & Troubleshooting

### Upload Steps

1. **Connect** USB-C cable (must be a data cable, not charge-only)
2. **Select board:** Tools → Board → ESP32C3 Dev Module
3. **Select port:** Tools → Port → COMxx (e.g. COM17)
4. **Verify:** click ✓ — fix any compile errors first
5. **Upload:** click → — wait for "Done uploading"
6. **Monitor:** Tools → Serial Monitor → 115200 baud

### If Upload Fails ("Failed to connect")

```
1. Hold the BOOT button on the ESP32-C3
2. Press and release the RST button
3. Release the BOOT button
4. Click Upload in Arduino IDE immediately
```

### Troubleshooting Table

| Symptom | Likely Cause | Fix |
|---------|-------------|-----|
| No COM port shown | Driver not installed | Install CH340 driver, or check USB cable |
| "Failed to connect" | Not in bootloader mode | Use BOOT+RST sequence above |
| Serial Monitor silent | USB CDC disabled | Tools → USB CDC On Boot → **Enabled** → re-flash |
| SPI appears to do nothing | Wrong GPIO or SEN timing | Check `SPI.begin(3, -1, 4, -1)` and SEN sequence |
| Capacitance resets on power-off | Expected — no NVRAM | Normal; always re-init in `setup()` |

---

## Quick Reference

### Pin Defines
```cpp
#define PIN_SEN   2
#define SPICLK    3
#define SPIMOSI   4
#define SPIMISO  -1
```

### State → Capacitance (approximate, linear interpolation)
```
C(pF) ≈ 0.6 + state × (4.8 / 31)
```

### Initialization Checklist
- [ ] Board: **ESP32C3 Dev Module**
- [ ] USB CDC On Boot: **Enabled**
- [ ] Flash Size: **4MB (32Mb)**
- [ ] Flash Mode: **QIO**
- [ ] Serial Monitor baud: **115200**
- [ ] SPI library: **SPI.h** (built-in, no install needed)
- [ ] External libraries needed: **none**

---

*TTLab / FCE-UIT — The Things Lab*
