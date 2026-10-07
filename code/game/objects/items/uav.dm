#define UAV_OFF 0
#define UAV_ON 1
#define UAV_PAIRING 2
#define UAV_PACKED 3

/obj/item/uav
	name = "recon skimmer"
	desc = "A semi-portable reconnaissance drone that folds into a backpack-sized carrying case."
	icon = 'icons/obj/uav.dmi'
	icon_state = "uav"

	var/obj/item/cell/cell
	var/cell_type = null //Can put a starting cell here

	density = TRUE //Is dense, but not anchored, so you can swap with it
	slowdown = 1.5 //Heevvee.

	max_integrity = 100

	light_system = MOVABLE_LIGHT_DIRECTIONAL
	light_cone_y_offset = 5
	light_range = 4
	light_power = 4
	var/power_per_process = 50 // About 6.5 minutes of use on a high-cell (10,000)

	var/datum/effect/effect/system/ion_trail_follow/ion_trail

	// The mobs flying it are UAV_MASTERS(src) (the uav_master relation).

	// So you know which is which
	var/nickname = "Unnamed UAV"

	// Radial menu
	var/static/image/radial_pickup = image(icon = 'icons/mob/radial.dmi', icon_state = "radial_pickup")
	var/static/image/radial_wrench = image(icon = 'icons/mob/radial.dmi', icon_state = "radial_wrench")
	var/static/image/radial_power = image(icon = 'icons/mob/radial.dmi', icon_state = "radial_power")
	var/static/image/radial_pair = image(icon = 'icons/mob/radial.dmi', icon_state = "radial_pair")

	// Movement cooldown
	EXPIRY_DECLARE(next_move)

	// Idle shutdown time
	var/no_masters_time = 0

CAPABILITIES(/obj/item/uav)
	every(2 SECONDS, then(PROC_REF(uav_step)), when = PROC_REF(is_flying))
	owns_one(nameof(cell), /obj/item/cell)
	owns_one(nameof(ion_trail), /datum/effect/effect/system/ion_trail_follow, starts = /datum/effect/effect/system/ion_trail_follow)
	op("use_screwdriver", tool(TOOL_SCREWDRIVER), wait(0), then(PROC_REF(screwdriver_used)))
	// the old attack_hand: on the floor, a radial of what to do with it (elsewhere the click declines to the ordinary hand)
	op("handle", hand(), label("Handle"),
		asks(/datum/prompt/choice, fields = list("choices" = computed(PROC_REF(handle_options)), "radial" = TRUE, "autopick_single_option" = TRUE, "timeout" = 0), when = PROC_REF(uav_on_floor)),
		then(PROC_REF(option_chosen)))
	// the old attackby: a pairing computer pairs it, a cell goes in
	op("item", item(/obj/item), label("Use"), then(PROC_REF(interaction_item)))
	// a pen writes its nickname
	op("nickname", inputs(item(/obj/item/pen), item(/obj/item/flashlight/pen)), label("Nickname"), priority(OP_PRIORITY_PART + 1),
		asks(/datum/prompt/text, fields = list("title" = "Nickname", "question" = computed(PROC_REF(nickname_question)), "default" = computed(PROC_REF(current_nickname)), "max_len" = MAX_NAME_LEN, "name_text" = TRUE, "timeout" = 0)),
		then(PROC_REF(nickname_entered)))

/obj/item/uav/loaded
	cell_type = /obj/item/cell/high

/obj/item/uav/Initialize(mapload)
	. = ..()

	if(!cell && cell_type)
		rel_set(src, nameof(cell), new cell_type) // ALLOW(decl): made in nullspace, not in src

	ion_trail.set_up(src)
	ion_trail.stop()


/obj/item/uav/examine(mob/user)
	. = ..()
	if(Adjacent(user))
		. += "It has <i>'[nickname]'</i> scribbled on the side."
	if(!cell)
		. += span_warning("It appears to be missing a power cell.")

	if(get_integrity() <= (max_integrity/4))
		. += span_warning("It looks like it might break at any second!")
	else if(get_integrity() <= (max_integrity/2))
		. += span_warning("It looks pretty beaten up...")

