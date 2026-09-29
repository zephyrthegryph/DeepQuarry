// The bespoke capability entries (hand/tool/use_on/insert, code/datums/capabilities/capabilities.dm):
// gating (behind, locked_by, needs + else_say, works_broken, works_unpowered), forms reaching the
// handler as named args, and the dispatch record (log + fingerprint).

/// The capability entry of A named `name`, or null.
/proc/dx_cap_entry(atom/A, name)
	RETURN_TYPE(/datum/interaction/capability)
	for(var/datum/interaction/capability/E as anything in cap_interactions(A))
		if(E.name == name)
			return E
	return null

/// Base fixture for capability tests: records handler calls, and has a switchable power state.
/obj/cap_fixture
	name = "fixture"
	anchored = FALSE
	var/powered = TRUE
	var/list/calls

/obj/cap_fixture/cap_powered()
	return powered

/obj/cap_fixture/entries
	var/ready = FALSE
	var/list/last_args

/obj/cap_fixture/entries/capabilities()
	. = ..()
	. += hand("Poke", PROC_REF(fx_poke), log = LOG_GAME)
	. += hand("Covered", PROC_REF(fx_poke), behind = COVER)
	. += hand("Paneled", PROC_REF(fx_poke), behind = PANEL)
	. += hand("Locked", PROC_REF(fx_poke), locked_by = LOCK)
	. += hand("Needy", PROC_REF(fx_poke), needs = PROC_REF(fx_ready), else_say = "it isn't ready")
	. += hand("Needy text", PROC_REF(fx_poke), needs = PROC_REF(fx_ready_text))
	. += hand("Broken ok", PROC_REF(fx_poke), works_broken = TRUE)
	. += hand("Unpowered ok", PROC_REF(fx_poke), works_unpowered = TRUE)
	. += tool("Tighten", TOOL_WRENCH, PROC_REF(fx_held), log = LOG_GAME)
	. += use_on("Write", /obj/item/pen, PROC_REF(fx_held))
	. += insert("Insert", /obj/item/paper, PROC_REF(fx_held))
	. += hand("Form", PROC_REF(fx_form), form = list(dx_canned_field(/datum/form_field/choice/dx_canned, "pack", "medical"), dx_canned_field(/datum/form_field/text/dx_canned, "reason", "because"), dx_canned_field(/datum/form_field/number/dx_canned, "qty", 3)))

/obj/cap_fixture/entries/proc/fx_poke(mob/user, obj/item/held)
	LAZYADD(calls, "poke")
	return TRUE

/obj/cap_fixture/entries/proc/fx_held(mob/user, obj/item/held)
	LAZYADD(calls, held)
	return TRUE

/obj/cap_fixture/entries/proc/fx_ready(mob/user, obj/item/held)
	return ready

/obj/cap_fixture/entries/proc/fx_ready_text(mob/user, obj/item/held)
	return ready ? TRUE : "the gears are jammed"

/obj/cap_fixture/entries/proc/fx_form(mob/user, obj/item/held, pack, reason, qty)
	last_args = list("pack" = pack, "reason" = reason, "qty" = qty)
	return TRUE

// Form fields that answer without prompting, so the form path runs synchronously in a test.
/datum/form_field/choice/dx_canned
	var/canned
/datum/form_field/choice/dx_canned/ask(datum/dispatch_context/ctx)
	return canned
/datum/form_field/text/dx_canned
	var/canned
/datum/form_field/text/dx_canned/ask(datum/dispatch_context/ctx)
	return canned
/datum/form_field/number/dx_canned
	var/canned
/datum/form_field/number/dx_canned/ask(datum/dispatch_context/ctx)
	return canned

/proc/dx_canned_field(path, name, canned)
	var/datum/form_field/F = new path
	F.name = name
	if(istype(F, /datum/form_field/choice/dx_canned))
		var/datum/form_field/choice/dx_canned/choice = F
		choice.canned = canned
	else if(istype(F, /datum/form_field/text/dx_canned))
		var/datum/form_field/text/dx_canned/text = F
		text.canned = canned
	else if(istype(F, /datum/form_field/number/dx_canned))
		var/datum/form_field/number/dx_canned/number = F
		number.canned = canned
	return F

/// behind / locked_by / needs / works_broken / works_unpowered gate an entry with the right reason.
/datum/unit_test/dx_cap_entries_gating

