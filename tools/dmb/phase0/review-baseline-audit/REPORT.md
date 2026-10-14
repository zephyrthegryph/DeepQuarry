# Offline frozen-baseline audit

This is a reanalysis of preserved channels, not a new runtime reproduction. No DreamDaemon, DreamMaker, Cargo, compiler test or mutable compiler/source operation was launched. Existing streaming normalizer reads one line at a time, retains counts and at most16 first-line examples per identity; SHA256 uses1MiB blocks. Small result objects are loaded independently. Inputs are unchanged.

## Contract and provenance

DESIGN rev5 §5.3 requires the same pinned source/private compatibility edits, compiler/engine binaries, runtime limits/map substitutions/Verdigris and seed policy; complete raw statuses/messages/runtime records; three runs per producer; normalized message+procedure+source/line counts; separate same-output variability; and an explanation or recorded acceptable-decision for every stable divergence. Offline replay cannot establish new compiler runtime behavior.

The preserved source commit is ac1af55d1a9a8e023e46bd058be59ed82c503f52, comparison dcd1b1f39fe14bd6a3ad65fd8d2bc1da. The saved source-snapshot receipt is SHA256 ca20759e24dd9b87afb027fea8dac90cda2786dc3420c6391ad3452579f14e26. Runtime engine is516.1687. Complete receipt assertions/configuration are retained in the original evidence.json; provenance.json binds inspected current files and exact normalization command.

Pinned DMBs: BYOND 8ff8911a26547da3e2cb49daa185b45cc723b4fc2f73d4cbc48efa43f20e5775; preserved native174359e9e849bdd610043f5879bbb781c35d406fe92142b295f822d19130a6ed. Original normalized report1e39336baf63c6a2e9132a66dbff9666c712eba0348d61b5019d45aaf14c95c2; preserved-comparison190afc7bf05fff744e39fc7ccebc2aa67e8f09ac6ac9b63f5a4849c8b6b4ccb9.

## Finite observed differences

1089 selected tests; no missing tests;40 stable different complete signatures;79 variable signatures. Stable categories overlap:4 status differences,6 message differences,37 runtime-count differences;34 are runtime-count-only. Variable signatures comprise10 status-variable,68 runtime-only and1 message+runtime-variable. Three observations are descriptive, not proof of distribution equality.

All4 stable status differences are BYOND failure versus native pass: dq_covert_market_agent_integration, dq_destroy_transaction_phase_timing_recorded, dq_lifecycle_sandbox, dq_power_idle_apc_and_smes_sleep. Two further stable failure-message differences are dq_latent_destroy_parity and dq_power_apc_cycle. Neither native passes nor higher pass counts establish correct semantics. classification.json retains exact selected rows and distributions.

49 selected runtime identities;2 vary within one producer; zero stable located selected-channel differences. That zero is severely coverage limited: BYOND structured409 events/run includes358 unlocated and409 ownership-unavailable; native102 events/run are all unlocated/unowned. Native raw-channel parser admits zero events and records3070943/3072717/3071882 parse failures across repetitions (3071005 preserved), principally blank-origin records. These are unresolved records, not absence of errors. BYOND raw records have source/line but no procedure/test ownership. Structured/raw totals must not be summed or inferred to correspond.

## Runtime gate still open

Six selected observations reached exact selection coverage and suite/shutdown markers, but BYOND exit codes were[-1073741819,0,-1073741819]; native[0,0,0]. Two terminal access violations invalidate a normal-exit claim. Engine prelaunch closure is proven5/6; BYOND1 missing audit is an explicit limitation. Equality/complete comparison coverage remain false. Stable divergences still need causal explanations or recorded acceptance decisions.

POWER_RUNTIME_AUDIT preserves concrete static differences (kind62 list-default token versus Null; shared versus Src random_seed) but does not establish runtime causality. Preserved raw bounds records: BYOND3087060; native3068028, all native blank-origin. Native unlocated events cannot be assigned to power_bridge or a particular test. Operand/state observations are missing.

## Next controlled experiment

First run a narrowly selected source-aware power/APC control against the exact frozen pair/config/FFI identities, serially, with prelaunch closure on every run and complete exit proof. Record test ownership, normalized procedure+source/line, receiver identity, events index/length, power_regions index/length and startup/retired phase at the two nested reads; preserve rejected/unlocated events separately. Do not alter behavior or assign an error to a proc from a stack guess.

Then repeat the unchanged1089 selection3times per producer with pinned limits, compatibility edits, map substitutions/Verdigris and any available fixed seeds; retain raw+structured channels and explain the terminal BYOND crashes. Compare the new compiler output separately against that controlled baseline; do not label this offline normalization as a new reproduction. Static CFG debug coverage may locate missing emission but cannot substitute for runtime identity/operand evidence.

## Reproduction result

The existing normalizer reproduced normalized.json **byte-for-byte** (SHA2561e39336baf63c6a2e9132a66dbff9666c712eba0348d61b5019d45aaf14c95c2). Existing preserved_observations reproduced the preserved-comparison JSON object exactly: True (after JSON tuple/list normalization). This confirms deterministic reanalysis of saved channels only. provenance.json binds60 files, both helper implementations and exact input/output hashes.