/obj/item/uav/proc/uav_on_floor(datum/act/op/A)
	return lies_on_floor(src)

/obj/item/uav/proc/handle_options(datum/act/op/A)
	return list(
		"Pick Up" = radial_pickup,
		"(Dis)Assemble" = radial_wrench,
		"Toggle Power" = radial_power,
		"Pairing Mode" = radial_pair)

/obj/item/uav/proc/nickname_question(datum/act/op/A)
	return "Enter a nickname for [src]"

/obj/item/uav/proc/current_nickname(datum/act/op/A)
	return nickname

/// Old attack_hand: the radial's choice (it has to be on the ground to work with it properly).
/obj/item/uav/proc/option_chosen(datum/act/op/A)
	if(!isturf(loc))
		return OP_DECLINE
	var/mob/user = A.actor
	var/datum/prompt/R = A.answer
	if(!R?.value || user.incapacitated())
		return OP_OK
	switch(R.value)
		// Can pick up when off or packed
		if("Pick Up")
			if(state == UAV_OFF || state == UAV_PACKED)
				// The standard hand pickup (the item's "Pick up" interaction), with all its checks.
				if(isliving(user) && user.Adjacent(src))
					pick_up_by_hand(user)
			else
				to_chat(user,span_warning("Turn [nickname] off or pack it first!"))
		// Can disasemble or reassemble from packed or off (and this one takes time)
		if("(Dis)Assemble")
			if(can_transition_to(state == UAV_PACKED ? UAV_OFF : UAV_PACKED, user))
				act_message(user, src, MSG_SELF(span_info("You start [state == UAV_PACKED ? "unpacking" : "packing"] [src].")), MSG_OTHERS(span_infoplain(span_bold("%U%") + " starts [state == UAV_PACKED ? "unpacking" : "packing"] [src].")))
				task_timed(user, 10 SECONDS, target = src, receiver = src, on_done = PROC_REF(attack_hand_timed_done), done_args = list(user))
		// Can toggle power from on and off
		if("Toggle Power")
			if(can_transition_to(state == UAV_ON ? UAV_OFF : UAV_ON, user))
				toggle_power(user)
		// Can pair when off
		if("Pairing Mode")
			if(can_transition_to(state == UAV_PAIRING ? UAV_OFF : UAV_PAIRING, user))
				toggle_pairing(user)
	return OP_OK

/obj/item/uav/proc/attack_hand_timed_done(mob/user)
	return toggle_packed(user)

