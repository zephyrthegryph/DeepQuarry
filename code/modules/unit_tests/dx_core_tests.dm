// The DX framework core (code/datums/capabilities/): capabilities(), TRACKED, changed() and the
// refresh engine, the look builder, drift, periodic gating, hidden verbs, ui_<action> dispatch,
// dispatch_call(), ask_* re-validation and forms, timed_set().

// ---------------------------------------------------------------- fixtures

/datum/capability/dx_test
	var/label

/datum/capability/dx_test/examine(atom/holder, mob/user)
	return list(label)

/datum/capability/dx_test/draw(atom/holder, datum/look/look)
	look.overlay(layer_name, when = cap_has(holder, CAP_PANEL_OPEN))

/datum/capability/dx_test/a
/datum/capability/dx_test/b
/datum/capability/dx_test/c

/proc/dx_test_cap(path, label)
	var/datum/capability/dx_test/C = new path
	C.label = label
	C.layer_name = "[label]_layer"
	return C

/// A form field that answers without a prompt.
/datum/form_field/dx_canned
	var/answer

/datum/form_field/dx_canned/ask(datum/dispatch_context/ctx)
	return answer

/proc/dx_canned_field(name, answer)
	var/datum/form_field/dx_canned/F = new
	F.name = name
	F.answer = answer
	return F

/datum/dx_core_child
	var/level = 0

TRACKED(/datum/dx_core_child, level, CHANGE_EFFECTS)

/obj/cap_fixture
	name = "capability fixture"

/obj/cap_fixture/dx_core
	icon_state = "fixture_base"
	var/power_level = 0
	var/drift_state = FALSE
	var/datum/dx_core_child/child
	var/state_changes = 0
	var/last_bits = 0
	var/slept_done = FALSE
	var/list/form_answers

OWN(/obj/cap_fixture/dx_core, child, OWN_DELETE)
TRACKED(/obj/cap_fixture/dx_core, power_level, CHANGE_EFFECTS)

/obj/cap_fixture/dx_core/capabilities()
	. = ..()
	. += dx_test_cap(/datum/capability/dx_test/a, "alpha")
	. += dx_test_cap(/datum/capability/dx_test/b, "beta")
	. += cap_hand("Configure", PROC_REF(dx_configure), form = list(dx_canned_field("mode", "fast"), dx_canned_field("count", 3)))

/obj/cap_fixture/dx_core/draw(datum/look/look)
	..()
	look.state(power_level ? "on" : "off")
	look.gauge("charge", level = power_level / 10, levels = 4)
	look.glow("light", when = power_level > 5)
	look.overlay("drift", when = drift_state)

/obj/cap_fixture/dx_core/hidden_verbs()
	. = ..()
	if(!power_level)
		. += /obj/cap_fixture/dx_core/verb/dx_secret

/obj/cap_fixture/dx_core/on_state_changed(bits)
	state_changes++
	last_bits = bits

/obj/cap_fixture/dx_core/verb/dx_secret()
	set name = "DX Secret"
	set src in view(1)

/obj/cap_fixture/dx_core/proc/dx_configure(mob/user, obj/item/held, mode, count)
	form_answers = list("mode" = mode, "count" = count)

/obj/cap_fixture/dx_core/proc/dx_sleepy(mob/user)
	sleep(1)
	slept_done = TRUE

/obj/cap_fixture/dx_core/child/capabilities()
	. = ..()
	. = without(., /datum/capability/dx_test/a)
	. += dx_test_cap(/datum/capability/dx_test/c, "gamma")

/// Draws nothing, hides nothing, has no capabilities.
/obj/cap_fixture/dx_plain
	icon_state = "keepme"

/obj/cap_fixture/dx_periodic
	periodic_cadence = PERIODIC_SLOW
	var/gating = FALSE

TRACKED(/obj/cap_fixture/dx_periodic, gating, CHANGE_EFFECTS)

