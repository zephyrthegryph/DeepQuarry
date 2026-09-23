// State schema tests (roadmap L1, doc/rewrite/state.md): round trips for every
// latent-safe type, codecs, canonical deltas, versioning, collapse blockers and
// the vore serializer migration.

/// Probe datum for codec and versioning tests.
/datum/dq_state_probe
	var/number = 1
	var/text = "a"
	var/list/values
	var/path_value
	var/datum/ref_value
	var/tmp/runtime_only = 0

/datum/dq_state_probe/state_codecs()
	return ..() + list("ref_value" = /datum/state_codec/owned)

/// Version 2 renamed old_number to number.
/datum/dq_state_probe/versioned
	state_version = 2

/datum/dq_state_probe/versioned/state_migrate(list/vars, from_version)
	..()
	if(from_version < 2 && ("old_number" in vars))
		vars["number"] = vars["old_number"]
		vars -= "old_number"

/// Holds an outside reference for the collapse test.
/datum/dq_state_holder
	var/atom/held

/datum/dq_state_holder/Destroy(force)
	held = null
	return ..()

/datum/dq_state_holder/proc/on_signal()
	SIGNAL_HANDLER
	return

/// Returns the canonical text of a full serialization, or null with the errors in `errors`.
/proc/dq_state_canonical_of(datum/D, list/errors)
	var/list/blob = state_serialize(D, STATE_FULL, errors)
	return blob ? state_canonical(blob) : null

/// Changes a few saved scalar vars so the round trip covers a non-default state.
/proc/dq_state_perturb(atom/movable/A)
	A.name = "[A.name] (sampled)"
	A.desc = "sampled state"
	var/count = 0
	for(var/name in state_saved_vars(A))
		if(count >= 3)
			break
		if(name in GLOB.state_builtin_vars)
			continue
		var/value = A.vars[name]
		if(isnum(value) && value != 0 && value == round(value))
			A.vars[name] = value + 1
			count++

/// Where two texts first differ, with some context.
/proc/dq_state_first_difference(expected, actual)
	var/limit = min(length(expected), length(actual))
	var/index = 1
	while(index <= limit && text2ascii(expected, index) == text2ascii(actual, index))
		index++
	var/start = max(1, index - 60)
	return "at [index]: before ...[copytext(expected, start, index + 80)]... after ...[copytext(actual, start, index + 80)]..."

/// Every latent-safe type (and subtype) survives serialize -> materialize, also through JSON.
/datum/unit_test/dq_state_latent_round_trip
	is_sweep_test = TRUE

/datum/unit_test/dq_state_latent_round_trip/Run()
	var/list/failures = list()
	var/tested = 0
	for(var/atom/movable/path as anything in sweep_types(subtypesof(/atom/movable)))
		if(!initial(path.latent_safe) || is_abstract(path))
			continue
		tested++
		var/atom/movable/original = new path(test_floor())
		dq_state_perturb(original)
		var/list/errors = list()
		var/list/blob = state_serialize(original, STATE_FULL, errors)
		if(!blob)
			failures += "[path]: did not serialize: [jointext(errors, "; ")]"
			qdel(original)
			continue
		var/expected = state_canonical(blob)
		for(var/pass in 1 to 2)
			var/list/source = pass == 1 ? blob : json_decode(json_encode(blob))
			errors = list()
			var/atom/movable/copy = state_materialize(source, test_floor(), STATE_FULL, errors)
			if(!copy)
				failures += "[path]: did not materialize[pass == 2 ? " from JSON" : ""]: [jointext(errors, "; ")]"
				continue
			var/actual = dq_state_canonical_of(copy, errors)
			if(actual != expected)
				failures += "[path]: round trip[pass == 2 ? " through JSON" : ""] changed the state: [dq_state_first_difference(expected, actual)]"
			qdel(copy)
		qdel(original)
	TEST_ASSERT(tested > 0, "no latent-safe types found")
	if(length(failures))
		TEST_FAIL("[length(failures)] of [tested] latent-safe types failed:\n[jointext(failures, "\n")]")

/// Deltas: identical items hash equal, a change shows up, key order does not matter.
/datum/unit_test/dq_state_canonical_delta

