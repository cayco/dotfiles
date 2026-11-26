---
name: loxone-layout
description: Maintain clean, grid-snapped, zero-crossing, pin-sorted visual layout in Loxone Config (.Loxone projects via loxone-config MCP code_run/code_query). Activate this skill WHENEVER adding, editing, rewiring, refactoring, or cleaning up blocks or connections on any Loxone Config page so every modification leaves zero overlapping blocks/marks, zero crossing wires, and strictly sorted side-by-side inputs/outputs.
---

# Loxone Config Clean Layout & Zero-Crossing Standard (`loxone-layout`)

Whenever you add, move, rewire, or refactor blocks on **any** Loxone Config page via the `loxone-config` MCP server (`code_run` / `code_query`), **you must enforce this layout standard before finishing** so Loxone pages never accumulate crossed wires, overlapping reference marks, or out-of-bounds blocks.

---

## 1. Exact Loxone Config 17.3 Geometry Laws

| Constant / Formula | Value | Notes |
|---|---|---|
| Grid quantum | `96 px` | Snap all block/mark coordinates to multiples of `96`. |
| Pin row pitch | `192 px` | Vertical distance between consecutive visible pins (`2 * 96`). |
| Sheet bounds (`page.bounds`) | `left: 1133, top: 566, width: 22112, height: 15705` | `right = 23245`, `bottom = 16271`. Keep top row `y >= 864` and `x >= 1248` (`4320` when block has left attachments). |
| Narrow block (`width == 1345`) pin `k` | `y = block.y + 288 + k * 192` | 1-line header (`288 px`). |
| Wide block (`width == 2689`) pin `k` | `y = block.y + 480 + k * 192` | 2-line header (`480 px`). |
| Standalone `InputRef` / `OutputRef` / `Memory` (`2113 × 193`) | `y = block.y + 0` | `baseDy = 0`. |
| Left attachment `X` (`InputRef` / `input` mark) | `x = host.x - 3072` | Footprint `2113 × 193` (`959 px` horizontal stub gap). |
| Right attachment `X` (`OutputRef` / `Memory` / `output` mark) | `x = host.x + host.size.width + 959` | Universal formula: `+2304` (`1345`-wide), `+3072` (`2113`-wide), `+3648` (`2689`-wide). |
| Direct chain horizontal step (`A -> B`) | `B.x = A.x + snap96(A.size.width) + 384` | `+1824` after narrow `1345`, `+3168` after wide `2689`. Never use raw `width + 384` before snapping! |
| Direct `InputRef -> OutputRef` bridge | `OutputRef.x = InputRef.x + 2496`, same `y` | `2113 + 383 px` gap (`4609 × 193` pair). |

> **Comparator Pin Indexing**: Blocks like `Greater`, `GreaterEqual`, `Less`, and `Equal` expose `Input1`/`Input2` in `det.connectors.parameters` (not `inputs`). Always build `inIdx` from `inputs.filter(c => !c.hidden)` followed by `parameters.filter(c => !c.hidden)`.

---

## 2. Zero-Crossing Wiring & Pin-Sorting Rules

1. **When to Keep Direct Wires (`reference: false`)**:
   - Local `1-to-1` `InputRef -> HostBlock` (`x = host.x - 3072`) and `HostBlock -> OutputRef / Memory` (`x = host.x + width + 959`).
   - Pure `1-to-1` horizontal chains `A -> B` (`<= 3` blocks) where `A` has **no** other outputs (`OutputRef`, `Memory`, `referenceMark`, or `OutputAPI`), `B` has **no** other inputs (`InputRef` or `referenceMark`), and `B.y` is aligned so `A`'s output pin `Y` equals `B`'s input pin `Y` (`dy = 0`, 100% straight horizontal wire).
   - Pure `1-to-1` `InputRef -> OutputRef` bridges.
2. **Convert All Other Logic-to-Logic Wires to `reference: true`**:
   - Any fan-out (`1 -> N`), fan-in (`N -> 1`), feedback edge (`x2 <= x1`), or cross-column connection **must** use `reference: true` so Manhattan orthogonal routing never braids or crosses in front of pins.
3. **One Local `InputRef` Per Input Pin (Split Shared `InputRef`s)**:
   - Never fan out one `InputRef` across multiple distant blocks with diagonal wires. Create a dedicated local `InputRef` per target pin via `cfg.add_object_ref({ source_uuid, page_uuid })` — **except**:
     - Never split an `InputRef` whose active edge is on a `hidden: true` output pin (e.g., digital `Q` hidden while `AQ` is visible).
     - If an `InputRef` also has a cross-page `reference: true` edge, convert its local outgoing edges to `reference: true` and place that `InputRef` as a standalone `5185`-wide mini-brick (`InputRef` + right `referenceMarks`).
4. **Never Duplicate `OutputRef`s**:
   - If `>= 2` blocks on a page feed the same `OutputRef`, convert **all** incoming edges on that `OutputRef` to `reference: true` and place the `OutputRef` as its own standalone `5185`-wide mini-brick (`left referenceMarks` at `x`, `OutputRef` at `x + 3072`). Never attach an `OutputRef` at `host.x + width + 959` if it also has a `reference: true` input (its input mark at `OutputRef.x - 3072` would collide with `host`!).
