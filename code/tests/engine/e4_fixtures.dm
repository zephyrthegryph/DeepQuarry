// E4, actions and hooks: the gate fixtures of doc/rewrite/final_api.html section 19 "The seven workers" (code/modules/unit_tests/dq_e4_actions_tests.dm).
//
// One ACTION with an instead (its notice marked replaced), an adjusts and an on_notice; actions nothing hooks (ACT_PASS), actions only a committed
// listener hears (an outcome nobody asked for), a recursive takeover (the nested-action cap), and while_slotted entries that are hooks. Compiled under
// UNIT_TESTS only.

#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

/// The strike of the main fixture: `amount` is the typed field adjusts() changes and ACT_FINAL reads.
ACTION(e4_strike, amount, notice = /datum/notice/e4_struck)
/// An action nothing hooks.
ACTION(e4_plain, amount, notice = /datum/notice/e4_plained)
/// An action only a committed listener hears.
ACTION(e4_quiet, notice = /datum/notice/e4_hushed)
/// An action whose takeover starts the same action again (the nested-action cap).
ACTION(e4_nest, notice = /datum/notice/e4_nested)

/// The target of the main fixture. A shield takes the strike over; the rest of its hooks: an adjusts that halves the amount, and three listeners
/// (committed, replaced, any).
/obj/e4_fixture
	name = "e4 fixture"
	anchored = TRUE
	/// Read by the instead hook's gate.
	var/shield = FALSE
	var/absorbed = 0
	var/heard_committed = 0
	var/heard_replaced = 0
	var/heard_any = 0
	var/last_amount
	var/last_outcome

/obj/e4_fixture/target

CAPABILITIES(/obj/e4_fixture/target, \
	extend(/datum/act/e4_strike, adjusts(amount, scale = 0.5)), \
	extend(/datum/act/e4_strike, instead(when(nameof(shield)), then(PROC_REF(absorb)))), \
	on_notice(/datum/notice/e4_struck, then(PROC_REF(heard))), \
	on_notice(/datum/notice/e4_struck, then(PROC_REF(heard_when_replaced)), outcome = ACT_REPLACED), \
	on_notice(/datum/notice/e4_struck, then(PROC_REF(heard_whatever)), outcome = ACT_ANY))

/obj/e4_fixture/target/proc/absorb(datum/act/A)
	absorbed++

/obj/e4_fixture/target/proc/heard(datum/act/A)
	var/datum/notice/e4_struck/N = A
	heard_committed++
	last_amount = N.amount
	last_outcome = N.outcome

/obj/e4_fixture/target/proc/heard_when_replaced(datum/act/A)
	var/datum/notice/e4_struck/N = A
	heard_replaced++
	last_outcome = N.outcome

/obj/e4_fixture/target/proc/heard_whatever(datum/act/A)
	heard_any++

/// Nothing hooks anything on it.
/obj/e4_fixture/plain

/// Only a committed listener.
/obj/e4_fixture/quiet

CAPABILITIES(/obj/e4_fixture/quiet, \
	on_notice(/datum/notice/e4_hushed, then(PROC_REF(heard))))

/obj/e4_fixture/quiet/proc/heard(datum/act/A)
	heard_committed++

/// A takeover that starts the same action again: each run is one deeper, and the ninth nested action is refused.
/obj/e4_fixture/nester
	var/runs = 0
	var/refused = 0

CAPABILITIES(/obj/e4_fixture/nester, \
	extend(/datum/act/e4_nest, instead(then(PROC_REF(again)))))

/obj/e4_fixture/nester/proc/again(datum/act/A)
	runs++
	var/datum/act/e4_nest/F = ACT_TRY(src, e4_nest)
	if(!F)
		refused++ // taken over again (the run before the cap) or refused at the cap: both end the nested action without an act
		return
	act_cancel(F)

/// A wearer: no hooks of its own.
/obj/e4_fixture/wearer

/// An item that declares hooks while it is in a slot: +1 to a strike's amount on its wearer.
/obj/item/e4_fixture
	name = "e4 item"

/obj/item/e4_fixture/amulet

CAPABILITIES(/obj/item/e4_fixture/amulet, \
	while_slotted("e4_slot", extend(/datum/act/e4_strike, adjusts(amount, by = 1)), on = ON_HOLDER))

/// A bed whose occupant gets +2 while buckled in.
/obj/e4_fixture/bed

CAPABILITIES(/obj/e4_fixture/bed, \
	while_slotted("e4_bed", extend(/datum/act/e4_strike, adjusts(amount, by = 2)), on = ON_CONTENTS))

/// A listener that observes another entity at runtime: observe(source, notice, listener, parts...).
/obj/e4_fixture/listener
	var/seen = 0
	var/seen_holder_was_me = FALSE
	var/seen_target_ref

/obj/e4_fixture/listener/proc/watch(datum/source)
	return observe(source, /datum/notice/e4_hushed, src, then(PROC_REF(saw)))

/obj/e4_fixture/listener/proc/saw(datum/act/A)
	var/datum/act/notice/N = A
	seen++
	seen_holder_was_me = (N.holder == src)
	seen_target_ref = REF(N.target)

/// on_op and on_change: a switch with a powered flag (an edge hook) and a charge_level (a key hook), and a watcher of one op key.
/obj/e4_fixture/switch
	var/powered = FALSE
	var/charge_level = 0
	var/entered = 0
	var/exited = 0
	var/charge_changes = 0
	var/ops_heard = 0

TRACKED(/obj/e4_fixture/switch, powered)
TRACKED(/obj/e4_fixture/switch, charge_level)

CAPABILITIES(/obj/e4_fixture/switch, 	on_change(nameof(powered), ENTER, then(PROC_REF(power_on))), 	on_change(nameof(powered), EXIT, then(PROC_REF(power_off))), 	on_change(nameof(charge_level), ANY, then(PROC_REF(charge_level_changed))), 	on_op("e4.toggle", then(PROC_REF(op_heard))))

/obj/e4_fixture/switch/proc/power_on(datum/act/A)
	entered++

/obj/e4_fixture/switch/proc/power_off(datum/act/A)
	exited++

/obj/e4_fixture/switch/proc/charge_level_changed(datum/act/A)
	charge_changes++

/obj/e4_fixture/switch/proc/op_heard(datum/act/A)
	ops_heard++

/// The twin pair of the bridge test: an entity that listens for the notice of an om event.
/datum/om_test_entity/e4_twin
	var/notices_heard = 0
	var/last_bumped

CAPABILITIES(/datum/om_test_entity/e4_twin, \
	on_notice(/datum/notice/atom_bumped, then(PROC_REF(notice_heard))))

/datum/om_test_entity/e4_twin/proc/notice_heard(datum/act/A)
	var/datum/notice/atom_bumped/N = A
	notices_heard++
	last_bumped = N.bumped

#endif
