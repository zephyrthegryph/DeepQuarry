/obj/structure/reflector
	name = "reflector base"
	icon = 'icons/obj/structures/tgs_structures.dmi'
	icon_state = "reflector_map"
	desc = "A base for reflector assemblies."
	anchored = FALSE
	density = FALSE
	var/deflector_icon_state
	var/image/deflector_overlay
	var/finished = FALSE
	var/admin = FALSE //Can't be rotated or deconstructed
	var/can_rotate = TRUE
	var/framebuildstacktype = /obj/item/stack/material//metal
	var/framebuildstackamount = 5
	var/buildstacktype = /obj/item/stack/material//metal
	var/buildstackamount = 0
	var/fires_projectile = /obj/item/projectile/beam/emitter
	var/fires_accuracy = 10000
	var/fires_dispersion = 0
	var/list/allowed_projectile_typecache = list(/obj/item/projectile/beam) // ALLOW(instance_list): d: replaced per instance at runtime (2 assignments)
	var/rotation_angle = -1
	var/can_decon = TRUE
	var/list/has_projectiles // Lazy: caught beam damage, angle text -> summed damage (numbers; the beams themselves are deleted on catch)
	var/bullet_act_in_progress = FALSE
	/// Has it caught a beam it has yet to re-fire? The every() below runs while it has.
	var/refiring = FALSE

TRACKED(/obj/structure/reflector, refiring)
TRACKED(/obj/structure/reflector, finished)
TRACKED(/obj/structure/reflector, admin)

/// The look (the draw sweep: from its layers).
/obj/structure/reflector/draw(datum/look/look)
	..()
	look.state("reflector_base")

/obj/structure/reflector/Initialize(mapload)
	. = ..()
	allowed_projectile_typecache = typecacheof(allowed_projectile_typecache)
	if(deflector_icon_state)
		deflector_overlay = image(icon, deflector_icon_state)
		add_overlay(deflector_overlay)

	if(rotation_angle == -1)
		setAngle(dir2angle(dir))
	else
		setAngle(rotation_angle)

	if(admin)
		can_rotate = FALSE
		resistance_flags |= BOMB_PROOF

/obj/structure/reflector/examine(mob/user)
	. = ..()
	if(finished)
		. += "It is set to [rotation_angle] degrees, and the rotation is [can_rotate ? "unlocked" : "locked"]."
		if(!admin)
			if(can_rotate)
				. += span_notice("Alt-click to adjust its direction.")
			else
				. += span_notice("Use screwdriver to unlock the rotation.")

/// Re-fires what it caught, every 0.5 s while `refiring`.
/// It starts when it catches a beam and parks once it has fired.
/obj/structure/reflector/proc/reflector_step(datum/act/A)
	if(bullet_act_in_progress) // a hit is mid-resolution: fire on the next step instead of waiting here
		return
	Fire()
	if(!LAZYLEN(has_projectiles))
		set_refiring(FALSE)

/obj/structure/reflector/proc/Fire()
	UNTIL(!bullet_act_in_progress)
	var/list/angles = has_projectiles || list()
	has_projectiles = null
	for(var/angle in angles)
		var/obj/item/projectile/P = new fires_projectile(src)
		rel_set(P, nameof(P.firer), src)
		P.damage = angles[angle]
		P.accuracy = 350
		P.dispersion = 0
		P.fire(text2num(angle))

/obj/structure/reflector/proc/setAngle(new_angle)
	if(can_rotate)
		rotation_angle = new_angle
		if(deflector_overlay)
			cut_overlay(deflector_overlay)
			deflector_overlay.transform = turn(matrix(), new_angle)
			add_overlay(deflector_overlay)

/obj/structure/reflector/proc/redirect_projectile(obj/item/projectile/P,pangle)
	var/angle_key = num2text(pangle)
	var/caught_damage = P.damage
	LAZYINITLIST(has_projectiles)
	has_projectiles[angle_key] += caught_damage
	set_refiring(TRUE)
	spent(P)

