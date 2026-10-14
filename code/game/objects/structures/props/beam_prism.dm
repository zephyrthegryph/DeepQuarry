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
	var/interaction_sound = SFX_MECHA_MECHMOVE04

	var/redirect_type = /obj/item/projectile/beam

	var/dialID = null
	var/obj/structure/prop/prismcontrol/remote_dial = null

	interaction_message = span_notice("The prismatic turret seems to be able to rotate.")

/obj/structure/prop/prism/Initialize(mapload)
	. = ..()
	if(degrees_from_north)
		animate(src, transform = turn(NORTH, degrees_from_north), time = 3)

CAPABILITIES(/obj/structure/prop/prism)
	links(/obj/structure/prop/prism::remote_dial, /obj/structure/prop/prismcontrol::my_turrets, b_many = TRUE)
	// the old attack_hand: a yes/no, then a bearing (free rotation) or a compass point, then the prism turns
	op("rotate", hand(), label("Rotate"), needs(req_is(nameof(rotation_lock), FALSE, because = MSG(prism/locked)), req_is(nameof(external_control_lock), FALSE, because = MSG(prism/external))),
		asks(/datum/prompt/yes_no, fields = list("title" = "name", "question" = computed(PROC_REF(rotate_question)), "timeout" = 0), step = "sure"),
		asks(/datum/prompt/number, fields = list("title" = "name", "question" = computed(PROC_REF(bearing_question)), "min_value" = 0, "max_value" = 360, "timeout" = 0), step = "bearing", when = PROC_REF(said_yes_free)),
		asks(/datum/prompt/choice, fields = list("title" = "name", "question" = computed(PROC_REF(point_question)), "choices" = computed(PROC_REF(compass_choices)), "timeout" = 0), step = "point", when = PROC_REF(said_yes_points)),
		then(PROC_REF(rotate_chosen)))
	without("message")   // the rotation shows the message itself

/obj/structure/prop/prism/proc/reset_rotation()
	var/degrees_to_rotate = -1 * degrees_from_north
	animate(src, transform = turn(src.transform, degrees_to_rotate), time = 2)

// The original attack_hand called ..() (prop's message display) unconditionally, then always
// continued into its own rotate prompt below, so prism_rotate() shows the message itself
// instead of also offering prop_hand (which would tie with it and open the Menu).
// Rotating a prism or prism controller (shared by both): standing next to it throughout.

/// The prism's question text: what it asks before it turns.
/obj/structure/prop/prism/proc/rotate_question(datum/act/A)
	return "Do you want to try to rotate \the [src]?"

/obj/structure/prop/prism/proc/bearing_question(datum/act/A)
	return "What bearing do you want to rotate \the [src] to?"

/obj/structure/prop/prism/proc/point_question(datum/act/A)
	return "What point do you want to set \the [src] to?"

/obj/structure/prop/prism/proc/compass_choices(datum/act/A)
	return assoc_to_keys(prism_compass_points())

/// The first answer was yes.
/obj/structure/prop/prism/proc/said_yes(datum/act/op/A)
	var/datum/prompt/R = A.step_answers?["sure"]
	return !!R?.value

/obj/structure/prop/prism/proc/said_yes_free(datum/act/op/A)
	return free_rotate && said_yes(A)

/obj/structure/prop/prism/proc/said_yes_points(datum/act/op/A)
	return !free_rotate && said_yes(A)

/// Old attack_hand: the prism is turned by hand to a bearing (or a compass point) the actor picks.
/obj/structure/prop/prism/proc/rotate_chosen(datum/act/op/A)
	var/mob/living/user = A.actor
	if(!said_yes(A))
		act_message(user, src, MSG_SELF(span_notice("You decide not to try turning %T%.")), \
			MSG_OTHERS(span_notice("%U% decides not to try turning %T%.")))
		return OP_OK
	var/datum/prompt/R = A.answer
	if(isnull(R?.value))
		return OP_OK
	rotate_to(user, free_rotate ? R.value : prism_compass_points()[R.value])
	return OP_OK

MSG_DEF_SELF(prism/locked, "It is locked at its current bearing.")
MSG_DEF_SELF(prism/external, "Its motors resist your efforts to rotate it. You may need to find some form of controller.")

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
		after(src, 0.3 SECONDS, PROC_REF(rotate_second_stage), with = list(rotate_degrees))
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
		after(src, 0.3 SECONDS, PROC_REF(rotate_second_stage), with = list(rotate_degrees))
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

/// The eight compass points a prism that turns by points takes, by name, with their bearings.
GLOBAL_LIST_INIT(prism_compass_points, list("North" = 0, "South" = 180, "East" = 90, "West" = 270, "Northwest" = 315, "Northeast" = 45, "Southeast" = 135, "Southwest" = 225))

/proc/prism_compass_points()
	READS_FROM() // a fixed table
	return GLOB.prism_compass_points

/// The compass points the linked prisms share out when any of them turns only by points; null when all of them take any bearing.
/obj/structure/prop/prismcontrol/proc/compass_points()
	for(var/obj/structure/prop/prism/PR in my_turrets)
		if(!PR.free_rotate) //Doesn't use bearing, it uses compass points.
			return prism_compass_points() // every prism shares the one compass
	return null

/obj/structure/prop/prismcontrol/proc/rotate_question(datum/act/A)
	return "Do you want to try to rotate \the [src]?"

