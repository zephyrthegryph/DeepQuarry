// The DX framework core (code/datums/capabilities/): the capability list, TRACKED, changed() and the
// refresh engine, the look builder, drift, periodic gating, hidden verbs, ui_<action> dispatch,
// dispatch_call(), ask_* re-validation, timed_set().

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

/datum/dx_core_child
	var/level = 0

TRACKED_BRIDGED(/datum/dx_core_child, level, CHANGE_DATUM_A)

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

/obj/cap_fixture/dx_core/ownership()
	. = ..()
	. += owns(nameof(child), policy = OWN_DELETE)

TRACKED_BRIDGED(/obj/cap_fixture/dx_core, power_level, CHANGE_DATUM_A)

/obj/cap_fixture/dx_core/declared_capabilities(list/into)
	..()
	into += dx_test_cap(/datum/capability/dx_test/a, "alpha")
	into += dx_test_cap(/datum/capability/dx_test/b, "beta")

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

/obj/cap_fixture/dx_core/proc/dx_sleepy(mob/user)
	sleep(1)
	slept_done = TRUE
	return TRUE

/obj/cap_fixture/dx_core/child/declared_capabilities(list/into)
	..()
	var/list/kept = without(into, /datum/capability/dx_test/a)
	into.Cut()
	into += kept
	into += dx_test_cap(/datum/capability/dx_test/c, "gamma")

/// A capability that draws the holder's child (H2: the owner is marked for that child's changes).
/datum/capability/dx_test/draws_child

/obj/cap_fixture/dx_core/drawer/declared_capabilities(list/into)
	..()
	var/datum/capability/dx_test/draws_child/C = dx_test_cap(/datum/capability/dx_test/draws_child, "drawer")
	C.draws_var = nameof(/obj/cap_fixture/dx_core::child)
	into += C

/// Inherits the child's capabilities: a third type building the same entries.
/obj/cap_fixture/dx_core/child/grand

/// Base properties and image overlays through the look builder.
/obj/cap_fixture/dx_look
	icon_state = "look_default"
	var/tinted = FALSE
	var/stated = TRUE
	var/mark_state = "mark_a"
	var/explode = FALSE

/obj/cap_fixture/dx_look/draw(datum/look/look)
	..()
	if(explode)
		CRASH("dx_look: deliberate draw failure")
	if(stated)
		look.state("look_on")
	if(tinted)
		look.set_color("#ff0000")
	look.overlay(mutable_appearance(icon, mark_state))

/// Draws nothing, hides nothing, has no capabilities.
/obj/cap_fixture/dx_plain
	icon_state = "keepme"

/obj/cap_fixture/dx_periodic
	periodic_cadence = PERIODIC_SLOW
	var/gating = FALSE

TRACKED_BRIDGED(/obj/cap_fixture/dx_periodic, gating, CHANGE_DATUM_A)

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
	return TRUE

/datum/dx_ui_host/proc/act_record(mob/user)
	logged_calls++
	return TRUE

// ---------------------------------------------------------------- 1. the capability list

/datum/unit_test/dx_core_capabilities_list/Run()
	var/obj/cap_fixture/dx_core/A = allocate(/obj/cap_fixture/dx_core)
	var/obj/cap_fixture/dx_core/B = allocate(/obj/cap_fixture/dx_core)
	var/obj/cap_fixture/dx_core/child/C = allocate(/obj/cap_fixture/dx_core/child)
	var/list/caps = caps_of(A)
	TEST_ASSERT_EQUAL(length(caps), 2, "two capabilities")
	TEST_ASSERT(istype(caps[1], /datum/capability/dx_test/a) && istype(caps[2], /datum/capability/dx_test/b), "declaration order kept")
	TEST_ASSERT(caps_of(B) == caps, "caps_of is cached and shared per type")
	TEST_ASSERT(caps_of(A) == caps, "caps_of returns the same list again")
	var/list/child_caps = caps_of(C)
	TEST_ASSERT_NULL(cap_of(C, /datum/capability/dx_test/a), "without() dropped the parent's entry by type")
	TEST_ASSERT(istype(child_caps[1], /datum/capability/dx_test/b) && istype(child_caps[2], /datum/capability/dx_test/c), "without() keeps the order, . += appends")
	TEST_ASSERT_EQUAL(jointext(caps_examine(A, null), ","), "alpha,beta", "examine follows list order")
	TEST_ASSERT_EQUAL(jointext(caps_examine(C, null), ","), "beta,gamma", "the child's examine follows its list")

// ---------------------------------------------------------------- 2/3. TRACKED, changed(), refresh

