////////////////////NOTHOLOSIGN///////////////////////////////////////
/obj/machinery/neonsign
	name = "neon sign"
	desc = "Small wall-mounted electronic sign"
	icon = 'icons/obj/neonsigns.dmi'
	icon_state = "sign_off"
	layer = ABOVE_WINDOW_LAYER
	plane = MOB_PLANE
	use_power = USE_POWER_IDLE
	idle_power_usage = 2
	active_power_usage = 4
	anchored = TRUE
	var/lit = 0
	var/id = null
	var/on_icon = "sign_on"
	var/off_icon = "sign_off"
	var/signlight = "#E9E4AF"

/obj/machinery/neonsign/proc/toggle()
	if(!operable())
		return
	lit = !lit
	set_use_power(lit ? USE_POWER_ACTIVE : USE_POWER_IDLE)

DECLARE_APPEARANCE_PROC(/obj/machinery/neonsign, TYPE_PROC_REF(/atom, appearance_overlays), list())
/obj/machinery/neonsign/appearance_overlays()
	. = list()
	if(!lit)
		icon_state = off_icon
		set_light(0)
	else
		icon_state = on_icon
		set_light(2, 0.25, signlight)

/obj/machinery/neonsign/power_change()
	. = ..()
	if(has_stat(NOPOWER))
		lit = 0
		set_use_power(USE_POWER_OFF)


/obj/machinery/neonsign/cafe
	name = "cafe neon sign"
	desc = "Small wall-mounted electronic sign. This one reads CAFE."
	icon_state = "cafesign_off"
	on_icon = "cafesign_on"
	off_icon = "cafesign_off"
	signlight = "#DFA571"

////////////////////SWITCH///////////////////////////////////////

/obj/machinery/button/neonsign
	name = "sign switch"
	desc = "A remote control switch for neon sign."
	icon = 'icons/obj/power.dmi'
	icon_state = "crema_switch"

CAPABILITIES(/obj/machinery/button/neonsign)
	op("toggle", hand(), priority(OP_PRIORITY_DEFAULT - 1), label("Toggle"), then(PROC_REF(interaction_toggle)))

/// Neon signs sharing our id (keyed).
/obj/machinery/button/neonsign/var/list/obj/machinery/neonsign/controlled_signs
/obj/machinery/button/neonsign/relations()
	. = ..()
	. += rel_many(nameof(controlled_signs), keyed = nameof(id), keyed_target = /obj/machinery/neonsign)
/obj/machinery/neonsign/relations()
	. = ..()
	. += rel_key(nameof(id))

/obj/machinery/button/neonsign/proc/interaction_toggle(datum/act/op/A)
	var/mob/user = A.actor
	add_fingerprint(user)

	use_power(5)

	set_active(!active)
	icon_state = "light[active]"

	for(var/obj/machinery/neonsign/M as anything in controlled_signs)
		M.toggle()
	return TRUE
