// the light switch
// can have multiple per area
// can also operate on non-loc area through "otherarea" var
/obj/machinery/light_switch
	name = "light switch"
	desc = "It turns lights on and off. What are you, simple?"
	icon = 'icons/obj/power_vr.dmi'
	icon_state = "light1"
	layer = ABOVE_WINDOW_LAYER
	anchored = TRUE
	use_power = USE_POWER_IDLE
	idle_power_usage = 10
	power_channel = LIGHT
	blocks_emissive = EMISSIVE_BLOCK_NONE
	vis_flags = VIS_HIDE // They have an emissive that looks bad in openspace due to their wall-mounted nature
	flags = WALL_ITEM
	on = 1
	var/area/area
	var/otherarea = null
	var/image/overlay

// ALLOW(init/INSTANCE_STATE): binds to the area it is placed in, or the one the map names, and takes its state
/obj/machinery/light_switch/Initialize(mapload)
	. = ..()

	area = get_area(src) // a location: a plain var

	if(otherarea)
		area = locate(text2path("/area/[otherarea]"))

	if(!name)
		name = "light switch ([area().name])"

	set_on(area().lightswitch)

// The light switch is declared (doc/rewrite/conversion_guide.md): a touch of the hand turns the lights of its area off and on whether the
// switch has power or not (so no machine_basics(): nothing here needs a working casing), any other item used on it leaves its prints, an
// electromagnetic pulse makes it read its power again. What the machine core keeps until the machine track (phase 4): the NOPOWER bit and
// the power_change() dispatch (an area calls it on every channel change and on every switch use).
CAPABILITIES(/obj/machinery/light_switch)
	powered(POWER_CHANNEL_LIGHTING)
	op("toggle", hand(), when(req_empty_hand()), label("Toggle"), wait(0), then(PROC_REF(toggle_lights)))
	op("touch", item(/obj/item), priority(OP_PRIORITY_DEFAULT), wait(0), then(PROC_REF(touched_with)), passes())
	examine_line(PROC_REF(examine_state))
	on_notice(/datum/notice/hit/emp, then(PROC_REF(emp_reread)))

/// What the switch shows: dark without power, else its state, lit in the colour of the state.
/obj/machinery/light_switch/draw(datum/look/look)
	..()
	if(power_lost())
		look.state("light-p")
		return
	look.state("light[on]")
	look.light(2, 0.1, on ? "#82FF4C" : "#F86060")
	look.glow("overlay")

/// Within reach it says what it is set to.
/obj/machinery/light_switch/proc/examine_state(datum/act/op/A)
	var/mob/user = A.actor
	if(!user || !Adjacent(user))
		return null
	return "A light switch. It is [on ? "on" : "off"]."

/// The touch: the area's lights, and every switch of the area, follow the switch.
/obj/machinery/light_switch/proc/toggle_lights(datum/act/op/A)
	set_on(!on)

	area().lightswitch = on
	area().update_icon()
	play_sfx(src, SFX_MACHINES_BUTTON, volume = 100)

	for(var/obj/machinery/light_switch/L as anything in area_contents_of_type(area(), /obj/machinery/light_switch))
		L.set_on(on)

	area().power_change()
	GLOB.lights_switched_on_roundstat++
	return OP_OK

/// Any other item used on it leaves the user's prints, and the click goes on.
/obj/machinery/light_switch/proc/touched_with(datum/act/op/A)
	add_fingerprint(A.actor)
	return OP_OK

/// An EMP makes the switch re-read its power.
/obj/machinery/light_switch/proc/emp_reread(datum/act/A)
	if(!operable())
		return
	power_change()

/obj/machinery/light_switch/allow_pai_interaction(mob/living/silicon/pai/user, proximity_flag)
	return proximity_flag

/// A switch pointed at another area leaves its power alone; every other one follows the light channel like any machine on it.
/obj/machinery/light_switch/power_change()
	if(otherarea)
		return FALSE
	return ..()

//Breakers for event maps

/obj/machinery/light_switch/breaker
	name = "lights breaker"
	desc = "A breaker for controlling power to the lights connected to the circuit."
	icon = 'icons/obj/power_breaker.dmi'
	icon_state = "light1"
	on = 0


/// area (a relation view: it reads null once the target is deleted).
/obj/machinery/light_switch/proc/area() as /area
	return area
