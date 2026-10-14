DECLARE_APPEARANCE_PROC(/obj/machinery/e, PROC_REF(e_look), list("a"))
DECLARE_APPEARANCE_PROC (/obj/machinery/e2, TYPE_PROC_REF(/obj/machinery/e2, e2_look), list())
DECLARE_APPEARANCE_PROC(/obj/machinery/e3, GLOBAL_PROC_REF(e3_look), list())
// DECLARE_APPEARANCE_PROC(/obj/machinery/e4, PROC_REF(e4_look), list())
DECLARE_APPEARANCE_PROC(/obj/machinery/e5, PROC_REF(e5_look), list()) DECLARE_APPEARANCE_PROC(/obj/machinery/e5, PROC_REF(e5b_look), list())

/obj/machinery/e/proc/e_look()
	icon_state = "a"
	src.icon_state = "b"
	src . icon = 'x.dmi'
	overlays += "x"
	src.overlays -= "x"
	underlays |= "x"
	color = "#fff"
	alpha += 5
	layer = 3
	plane = 3
	transform = matrix()
	pixel_x = 1
	pixel_y = 1
	pixel_w = 1
	pixel_z = 1
	pixel_x == 1
	icon_state = 2; on = 1
	icon_state = f(set_thing(1))
	icon_state = "x" + user.Add(2)
	icon_state *= 2
	icon_state <<= 2
	name = "n"
	desc = "d"
	x.icon_state = "x"
	var/icon_state = "z"
	changed(src)
	set_light(2)
	playsound(src, 'x.ogg', 40)
	to_chat(usr, "x")
	update_icon()
	return list()

/obj/machinery/e2/proc/e2_look()
	level++
	holder.verbs.Remove(x)
	return

/proc/e3_look()
	x = 1
	return

/obj/machinery/e5/proc/e5_look()
	state = 1
	// ALLOW(sys_dx_appearance_side_effect): fixture keeps the next one
	state = 2
	state = 3 // ALLOW(sys_dx_appearance_side_effect): fixture keeps this one

/obj/machinery/e5/proc/e5b_look()
	state = 4

/obj/machinery/e5/proc/not_listed()
	state = 5

/atom/appearance_overlays()
	state = 6

/datum/appearance_overlays()
	state = 7

/atom/proc/appearance_overlays()
	state = 8

/datum/thing/appearance_overlays()
	state = 9
	return list()

/obj/item/thing/appearance_overlays(
		a, b)
	state = 10
	return

/obj/item/thing/appearance_overlays()
	var/n = 0
	n++
	if(n == 1)
		return
	for(var/i in list())
		return
