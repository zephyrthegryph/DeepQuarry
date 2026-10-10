// The design-review changes to the DX core (design_review.md §8): replace(), ordering, extras,
// systems(), Menu ids, applies, timed_set revert-if-unchanged, VV through setters, one prompt per
// user per action, the look's full coverage, and the self-mark detector.

/datum/capability/dx_review
	var/label

/datum/capability/dx_review/examine(atom/holder, mob/user)
	return list(label)

/datum/capability/dx_review/draw(atom/holder, datum/look/look)
	look.overlay(label)

/datum/capability/dx_review/a
/datum/capability/dx_review/b
/datum/capability/dx_review/c

/proc/dx_review_cap(path, label, layer_order, examine_order)
	var/datum/capability/dx_review/C = new path
	C.label = label
	C.layer_order = layer_order
	C.examine_order = examine_order
	return C

/obj/cap_fixture/dx_review
	var/tracked_value = 0
	var/timed_flag = FALSE

TRACKED_BRIDGED(/obj/cap_fixture/dx_review, tracked_value, CHANGE_DATUM_A)

/obj/cap_fixture/dx_review/capabilities()
	. = ..()
	. += dx_review_cap(/datum/capability/dx_review/a, "a")
	. += dx_review_cap(/datum/capability/dx_review/b, "b", layer_order = 100, examine_order = -1)
	. += dx_review_cap(/datum/capability/dx_review/c, "c")

/obj/cap_fixture/dx_review/replaced/capabilities()
	. = ..()
	. = replace(., /datum/capability/dx_review/a, dx_review_cap(/datum/capability/dx_review/a, "a2"))

/// replace() keeps the position; layer_order / examine_order reorder draw and examine only.
/datum/unit_test/dx_review_order_and_replace/Run()
	var/obj/cap_fixture/dx_review/F = allocate(/obj/cap_fixture/dx_review)
	var/list/labels = list()
	for(var/datum/capability/dx_review/C as anything in caps_of(F))
		labels += C.label
	TEST_ASSERT_EQUAL(jointext(labels, ","), "a,b,c", "list order is declaration order")
	labels = list()
	for(var/datum/capability/dx_review/C as anything in caps_ordered(F, CAP_ORDER_DRAW))
		labels += C.label
	TEST_ASSERT_EQUAL(jointext(labels, ","), "a,c,b", "layer_order = 100 draws b last")
	TEST_ASSERT_EQUAL(jointext(caps_examine(F, null), ","), "b,a,c", "examine_order = -1 lists b first")
	var/obj/cap_fixture/dx_review/replaced/R = allocate(/obj/cap_fixture/dx_review/replaced)
	labels = list()
	for(var/datum/capability/dx_review/C as anything in caps_of(R))
		labels += C.label
	TEST_ASSERT_EQUAL(jointext(labels, ","), "a2,b,c", "replace() keeps the position")

/datum/system/dx_review

/datum/capability/dx_review/joining
	joins = list(/datum/system/dx_review)

/// A runtime extra joins the type's list, its systems and its menu; removing it undoes all three.
/datum/unit_test/dx_review_extras_and_systems/Run()
	var/obj/cap_fixture/dx_review/F = allocate(/obj/cap_fixture/dx_review)
	var/datum/capability/dx_review/joining/X = dx_review_cap(/datum/capability/dx_review/joining, "extra")
	TEST_ASSERT(add_capability(F, X), "the extra attaches")
	TEST_ASSERT(!add_capability(F, X), "the same key can't attach twice")
	TEST_ASSERT(X in caps_all(F), "caps_all() includes the extra")
	TEST_ASSERT(!(X in caps_of(F)), "the type's list is untouched")
	var/datum/system/dx_review/review_system = system(/datum/system/dx_review)
	TEST_ASSERT(F in review_system.member_list(), "the holder joined the extra's system")
	TEST_ASSERT("extra" in caps_examine(F, null), "the extra's examine line shows")
	TEST_ASSERT(remove_capability(F, /datum/capability/dx_review/joining), "the extra detaches")
	TEST_ASSERT(!(F in review_system.member_list()), "the holder left the system")
	TEST_ASSERT(!("extra" in caps_examine(F, null)), "the examine line is gone")

/obj/cap_fixture/dx_review_menu

/obj/cap_fixture/dx_review_menu/capabilities()
	. = ..()
	. += cap_hand("Poke", PROC_REF(poke), works_unpowered = TRUE, applies = PROC_REF(pokeable))

/obj/cap_fixture/dx_review_menu/var/can_poke = TRUE

/obj/cap_fixture/dx_review_menu/proc/poke(mob/user)
	return TRUE

/obj/cap_fixture/dx_review_menu/proc/pokeable()
	return can_poke