/obj/structure/reflector/set_dir(new_dir)
	return ..(NORTH)

/obj/structure/reflector/Crossed(atom/movable/AM)	//Ok so this is my solution to garbage projectile code. Please god let this work.
	if(istype(AM,/obj/item/projectile))
		AM.Bump(src)

/obj/structure/reflector/bullet_act(obj/item/projectile/P)
	bullet_act_in_progress = TRUE
	var/pdir = P.dir
	var/pangle = P.Angle
	var/ploc = get_turf(P)
	if(!finished || !allowed_projectile_typecache[P.type] || !(P.dir in GLOB.cardinal))
		bullet_act_in_progress = FALSE
		return ..()
	if(auto_reflect(P, pdir, ploc, pangle) != 2)
		bullet_act_in_progress = FALSE
		return ..()
	bullet_act_in_progress = FALSE

/obj/structure/reflector/proc/auto_reflect(obj/item/projectile/P, pdir, turf/ploc, pangle)
	P.ignore_source_check = TRUE
	return 2

CAPABILITIES(/obj/structure/reflector)
	every(0.5 SECONDS, then(PROC_REF(reflector_step)), when = nameof(refiring))
	op("item", item(/obj/item), label("Use"), needs(req_bool(PROC_REF(reflector_not_admin_holds), because = PROC_REF(reflector_not_admin_refusal))), then(PROC_REF(interaction_item)))
	op("dismantle", tool(TOOL_WRENCH), label("Dismantle"), when(PROC_REF(can_be_deconstructed)), needs(req_bool(PROC_REF(not_anchored), because = MSG(reflector/unweld_first))),
		begins(MSG(reflector/dismantling)), wait(2 SECONDS), then(PROC_REF(dismantled)))
	op("weld_down", lit_welder(fuel = 1), label("Weld to the floor"), when(PROC_REF(not_anchored)), begins(MSG(reflector/welding_down), blind = span_hear("You hear welding.")), wait(2 SECONDS), then(PROC_REF(welded_down)))
	op("cut_free", lit_welder(fuel = 1), label("Cut free"), when(nameof(anchored)), priority(OP_PRIORITY_PART + 1), then(PROC_REF(cut_free)))
	op("alt", hand(), ungated(), gesture(GESTURE_ALT), label("Rotate"), when(req_bool(PROC_REF(reflector_finished_holds))), then(PROC_REF(interaction_alt)))

/obj/structure/reflector/proc/reflector_not_admin(mob/actor, atom/target, obj/item/held)
	return !admin

/// Requirement (was REQ_* reflector_not_admin): the legacy check answers TRUE to pass.
/obj/structure/reflector/proc/reflector_not_admin_holds(datum/act/op/A)
	var/answer = reflector_not_admin(A.actor, src, A.held)
	return !istext(answer) && !!answer

/// Why reflector_not_admin_holds refuses: the legacy check's text, else the clause's own reason.
/obj/structure/reflector/proc/reflector_not_admin_refusal(datum/act/op/A)
	var/answer = reflector_not_admin(A.actor, src, A.held)
	return istext(answer) ? answer : /datum/msg/req_failed

