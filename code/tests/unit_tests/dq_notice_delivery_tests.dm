// Delivery pins for PUBLISH_LEGACY, the delivery of the notices that replaced the old events of code/engine/events (signal_events.dm,
// atom_events.dm), written before those declarations were deleted. The notices below are fixtures that stand in for the real ones
// (atom_dir_change, atom_entered, atom_exited, examine, hitby, in_range_of_irradiation, trait_gained): those are ACTION() notices now, published with
// PUBLISH() and delivered synchronously (dq_publish_notice_tests.dm), and the fixtures keep the legacy queue, read-back and fault rules
// pinned for as long as PUBLISH_LEGACY has a caller.
// Pinned: a publish is delivered before PUBLISH_LEGACY returns, the type's own on_notice() reactions hear it before an
// observe() hook does, two publishes of one type are both delivered (never coalesced), a handler that appends to a payload
// list has appended when the sender reads it back, and a notice published from inside a delivery is delivered after the
// current one finishes and before the outermost publish returns (reactions.md section 3).

// ---------------------------------------------------------------- fixture notices

/datum/notice/fx_dir_change
	var/old_dir
	var/new_dir

/datum/notice/fx_dir_change/fill(old_dir, new_dir)
	src.old_dir = old_dir
	src.new_dir = new_dir

/datum/notice/fx_entered
	var/arrived
	var/old_loc

/datum/notice/fx_entered/fill(arrived, old_loc)
	src.arrived = arrived
	src.old_loc = old_loc

/datum/notice/fx_exited
	var/gone
	var/new_loc

/datum/notice/fx_exited/fill(gone, new_loc)
	src.gone = gone
	src.new_loc = new_loc

/datum/notice/fx_examine
	read_back = TRUE // the sender reads what the handlers wrote: answered at once, even mid-delivery (reactions.md section 3)
	var/user
	var/texts

/datum/notice/fx_examine/fill(user, texts)
	src.user = user
	src.texts = texts

/datum/notice/fx_trait
	var/trait

/datum/notice/fx_trait/fill(trait)
	src.trait = trait

/datum/notice/fx_hitby
	var/source_
	var/throwingdatum

/datum/notice/fx_hitby/fill(source_, throwingdatum)
	src.source_ = source_
	src.throwingdatum = throwingdatum

/datum/notice/fx_irradiation
	var/pulse_information
	var/insulation_to_target

/datum/notice/fx_irradiation/fill(pulse_information, insulation_to_target)
	src.pulse_information = pulse_information
	src.insulation_to_target = insulation_to_target

// ---------------------------------------------------------------- fixtures

/datum/notice_fx
	var/list/log = list()
	/// atom_entered handlers publish atom_exited from inside the delivery.
	var/republish = FALSE
	/// atom_dir_change handlers publish a read-back examine (and a plain atom_exited) from inside the delivery and read the lines back.
	var/ask_examine = FALSE
	/// examine handlers publish another examine from inside the answer.
	var/recurse_examine = FALSE

/datum/notice_fx/reactions()
	. = ..()
	. += on_notice(/datum/notice/fx_dir_change, PROC_REF(on_dir))
	. += on_notice(/datum/notice/fx_entered, PROC_REF(on_entered))
	. += on_notice(/datum/notice/fx_exited, PROC_REF(on_exited))
	. += on_notice(/datum/notice/fx_trait, PROC_REF(on_trait))
	. += on_notice(/datum/notice/fx_examine, PROC_REF(on_examine_lines))
	. += on_notice(/datum/notice/fx_hitby, PROC_REF(on_hitby))
	. += on_notice(/datum/notice/fx_irradiation, PROC_REF(on_irradiation))

/datum/notice_fx/proc/on_dir(datum/notice/fx_dir_change/N)
	log += "dir:[N.old_dir]>[N.new_dir]"
	if(ask_examine)
		var/list/texts = list("base")
		PUBLISH_LEGACY(src, /datum/notice/fx_exited, "plain", "nested")
		PUBLISH_LEGACY(src, /datum/notice/fx_examine, "inner", texts)
		log += "read:[jointext(texts, "|")]"

/datum/notice_fx/proc/on_entered(datum/notice/fx_entered/N)
	log += "entered:[N.arrived]<[N.old_loc]"
	if(republish)
		PUBLISH_LEGACY(src, /datum/notice/fx_exited, N.arrived, "nested")
		log += "entered:done"

/datum/notice_fx/proc/on_exited(datum/notice/fx_exited/N)
	log += "exited:[N.gone]>[N.new_loc]"

/datum/notice_fx/proc/on_trait(datum/notice/fx_trait/N)
	log += "trait:[N.trait]"

/datum/notice_fx/proc/on_examine_lines(datum/notice/fx_examine/N)
	log += "examine:[N.user]"
	N.texts += "line from [N.user]"
	if(recurse_examine)
		PUBLISH_LEGACY(src, /datum/notice/fx_examine, "deeper", N.texts)

/datum/notice_fx/proc/on_hitby(datum/notice/fx_hitby/N)
	log += "hitby:[N.source_]:[N.throwingdatum]"

