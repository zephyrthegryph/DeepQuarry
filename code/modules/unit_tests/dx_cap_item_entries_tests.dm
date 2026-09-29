// cap_use_self / cap_use_at (code/datums/capabilities/item_entries.dm): an item used on itself (only in
// hand), used on another atom (adjacent and ranged, target_types), form args, the dispatch record, and
// the legacy attackby/afterattack path when no entry matches.

/obj/item/cap_fixture_item
	name = "fixture item"
	var/list/calls
	var/list/last_args
	var/legacy_after = 0
	var/ready = TRUE

/obj/item/cap_fixture_item/capabilities()
	. = ..()
	. += cap_use_self("Squeeze", PROC_REF(fx_self), log = LOG_GAME)
	. += cap_use_self("Squeeze with form", PROC_REF(fx_self_form), form = list(dx_entries_canned_field(/datum/form_field/text/dx_canned, "reason", "because")))
	. += cap_use_at("Poke", PROC_REF(fx_at), log = LOG_GAME, target_types = /obj/cap_fixture/item_target)
	. += cap_use_at("Zap", PROC_REF(fx_at), range = 7, target_types = list(/obj/cap_fixture/zap_target))
	. += cap_use_at("Gated", PROC_REF(fx_at), target_types = /obj/cap_fixture/gated_target, needs = PROC_REF(fx_ready), else_say = "it is not ready")
	. += cap_use_at("Form", PROC_REF(fx_at_form), target_types = /obj/cap_fixture/form_target, form = list(dx_entries_canned_field(/datum/form_field/choice/dx_canned, "pack", "medical")))

/obj/item/cap_fixture_item/proc/fx_self(mob/user)
	LAZYADD(calls, "self")
	return TRUE

/obj/item/cap_fixture_item/proc/fx_self_form(mob/user, reason)
	last_args = list("reason" = reason)
	return TRUE

/obj/item/cap_fixture_item/proc/fx_at(mob/user, atom/target)
	LAZYADD(calls, target)
	return TRUE

/obj/item/cap_fixture_item/proc/fx_at_form(mob/user, atom/target, pack)
	last_args = list("target" = target, "pack" = pack)
	return TRUE

/obj/item/cap_fixture_item/proc/fx_ready(mob/user, obj/item/held)
	return ready

/obj/item/cap_fixture_item/afterattack(atom/target, mob/user, proximity_flag, click_parameters, stance = I_HURT)
	legacy_after++

/obj/cap_fixture/item_target
	var/attacked = 0

/obj/cap_fixture/item_target/attackby(obj/item/W, mob/user, attack_modifier, click_parameters)
	attacked++
	return ..()

/obj/cap_fixture/zap_target
/obj/cap_fixture/gated_target
/obj/cap_fixture/form_target
/obj/cap_fixture/plain_target
	var/attacked = 0

/obj/cap_fixture/plain_target/attackby(obj/item/W, mob/user, attack_modifier, click_parameters)
	attacked++
	return ..()

/// What the click adapter does with an item in hand: the target's attackby, then the use_at entries or afterattack.
/proc/dx_item_click(obj/item/W, atom/A, mob/user, proximity)
	var/resolved
	if(proximity)
		resolved = W.resolve_attackby(A, user)
	if(!ITEM_INTERACT_CONSUMED(resolved))
		W.after_click(A, user, proximity)

/// cap_use_self: offered only while the item is in the user's hand; the handler runs through attack_self.
/datum/unit_test/dx_cap_use_self

/datum/unit_test/dx_cap_use_self/Run()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/obj/item/cap_fixture_item/I = allocate(/obj/item/cap_fixture_item, T)
	var/datum/interaction/capability/E = dx_cap_entry(I, "Squeeze")
	TEST_ASSERT_NOTNULL(E, "the use_self entry is built on the item")
	TEST_ASSERT_EQUAL(E.default_action, INPUT_ACTION_SELF_USE, "it answers the self-use input")
	TEST_ASSERT_EQUAL(E.entry, INTERACTION_ENTRY_SELF, "it runs from attack_self")
	TEST_ASSERT(!E.passes_held, "the handler is (mob/user)")
	TEST_ASSERT_NOTNULL(E.why_not(H, I, I), "refused while the item is not held")
	I.attack_self(H)
	TEST_ASSERT_EQUAL(LAZYLEN(I.calls), 0, "attack_self on an unheld item does nothing")
	TEST_ASSERT(H.put_in_active_hand(I), "the human holds the item")
	TEST_ASSERT_NULL(E.why_not(H, I, I), "offered while held")
	I.attack_self(H)
	TEST_ASSERT_EQUAL(LAZYLEN(I.calls), 1, "the handler ran once when held")
	TEST_ASSERT_EQUAL(I.calls[1], "self", "the right handler")
	TEST_ASSERT_EQUAL(GLOB.dispatch_last_record["action"], "Squeeze", "the dispatch recorded it")
	TEST_ASSERT_EQUAL(GLOB.dispatch_last_record["log"], LOG_GAME, "with the declared log")
	TEST_ASSERT(GLOB.dispatch_last_record["target"] == I, "on the item")

/// A form on a use_self entry reaches the handler by name.
/datum/unit_test/dx_cap_use_self_form