5. **Strict Pin-Order Sorting & Side-by-Side Grouping**:
   - On every block, sort all left items (`InputRef` + `input` `referenceMarks`) and all right items (`OutputRef` + `Memory` + `output` `referenceMarks`) strictly by `(pinIdx, isMark, title)`.
   - Place items feeding the **same** pin immediately adjacent (`y = Math.max(host.y + baseDy + pinIdx * 192, prevY + 192)`), skipping any `y` occupied by a kept direct horizontal wire. This guarantees zero crossing stub wires at block entrances/exits.

---

## 3. Critical SDK & Runtime Pitfalls (Must Follow)

1. **Live Mark Handle Rule (Ephemeral `referenceMarks` UUIDs)**:
   - `uuid`s inside `cfg.get_page().page.referenceMarks` are **ephemeral** — any subsequent `disconnect_blocks` / `connect_blocks` call invalidates previously returned mark UUIDs (`NOT_FOUND`).
   - **Mandatory Pattern**: Pre-compute exact `(x, y)` target slots for all `reference: true` connections first. Then, inside the reconnect loop, call `cfg.update_block({ uuid: res.connection.referenceInUuid, position: inSlot })` and `cfg.update_block({ uuid: res.connection.referenceOutUuid, position: outSlot })` **immediately on the very next line** after `cfg.connect_blocks(...)`.
2. **Cross-Page Mark Preservation**:
   - Reconnecting a cross-page `reference: true` edge recreates **both** endpoints' marks, resetting the remote page's mark to `auto`! Always snapshot remote-page `referenceMarks` positions before reconnecting and immediately restore the remote endpoint's `{ x, y }` via `res.connection.referenceInUuid` / `referenceOutUuid`.
3. **Preserve Connector Inversion (`inverted`)**:
   - `disconnect_blocks` + `connect_blocks` can reset `inverted` on the target input/parameter. Always read `wasInverted` from `cfg.get_block({ uuid: toUuid })` before disconnecting and restore via `cfg.set_connector_inverted` if changed.
4. **Immovable `OutputAPI` Marks (`HeatIRoomController2`, `AcControl`, `Ventilation`)**:
   - `OutputAPI` links (`Irc2`, `ACCC`, `Cco`, `ACc`, `Rvco`) are **not** in `cfg.get_connections()` — they appear only in `page.referenceMarks` (`connectorKey === "OutputAPI"`) near the bottom of the block (`block.height - 217`).
   - Always reserve their `2113 × 193` bounding boxes during brick packing, add their `position.y` to `occupied`, and when `host.y + baseDy + totalRegularOutputs * 192 > apiMinY` (e.g., `AcControl` with 6 regular outputs above 2 `OutputAPI` marks), start regular outputs at `Math.max(host.y + 96, apiMinY - totalRegularOutputs * 192)` so sibling pins (such as dual `tempTarget` marks) stay grouped side-by-side above `OutputAPI` without straddling it.
5. **`Memory` (Merker) Blocks (`2113 × 193`)**:
   - Treat `type === "Memory"` geometry identically to `OutputRef` (`baseDy = 0`, right attachment `dx = +width + 959`). Ignore hidden `Memory.AQ -> InputRef.AI` bindings in canvas wire checks (no wire is drawn on canvas for hidden connectors).
6. **Hidden `1×1` Tree Device Refs at `(0, 0)` & Orphan `InputRef`s**:
   - Inline Tree device bindings (`PresenceDetector`, `Burglar Alarm`) appear as `size.width <= 10` objects at `(0, 0)`. **Never** move, reset, or include `size.width <= 10` objects in OOB/collision checks.
   - Never delete unconnected `InputRef`s unless explicitly requested by the user.
   - Keep `Text` (`Note`) blocks positioned directly above the block they document (`ry = 0`), reserving `max(note.width, 3840)` width.
7. **Cross-Page Block Moves & Saving**:
   - `cfg.update_block` cannot move blocks across pages (`page_uuid` is unsupported), and deleting/recreating blocks destroys UUIDs referenced by Home Assistant, `LoxAPP3.json`, `permissions.bin`, and `CentralMusic`/`CentralLight`. To stage blocks for manual `Ctrl+X -> Ctrl+V` by the user, isolate them cleanly below `y = 17472` (`> 16271`) and lock all their marks via immediate live handles (otherwise Loxone clamps `auto` marks below `16271` to `y = 0`).
   - Never call `save_project` without explicit user approval.

---

## 4. Mandatory Post-Modification Verification Gate

After **any** block addition, move, or rewiring on a page, run `references/align_and_verify_page.js` (or an equivalent check in `code_run` / `code_query`) and confirm **all** geometry metrics equal **`0`** before completing the task:
- `bvb === 0` (zero block-vs-block overlaps)
- `mvb === 0` (zero mark-vs-block overlaps)
- `mvm === 0` (zero mark-vs-mark overlaps)
- `upperOob === 0` (zero blocks or marks outside `page.bounds` `[1133..23245] × [566..16271]`)
- `clampedAtZero === 0` (zero marks clamped to `y = 0`)
- `disordered === 0` (100% of left/right attachments strictly monotonic in pin order with zero duplicate `Y`)
- `backwardWires === 0` and `wireHits === 0` (zero backward or colliding visible direct wires)