/obj/cap_fixture/dx_periodic/should_run()
	return gating

/obj/cap_fixture/dx_periodic/periodic_step(delta)
	return

/datum/dx_ui_host
	var/allow = TRUE
	var/value
	var/logged_calls = 0

/datum/dx_ui_host/ui_allowed(mob/user, action)
	return allow

/datum/dx_ui_host/ui_logged()
	return list("record" = LOG_GAME)

/datum/dx_ui_host/proc/act_set_value(mob/user, value)
	value = ui_number(value, 0, 100)
	if(isnull(value))
		return refuse(user, "That isn't a number.")
	src.value = value

/datum/dx_ui_host/proc/act_record(mob/user)
	logged_calls++

// ---------------------------------------------------------------- 1. capabilities()

/datum/unit_test/dx_core_capabilities_list/Run()
	var/obj/cap_fixture/dx_core/A = allocate(/obj/cap_fixture/dx_core)
	var/obj/cap_fixture/dx_core/B = allocate(/obj/cap_fixture/dx_core)
	var/obj/cap_fixture/dx_core/child/C = allocate(/obj/cap_fixture/dx_core/child)
	var/list/caps = caps_of(A)
	TEST_ASSERT_EQUAL(length(caps), 3, "three capabilities")
	TEST_ASSERT(istype(caps[1], /datum/capability/dx_test/a) && istype(caps[2], /datum/capability/dx_test/b), "declaration order kept")
	TEST_ASSERT(caps_of(B) == caps, "caps_of is cached and shared per type")
	TEST_ASSERT(caps_of(A) == caps, "caps_of returns the same list again")
	var/list/child_caps = caps_of(C)
	TEST_ASSERT_NULL(cap_of(C, /datum/capability/dx_test/a), "without() dropped the parent's entry by type")
	TEST_ASSERT(istype(child_caps[1], /datum/capability/dx_test/b) && istype(child_caps[3], /datum/capability/dx_test/c), "without() keeps the order, . += appends")
	TEST_ASSERT_EQUAL(jointext(A.caps_examine(null), ","), "alpha,beta", "examine follows list order")
	TEST_ASSERT_EQUAL(jointext(C.caps_examine(null), ","), "beta,gamma", "the child's examine follows its list")

// ---------------------------------------------------------------- 2/3. TRACKED, changed(), refresh

/datum/unit_test/dx_core_tracked_and_changed/Run()
	var/obj/cap_fixture/dx_core/F = allocate(/obj/cap_fixture/dx_core)
	refresh_flush()
	var/before = F.state_changes
	TEST_ASSERT(F.set_power_level(3), "set_ returns TRUE on a change")
	TEST_ASSERT(F.refresh_queued, "a change queues the refresh")
	TEST_ASSERT(F.refresh_bits & CHANGE_EFFECTS, "refresh_bits carries the channel")
	TEST_ASSERT(!F.set_power_level(3), "set_ returns FALSE with no change")
	var/queued = 0
	for(var/datum/D as anything in GLOB.refresh_queue)
		if(D == F)
			queued++
	TEST_ASSERT_EQUAL(queued, 1, "queued once per frame")
	changed(F, CHANGE_CONTENTS)
	refresh_flush()
	TEST_ASSERT_EQUAL(F.state_changes - before, 1, "on_state_changed ran once for the frame")
	TEST_ASSERT(F.last_bits & CHANGE_EFFECTS, "on_state_changed got the TRACKED channel")
	TEST_ASSERT(F.last_bits & CHANGE_CONTENTS, "on_state_changed got the explicit channel")
	TEST_ASSERT_EQUAL(F.refresh_bits, 0, "bits are cleared after the refresh")
	TEST_ASSERT_EQUAL(F.icon_state, "on", "draw ran")

/// A capability that draws the holder's `child` (draws_var): the child's changes mark the holder (H2).
/datum/capability/dx_draws_child
	draws_var = "child"