/datum/unit_test/dx_cap_entries_gating/Run()
	var/turf/T = test_floor()
	var/obj/cap_fixture/entries/F = allocate(/obj/cap_fixture/entries, T)
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)

	var/datum/interaction/capability/poke = dx_cap_entry(F, "Poke")
	TEST_ASSERT_NOTNULL(poke, "the hand entry is offered")
	TEST_ASSERT_NULL(poke.why_not(H, F, null), "an ungated entry runs")
	TEST_ASSERT(poke.perform(H, F, null), "it performs")
	TEST_ASSERT_EQUAL(LAZYLEN(F.calls), 1, "the handler ran once")

	var/datum/interaction/capability/covered = dx_cap_entry(F, "Covered")
	TEST_ASSERT_EQUAL(covered.why_not(H, F, null), "open the cover first", "behind = COVER refuses with the cover shut")
	TEST_ASSERT(!covered.perform(H, F, null), "and does not run")
	TEST_ASSERT_EQUAL(LAZYLEN(F.calls), 1, "the handler did not run")
	cap_set(F, CAP_COVER_OPEN, TRUE)
	TEST_ASSERT_NULL(covered.why_not(H, F, null), "the open cover lets it through")
	TEST_ASSERT_EQUAL(dx_cap_entry(F, "Paneled").why_not(H, F, null), "open the maintenance panel first", "behind = PANEL")
	cap_set(F, CAP_PANEL_OPEN, TRUE)
	TEST_ASSERT_NULL(dx_cap_entry(F, "Paneled").why_not(H, F, null), "the open panel lets it through")

	var/datum/interaction/capability/locked = dx_cap_entry(F, "Locked")
	TEST_ASSERT_NULL(locked.why_not(H, F, null), "unlocked")
	cap_set(F, CAP_LOCKED, TRUE)
	TEST_ASSERT_EQUAL(locked.why_not(H, F, null), "it's locked", "locked_by = LOCK refuses while locked")
	TEST_ASSERT_NULL(poke.why_not(H, F, null), "an entry without locked_by ignores the lock")
	cap_set(F, CAP_LOCKED, FALSE)

	TEST_ASSERT_EQUAL(dx_cap_entry(F, "Needy").why_not(H, F, null), "it isn't ready", "a FALSE needs says else_say")
	TEST_ASSERT_EQUAL(dx_cap_entry(F, "Needy text").why_not(H, F, null), "the gears are jammed", "a text needs is the reason")
	F.ready = TRUE
	TEST_ASSERT_NULL(dx_cap_entry(F, "Needy").why_not(H, F, null), "needs passes")
	TEST_ASSERT_NULL(dx_cap_entry(F, "Needy text").why_not(H, F, null), "text needs passes")

	cap_set(F, CAP_BROKEN, TRUE)
	TEST_ASSERT_EQUAL(poke.why_not(H, F, null), "it's broken", "entries refuse while broken")
	TEST_ASSERT_NULL(dx_cap_entry(F, "Broken ok").why_not(H, F, null), "works_broken ignores it")
	cap_set(F, CAP_BROKEN, FALSE)

	F.powered = FALSE
	TEST_ASSERT_EQUAL(poke.why_not(H, F, null), "it has no power", "entries refuse unpowered")
	TEST_ASSERT_NULL(dx_cap_entry(F, "Unpowered ok").why_not(H, F, null), "works_unpowered ignores it")
	TEST_ASSERT_NULL(dx_cap_entry(F, "Tighten").why_not(H, F, null), "tool entries default to works_unpowered")
	F.powered = TRUE

/// tool/use_on/insert pass the held item to the handler; the selector wants the right item.
/datum/unit_test/dx_cap_entries_held

