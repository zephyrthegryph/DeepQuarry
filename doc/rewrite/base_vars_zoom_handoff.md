# Optical configuration and active-view proposal

Two base vars retire. Source-only ignored proposal; no generation/build/tests. Wire code/__defines/optics.dm near defines, code/game/objects/items/optical_view.dm before consumers, and dq_base_vars_zoom_tests.dm under UNIT_TESTS. Run dq_base_vars_zoom, its replacement_and_host_death and config_and_public_refusal leaves, plus existing interim_scope_actor_refusal/interim_binocular_actor_refusal.

Optical device_name is a real type trait: null default, inherited gun scope, var_names map/admin compatibility and runtime set_trait copy-on-write including null clears. Zoom-active is actual reciprocal sparse item/view membership. The mob remains sole owner of the view; both pair endpoints are borrowed CLEAR/REPLACE. All production bool reads and both writes retire; actual zoom() methods remain methods.

Old item_zoom unbind cleared item.zoom only with BOTH host_mob and host_item present. Unconditional endpoint cleanup now clears after forget_host; old same-device view cleanup also cannot erase a replacement's endpoint. These are deliberate stale-state fixes. Existing pixel offsets, subscriptions, messages and public no-client refusal are unchanged.

Tests construct actual item_zoom objects through real New, establish real mob ownership and native borrowed endpoints, and exercise qdel, replacement, actual generic begin_remote_view replacement, forget_host and viewer death. No override of start or fake client is used. Full live-client offset/rendering/drop-observer integration remains untested because no controlled connected-client fixture exists here. Production item_zoom.start still needs a connection for pixel assignments; that code is untouched. Lifecycle coverage is not represented as a graphical client session.
