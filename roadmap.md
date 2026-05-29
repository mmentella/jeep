# Roadmap

## P0 - Indispensabile

1. Request serialization
   - Add a single command queue or actor so polling and PID Lab cannot call `send` concurrently.
   - Prevent overwritten continuations and mixed ELM327 responses.

2. ELM327 response model
   - Split raw response parsing from PID value parsing.
   - Represent prompt, lines, headers, payloads, adapter errors, negative ECU responses.

3. Typed adapter errors
   - Add handling for `NO DATA`, `STOPPED`, `UNABLE TO CONNECT`, `BUS ERROR`, `CAN ERROR`, `BUS INIT: ERROR`, `BUFFER FULL`, `RX ERROR`, `?`.
   - Use typed errors for UI and retry decisions.

4. BLE readiness state machine
   - Wait for service discovery, characteristic selection, notify enable confirmation.
   - Track states: idle, scanning, connecting, discovering, initializing, ready, failed, reconnecting.

5. Reconnect and timeout policy
   - Add reconnect/backoff.
   - Make timeout configurable by command type.
   - Skip/backoff PIDs that repeatedly timeout.

6. Safety hardening for PID Lab
   - Disable PID Lab while polling unless explicitly paused.
   - Keep service denylist.
   - Add prominent real-vehicle warning.
   - Consider allowlist-only mode for real Bluetooth.

7. Persistent diagnostic sessions
   - Store raw logs and PID Lab logs on device.
   - Export complete sessions as CSV/JSON.
   - Include adapter fingerprint and app version.

8. Adapter fingerprinting
   - Capture BLE name, service UUIDs, characteristic UUIDs, `ATI`, `AT@1`, `ATDP`, `ATDPN`.
   - Show diagnostics for Vgate/clone compatibility.

9. Test expansion
   - Add parser tests for multiline, multi-ECU, BUS ERROR, CAN ERROR, STOPPED, response pending, echo enabled.
   - Add command queue tests.

## P1 - Importante

1. Polling scheduler
   - Fast lane: RPM, speed, throttle.
   - Medium lane: engine load, voltage.
   - Slow lane: coolant, DTC, supported PIDs.

2. Vehicle profile model
   - Add `VehicleProfile` for Jeep Renegade 4xe.
   - Include model year, ECU notes, supported categories, PID catalog version.

3. Custom PID formula engine
   - Replace free-form formula string with safe expression model.
   - Validate required bytes, units, scale, offset, min/max.

4. Known adapter profiles
   - Add BLE UUID profiles for tested adapters.
   - Keep property-based discovery as fallback, not primary strategy.

5. Dashboard UX upgrade
   - Add configurable cards.
   - Add driving-safe mode with 3-4 large values.
   - Add landscape layout.

6. Connection onboarding
   - Explain BLE vs Bluetooth Classic/SPP.
   - Help user select compatible adapter.
   - Show checklist: ignition on, adapter powered, mock/live mode.

7. Log filtering and search
   - Filter TX/RX/error/info.
   - Copy/share individual raw responses.
   - Tag logs by command.

8. App lifecycle handling
   - Pause polling in background.
   - Resume gracefully.
   - Handle Bluetooth authorization changes.

9. Android preparation
   - Export PID catalog and command policy to JSON/YAML.
   - Create shared test vectors for parser behavior.
   - Document Android transport variants: BLE, Classic SPP, Wi-Fi.

## P2 - Nice To Have

1. Charts
   - Small historical sparklines per PID.
   - Session graphs for RPM/speed/load/voltage.

2. Alerts
   - User-defined thresholds.
   - Low 12V voltage warning.
   - Coolant high warning.

3. DTC MVP
   - Read standard DTCs.
   - Clear DTC must remain out of scope unless explicitly approved.

4. Session replay
   - Replay saved raw logs through parser and UI.
   - Useful for debugging without car.

5. Adapter benchmark
   - Measure average latency per command.
   - Score adapter reliability.

6. Localization
   - Italian/English strings.
   - Technical terms consistent across UI and README.

7. Visual polish
   - Better automotive typography.
   - More informative connection state.
   - Configurable accent color.

8. Public compatibility matrix
   - List tested adapters.
   - Firmware/model notes.
   - Known quirks and workarounds.

9. CI enhancements
   - Upload `.xcresult` artifacts on failure.
   - Add SwiftLint or formatter once style stabilizes.
   - Add scheduled build against latest macOS runner.

## Suggested Next Sprint

1. Implement command queue/actor.
2. Implement `Elm327ResponseParser`.
3. Add typed ELM327 errors and tests.
4. Add BLE state machine readiness checks.
5. Add persistent diagnostic session export.

This sprint should happen before adding any real Jeep/4xe proprietary PID.