/datum/unit_test/dq_state_canonical_delta/Run()
	var/obj/item/paper/first = allocate(/obj/item/paper)
	var/obj/item/paper/second = allocate(/obj/item/paper)
	first.pixel_x = second.pixel_x
	first.pixel_y = second.pixel_y
	var/first_text = state_canonical(state_serialize(first))
	var/second_text = state_canonical(state_serialize(second))
	TEST_ASSERT_EQUAL(state_hash(state_serialize(first)), state_hash(state_serialize(second)), "two untouched papers should hash the same: [dq_state_first_difference(first_text, second_text)]")
	var/list/delta = state_delta(first)
	TEST_ASSERT(!("info" in delta), "an untouched var should not be in the delta")
	first.info = "written on"
	delta = state_delta(first)
	TEST_ASSERT_EQUAL(delta["info"], "written on", "a changed var should be in the delta")
	TEST_ASSERT(state_hash(state_serialize(first)) != state_hash(state_serialize(second)), "a changed paper should hash differently")
	var/unsorted = state_canonical(list("b" = 1, "a" = list("d" = 0.1000000001, "c" = 2)))
	var/sorted = state_canonical(list("a" = list("c" = 2, "d" = 0.1), "b" = 1))
	TEST_ASSERT_EQUAL(unsorted, sorted, "canonical text should sort keys and normalize numbers")
	TEST_ASSERT(!("runtime_only" in state_saved_vars(new /datum/dq_state_probe)), "tmp vars are not part of the schema")

/// Values the codecs must carry: paths, assoc lists with path and escaped keys,
/// registry singletons, owned datums, and children in the subtree.
/datum/unit_test/dq_state_codecs

/datum/unit_test/dq_state_codecs/Run()
	var/datum/dq_state_probe/probe = new
	var/datum/material/steel = GLOB.name_to_material[MAT_STEEL]
	var/datum/dq_state_probe/owned = new
	owned.text = "owned"
	probe.path_value = /obj/item/paper
	probe.values = list("plain", 3, /obj/item/pen, "#hash" = "escaped", "#path" = "not a wrapper")
	probe.ref_value = owned
	var/list/blob = state_serialize(probe)
	TEST_ASSERT_NOTNULL(blob, "the probe should serialize")
	var/datum/dq_state_probe/copy = state_materialize(json_decode(json_encode(blob)), null)
	TEST_ASSERT_NOTNULL(copy, "the probe should materialize from JSON")
	TEST_ASSERT_EQUAL(copy.path_value, /obj/item/paper, "a path should come back as a path")
	TEST_ASSERT_EQUAL(copy.values["#hash"], "escaped", "a key starting with # should come back unchanged")
	TEST_ASSERT_EQUAL(copy.values["#path"], "not a wrapper", "a key that looks like a wrapper should come back unchanged")
	TEST_ASSERT(/obj/item/pen in copy.values, "a path in a list should come back as a path")
	var/datum/dq_state_probe/copy_owned = copy.ref_value
	TEST_ASSERT(istype(copy_owned), "an owned datum should come back: [json_encode(blob)]")
	TEST_ASSERT(copy_owned != owned, "an owned datum should come back as a new copy")
	TEST_ASSERT_EQUAL(copy_owned.text, "owned", "an owned datum should keep its state: [json_encode(blob)]")

	var/list/pairs = list(/obj/item/paper = 2, /obj/item/pen = 1)
	probe.values = pairs
	copy = state_materialize(json_decode(json_encode(state_serialize(probe))), null)
	TEST_ASSERT_EQUAL(copy.values[/obj/item/pen], 1, "an assoc list keyed by paths should come back")

	probe.values = list(steel)
	copy = state_materialize(json_decode(json_encode(state_serialize(probe))), null)
	TEST_ASSERT_EQUAL(copy.values[1], steel, "a material should come back as the same registry singleton")

	// A reference to something outside the subtree is refused.
	var/datum/dq_state_probe/stranger = new
	probe.values = list(stranger)
	var/list/errors = list()
	TEST_ASSERT_NULL(state_serialize(probe, NONE, errors), "a reference without a codec should refuse serialization")
	TEST_ASSERT(length(errors), "a refusal should say why")

	// A reference to a child of the subtree is kept as a child ID.
	var/obj/item/ammo_casing/casing = allocate(/obj/item/ammo_casing/a380)
	TEST_ASSERT_NOTNULL(casing.BB, "the casing should hold its projectile")
	var/obj/item/ammo_casing/casing_copy = state_materialize(json_decode(json_encode(state_serialize(casing, STATE_FULL))), test_floor())
	TEST_ASSERT(casing_copy?.BB && casing_copy.BB.loc == casing_copy, "the projectile var should point at the materialized child")
	TEST_ASSERT_EQUAL(length(casing_copy.contents), length(casing.contents), "contents made by Initialize should be replaced, not added to")
	qdel(casing_copy)

	// Reagents go through their codec.
	var/obj/item/reagent_containers/pill/pill = allocate(/obj/item/reagent_containers/pill)
	pill.reagents.add_reagent(REAGENT_ID_WATER, 5)
	var/obj/item/reagent_containers/pill/pill_copy = state_materialize(json_decode(json_encode(state_serialize(pill, STATE_FULL))), test_floor())
	TEST_ASSERT_EQUAL(pill_copy.reagents.get_reagent_amount(REAGENT_ID_WATER), 5, "the pill's reagents should come back")
	qdel(pill_copy)

