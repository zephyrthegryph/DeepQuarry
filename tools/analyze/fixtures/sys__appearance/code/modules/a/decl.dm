OM_FIELD(/obj/machinery/widget, on, FALSE, CHANGE_MACHINE_STATE)
OM_FIELD(/obj/machinery/widget, hidden_f, FALSE, CHANGE_X)
OM_FIELD_TYPED(/obj/machinery/widget, /list, items, null, CHANGE_Y)
OM_FLAG_FIELD(/obj/machinery/widget, bits, 0, CHANGE_Z)
OM_FIELD_SETTER(/obj/machinery/widget, charge, CHANGE_C)
OM_FIELD(/obj/machinery/widget, quiet, 0, 0)
OM_DERIVE_FIELD(/obj/machinery/widget, derived, CH)
OM_FIELD(/obj/item/gadget, lit, FALSE, CHANGE_L)
OM_FLAG_FIELD_BITS(/obj/item/gadget, gbits, 0, CH)
OM_FIELD(/obj/machinery/widget, short_args)

APPEARANCE_TEMPLATE(/obj/machinery/widget, "widget{on}{bits?x:y}{initial}")
APPEARANCE_WATCH(/obj/machinery/widget, list("items", "charge"))
APPEARANCE_LEVEL(/obj/machinery/widget, "charge", "x{quiet}")
APPEARANCE_EMISSIVE(/obj/machinery/widget/sub, null)
DECLARE_APPEARANCE(/obj/item/gadget, lit)
APPEARANCE_NONE(/obj/item/gadget/plain,)
APPEARANCE_NONE(/obj/item/gadget/noclose)
APPEARANCE_TEMPLATE(/obj/item/gadget/templated, "g{gbits}")

/obj/machinery/widget
	var/obj/machinery/widget/partner
	var/obj/item/gadget/tool
	var/datum/thing

/obj/machinery/widget/proc/set_on(v)
	on = v
	update_icon()
	src.update_icon()
	queue_icon_update()
	thing.update_icon()
	INVOKE_ASYNC(src, PROC_REF(update_icon))
	addtimer(CALLBACK(src, PROC_REF(update_icon)), 5)
	om_after(src, 5, PROC_REF(update_icon))
	om_after_x(src, 5, PROC_REF(queue_icon_update))
	CALLBACK(thing, PROC_REF(update_icon))
	update_icon() // ALLOW(sys_update_icon): an alias keeps only overrides
	update_icon() // ALLOW(sys_update_icon_call): fixture keep
	// ALLOW(sys_update_icon_call): fixture keep above
	update_icon()
	update_icon(1)
	update_icon (1)
	to_chat(usr, "update_icon()")
	// update_icon()
	x.update_icon()
	proc/update_icon()
	thing?.update_icon()

/obj/machinery/widget/proc/poke(obj/machinery/widget/other)
	set_on(TRUE)
	update_icon()

/obj/machinery/widget/proc/poke2(obj/machinery/widget/other)
	other.set_on(TRUE)
	other.update_icon()
	update_icon()

/obj/machinery/widget/proc/cond(a)
	if(a)
		set_on(TRUE)
	update_icon()

/obj/machinery/widget/proc/cond2(a)
	set_on(TRUE)
	if(a)
		update_icon()

/obj/machinery/widget/proc/cond3(a)
	if(a)
		set_on(TRUE)
	else
		set_on(FALSE)
	update_icon()

/obj/machinery/widget/proc/cond4(a)
	if(a)
		to_chat(usr, "x")
	update_icon()

/obj/machinery/widget/proc/harmless()
	set_on(TRUE)
	to_chat(usr, "x")
	playsound(src, 'x.ogg', 1)
	var/x = 1
	. = 1
	user.visible_message("a")
	MACHINE_WAKE(src)
	SStgui.update_uis(src)
	update_icon()

/obj/machinery/widget/proc/nonharmless()
	set_on(TRUE)
	do_thing()
	update_icon()

/obj/machinery/widget/proc/early_return(a)
	if(a)
		set_on(TRUE)
		return
	update_icon()

/obj/machinery/widget/proc/early_return2(a)
	set_on(TRUE)
	if(a)
		return
	update_icon()

/obj/machinery/widget/proc/blank_lines()
	set_on(TRUE)

	update_icon()

/obj/machinery/widget/proc/hidden_set()
	set_hidden_f(TRUE)
	update_icon()

/obj/machinery/widget/proc/quiet_set()
	set_quiet(1)
	update_icon()

/obj/machinery/widget/proc/derived_set()
	set_derived(1)
	update_icon()

