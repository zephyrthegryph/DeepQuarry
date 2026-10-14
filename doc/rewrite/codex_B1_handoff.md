# B1 asset-system boundary

Branch `codex/B1`, based on master `274d176a88`.

The asset system owns its cache and active transport. Its `code/controllers/subsystems/assets_api.dm` now exposes registration, unregistration, URL generation, sending, backend type, cached-item lookup, detached name snapshots and cache mutation. External callers in asset generation, icon rendering, tgui, belly overlays and client login use that API.

The owner shares `controllers/subsystems` with unrelated systems. A generic `api.dm` there falsely made the boundary checker require external API callers for atoms and behaviours, so this uses the existing owner-specific `*_api.dm` convention (as emergency shuttles and other systems do). No API function, lint, exemption or ceiling was renamed or relaxed.

Login preloading captures the original transport and preload list when queued, preserving behavior across a later configuration switch. Cache lookups preserve item identity; asset sends preserve the original associative list and transport return value. Existing tracing remains.

The eight SSassets baseline entries represented 57 accesses. They are now zero; the overall `system_boundary` baseline shrank from 146 to 138 entries using the analyzer. No SSassets B3 proc-definition rows or residual private-state accesses remain. Generated accessor declarations and all tracked/ownership declarations were left unchanged.

Focused tests: `dq_assets_boundary`, `dq_assets_preload_capture`, `test_asset_smart_cache`. The new tests cover real registered assets, API dispatch, detached cache-name snapshots, unregistration and a queued preload surviving a backend switch. Lane-ready verification is pending. No merge or push.
