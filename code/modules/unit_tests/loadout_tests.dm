/// converted unit test, maybe should be fully refactored

/datum/unit_test/loadout_tests/Run()
	for(var/datum/gear/G as anything in subtypesof(/datum/gear))
		TEST_ASSERT(initial(G.display_name), "[G]: Loadout - Missing display name.")
		TEST_ASSERT_NOTNULL(initial(G.cost), "[G]: Loadout - Missing cost.")
		TEST_ASSERT(initial(G.path), "[G]: Loadout - Missing path definition.")


// ---------------------------------------------------------------------------
//   Loadout editor persistence
//
//   Reproduces the "added item doesn't stick" report against the real editor
//   action handlers + preference cache, with the client-dependent preview
//   renderer stubbed out so we exercise pure persistence/read-back.
// ---------------------------------------------------------------------------

/// Clientless prefs stub for the loadout editor: skips the real New() chain (which needs
/// a client + savefile) and no-ops the preview renderer (which needs a mannequin/client).
/datum/preferences/dq_loadout_test_stub

/datum/preferences/dq_loadout_test_stub/New()
	return

/datum/preferences/dq_loadout_test_stub/Destroy()
	value_cache = null
	return ..()

/datum/preferences/dq_loadout_test_stub/update_preview_icon(south_only = FALSE)
	return

/datum/preferences/dq_loadout_test_stub/update_preview_icon_lazy()
	return

// No savefile in the stub — the auto-save flush at end_update_batch would CRASH. The
// in-memory value_cache is what these tests verify; the disk write is out of scope.
/datum/preferences/dq_loadout_test_stub/save_preferences()
	return FALSE

/datum/preferences/dq_loadout_test_stub/save_character(override)
	return FALSE

/// Find a real gear datum that the given prefs are allowed to pick, occupies a single
/// body slot (not the multi-allowed tie slot), so set_body_slot is the exercised path.
/proc/dq_test_pick_slotted_gear(datum/preferences/prefs)
	for(var/name in GLOB.gear_datums)
		var/datum/gear/G = GLOB.gear_datums[name]
		if(!G.slot || G.slot == slot_tie)
			continue
		if(!G.is_pickable_by(prefs))
			continue
		return G
	return null


/datum/unit_test/dq_loadout_persists_add

/datum/unit_test/dq_loadout_persists_add/Run()
	var/datum/preference_editor/loadout/editor = GLOB.preference_editors_by_key["loadout"]
	TEST_ASSERT_NOTNULL(editor, "loadout editor not registered")

	var/datum/preferences/dq_loadout_test_stub/p = new()
	TEST_ASSERT_NOTNULL(p, "couldn't allocate loadout test stub")

	var/datum/gear/chosen = dq_test_pick_slotted_gear(p)
	TEST_ASSERT_NOTNULL(chosen, "no pickable single-slot gear datum found")

	// Emulate the panel's mount effect: editing target = the default loadout.
	var/r0 = editor.handle_action(p, "set_loadout_key", list("key" = "_default"), null)
	TEST_ASSERT_EQUAL(r0, PREF_UPDATE_ACCEPTED, "set_loadout_key _default was not accepted (got [r0])")

	// The add the user performs by clicking a slot then an item.
	var/result = editor.handle_action(p, "set_body_slot", list("body_slot" = chosen.slot, "gear" = chosen.display_name), null)
	TEST_ASSERT_EQUAL(result, PREF_UPDATE_ACCEPTED, "set_body_slot did not ACCEPT (got [result]) for '[chosen.display_name]' slot=[chosen.slot]")

	// Persistence: the cache must hold the item under the _default loadout key.
	var/list/gear_list = p.read_preference(/datum/preference/gear_list)
	TEST_ASSERT_NOTNULL(gear_list, "gear_list is null after add")
	var/list/active = gear_list["_default"]
	TEST_ASSERT(islist(active) && (chosen.display_name in active), "added gear not persisted under the _default loadout: [json_encode(gear_list)]")

	qdel(p)


