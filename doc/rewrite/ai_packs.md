# AI packs, states and standings (approved 2026-10-06)

Status: approved by the user. Part A (engine forms) landed on `rewrite/engine-forms`; part B (AI) landed on `rewrite/ai-packs` through the steps in "Implementation status" below.

## Principles
- The **pack** is the unit of thinking; the **brain** is the unit of acting; **tactics** read only brain accessors and never know which one answers.
- Every AI mob is in a pack; a solo mob is a pack of one. One code path. Parity rule: a pack of one in the default state set passes every existing tactic test unchanged.
- No hand-rolled bookkeeping: no dirty flags, no combat booleans, no special lord/leader fields. Use the three engine forms below.

## Part A: engine forms (general, reusable outside AI)

### A1. `coalesce(interval)`: many triggers, one run
A part for `on_notice()` and `on_change()`: any number of triggers within the window give one run of the `then()`, at most once per interval (a value or an interval proc). It is built on `after_unique` (keyed by holder + hook). With no triggers, nothing is scheduled. It is cancelled with its holder.

Example:
`on_notice(/datum/notice/chunk_activity, coalesce(PROC_REF(perceive_interval)), then(PROC_REF(perceive)))`

### A2. `modes(nameof(var))`: exclusive state capabilities
A TRACKED var holds a capability type. The engine grants that capability (with the holder as source) and revokes the previous one, publishing a mode-changed notice.
- `go(/datum/capability/x)` is a then-part that sets the mode.
- `after_in_state(delay, go(...))` is a timer owned by the state, cancelled when the state is left.

Each state declares its own `every()`, `on_notice()`, `on_change()`, cadences and eligibility entries. It is reusable for machines (idle/working/broken), doors, reactor modes and so on.

### A3. Keyed standings: `standing()` / `standing_toward()`
- Shape: `standing(E, toward = subject, value, source = S, lasts = T, priority = P)`.
- Semantics are hold semantics: rows are source-attributed, released when the source dies, expire on their own, and are deduplicated per (source, subject).
- Subject: a datum (mob), a faction key, `STANDING_PLAYERS`, or `STANDING_ANY`.
- `standing_toward(E, subject)` composes the specific subject's rows, then the subject's faction, then players or any.
- Composition: the highest-priority row wins; on a tie, the most hostile wins.
- Results are cached per (E, subject) and invalidated by a notice when any row of E changes (or when a subject-wide row changes).
- It is built on the existing hold rows (`H_KEY` column in `code/engine/stats/store.dm`); it is not a new store.
- Holder: AI standing rows live on the `/datum/ai_brain` (`standing(brain, ...)`, `standing_toward(brain, subject)`), never on the mob. The rows are kept in the holder's own stat record, so the mob's hold list stays empty and its stats keep the no-holds fast path.
- Players: the form supports player subjects and faction-toward-player rows. Player reputation content (players holding stances toward factions, disguises) is NOT built now; only AI uses it.

## Part B: AI

### B1. Accessor seam (mechanical, no behaviour change)
Tactics call only brain accessors: `known_hostiles()`, `primary_target()`, `path_to(goal)`, `active_intents()`, `act(key, target, held)`, `act_waiting(...)`. They no longer read `brain.model.*` directly.

### B2. Per-behaviour cadence
Each `/datum/ai_behavior` has a `tick_interval`, defaulting to the current rates (0.25 s for combat tactics, 2 s for idle ones).
- The brain's action loop is `every(CAP_PROC(action_interval), ...)`, parked when there is no runnable behaviour or the brain is waiting on an op.
- IDLE and BACKGROUND tactics stretch ×3 when the mob is below RELEVANCE_VISIBLE. NORMAL and higher never stretch.
- Multi-step tactics (charge, aimed shot, grenade) are ops with `wait()`; the behaviour resumes on the op outcome.
- Movement is a shared step op paced by the mob's move delay.
- Re-selection is event-driven: knowledge changed, target assigned, behaviour ended or refused, damage taken. In engaged state there is also a minimum 1 s re-check.

### B3. `/datum/ai_pack`
- **Membership:** members are linked two ways, `links("ai_pack.members", "ai_brain.pack", a_many = TRUE)`.
- **Relevance:** each member holds its mob's relevance on the pack (MAX), so the pack is relevant if any member is.
- **Perception** runs once per pack through `coalesce` on chunk activity, member hurt and member heard:
  - candidates come from the chunk index over the chunks covering the members' vision;
  - friendlies and neutrals are noted without a line-of-sight check;
  - for each possible hostile, line of sight is checked from the nearest member first (sentinels first for dark or invisible targets), stopping at the first that sees it;
  - knowledge stores who was seen, not their classification. Members classify with their own cached `standing_toward()`;
  - the pack publishes only differences to its members.
