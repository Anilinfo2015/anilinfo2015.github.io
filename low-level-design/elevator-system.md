---
title: "Design an Elevator System"
series: "Low-Level Design Interview Playbook"
readingTime: "~3 minutes"
difficulty: Advanced
date: 2026-07-10
topics: ["Low-Level Design", "Elevator System", "State Machine", "Concurrency"]
---

# Design an Elevator System

Model hall calls, car assignments, directional stops, and acknowledged door transitions in a single-controller elevator simulator.

LLD stages: [Requirements](#requirements) → [Core entities](#core-entities) → [API or system interface](#api) → [High-level design](#high-level-design) → [Deep dives](#deep-dives).

## 1. Requirements
{: #requirements }

### Functional requirements

Model hall calls, cabin destinations, car movement, doors, and unavailable cars. Coalesce repeated calls and reassign hall calls when a car becomes unavailable.

### Non-functional and execution constraints

Concurrent producers submit events to a single controller loop in one process. This is a simulator, not a safety-certified lift controller. State is volatile; restart requires a fresh sensor snapshot. With E cars and F floors, dispatch costs O(E), and ordered stop insertion costs O(log F).

<a id="2-out-of-scope"></a>

### Out of scope

Exclude emergency braking, motor control, passenger identification, and optimal traffic prediction. Hardware safety interlocks belong to a separate certified controller. This component issues high-level commands and consumes acknowledgements; it must not pretend that issuing a command proves movement occurred.

<a id="3-model-and-invariants"></a>
<a id="model-and-invariants"></a>

## 2. Core entities
{: #core-entities }

`Controller` owns all car states and the hall-call assignment map. Each `Car` owns current floor, travel direction, door state, ordered cabin stops, and assigned hall calls. A `DispatchPolicy` reads snapshots without mutating cars.

A hall call has at most one assigned car. Duplicate `(floor, direction)` calls coalesce until served. Movement is permitted only after doors report closed. Floors stay within the building range, and an unavailable car receives no new work.

```mermaid
stateDiagram-v2
    Idle --> Moving: closed-door acknowledgement
    Idle --> DoorOpen: call at current floor
    Moving --> DoorOpen: arrival at eligible stop
    DoorOpen --> Idle: dwell elapsed and doors closed
    Idle --> Unavailable: fault
    Moving --> Unavailable: fault
    DoorOpen --> Unavailable: fault
```

<a id="4-public-contract"></a>
<a id="public-contract"></a>

## 3. API or system interface
{: #api }

`call(floor, direction) -> CallId` validates floor and rejects impossible outward calls at terminal floors. Repeats return the active call ID. `select(carId, floor) -> Accepted` coalesces duplicate destinations; unknown or unavailable cars return `NotFound` or `Unavailable`.

`onEvent(carId, epoch, sequence, event) -> Applied|Ignored|InvalidEvent` accepts ordered sensor events; duplicate or older sequence numbers are ignored. `tick(monotonicNow) -> Commands` advances dwell timers without sleeping. `snapshot() -> BuildingState` returns an immutable copy. Invalid input never creates partial assignments.

<a id="5-core-flow"></a>
<a id="core-flow"></a>

## 4. High-level design
{: #high-level-design }

On a hall call, `Controller` first checks its assignment map for an existing active call. Otherwise it passes car snapshots to `DispatchPolicy`, which chooses the nearest available car already approaching in the requested direction; if none qualifies, choose the nearest available car, breaking ties by car ID. The controller records the assignment and updates the chosen car's stops before issuing commands through the adapter.

An idle car heads toward its nearest assigned stop. A moving car follows a directional sweep, serving cabin stops and same-direction hall calls ahead before reversing. Opposite-direction calls remain assigned for the return sweep; if only opposite-direction work remains ahead, travel to the furthest such call before reversing. At an eligible stop, acknowledge arrival, request door opening, and mark calls served only after the door-open acknowledgement. Start dwell timing from that acknowledgement using a monotonic clock.

## 5. Deep dives
{: #deep-dives }

<a id="6-trade-offs-and-extensions"></a>

### Trade-offs and extensions

Nearest-car dispatch is predictable but can produce poor tail waits. A bounded extension assigns priority to calls exceeding a wait threshold, while preserving car movement invariants. Stop sets bound stored work to O(EF); repeated button presses cannot grow memory indefinitely.

<a id="7-concurrency-and-failure-handling"></a>

### Concurrency and failure handling

The event loop serializes assignment and stop updates. Adapter calls run outside it; commands carry IDs and acknowledgements return as events. A fault requeues hall calls, but cabin destinations remain attached to the unavailable car for operator handling. Queue overflow returns `Busy`, never silent acceptance. Restart changes the epoch and reconciles physical state before movement; volatile requests are not claimed durable.

<a id="8-test-cases"></a>

### Test cases

- Cars at floors 1 and 8; upward call at 2: assign car at 1.
- 1,000 concurrent upward calls at 4: one active call ID and one assigned stop, not 1,000 queued stops.
- Downward call at floor 0 in a 0–9 building: `InvalidFloorDirection`.
- Door-close acknowledgement missing: no movement command.
- Assigned car faults: hall call becomes pending for reassignment.
- Duplicate arrival sequence: no duplicate door cycle or call completion.

[Question catalog](../interview-guide.html) · [Article template](interview-template.html)
