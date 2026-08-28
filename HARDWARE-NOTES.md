# Hardware status and evidence

Status meanings:

- **proven**: observed working in the Debian 6.1 boot;
- **encoded**: copied from tablet evidence into source, awaiting a clean-image
  validation;
- **deferred**: intentionally disabled until its dependencies are known.

## Current matrix

| Function | Status | Current source decision |
|---|---|---|
| BootROM/IDB/U-Boot/trust | proven | exact tablet blobs, verified by SHA-256 |
| LPDDR3 2 GiB | proven | firmware-trained 332/333 MHz; DMC/DFI DVFS disabled |
| RK817 PMIC and regulators | proven | default IRQ pin state only |
| Thermal sensor | proven | enabled by the vendor base DTS |
| microSD | proven | `ff370000`, SDR104 at 100 MHz, tuned phase 135 |
| Debian root filesystem | proven | partition 8, selected by fixed PARTUUID |
| UART console | proven | UART2 M1, 1,500,000 baud |
| USB2 PHY IRQs | proven | Linux IRQs 100/96/98/97 registered from OEM SPI values |
| USB power rails | deferred | DWC2 currently falls back to dummy supplies |
| LCD/DSI/backlight | proven | console visible at 1024x600 over four DSI lanes |
| Touchscreen | proven | OEM firmware/config plus GPIO0_PC1 IRQ and GPIO0_PB4 reset |
| eMMC | deferred | disabled to prevent accidental writes |
| SDIO Wi-Fi | proven | RTL8723CS associated through `p2p0`; IPv4 and Internet traffic verified |
| Bluetooth | deferred | shared module on UART1 |
| Battery gauge | proven | RK817 reports capacity, voltage, current and status |
| Battery temperature | unavailable | two-wire pack has no NTC; `188` is a virtual driver fallback |
| Charger | test profile | conservative charge proven; exact 4.4 V / 2 A OEM policy isolated in `charge-test` |
| Audio | deferred | RK817 codec and external amplifier |
| Mali-G31 GPU | proven | Panfrost bound; EGL/GLES 3.1 and kmscube at about 61 FPS |
| VPU/RGA/cameras | deferred | not required for current hardware test |
| Suspend | deferred | regulator and wake-source validation required |

## Confirmed hardware

| Function | Value |
|---|---|
| SoC | Rockchip RK3326 / PX30 family |
| RAM | 2 GiB LPDDR3 |
| eMMC | 16 GB class device, controller `ff390000` |
| PMIC | RK817 on I2C0 address `0x20` |
| LCD | MIPI-DSI, RGB888, four lanes |
| LCD mode | 1024x600 at 49 MHz pixel clock |
| Touch | GSL3673 at I2C1 address `0x40` |
| Wi-Fi/BT | Realtek RTL8723CS, SDIO `024c:b703` |

## LCD evidence copied from the tablet DTB

| Signal | GPIO |
|---|---|
| enable | GPIO0_PB5, active low |
| standby | GPIO3_PB4, active low |
| reset | GPIO3_PB7, active low |
| backlight | PWM1 |

| Timing | Value |
|---|---:|
| pixel clock | 49,000,000 Hz |
| hactive / vactive | 1024 / 600 |
| horizontal front / sync / back | 65 / 10 / 63 |
| vertical front / sync / back | 40 / 20 / 30 |
| pixel clock active | 1 |

The panel works without a driver change. The vendor `stbyb-gpios` property
is retained as evidence even though the current public Rockchip
`panel-simple` implementation does not consume it.

## Battery evidence

The enabled RK817 fuel gauge has reported:

- `type=Battery`;
- `status=Discharging`;
- `capacity=60`;
- `voltage_now=3935000`;
- `current_now` with the expected sign change between discharge and charge;
- `temp=188`, which is **not** a measurement.

The battery has only two wires and exposes no thermistor. The Android DTB has
no `ntc_table`; in that condition the Rockchip RK817 battery driver returns its
hard-coded `VIRTUAL_TEMPERATURE` value of 188 (18.8 C). Battery temperature and
the driver's unconditional `health=Good` must therefore not be used as safety
signals.

The exact charger policy below is copied from the tablet's Android DTB:

- Battery design capacity: 2543 mAh.
- Battery design qmax: 2798 mAh.
- Minimum input voltage: 4500 mV.
- Maximum input current: 1500 mA.
- Maximum charge current: 2000 mA.
- Maximum charge voltage: 4400 mV.
- Charger termination mode: 1.
- Charger finish current: 120 mA.
- Codec speaker volume: 35.
- Codec capture volume: 21.
- Codec external amplifier: GPIO3_PB6, active high.
- Touch IRQ: GPIO0_PC1, level low.
- Touch reset: GPIO0_PB4, active high.

## Touchscreen evidence

The stock Rockchip GSL3673 header registered an evdev device but never
generated a second interrupt or touch event. The verified OEM
configuration/firmware extracted from Android fixed the controller:

- input range: 800 x 1280;
- IRQ: GPIO0_PC1, level low;
- reset: GPIO0_PB4, active high;
- generated header SHA-256:
  `63d9fd1141d4072201943283e30c01e39763d33b77e8152b339b80ed2036dcf8`.

## Charging validation boundary

A conservative 4.20 V / 500 mA test successfully detected a USB DCP source
and changed battery current from about -490 mA to about +520 mA. The OEM
profile is now encoded only in `rk3326-863-tablet-charge-test.dtb`.

During the first complete OEM-profile cycle:

- keep the tablet attended;
- attach an external thermometer to the cell;
- run `rk3326-charge-watch`;
- stop on rapid heating, swelling, smell or other abnormal behaviour.

The tool reports `bat_C=N/A` by design. `system_max_C` is useful system
telemetry but is not a substitute for cell temperature.

## Current validation boundary

- Display, touch, keys, microSD, battery gauge, RTL8723CS Wi-Fi and Mali-G31
  acceleration are proven.
- The charger path is proven at 4.20 V / 500 mA.
- The exact Android 4.40 V / 2.00 A policy is encoded for an externally
  monitored complete-cycle test.

## Known non-fatal boot messages

- RK817 regulator dependency cycles are resolved automatically.
- RK817 DVS0/DVS1 GPIOs are optional on this board.
- SCMI protocols absent from the vendor ATF must not be treated as hardware
  discovery failures.
- MMC `normal` and `idle` pinctrl warnings do not prevent the proven SDR104
  transfer mode, but should be revisited before suspend.
- Rockchip's USB2 PHY driver logs a missing optional combined parent IRQ even
  though all four separate PX30 child IRQs register correctly.
