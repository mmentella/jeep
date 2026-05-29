# ELM327 Command Queue

## Goal

The ELM327 adapter is a single request/response channel. Polling, initialization and PID Lab manual commands must not write concurrently to the same adapter because responses can be interleaved or consumed by the wrong caller.

`Elm327CommandQueue` is the only application component allowed to call `ObdTransport.send(_:)`.

## Layers

- `ObdTransport`: raw BLE/mock I/O. It writes one command and returns raw text assembled by the transport.
- `Elm327CommandQueue`: serial actor. It guarantees one command in flight and applies per-command timeout.
- `Elm327FrameParser`: parses raw ELM327 text into typed `Elm327Response` or typed `Elm327Error`.
- `Elm327Client`: app-facing protocol client used by initialization, polling and PID Lab.
- `ObdPollingScheduler`: polling loop. It uses `Elm327Client`, never the transport directly.
- `PidLabView` / `ObdDashboardViewModel`: manual commands pause polling, execute through `Elm327Client`, then resume polling.

## Command Model

Each command is represented by `Elm327Command`:

- `command`: normalized command string.
- `timeout`: per-command timeout in seconds.
- `expectedResponsePrefix`: optional normalized prefix, for example `410C` for RPM.
- `source`: `initialization`, `polling`, `manual`, or `diagnostic`.

## Queue Behavior

1. Caller submits `Elm327Command`.
2. Actor serializes access.
3. Actor calls `ObdTransport.send(_:)`.
4. Actor races transport completion against timeout.
5. Raw response is parsed by `Elm327FrameParser`.
6. Caller receives `Elm327Response` or a typed `Elm327Error`.

Because `Elm327CommandQueue` is an actor, concurrent callers await their turn automatically.

## Parser Behavior

`Elm327FrameParser` keeps both:

- `rawText`: exact response from the transport.
- `normalizedText`: uppercase, prompt-stripped text for matching/parsing.

It handles:

- `OK`
- `NO DATA`
- `STOPPED`
- `SEARCHING...`
- `BUS ERROR`
- `CAN ERROR`
- `UNABLE TO CONNECT`
- `BUFFER FULL`
- `RX ERROR`
- ECU negative response frames beginning with `7F`
- malformed frame text

The parser preserves frame lines, optional CAN headers such as `7E8`, and parsed bytes.

## PID Lab Interaction

Manual commands:

1. pass through `ObdCommandPolicy`;
2. pause `ObdPollingScheduler`;
3. execute through the same `Elm327CommandQueue`;
4. store raw response in PID Lab log;
5. resume polling if it was previously active.

No manual command bypasses the queue.

## Current Non-Goals

- No Jeep/4xe proprietary PID implementation.
- No write/programming services.
- No ECU coding.
- No Bluetooth Classic/SPP support on iOS.