/datum/unit_test/dx_core_tracked_and_changed/Run()
	var/obj/cap_fixture/dx_core/F = allocate(/obj/cap_fixture/dx_core)
	refresh_flush()
	var/before = F.state_changes
	TEST_ASSERT(F.set_power_level(3), "set_ returns TRUE on a change")
	TEST_ASSERT(F.refresh_queued, "a change queues the refresh")
	TEST_ASSERT(F.refresh_bits & CHANGE_DATUM_A, "refresh_bits carries the channel")
	TEST_ASSERT(!F.set_power_level(3), "set_ returns FALSE with no change")
	var/queued = 0
	for(var/datum/D as anything in GLOB.refresh_queue)
		if(D == F)
			queued++
	TEST_ASSERT_EQUAL(queued, 1, "queued once per frame")
	changed(F, CHANGE_DATUM_B)
	refresh_flush()
	TEST_ASSERT_EQUAL(F.state_changes - before, 1, "on_state_changed ran once for the frame")
	TEST_ASSERT(F.last_bits & CHANGE_DATUM_A, "on_state_changed got the TRACKED channel")
	TEST_ASSERT(F.last_bits & CHANGE_DATUM_B, "on_state_changed got the explicit channel")
	TEST_ASSERT_EQUAL(F.refresh_bits, 0, "bits are cleared after the refresh")
	TEST_ASSERT_EQUAL(F.icon_state, "on", "draw ran")

/// H2: a child's change marks its owner only when one of the owner's capabilities draws that child.
/datum/unit_test/dx_core_changed_owner_chain/Run()
	var/obj/cap_fixture/dx_core/F = allocate(/obj/cap_fixture/dx_core)
	var/datum/dx_core_child/K = new
	rel_set(F, nameof(/obj/cap_fixture/dx_core::child), K)
	refresh_flush()
	TEST_ASSERT(owner_of(K) == F, "the child is owned")
	TEST_ASSERT(K.set_level(2), "the child's setter changed it")
	TEST_ASSERT(K.refresh_queued, "the child itself is queued")
	TEST_ASSERT(!F.refresh_queued, "an owner that doesn't draw the child is not marked")
	refresh_flush()

	var/obj/cap_fixture/dx_core/drawer/D = allocate(/obj/cap_fixture/dx_core/drawer)
	var/datum/dx_core_child/DK = new
	rel_set(D, nameof(/obj/cap_fixture/dx_core::child), DK)
	refresh_flush()
	var/before = D.state_changes
	TEST_ASSERT(DK.set_level(4), "the drawn child's setter changed it")
	TEST_ASSERT(D.refresh_queued, "an owner whose capability draws the child is queued with it")
	TEST_ASSERT(D.refresh_bits & CHANGE_DATUM_A, "the owner carries the child's channel")
	refresh_flush()
	TEST_ASSERT_EQUAL(D.state_changes - before, 1, "the owner refreshed once")

// ---------------------------------------------------------------- 4. look builder

/datum/unit_test/dx_core_look/Run()
	var/obj/cap_fixture/dx_core/F = allocate(/obj/cap_fixture/dx_core)
	F.set_power_level(5)
	refresh_flush()
	TEST_ASSERT_EQUAL(F.icon_state, "on", "state applied")
	TEST_ASSERT(findtext(F.rx?.look_key, "charge2"), "gauge quantised 0.5 of 4 to step 2: [F.rx?.look_key]")
	TEST_ASSERT(!findtext(F.rx?.look_key, "light"), "glow off while its condition is false")
	TEST_ASSERT(!findtext(F.rx?.look_key, "alpha_layer"), "a capability overlay off while its condition is false")
	cap_set(F, CAP_PANEL_OPEN, TRUE)
	F.set_power_level(8)
	refresh_flush()
	TEST_ASSERT(findtext(F.rx?.look_key, "light"), "glow on: [F.rx?.look_key]")
	TEST_ASSERT(findtext(F.rx?.look_key, "alpha_layer,beta_layer"), "capability overlays in list order: [F.rx?.look_key]")
	TEST_ASSERT(findtext(F.rx?.look_key, "charge3"), "gauge moved to step 3")
	var/key = F.rx?.look_key
	var/list/applied = F.rx?.look_overlays
	changed(F)
	refresh_flush()
	TEST_ASSERT_EQUAL(F.rx?.look_key, key, "an identical look keeps its key")
	TEST_ASSERT(F.rx?.look_overlays == applied, "an identical look churns no overlays")

	var/obj/cap_fixture/dx_plain/P = allocate(/obj/cap_fixture/dx_plain)
	changed(P)
	refresh_flush()
	TEST_ASSERT_EQUAL(P.icon_state, "keepme", "a type that draws nothing keeps its icon_state")
	TEST_ASSERT_NULL(P.rx?.look_key, "and has no look key")
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
	set_global("refresh_drift_expected", TRUE)
	var/found = refresh_check_drift(F)
	set_global("refresh_drift_expected", FALSE)
	TEST_ASSERT(found, "the sweep check found the unmarked write")
	TEST_ASSERT_EQUAL(length(GLOB.refresh_drift) - before, 1, "one REFRESH DRIFT report")
	TEST_ASSERT(findtext(GLOB.refresh_drift[length(GLOB.refresh_drift)], "REFRESH DRIFT"), "the report names the drift")
	TEST_ASSERT(findtext(F.rx?.look_key, "drift"), "the drift was corrected")
	TEST_ASSERT(!refresh_check_drift(F), "and is gone after the correction")
	set_global("refresh_drift_expected", TRUE)
	refresh_sweep_step(length(GLOB.refresh_sweep_list))
	set_global("refresh_drift_expected", FALSE)