/obj/cap_fixture/dx_core/draws_child

/obj/cap_fixture/dx_core/draws_child/capabilities()
	. = ..()
	var/datum/capability/dx_draws_child/C = new
	C.draws_var = nameof(/obj/cap_fixture/dx_core::child)
	. += C

/// H2: a child's change marks its owner only when a capability of the owner draws that child.
/datum/unit_test/dx_core_changed_owner_chain/Run()
	var/obj/cap_fixture/dx_core/plain = allocate(/obj/cap_fixture/dx_core)
	var/datum/dx_core_child/plain_child = new
	own_set(plain, nameof(/obj/cap_fixture/dx_core::child), plain_child)
	refresh_flush()
	TEST_ASSERT(owner_of(plain_child) == plain, "the child is owned")
	TEST_ASSERT(plain_child.set_level(2), "the child's setter changed it")
	TEST_ASSERT(!plain.refresh_queued, "an owner that doesn't draw the child is not marked")
	refresh_flush()

	var/obj/cap_fixture/dx_core/draws_child/F = allocate(/obj/cap_fixture/dx_core/draws_child)
	var/datum/dx_core_child/K = new
	own_set(F, nameof(/obj/cap_fixture/dx_core::child), K)
	refresh_flush()
	var/before = F.state_changes
	TEST_ASSERT(K.set_level(2), "the child's setter changed it")
	TEST_ASSERT(F.refresh_queued, "the owner that draws the child is queued with it")
	TEST_ASSERT(F.refresh_bits & CHANGE_EFFECTS, "the owner carries the child's channel")
	refresh_flush()
	TEST_ASSERT_EQUAL(F.state_changes - before, 1, "the owner refreshed once")

// ---------------------------------------------------------------- 4. look builder

/datum/unit_test/dx_core_look/Run()
	var/obj/cap_fixture/dx_core/F = allocate(/obj/cap_fixture/dx_core)
	F.set_power_level(5)
	refresh_flush()
	TEST_ASSERT_EQUAL(F.icon_state, "on", "state applied")
	TEST_ASSERT(findtext(F.look_key, "charge2"), "gauge quantised 0.5 of 4 to step 2: [F.look_key]")
	TEST_ASSERT(!findtext(F.look_key, "light"), "glow off while its condition is false")
	TEST_ASSERT(!findtext(F.look_key, "alpha_layer"), "a capability overlay off while its condition is false")
	cap_set(F, CAP_PANEL_OPEN, TRUE)
	F.set_power_level(8)
	refresh_flush()
	TEST_ASSERT(findtext(F.look_key, "light"), "glow on: [F.look_key]")
	TEST_ASSERT(findtext(F.look_key, "alpha_layer,beta_layer"), "capability overlays in list order: [F.look_key]")
	TEST_ASSERT(findtext(F.look_key, "charge3"), "gauge moved to step 3")
	var/key = F.look_key
	var/list/applied = F.look_overlays
	changed(F)
	refresh_flush()
	TEST_ASSERT_EQUAL(F.look_key, key, "an identical look keeps its key")
	TEST_ASSERT(F.look_overlays == applied, "an identical look churns no overlays")

	var/obj/cap_fixture/dx_plain/P = allocate(/obj/cap_fixture/dx_plain)
	changed(P)
	refresh_flush()
	TEST_ASSERT_EQUAL(P.icon_state, "keepme", "a type that draws nothing keeps its icon_state")
	TEST_ASSERT_NULL(P.look_key, "and has no look key")
	TEST_ASSERT(!type_derives(P), "type_derives: FALSE for a type with nothing derived")
	TEST_ASSERT(!isnull(GLOB.type_derives_cache[P.type]), "type_derives is cached per type")
	TEST_ASSERT(type_derives(F), "type_derives: TRUE for a type that draws")

// ---------------------------------------------------------------- 5. drift