/obj/structure/prop/prismcontrol/proc/bearing_question(datum/act/A)
	return "What bearing do you want to rotate \the [src] to?"

/obj/structure/prop/prismcontrol/proc/point_question(datum/act/A)
	return "What point do you want to set \the [src] to?"

/obj/structure/prop/prismcontrol/proc/final_question(datum/act/A)
	return "Are you certain you want to rotate \the [src]?"

/obj/structure/prop/prismcontrol/proc/compass_choices(datum/act/A)
	return assoc_to_keys(compass_points())

/// Yes, and there are prisms on the dial.
/obj/structure/prop/prismcontrol/proc/said_yes(datum/act/op/A)
	var/datum/prompt/R = A.step_answers?["sure"]
	return R?.value && length(my_turrets)

/obj/structure/prop/prismcontrol/proc/said_yes_free(datum/act/op/A)
	return said_yes(A) && !compass_points()

/obj/structure/prop/prismcontrol/proc/said_yes_points(datum/act/op/A)
	return said_yes(A) && compass_points()

/// The bearing the dial would turn to: the number entered, or the compass point's bearing; null when none.
/obj/structure/prop/prismcontrol/proc/chosen_bearing(datum/act/op/A)
	var/datum/prompt/number = A.step_answers?["bearing"]
	if(!isnull(number?.value))
		return round(number.value)
	var/datum/prompt/point = A.step_answers?["point"]
	if(!isnull(point?.value))
		var/list/compass_directions = compass_points()
		var/bearing = compass_directions?[point.value]
		return isnull(bearing) ? null : round(bearing)
	return null

/// A bearing worth turning to was chosen: the last question is asked.
/obj/structure/prop/prismcontrol/proc/bearing_sane(datum/act/op/A)
	var/bearing = chosen_bearing(A)
	return !isnull(bearing) && bearing > -1 && bearing <= 360

/// Old attack_hand: the dial turns every linked prism to the bearing (or compass point) the actor picks, after a last yes.
/obj/structure/prop/prismcontrol/proc/rotate_chosen(datum/act/op/A)
	var/mob/living/user = A.actor
	var/datum/prompt/sure = A.step_answers?["sure"]
	if(!sure?.value)
		act_message(user, src, MSG_SELF(span_notice("You decide not to try turning %T%.")), \
			MSG_OTHERS(span_notice("%U% decides not to try turning %T%.")))
		return OP_OK
	if(!length(my_turrets))
		to_chat(user, span_notice("\The [src] doesn't seem to do anything."))
		return OP_OK
	var/new_bearing = chosen_bearing(A)
	if(isnull(new_bearing))
		return OP_OK
	if(!bearing_sane(A))
		to_chat(user, span_warning("Rotating \the [src] [new_bearing] degrees would be a waste of time."))
		return OP_OK
	var/datum/prompt/final = A.step_answers?["final"]
	if(!final?.value)
		act_message(user, src, MSG_SELF(span_notice("You decide not to try turning %T%.")), \
			MSG_OTHERS(span_notice("%U% decides not to try turning %T%.")))
		return OP_OK
	to_chat(user, span_notice("\The [src] clicks into place."))
	for(var/obj/structure/prop/prism/PR in my_turrets)
		PR.rotate_auto(new_bearing)
	return OP_OK

/obj/structure/prop/prismcontrol/Initialize(mapload)
	. = ..()
	if(length(my_turrets)) //Preset controls.
		for(var/obj/structure/prop/prism/P in my_turrets)
			rel_set(P, nameof(P.remote_dial), src)

CAPABILITIES(/obj/structure/prop/prismcontrol)
	after_init(0, then(PROC_REF(find_turrets)))
	// the old attack_hand: a yes/no, a bearing (or a compass point when a linked prism turns by points), a last yes, then every linked prism turns
	op("rotate", hand(), label("Rotate"),
		asks(/datum/prompt/yes_no, fields = list("title" = "name", "question" = computed(PROC_REF(rotate_question)), "timeout" = 0), step = "sure"),
		asks(/datum/prompt/number, fields = list("title" = "name", "question" = computed(PROC_REF(bearing_question)), "min_value" = 0, "max_value" = 360, "timeout" = 0), step = "bearing", when = PROC_REF(said_yes_free)),
		asks(/datum/prompt/choice, fields = list("title" = "name", "question" = computed(PROC_REF(point_question)), "choices" = computed(PROC_REF(compass_choices)), "timeout" = 0), step = "point", when = PROC_REF(said_yes_points)),
		asks(/datum/prompt/yes_no, fields = list("title" = "name", "question" = computed(PROC_REF(final_question)), "timeout" = 0), step = "final", when = PROC_REF(bearing_sane)),
		then(PROC_REF(rotate_chosen)))
	without("message")   // the rotation shows the message itself

/// A control without preset turrets takes the nearby prisms on its dial.
/obj/structure/prop/prismcontrol/proc/find_turrets(datum/act/timer/A)
	if(length(my_turrets))
		return // preset controls set their turrets up in Initialize()
	for(var/obj/structure/prop/prism/P in orange(src, world.view)) //Don't search a huge area.
		if(P.dialID == dialID && !P.remote_dial && P.external_control_lock)
			rel_add(src, nameof(my_turrets), P) // the pair sets P.remote_dial

/// The second half of a two-stage turn.
/obj/structure/prop/prism/proc/rotate_second_stage(rotate_degrees)
	animate(src, transform = turn(src.transform, rotate_degrees), time = 3)