/// Schema versions and migrations: a renamed var, a legacy flat blob, a renamed type.
/datum/unit_test/dq_state_versioning

/datum/unit_test/dq_state_versioning/Run()
	var/list/old_blob = list(STATE_KEY_TYPE = "[/datum/dq_state_probe/versioned]", STATE_KEY_VERSION = 1, STATE_KEY_VARS = list("old_number" = 7))
	var/datum/dq_state_probe/versioned/migrated = state_materialize(old_blob, null)
	TEST_ASSERT_EQUAL(migrated?.number, 7, "state_migrate() should rename old_number to number")

	var/list/legacy = list("type" = "[/datum/dq_state_probe]", "number" = 5, "gone_var" = 1)
	var/datum/dq_state_probe/from_legacy = state_materialize(legacy, null)
	TEST_ASSERT_EQUAL(from_legacy?.number, 5, "a legacy flat blob should load, ignoring vars it no longer has")

	var/list/errors = list()
	var/list/unknown_var = list(STATE_KEY_TYPE = "[/datum/dq_state_probe]", STATE_KEY_VERSION = 1, STATE_KEY_VARS = list("gone_var" = 1))
	TEST_ASSERT_NULL(state_materialize(unknown_var, null, STATE_FULL, errors), "a current blob with an unknown var should fail without a migration")

	GLOB.state_type_migrations["/datum/dq_state_probe_old_name"] = /datum/dq_state_probe
	var/datum/dq_state_probe/renamed = state_materialize(list(STATE_KEY_TYPE = "/datum/dq_state_probe_old_name", STATE_KEY_VERSION = 1, STATE_KEY_VARS = list("number" = 3)), null)
	GLOB.state_type_migrations -= "/datum/dq_state_probe_old_name"
	TEST_ASSERT_EQUAL(renamed?.number, 3, "a type migration should load the blob as the new type")

/// Collapse blockers: a clean item has none; an outside reference, a timer and a
/// signal registration each block it.
/datum/unit_test/dq_state_collapse_blockers