/datum/unit_test/dx_core_refresh_drift/Run()
	var/obj/cap_fixture/dx_core/F = allocate(/obj/cap_fixture/dx_core)
	refresh_flush()
	TEST_ASSERT(GLOB.refresh_sweep_list[REF(F)], "a drawn atom is tracked by the sweep")
	TEST_ASSERT(!refresh_check_drift(F), "no drift right after a refresh")
	F.drift_state = TRUE // deliberately unmarked
	var/before = length(GLOB.refresh_drift)
	GLOB.refresh_drift_expected = TRUE
	var/found = refresh_check_drift(F)
	GLOB.refresh_drift_expected = FALSE
	TEST_ASSERT(found, "the sweep check found the unmarked write")
	TEST_ASSERT_EQUAL(length(GLOB.refresh_drift) - before, 1, "one REFRESH DRIFT report")
	TEST_ASSERT(findtext(GLOB.refresh_drift[length(GLOB.refresh_drift)], "REFRESH DRIFT"), "the report names the drift")
	TEST_ASSERT(findtext(F.look_key, "drift"), "the drift was corrected")
	TEST_ASSERT(!refresh_check_drift(F), "and is gone after the correction")
	GLOB.refresh_drift_expected = TRUE
	refresh_sweep_step(length(GLOB.refresh_sweep_list))
	GLOB.refresh_drift_expected = FALSE

// ---------------------------------------------------------------- 6. periodic gating

/datum/unit_test/dx_core_periodic_gate/Run()
	var/obj/cap_fixture/dx_periodic/F = allocate(/obj/cap_fixture/dx_periodic)
	refresh_flush()
	TEST_ASSERT(!om_task_periodic_running(F), "not running while should_run() is FALSE")
	F.set_gating(TRUE)
	refresh_flush()
	TEST_ASSERT(om_task_periodic_running(F), "running once should_run() is TRUE")
	F.set_gating(FALSE)
	refresh_flush()
	TEST_ASSERT(!om_task_periodic_running(F), "stopped once should_run() is FALSE again")

// ---------------------------------------------------------------- 7. hidden verbs

/datum/unit_test/dx_core_hidden_verbs/Run()
	var/obj/cap_fixture/dx_core/F = allocate(/obj/cap_fixture/dx_core)
	refresh_flush()
	TEST_ASSERT(!(/obj/cap_fixture/dx_core/verb/dx_secret in F.verbs), "hidden while power_level is 0")
	F.set_power_level(1)
	refresh_flush()
	TEST_ASSERT(/obj/cap_fixture/dx_core/verb/dx_secret in F.verbs, "shown once power_level is set")
	F.set_power_level(0)
	refresh_flush()
	TEST_ASSERT(!(/obj/cap_fixture/dx_core/verb/dx_secret in F.verbs), "hidden again")

// ---------------------------------------------------------------- 8. ui_<action>