/datum/notice_fx/proc/on_irradiation(datum/notice/fx_irradiation/N)
	log += "rad:[N.pulse_information]:[N.insulation_to_target]"

/// Hears atom_entered through observe(), the hook form the converted listeners use.
/datum/notice_fx_listener
	var/datum/notice_fx/into

/datum/notice_fx_listener/proc/heard_entered(datum/act/notice/A)
	var/datum/notice/fx_entered/N = A
	into.log += "hook entered:[N.arrived]"

// ---------------------------------------------------------------- tests

/// Each representative notice is delivered at once, with its payload in fill() order.
/datum/unit_test/dq_notice_delivery_sync/Run()
	var/datum/notice_fx/F = allocate(/datum/notice_fx)
	PUBLISH_LEGACY(F, /datum/notice/fx_dir_change, NORTH, SOUTH)
	TEST_ASSERT_EQUAL(jointext(F.log, ","), "dir:[NORTH]>[SOUTH]", "delivered before PUBLISH_LEGACY returned")
	PUBLISH_LEGACY(F, /datum/notice/fx_trait, "fx_trait")
	PUBLISH_LEGACY(F, /datum/notice/fx_hitby, "rock", "throw")
	PUBLISH_LEGACY(F, /datum/notice/fx_irradiation, "pulse", 0.5)
	TEST_ASSERT_EQUAL(jointext(F.log, ","), "dir:[NORTH]>[SOUTH],trait:fx_trait,hitby:rock:throw,rad:pulse:0.5", "each delivered at once, fields in fill() order")
	var/list/texts = list("base")
	PUBLISH_LEGACY(F, /datum/notice/fx_examine, "viewer", texts)
	TEST_ASSERT_EQUAL(jointext(texts, "|"), "base|line from viewer", "an examine handler has appended its line when the sender reads the list back")

/// Occurrences are never coalesced: back-to-back publishes of one type are all delivered, in publish order.
/datum/unit_test/dq_notice_delivery_not_coalesced/Run()
	var/datum/notice_fx/F = allocate(/datum/notice_fx)
	PUBLISH_LEGACY(F, /datum/notice/fx_dir_change, NORTH, EAST)
	PUBLISH_LEGACY(F, /datum/notice/fx_dir_change, EAST, NORTH)
	PUBLISH_LEGACY(F, /datum/notice/fx_dir_change, NORTH, EAST)
	TEST_ASSERT_EQUAL(jointext(F.log, ","), "dir:[NORTH]>[EAST],dir:[EAST]>[NORTH],dir:[NORTH]>[EAST]", "three changes that end where the first did: all three delivered")

/// The type's own reactions hear a notice before an observe() hook does; a notice published from a handler is
/// delivered after the current delivery (hooks included) and before the outermost publish returns.
/datum/unit_test/dq_notice_delivery_order/Run()
	var/datum/notice_fx/F = allocate(/datum/notice_fx)
	var/datum/notice_fx_listener/L = allocate(/datum/notice_fx_listener)
	L.into = F
	TEST_ASSERT(observe(F, /datum/notice/fx_entered, L, then(TYPE_PROC_REF(/datum/notice_fx_listener, heard_entered))), "observed")
	PUBLISH_LEGACY(F, /datum/notice/fx_entered, "crate", "hall")
	TEST_ASSERT_EQUAL(jointext(F.log, ","), "entered:crate<hall,hook entered:crate", "static reaction first, then the hook, both before the publish returned")
	F.log.Cut()
	F.republish = TRUE
	PUBLISH_LEGACY(F, /datum/notice/fx_entered, "crate", "hall")
	TEST_ASSERT_EQUAL(jointext(F.log, ","), "entered:crate<hall,entered:done,hook entered:crate,exited:crate>nested", "the nested publish waits for the current delivery, then is delivered before the outer publish returns")
	TEST_ASSERT_EQUAL(unobserve(F, /datum/notice/fx_entered, L), 1, "unobserve removed the hook")
	F.log.Cut()
	F.republish = FALSE
	PUBLISH_LEGACY(F, /datum/notice/fx_entered, "crate", "hall")
	TEST_ASSERT_EQUAL(jointext(F.log, ","), "entered:crate<hall", "and the hook hears nothing more")

/// A read-back notice published from inside another delivery is answered at once: the handler that published it reads the lines
/// back on its next line. A plain notice published from the same handler still waits for the current delivery (reactions.md section 3).
/datum/unit_test/dq_notice_delivery_read_back_nested/Run()
	var/datum/notice_fx/F = allocate(/datum/notice_fx)
	F.ask_examine = TRUE
	PUBLISH_LEGACY(F, /datum/notice/fx_dir_change, NORTH, SOUTH)
	TEST_ASSERT_EQUAL(jointext(F.log, ","), "dir:[NORTH]>[SOUTH],examine:inner,read:base|line from inner,exited:plain>nested", "the nested examine was answered before its sender read the list; the plain notice still queued behind the delivery")
	for(var/read_back_type in list(/datum/notice/fx_examine, /datum/notice/turf_change))
		var/datum/notice/proto = read_back_type
		TEST_ASSERT(initial(proto.read_back), "[read_back_type] is read back by its sender, so it is declared read_back")