/// The Menu runs a chosen capability entry by id; applies = hides it per instance.
/datum/unit_test/dx_review_menu_ids_and_applies/Run()
	var/obj/cap_fixture/dx_review_menu/F = allocate(/obj/cap_fixture/dx_review_menu)
	var/list/entries = cap_interactions(F)
	TEST_ASSERT_EQUAL(length(entries), 1, "one entry")
	var/datum/interaction/capability/E = entries[1]
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, get_turf(F))
	TEST_ASSERT(run_chosen_interaction(H, F, E.id), "the Menu runs the capability entry by its id on this target")
	TEST_ASSERT(E.applies_to(F), "offered while pokeable")
	F.can_poke = FALSE
	TEST_ASSERT(!E.applies_to(F), "not offered once applies says no")

/// M5: a revert only fires while the var still holds what timed_set wrote. M6: VV uses the setter.
/datum/unit_test/dx_review_timed_and_vv/Run()
	var/obj/cap_fixture/dx_review/F = allocate(/obj/cap_fixture/dx_review)
	timed_set(F, nameof(/obj/cap_fixture/dx_review::tracked_value), 5, for_time = 1 SECONDS, clock = CLOCK_WORLD)
	TEST_ASSERT_EQUAL(F.tracked_value, 5, "timed_set wrote through the setter")
	F.set_tracked_value(7)
	var/list/pending = F.timed_until[nameof(/obj/cap_fixture/dx_review::tracked_value)]
	TEST_ASSERT_NOTNULL(pending, "a revert is pending")
	timed_expire(F, nameof(/obj/cap_fixture/dx_review::tracked_value), pending[1])
	TEST_ASSERT_EQUAL(F.tracked_value, 7, "the revert kept a value written since")

	refresh_flush()
	F.vv_edit_var(nameof(/obj/cap_fixture/dx_review::tracked_value), 11)
	TEST_ASSERT_EQUAL(F.tracked_value, 11, "VV wrote the value")
	TEST_ASSERT(F.refresh_queued, "VV went through the setter, which marked the fixture")
	refresh_flush()

/// M7: one open prompt per user per action.
/datum/unit_test/dx_review_one_prompt/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/obj/cap_fixture/dx_review/F = allocate(/obj/cap_fixture/dx_review)
	var/datum/dispatch_context/ctx = new(H, F)
	TEST_ASSERT(ask_open(ctx), "the first prompt opens")
	TEST_ASSERT(!ask_open(new /datum/dispatch_context(H, F)), "a second prompt for the same action is refused")
	ask_close(ctx)
	TEST_ASSERT(ask_open(ctx), "it opens again once closed")
	ask_close(ctx)

/obj/cap_fixture/dx_review_look
	var/tint = "#ff0000"

/obj/cap_fixture/dx_review_look/draw(datum/look/look)
	..()
	look.state("base")
	look.set_color(tint)
	look.set_alpha(200)
	look.add_look_filter("outline", list("type" = "outline", "size" = 1))

/// M9: the look covers color, alpha and filters, and they are part of the key.
/datum/unit_test/dx_review_look_coverage/Run()
	var/obj/cap_fixture/dx_review_look/F = allocate(/obj/cap_fixture/dx_review_look)
	changed(F)
	refresh_flush()
	TEST_ASSERT_EQUAL(F.icon_state, "base", "state applied")
	TEST_ASSERT_EQUAL(F.color, "#ff0000", "color applied")
	TEST_ASSERT_EQUAL(F.alpha, 200, "alpha applied")
	TEST_ASSERT(F.get_filter("outline"), "filter applied")
	var/key = F.rx?.look_key
	F.tint = "#00ff00"
	changed(F)
	refresh_flush()
	TEST_ASSERT(F.rx?.look_key != key, "a color change changes the key")
	TEST_ASSERT_EQUAL(F.color, "#00ff00", "the new color applied")

/obj/cap_fixture/dx_review_selfmark

/obj/cap_fixture/dx_review_selfmark/on_state_changed(bits)
	changed(src) // wrong on purpose: a reactive proc marking its own entity

/// H5: an entity that marks itself during its own refresh is reported.
/datum/unit_test/dx_review_self_mark/Run()
	set_global("refresh_self_mark_expected", TRUE)
	var/before = length(GLOB.refresh_self_marks)
	var/obj/cap_fixture/dx_review_selfmark/F = allocate(/obj/cap_fixture/dx_review_selfmark)
	changed(F)
	// One drain, not refresh_flush(): the fixture re-marks itself forever, which flush reports as a
	// runaway after its pass cap. One pass is enough for the detector, and the re-mark waits (deferred).
	refresh_drain(null)
	set_global("refresh_self_mark_expected", FALSE)
	TEST_ASSERT(length(GLOB.refresh_self_marks) > before, "the self-mark detector reported it")
	TEST_ASSERT(F.refresh_queued, "the self re-mark waits for the next drain instead of spinning")
	F.refresh_queued = FALSE
	GLOB.refresh_queue -= F

/datum/dx_ui_secure
	var/mob/last_user
	var/last_force
	var/hook_called = FALSE
	var/legacy_called = FALSE

/datum/dx_ui_secure/proc/act_vent(mob/user, force)
	last_user = user
	last_force = ui_bool(force)
	return TRUE

/datum/dx_ui_secure/ui_logged()
	hook_called = TRUE
	return list()

