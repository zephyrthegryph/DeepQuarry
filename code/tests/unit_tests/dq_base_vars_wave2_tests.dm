// base_vars wave 2: item handling (the item_handling() trait) and the object, item, machine, atom, movable and mob scratch state that became
// sparse slots. Behaviour must be as it was: a slot reads as the default the var had, a write of null clears it back to that default, and the
// per-type numbers of an item are what the type declared.

#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

/// The per-type values of the item_handling() trait, the run-time copy of one instance, and the range the jitter roll reads.
/datum/unit_test/dq_item_handling_trait

/datum/unit_test/dq_item_handling_trait/Run()
	var/turf/T = dq_containment_floor()
	var/datum/type_trait/item_handling/base = handling_of_type(/obj/item)
	TEST_ASSERT_EQUAL(base.center_x, 16, "an item balances at 16, 16 unless its type says otherwise")
	TEST_ASSERT_EQUAL(base.center_y, 16, "on both axes")
	TEST_ASSERT_EQUAL(base.randpixel, 6, "and scatters over 6 pixels")
	TEST_ASSERT_EQUAL(base.preserve, 0, "it is not preserved in cryo")
	TEST_ASSERT_EQUAL(base.no_attack_log, 0, "it writes attack logs")
	TEST_ASSERT_EQUAL(base.no_random_knockdown, FALSE, "and may knock people down at random")

	var/datum/type_trait/item_handling/casing = handling_of_type(/obj/item/ammo_casing)
	TEST_ASSERT_EQUAL(casing.randpixel, 10, "a casing scatters over 10 pixels")
	TEST_ASSERT_EQUAL(casing.preserve, 1, "and is preserved in cryo")
	var/datum/type_trait/item_handling/stack = handling_of_type(/obj/item/stack)
	TEST_ASSERT_EQUAL(stack.randpixel, 7, "a stack scatters over 7 pixels")
	TEST_ASSERT_EQUAL(stack.center_x, 0, "and has no balance point")
	TEST_ASSERT_EQUAL(stack.center_y, 0, "on either axis")
	var/datum/type_trait/item_handling/fragment = handling_of_type(/obj/item/projectile/bullet/pellet/fragment)
	TEST_ASSERT_EQUAL(fragment.no_attack_log, 1, "a fragment writes no attack log")
	TEST_ASSERT_EQUAL(fragment.randpixel, 6, "and keeps every other value of its parent")

	var/obj/item/ammo_casing/shell = allocate(/obj/item/ammo_casing, T)
	TEST_ASSERT_EQUAL(handling_of(shell).preserve, 1, "an instance reads its type's value")
	TEST_ASSERT_EQUAL(shell.randpixel_range(), 10, "the range of its jitter is the trait's")
	var/obj/item/ammo_casing/other = allocate(/obj/item/ammo_casing, T)
	shell.set_randpixel(3)
	TEST_ASSERT_EQUAL(shell.randpixel_range(), 3, "a run-time write changes that instance")
	TEST_ASSERT_EQUAL(other.randpixel_range(), 10, "and no other")
	TEST_ASSERT_EQUAL(handling_of_type(/obj/item/ammo_casing).randpixel, 10, "nor the type's declaration")
	TEST_ASSERT_EQUAL(handling_of(shell).preserve, 1, "the copy keeps the values it did not change")

	shell.set_center_of_mass_x(5)
	shell.set_center_of_mass_y(7)
	TEST_ASSERT_EQUAL(handling_of(shell).center_x, 5, "the balance point is writable at run time")
	TEST_ASSERT_EQUAL(handling_of(shell).center_y, 7, "on both axes")

/// A jitter roll declared with PIXEL_JITTER(PROC_REF(randpixel_range)) scatters within the item's own range.
/datum/unit_test/dq_item_handling_jitter

/datum/unit_test/dq_item_handling_jitter/Run()
	var/turf/T = dq_containment_floor()
	var/obj/item/ammo_casing/shell = allocate(/obj/item/ammo_casing, T)
	TEST_ASSERT(abs(shell.pixel_x) <= 10 && abs(shell.pixel_y) <= 10, "a casing is scattered within its 10 pixels, got [shell.pixel_x], [shell.pixel_y]")
	var/obj/item/stack/material/steel/sheet = allocate(/obj/item/stack/material/steel, T)
	TEST_ASSERT(abs(sheet.pixel_x) <= 7 && abs(sheet.pixel_y) <= 7, "a stack is scattered within its 7 pixels, got [sheet.pixel_x], [sheet.pixel_y]")

