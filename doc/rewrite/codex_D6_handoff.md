# D6 actor forwarding handoff

WT E:/projects/dq-wt/codex-D6, branch codex/D6. Root edits preserved. Offline 130 -> 85; remaining identities and reasons in retained-sites.md and remaining-usr-content.offline.json. Six dead commented xenochimera lines were never reactivated.

Converted native HUD clicks, eight drag routes, item/mob/sector/zone hover exits/entries, protean power/stat-panel clicks; public ore removal and smokable lighting actor arguments; all description-panel image and VV image viewer propagation; debug helper actor arguments; existing PushUsr and prompt reruns use with_actor. Authorization routines unchanged. Native storage/clothing override callback chains preserve parent ordering instead of independent fallthrough entries.

Nine focused dq_d6_actor_inputs children: ore_drop, storage_close, secure_drag, ammo_click, palette_gate, zone_hover, scoped_callback, radial_close, item_hover_timer. Existing root include is present. Real object routes and distinct ambient actor assertions; radial closure uses null-client context and cannot exercise distinct real clients. New warms dview/status caches and scopes coalesce_runs. No verification run by subagent.

Important unresolved global duplicate: anomaly_container.dm declares /atom/MouseDrop later than router.dm. Do not migrate both into active independent drag entries without proving old behavior. Parent-first medical stand/wheelchair drag cannot use ordinary native fallback without reordering. Unsupported MouseDown/MouseMove remain. Other residuals preserve native authorization, callback inheritance and diagnostics until explicit actor entry/consumer protocols exist.

Changed helper callers audited tree-wide: 19 description overrides, all 33 panel-image calls, recursive VV formatters and each vv_get_var override/caller; all 14 smokable light calls use existing actor. Other light APIs unchanged. Debug helpers have no static production callers; dynamic CallProc/VV must supply the explicit new actor argument. No setter/declaration edits, no logging removed, no builds/gen/tests/baseline/manifest/commit/push by subagent.

Root analyzer preflight: usr_content ceiling130 ->85, with generated trackedcheck clean. Existing callback compatibility now uses the real engine with_actor scoped invocation (restores outeractor), not a renamed helper. Native securityshims and unsupportedentry cases remain explicitlylisted. Runtime verification pending.


Source-only fixture repair (2026-10-15): scoped_callback inherits current_actor_for_test and push_then_read from /datum/unit_test/dq_d6_actor_inputs. Its two new callback references now use TYPE_PROC_REF at that defining ancestor; production actor bindings and fixture behavior are unchanged. No generation, analyzer, build or test was run; the A coordinator retains exclusive verification.

Fresh verification repaired four inherited mousedrop declarations to overrides and removed a fixture override of final add_fingerprint(). Locked headless behavior and real unlocked storage selection remain checked; real-client fingerprint evidence is explicitly untested here. First gate compiled no test world; original focused list remains pending.
