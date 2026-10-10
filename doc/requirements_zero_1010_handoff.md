# Boolean requirement burn-down: first sweep

Branch: `codex/requirements-zero-1010`, based on `origin/master` at `2e4cbdfd1d`.

## Counts and scope

`requirement_bool`: **831 -> 664** normalized baseline rows, a reduction of **167**.
The baseline update removed entries only. No ceilings, exemptions, annotations,
resolver behavior or operation priorities were added or changed.

Actual requirement callbacks now return null on success and their original
refusal on failure. Paired Boolean adapters were removed in air alarms, cell
chargers, rechargers, airlocks and tape recorders; their existing reason providers
are used directly. Pure selection conditions use native `when(PROC_REF(...))`,
whose Boolean evaluation matches the former requirement wrapper. Boolean
selectors and unrelated same-named callbacks were retained.

The sweep covers atmos controls, machinery, power, shared item/machine
capabilities, body items, clothing, containers, food, hydroponics, mining,
paperwork, projectiles, research, ship consoles and related pinned content.
Every edited baseline line was closed completely: no `req_bool` was left on a
changed line and no fingerprint was re-keyed.

## Old behavior and checks

Before production edits, `dq_conversion_pin` passed all **979 recorded types**;
the boot gate was clean and the test compile reported zero errors. Six new
old-code pins were recorded and committed separately (`211cbe14ab`): laundry
basket, omni filter, omni mixer, shutoff valve, airlock and battery rack.
Existing recorded pins cover the remaining converted content and shared
capability consumers. No existing pin was re-blessed.

The real laundry-basket lift test now asserts the occupied-second-hand refusal;
the natural-weapon test checks the self-attack refusal after its cooldown ends.
The post-edit lane-ready results will be recorded here after verification.

## Semantic review and remaining work

The refreshed pre-sweep inventory separated **556 mechanical candidates** from
**275 semantic-review rows**. Ten samples were sent before broader semantic
conversion: tape record/record refusal, paper-bin hand/limb refusal, casino busy
reason precedence, AIcore panel selector versus requirement, inherited machine
hand admission, storage capacity/reason decoration, pod passenger admission,
edible open/shut reasons, honey-extractor mixed returns, and paper mouth-wiping
selection. These counts describe the pre-sweep classification, not the current
remaining count.

Still pending: the remaining Boolean requirements and `REQ_*` forms, followed by
machinery/power change channels and looks, then tracked access lists. Hard bans
will be added only once their respective production counts reach zero.

The old `round3-stun-asks` branch should be dropped rather than merged wholesale:
master already contains the stun bridge and most request conversions, while
the old patch retains obsolete Boolean adapters and regresses scanner behavior.
Its remaining replicator print-choice behavior should be considered separately.

## Cache cleanup

Deletion of the three user-named obsolete caches (`dmb-native-iterations`,
`codex-ownership-analyze`, `codex-interim-analyze`) was rejected by automatic
approval review with only "blocked by policy". Nothing was deleted. Current
native compiler output and the shared analyzer, Bun and Verdigris caches were
left intact.
