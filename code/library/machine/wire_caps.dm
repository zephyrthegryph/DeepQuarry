// The capabilities that bring the common wires (doc/rewrite/final_api.html, section 11 "The library": wires()).
//
// Each one owns the state its wire drives and brings the wire to any holder that has wires(): the holder declares the capability and the wire
// appears, its effects as the wire's WIRE_DEF says (code/library/machine/wires.dm), acting on this capability's params. A holder never lists
// these wires itself. The state is a stat of the holder, named by `stat` (the holder declares it: STAT(T, aidisabled, ANY)); the wire holds
// it while cut and for a pulse, keyed per wire, and mending releases both.
//
//   ai_control(stat = STAT_AIDISABLED, pulse_lasts = 10 SECONDS)         WIRE_AI_CONTROL: cut locks the AI out until mended; a pulse, for a while
//   power_wires(stat = STAT_SHORTED, count = 2, pulse_lasts =, shock = 50, shock_hands_only =)   WIRE_MAIN_POWER1 (and 2): cut shorts it (and may shock the hand)
//   shock_wire(stat = STAT_SHOCKED, pulse_lasts = 5 SECONDS)            WIRE_ELECTRIFY (or wire = WIRE_SHOCK): live while cut, a while pulsed
//   shock_wire(counter = nameof(seconds_electrified), cut_value = -1, pulse_value = 30)   the same on a machine whose shock is a countdown it runs
//                                                                        down itself, a frame at a time: cut sets it to cut_value, a pulse to
//                                                                        pulse_value, mending to 0 (through the holder's set_<counter>() when it has one)
//   id_scan(stat = STAT_SCAN_ID, cut_value = TRUE, pulse_value = FALSE)   WIRE_IDSCAN: a scanner the wire overrides (pulses flip it)
//   item_throw(stat = STAT_SHOOT_INVENTORY)                               WIRE_THROW_ITEM: the stock flies while cut; a pulse flips it
//   safety_wire(stat = STAT_SAFETIES)                                     WIRE_SAFETY: the safeties are off while cut; a pulse flips them
//   lathe_wires(pulse_lasts = 5 SECONDS, refresh = TRUE)                  WIRE_LATHE_HACK and WIRE_LATHE_DISABLE on STAT_HACKED and STAT_DISABLED (refresh:
//                                                                        the hand's window shows the hacked designs come and go)
//
// Elsewhere: lock(wire = WIRE_IDSCAN) (code/library/access/lock.dm) and bolts(wire = WIRE_DOOR_BOLTS) (code/library/machine/door_parts.dm).
// pulse_lasts = WIRE_PULSE_TOGGLES makes a pulse flip the hold instead of timing it; pulse_lasts = 0, a pulse does nothing. A capability given
// no stat brings its wire with no state of its own (a wire the holder reads with wire_is_cut(), or a decoy).

CAPABILITY_TYPE(ai_control, CAP_AI_CONTROL, /datum/capability/lib/ai_control, key = NONE, stat = null, pulse_lasts = 1 SECOND)

TYPE_TABLE(/datum/capability/lib/ai_control, brought_wires, list(WIRE_AI_CONTROL))

CAPABILITY_TYPE(power_wires, CAP_POWER_WIRES, /datum/capability/lib/power_wires, key = NONE, stat = null, count = 1, pulse_lasts = 0, shock = 0, shock_hands_only = FALSE)

/datum/capability/lib/power_wires/brings_wires()
	return count >= 2 ? list(WIRE_MAIN_POWER1, WIRE_MAIN_POWER2) : list(WIRE_MAIN_POWER1)

/// A power wire cut or mended: cutting it may shock the hand, and so may mending it when that brings the power back. shock_hands_only: only a
/// living hand is shocked (a scripted cut sparks nothing); otherwise the machine's shock runs whoever (or nothing) cut it.
/datum/capability/lib/power_wires/proc/power_wire_moved(atom/holder, wire, mob/user)
	if(!shock || !istype(holder, /obj/machinery))
		return
	if(shock_hands_only && !isliving(user))
		return
	if(!wire_is_cut(holder, wire) && stat && stat_value(holder, stat))
		return // mended, but the power is still out
	var/obj/machinery/M = holder
	M.shock(user, shock)

CAPABILITY_TYPE(shock_wire, CAP_SHOCK_WIRE, /datum/capability/lib/shock_wire, key = NONE, wire = WIRE_ELECTRIFY, stat = null, counter = null, cut_value = TRUE, pulse_value = TRUE, pulse_lasts = 30 SECONDS)

/datum/capability/lib/shock_wire/brings_wires()
	return list(wire)

/// The countdown of a machine that runs its shock down itself (`counter`), set from the wire.
/datum/capability/lib/shock_wire/proc/counter_set(datum/holder, value)
	if(!counter)
		return
	var/setter = "set_[counter]"
	if(hascall(holder, setter))
		call(holder, setter)(value)
	else
		holder.vars[counter] = value // ALLOW(api): the countdown var the capability's counter param names, on a holder with no setter for it

/// The shock wire cut: live for good.
/datum/capability/lib/shock_wire/proc/counter_cut(datum/holder, cut_wire, mob/user)
	counter_set(holder, cut_value)

/// The shock wire pulsed: live for pulse_value frames.
/datum/capability/lib/shock_wire/proc/counter_pulsed(datum/holder, pulsed_wire, mob/user)
	counter_set(holder, pulse_value)

/// The shock wire mended: safe.
/datum/capability/lib/shock_wire/proc/counter_mended(datum/holder, mended_wire, mob/user)
	counter_set(holder, 0)

CAPABILITY_TYPE(id_scan, CAP_ID_SCAN, /datum/capability/lib/id_scan, key = NONE, stat = null, cut_value = TRUE, pulse_value = TRUE, pulse_lasts = WIRE_PULSE_TOGGLES)

TYPE_TABLE(/datum/capability/lib/id_scan, brought_wires, list(WIRE_IDSCAN))

CAPABILITY_TYPE(item_throw, CAP_ITEM_THROW, /datum/capability/lib/item_throw, key = NONE, stat = null, pulse_lasts = WIRE_PULSE_TOGGLES)

TYPE_TABLE(/datum/capability/lib/item_throw, brought_wires, list(WIRE_THROW_ITEM))

CAPABILITY_TYPE(safety_wire, CAP_SAFETY_WIRE, /datum/capability/lib/safety_wire, key = NONE, stat = null, pulse_lasts = WIRE_PULSE_TOGGLES)

TYPE_TABLE(/datum/capability/lib/safety_wire, brought_wires, list(WIRE_SAFETY))

CAPABILITY_TYPE(lathe_wires, CAP_LATHE_WIRES, /datum/capability/lib/lathe_wires, key = NONE, hack_stat = STAT_HACKED, disable_stat = STAT_DISABLED, pulse_lasts = WIRE_PULSE_TOGGLES, refresh = FALSE)

TYPE_TABLE(/datum/capability/lib/lathe_wires, brought_wires, list(WIRE_LATHE_HACK, WIRE_LATHE_DISABLE))

/// The hack wire moved under a hand (lathe_wires(refresh = TRUE)): the hacked designs came or went, so that hand's window refreshes its designs at
/// once. A pulse running out refreshes through the holder's own on_change(nameof(hacked), EXIT, ...).
/datum/capability/lib/lathe_wires/proc/hack_wire_moved(datum/holder, moved_wire, mob/user)
	if(!refresh || !istype(holder, /obj/machinery))
		return
	var/obj/machinery/M = holder
	M.update_tgui_static_data(user)