/// Old attackby.
/obj/item/uav/proc/interaction_item(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/I = A.held
	if(istype(I, /obj/item/modular_computer) && state == UAV_PAIRING)
		var/obj/item/modular_computer/MC = I
		rel_add(MC, nameof(MC.paired_uavs), src)
		play_sfx(src, SFX_MACHINES_BUTTONBEEP)
		act_message(user, src, others = span_notice("%U% pairs [I] to [nickname]"))
		toggle_pairing()

	else if(istype(I, /obj/item/cell) && !cell)
		task_timed(user, 3 SECONDS, target = src, receiver = src, on_done = PROC_REF(attackby_timed_done), done_args = list(I, user))

	else
		return OP_DECLINE
	return OP_PASS

/obj/item/uav/proc/nickname_entered(datum/act/op/A)
	var/datum/prompt/R = A.answer
	if(!R)
		return OP_PASS
	var/mob/user = A.actor
	var/tmp_label = R.value
	if(length(tmp_label) > 50 || length(tmp_label) < 3)
		to_chat(user, span_notice("The nickname must be between 3 and 50 characters."))
	else
		to_chat(user, span_notice("You scribble your new nickname on the side of [src]."))
		nickname = tmp_label
		desc = initial(desc) + " This one has "  + span_notice("'[nickname]'") + " scribbled on the side."
	return OP_PASS

/obj/item/uav/proc/attackby_timed_done(obj/item/I, mob/user)
	to_chat(user, span_notice("You insert [I] into [nickname]."))
	play_sfx(src, SFX_ITEMS_DECONSTRUCT)
	power_down()
	move_into(src, nameof(src.cell), I, user)

/obj/item/uav/proc/screwdriver_used(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/tool = A.held
	if(!cell)
		return OP_OK
	task_timed(user, 3 SECONDS, target = src, receiver = src, on_done = PROC_REF(screwdriver_act_timed_done), done_args = list(user, tool))
	return OP_OK

/obj/item/uav/proc/screwdriver_act_timed_done(mob/user, obj/item/tool)
	if(!(cell))
		return
	to_chat(user, span_notice("You remove [cell] from [nickname]."))
	playsound(src, tool.usesound, 50, 1)
	power_down()
	cell.forceMove(get_turf(src))
	rel_take(src, nameof(cell))

/obj/item/uav/proc/can_transition_to(new_state, mob/user)
	switch(state) //Current one
		if(UAV_ON)
			if(new_state == UAV_OFF || new_state == UAV_PACKED)
				. = TRUE
		if(UAV_OFF)
			if(new_state == UAV_ON || new_state == UAV_PACKED || new_state == UAV_PAIRING)
				. = TRUE
		if(UAV_PAIRING)
			if(new_state == UAV_OFF)
				. = TRUE
		if(UAV_PACKED)
			if(new_state == UAV_OFF)
				. = TRUE

	if(!.)
		if(user)
			to_chat(user, span_warning("You can't do that while [nickname] is in this state."))
		return FALSE

/obj/item/uav/proc/appearance_uav_suffix()
	switch(state)
		if(UAV_ON)
			return "_on"
		if(UAV_PACKED)
			return "_packed"
	return ""

/// The look (the draw sweep: from its template and its layers).
/obj/item/uav/draw(datum/look/look)
	..()
	look.state("[initial(icon_state)][appearance_uav_suffix()]")
	if(state == 2)
		look.overlay("uav_pairing")

// "2" is UAV_PAIRING.

/obj/item/uav/var/state = UAV_OFF
TRACKED(/obj/item/uav, state)

/// Whether it flies (the every() gate, polled).
/obj/item/uav/proc/is_flying(datum/act/A)
	return state == UAV_ON

/// Drains its cell and watches for masters every 2 s while flying.
/obj/item/uav/proc/uav_step(datum/act/timer/A)
	if(cell?.use(power_per_process) != power_per_process)
		visible_message(span_warning("[src] sputters and thuds to the ground, inert."))
		play_sfx(src, SFX_ITEMS_DROP_METALBOOTS)
		power_down()
		take_damage(max_integrity*0.25, sound_effect = FALSE) //Lose 25% of your original health

	if(length(src?.uav_masters()))
		no_masters_time = 0
	else if(no_masters_time++ > 50)
		power_down()

/obj/item/uav/proc/toggle_pairing()
	switch(state)
		if(UAV_PAIRING)
			set_state(UAV_OFF)
			return TRUE
		if(UAV_OFF)
			set_state(UAV_PAIRING)
			return TRUE
	return FALSE

/obj/item/uav/proc/toggle_power()
	switch(state)
		if(UAV_OFF)
			power_up()
			return TRUE
		if(UAV_ON)
			power_down()
			return TRUE
	return FALSE

/obj/item/uav/proc/toggle_packed()
	if(state == UAV_ON)
		power_down()
	switch(state)
		if(UAV_OFF) //Packing
			set_state(UAV_PACKED)
			w_class = ITEMSIZE_LARGE
			slowdown = 0.5
			set_density(FALSE)
			return TRUE
		if(UAV_PACKED) //Unpacking
			set_state(UAV_OFF)
			w_class = ITEMSIZE_HUGE
			slowdown = 1.5
			set_density(TRUE)
			return TRUE
	return FALSE

/obj/item/uav/proc/power_up()
	if(state != UAV_OFF || !isturf(loc))
		return
	if(cell?.use(power_per_process) != power_per_process)
		visible_message(span_warning("[src] sputters and chugs as it tries, and fails, to power up."))
		return

	set_state(UAV_ON)
	start_hover()
	set_light_on(TRUE)
	no_masters_time = 0
	visible_message(span_notice("[nickname] buzzes and lifts into the air."))

/obj/item/uav/proc/power_down()
	if(state != UAV_ON)
		return

	set_state(UAV_OFF)
	stop_hover()
	set_light_on(FALSE)
	clear_masters()
	visible_message(span_notice("[nickname] gracefully settles onto the ground."))

//////////////// Helpers
/obj/item/uav/get_cell()
	return cell

/obj/item/uav/relaymove(mob/user, direction, signal = 1)
	if(signal && state == UAV_ON && (user in src?.uav_masters()))
		if(COOLDOWN_FINISHED(src, next_move))
			EXPIRY_SET(src, next_move, (1 SECOND/signal), CLOCK_WORLD)
			step(src, direction)
		return TRUE // Even if we couldn't step, we're taking credit for absorbing the move
	return FALSE

/obj/item/uav/proc/get_status_string()
	return "[nickname] - [get_x(src)],[get_y(src)],[get_z(src)] - I:[get_integrity()]/[max_integrity] - C:[cell ? "[cell.charge]/[cell.maxcharge]" : "Not Installed"]"

/obj/item/uav/proc/add_master(mob/living/M)
	om_link(M, src, /datum/om/relation/uav_master)

/obj/item/uav/proc/remove_master(mob/living/M)
	om_unlink(M, src, /datum/om/relation/uav_master)

/obj/item/uav/proc/clear_masters()
	for(var/mob/living/M as anything in src?.uav_masters())
		remove_master(M)

/obj/item/uav/proc/start_hover()
	if(!ion_trail.on) //We'll just use this to store if we're floating or not
		ion_trail.start()
		var/amplitude = 2 //maximum displacement from original position
		var/period = 36 //time taken for the mob to go up >> down >> original position, in deciseconds. Should be multiple of 4

		var/top = old_y + amplitude
		var/bottom = old_y - amplitude
		var/half_period = period / 2
		var/quarter_period = period / 4

		animate(src, pixel_y = top, time = quarter_period, easing = SINE_EASING | EASE_OUT, loop = -1)		//up
		animate(pixel_y = bottom, time = half_period, easing = SINE_EASING, loop = -1)						//down
		animate(pixel_y = old_y, time = quarter_period, easing = SINE_EASING | EASE_IN, loop = -1)			//back

/obj/item/uav/proc/stop_hover()
	if(ion_trail.on)
		ion_trail.stop()
		animate(src, pixel_y = old_y, time = 5, easing = SINE_EASING | EASE_IN) //halt animation

/obj/item/uav/hear_talk(mob/M, list/message_pieces, verb)
	var/name_used = M.GetVoice()
	for(var/mob/master as anything in src?.uav_masters())
		var/list/combined = master.combine_message(message_pieces, verb, M)
		var/message = combined["formatted"]
		var/rendered = span_game(span_say(span_italics("UAV received: " + span_name("[name_used]") + " [message]")))
		master.show_message(rendered, 2)

/obj/item/uav/see_emote(mob/living/M, text)
	for(var/mob/master as anything in src?.uav_masters())
		var/rendered = span_game(span_say(span_italics("UAV received, " + span_message("[text]"))))
		master.show_message(rendered, 2)

/obj/item/uav/show_message(msg, type, alt, alt_type)
	for(var/mob/master as anything in src?.uav_masters())
		var/rendered = span_game(span_say(span_italics("UAV received, " + span_message("[msg]"))))
		master.show_message(rendered, type)

/obj/item/uav/atom_destruction(damage_flag)
	. = ..()
	die()

/obj/item/uav/proc/die()
	visible_message(span_danger("[src] shorts out and explodes!"))
	power_down()
	var/turf/T = get_turf(src)
	destroyed(src)
	explosion(T, -1, 0, 1, 2) //Not very large

#undef UAV_OFF
#undef UAV_ON
#undef UAV_PAIRING
#undef UAV_PACKED
