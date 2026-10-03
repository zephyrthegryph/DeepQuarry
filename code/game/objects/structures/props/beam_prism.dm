//A series(?) of prisms for PoIs. The base one only works for beams.

/obj/structure/prop/prism
	name = "prismatic turret"
	desc = "A raised, externally powered 'turret'. It seems to have a massive crystal ring around its base."
	icon = 'icons/obj/props/prism.dmi'
	icon_state = "prism"
	density = TRUE
	anchored = TRUE

	layer = 3.1					//Layer over projectiles.
	plane = -10					//Layer over projectiles.

	var/rotation_lock = 0		// Can you rotate the prism at all?
	var/free_rotate = 1			// Does the prism rotate in any direction, or only in the eight standard compass directions?
	var/external_control_lock = 0	// Does the prism only rotate from the controls of an external switch?
	var/degrees_from_north = 0	// How far is it rotated clockwise?
	var/compass_directions = list("North" = 0, "South" = 180, "East" = 90, "West" = 270, "Northwest" = 315, "Northeast" = 45, "Southeast" = 135, "Southwest" = 225)
	var/interaction_sound = SFX_MECHA_MECHMOVE04

	var/redirect_type = /obj/item/projectile/beam

	var/dialID = null
	var/obj/structure/prop/prismcontrol/remote_dial = null

	interaction_message = span_notice("The prismatic turret seems to be able to rotate.")

/obj/structure/prop/prism/Initialize(mapload)
	. = ..()
	if(degrees_from_north)
		animate(src, transform = turn(NORTH, degrees_from_north), time = 3)

/obj/structure/prop/prism/relations()
	. = ..()
	. += rel_one(nameof(remote_dial), back = nameof(/obj/structure/prop/prismcontrol::my_turrets))
/obj/structure/prop/prismcontrol/relations()
	. = ..()
	. += rel_many(nameof(my_turrets), back = nameof(/obj/structure/prop/prism::remote_dial))

/obj/structure/prop/prism/proc/reset_rotation()
	var/degrees_to_rotate = -1 * degrees_from_north
	animate(src, transform = turn(src.transform, degrees_to_rotate), time = 2)

// The original attack_hand called ..() (prop's message display) unconditionally, then always
// continued into its own rotate prompt below, so prism_rotate() shows the message itself
// instead of also offering prop_hand (which would tie with it and open the Menu).
/obj/structure/prop/prism/declare_interactions(list/into)
	into += list(
		/datum/interaction/entry_hand/prism_rotate,
	)
	..()
	into -= /datum/interaction/entry_hand/prop_hand

/// Old attack_hand: manually rotate the prism to a chosen bearing.
/datum/interaction/entry_hand/prism_rotate
	id = "prism_rotate"
	name = "Rotate"
	effect = /obj/structure/prop/prism/proc/interaction_rotate

/obj/structure/prop/prism/proc/interaction_rotate(mob/living/user, obj/item/held, datum/interaction/interaction)
	if(interaction_message)
		to_chat(user, interaction_message)
	if(rotation_lock)
		to_chat(user, span_warning("\The [src] is locked at its current bearing."))
		return TRUE
	if(external_control_lock)
		to_chat(user, span_warning("\The [src]'s motors resist your efforts to rotate it. You may need to find some form of controller."))
		return TRUE

	om_ask(user, /datum/om/prompt/confirm/prism_rotate, PROC_REF(rotate_confirmed))
	return TRUE

/// Rotating a prism or prism controller (shared by both): standing next to it throughout.
/datum/om/prompt/confirm/prism_rotate
	answer_on_no = TRUE
	ask_flags = ASK_NEAR_SUBJECT | ASK_CAPABLE

/datum/om/prompt/confirm/prism_rotate/prepare()
	var/atom/A = subject
	title = "[A.name]"
	message = "Do you want to try to rotate \the [A]?"
	return TRUE

/datum/om/prompt/number/prism_bearing
	max = 360
	ask_flags = ASK_NEAR_SUBJECT | ASK_CAPABLE

/datum/om/prompt/number/prism_bearing/prepare()
	var/atom/A = subject
	title = "[A.name]"
	message = "What bearing do you want to rotate \the [A] to?"
	return TRUE

/// `choices` is a compass point -> bearing list.
/datum/om/prompt/choice/prism_point
	ask_flags = ASK_NEAR_SUBJECT | ASK_CAPABLE

/datum/om/prompt/choice/prism_point/prepare()
	var/atom/A = subject
	title = "[A.name]"
	message = "What point do you want to set \the [A] to?"
	return TRUE

