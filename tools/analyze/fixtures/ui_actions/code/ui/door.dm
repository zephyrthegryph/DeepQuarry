/datum/capability/lock
/datum/capability/lock/airlock
/datum/capability/lock/proc/act_lock_toggle(mob/user, atom/holder, state, key, extra)
	state = ui_bool(state)
	key = ui_number(key)
	return extra
/datum/capability/lock/airlock/proc/act_lock_toggle(mob/user, atom/holder, state, key, extra, strength)
	state = ui_bool(state)
	return strength
/datum/capability/lock/airlock/proc/act_lock_extra(mob/user, atom/holder, wide)
	return ui_bool(wide)
/datum/capability/cycle
/datum/capability/cycle/proc/act_cycle_it(mob/user, atom/holder, times)
	return ui_number(times)
/datum/capability/weird/proc/act_weird(mob/user, atom/holder, wobble)
	return ui_number(wobble)
/datum/capability/slot/x/proc/act_slot_it(mob/user, atom/holder, which)
	return ui_choice(which)
/datum/capability/plain/proc/act_plain(mob/user, atom/holder, p)
	return p

/obj/machine/door
	tgui_id = "Door"
/obj/machine/door/capabilities()
	. = ..()
	. += cap_lock()
	. += door_bundle(subtypes = list(a = /datum/capability/lock/airlock))
	. += cap_weird()
	. += cap_args()
/obj/machine/door/proc/act_open(mob/user, speed)
	speed = ui_number(speed)

/obj/machine/door/airlock
	tgui_id = "AirlockUi"
/obj/machine/door/airlock/capabilities()
	. = ..()
	. += cap_lock_airlock()
/obj/machine/door/airlock/proc/act_open(mob/user, speed, bolt)
	speed = ui_number(speed)
	bolt = ui_bool(bolt)
