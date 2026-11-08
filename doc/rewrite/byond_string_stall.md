# The BYOND string-building stall (November 2026)

A station blast's minute after held one tick for 0.8–2.8 s, several times. The cause was a step in BYOND itself, hit by DM code that
builds many keys of one shape in a row. This note records what the `alloc_stall` bench (`code/tests/benchmarks/alloc_stall.dm`) showed,
what is fixed, and what is still unexplained.

Run it: `tools/build/build.sh bench --scenario=alloc_stall -DCITESTING_FULL_MAP --arg=facts=5000 --arg=kinds=<k1,k2,...>`. Each op is
timed alone (`TICK_USAGE_REAL`), and every op over 20 ms is logged as `ALLOC_STALL <kind> #<op>` in the runtime log. Full map, about
512k atoms and 720k datums live.

## What was measured

| Probe (5000 ops unless noted) | What one op does | Stalls (≥ 20 ms, each 0.6–1.3 s) |
|---|---|---|
| `datums` 400k, `lists` 400k, `slots` 300k | make and keep a datum / a list / a datum with a handle slot | 0 (worst op 1.4–14 ms) |
| `strings` 1M | keep `"alloc-stall-[i]-[world.time]"` | 0 |
| `string_churn`, `datum_churn`, `list_churn` 300k | make and drop at once | 0 |
| `ref_kept`, `ref_prefixed_kept`, `ref_suffixed_kept` | keep a datum and `REF(D)` / `"click:[REF(D)]"` / `"[REF(D)]:click"` | 0 |
| `busy` | 50 multiplications, no allocation | 0 |
| `fact_strings` | keep `"infrastructure-damage:[handle_text(h)]"` and `...:1` | 2: at op 491 and 981, then none |
| `fact_short_prefix` | keep `"i:[handle_text(h)]"` and `...:1` | 2: at 491 and 981 |
| `fact_suffix` | keep `"[handle_text(h)]:infrastructure-damage"` and `...:1:...` | 0 |
| `handle_only` | keep `handle_text(h)` and `"[handle_text(h)]:1"` | 0 |
| `num8_kept` 20000 | keep `num2text(n, 8)`; past 1e8 that is exponent text | 7, from about op 13000 (where n passes 1e8), every ~982 |
| `window_prefix` | `"seq:[num2text(n, 8)]:rewake"`, about 1000 held, oldest dropped | 5, every ~982 ops |
| `window_suffix` | the same with the number first | 4, every ~982 ops |
| `small_window_prefix` | `"seq:[i]:rewake"` (small integers), 1000 held | 3, from op ~2990 |
| `same_string` | `"seq:[7000000 + i]:rewake"`: always the same text (`7e+06`), 1000 held | 5, every ~981 ops |
| `drain` 3000 | the real contract damage-report drain, no blast | before the fix: 6 (1.3–2.8 s), 30.9 s wall. After: 0, 12.6 s wall |

What holds across the runs:
- It is deterministic: the same probe stalls at the same op counts run after run (491/981; every ~981).
- It is not allocation, churn, slot-table growth or the `REF()` shape: those probes never stall, and pre-creating 300k strings at boot
  does not prevent it.
- It is not uniqueness: `same_string` builds the same text every time and still stalls every ~981 ops.
- It is not the machine descheduling the process: the busy loop beside it never stalls.
- The pattern that stalls is building many strings of one shape in a row, with a number formatted into them. The varying part first
  helped where the number came from `handle_text()` (`fact_suffix`, the real drain). It did not help for the sliding windows
  (`window_suffix`). The mechanism inside BYOND is not known.

## What changed

- The contract keys that a blast builds thousands of now put the varying part first (`contract_infrastructure_fact_id()` /
  `contract_infrastructure_occurrence_id()` in `code/content/contracts/social_framework.dm`, the event dedup key in `publish_event()`,
  the opportunity window's fact key in `revise()`). The real drain went from 6 stalls to none, and the supermatter bench's minute-after
  worst tick from 5.4 s to 0.34 s.
- The contract drain also time-slices its chunks, so no single job step runs long enough to meet one (`flush_damage_chunk()`).

## Rules for new code

- In a loop that builds hundreds of keys or more, don't make them `"<constant prefix>[number]"`. Prefer a numeric key or an alist
  keyed by the number. If it must be text, lead with `handle_text(n)` (or the number's text) and put the constant after.
- Time-slice long DM loops (a `job()` with a budget). A stall can only land inside work that is running, so a step that stays small
  cannot hold a tick for long.
- Player-visible ids (`DQ-CE-<serial>`) are left as they are. Change one only if a bench shows it stalling, and then keep the display
  string separate from the key.

## Open

- No lint: the shapes that stall are not crisp enough to flag without false positives (`window_suffix` stalls with the number first,
  and `same_string` stalls with no new string at all). A ratchet would need the mechanism first.
- The timer-key families (`"seq:[idx]:rewake"`, `"activation:[serial]"`, `"after_init:[index]"`, ...) match `small_window_prefix`. They
  are made at a lower rate (tens per second in the steady-state bench) and sit in `code/engine/` (the engine agent's area). Probe them
  under load before changing them.