/datum/om/prompt/confirm/prism_rotate_final
	answer_on_no = TRUE
	ask_flags = ASK_NEAR_SUBJECT | ASK_CAPABLE
	var/bearing

/datum/om/prompt/confirm/prism_rotate_final/prepare()
	var/atom/A = subject
	title = "[A.name]"
	message = "Are you certain you want to rotate \the [A]?"
	return TRUE

/obj/structure/prop/prism/proc/rotate_confirmed(datum/om/prompt/confirm/prism_rotate/ask)
	var/mob/living/user = ask.answerer
	if(!ask.yes)
		act_message(user, src, MSG_SELF(span_notice("You decide not to try turning %T%.")), \
			MSG_OTHERS(span_notice("%U% decides not to try turning %T%.")))
		return
	if(free_rotate)
		om_ask(user, /datum/om/prompt/number/prism_bearing, PROC_REF(bearing_entered))
	else
		om_ask(user, /datum/om/prompt/choice/prism_point, PROC_REF(rotate_to_point), choices = compass_directions)

/obj/structure/prop/prism/proc/rotate_to_point(datum/om/prompt/choice/prism_point/ask)
	rotate_to(ask.answerer, compass_directions[ask.choice])

/obj/structure/prop/prism/proc/bearing_entered(datum/om/prompt/number/prism_bearing/ask)
	rotate_to(ask.answerer, ask.number)

/obj/structure/prop/prism/proc/rotate_to(mob/living/user, new_bearing)
	if(rotation_lock || external_control_lock)
		return
	new_bearing = round(new_bearing)
	if(new_bearing <= -1 || new_bearing > 360)
		to_chat(user, span_warning("Rotating \the [src] [new_bearing] degrees would be a waste of time."))
		return

	var/rotate_degrees = new_bearing - degrees_from_north

	if(new_bearing == 360) // Weird artifact.
		new_bearing = 0
	degrees_from_north = new_bearing

	var/two_stage = 0
	if(rotate_degrees == 180 || rotate_degrees == -180)
		two_stage = 1
		var/multiplier = pick(-1, 1)
		rotate_degrees = multiplier * (rotate_degrees / 2)

	playsound(src, interaction_sound, 50, 1)
	if(two_stage)
		animate(src, transform = turn(src.transform, rotate_degrees), time = 3)
		after(src, 3, PROC_REF(rotate_second_stage), with = list(rotate_degrees))
	else
		animate(src, transform = turn(src.transform, rotate_degrees), time = 6) //Can't update transform because it will reset the angle.
	return TRUE

/obj/structure/prop/prism/proc/rotate_auto(new_bearing)
	if(rotation_lock)
		visible_message(span_infoplain(span_bold("\The [src]") + " shudders."))
		play_sfx(src, SFX_EFFECTS_CLANG, 2, extrarange = 0)
		return

	visible_message(span_infoplain(span_bold("\The [src]") + " rotates to a bearing of [new_bearing]."))

	var/rotate_degrees = new_bearing - degrees_from_north

	if(new_bearing == 360)
		new_bearing = 0
	degrees_from_north = new_bearing

	var/two_stage = 0
	if(rotate_degrees == 180 || rotate_degrees == -180)
		two_stage = 1
		var/multiplier = pick(-1, 1)
		rotate_degrees = multiplier * (rotate_degrees / 2)

	playsound(src, interaction_sound, 50, 1)
	if(two_stage)
		animate(src, transform = turn(src.transform, rotate_degrees), time = 3)
		after(src, 3, PROC_REF(rotate_second_stage), with = list(rotate_degrees))
	else
		animate(src, transform = turn(src.transform, rotate_degrees), time = 6)

/obj/structure/prop/prism/bullet_act(obj/item/projectile/Proj)
	if(istype(Proj, redirect_type))
		visible_message(span_danger("\The [src] redirects \the [Proj]!"))
		flick("[initial(icon_state)]+glow", src)

		var/new_x = (1 * round(10 * cos(degrees_from_north - 90))) + x //Vectors vectors vectors.
		var/new_y = (-1 * round(10 * sin(degrees_from_north - 90))) + y
		var/turf/curloc = get_turf(src)

		Proj.penetrating += 1 // Needed for the beam to get out of the turret.

		Proj.redirect(new_x, new_y, curloc, null)

/obj/structure/prop/prism/incremental
	free_rotate = 0

/obj/structure/prop/prism/incremental/externalcont
	external_control_lock = 1

/obj/structure/prop/prism/externalcont
	external_control_lock = 1