/datum/unit_test/dx_core_ui_actions/Run()
	var/datum/dx_ui_host/H = new
	var/datum/tgui/ui = ui_test_window(H)
	TEST_ASSERT(H.tgui_act("set_value", list("value" = "42"), ui), "act_set_value ran")
	TEST_ASSERT_EQUAL(H.value, 42, "named arg reached the proc and was validated")
	TEST_ASSERT(!H.tgui_act("set_value", list("value" = "lots"), ui), "a validator refusal is refused")
	TEST_ASSERT_EQUAL(H.value, 42, "unchanged after a refusal")
	var/fails = length(GLOB.dispatch_failures)
	GLOB.dispatch_failure_expected = TRUE
	var/result = H.tgui_act("set_value", list("value" = 3, "bogus" = 1), ui)
	GLOB.dispatch_failure_expected = FALSE
	TEST_ASSERT(!result, "an unknown argument name is refused")
	TEST_ASSERT_EQUAL(length(GLOB.dispatch_failures) - fails, 1, "and logged")
	H.allow = FALSE
	TEST_ASSERT(!H.tgui_act("set_value", list("value" = 7), ui), "ui_allowed FALSE refuses")
	TEST_ASSERT_EQUAL(H.value, 42, "the refused action did not run")
	H.allow = TRUE
	var/records = length(GLOB.dispatch_records)
	TEST_ASSERT(H.tgui_act("record", list(), ui), "act_record ran")
	TEST_ASSERT_EQUAL(H.logged_calls, 1, "once")
	TEST_ASSERT_EQUAL(GLOB.dispatch_records[length(GLOB.dispatch_records)], "record|0|1", "a ui_logged action is logged")
	TEST_ASSERT_EQUAL(length(GLOB.dispatch_records) - records, 1, "one record")
	qdel(ui)
	qdel(H)

	TEST_ASSERT_EQUAL(ui_number("12.6", 0, 10), 10, "ui_number clamps numeric text")
	TEST_ASSERT_EQUAL(ui_number(12.6, round_to = 1), 13, "ui_number rounds")
	TEST_ASSERT_NULL(ui_number("abc"), "ui_number refuses text")
	TEST_ASSERT_EQUAL(ui_text(5), "5", "ui_text renders a number")
	TEST_ASSERT_NULL(ui_text(list()), "ui_text refuses a list")
	TEST_ASSERT_EQUAL(ui_choice("b", list("a", "b")), "b", "ui_choice accepts a member")
	TEST_ASSERT_NULL(ui_choice("c", list("a", "b")), "ui_choice refuses a non-member")
	var/datum/dx_core_child/X = new
	var/datum/dx_core_child/Y = new
	TEST_ASSERT(ui_ref(REF(X), list(X)) == X, "ui_ref resolves a member")
	TEST_ASSERT_NULL(ui_ref(REF(Y), list(X)), "ui_ref refuses a non-member")
	TEST_ASSERT_NULL(ui_ref(REF(X), list(X), /datum/dx_ui_host), "ui_ref checks the type")
	qdel(X)
	qdel(Y)

// ---------------------------------------------------------------- 9. dispatch_call

/datum/unit_test/dx_core_dispatch_async/Run()
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human)
	var/obj/cap_fixture/dx_core/F = allocate(/obj/cap_fixture/dx_core, get_turf(user))
	refresh_flush()
	var/datum/dispatch_context/ctx = new(user, F)
	var/records = length(GLOB.dispatch_records)
	var/result = dispatch_call(ctx, F, TYPE_PROC_REF(/obj/cap_fixture/dx_core, dx_sleepy), list("user" = user), "sleepy", null)
	TEST_ASSERT_NULL(result, "a sleeping handler returns control")
	TEST_ASSERT(!F.slept_done, "it has not finished yet")
	TEST_ASSERT(GLOB.dispatch_context_now != ctx, "a sleeping handler's context does not leak")
	TEST_ASSERT_EQUAL(length(GLOB.dispatch_records), records, "nothing recorded before it finishes")
	var/waited = 0
	while(!F.slept_done && waited++ < 50)
		sleep(world.tick_lag)
	TEST_ASSERT(F.slept_done, "the handler finished")
	TEST_ASSERT_EQUAL(GLOB.dispatch_records[length(GLOB.dispatch_records)], "sleepy|1|0", "recorded with a fingerprint for a living user")
	TEST_ASSERT(F.refresh_queued || F.state_changes, "changed() ran after it finished")

// ---------------------------------------------------------------- 10. ask re-validation and forms

/datum/unit_test/dx_core_ask_context/Run()
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human)
	var/obj/cap_fixture/dx_core/F = allocate(/obj/cap_fixture/dx_core, get_turf(user))
	var/datum/dispatch_context/ctx = new(user, F)
	TEST_ASSERT(ask_still_valid(ctx), "valid while in reach")
	F.forceMove(run_loc_floor_top_right)
	user.forceMove(run_loc_floor_bottom_left)
	TEST_ASSERT(!ask_still_valid(ctx), "invalid once the user is far away")
	F.forceMove(get_turf(user))
	qdel(F)
	TEST_ASSERT(!ask_still_valid(ctx), "invalid once the target is deleted")

