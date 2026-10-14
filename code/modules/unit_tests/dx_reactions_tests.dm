// Reactions (code/datums/reactions): demand-gated publish_change, the relation ledger, notices, operations,
// crossings, observe() and the one timer.

// ---------------------------------------------------------------- fixtures

/// `watched` is read by an on_change reaction; `quiet` is read by nobody.
/datum/rx_fx
	var/watched = 0
	var/quiet = 0
	var/level = 0
	var/list/heard = list()
	var/list/crossings = list()
	var/list/seen_ops = list()
	var/list/notes = list()
	var/republish = FALSE

TRACKED(/datum/rx_fx, watched)
TRACKED(/datum/rx_fx, quiet)
TRACKED(/datum/rx_fx, level)

/datum/rx_fx/reactions()
	. = ..()
	. += on_change(list(nameof(watched)), PROC_REF(on_watched))
	. += on_notice(/datum/notice/rx_fx, PROC_REF(on_note))
	. += before_op("rx_fx_op", PROC_REF(veto_op))
	. += after_op("rx_fx_op", PROC_REF(did_op))
	. += on_cross(nameof(level), list(10, 20), PROC_REF(on_level), urgent = TRUE)

/datum/rx_fx/proc/on_watched(list/keys)
	heard += list(keys.Copy())

/datum/rx_fx/proc/on_note(datum/notice/rx_fx/N)
	notes += N.mark
	if(republish && N.mark == 1)
		publish(src, take_notice(/datum/notice/rx_fx, 2))
		publish(src, take_notice(/datum/notice/rx_fx, 3))

/datum/rx_fx/proc/veto_op(ctx)
	seen_ops += "before:[ctx]"
	return ctx == "deny" ? "denied" : null

/datum/rx_fx/proc/did_op(ctx)
	seen_ops += "after:[ctx]"

/datum/rx_fx/proc/on_level(band, previous)
	crossings += list(list(band, previous))

/// An occurrence with a named field.
/datum/notice/rx_fx
	var/mark

/datum/notice/rx_fx/fill(mark)
	src.mark = mark

/// A second notice type nothing listens for.
/datum/notice/rx_fx_other

/// A listener for observe().
/datum/rx_fx_listener
	var/list/got = list()

/datum/rx_fx_listener/proc/heard_quiet(datum/source, list/keys)
	got += list(keys.Copy())

// ---------------------------------------------------------------- tests

/// A change is published only for keys something reads, and handlers run once per drain with the keys.
/datum/unit_test/dx_reactions_demand_gate/Run()
	var/datum/rx_fx/F = allocate(/datum/rx_fx)
	TEST_ASSERT(READERS(F, nameof(/datum/rx_fx::watched)), "an on_change read is a reader")
	TEST_ASSERT(!READERS(F, nameof(/datum/rx_fx::quiet)), "a var nobody reads has no reader")
	F.set_watched(1)
	F.set_watched(2)
	F.set_quiet(9)
	TEST_ASSERT_EQUAL(length(F.heard), 0, "handlers wait for the drain")
	rx_drain()
	TEST_ASSERT_EQUAL(length(F.heard), 1, "two writes, one delivery")
	TEST_ASSERT_EQUAL(F.heard[1][1], nameof(/datum/rx_fx::watched), "with the key that changed")
	F.set_watched(3)
	rx_drain()
	TEST_ASSERT_EQUAL(length(F.heard), 2, "the next frame delivers again")

