// Delivery pins for the notices that replaced the om events of code/datums/om_events (signal_events.dm, atom_events.dm),
// written before those declarations were deleted. A representative set: plain sync events (atom_dir_change, atom_entered,
// atom_exited, trait_gained), the atom events (examine, hitby) and a former before/ accumulate event (in_range_of_irradiation).
// Pinned: a publish is delivered before PUBLISH_LEGACY returns, the type's own on_notice() reactions hear it before an
// observe() hook does, two publishes of one type are both delivered (never coalesced), a handler that appends to a payload
// list has appended when the sender reads it back, and a notice published from inside a delivery is delivered after the
// current one finishes and before the outermost publish returns (reactions.md section 3).

// ---------------------------------------------------------------- fixtures

/datum/om_notice_fx
	var/list/log = list()
	/// atom_entered handlers publish atom_exited from inside the delivery.
	var/republish = FALSE
	/// atom_dir_change handlers publish a read-back examine (and a plain atom_exited) from inside the delivery and read the lines back.
	var/ask_examine = FALSE
	/// examine handlers publish another examine from inside the answer.
	var/recurse_examine = FALSE

/datum/om_notice_fx/reactions()
	. = ..()
	. += on_notice(/datum/notice/atom_dir_change, PROC_REF(on_dir))
	. += on_notice(/datum/notice/atom_entered, PROC_REF(on_entered))
	. += on_notice(/datum/notice/atom_exited, PROC_REF(on_exited))
	. += on_notice(/datum/notice/trait_gained, PROC_REF(on_trait))
	. += on_notice(/datum/notice/examine, PROC_REF(on_examine_lines))
	. += on_notice(/datum/notice/hitby, PROC_REF(on_hitby))
	. += on_notice(/datum/notice/in_range_of_irradiation, PROC_REF(on_irradiation))

/datum/om_notice_fx/proc/on_dir(datum/notice/atom_dir_change/N)
	log += "dir:[N.old_dir]>[N.new_dir]"
	if(ask_examine)
		var/list/texts = list("base")
		PUBLISH_LEGACY(src, /datum/notice/atom_exited, "plain", "nested")
		PUBLISH_LEGACY(src, /datum/notice/examine, "inner", texts)
		log += "read:[jointext(texts, "|")]"

/datum/om_notice_fx/proc/on_entered(datum/notice/atom_entered/N)
	log += "entered:[N.arrived]<[N.old_loc]"
	if(republish)
		PUBLISH_LEGACY(src, /datum/notice/atom_exited, N.arrived, "nested")
		log += "entered:done"

/datum/om_notice_fx/proc/on_exited(datum/notice/atom_exited/N)
	log += "exited:[N.gone]>[N.new_loc]"

/datum/om_notice_fx/proc/on_trait(datum/notice/trait_gained/N)
	log += "trait:[N.trait]"

/datum/om_notice_fx/proc/on_examine_lines(datum/notice/examine/N)
	log += "examine:[N.user]"
	N.texts += "line from [N.user]"
	if(recurse_examine)
		PUBLISH_LEGACY(src, /datum/notice/examine, "deeper", N.texts)

/datum/om_notice_fx/proc/on_hitby(datum/notice/hitby/N)
	log += "hitby:[N.source_]:[N.throwingdatum]"

/datum/om_notice_fx/proc/on_irradiation(datum/notice/in_range_of_irradiation/N)
	log += "rad:[N.pulse_information]:[N.insulation_to_target]"

/// Hears atom_entered through observe(), the hook form the converted listeners use.
/datum/om_notice_fx_listener
	var/datum/om_notice_fx/into

/datum/om_notice_fx_listener/proc/heard_entered(datum/act/notice/A)
	var/datum/notice/atom_entered/N = A
	into.log += "hook entered:[N.arrived]"

// ---------------------------------------------------------------- tests

/// Each representative notice is delivered at once, with its payload in fill() order.
/datum/unit_test/dq_om_notice_delivery_sync/Run()
	var/datum/om_notice_fx/F = allocate(/datum/om_notice_fx)
	PUBLISH_LEGACY(F, /datum/notice/atom_dir_change, NORTH, SOUTH)
	TEST_ASSERT_EQUAL(jointext(F.log, ","), "dir:[NORTH]>[SOUTH]", "delivered before PUBLISH_LEGACY returned")
	PUBLISH_LEGACY(F, /datum/notice/trait_gained, "fx_trait")
	PUBLISH_LEGACY(F, /datum/notice/hitby, "rock", "throw")
	PUBLISH_LEGACY(F, /datum/notice/in_range_of_irradiation, "pulse", 0.5)
	TEST_ASSERT_EQUAL(jointext(F.log, ","), "dir:[NORTH]>[SOUTH],trait:fx_trait,hitby:rock:throw,rad:pulse:0.5", "each delivered at once, fields in fill() order")
	var/list/texts = list("base")
	PUBLISH_LEGACY(F, /datum/notice/examine, "viewer", texts)
	TEST_ASSERT_EQUAL(jointext(texts, "|"), "base|line from viewer", "an examine handler has appended its line when the sender reads the list back")