/datum/unit_test/dq_state_collapse_blockers/Run()
	var/obj/item/paper/lone = new(test_floor())
	var/list/blockers = lone.state_collapse_blockers(1)
	TEST_ASSERT_EQUAL(length(blockers), 0, "a paper with no outside references should collapse: [jointext(blockers, "; ")]")
	qdel(lone)

	var/obj/item/storage/box/box = new(test_floor())
	blockers = box.state_collapse_blockers(1)
	TEST_ASSERT_EQUAL(length(blockers), 0, "an empty box with no outside references should collapse: [jointext(blockers, "; ")]")
	new /obj/item/paper(box)
	blockers = box.state_collapse_blockers(1)
	TEST_ASSERT_EQUAL(length(blockers), 0, "a box of paper with no outside references should collapse: [jointext(blockers, "; ")]")

	var/datum/dq_state_holder/holder = new
	holder.held = box
	blockers = box.state_collapse_blockers(1)
	TEST_ASSERT(length(blockers) == 1 && findtext(blockers[1], "outside"), "an outside var holding the box should block collapse: [jointext(blockers, "; ")]")
	qdel(holder)
	blockers = box.state_collapse_blockers(1)
	TEST_ASSERT_EQUAL(length(blockers), 0, "releasing the outside reference should unblock: [jointext(blockers, "; ")]")

	var/datum/dq_state_holder/listener = new
	listener.RegisterSignal(box, COMSIG_QDELETING, TYPE_PROC_REF(/datum/dq_state_holder, on_signal))
	blockers = box.state_collapse_blockers(1)
	var/found_signal = FALSE
	for(var/reason in blockers)
		if(findtext(reason, "listens"))
			found_signal = TRUE
	TEST_ASSERT(found_signal, "a signal registration from outside should block collapse: [jointext(blockers, "; ")]")
	listener.UnregisterSignal(box, COMSIG_QDELETING)
	qdel(listener)

	var/obj/item/paper/timed = new(test_floor())
	addtimer(CALLBACK(timed, TYPE_PROC_REF(/atom, update_icon)), 10 SECONDS)
	blockers = timed.state_collapse_blockers(1)
	var/found_timer = FALSE
	for(var/reason in blockers)
		if(findtext(reason, "timers"))
			found_timer = TRUE
	TEST_ASSERT(found_timer, "an active timer should block collapse: [jointext(blockers, "; ")]")
	qdel(timed)
	qdel(box)