/// Two examine handlers, the first of which throws; a dir change asks for an examine from inside a delivery.
/datum/notice_fault_fx
	var/answered

/datum/notice_fault_fx/reactions()
	. = ..()
	. += on_notice(/datum/notice/fx_examine, PROC_REF(faulting))
	. += on_notice(/datum/notice/fx_examine, PROC_REF(healthy))
	. += on_notice(/datum/notice/fx_dir_change, PROC_REF(ask))

/datum/notice_fault_fx/proc/faulting(datum/notice/fx_examine/N)
	N.texts += "first"
	throw EXCEPTION("expected examine handler fault")

/datum/notice_fault_fx/proc/healthy(datum/notice/fx_examine/N)
	N.texts += "second"

/datum/notice_fault_fx/proc/ask(datum/notice/fx_dir_change/N)
	var/list/texts = list()
	PUBLISH_LEGACY(src, /datum/notice/fx_examine, "inner", texts)
	answered = jointext(texts, "|")

/// A notice that faults past its handlers, where nothing in the delivery catches it.
/datum/notice/fx_release_fault

/datum/notice/fx_release_fault/release()
	throw EXCEPTION("expected release fault")

/// Clears what a broken delivery left behind so one failure cannot wedge every later test, and returns what it found.
/proc/notice_fx_state_left()
	. = "delivering=[GLOB.rx_notice_delivering],depth=[GLOB.rx_answer_depth],queued=[length(GLOB.rx_notice_queue)]"
	GLOB.rx_notice_delivering = FALSE
	GLOB.rx_answer_depth = 0
	GLOB.rx_notice_queue.Cut()

/// A throwing examine handler costs its own line only: the next handler still answers, at the top level and nested, and delivery is not left wedged.
/datum/unit_test/dq_notice_delivery_handler_fault/Run()
	var/datum/notice_fault_fx/F = allocate(/datum/notice_fault_fx)
	GLOB.dq_caught_capture = list()
	var/list/texts = list()
	var/escaped = null
	try
		PUBLISH_LEGACY(F, /datum/notice/fx_examine, "viewer", texts)
		PUBLISH_LEGACY(F, /datum/notice/fx_dir_change, NORTH, SOUTH)
	catch(var/exception/e)
		escaped = e.name
	var/list/reported = GLOB.dq_caught_capture
	GLOB.dq_caught_capture = null
	var/left = notice_fx_state_left()
	TEST_ASSERT_NULL(escaped, "a handler fault stays inside the delivery")
	TEST_ASSERT_EQUAL(left, "delivering=0,depth=0,queued=0", "a handler fault leaves delivery idle")
	TEST_ASSERT_EQUAL(jointext(texts, "|"), "first|second", "the handler after the fault still wrote its line (top level)")
	TEST_ASSERT_EQUAL(F.answered, "first|second", "the handler after the fault still wrote its line (nested)")
	TEST_ASSERT_EQUAL(length(reported), 2, "each fault is reported")

/// A fault outside any handler's try cannot strand the delivering flag: if it did, every later notice in the world would queue forever.
/datum/unit_test/dq_notice_delivery_fault_not_wedged/Run()
	var/datum/notice_fx/F = allocate(/datum/notice_fx)
	GLOB.dq_caught_capture = list()
	var/escaped = null
	try
		publish(F, take_notice(/datum/notice/fx_release_fault))
	catch(var/exception/e)
		escaped = e.name
	GLOB.dq_caught_capture = null
	var/left = notice_fx_state_left()
	TEST_ASSERT_NULL(escaped, "the fault stays inside publish()")
	TEST_ASSERT_EQUAL(left, "delivering=0,depth=0,queued=0", "the fault leaves delivery idle")
	PUBLISH_LEGACY(F, /datum/notice/fx_trait, "after")
	TEST_ASSERT_EQUAL(jointext(F.log, ","), "trait:after", "the next notice is delivered at once")

/// An examine handler that examines again is cut at RX_ANSWER_DEPTH with one report; every answer that ran keeps its line and the sender keeps going.
/datum/unit_test/dq_notice_delivery_examine_recursion/Run()
	var/datum/notice_fx/F = allocate(/datum/notice_fx)
	F.recurse_examine = TRUE
	GLOB.dq_caught_capture = list()
	var/list/texts = list()
	var/escaped = null
	try
		PUBLISH_LEGACY(F, /datum/notice/fx_examine, "viewer", texts)
	catch(var/exception/e)
		escaped = e.name
	var/list/reported = GLOB.dq_caught_capture
	GLOB.dq_caught_capture = null
	var/left = notice_fx_state_left()
	TEST_ASSERT_NULL(escaped, "the cut stays inside publish()")
	TEST_ASSERT_EQUAL(left, "delivering=0,depth=0,queued=0", "the cut leaves delivery idle")
	TEST_ASSERT_EQUAL(length(texts), RX_ANSWER_DEPTH + 1, "the outer delivery and every answer wrote its line")
	TEST_ASSERT_EQUAL(length(reported), 1, "the cut is reported once")
