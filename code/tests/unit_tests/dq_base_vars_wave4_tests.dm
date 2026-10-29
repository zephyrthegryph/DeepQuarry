// base_vars wave 4: stamps, small lists and flags that left /mob, /mob/living, /human and /obj/item for sparse slots (and one cooldown name).
// Each is gone as a var, reads as the default the var had, and is reached by View Variables by its slot label.

#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

/// Every slot of this wave: list(owner type, slot name, a value to set, the default it reads as).
/proc/dq_wave4_slot_rows()
	var/static/list/rows = list(
		list(/mob, "lastareachange", 50, 0),
		list(/mob, "global_hud_claims", list("a" = TRUE), null),
		list(/mob/living, "last_instability_event", 50, 0),
		list(/mob/living, "rad_countdown_started", 50, 0),
		list(/mob/living, "pipes_shown", list(), null),
		list(/mob/living/carbon/human, "disability_motor_tics", list("nya"), null),
		list(/mob/living/carbon/human, "speech_sound_enabled", FALSE, TRUE),
		list(/obj/item/pen, "warned_of_possession", list(), null),
	)
	return rows

/datum/unit_test/dq_base_vars_wave4_slots

/datum/unit_test/dq_base_vars_wave4_slots/Run()
	var/turf/T = dq_containment_floor()
	for(var/list/row as anything in dq_wave4_slot_rows())
		var/datum/holder = allocate(row[1] == /mob ? /mob/living/carbon/human : row[1], T)
		var/name = row[2]
		var/label = sparse_slot_label(name)
		TEST_ASSERT(!(name in holder.vars), "[name] is no longer a var of [holder.type]")
		TEST_ASSERT((label in sparse_slots_of(holder)), "[name] is listed as a slot of [holder.type]")
		TEST_ASSERT_EQUAL(_sparse_get(holder, name, row[4]), row[4], "[name] reads as the default its var had")
		TEST_ASSERT(holder.vv_edit_var(label, row[3]), "the VV edit of [name] is accepted")
		TEST_ASSERT_EQUAL(vv_var_value(holder, label), row[3], "[name] reads back what View Variables wrote")

/// The helpers that carried the vars: possession warnings fire once per ckey, a cooldown name replaces the pred's prey-loop timer.
/datum/unit_test/dq_base_vars_wave4_behaviour

/datum/unit_test/dq_base_vars_wave4_behaviour/Run()
	var/turf/T = dq_containment_floor()
	var/obj/item/pen/pen = allocate(/obj/item/pen, T)
	TEST_ASSERT(pen.possession_warn_new("someone"), "the first warning for a ckey is new")
	TEST_ASSERT(!pen.possession_warn_new("someone"), "the second is not")
	TEST_ASSERT(pen.possession_warn_new("other"), "another ckey is new again")
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	TEST_ASSERT(cooldown_ready(H, next_preyloop), "no prey loop has played yet")
	cooldown_start(H, next_preyloop, 52 SECONDS)
	TEST_ASSERT(!cooldown_ready(H, next_preyloop), "a started prey loop waits")
	TEST_ASSERT_EQUAL(sparse_get_or(H, speech_sound_enabled, TRUE), TRUE, "speech sounds are on until switched off")

#endif