/// A sparse slot reads as the default its var had, a value is kept, and a null write clears it back to the default.
/datum/unit_test/dq_base_vars_wave2_defaults

/datum/unit_test/dq_base_vars_wave2_defaults/Run()
	var/turf/T = dq_containment_floor()
	var/obj/item/pen/P = allocate(/obj/item/pen, T)
	TEST_ASSERT_EQUAL(sparse_get_or(P, trash_eatable, TRUE), TRUE, "an item can be eaten as trash until it is marked otherwise")
	sparse_set(P, trash_eatable, FALSE)
	TEST_ASSERT_EQUAL(sparse_get_or(P, trash_eatable, TRUE), FALSE, "a write of FALSE is kept")
	sparse_set(P, trash_eatable, null)
	TEST_ASSERT_EQUAL(sparse_get_or(P, trash_eatable, TRUE), TRUE, "a write of null reads back the default")
	TEST_ASSERT_EQUAL(sparse_get_or(P, d_mult_old, 1), 1, "the digest multiplier starts at 1")
	TEST_ASSERT_EQUAL(sparse_get_or(P, mat_toxicity, 0), 0, "a material emission starts at 0")
	TEST_ASSERT(isnull(sparse_get(P, cleanname)), "a clean name starts unset")
	sparse_set(P, cleanname, "pen")
	sparse_set(P, cleandesc, "a pen")
	TEST_ASSERT_EQUAL(sparse_get(P, cleanname), "pen", "and keeps what it is given")
	TEST_ASSERT_EQUAL(sparse_get(P, cleandesc), "a pen", "likewise the clean description")
	sparse_set(P, cleanname, null)
	sparse_set(P, cleandesc, null)
	TEST_ASSERT(isnull(P.sparse_slots), "and the slot list goes with the last slot")

	TEST_ASSERT_EQUAL(sparse_get_or(P, economic_export_value, 0), 0, "an object has no export value until one is set")
	TEST_ASSERT_EQUAL(sparse_get_or(P, economic_producer_account, 0), 0, "no producer account")
	TEST_ASSERT_EQUAL(sparse_get_or(P, economic_sale_invoice_id, 0), 0, "and no sale invoice")
	TEST_ASSERT(isnull(sparse_get(P, economic_department)), "and no department")
	sparse_set(P, economic_export_value, 12)
	TEST_ASSERT_EQUAL(sparse_get_or(P, economic_export_value, 0), 12, "an export value is kept")

	TEST_ASSERT_EQUAL(sparse_get_or(P, micro_accepted_scale, 0.5), 0.5, "a structure lets micros through at half size")
	TEST_ASSERT_EQUAL(sparse_get_or(P, debris_amount, 1), 1, "an object leaves one debris")
	TEST_ASSERT_EQUAL(sparse_get_or(P, being_shocked, FALSE), FALSE, "an object is not being shocked")

/// The atom transform keeps its parts in slots and applies them as before.
/datum/unit_test/dq_base_vars_wave2_transform

/datum/unit_test/dq_base_vars_wave2_transform/Run()
	var/turf/T = dq_containment_floor()
	var/obj/item/pen/P = allocate(/obj/item/pen, T)
	TEST_ASSERT(isnull(sparse_get(P, tf_scale_x)), "an atom starts without a base transform scale")
	P.SetTransform(scale = 2, rotation = 90)
	TEST_ASSERT_EQUAL(sparse_get(P, tf_scale_x), 2, "a scale sets the width")
	TEST_ASSERT_EQUAL(sparse_get(P, tf_scale_y), 2, "and the height")
	TEST_ASSERT_EQUAL(sparse_get(P, tf_rotation), 90, "and the rotation is kept")
	P.SetTransform(offset_x = 4)
	TEST_ASSERT_EQUAL(sparse_get(P, tf_scale_x), 2, "a later call keeps the scale it did not change")
	TEST_ASSERT_EQUAL(sparse_get(P, tf_offset_x), 4, "and takes the new offset")
	P.ClearTransform()
	TEST_ASSERT(isnull(sparse_get(P, tf_scale_x)) && isnull(sparse_get(P, tf_rotation)) && isnull(sparse_get(P, tf_offset_x)), "clearing resets every part")
	TEST_ASSERT(isnull(P.sparse_slots), "and leaves no slot behind")

