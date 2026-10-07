/obj/machinery/reagent_refinery/mixer
	name = "Industrial Chemical Mixer"
	desc = "A large mixing machine. Each input is only fed into the mixer once during each rotation."
	icon_state = "mixer"
	density = TRUE
	anchored = TRUE
	use_power = USE_POWER_IDLE
	idle_power_usage = 0
	active_power_usage = 50
	circuit = /obj/item/circuitboard/industrial_reagent_mixer
	default_max_vol = 240 // Two large beakers of volume
	var/mixer_angle = 0
	var/mixer_rotation_rate = 45
	var/got_input = FALSE
TRACKED(/obj/machinery/reagent_refinery/mixer, got_input)
TRACKED(/obj/machinery/reagent_refinery/mixer, mixer_angle)

/obj/machinery/reagent_refinery/mixer/Initialize(mapload)
	set_mixer_angle(dir2angle(dir))
	. = ..()
	default_apply_parts()

/obj/machinery/reagent_refinery/mixer/refinery_step()
	if(!anchored)
		return

	power_change()
	if(!operable())
		return

	// Drain it!
	if(mixer_angle == dir2angle(dir))
		refinery_transfer()
		if(reagents.total_volume <= 0)
			set_mixer_angle(mixer_angle + (mixer_rotation_rate))
			set_mixer_angle((360 + mixer_angle) % 360)
			changed(src)
		set_got_input(FALSE)
		return

	// Check if we were filled...
	if(mixer_angle % 90 != 0) // Not cardinal, keep going
		set_got_input(TRUE)
	else if(!(locate_within(get_step(src,angle2dir(mixer_angle)), /obj/machinery/reagent_refinery))) // If nothing, keep rotating
		set_got_input(TRUE)

	if(!got_input)
		return
	set_mixer_angle(mixer_angle + (mixer_rotation_rate))
	set_mixer_angle((360 + mixer_angle) % 360)
	changed(src)
	set_got_input(FALSE)

/obj/machinery/reagent_refinery/mixer/draw(datum/look/look)
	..()
	// GOOBY!
	if(reagents && reagents.total_volume >= 5)
		var/percent = (reagents.total_volume / reagents.maximum_volume) * 100
		switch(percent)
			if(5 to 20) percent = 2
			if(20 to 40) percent = 4
			if(40 to 60) percent = 6
			if(60 to 80) percent = 8
			if(80 to INFINITY) percent = 10
		look.overlay(look_overlay_image(icon, "mixer_r_[percent]", color = reagents.get_color(), dir = dir))
	// Get main dir pipe
	look.overlay(look_overlay_image(icon, "mixer_cons", dir = dir))
	if(anchored)
		if(operable())
			look.overlay(look_overlay_image(icon, "mixer_dot_[ got_input ? "on" : "off" ]"))
		look.overlay(update_input_connection_overlays("mixer_intakes"))
	// Get mixer overlay
	look.overlay(look_overlay_image(icon, "mixer_arm", dir = angle2dir(mixer_angle)))

/obj/machinery/reagent_refinery/mixer/proc/interaction_set_rotation(datum/act/op/A)
	var/mob/user = A.actor
	if(mixer_rotation_rate > 0)
		mixer_rotation_rate = -45
		to_chat(user,span_notice("You set \the [src] to rotate counter clockwise."))
	else
		mixer_rotation_rate = 45
		to_chat(user,span_notice("You set \the [src] to rotate clockwise."))
	return OP_OK

/obj/machinery/reagent_refinery/mixer/examine(mob/user, infix, suffix)
	. = ..()
	. += "The meter shows [reagents.total_volume]u / [reagents.maximum_volume]u. It is pumping chemicals at a rate of [amount_per_transfer_from_this]u."
	tutorial(REFINERY_TUTORIAL_SINGLEOUTPUT, .)

/obj/machinery/reagent_refinery/mixer/handle_transfer(atom/origin_machine, datum/reagents/RT, source_forward_dir, transfer_rate, filter_id = "")
	// no back/forth, filters don't use just their forward, they send the side too!
	if(mixer_angle % 90 != 0) // Only handle proper directions
		return 0
	if(got_input) // Only ONCE per direction
		return 0
	if(dir == GLOB.reverse_dir[source_forward_dir])
		return 0
	if(get_turf(origin_machine) != get_step(src,angle2dir(mixer_angle))) // Check if the mixer arm is pointing at the machine too!
		return 0

	. = ..(origin_machine, RT, source_forward_dir, transfer_rate, filter_id)

	// If we transfered anything, then inform process() of it!
	if(.)
		set_got_input(TRUE)
		changed(src)

/// Busy while it turns between inputs; it waits (asleep) facing an input until reagents arrive.
/obj/machinery/reagent_refinery/mixer/refinery_busy()
	if(mixer_angle == dir2angle(dir))
		return reagents.total_volume <= 0
	if(mixer_angle % 90)
		return TRUE
	if(!(locate_within(get_step(src, angle2dir(mixer_angle)), /obj/machinery/reagent_refinery)))
		return TRUE
	return got_input

CAPABILITIES(/obj/machinery/reagent_refinery/mixer)
	without("reagent_refinery_set_transfer_amount")
	op("set_rotation", hand(), ungated(), priority(OP_PRIORITY_DEFAULT - 1), label("Use"), then(PROC_REF(interaction_set_rotation)))
	op("set_rotation_2", menu(), label("Set Mixer Rotation"), needs(req_adjacent(), req_capable()), then(PROC_REF(interaction_set_rotation)))
