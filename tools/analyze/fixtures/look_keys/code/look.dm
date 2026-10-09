/datum
	var/tmp/abstract_type

/obj/base_thing
	abstract_type = /obj/base_thing
	icon = 'icons/thing.dmi'
	var/open = 0
	var/tint = 0
	var/unused = 0

/obj/base_thing/proc/unrelated()
	// not called from any draw proc
	return 1

/obj/base_thing/update_icon()
	..()
	overlays.Cut()
	if(open)
		overlays += "open"
	draw_tint()

/obj/base_thing/proc/draw_tint()
	if(tint)
		overlays += "tint"

/obj/base_thing/door
	open = 1

/obj/dynamic_thing
	var/mode = 0

/obj/dynamic_thing/update_icon()
	..()
	var/key = "mode"
	if(vars[key])
		overlays += "dyn"

/obj/plain_thing
	var/level = 0