/// Burning keeps its fuel and why it ended in slots, and the fire goes out when the fuel runs out.
/datum/unit_test/dq_base_vars_wave2_burning

/datum/unit_test/dq_base_vars_wave2_burning/Run()
	var/turf/T = dq_containment_floor()
	// The finder returns the first litter-free floor, which earlier tests move around the map (a nitrogen-only room or a vented floor is
	// one): a fire needs the oxygen of an ordinary room to end by running out of fuel. dq_containment_floor() snapshotted the air, so it
	// is put back after the test.
	dq_atmos_test_fill_standard_air(T)
	var/obj/item/paper/sheet = allocate(/obj/item/paper, T)
	TEST_ASSERT_EQUAL(sparse_get_or(sheet, burn_fuel, 0), 0, "an object holds no fuel before it burns")
	TEST_ASSERT(sheet.start_burning(), "paper catches fire")
	TEST_ASSERT(sparse_get_or(sheet, burn_fuel, 0) > 0, "and holds the fuel its integrity gives")
	TEST_ASSERT(!isnull(sparse_get(sheet, burn_overlay)), "and shows the fire overlay")
	sparse_set(sheet, burn_fuel, 1)
	sheet.burning_step(10)
	TEST_ASSERT(!sheet.is_burning(), "it goes out when the fuel runs out")
	TEST_ASSERT_EQUAL(sparse_get(sheet, burn_ended_by), BURN_ENDED_FUEL, "and says why")
	TEST_ASSERT(isnull(sparse_get(sheet, burn_overlay)), "and the overlay goes with it")

/// Mob scratch state: defaults, the AFK pair, the touch reaction bit flags and the suicide counter.
/datum/unit_test/dq_base_vars_wave2_mob

/datum/unit_test/dq_base_vars_wave2_mob/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, dq_containment_floor())
	TEST_ASSERT_EQUAL(sparse_get_or(H, omen_luck, 1), 1, "an unlucky soul starts at one luck")
	TEST_ASSERT_EQUAL(sparse_get_or(H, omen_vorish, TRUE), TRUE, "and vore omens")
	TEST_ASSERT_EQUAL(sparse_get_or(H, pickup_active, TRUE), TRUE, "a mob picks up micros by default")
	TEST_ASSERT_EQUAL(sparse_get_or(H, liquidbelly_visuals, TRUE), TRUE, "and shows liquidbelly overlays")
	TEST_ASSERT_EQUAL(sparse_get_or(H, trait_injection_amount, 5), 5, "a trait injection is 5 units")
	TEST_ASSERT_EQUAL(sparse_get_or(H, active_regen_delay, 300), 300, "and regeneration waits 300")
	TEST_ASSERT_EQUAL(sparse_get_or(H, omen_incidents, INFINITY), INFINITY, "an omen has no incident limit")
	sparse_set(H, pickup_active, FALSE)
	TEST_ASSERT_EQUAL(sparse_get_or(H, pickup_active, TRUE), FALSE, "turning pickup off is kept")
	sparse_set(H, pickup_active, null)
	TEST_ASSERT_EQUAL(sparse_get_or(H, pickup_active, TRUE), TRUE, "and clearing it restores the default")

	TEST_ASSERT(isnull(sparse_get(H, touch_reaction_flags)), "no touch reaction flags are set")
	sparse_set(H, touch_reaction_flags, sparse_get(H, touch_reaction_flags) | SPECIES_TRAIT_THORNS)
	TEST_ASSERT(sparse_get(H, touch_reaction_flags) & SPECIES_TRAIT_THORNS, "a flag is set")
	sparse_set(H, touch_reaction_flags, sparse_get(H, touch_reaction_flags) & (~SPECIES_TRAIT_THORNS))
	TEST_ASSERT(!(sparse_get(H, touch_reaction_flags) & SPECIES_TRAIT_THORNS), "and cleared")

	TEST_ASSERT_EQUAL(sparse_get_or(H, away_from_keyboard, FALSE), FALSE, "a mob is at its keyboard")
	H.toggle_afk()
	TEST_ASSERT_EQUAL(sparse_get_or(H, away_from_keyboard, FALSE), TRUE, "the AFK verb marks it away")
	TEST_ASSERT_EQUAL(sparse_get_or(H, manual_afk, FALSE), TRUE, "by hand")
	H.toggle_afk()
	TEST_ASSERT_EQUAL(sparse_get_or(H, away_from_keyboard, FALSE), FALSE, "and brings it back")
	TEST_ASSERT_EQUAL(sparse_get_or(H, manual_afk, FALSE), FALSE, "clearing both")

	TEST_ASSERT_EQUAL(sparse_get_or(H, suiciding, 0), 0, "a mob is not suiciding")
	sparse_set(H, suiciding, 1)
	TEST_ASSERT(sparse_get_or(H, suiciding, 0), "until it does")