/datum/unit_test/dq_loadout_build_ui_reflects_add

/datum/unit_test/dq_loadout_build_ui_reflects_add/Run()
	var/datum/preference_editor/loadout/editor = GLOB.preference_editors_by_key["loadout"]
	TEST_ASSERT_NOTNULL(editor, "loadout editor not registered")

	var/datum/preferences/dq_loadout_test_stub/p = new()
	var/datum/gear/chosen = dq_test_pick_slotted_gear(p)
	TEST_ASSERT_NOTNULL(chosen, "no pickable single-slot gear datum found")

	editor.handle_action(p, "set_loadout_key", list("key" = "_default"), null)
	var/result = editor.handle_action(p, "set_body_slot", list("body_slot" = chosen.slot, "gear" = chosen.display_name), null)
	TEST_ASSERT_EQUAL(result, PREF_UPDATE_ACCEPTED, "set_body_slot did not ACCEPT (got [result])")

	// The read path the slot cell + catalog checkmark consume must reflect the add.
	var/list/ui = editor.build_ui_data(p)
	TEST_ASSERT_NOTNULL(ui, "build_ui_data returned null")
	var/list/by_body_slot = ui["by_body_slot"]
	var/slot_key = "[chosen.slot]"
	var/list/slot_items = islist(by_body_slot) ? by_body_slot[slot_key] : null
	TEST_ASSERT(islist(slot_items) && (chosen.display_name in slot_items), "build_ui_data by_body_slot for slot [slot_key] missing the added gear: [json_encode(by_body_slot)]")

	qdel(p)


// Every instantiated gear datum must have a UNIQUE display_name. GLOB.gear_datums is keyed
// by display_name, so any collision silently drops one datum and makes the catalog entry and
// the write-path datum potentially disagree (the "blue blazer doesn't save" report: the base
// /datum/gear/uniform and its implicit intermediate subtypes — /uniform/suit, /tropical_outfit,
// /solgov — all inherit display_name "blazer, blue").
/datum/unit_test/dq_gear_unique_display_names

/datum/unit_test/dq_gear_unique_display_names/Run()
	var/list/seen = list()
	var/list/collisions = list()
	for(var/datum/gear/G as anything in subtypesof(/datum/gear))
		// mirror populate_gear_list's skip rules: abstract category parents, missing names,
		// and subtypes that inherit (rather than declare) their parent's display_name.
		if(initial(G.type_category) == G)
			continue
		var/nm = initial(G.display_name)
		if(!nm)
			continue
		var/datum/gear/parent_gear = G.parent_type
		if(parent_gear && initial(parent_gear.display_name) == nm)
			continue
		if(seen[nm])
			collisions += "'[nm]' : [G] collides with [seen[nm]]"
		else
			seen[nm] = G
	if(length(collisions))
		TEST_FAIL("[length(collisions)] gear display_name collision(s): [collisions.Join(" | ")]")


// A variant-selector gear (one carrying a /datum/gear_tweak/variant) renders its catalog /
// slot sprite from initial(G.path). When the variant offers concrete item paths, G.path must
// be one of them — otherwise the gear inherited an unrelated base item's path and shows the
// wrong sprite (the "croptop selection shows the blue blazer" report: croptop/cheongsam/the
// altevian selectors set a name + variant tweak but no path, so they inherited the blazer/
// apron/base-accessory path). String-keyed variants (recolors/restyles of G.path itself) carry
// no path options and are left alone, as are non-variant gears that legitimately reuse a
// parent's item (e.g. generic implant secondary/tertiary, colorable latex gloves).
/datum/unit_test/dq_gear_variant_sprite