- **Alert delay:** members other than the spotter learn of a sighting after a per-faction delay (default 0.75 s), within a communication radius.
- **Targeting:** done once per pack and published to members. Doctrine is per faction; the default is SPREAD with a cap of 2 members per target, and FOCUS is the alternative.
- **Shared paths:** a bounded flow field per goal, keyed by goal and navigation revision; each member reads its next step from it.
- **Formation:** join radius 5, leave radius 9 (hysteresis). A pack's upkeep `every(5 s)` handles splits, merges and chunk re-cover. An empty pack deletes itself.
- **Exclusions:** player-controlled mobs, unless on autopilot.
- **Rollout:** a per-faction `pack_join_radius`, 0 by default (solo). It is turned on first for wolves, spiders and xenos.

### B4. States (via `modes()`)
- **Default set:** calm, alert, engaged, fleeing, regroup. A faction or species can supply its own set.
- **Perception interval by state:**
  - calm: 5 s, event-only;
  - alert: 1 s;
  - engaged: 1 s on-screen, 2 s off-screen;
  - fleeing: 1 s.
- **Eligible tactics:** each state declares which tactics may run.
- **Transitions:** declared in the state that owns them.
- **Brains** may have their own states the same way (for example a stunned member while the pack is engaged).

### B5. Disposition via standings
`disposition_to()`, the `personal` list and the per-call `faction_data` lookups are replaced by standing providers (capabilities):

| Provider | Gives | Priority |
|---|---|---|
| `faction_relations()` (the existing faction tables as data) | base standing | 0 |
| `pack_member()` | ALLY toward packmates, source = pack | 50 |
| `serves(lord)` | inherits the lord's rows, source = lord | 55 |
| `grudges()` | HOSTILE toward the attacker, 5 min | 60 |
| tame/charm/pacify effects | as the effect sets | 80 |
| admin | anything | 100 |

### B6. Authority, roles, intents
- **Leader:** the member with the highest `STAT_AI_AUTHORITY`. Contributions:
  - lord role: +100;
  - alpha trait: +30;
  - health fraction: 0–20;
  - seniority: 0–10.

  The leader is re-elected when a member's authority changes.
- **Roles** are capabilities:
  - `lord`: authority and order tactics;
  - `sworn`: tether (never split off) plus `serves(lord)`;
  - `sentinel`: granted to members with special sight.
- **Orders are intents:** `intend(pack, /datum/ai_intent/x, ..., source = issuer, lasts = T)`. They are released when the issuer dies. Members' `evaluate()` reads them.
- **Migration of existing code:**
  - `set_leader()` and follow become joining the leader's pack as `sworn`;
  - broodmother and boss spawns get lord and sworn roles;
  - call for help and pack retreat become pack-level.

## Tests (focused only)
- **Engine forms:** coalesce, modes, standings.
- **Parity:** all 21 tactic tests with packs of one.
- **Packs:**
  - formation, split hysteresis, merge, leader or lord death, empty-pack deletion;
  - shared sight with alert delay, and grudges overriding the pack;
  - SPREAD and FOCUS targeting;
  - a counter proving one line-of-sight check per hostile;
  - a calm pack schedules zero timers;
  - flow field vs individual path.
- **Cost:** a focused cost test with packs of 1, 5 and 20, idle and engaged, before and after. No benchmarks.

## Implementation status (rewrite/ai-packs)

Landed, with focused tests (`dq_ai_cadence_*`, `dq_ai_pack_*`, `dq_ai_standing_*`, `dq_ai_state_*`, `dq_ai_roles_*`, `dq_ai_port_*`, `dq_ai_cost_*`; the 23 tactic tests and `dq_ai_tactic_shared_ops` stay green):