/// The legacy belly save keys, from the removed /datum/belly_serializer schema:
/// the vore serializer migration must not save anything outside them.
/proc/dq_state_legacy_belly_keys()
	return list("name", "desc", "color", "dir", "icon", "icon_state", "pixel_x", "pixel_y", "digest_mode",
		"display_name", "absorbed_desc", "message_mode", "vore_sound", "vore_verb", "release_verb", "release_sound",
		"fancy_vore", "is_wet", "wet_loop", "vorefootsteps_sounds", "sound_volume", "noise_freq",
		"human_prey_swallow_time", "nonhuman_prey_swallow_time", "emote_time", "emote_active", "nutrition_percent",
		"digest_max", "digest_brute", "digest_burn", "digest_oxy", "digest_tox", "digest_clone", "bellytemperature",
		"temperature_damage", "slow_digestion", "slow_brutal", "speedy_mob_processing", "escapable", "escapetime",
		"escapechance", "escapechance_absorbed", "selectchance", "digestchance", "absorbchance", "escape_stun",
		"private_struggle", "belchchance", "transferchance", "transferchance_secondary", "transferlocation",
		"transferlocation_secondary", "transferlocation_absorb", "autotransferchance", "autotransferwait",
		"autotransferlocation", "autotransferextralocation", "autotransfer_enabled", "autotransfer_min_amount",
		"autotransfer_max_amount", "autotransferchance_secondary", "autotransferlocation_secondary",
		"autotransferextralocation_secondary", "autotransfer_whitelist", "autotransfer_blacklist",
		"autotransfer_whitelist_items", "autotransfer_blacklist_items", "autotransfer_secondary_whitelist",
		"autotransfer_secondary_blacklist", "autotransfer_secondary_whitelist_items",
		"autotransfer_secondary_blacklist_items", "vorespawn_blacklist", "vorespawn_whitelist", "vorespawn_absorbed",
		"immutable", "can_taste", "bulge_size", "display_absorbed_examine", "shrink_grow_size",
		"show_fullness_messages", "entrance_logs", "item_digest_logs", "is_feedable", "absorbedrename_enabled",
		"absorbedrename_name", "mode_flags", "item_digest_mode", "selective_preference", "drainmode",
		"save_digest_mode", "eating_privacy_local", "silicon_belly_overlay_preference", "belly_mob_mult",
		"belly_item_mult", "belly_overall_mult", "displayed_message_flags", "contaminates", "contamination_flavor",
		"contamination_color", "reagentbellymode", "reagent_gen_cost_limit", "reagent_mode_flags", "show_liquids",
		"liquid_overlay", "max_liquid_level", "reagent_touches", "mush_overlay", "mush_color", "mush_alpha",
		"max_mush", "min_mush", "item_mush_val", "custom_reagentcolor", "custom_reagentalpha", "metabolism_overlay",
		"metabolism_mush_ratio", "max_ingested", "custom_ingested_color", "custom_ingested_alpha",
		"nutri_reagent_gen", "is_beneficial", "gen_cost", "gen_amount", "gen_time", "gen_time_display",
		"reagent_transfer_verb", "custom_max_volume", "reagent_name", "reagentid", "reagentcolor",
		"generated_reagents", "liquid_fullness1_messages", "liquid_fullness2_messages", "liquid_fullness3_messages",
		"liquid_fullness4_messages", "liquid_fullness5_messages", "fullness1_messages", "fullness2_messages",
		"fullness3_messages", "fullness4_messages", "fullness5_messages", "belly_fullscreen", "disable_hud",
		"colorization_enabled", "belly_fullscreen_color", "belly_fullscreen_color2", "belly_fullscreen_color3",
		"belly_fullscreen_color4", "belly_fullscreen_alpha", "vore_sprite_flags", "affects_vore_sprites",
		"count_absorbed_prey_for_sprite", "absorbed_multiplier", "count_liquid_for_sprite", "liquid_multiplier",
		"count_items_for_sprite", "item_multiplier", "health_impacts_size", "resist_triggers_animation",
		"size_factor_for_sprite", "belly_sprite_to_affect", "undergarment_chosen", "undergarment_if_none",
		"undergarment_color", "egg_type", "egg_name", "egg_size", "recycling", "storing_nutrition", "prevent_saving",
		"struggle_messages_outside", "struggle_messages_inside", "absorbed_struggle_messages_outside",
		"absorbed_struggle_messages_inside", "escape_attempt_messages_owner", "escape_attempt_messages_prey",
		"escape_messages_owner", "escape_messages_prey", "escape_messages_outside", "escape_item_messages_owner",
		"escape_item_messages_prey", "escape_item_messages_outside", "escape_fail_messages_owner",
		"escape_fail_messages_prey", "escape_attempt_absorbed_messages_owner", "escape_attempt_absorbed_messages_prey",
		"escape_absorbed_messages_owner", "escape_absorbed_messages_prey", "escape_absorbed_messages_outside",
		"escape_fail_absorbed_messages_owner", "escape_fail_absorbed_messages_prey", "primary_transfer_messages_owner",
		"primary_transfer_messages_prey", "secondary_transfer_messages_owner", "secondary_transfer_messages_prey",
		"primary_autotransfer_messages_owner", "primary_autotransfer_messages_prey",
		"secondary_autotransfer_messages_owner", "secondary_autotransfer_messages_prey", "digest_chance_messages_owner",
		"digest_chance_messages_prey", "absorb_chance_messages_owner", "absorb_chance_messages_prey",
		"digest_messages_owner", "digest_messages_prey", "absorb_messages_owner", "absorb_messages_prey",
		"unabsorb_messages_owner", "unabsorb_messages_prey", "examine_messages", "examine_messages_absorbed",
		"emote_lists", "trash_eater_in", "trash_eater_out")

/// The vore serializer on the generic one: a belly's saved keys stay within the
/// legacy set, its state survives the prefs round trip, and a legacy flat blob loads.
/datum/unit_test/dq_state_vore_belly_round_trip

