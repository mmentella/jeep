# Risk Register

| ID | Area | Severity | Likelihood | Risk | Impact | Mitigation |
|---|---|---:|---:|---|---|---|
| R01 | Bluetooth | High | High | Adapter BLE exposes custom UUIDs or unexpected characteristic layout. | App connects but cannot write/read reliably. | Add known UUID profiles, service filtering, user-visible adapter diagnostics. |
| R02 | Bluetooth | High | Medium | `send` is not safe for concurrent calls. | PID Lab and polling can race, pending continuation can be overwritten. | Introduce request queue/actor around transport send. |
| R03 | Bluetooth | High | Medium | No reconnection strategy. | App stays disconnected after transient BLE drop. | Add connection state machine with backoff, watchdog, manual retry. |
| R04 | Bluetooth | Medium | High | Scanning without service UUID lists many devices. | Confusing UX and accidental wrong peripheral selection. | Filter names/advertised services, add adapter selection screen. |
| R05 | Bluetooth | Medium | Medium | Notify state is not confirmed before connection considered ready. | First command can be lost. | Wait for `didUpdateNotificationState` and validate write/notify pair. |
| R06 | Bluetooth | Medium | Medium | BLE response chunking is assumed to end only at `>`. | Partial or merged responses can corrupt parser. | Add response assembler with command correlation and max buffer. |
| R07 | iOS Compatibility | High | High | Bluetooth Classic/SPP adapters do not work with iOS app. | Users buy wrong adapter or cannot connect. | Onboarding and README must state BLE/MFi requirement clearly. |
| R08 | Vgate | Medium | Medium | Vgate iCar Pro 2S variants differ by firmware/model. | Works for one unit, fails for another. | Build adapter fingerprinting: device name, services, characteristics, `ATI`, `AT@1`. |
| R09 | ELM327 | High | High | Cheap clones return misleading `OK` or partial ELM327 compatibility. | Incorrect feature detection, false confidence. | Add adapter capability tests and conservative fallback modes. |
| R10 | ELM327 | High | Medium | Parser treats any `7F` substring as negative response. | Valid payload may be rejected. | Parse frames first, detect `7F service nrc` structurally. |
| R11 | ELM327 | High | Medium | `BUS ERROR`, `CAN ERROR`, `BUFFER FULL`, `RX ERROR` not typed. | Poor diagnostics and bad retry behavior. | Add adapter error enum and targeted recovery strategy. |
| R12 | ELM327 | High | Medium | Multiline/multi-ECU responses not modeled. | Wrong ECU value or parser mismatch. | Preserve lines and headers; choose ECU by profile. |
| R13 | Jeep 4xe | High | High | Proprietary PID assumptions can be wrong by model year/ECU. | Misleading readings or unsafe probing. | Require vehicle profile, source, test logs, and read-only safety review. |
| R14 | Safety | Critical | Low | PID Lab allows a command that is read-like syntactically but unsafe in context. | Vehicle behavior or ECU side effects. | Keep denylist, add allowlist mode for real vehicle, disable Lab while moving. |
| R15 | Safety | Critical | Low | Future implementation adds write/programming accidentally. | ECU coding/programming risk. | Enforce architectural boundary: no write services in production build. |
| R16 | Performance | Medium | High | Fixed polling treats all PID equally. | Lag, wasted BLE/ECU bandwidth, battery drain. | Add adaptive scheduler with fast/medium/slow lanes. |
| R17 | Performance | Medium | Medium | 4s timeout serially blocks all PID. | Dashboard freezes during one bad PID. | Per-PID timeout policy, skip/backoff bad PID. |
| R18 | Battery Phone | Medium | Medium | Continuous BLE + bright screen drains phone. | Bad road-trip UX. | Pause in background, low-power mode, dim-friendly UI. |
| R19 | Battery Vehicle | High | Medium | Adapter remains powered when car is off. | 12V battery drain over time. | Warn user, detect low voltage, stop polling, recommend unplugging. |
| R20 | UI/UX | Medium | High | Dashboard not configurable. | Cannot compete with Car Scanner workflows. | Add dashboard editor and sensor selection. |
| R21 | UI/UX | High | Medium | PID Lab is available while driving. | Driver distraction and unsafe manual probing. | Gate Lab behind parked/debug mode. |
| R22 | Data | Medium | Medium | Logs are in memory only. | Lost diagnostic evidence after app restart. | Add persistent session store with explicit delete/export. |
| R23 | Data Privacy | Medium | Medium | VIN/manual logs can be exported/shared. | Privacy leak. | Redact VIN option and export warning. |
| R24 | CI | Medium | Medium | CI only builds simulator. | BLE/device issues undetected. | Add manual device test checklist and hardware regression matrix. |
| R25 | Android | Medium | Medium | iOS transport assumptions leak into domain. | Android port needs rewrite. | Keep shared protocol specs in JSON/YAML and platform-specific transports. |

## Top Risks

1. `R02` concurrent send/polling race.
2. `R10-R12` parser is not yet a true ELM327 frame parser.
3. `R01/R08/R09` adapter fragmentation and clone behavior.
4. `R14/R15` manual command safety as PID Lab grows.
5. `R16/R17` fixed polling and timeout strategy.

## Safety Position

The app should remain read-only by architecture. Any future service beyond known read services must be explicitly reviewed. UDS write/programming-related services should remain blocked in production builds unless the product scope changes completely.