/datum/unit_test/dx_core_form/Run()
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human)
	var/obj/cap_fixture/dx_core/F = allocate(/obj/cap_fixture/dx_core, get_turf(user))
	var/datum/interaction/capability/entry
	for(var/datum/interaction/capability/E as anything in cap_interactions(F))
		if(E.name == "Configure")
			entry = E
	TEST_ASSERT_NOTNULL(entry, "the form entry exists")
	var/datum/dispatch_context/ctx = new(user, F, null, entry)
	cap_dispatch(ctx)
	TEST_ASSERT_NOTNULL(F.form_answers, "the handler ran")
	TEST_ASSERT_EQUAL(F.form_answers["mode"], "fast", "the choice answer arrived by name")
	TEST_ASSERT_EQUAL(F.form_answers["count"], 3, "the number answer arrived by name")

// ---------------------------------------------------------------- 11. timed_set

/datum/unit_test/om/dx_core_timed_set

/datum/unit_test/om/dx_core_timed_set/run_om(list/made)
	var/obj/cap_fixture/dx_core/F = new
	made += F
	refresh_flush()
	TEST_ASSERT(timed_set(F, nameof(F.power_level), 7, for_time = 2 SECONDS), "timed_set ran")
	TEST_ASSERT_EQUAL(F.power_level, 7, "written through the setter")
	TEST_ASSERT(F.refresh_queued, "the setter marked it changed")
	TEST_ASSERT(time_left(F, nameof(F.power_level)) > 1 SECONDS, "time_left on the own clock")
	scheduler_advance(1)
	TEST_ASSERT_EQUAL(F.power_level, 7, "not reverted early")
	TEST_ASSERT(!timed_set(F, nameof(F.power_level), 9, for_time = 0.5 SECONDS, keep_longer = TRUE), "keep_longer keeps the later end")
	TEST_ASSERT_EQUAL(F.power_level, 7, "and does not write")
	scheduler_advance(1.5)
	TEST_ASSERT_EQUAL(F.power_level, 0, "reverted through the setter")
	TEST_ASSERT_EQUAL(time_left(F, nameof(F.power_level)), 0, "nothing pending after the revert")

	timed_set(F, nameof(F.power_level), 4, for_time = 1 SECONDS)
	timed_set(F, nameof(F.power_level), 6, for_time = 3 SECONDS)
	scheduler_advance(1.5)
	TEST_ASSERT_EQUAL(F.power_level, 6, "a replaced timer does not fire")
	scheduler_advance(2)
	TEST_ASSERT_EQUAL(F.power_level, 0, "the replacement reverts to the original prior value")

	timed_set(F, nameof(F.power_level), 5, for_time = 1 SECONDS, clock = CLOCK_WORLD)
	TEST_ASSERT(time_left(F, nameof(F.power_level)) > 0, "time_left on the world clock")
	scheduler_advance(1.5)
	TEST_ASSERT_EQUAL(F.power_level, 0, "the world clock reverts")

	timed_set(F, nameof(F.power_level), 2, for_time = 1 SECONDS)
	timed_cancel(F, nameof(F.power_level))
	scheduler_advance(1.5)
	TEST_ASSERT_EQUAL(F.power_level, 2, "timed_cancel keeps the current value")

	timed_set(F, nameof(F.power_level), 8, for_time = 1 SECONDS)
	TEST_ASSERT(om_timer_slot_pending(F, "timed:[nameof(F.power_level)]"), "the owned slot is pending")
	qdel(F)
	TEST_ASSERT(!om_timer_slot_pending(F, "timed:[nameof(F.power_level)]"), "teardown drops the timer")