// ---------------------------------------------------------------- 6. periodic gating

/datum/unit_test/dx_core_periodic_gate/Run()
	var/obj/cap_fixture/dx_periodic/F = allocate(/obj/cap_fixture/dx_periodic)
	refresh_flush()
	TEST_ASSERT(!(!isnull(F.periodic_pipe)), "not running while should_run() is FALSE")
	F.set_gating(TRUE)
	refresh_flush()
	TEST_ASSERT((!isnull(F.periodic_pipe)), "running once should_run() is TRUE")
	F.set_gating(FALSE)
	refresh_flush()
	TEST_ASSERT(!(!isnull(F.periodic_pipe)), "stopped once should_run() is FALSE again")

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
	set_global("dispatch_failure_expected", TRUE)
	var/result = H.tgui_act("set_value", list("value" = 3, "bogus" = 1), ui)
	set_global("dispatch_failure_expected", FALSE)
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

// ---------------------------------------------------------------- 11. timed_set

/datum/unit_test/om/dx_core_timed_set

/datum/unit_test/om/dx_core_timed_set/run_om(list/made)
	var/obj/cap_fixture/dx_core/F = new
	made += F
	refresh_flush()
	TEST_ASSERT(timed_set(F, nameof(F.power_level), 7, for_time = 2 SECONDS, clock = CLOCK_OWN), "timed_set ran")
	TEST_ASSERT_EQUAL(F.power_level, 7, "written through the setter")
	TEST_ASSERT(F.refresh_queued, "the setter marked it changed")
	TEST_ASSERT(time_left(F, nameof(F.power_level)) > 1 SECONDS, "time_left on the own clock")
	scheduler_advance(1)
	TEST_ASSERT_EQUAL(F.power_level, 7, "not reverted early")
	TEST_ASSERT(!timed_set(F, nameof(F.power_level), 9, for_time = 0.5 SECONDS, clock = CLOCK_OWN, keep_longer = TRUE), "keep_longer keeps the later end")
	TEST_ASSERT_EQUAL(F.power_level, 7, "and does not write")
	scheduler_advance(1.5)
	TEST_ASSERT_EQUAL(F.power_level, 0, "reverted through the setter")
	TEST_ASSERT_EQUAL(time_left(F, nameof(F.power_level)), 0, "nothing pending after the revert")

	timed_set(F, nameof(F.power_level), 4, for_time = 1 SECONDS, clock = CLOCK_OWN)
	timed_set(F, nameof(F.power_level), 6, for_time = 3 SECONDS, clock = CLOCK_OWN)
	scheduler_advance(1.5)
	TEST_ASSERT_EQUAL(F.power_level, 6, "a replaced timer does not fire")
	scheduler_advance(2)
	TEST_ASSERT_EQUAL(F.power_level, 0, "the replacement reverts to the original prior value")

	timed_set(F, nameof(F.power_level), 5, for_time = 1 SECONDS, clock = CLOCK_WORLD)
	TEST_ASSERT(time_left(F, nameof(F.power_level)) > 0, "time_left on the world clock")
	scheduler_advance(1.5)
	TEST_ASSERT_EQUAL(F.power_level, 0, "the world clock reverts")

	timed_set(F, nameof(F.power_level), 2, for_time = 1 SECONDS, clock = CLOCK_OWN)
	timed_cancel(F, nameof(F.power_level))
	scheduler_advance(1.5)
	TEST_ASSERT_EQUAL(F.power_level, 2, "timed_cancel keeps the current value")

	timed_set(F, nameof(F.power_level), 8, for_time = 1 SECONDS, clock = CLOCK_OWN)
	TEST_ASSERT(after_pending(F, "timed:[nameof(F.power_level)]"), "the owned slot is pending")
	qdel(F)
	TEST_ASSERT(!after_pending(F, "timed:[nameof(F.power_level)]"), "teardown drops the timer")