/datum/unit_test/dq_gear_variant_sprite/Run()
	var/list/offenders = list()
	for(var/name in GLOB.gear_datums)
		var/datum/gear/G = GLOB.gear_datums[name]
		var/datum/gear_tweak/variant/vt
		for(var/datum/gear_tweak/gt as anything in G.gear_tweaks)
			if(istype(gt, /datum/gear_tweak/variant))
				vt = gt
				break
		if(!vt || !islist(vt.valid_variants))
			continue
		var/list/option_paths = list()
		for(var/disp in vt.valid_variants)
			var/val = vt.valid_variants[disp]
			if(ispath(val))
				option_paths += val
		if(length(option_paths) && !(G.path in option_paths))
			offenders += "'[name]' ([G.type]) sprite path [G.path] is not among its variant options"
	if(length(offenders))
		TEST_FAIL("[length(offenders)] variant-selector gear show a sprite outside their own options: [offenders.Join(" | ")]")


// Direct repro of the user's report: add "blazer, blue" and confirm it persists.
/datum/unit_test/dq_loadout_blazer_persists

/datum/unit_test/dq_loadout_blazer_persists/Run()
	var/datum/preference_editor/loadout/editor = GLOB.preference_editors_by_key["loadout"]
	TEST_ASSERT_NOTNULL(editor, "loadout editor not registered")
	var/datum/gear/G = GLOB.gear_datums["blazer, blue"]
	TEST_ASSERT_NOTNULL(G, "'blazer, blue' not in GLOB.gear_datums")

	var/datum/preferences/dq_loadout_test_stub/p = new()
	editor.handle_action(p, "set_loadout_key", list("key" = "_default"), null)
	var/result = editor.handle_action(p, "set_body_slot", list("body_slot" = G.slot, "gear" = "blazer, blue"), null)
	TEST_ASSERT_EQUAL(result, PREF_UPDATE_ACCEPTED, "blazer set_body_slot not accepted (got [result]); resolved type=[G.type] slot=[G.slot]")

	var/list/gl = p.read_preference(/datum/preference/gear_list)
	var/list/active = gl["_default"]
	TEST_ASSERT(islist(active) && ("blazer, blue" in active), "'blazer, blue' not persisted: [json_encode(gl)]")
	qdel(p)


// Swapping items in a single-occupancy slot must EVICT the previous item (no stacking) and
// keep total_cost equal to just the new item — the "points keep increasing / items stack"
// report.
/datum/unit_test/dq_loadout_swap_evicts

/datum/unit_test/dq_loadout_swap_evicts/Run()
	var/datum/preference_editor/loadout/editor = GLOB.preference_editors_by_key["loadout"]
	var/datum/preferences/dq_loadout_test_stub/p = new()

	// Find two distinct pickable gears that share a single (non-tie) body slot.
	var/datum/gear/a
	var/datum/gear/b
	for(var/name in GLOB.gear_datums)
		var/datum/gear/G = GLOB.gear_datums[name]
		if(!G.slot || G.slot == slot_tie || !G.is_pickable_by(p))
			continue
		if(!a)
			a = G
			continue
		if(G.slot == a.slot && G.display_name != a.display_name)
			b = G
			break
	TEST_ASSERT_NOTNULL(a, "no first slotted gear")
	TEST_ASSERT_NOTNULL(b, "no second gear sharing a's slot")

	editor.handle_action(p, "set_loadout_key", list("key" = "_default"), null)
	editor.handle_action(p, "set_body_slot", list("body_slot" = a.slot, "gear" = a.display_name), null)
	editor.handle_action(p, "set_body_slot", list("body_slot" = b.slot, "gear" = b.display_name), null)

	var/list/gl = p.read_preference(/datum/preference/gear_list)
	var/list/active = gl["_default"]
	TEST_ASSERT(!(a.display_name in active), "first item '[a.display_name]' was not evicted when '[b.display_name]' replaced it: [json_encode(active)]")
	TEST_ASSERT((b.display_name in active), "replacement item '[b.display_name]' missing after swap: [json_encode(active)]")

	var/list/ui = editor.build_ui_data(p)
	TEST_ASSERT_EQUAL(ui["total_cost"], b.cost, "total_cost should equal only the replacement's cost after a swap")
	qdel(p)