/datum/dx_ui_secure/proc/ui_act_legacy(mob/user, list/params)
	legacy_called = TRUE
	return TRUE

/// Review 2 C1: only act_* procs are actions; the client can't set reserved names or reach hooks
/// and legacy handlers; hyphen/camelCase names normalise to one key.
/datum/unit_test/dx_review_ui_security/Run()
	var/datum/dx_ui_secure/H = new
	var/datum/tgui/ui = ui_test_window(H)
	TEST_ASSERT(H.tgui_act("vent", list("user" = "EVIL", "force" = "1"), ui), "the action ran")
	TEST_ASSERT(H.last_user == ui.user, "a client-sent user never overrides the real user")
	TEST_ASSERT_EQUAL(H.last_force, TRUE, "a declared param arrives")
	TEST_ASSERT(!H.tgui_act("logged", list(), ui), "a ui_ hook is not an action")
	TEST_ASSERT(!H.tgui_act("act_legacy", list("params" = list()), ui), "a ui_act_* legacy handler is not an action")
	TEST_ASSERT(!H.tgui_act("ui_act_legacy", list(), ui), "not by its full name either")
	TEST_ASSERT(!H.legacy_called, "the legacy handler never ran")
	TEST_ASSERT(H.tgui_act("Vent", list("Force" = "0"), ui), "a capitalised name normalises")
	TEST_ASSERT_EQUAL(H.last_force, FALSE, "a capitalised key normalises")
	TEST_ASSERT_EQUAL(ui_action_key("bolt-toggle"), "bolt_toggle", "hyphens normalise")
	TEST_ASSERT_EQUAL(ui_action_key("setScreen"), "set_screen", "camelCase normalises")
	TEST_ASSERT_NULL(ui_action_key("../x"), "anything else is refused")
	qdel(ui)

/// Review 2 M10: a static per-type verb difference is type_verbs() (no per-instance hide, no sweep).
/datum/unit_test/dx_review_type_verbs/Run()
	var/obj/item/healthanalyzer/basic = allocate(/obj/item/healthanalyzer)
	var/obj/item/healthanalyzer/advanced/adv = allocate(/obj/item/healthanalyzer/advanced)
	refresh_flush()
	TEST_ASSERT(!(/obj/item/healthanalyzer/proc/toggle_adv in basic.verbs), "a basic analyzer has no toggle")
	TEST_ASSERT(/obj/item/healthanalyzer/proc/toggle_adv in adv.verbs, "an advanced analyzer has the toggle from init")
	TEST_ASSERT(!basic.rx?.refresh_hidden_verbs, "no per-instance hide list on the basic one")

/obj/cap_fixture/dx_review_light
	var/lit = TRUE

/obj/cap_fixture/dx_review_light/draw(datum/look/look)
	..()
	look.state("lamp")
	if(lit)
		look.light(2, 1, "#ffcc00")

/// Review 2 H4: look.light() applies with the look and is taken back when the look stops setting it.
/datum/unit_test/dx_review_look_light/Run()
	var/obj/cap_fixture/dx_review_light/F = allocate(/obj/cap_fixture/dx_review_light)
	changed(F)
	refresh_flush()
	TEST_ASSERT_EQUAL(F.light_range, 2, "the look's light applied")
	F.lit = FALSE
	changed(F)
	refresh_flush()
	TEST_ASSERT(!F.light_range, "the light went off when the look stopped setting it")

/obj/cap_fixture/dx_review_interval
	periodic_interval = 1 SECONDS
	var/running = FALSE
	var/steps = 0

/obj/cap_fixture/dx_review_interval/should_run()
	return running

/obj/cap_fixture/dx_review_interval/periodic_step(delta)
	steps++

/// periodic_interval: a custom-interval step that runs while should_run() holds (the DECLARE_REPEAT replacement).
/datum/unit_test/om/dx_review_periodic_interval

/datum/unit_test/om/dx_review_periodic_interval/run_om(list/made)
	var/obj/cap_fixture/dx_review_interval/F = new
	made += F
	refresh_flush()
	TEST_ASSERT(!after_pending(F, "periodic_interval"), "not armed while should_run() is FALSE")
	F.running = TRUE
	changed(F)
	refresh_flush()
	TEST_ASSERT(after_pending(F, "periodic_interval"), "armed once should_run() holds")
	scheduler_advance(2.5)
	TEST_ASSERT(F.steps >= 2, "stepped every interval ([F.steps])")
	F.running = FALSE
	changed(F)
	refresh_flush()
	var/steps = F.steps
	scheduler_advance(2.5)
	TEST_ASSERT_EQUAL(F.steps, steps, "stopped once should_run() is FALSE")

/// The UI data one capability of A contributes (tgui_data nests it under data["caps"][ui_key()]).
/proc/dx_cap_ui_data(atom/A, mob/user, cap_type)
	var/list/data = list()
	caps_ui_data(A, user, data)
	var/datum/capability/C = cap_of_all(A, cap_type)
	var/list/caps = data["caps"]
	return (C && caps) ? (caps[C.ui_key()] || list()) : list()