/datum/unit_test/dx_cap_use_self_form/Run()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/obj/item/cap_fixture_item/I = allocate(/obj/item/cap_fixture_item, T)
	TEST_ASSERT(H.put_in_active_hand(I), "the human holds the item")
	I.attack_self(H)
	// Two use_self entries are candidates; the first meant one answers (Squeeze), so drive the form entry directly.
	var/datum/interaction/capability/E = dx_cap_entry(I, "Squeeze with form")
	TEST_ASSERT(E.perform(H, I, I), "the form entry performs")
	TEST_ASSERT_EQUAL(I.last_args["reason"], "because", "the form answer arrives as a named arg")

/// cap_use_at: adjacent and ranged, target_types filtering, the dispatch record, gating and form args.
/datum/unit_test/dx_cap_use_at

/datum/unit_test/dx_cap_use_at/Run()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/obj/item/cap_fixture_item/I = allocate(/obj/item/cap_fixture_item, T)
	var/obj/cap_fixture/item_target/near = allocate(/obj/cap_fixture/item_target, T)
	var/obj/cap_fixture/zap_target/zap = allocate(/obj/cap_fixture/zap_target, T)
	var/obj/cap_fixture/gated_target/gated = allocate(/obj/cap_fixture/gated_target, T)
	var/obj/cap_fixture/form_target/form = allocate(/obj/cap_fixture/form_target, T)
	TEST_ASSERT(H.put_in_active_hand(I), "the human holds the item")
	TEST_ASSERT_NULL(dx_cap_entry(near, "Poke"), "a use_at entry is not an interaction on the target")
	TEST_ASSERT_NULL(dx_cap_entry(I, "Poke"), "nor on the item itself")

	// Adjacent, matching type: the entry runs INSTEAD of afterattack; the target is passed.
	dx_item_click(I, near, H, TRUE)
	TEST_ASSERT_EQUAL(LAZYLEN(I.calls), 1, "the adjacent use_at ran")
	TEST_ASSERT(I.calls[1] == near, "the clicked atom is the handler's target")
	TEST_ASSERT_EQUAL(I.legacy_after, 0, "afterattack did not also run")
	TEST_ASSERT_EQUAL(near.attacked, 1, "the target's own attackby still ran first")
	TEST_ASSERT_EQUAL(GLOB.dispatch_last_record["action"], "Poke", "the dispatch recorded the entry")
	TEST_ASSERT_EQUAL(GLOB.dispatch_last_record["log"], LOG_GAME, "with its log")
	TEST_ASSERT(GLOB.dispatch_last_record["target"] == I, "the item is the holder that is marked and logged")
	TEST_ASSERT(GLOB.dispatch_last_record["user"] == H, "by the user")

	// Ranged (proximity FALSE): only range > 1 entries match.
	I.calls = null
	dx_item_click(I, near, H, FALSE)
	TEST_ASSERT_EQUAL(LAZYLEN(I.calls), 0, "a range 1 entry does not fire at range")
	TEST_ASSERT_EQUAL(I.legacy_after, 1, "the legacy afterattack ran instead")
	dx_item_click(I, zap, H, FALSE)
	TEST_ASSERT_EQUAL(LAZYLEN(I.calls), 1, "the range 7 entry fires at a ranged target")
	TEST_ASSERT(I.calls[1] == zap, "with the target")
	I.calls = null
	dx_item_click(I, zap, H, TRUE)
	TEST_ASSERT_EQUAL(LAZYLEN(I.calls), 1, "a ranged entry also fires adjacent")

	// target_types filtering: a plain fixture matches no entry, so afterattack ran.
	var/obj/cap_fixture/plain_target/plain = allocate(/obj/cap_fixture/plain_target, T)
	I.calls = null
	var/before = I.legacy_after
	dx_item_click(I, plain, H, TRUE)
	TEST_ASSERT_EQUAL(LAZYLEN(I.calls), 0, "no entry matches an unlisted target type")
	TEST_ASSERT_EQUAL(plain.attacked, 1, "the ordinary attackby on the target still happened")
	TEST_ASSERT_EQUAL(I.legacy_after, before + 1, "and the legacy afterattack followed")

	// Gating reads the item and tells the user.
	I.calls = null
	I.ready = FALSE
	dx_item_click(I, gated, H, TRUE)
	TEST_ASSERT_EQUAL(LAZYLEN(I.calls), 0, "a needs that fails stops the entry")
	var/datum/capability/entry/use_at/G
	for(var/datum/capability/C as anything in caps_all(I))
		var/datum/capability/entry/use_at/U = C
		if(istype(U) && U.entry.name == "Gated")
			G = U
	TEST_ASSERT_NOTNULL(G, "the gated entry is on the item")
	var/datum/interaction/capability/use_at/GE = G.entry
	TEST_ASSERT_EQUAL(GE.why_not(H, gated, I), "it is not ready", "the reason is else_say")
	I.ready = TRUE
	dx_item_click(I, gated, H, TRUE)
	TEST_ASSERT_EQUAL(LAZYLEN(I.calls), 1, "it runs once the need holds")

	// Not held: no entry offers itself.
	var/obj/item/cap_fixture_item/loose = allocate(/obj/item/cap_fixture_item, T)
	TEST_ASSERT_NOTNULL(GE.why_not(H, gated, loose), "an item that is not in hand refuses")

	// Form args and the target arrive by name.
	dx_item_click(I, form, H, TRUE)
	TEST_ASSERT_EQUAL(I.last_args["pack"], "medical", "the form answer arrives as a named arg")
	TEST_ASSERT(I.last_args["target"] == form, "with the target")