/obj/structure/prop/prismcontrol
	name = "prismatic dial"
	desc = "A large dial with a crystalline ring."
	icon = 'icons/obj/props/prism.dmi'
	icon_state = "dial"
	density = FALSE
	anchored = TRUE

	interaction_message = span_notice("The dial pulses as your hand nears it.")
	var/list/my_turrets
	var/dialID = null

/obj/structure/prop/prismcontrol/declare_interactions(list/into)
	into += list(
		/datum/interaction/entry_hand/prismcontrol_rotate,
	)
	..()
	into -= /datum/interaction/entry_hand/prop_hand

/// Old attack_hand: rotate every linked prism to a chosen bearing.
/datum/interaction/entry_hand/prismcontrol_rotate
	id = "prismcontrol_rotate"
	name = "Rotate"
	effect = /obj/structure/prop/prismcontrol/proc/interaction_rotate

/obj/structure/prop/prismcontrol/proc/interaction_rotate(mob/living/user, obj/item/held, datum/interaction/interaction)
	if(interaction_message)
		to_chat(user, interaction_message)
	om_ask(user, /datum/om/prompt/confirm/prism_rotate, PROC_REF(rotate_confirmed))
	return TRUE

/obj/structure/prop/prismcontrol/proc/rotate_confirmed(datum/om/prompt/confirm/prism_rotate/ask)
	var/mob/living/user = ask.answerer
	if(!ask.yes)
		act_message(user, src, MSG_SELF(span_notice("You decide not to try turning %T%.")), \
			MSG_OTHERS(span_notice("%U% decides not to try turning %T%.")))
		return TRUE

	if(!my_turrets || !length(my_turrets))
		to_chat(user, span_notice("\The [src] doesn't seem to do anything."))
		return TRUE

	var/free_rotate = 1
	var/list/compass_directions = list()
	for(var/obj/structure/prop/prism/PR in my_turrets)
		if(!PR.free_rotate) //Doesn't use bearing, it uses compass points.
			free_rotate = 0
			compass_directions |= PR.compass_directions

	if(free_rotate)
		om_ask(user, /datum/om/prompt/number/prism_bearing, PROC_REF(bearing_entered))
	else
		om_ask(user, /datum/om/prompt/choice/prism_point, PROC_REF(point_chosen), choices = compass_directions)

/obj/structure/prop/prismcontrol/proc/point_chosen(datum/om/prompt/choice/prism_point/ask)
	bearing_chosen(ask.answerer, ask.choices[ask.choice])

/obj/structure/prop/prismcontrol/proc/bearing_entered(datum/om/prompt/number/prism_bearing/ask)
	bearing_chosen(ask.answerer, ask.number)

/obj/structure/prop/prismcontrol/proc/bearing_chosen(mob/living/user, new_bearing)
	new_bearing = round(new_bearing)
	if(new_bearing <= -1 || new_bearing > 360)
		to_chat(user, span_warning("Rotating \the [src] [new_bearing] degrees would be a waste of time."))
		return
	om_ask(user, /datum/om/prompt/confirm/prism_rotate_final, PROC_REF(rotate_final), bearing = new_bearing)

/obj/structure/prop/prismcontrol/proc/rotate_final(datum/om/prompt/confirm/prism_rotate_final/ask)
	var/mob/living/user = ask.answerer
	if(!ask.yes)
		act_message(user, src, MSG_SELF(span_notice("You decide not to try turning %T%.")), \
			MSG_OTHERS(span_notice("%U% decides not to try turning %T%.")))
		return
	var/new_bearing = ask.bearing

	to_chat(user, span_notice("\The [src] clicks into place."))
	for(var/obj/structure/prop/prism/PR in my_turrets)
		PR.rotate_auto(new_bearing)

/obj/structure/prop/prismcontrol/Initialize(mapload)
	. = ..()
	if(length(my_turrets)) //Preset controls.
		for(var/obj/structure/prop/prism/P in my_turrets)
			rel_set(P, nameof(P.remote_dial), src)
	else
		. = INITIALIZE_HINT_LATELOAD

/obj/structure/prop/prismcontrol/LateInitialize()
	for(var/obj/structure/prop/prism/P in orange(src, world.view)) //Don't search a huge area.
		if(P.dialID == dialID && !P.remote_dial && P.external_control_lock)
			rel_add(src, nameof(my_turrets), P) // the pair sets P.remote_dial

/// The second half of a two-stage turn.
/obj/structure/prop/prism/proc/rotate_second_stage(rotate_degrees)
	animate(src, transform = turn(src.transform, rotate_degrees), time = 3)