/datum/unit_test/dq_state_vore_belly_round_trip/Run()
	var/mob/living/simple_mob/animal/passive/mouse/pred = allocate(/mob/living/simple_mob/animal/passive/mouse)
	var/obj/belly/belly = new(pred)
	belly.name = "Tummy"
	belly.desc = "A test belly."
	belly.digest_mode = DM_DIGEST
	belly.escapechance = 42
	belly.struggle_messages_inside = list("one", "two")
	belly.emote_lists = list(DM_HOLD = list("held"), DM_DIGEST = list("digested"))
	belly.generated_reagents = list(REAGENT_ID_WATER = 1)
	belly.reagents.add_reagent(REAGENT_ID_WATER, 10)

	var/list/errors = list()
	var/list/blob = state_serialize(belly, NONE, errors)
	TEST_ASSERT_NOTNULL(blob, "a processing belly should still serialize for prefs: [jointext(errors, "; ")]")
	var/list/legacy_keys = dq_state_legacy_belly_keys()
	for(var/key in blob[STATE_KEY_VARS])
		TEST_ASSERT(key in legacy_keys, "belly saved [key], which the vore serializer never saved")
	TEST_ASSERT(!("reagents" in blob[STATE_KEY_VARS]), "the belly's liquid is not part of its prefs")

	var/obj/belly/copy = state_materialize(json_decode(json_encode(blob)), pred, NONE, errors)
	TEST_ASSERT_NOTNULL(copy, "the belly should load: [jointext(errors, "; ")]")
	TEST_ASSERT_EQUAL(copy.name, "Tummy", "name should round trip")
	TEST_ASSERT_EQUAL(copy.desc, "A test belly.", "desc should round trip")
	TEST_ASSERT_EQUAL(copy.digest_mode, DM_DIGEST, "digest mode should round trip while save_digest_mode is set")
	TEST_ASSERT_EQUAL(copy.escapechance, 42, "escapechance should round trip")
	TEST_ASSERT_EQUAL(jointext(copy.struggle_messages_inside, "|"), "one|two", "message lists should round trip")
	TEST_ASSERT_EQUAL(jointext(copy.emote_lists[DM_DIGEST], "|"), "digested", "emote lists should round trip")
	TEST_ASSERT_EQUAL(copy.owner, pred, "the loaded belly should belong to the mob it loaded into")
	TEST_ASSERT(copy in pred.vore_organs, "the loaded belly should be registered on its owner")

	belly.save_digest_mode = FALSE
	blob = state_serialize(belly)
	TEST_ASSERT(!("digest_mode" in blob[STATE_KEY_VARS]), "digest mode is not saved when save_digest_mode is off")

	// A belly saved by the pre-L1 serializer: flat keys next to "type".
	var/list/legacy = list("type" = "/obj/belly", "name" = "Old Gut", "escapechance" = 7, "reagent_chosen" = "Water",
		"struggle_messages_outside" = list("legacy"), "emote_lists" = list(DM_HOLD = list("old")))
	var/obj/belly/old = state_materialize(json_decode(json_encode(legacy)), pred, NONE, errors)
	TEST_ASSERT_NOTNULL(old, "a legacy belly blob should load: [jointext(errors, "; ")]")
	TEST_ASSERT_EQUAL(old.name, "Old Gut", "legacy name should load")
	TEST_ASSERT_EQUAL(old.escapechance, 7, "legacy escapechance should load")
	TEST_ASSERT_EQUAL(jointext(old.emote_lists[DM_HOLD], "|"), "old", "legacy emote lists should load")

	// The soulgem saves its linked belly by name and relinks it on load.
	var/obj/soulgem/gem = new(pred)
	gem.inside_flavor = "a test room"
	gem.linked_belly = copy
	var/list/gem_blob = state_serialize(gem, NONE, errors)
	TEST_ASSERT_NOTNULL(gem_blob, "the soulgem should serialize: [jointext(errors, "; ")]")
	var/list/gem_vars = gem_blob[STATE_KEY_VARS]
	TEST_ASSERT_EQUAL(gem_vars["linked_belly"], "Tummy", "the linked belly should be saved by name")
	gem.linked_belly = null
	var/obj/soulgem/gem_copy = state_materialize(json_decode(json_encode(gem_blob)), pred, NONE, errors)
	TEST_ASSERT_EQUAL(gem_copy?.inside_flavor, "a test room", "soulgem text should round trip")
	TEST_ASSERT(gem_copy?.linked_belly?.name == "Tummy", "the soulgem should relink the belly by name")
	qdel(gem_copy)
	qdel(gem)