/// Occurrences are never coalesced: back-to-back publishes of one type are all delivered, in publish order.
/datum/unit_test/dq_om_notice_delivery_not_coalesced/Run()
	var/datum/om_notice_fx/F = allocate(/datum/om_notice_fx)
	PUBLISH_LEGACY(F, /datum/notice/atom_dir_change, NORTH, EAST)
	PUBLISH_LEGACY(F, /datum/notice/atom_dir_change, EAST, NORTH)
	PUBLISH_LEGACY(F, /datum/notice/atom_dir_change, NORTH, EAST)
	TEST_ASSERT_EQUAL(jointext(F.log, ","), "dir:[NORTH]>[EAST],dir:[EAST]>[NORTH],dir:[NORTH]>[EAST]", "three changes that end where the first did: all three delivered")

/// The type's own reactions hear a notice before an observe() hook does; a notice published from a handler is
/// delivered after the current delivery (hooks included) and before the outermost publish returns.
/datum/unit_test/dq_om_notice_delivery_order/Run()
	var/datum/om_notice_fx/F = allocate(/datum/om_notice_fx)
	var/datum/om_notice_fx_listener/L = allocate(/datum/om_notice_fx_listener)
	L.into = F
	TEST_ASSERT(observe(F, /datum/notice/atom_entered, L, then(TYPE_PROC_REF(/datum/om_notice_fx_listener, heard_entered))), "observed")
	PUBLISH_LEGACY(F, /datum/notice/atom_entered, "crate", "hall")
	TEST_ASSERT_EQUAL(jointext(F.log, ","), "entered:crate<hall,hook entered:crate", "static reaction first, then the hook, both before the publish returned")
	F.log.Cut()
	F.republish = TRUE
	PUBLISH_LEGACY(F, /datum/notice/atom_entered, "crate", "hall")
	TEST_ASSERT_EQUAL(jointext(F.log, ","), "entered:crate<hall,entered:done,hook entered:crate,exited:crate>nested", "the nested publish waits for the current delivery, then is delivered before the outer publish returns")
	TEST_ASSERT_EQUAL(unobserve(F, /datum/notice/atom_entered, L), 1, "unobserve removed the hook")
	F.log.Cut()
	F.republish = FALSE
	PUBLISH_LEGACY(F, /datum/notice/atom_entered, "crate", "hall")
	TEST_ASSERT_EQUAL(jointext(F.log, ","), "entered:crate<hall", "and the hook hears nothing more")

/// A read-back notice published from inside another delivery is answered at once: the handler that published it reads the lines
/// back on its next line. A plain notice published from the same handler still waits for the current delivery (reactions.md section 3).
/datum/unit_test/dq_om_notice_delivery_read_back_nested/Run()
	var/datum/om_notice_fx/F = allocate(/datum/om_notice_fx)
	F.ask_examine = TRUE
	PUBLISH_LEGACY(F, /datum/notice/atom_dir_change, NORTH, SOUTH)
	TEST_ASSERT_EQUAL(jointext(F.log, ","), "dir:[NORTH]>[SOUTH],examine:inner,read:base|line from inner,exited:plain>nested", "the nested examine was answered before its sender read the list; the plain notice still queued behind the delivery")
	for(var/read_back_type in list(/datum/notice/examine, /datum/notice/living_shield_injury, /datum/notice/robot_belly_fullness, /datum/notice/turf_change))
		var/datum/notice/proto = read_back_type
		TEST_ASSERT(initial(proto.read_back), "[read_back_type] is read back by its sender, so it is declared read_back")

/// Two examine handlers, the first of which throws; a dir change asks for an examine from inside a delivery.
/datum/om_notice_fault_fx
	var/answered

/datum/om_notice_fault_fx/reactions()
	. = ..()
	. += on_notice(/datum/notice/examine, PROC_REF(faulting))
	. += on_notice(/datum/notice/examine, PROC_REF(healthy))
	. += on_notice(/datum/notice/atom_dir_change, PROC_REF(ask))