// ---------------------------------------------------------------- review-2 follow-ups

/// An image overlay keys by what it shows, so a changed image is applied; base properties a look
/// stops setting go back to the type default.
/datum/unit_test/dx_core_look_images_and_takeback/Run()
	var/obj/cap_fixture/dx_look/F = allocate(/obj/cap_fixture/dx_look)
	refresh_flush()
	var/key = F.rx?.look_key
	TEST_ASSERT(findtext(key, "mark_a"), "an image overlay keys by its icon_state: [key]")
	F.mark_state = "mark_b"
	changed(F)
	refresh_flush()
	TEST_ASSERT(F.rx?.look_key != key, "a different image changes the key")
	TEST_ASSERT(findtext(F.rx?.look_key, "mark_b"), "the new image is applied: [F.rx?.look_key]")
	var/list/applied = F.rx?.look_overlays
	changed(F)
	refresh_flush()
	TEST_ASSERT(F.rx?.look_overlays == applied, "an equal image (a fresh mutable_appearance) churns no overlays")

	F.tinted = TRUE
	changed(F)
	refresh_flush()
	TEST_ASSERT_EQUAL(F.color, "#ff0000", "set_color applied")
	F.tinted = FALSE
	changed(F)
	refresh_flush()
	TEST_ASSERT_EQUAL(F.color, initial(F.color), "a colour the look stopped setting goes back to the default")
	TEST_ASSERT_EQUAL(F.icon_state, "look_on", "state still applied")
	F.stated = FALSE
	changed(F)
	refresh_flush()
	TEST_ASSERT_EQUAL(F.icon_state, "look_default", "a state the look stopped setting goes back to the default")

/// A draw() that throws leaves no stale refresh_running behind (it would flag every later mark as a
/// self-mark), and the refresh after it works.
/datum/unit_test/dx_core_refresh_throw_restores/Run()
	var/obj/cap_fixture/dx_look/F = allocate(/obj/cap_fixture/dx_look)
	refresh_flush()
	F.explode = TRUE
	var/caught = FALSE
	try
		refresh_one(F, 0)
	catch(var/exception/e)
		caught = !!e
	TEST_ASSERT(caught, "the draw failure propagated")
	TEST_ASSERT(GLOB.refresh_running != F, "refresh_running was restored after the failure")
	F.explode = FALSE
	changed(F) // would stack_trace REFRESH SELF-MARK with a stale refresh_running
	refresh_flush()
	TEST_ASSERT(!F.refresh_queued, "the next refresh ran")

/// M5: a var written through its setter while a timed revert is pending keeps the newer value.
/datum/unit_test/om/dx_core_timed_newer_write_wins

/datum/unit_test/om/dx_core_timed_newer_write_wins/run_om(list/made)
	var/obj/cap_fixture/dx_core/F = new
	made += F
	timed_set(F, nameof(F.power_level), 7, for_time = 1 SECONDS)
	F.set_power_level(3)
	scheduler_advance(1.5)
	TEST_ASSERT_EQUAL(F.power_level, 3, "the revert did not clobber a newer write")
	TEST_ASSERT_EQUAL(time_left(F, nameof(F.power_level)), 0, "nothing pending")

/// M7: one open prompt per user per action.
/datum/unit_test/dx_core_ask_one_open/Run()
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human)
	var/obj/cap_fixture/dx_core/F = allocate(/obj/cap_fixture/dx_core, get_turf(user))
	var/datum/dispatch_context/ctx = new(user, F)
	TEST_ASSERT(ask_open(ctx), "the first prompt opens")
	TEST_ASSERT(!ask_open(new /datum/dispatch_context(user, F)), "a second prompt for the same action is refused")
	ask_close(ctx)
	TEST_ASSERT(ask_open(ctx), "it opens again once closed")
	ask_close(ctx)

/// A tgui window on `host` for a test, interactive, with no client behind it.
/proc/ui_test_window(datum/host)
	var/datum/tgui/ui = new(null, host, "UiTest")
	ui.status = STATUS_INTERACTIVE
	return ui