/obj/structure/reflector/proc/interaction_item(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/W = A.held
	if(W.has_tool_quality(TOOL_SCREWDRIVER))
		can_rotate = !can_rotate
		to_chat(user, span_notice("You [can_rotate ? "unlock" : "lock"] [src]'s rotation."))
		playsound(W, W.usesound, 50, 1)
		return TRUE

	if(W.get_welder() || (W.has_tool_quality(TOOL_WRENCH) && can_decon))
		return TRUE

	//Finishing the frame
	if(istype(W, /obj/item/stack/material))
		if(finished)
			return TRUE
		var/obj/item/stack/material/S = W
		if(istype(S, /obj/item/stack/material/glass))
			if(S.use(5))
				replace_with(src, /obj/structure/reflector/single)
			else
				to_chat(user, span_warning("You need five sheets of glass to create a reflector!"))
				return TRUE
		if(istype(S, /obj/item/stack/material/glass/reinforced))
			if(S.use(10))
				replace_with(src, /obj/structure/reflector/double)
			else
				to_chat(user, span_warning("You need ten sheets of reinforced glass to create a double reflector!"))
				return TRUE
		if(istype(S, /obj/item/stack/material/diamond))
			if(S.use(1))
				replace_with(src, /obj/structure/reflector/box)
	return TRUE

MSG_DEF(reflector/unweld_first, span_warning("Unweld the reflector from the floor first!"), null)
MSG_DEF(reflector/dismantling, span_notice("You start to dismantle %T%..."), span_notice("%U% starts to dismantle %T%."))
MSG_DEF(reflector/welding_down, span_notice("You start to weld %T% to the floor..."), span_notice("%U% starts to weld %T% to the floor."))

/// A wrench takes it apart only when it can be deconstructed (a fixed property of the type).
/obj/structure/reflector/proc/can_be_deconstructed(datum/act/op/A)
	return !!read_once(can_decon)

/obj/structure/reflector/proc/not_anchored(datum/act/op/A)
	return !anchored

/obj/structure/reflector/proc/dismantled(datum/act/op/A)
	act_message(A.actor, src, MSG_SELF(span_notice("You dismantle %T%...")), MSG_OTHERS(span_notice("%U% dismantles %T%.")))
	if(buildstackamount)
		new buildstacktype(drop_location(), buildstackamount)
	replace_with(src, framebuildstacktype, framebuildstackamount)

/obj/structure/reflector/proc/welded_down(datum/act/op/A)
	set_anchored(TRUE)
	act_message(A.actor, src, MSG_SELF(span_notice("You weld %T% to the floor...")), 		MSG_OTHERS(span_notice("%U% welds %T% to the floor.")), 		MSG_BLIND(span_hear("You hear welding.")))

/obj/structure/reflector/proc/cut_free(datum/act/op/A)
	act_message(A.actor, src, MSG_SELF(span_notice("You start to cut %T% free from the floor...")), 		MSG_OTHERS(span_notice("%U% starts to cut %T% free from the floor.")), 		MSG_BLIND(span_hear("You hear welding.")))
	set_anchored(FALSE)
	to_chat(A.actor, span_notice("You cut [src] free from the floor."))

/obj/structure/reflector/proc/rotate(mob/user)
	if (!can_rotate || admin)
		to_chat(user, span_warning("The rotation is locked!"))
		return FALSE
	open_request(src, /datum/prompt/number, PROC_REF(angle_entered), valid = PROC_REF(angle_valid), answerer = user, title = "Reflector Angle", question = "Input a new angle for primary reflection face.", min_value = -360, max_value = 360, default = rotation_angle, timeout = 0)
	return TRUE

/// Re-checked: the person is still next to the reflector and able, and its rotation unlocked.
/obj/structure/reflector/proc/angle_valid(datum/request/R)
	return can_rotate && !admin && answerer_holds(R, ANSWER_NEAR_SUBJECT | ANSWER_CAPABLE, src)

/obj/structure/reflector/proc/angle_entered(datum/act/request/A)
	if(!A.answer)
		return
	setAngle(SIMPLIFY_DEGREES(A.answer.value))

/obj/structure/reflector/proc/reflector_finished(mob/actor, atom/target, obj/item/held)
	return !!finished

/// Requirement (was REQ_* reflector_finished): the legacy check answers TRUE to pass.
/obj/structure/reflector/proc/reflector_finished_holds(datum/act/op/A)
	var/answer = reflector_finished(A.actor, src, A.held)
	return !istext(answer) && !!answer

/obj/structure/reflector/proc/interaction_alt(datum/act/op/A)
	var/mob/user = A.actor
	if(!CanUseTopic(user))
		return TRUE
	rotate(user)
	return TRUE


//TYPES OF REFLECTORS, SINGLE, DOUBLE, BOX

//SINGLE

/obj/structure/reflector/single
	name = "reflector"
	deflector_icon_state = "reflector"
	desc = "An angled mirror for reflecting laser beams."
	density = TRUE
	finished = TRUE
	buildstacktype = /obj/item/stack/material//glass
	buildstackamount = 5

/obj/structure/reflector/single/anchored
	anchored = TRUE

/obj/structure/reflector/single/mapping
	admin = TRUE
	anchored = TRUE

/obj/structure/reflector/single/auto_reflect(obj/item/projectile/P, pdir, turf/ploc, pangle)
	var/incidence = GET_ANGLE_OF_INCIDENCE(rotation_angle, (P.Angle + 180))
	if(abs(incidence) > 90 && abs(incidence) < 270)
		return FALSE
	var/new_angle = SIMPLIFY_DEGREES(rotation_angle + incidence)
	redirect_projectile(P,new_angle)
	return ..()

//DOUBLE

/obj/structure/reflector/double
	name = "double sided reflector"
	deflector_icon_state = "reflector_double"
	desc = "A double sided angled mirror for reflecting laser beams."
	density = TRUE
	finished = TRUE
	buildstacktype = /obj/item/stack/material/glass/reinforced
	buildstackamount = 10

/obj/structure/reflector/double/anchored
	anchored = TRUE

/obj/structure/reflector/double/mapping
	admin = TRUE
	anchored = TRUE

/obj/structure/reflector/double/auto_reflect(obj/item/projectile/P, pdir, turf/ploc, pangle)
	var/incidence = GET_ANGLE_OF_INCIDENCE(rotation_angle, (P.Angle + 180))
	var/new_angle = SIMPLIFY_DEGREES(rotation_angle + incidence)
	redirect_projectile(P,new_angle)
	return ..()

//BOX

/obj/structure/reflector/box
	name = "reflector box"
	deflector_icon_state = "reflector_box"
	desc = "A box with an internal set of mirrors that reflects all laser beams in a single direction."
	density = TRUE
	finished = TRUE
	buildstacktype = /obj/item/stack/material/diamond
	buildstackamount = 1

/obj/structure/reflector/box/Fire()	//Since they all end up at the same angle, this should save a tad bit of processing power and memory <3
	UNTIL(!bullet_act_in_progress)
	var/total_damage = 0
	for(var/angle in has_projectiles)
		total_damage += has_projectiles[angle]
	has_projectiles = null
	if(total_damage)
		var/obj/item/projectile/P = new fires_projectile(src)
		rel_set(P, nameof(P.firer), src)
		P.damage = total_damage
		P.accuracy = 350
		P.dispersion = 0
		P.fire(rotation_angle)

/obj/structure/reflector/box/anchored
	anchored = TRUE

/obj/structure/reflector/box/mapping
	admin = TRUE
	anchored = TRUE

/obj/structure/reflector/box/auto_reflect(obj/item/projectile/P)
	redirect_projectile(P,rotation_angle)
	return ..()

/obj/structure/reflector/singularity_act()
	if(admin)
		return
	else
		return ..()

/obj/structure/reflector/box/orderable
	name = "NanoTrasen reflector box"
	desc = "A box with an internal set of mirrors that reflects all laser beams in a single direction. This one is marked with NanoTrasen's logo."
	can_decon = FALSE

/datum/material/steel/generate_recipes()
	var/list/recipes = ..()
	recipes += new/datum/stack_recipe("reflector frame", /obj/structure/reflector, 5, time = 25, one_per_turf = TRUE, on_floor = TRUE)
	return recipes

/datum/supply_pack/eng/reflector
	name = "Reflector crate"
	cost = 35
	containername = "Reflector crate"
	containertype = /obj/structure/closet/crate/secure/einstein
	contains = list(/obj/structure/reflector/box/orderable = 3)

//Below is mostly mapping stuff for the spicy storage I added to house these new reflectors ;p


/obj/machinery/portable_atmospherics/canister
	var/dont_burst = FALSE

/obj/machinery/portable_atmospherics/canister/phoron/cold/Initialize(mapload)
	. = ..()
	heat_set(src.air_contents, 2.72)