/obj/machinery/widget/proc/charge_it()
	set_charge(5)
	update_icon()

/obj/machinery/widget/proc/items_it()
	set_items(list())
	update_icon()

/obj/machinery/widget/proc/bits_it()
	bits_add(1)
	bits_remove(1)
	update_icon()

/obj/machinery/widget/proc/om_set_it()
	om_set(src, "on", TRUE)
	update_icon()

/obj/machinery/widget/proc/short_it()
	set_short_args(1)
	update_icon()

/obj/machinery/widget/proc/typed(obj/item/gadget/g, obj/machinery/widget/w, mob/m)
	g.set_lit(1)
	g.update_icon()
	w.set_on(1)
	w.update_icon()
	g.update_icon()
	m.set_on(1)
	m.update_icon()
	GLOB.x.update_icon()

/obj/machinery/widget/proc/members()
	partner.set_on(1)
	partner.update_icon()
	tool.set_lit(1)
	tool.update_icon()
	partner.tool.set_lit(1)
	partner.tool.update_icon()
	src.partner.set_on(1)
	src.partner.update_icon()
	partner?.set_on(1)
	partner?.update_icon()
	thing.set_on(1)
	thing.update_icon()
	src.set_on(1)
	src.update_icon()

/obj/machinery/widget/proc/power_change()
	set_on(TRUE)
	return

/obj/machinery/widget/sub/proc/power_change()
	..()
	update_icon()

/obj/machinery/widget/sub/proc/power_change2()
	. = ..()
	update_icon()

/obj/machinery/widget/sub/proc/power_change3()
	return ..()
	update_icon()

/obj/machinery/widget/sub/proc/atom_break()
	if(..())
		update_icon()

/obj/machinery/widget/sub/proc/atom_fix()
	update_icon()

/obj/machinery/widget/sub/proc/power_change4()
	var/x = ..()
	update_icon()

/obj/machinery/widget/sub/sub2/proc/power_change()
	..()
	update_icon()

/obj/machinery/widget/Initialize(mapload)
	set_on(TRUE)
	update_icon()

/obj/machinery/widget/proc/inl() update_icon()

/obj/machinery/widget/proc/inl2() set_on(TRUE)
	update_icon()

/obj/machinery/widget/update_icon()
	return

/obj/machinery/widget/proc/update_icon()
	return

/obj/machinery/widget/verb/update_icon()
	return

/atom/update_icon()
	return

/atom/proc/update_icon()
	return

/obj/item/gadget/update_icon() // ALLOW(sys_update_icon): procedural drawing
	return

// ALLOW(sys_update_icon): procedural from above
/obj/item/gadget/plain/update_icon()
	return

/obj/item/gadget/noclose/update_icon() // ALLOW(sys_update_icon_override): the canonical name
	return

/obj/item/gadget/templated/update_icon() // ALLOW(sys_update_icon)
	return

/obj/item/x/update_icon() // ALLOW(other): nope
	return

/obj/item/y/proc/update_icon()
	return

/obj/item/gadget/proc/light()
	set_lit(TRUE)
	update_icon()

/obj/item/gadget/plain/proc/light2()
	set_lit(TRUE)
	update_icon()

/obj/item/gadget/noclose/proc/light3()
	set_lit(TRUE)
	update_icon()

/obj/item/gadget/templated/proc/light4()
	set_lit(TRUE)
	set_gbits(1)
	update_icon()

/obj/item/gadget/proc/light5()
	gbits_add(1)
	update_icon()

/mob/proc/not_capable()
	set_on(TRUE)
	update_icon()

/datum/proc/unknown_type()
	set_on(TRUE)
	update_icon()

/obj/machinery/widget/proc/appearance_overlays()
	add_overlay(x)
	src.cut_overlays()
	cut_overlay(y)
	copy_overlays(z)
	overlays += x
	overlays = list()
	overlays.Cut()
	src.overlays -= x
	overlays == x
	other.add_overlay(x)
	other.overlays += x
	set_on(TRUE)
	om_set(src, "on", 1)
	update_icon()
	add_overlay(x) // ALLOW(sys_appearance_proc_overlays): fixture keep
	set_on(FALSE) // ALLOW(sys_appearance_proc_state): fixture keep
	return list()

/obj/item/gadget/proc/appearance_overlays()
	set_lit(1)
	set_hidden_f(1)
	overlays = null
	return list()

/obj/item/gadget/plain/proc/appearance_overlays()
	set_lit(1)

/mob/proc/appearance_overlays()
	set_on(1)
	add_overlay(x)