- **B1 accessor seam.** Tactics read only `known_hostiles()`, `known_friendlies()`, `last_attacker()`, `primary_target()`, `path_to()`, `active_intents()`, `act()`, `act_waiting()` (`brain/actions.dm`). `set_primary_target()` is the one write.
- **B2 cadence (partly).** `tick_interval` on every behaviour (default `DQ_ACTION_TICK`, 0.25 s), IDLE and BACKGROUND x3 below `RELEVANCE_VISIBLE`; the tactical loop is the action loop, armed `every(ai_action_interval)` from the active behaviour; events re-arm a stretched loop; a running behaviour no longer blocks re-selection (an event, or one second engaged, re-picks).
- **B3 packs.** `/datum/ai_pack` (`code/modules/combat_ai/pack/`): two-way link with brains, every brain in a pack (of one unless its faction sets `pack_join_radius`), formation by leader distance with join/leave hysteresis, merge, split, empty pack deletes itself; perception once per pack (`coalesce` on chunk activity, member hurt, member heard; candidates from a per-chunk living-mob index in `mob_chunks.dm`; line of sight is a lookup in the nearest member's `view()`, one per hostile; knowledge records who was seen, members classify with their own `disposition_to()`; alert delay and communication radius per faction; differences only); targeting once per pack (SPREAD cap 2, FOCUS); a shared flow field per goal for packs of more than one member (`pack/flowfield.dm`), keyed by goal and `GLOB.ai_navigation_revision`. Traced throughout (`pack.trace()`, `brain.trace()`).
- **B4 states.** `ai_state` is a TRACKED var with `modes()`: calm, alert, engaged, fleeing, regroup (`states/states.dm`); each state declares what it allows, its pack perception window and its own timers; a faction may supply its set (`faction_data.states`). State gates tactic eligibility (replacing the `primary_threat` check in `pick_and_run()`).
- **B5 standings.** `disposition_to()` is `standing_toward()`; providers: faction relations (the tables, priorities -1/0/1), pack_member (50, only while the pack has more than one member), serves(lord) (55), grudges (60, 5 minutes), effects (80), admin (100) (`standings/standings.dm`). The brain's `personal` list is gone.
- **B6 authority, roles, intents.** `STAT_AI_AUTHORITY` (lord +100, alpha +30 holds; health 0-20 and seniority 0-10 added); roles `lord`, `sworn`, `sentinel` as capabilities; `intend()` orders with a source and lifetime read through `active_intents()`; `set_leader()`/follow join the leader's pack as sworn; broodmother is a lord and its broodlings sworn; `call_for_help` rallies the pack; `pack_retreat` is pack-level (`roles/`).
- **B7.** `pack_join_radius` 5 for spiders, xenomorphs and wolves (wolves get their own `FACTION_WOLF`; the station dogs stay `FACTION_NEUTRAL`).

Also landed in the follow-up pass:

- **One loop.** The strategic capability is gone: the action loop (`every(ai_action_interval)`) is the brain's only loop. Its interval is the active tactic's, `DQ_ACTION_TICK` with a target and `DQ_CALM_TICK` (2 s) without; the slow work (re-reading what the mob holds, the backstop perception pass, idle selection, grace timers) runs inside it on its own cadence (`strategic_tick()`), and a calm brain with nothing to do parks (`park_calm()`, replacing the chunk hibernation) until its pack perceives something, it is hit or it is given a target (`wake_loops()`). The pack, not the brain, watches the mob chunks and perceives on activity.
- **Charge slam is an op with `wait()`** (`mob_attacks.charge`: a 1.2 s wait that cancels with its actor or target, then the dash and the slam). The brain waits on the op (`begin_waiting_op()`, busy until it ends) and the tactic ends with its outcome; replacing the tactic cancels the op. Aimed shot and grenade were already single-step ops (no wait to convert).
- **Members hold their mob's relevance on the pack** (`sync_relevance()`, a hold with the brain as source; a mob's `on_change(STAT_RELEVANCE)` re-syncs it).
- **Sentinels.** A member that sees through darkness, invisibility or walls (a sight flag, long night vision) is granted the sentinel role when asked; line of sight for a dark or invisible target is checked from sentinels first.
- **Effects use `place_effect_standing()`**: the technomancer control spell and the capture crystal's follow place their ally standing with the spell or crystal as source (it goes with them). **Lords and sworn**: `serve()` makes the lord a lord; carrier swarmlings and glitch-boss illusions are sworn to their parents, as broodlings are.
- **Engine:** `modes()` grants the initial state to a plain datum when it is made (the generator marks a datum type with `modes()` as `lifeform_declared`; `lifeform_datum_new` runs `modes_init`); no manual `modes_sync()` remains.

Perception cost, measured by `dq_ai_cost_packs_of_1_5_20` (steady-state passes, the old per-brain loop includes its list publishing): a pack of 5 or 20 is strictly cheaper than its members alone (engaged x20: 18 ms against 85 ms, view builds 5 against 100); an idle solo pack is at or below the old pass; an engaged solo pack is about 1.1 to 1.7 times the old pass (the cost of the pack machinery around one `view()`).
