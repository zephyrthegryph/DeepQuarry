////////////////////HOLOSIGN///////////////////////////////////////
/obj/machinery/holosign
	name = "holosign"
	desc = "Small wall-mounted holographic projector"
	icon = 'icons/obj/holosign.dmi'
	icon_state = "sign_off"
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

/obj/machinery/holosign/proc/toggle()
	if(!operable())
		return
	lit = !lit
	set_use_power(lit ? USE_POWER_ACTIVE : USE_POWER_IDLE)

/obj/machinery/holosign/draw(datum/look/look)
	..()
	if(!lit)
		look.state(off_icon)
		look.light_off()
	else
		look.state(on_icon)
		look.light(2, 0.25, signlight)

/obj/machinery/holosign/power_change()
	. = ..()
	if(power_lost())
		lit = 0
		set_use_power(USE_POWER_OFF)


/obj/machinery/holosign/surgery
	name = "surgery holosign"
	desc = "Small wall-mounted holographic projector. This one reads SURGERY."
	on_icon = "surgery"

/obj/machinery/holosign/exit
	name = "exit holosign"
	desc = "Small wall-mounted holographic projector. This one reads EXIT."
	on_icon = "emergencyexit"

/obj/machinery/holosign/bar
	name = "bar holosign"
	desc = "Small wall-mounted holographic projector. This one reads OPEN."
	icon_state = "barclosed"
	on_icon = "baropen"
	off_icon = "barclosed"
	signlight = "#b1edf9"

////////////////////SWITCH///////////////////////////////////////

/obj/machinery/button/holosign
	name = "holosign switch"
	desc = "A remote control switch for holosign."
	icon = 'icons/obj/power.dmi'
	icon_state = "crema_switch"

CAPABILITIES(/obj/machinery/button/holosign)
	op("toggle", hand(), priority(OP_PRIORITY_DEFAULT), label("Toggle"), then(PROC_REF(interaction_toggle)))

/// Holosigns sharing our id (keyed).
/obj/machinery/button/holosign/var/list/obj/machinery/holosign/controlled_signs
/obj/machinery/button/holosign/relations()
	. = ..()
	. += rel_many(nameof(controlled_signs), keyed = nameof(id), keyed_target = /obj/machinery/holosign)
/obj/machinery/holosign/relations()
	. = ..()
	. += rel_key(nameof(id))

/obj/machinery/button/holosign/proc/interaction_toggle(datum/act/op/A)
	var/mob/user = A.actor
	add_fingerprint(user)

	use_power(5)

	set_active(!active)
	icon_state = "light[active]"

	for(var/obj/machinery/holosign/M as anything in controlled_signs)
		M.toggle()
	return TRUE


/obj/machinery/holosign/chemistry
	name = "chemistry holosign"
	desc = "Small wall-mounted holographic projector. This one signifies that a chemist is on duty."
	icon = 'icons/obj/holosign.dmi'
	icon_state = "chemoff"
	on_icon = "chemon"
	off_icon = "chemoff"

/obj/machinery/holosign/robotics
	name = "robotics holosign"
	desc = "Small wall-mounted holographic projector. This one signifies that a roboticist is on duty."
	icon = 'icons/obj/holosign.dmi'
	icon_state = "robotoff"
	on_icon = "roboton"
	off_icon = "robotoff"
