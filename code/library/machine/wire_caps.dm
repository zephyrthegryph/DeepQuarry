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
//   shock_wire(stat = STAT_ELECTRIFIED)                                  the same, 30 s a pulse, on STAT(T, electrified, TOP, base = 0); read it with
//                                                                        shock_live(holder): live only while the holder is operable (an unpowered
//                                                                        machine shocks nobody; a pulse's 30 s still run out while it is down)
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

CAPABILITY_TYPE(shock_wire, CAP_SHOCK_WIRE, /datum/capability/lib/shock_wire, key = NONE, wire = WIRE_ELECTRIFY, stat = null, cut_value = TRUE, pulse_value = TRUE, pulse_lasts = 30 SECONDS)

/datum/capability/lib/shock_wire/brings_wires()
	return list(wire)

/// Is E electrified now: a hold on its STAT_ELECTRIFIED (the shock wire's, an AI's, an event's; the strongest wins, none overwrites another)
/// while it is operable. A timed hold's clock runs on while E is down, so a pulse's 30 s can run out before the power comes back.
/proc/shock_live(datum/E)
	READS_FROM(E)
	return stat_value(E, STAT_ELECTRIFIED) && stat_value(E, STAT_OPERABLE)

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
