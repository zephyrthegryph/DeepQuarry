/datum/proc/act_modal_close(mob/user, id)
	return TRUE
/atom/proc/act_atom_thing(mob/user, nothing)
	return TRUE
/obj/thing
	tgui_id = "Thing"
/obj/thing/proc/act_go(mob/user, speed, force)
	speed = ui_number(speed, 0, 10)
	if(!speed)
		return
/obj/thing/proc/act_pick(mob/user, mode, ref, flag)
	var/datum/D = find_ref(user, ref)
	if(!!flag)
		return
	switch(mode)
		if("a")
			return
/obj/thing/proc/find_ref(mob/user, ref)
	return ui_ref(ref, null, /datum)
/obj/thing/proc/act_raw(mob/user, amount, name, kind, when, extra)
	if(!amount)
		return
	var/x = amount + 1
	to_chat(user, name)
	if(kind == MODE_FAST)
		return
	helper(when)
	src.helper(extra)
/obj/thing/proc/helper(value)
	world << value
/obj/thing/subtype/proc/act_sub(mob/user, level, list/items)
	var/obj/level/marker = null
	level = ui_bool(level)
	for(var/i in islist(items) ? items : list())
		return
/obj/thing/proc/act_bolt_toggle(mob/user, target_state)
	return ui_bool(target_state)
/obj/old
	tgui_id = "Old"
DECLARE_UI(/obj/old, UI_TITLE("Old"))
/obj/old/proc/act_whatever(mob/user, anything)
	return anything
/datum/capability/breakers
/proc/cap_breakers()
	return new /datum/capability/breakers
/obj/thing/capabilities()
	. = ..()
	. += thing_bundle()
/datum/capability/breakers/proc/act_breaker(mob/user, atom/holder, channel, force)
	channel = ui_number(channel, 1, 3)
	if(!channel)
		return
/datum/capability/unused/proc/act_unused(mob/user, atom/holder, level)
	world << level
/obj/thing/proc/thing_bundle()
	return list()

// Multi-line head, `as` clause and defaults.
/obj/thing/proc/act_multi(mob/user,
		amount = 1,
		list/items = list(),
		text as text)
	amount = ui_number(amount)
	if(items)
		return
	world << text