/// A machine keeps its power setup flag and its diagnostic wake counter in slots.
/datum/unit_test/dq_base_vars_wave2_machine

/datum/unit_test/dq_base_vars_wave2_machine/Run()
	var/turf/T = dq_containment_floor()
	var/obj/machinery/light_switch/M = allocate(/obj/machinery/light_switch, T)
	TEST_ASSERT(sparse_get_or(M, power_init_complete, FALSE), "a machine has its power setup done after init")
	TEST_ASSERT_EQUAL(sparse_get_or(M, gas_dependency_wake_count, 0), 0, "and has woken for no gas change")

/// The object, machine, mob and atom traits (obj_rules, machine_usage, mob_nature, atom_shielding) hold what their vars held.
/datum/unit_test/dq_base_vars_wave2_type_traits

/datum/unit_test/dq_base_vars_wave2_type_traits/Run()
	var/datum/type_trait/obj_rules/rules = rules_of_type(/obj)
	TEST_ASSERT_EQUAL(rules.tk_reach, TRUE, "telekinesis reaches an object by default")
	TEST_ASSERT_EQUAL(rules.redgate_allowed, TRUE, "an object may go through the redgate")
	TEST_ASSERT_EQUAL(rules.micro_target, FALSE, "and is not a micro target")
	TEST_ASSERT_EQUAL(rules.surgery_cleanliness, 0, "no surgery surface is clean")
	TEST_ASSERT(isnull(rules.sellable_type), "and nothing is sellable")

	var/datum/type_trait/machine_usage/usage = usage_of_type(/obj/machinery)
	TEST_ASSERT_EQUAL(usage.click_volume, 40, "a machine clicks at 40")
	TEST_ASSERT_EQUAL(usage.interact_offline, 0, "it needs power to be used")
	TEST_ASSERT_EQUAL(usage.wrench_time, 0, "wrenching it is immediate")
	TEST_ASSERT_EQUAL(usage.weld_time, 2 SECONDS, "and welding takes two seconds")
	var/turf/T = dq_containment_floor()
	var/obj/machinery/light_switch/M = allocate(/obj/machinery/light_switch, T)
	TEST_ASSERT_EQUAL(usage_of(M).click_volume, 40, "an instance reads its type's value")
	M.set_clickvol(10)
	TEST_ASSERT_EQUAL(usage_of(M).click_volume, 10, "and its own once written")
	TEST_ASSERT_EQUAL(usage_of_type(/obj/machinery).click_volume, 40, "without touching the type")

	var/datum/type_trait/mob_nature/mob_default = nature_of_type(/mob/living)
	TEST_ASSERT_EQUAL(mob_default.can_pain_emote, TRUE, "a mob cries out in pain")
	TEST_ASSERT_EQUAL(mob_default.name_the_meat, TRUE, "names its meat")
	TEST_ASSERT_EQUAL(mob_default.drops_organs, TRUE, "drops organs when butchered")
	TEST_ASSERT_EQUAL(mob_default.gib_on_butchery, FALSE, "and is not gibbed by it")
	TEST_ASSERT_EQUAL(mob_default.no_vore, FALSE, "it can vore")
	TEST_ASSERT_EQUAL(mob_default.belly_size, 1, "with a full size belly")
	var/datum/type_trait/mob_nature/bot = nature_of_type(/mob/living/bot)
	TEST_ASSERT_EQUAL(bot.can_pain_emote, FALSE, "a bot does not cry out")
	TEST_ASSERT_EQUAL(bot.no_vore, TRUE, "and cannot vore")
	TEST_ASSERT_EQUAL(bot.belly_size, 1, "but keeps every other value")
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	H.set_no_vore(TRUE)
	TEST_ASSERT_EQUAL(nature_of(H).no_vore, TRUE, "a mob's own write is read back")
	TEST_ASSERT_EQUAL(nature_of_type(/mob/living/carbon/human).no_vore, FALSE, "and is not the type's")

	var/datum/type_trait/atom_shielding/atom_default = shielding_of_type(/atom)
	TEST_ASSERT_EQUAL(atom_default.deflection, 0, "no atom ignores damage")
	TEST_ASSERT_EQUAL(atom_default.damage_wear, "scrapes and dents", "damage wears it into scrapes and dents")
	TEST_ASSERT_EQUAL(atom_default.announce_bands, FALSE, "it does not announce damage bands")
	TEST_ASSERT(isnull(atom_default.rad_material), "and shields no radiation")

	TEST_ASSERT_EQUAL(handling_of_type(/obj/item).cavity_implantable, TRUE, "an item can be implanted in a cavity")
	TEST_ASSERT_EQUAL(handling_of_type(/obj/item/tool).cavity_implantable, FALSE, "a tool cannot")
	TEST_ASSERT_EQUAL(handling_of_type(/obj/item/gun).zoom_name, "scope", "a gun zooms as a scope")

