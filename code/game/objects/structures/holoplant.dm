/obj/machinery/holoplant
	name = "holoplant"
	desc = "One of those Ward-Takahashi holoplants! Give your space a bit of the comfort of being outdoors, by buying this blue buddy. A rugged case guarantees that your flower will outlive you, and variety of plant types won't let you to get bored along the way!"
	icon = 'icons/obj/holoplants.dmi'
	icon_state = "holopot"
	light_color = "#3C94C5"
	anchored = TRUE
	idle_power_usage = 0
	active_power_usage = 5
	maintenance_flags = MACHINE_MAINT_WRENCH
	maintenance_wrench_time = 1 SECOND
	var/interference = FALSE
	var/icon/plant = null

/obj/machinery/holoplant/Initialize(mapload)
	. = ..()
	activate()

/// Old attack_hand: switch the projection on or off (not while it flickers).
/obj/machinery/holoplant/proc/interaction_toggle(datum/act/op/A)
	var/mob/living/user = A.actor
	if(!istype(user) || interference)
		return OP_OK

	if(!plant)
		activate()
	else
		deactivate()
	return OP_OK

/// Anchored or loosened (the machine's wrench), the projection goes out.
/obj/machinery/holoplant/proc/anchoring_changed(datum/act/A)
	deactivate()

/obj/machinery/holoplant/proc/activate()
	if(!anchored || !operable())
		return

	plant = prepare_icon(emagged() ? "emagged" : null)
	cut_overlays()
	add_overlay(plant)
	set_light(2)
	set_use_power(USE_POWER_ACTIVE)

/obj/machinery/holoplant/proc/deactivate()
	cut_overlays()
	QDEL_NULL(plant)
	set_light(0)
	set_use_power(USE_POWER_OFF)

/obj/machinery/holoplant/power_change()
	. = ..()
	if(power_lost())
		deactivate()
	else
		activate()

/obj/machinery/holoplant/proc/flicker()
	interference = TRUE
	flicker_step(1)

/obj/machinery/holoplant/proc/flicker_step(n)
	if(n % 2)
		cut_overlays()
		set_light(0)
	else
		add_overlay(plant)
		set_light(2)
	if(n >= 4)
		interference = FALSE
		return
	after(src, rand(0.2 SECONDS, 0.4 SECONDS), PROC_REF(flicker_step), with = list(n + 1))

/obj/machinery/holoplant/proc/prepare_icon(state)
	if(!state)
		state = pick(GLOB.possible_plants)
	var/plant_icon = icon(icon, state)
	return getHologramIcon(plant_icon, 0)

CAPABILITIES(/obj/machinery/holoplant)
	on_change(nameof(anchored), ANY, then(PROC_REF(anchoring_changed)))
	emag(then(PROC_REF(on_emag)))
	op("toggle", hand(), label("Toggle"), needs(req_is(nameof(anchored), TRUE, because = MSG(holoplant/unanchored))), then(PROC_REF(interaction_toggle)))

MSG_DEF_SELF(holoplant/unanchored, "It must be anchored before activation.")

/// The sequencer swaps the plant for the corrupted one.
/obj/machinery/holoplant/proc/on_emag(datum/act/op/A)
	set_emagged(TRUE)
	if(plant)
		deactivate()
	activate()
	return OP_OK

/obj/machinery/holoplant/Crossed(mob/living/L)
	if(!interference && plant && istype(L))
		flicker()


/obj/machinery/holoplant/shipped
	anchored = FALSE