/datum/om_notice_fault_fx/proc/faulting(datum/notice/examine/N)
	N.texts += "first"
	throw EXCEPTION("expected examine handler fault")

/datum/om_notice_fault_fx/proc/healthy(datum/notice/examine/N)
	N.texts += "second"

/datum/om_notice_fault_fx/proc/ask(datum/notice/atom_dir_change/N)
	var/list/texts = list()
	PUBLISH_LEGACY(src, /datum/notice/examine, "inner", texts)
	answered = jointext(texts, "|")

/// A notice that faults past its handlers, where nothing in the delivery catches it.
/datum/notice/om_fx_release_fault

/datum/notice/om_fx_release_fault/release()
	throw EXCEPTION("expected release fault")

/// Clears what a broken delivery left behind so one failure cannot wedge every later test, and returns what it found.
/proc/om_notice_fx_state_left()
	. = "delivering=[GLOB.rx_notice_delivering],depth=[GLOB.rx_answer_depth],queued=[length(GLOB.rx_notice_queue)]"
	GLOB.rx_notice_delivering = FALSE
	GLOB.rx_answer_depth = 0
	GLOB.rx_notice_queue.Cut()

/// A throwing examine handler costs its own line only: the next handler still answers, at the top level and nested, and delivery is not left wedged.
/datum/unit_test/dq_om_notice_delivery_handler_fault/Run()
	var/datum/om_notice_fault_fx/F = allocate(/datum/om_notice_fault_fx)
	GLOB.dq_caught_capture = list()
	var/list/texts = list()
	var/escaped = null
	try
		PUBLISH_LEGACY(F, /datum/notice/examine, "viewer", texts)
		PUBLISH_LEGACY(F, /datum/notice/atom_dir_change, NORTH, SOUTH)
	catch(var/exception/e)
		escaped = e.name
	var/list/reported = GLOB.dq_caught_capture
	GLOB.dq_caught_capture = null
	var/left = om_notice_fx_state_left()
	TEST_ASSERT_NULL(escaped, "a handler fault stays inside the delivery")
	TEST_ASSERT_EQUAL(left, "delivering=0,depth=0,queued=0", "a handler fault leaves delivery idle")
	TEST_ASSERT_EQUAL(jointext(texts, "|"), "first|second", "the handler after the fault still wrote its line (top level)")
	TEST_ASSERT_EQUAL(F.answered, "first|second", "the handler after the fault still wrote its line (nested)")
	TEST_ASSERT_EQUAL(length(reported), 2, "each fault is reported")

/// A fault outside any handler's try cannot strand the delivering flag: if it did, every later notice in the world would queue forever.
/datum/unit_test/dq_om_notice_delivery_fault_not_wedged/Run()
	var/datum/om_notice_fx/F = allocate(/datum/om_notice_fx)
	GLOB.dq_caught_capture = list()
	var/escaped = null
	try
		publish(F, take_notice(/datum/notice/om_fx_release_fault))
	catch(var/exception/e)
		escaped = e.name
	GLOB.dq_caught_capture = null
	var/left = om_notice_fx_state_left()
	TEST_ASSERT_NULL(escaped, "the fault stays inside publish()")
	TEST_ASSERT_EQUAL(left, "delivering=0,depth=0,queued=0", "the fault leaves delivery idle")
	PUBLISH_LEGACY(F, /datum/notice/trait_gained, "after")
	TEST_ASSERT_EQUAL(jointext(F.log, ","), "trait:after", "the next notice is delivered at once")

/// An examine handler that examines again is cut at RX_ANSWER_DEPTH with one report; every answer that ran keeps its line and the sender keeps going.
/datum/unit_test/dq_om_notice_delivery_examine_recursion/Run()
	var/datum/om_notice_fx/F = allocate(/datum/om_notice_fx)
	F.recurse_examine = TRUE
	GLOB.dq_caught_capture = list()
	var/list/texts = list()
	var/escaped = null
	try
		PUBLISH_LEGACY(F, /datum/notice/examine, "viewer", texts)
	catch(var/exception/e)
		escaped = e.name
	var/list/reported = GLOB.dq_caught_capture
	GLOB.dq_caught_capture = null
	var/left = om_notice_fx_state_left()
	TEST_ASSERT_NULL(escaped, "the cut stays inside publish()")
	TEST_ASSERT_EQUAL(left, "delivering=0,depth=0,queued=0", "the cut leaves delivery idle")
	TEST_ASSERT_EQUAL(length(texts), RX_ANSWER_DEPTH + 1, "the outer delivery and every answer wrote its line")
	TEST_ASSERT_EQUAL(length(reported), 1, "the cut is reported once")