/// A slot that used to be a saved var rides beside the delta, so a serialized and materialized item keeps it, and an untouched item adds nothing.
/datum/unit_test/dq_base_vars_wave2_state

/datum/unit_test/dq_base_vars_wave2_state/Run()
	var/turf/T = dq_containment_floor()
	var/list/errors = list()
	var/obj/item/pen/plain = allocate(/obj/item/pen, T)
	var/list/plain_blob = state_serialize(plain, STATE_FULL, errors)
	TEST_ASSERT_NOTNULL(plain_blob, "an untouched pen serializes: [jointext(errors, "; ")]")
	TEST_ASSERT_NULL(plain_blob[STATE_KEY_EXTRA], "and adds no extra state")

	var/obj/item/pen/marked = allocate(/obj/item/pen, T)
	sparse_set(marked, cleanname, "pen")
	sparse_set(marked, cleandesc, "a pen")
	sparse_set(marked, economic_export_value, 12)
	sparse_set(marked, digest_stage, 2)
	sparse_set(marked, trash_eatable, FALSE)
	sparse_set(marked, tf_scale_x, 2)
	sparse_set(marked, d_mult_old, 1) // the default: not state
	sparse_set(marked, burn_fuel, 0) // likewise
	errors = list()
	var/list/blob = state_serialize(marked, STATE_FULL, errors)
	TEST_ASSERT_NOTNULL(blob, "a pen with slots set serializes: [jointext(errors, "; ")]")
	var/list/extra = blob[STATE_KEY_EXTRA]
	TEST_ASSERT_NOTNULL(extra, "its slots ride beside the delta")
	TEST_ASSERT_EQUAL(length(extra), 6, "one entry for each slot off its default, got [length(extra)]")
	for(var/pass in 1 to 2)
		var/list/source = pass == 1 ? blob : json_decode(json_encode(blob))
		errors = list()
		var/obj/item/pen/copy = state_materialize(source, T, STATE_FULL, errors)
		TEST_ASSERT_NOTNULL(copy, "[pass == 2 ? "through JSON: " : ""]it materializes: [jointext(errors, "; ")]")
		TEST_ASSERT_EQUAL(sparse_get(copy, cleanname), "pen", "the clean name comes back")
		TEST_ASSERT_EQUAL(sparse_get(copy, cleandesc), "a pen", "and the clean description")
		TEST_ASSERT_EQUAL(sparse_get_or(copy, economic_export_value, 0), 12, "and the export value")
		TEST_ASSERT_EQUAL(sparse_get(copy, digest_stage), 2, "and the digest stage")
		TEST_ASSERT_EQUAL(sparse_get_or(copy, trash_eatable, TRUE), FALSE, "and the trash flag")
		TEST_ASSERT_EQUAL(sparse_get(copy, tf_scale_x), 2, "and the transform scale")
		TEST_ASSERT(!sparse_has(copy, d_mult_old), "a slot at its default is not carried")
		qdel(copy)

	// Applying a blob to an object that has other slots clears them, as applying a delta resets the vars.
	var/obj/item/pen/target = allocate(/obj/item/pen, T)
	sparse_set(target, oldname, "old")
	TEST_ASSERT(state_apply(target, blob, STATE_FULL, errors), "the blob applies to a pen that has a slot of its own: [jointext(errors, "; ")]")
	TEST_ASSERT(isnull(sparse_get(target, oldname)), "and its own slot is gone")
	TEST_ASSERT_EQUAL(sparse_get(target, cleanname), "pen", "while the blob's are set")

#endif
