# Final Phase 0 observation classification

Evidence: `D:/dmb-native-v2-phase0/parity-final-corrected-20261007-b/normalized.json` and `preserved-comparison.json`. Full per-test classifications and raw power-bridge counts are saved alongside them in `variable-classification.json`. This report classifies existing observations; no compiler or runtime was launched.

Normalized SHA256: `1E39336BAF63C6A2E9132A66DBFF9666C712EBA0348D61B5019D45AAF14C95C2`. Preserved-comparison SHA256: `190AFC7BF05FFF744E39FC7CCEBC2AA67E8F09AC6AC9B63F5A4849C8B6B4CCB9`.

## The 79 variable tests

| Classification within either producer, three observations | Count |
| --- | ---: |
| Status varies (may also vary in message/count) | 10 |
| Status fixed; runtime count only varies | 68 |
| Status fixed; both normalized message and runtime count vary | 1 |
| Message only | 0 |

The one message/count case is `dq_constraint_declarations_compile`. Thus 79 variable signatures are not 79 pass/fail changes. Status0/1 below is retained directly from the result records (0 pass,1 failure).

| Test suffix | BYOND statuses | Native statuses |
| --- | --- | --- |
| dq_contract_sustained_evidence | 1,0,0 | 0,0,0 |
| dq_gas_dependencies_wake_exact_devices | 0,0,1 | 0,0,0 |
| dq_idle_auxiliary_machines_hibernate | 1,0,1 | 0,1,0 |
| dq_item_takes_atmos_heat | 0,0,1 | 0,0,0 |
| dq_medical_trial_deferred_availability | 0,0,1 | 0,0,0 |
| dq_power_monitor_hibernates_until_grid_warning | 0,1,0 | 1,0,0 |
| dq_radiation_dose_falls_off | 0,1,0 | 0,0,0 |
| dq_reactor_timers_fire_at_their_tick | 1,0,1 | 0,1,1 |
| dq_shutoff_wake_is_network_local | 1,1,0 | 0,0,0 |
| dq_station_alarm_component_is_sealed | 0,1,0 | 0,0,0 |

## Stable cross-producer differences

40 tests have stable different complete signatures. Categories overlap:4 differ in status,6 in normalized message,37 in runtime count. Of these,34 differ only in runtime counts. All four status differences are BYOND1,1,1 versus native0,0,0:

- `/datum/unit_test/dq_covert_market_agent_integration` — BYOND message: FAILURE #<number>: [<number>:<number>:<number>] Runtime in code/game/atoms_movable.dm,<number>: /mob/living/carbon/human still holds contents/latent entries entering Destroy() -- the destroy transaction's contents phase should have released them
- `/datum/unit_test/dq_destroy_transaction_phase_timing_recorded` — BYOND message: FAILURE #<number>: [<number>:<number>:<number>] Runtime in code/modules/unit_tests/dq_destroy_transaction_tests.dm,<number>: list index out of bounds
- `/datum/unit_test/dq_lifecycle_sandbox` — BYOND message: FAILURE #<number>: [<number>:<number>:<number>] Runtime in code/modules/unit_tests/dq_lifecycle_tests.dm,<number>: Cannot read null._active_timers
- `/datum/unit_test/dq_power_idle_apc_and_smes_sleep` — BYOND message: FAILURE #<number>: [<number>:<number>:<number>] Runtime in code/modules/power/power_bridge.dm,<number>: list index out of bounds

The two additional stable message differences retain failure status on both producers: `dq_latent_destroy_parity` (BYOND expected-value assertion versus native contents/latent destruction runtime) and `dq_power_apc_cycle` (BYOND power-bridge bounds runtime versus native isolated-APC powered assertion). These are meaningful error-path differences, not evidence either compiler is correct. Runtime-only count differences remain errors worth investigating, even where tests pass.

## Power-bridge evidence

Raw audit channel, `code/modules/power/power_bridge.dm`:

| Location/message | BYOND1 | BYOND2 | BYOND3 | Preserved BYOND |
| --- | ---: | ---: | ---: | ---: |
|85, list index out of bounds |1407|1303|1283|1099|
|107, Cannot execute null.read info(). |1407|1303|1283|1099|
|151, list index out of bounds |111|111|111|111|
|154, list index out of bounds |149|138|136|117|

No matching raw identities occur in the three native audits or preserved native audit. This is raw-channel evidence only; selected structured events lack complete ownership/source mapping. Do not add these counts to structured totals or assign all events to the APC test. In particular, the stable APC-cycle assertion difference survives despite absence of these raw native errors. Causes remain unknown here; `power-rootcause.json` is a separate investigation, not established by these counts.

## Preserved runs and limitations

Four tests contain a producer with a stable signature differing from its preserved observation: native `dq_item_takes_atmos_heat`, `dq_pressure_pushes_unanchored_movable`, `dq_reactor_wakes_merge`; BYOND `dq_robot_brownout`. These changes are runtime counts with status0 and empty message, not stable pass/fail regressions. Complete signatures and all79 variable rows are retained in the accompanying JSON.

Coverage remains incomplete; equality is not claimed. Two of three BYOND observations terminate with access violation despite complete result markers, while native exits are0. Three observations are descriptive, not statistical equivalence or causal proof. Normalized numbers/references may hide distinct raw messages; structured versus raw reconciliation/ownership gaps remain explicit in the primary evidence.