/datum/unit_test/dx_cap_entries_held/Run()
	var/turf/T = test_floor()
	var/obj/cap_fixture/entries/F = allocate(/obj/cap_fixture/entries, T)
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/obj/item/tool/wrench/wrench = dq_zero_speed(allocate(/obj/item/tool/wrench, T))
	var/obj/item/tool/screwdriver/screwdriver = allocate(/obj/item/tool/screwdriver, T)
	var/obj/item/pen/pen = allocate(/obj/item/pen, T)
	var/obj/item/paper/paper = allocate(/obj/item/paper, T)

	var/datum/interaction/capability/tighten = dx_cap_entry(F, "Tighten")
	TEST_ASSERT_EQUAL(tighten.tool, TOOL_WRENCH, "tool() sets the quality")
	TEST_ASSERT(!tighten.is_meant(H, F, screwdriver), "a screwdriver doesn't select the wrench entry")
	TEST_ASSERT(tighten.is_meant(H, F, wrench), "a wrench does")
	TEST_ASSERT(tighten.perform(H, F, wrench), "the tool entry performs")
	TEST_ASSERT(wrench in F.calls, "the handler got the wrench")

	var/datum/interaction/capability/write = dx_cap_entry(F, "Write")
	TEST_ASSERT(!write.is_meant(H, F, paper), "paper doesn't select use_on(pen)")
	TEST_ASSERT(write.perform(H, F, pen), "use_on performs")
	TEST_ASSERT(pen in F.calls, "the handler got the pen")

	var/datum/interaction/capability/put = dx_cap_entry(F, "Insert")
	TEST_ASSERT_EQUAL(put.category, INTERACTION_CAT_INSERT, "insert() is an insert")
	TEST_ASSERT(put.perform(H, F, paper), "insert performs")
	TEST_ASSERT(paper in F.calls, "the handler got the paper")

/// A form's answers reach the handler as named args; the field constructors keep their settings.
/datum/unit_test/dx_cap_entries_form

/datum/unit_test/dx_cap_entries_form/Run()
	var/turf/T = test_floor()
	var/obj/cap_fixture/entries/F = allocate(/obj/cap_fixture/entries, T)
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)

	TEST_ASSERT(dx_cap_entry(F, "Form").perform(H, F, null), "the form entry performs")
	TEST_ASSERT_NOTNULL(F.last_args, "the handler ran")
	TEST_ASSERT_EQUAL(F.last_args["pack"], "medical", "the choice answer arrives as pack")
	TEST_ASSERT_EQUAL(F.last_args["reason"], "because", "the text answer arrives as reason")
	TEST_ASSERT_EQUAL(F.last_args["qty"], 3, "the number answer arrives as qty")

	var/datum/form_field/choice/C = choice_field("pack", list("a", "b"))
	TEST_ASSERT_EQUAL(C.name, "pack", "choice_field name")
	TEST_ASSERT_EQUAL(length(C.choices), 2, "choice_field choices")
	var/datum/form_field/text/X = text_field("reason", max_length = 20)
	TEST_ASSERT_EQUAL(X.max_length, 20, "text_field max_length")
	var/datum/form_field/number/N = number_field("qty", min_value = 1, max_value = 9)
	TEST_ASSERT_EQUAL(N.min_value, 1, "number_field min")
	TEST_ASSERT_EQUAL(N.max_value, 9, "number_field max")

/// A successful dispatch records the user, target, action and the entry's log level.
/datum/unit_test/dx_cap_entries_record

/datum/unit_test/dx_cap_entries_record/Run()
	var/turf/T = test_floor()
	var/obj/cap_fixture/entries/F = allocate(/obj/cap_fixture/entries, T)
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)

	GLOB.dispatch_last_record = list()
	TEST_ASSERT(dx_cap_entry(F, "Poke").perform(H, F, null), "poke performs")
	TEST_ASSERT_EQUAL(GLOB.dispatch_last_record["user"], H, "recorded the user (fingerprint)")
	TEST_ASSERT_EQUAL(GLOB.dispatch_last_record["target"], F, "recorded the target")
	TEST_ASSERT_EQUAL(GLOB.dispatch_last_record["action"], "Poke", "recorded the action name")
	TEST_ASSERT_EQUAL(GLOB.dispatch_last_record["log"], LOG_GAME, "at the entry's log level")

	GLOB.dispatch_last_record = list()
	TEST_ASSERT(dx_cap_entry(F, "Covered").perform(H, F, null) == FALSE, "a refused entry doesn't run")
	TEST_ASSERT_NULL(GLOB.dispatch_last_record["user"], "and records nothing")

	TEST_ASSERT(dx_cap_entry(F, "Broken ok").perform(H, F, null), "an entry without a log performs")
	TEST_ASSERT_EQUAL(GLOB.dispatch_last_record["user"], H, "still fingerprints")
	TEST_ASSERT_NULL(GLOB.dispatch_last_record["log"], "with no log level")