/// observe() makes a key readable at runtime, delivers to the listener, and is undone by unobserve and by
/// either end dying.
/datum/unit_test/dx_reactions_observe/Run()
	var/datum/rx_fx/F = allocate(/datum/rx_fx)
	var/datum/rx_fx_listener/L = new
	var/datum/reaction/trigger = on_change(list(nameof(/datum/rx_fx::quiet)), TYPE_PROC_REF(/datum/rx_fx_listener, heard_quiet))
	TEST_ASSERT(!READERS(F, nameof(/datum/rx_fx::quiet)), "unread before observe")
	var/datum/rx_listener/rec = observe(F, trigger, L, TYPE_PROC_REF(/datum/rx_fx_listener, heard_quiet))
	TEST_ASSERT(rec, "observe returned the record")
	TEST_ASSERT_EQUAL(observe(F, trigger, L, TYPE_PROC_REF(/datum/rx_fx_listener, heard_quiet)), rec, "the same observation is not doubled")
	TEST_ASSERT(READERS(F, nameof(/datum/rx_fx::quiet)), "observed: now read")
	TEST_ASSERT(rx_ledger_has(F, RELK_LISTENER, L), "stored as a LISTENER relation")
	F.set_quiet(4)
	rx_drain()
	TEST_ASSERT_EQUAL(length(L.got), 1, "the listener heard it")
	TEST_ASSERT_EQUAL(unobserve(F, trigger, L), 1, "unobserve removed one")
	TEST_ASSERT(!READERS(F, nameof(/datum/rx_fx::quiet)), "and the key is unread again")
	TEST_ASSERT(!rx_ledger_has(F, RELK_LISTENER, L), "and the relation is gone")
	observe(F, trigger, L, TYPE_PROC_REF(/datum/rx_fx_listener, heard_quiet))
	qdel(L)
	TEST_ASSERT(!length(F.rx?.listeners), "a dying listener drops its observations from the source")
	TEST_ASSERT(!READERS(F, nameof(/datum/rx_fx::quiet)), "and the key is unread")

/// Occurrences are ordered and never coalesced, even when published from inside a delivery.
/datum/unit_test/dx_reactions_notices_ordered/Run()
	var/datum/rx_fx/F = allocate(/datum/rx_fx)
	F.republish = TRUE
	TEST_ASSERT(WANTS(F, /datum/notice/rx_fx), "the type wants its notice")
	TEST_ASSERT(!WANTS(F, /datum/notice/rx_fx_other), "and not one it doesn't listen for")
	PUBLISH_LEGACY(F, /datum/notice/rx_fx, 1)
	PUBLISH_LEGACY(F, /datum/notice/rx_fx, 3)
	PUBLISH_LEGACY(F, /datum/notice/rx_fx_other)
	TEST_ASSERT_EQUAL(jointext(F.notes, ","), "1,2,3,3", "1 first, its two republishes next (2 then 3), then the second 3: none merged")
	var/datum/notice/rx_fx/N = take_notice(/datum/notice/rx_fx, 7)
	TEST_ASSERT_EQUAL(N.mark, 7, "a notice is filled by take_notice")
	N.release()
	TEST_ASSERT(isnull(N.mark), "and cleared when released")

/// The relation ledger counts sources: a grant lasts until its last source lets go.
/datum/unit_test/dx_reactions_ledger_sources/Run()
	var/datum/rx_fx/F = allocate(/datum/rx_fx)
	var/datum/rx_fx/system = allocate(/datum/rx_fx)
	TEST_ASSERT(grant(F, "night_vision", "goggles"), "the first source makes the grant")
	TEST_ASSERT(!grant(F, "night_vision", "implant"), "a second source does not")
	TEST_ASSERT(granted(F, "night_vision"), "granted")
	TEST_ASSERT(!revoke(F, "night_vision", "goggles"), "one source left")
	TEST_ASSERT(granted(F, "night_vision"), "still granted")
	TEST_ASSERT(revoke(F, "night_vision", "implant"), "the last source gone")
	TEST_ASSERT(!granted(F, "night_vision"), "no longer granted")
	TEST_ASSERT(join(system, F, "cap_a"), "first membership")
	TEST_ASSERT(!join(system, F, "cap_b"), "a second source is the same member")
	TEST_ASSERT(is_member(system, F), "member")
	TEST_ASSERT(!leave(system, F, "cap_a"), "still a member through cap_b")
	TEST_ASSERT(leave(system, F, "cap_b"), "left")
	TEST_ASSERT_EQUAL(length(members_of(system)), 0, "no members")
	join(system, F, "cap_a")
	qdel(F)
	TEST_ASSERT_EQUAL(length(members_of(system)), 0, "a member that dies leaves the system")

/// before_op vetoes with a reason, after_op runs after; both in order, with the op's context.
/datum/unit_test/dx_reactions_ops/Run()
	var/datum/rx_fx/F = allocate(/datum/rx_fx)
	TEST_ASSERT(isnull(rx_before_op(F, "rx_fx_op", null, "ok")), "no veto")
	TEST_ASSERT_EQUAL(rx_before_op(F, "rx_fx_op", null, "deny"), "denied", "a reason vetoes")
	rx_after_op(F, "rx_fx_op", null, "ok")
	TEST_ASSERT_EQUAL(jointext(F.seen_ops, ","), "before:ok,before:deny,after:ok", "each ran with its context, in order")
	TEST_ASSERT(isnull(rx_before_op(F, "another_op", null, "deny")), "another op key is not matched")

/// A read moving to another band delivers (band, previous); the first sight is a baseline. The reaction is urgent:
/// the kernel delivers it (kernel_urgent), so each crossing is run from the U phase here.
/datum/unit_test/dx_reactions_cross/Run()
	var/datum/rx_fx/F = allocate(/datum/rx_fx)
	F.set_level(5)
	kernel().run_urgent(WORK_TEST_LIMIT)
	TEST_ASSERT_EQUAL(length(F.crossings), 0, "the first sight is a baseline")
	F.set_level(7)
	kernel().run_urgent(WORK_TEST_LIMIT)
	TEST_ASSERT_EQUAL(length(F.crossings), 0, "same band: nothing")
	F.set_level(15)
	kernel().run_urgent(WORK_TEST_LIMIT)
	TEST_ASSERT_EQUAL(length(F.crossings), 1, "band 1 entered")
	TEST_ASSERT_EQUAL(F.crossings[1][1], 1, "the new band")
	TEST_ASSERT_EQUAL(F.crossings[1][2], 0, "and the previous one")
	F.set_level(25)
	kernel().run_urgent(WORK_TEST_LIMIT)
	F.set_level(3)
	kernel().run_urgent(WORK_TEST_LIMIT)
	TEST_ASSERT_EQUAL(length(F.crossings), 3, "each band change is delivered in order")
	TEST_ASSERT_EQUAL(F.crossings[3][1], 0, "back below the first threshold")

/// The one timer: a keyed timer is a TIMER relation, replaced by the same key and cancelled by key.
/datum/unit_test/dx_reactions_after_keyed/Run()
	var/datum/rx_fx/F = allocate(/datum/rx_fx)
	var/first = after(F, 100, TYPE_PROC_REF(/datum/rx_fx, did_op), key = "settle", with = list("a"))
	TEST_ASSERT(first, "scheduled")
	TEST_ASSERT(after_pending(F, "settle"), "pending")
	TEST_ASSERT(rx_ledger_has(F, RELK_TIMER, "settle"), "a TIMER relation")
	after(F, 100, TYPE_PROC_REF(/datum/rx_fx, did_op), key = "settle", with = list("b"))
	TEST_ASSERT_EQUAL(length(rx_ledger_sources(F, RELK_TIMER, "settle")), 1, "the same key replaced it: one pending")
	TEST_ASSERT(cancel_after(F, "settle"), "cancelled")
	TEST_ASSERT(!after_pending(F, "settle"), "not pending")
	TEST_ASSERT(!rx_ledger_has(F, RELK_TIMER, "settle"), "and the relation is gone")
	TEST_ASSERT(!cancel_after(F, "settle"), "nothing left to cancel")

/// rel_one/rel_many take a kind; occurrences are not coalesced by default.
/datum/unit_test/dx_reactions_kinds_and_defaults/Run()
	var/datum/own_entry/ref = rel_one("x", kind = RELK_REF)
	var/datum/own_entry/paired = rel_many("y", kind = RELK_PAIRED, back = "z")
	var/datum/own_entry/owned = rel_one("w", kind = RELK_OWNED)
	TEST_ASSERT_EQUAL(ref.entry[OWNE_KIND], OWNK_REL, "REF is a relation view")
	TEST_ASSERT_EQUAL(ref.entry[OWNE_ARG], RELS_PLAIN, "a plain one")
	TEST_ASSERT_EQUAL(paired.entry[OWNE_ARG], RELS_PAIR, "PAIRED with a back is a pair")
	TEST_ASSERT_EQUAL(owned.entry[OWNE_KIND], OWNK_OWN, "OWNED is an ownership entry")
	var/datum/definition_event/E = new
	TEST_ASSERT(!E.coalesce, "an event is an occurrence: not coalesced by default")
	TEST_ASSERT(!E.skip_in_bulk, "and not dropped in bulk by default")
