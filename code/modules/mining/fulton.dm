/obj/item/extraction_pack
	name = "bluespace fulton extraction pack"
	desc = "A balloon that can be used to extract equipment or personnel to anywhere a bluespace Fulton Recovery Beacon is. Anything not bolted down can be moved. Link the pack to a beacon by using the pack in hand."
	icon = 'icons/obj/fulton.dmi'
	icon_state = "extraction_pack"
	w_class = ITEMSIZE_NORMAL
	var/tmp/obj/structure/extraction_point/beacon
	var/static/list/beacon_networks = list("station")
	var/uses_left = 3
	var/can_use_indoors = TRUE // Can be used anywhere.
	var/safe_for_living_creatures = 1

/obj/item/extraction_pack/examine()
	. = ..()
	. += "It has [uses_left] use\s remaining."

CAPABILITIES(/obj/item/extraction_pack)
	op("self", in_hand(), priority(OP_PRIORITY_DEFAULT - 1), asks(/datum/prompt/choice, fields = list("question" = "Select a beacon to connect to", "title" = "Balloon Extraction Pack", "choices" = computed(PROC_REF(possible_beacon_choices)), "timeout" = 0), step = "beacon", when = PROC_REF(has_possible_beacons)), then(PROC_REF(interaction_self)))

	op("attach", at_target(/atom/movable), label("Attach"), needs(req(PROC_REF(can_attach), because = PROC_REF(attach_refusal))), begins(PROC_REF(attach_begins)), wait(5 SECONDS, keeps = TARGET_PRESENT | STAY | ADJACENT), then(PROC_REF(attach_done)))

/// Requirement: the pack is linked to a beacon and the target can be sent (anything else is refused, some of it silently).
/obj/item/extraction_pack/proc/can_attach(datum/act/op/A)
	return isnull(attach_refusal(A))

/// Why the pack cannot be attached to the target: a text, the silent message for a target that is simply not eligible, or null.
/obj/item/extraction_pack/proc/attach_refusal(datum/act/op/A)
	var/atom/movable/target = A.target
	if(!beacon())
		return "[src] is not linked to a beacon, and cannot be used."
	if(!can_use_indoors)
		var/turf/T = get_turf(target)
		if(T && !T.is_outdoors())
			return "[src] can only be used on things that are outdoors!"
	if(!istype(target) || !read_once(A.actor.Adjacent(target)))
		return /datum/msg/req_silent
	if(!safe_for_living_creatures && check_for_living_mobs(target))
		return "[src] is not safe for use with living creatures, they wouldn't survive the trip back!"
	if(!isturf(target.loc) || target.anchored) // no extracting stuff inside other stuff
		return /datum/msg/req_silent
	return null

/obj/item/extraction_pack/proc/attach_begins(datum/act/op/A)
	return msg_text(span_notice("You start attaching the pack to [A.target]..."))

/// The extraction beacons on this pack's networks.
/obj/item/extraction_pack/proc/possible_beacons()
	var/list/possible_beacons = list()
	for(var/obj/structure/extraction_point/EP as anything in REGISTRY_MEMBERS(REGISTRY_EXTRACTION_BEACONS))
		if(EP.beacon_network in beacon_networks)
			possible_beacons += EP
	return possible_beacons

/// The beacons the question offers.
/obj/item/extraction_pack/proc/possible_beacon_choices(datum/act/op/A)
	return possible_beacons()

/// The question is asked only when there is a beacon to choose.
/obj/item/extraction_pack/proc/has_possible_beacons(datum/act/op/A)
	return length(possible_beacons()) > 0

/// Old attack_self: link the pack to a beacon.
/obj/item/extraction_pack/proc/interaction_self(datum/act/op/A)
	var/mob/user = A.actor
	if(!length(possible_beacons()))
		to_chat(user, "There are no extraction beacons in existence!")
		return OP_OK
	var/obj/structure/extraction_point/selected = A.step_value("beacon")
	if(!istype(selected) || QDELETED(selected))
		return OP_OK
	rel_set(src, nameof(beacon), selected)
	to_chat(user, "You link the extraction pack to the beacon system.")
	return OP_OK

/// The pack is on: the balloon lifts `A` off (a sequence of steps on the holder, fulton_*()).
/obj/item/extraction_pack/proc/attach_done(datum/act/op/Op)
	var/mob/user = Op.actor
	var/atom/movable/A = Op.target
	if(!beacon() || A.anchored || !isturf(A.loc))
		return OP_OK
	to_chat(user, span_notice("You attach the pack to [A] and activate it."))
	uses_left--
	if(isliving(A))
		var/mob/living/M = A
		M.status_adjust(STAT_STUNNED, 20) // Keep them from moving during the duration of the extraction
		if(M?.buckled_to())
			var/atom/movable/_tmp_buck_15 = M?.buckled_to()
			_tmp_buck_15.unbuckle_mob(M)
	else
		A.set_anchored(TRUE)
		A.set_density(FALSE)
	var/list/flooring_near_beacon = list()
	for(var/turf/simulated/floor/floor in orange(1, beacon()))
		flooring_near_beacon += floor
	var/turf/landing = length(flooring_near_beacon) ? pick(flooring_near_beacon) : get_turf(beacon())
	var/obj/effect/extraction_holder/holder_obj = new(A.loc)
	holder_obj.appearance = A.appearance
	A.forceMove(holder_obj)
	holder_obj.fulton_expand(A, landing)
	if(uses_left <= 0)
		consume(src, user)
	return OP_OK

/obj/effect/extraction_holder/proc/fulton_balloon(state)
	var/mutable_appearance/balloon = mutable_appearance('icons/obj/fulton_balloon.dmi', state)
	balloon.pixel_y = 10
	balloon.appearance_flags = RESET_COLOR | RESET_ALPHA | RESET_TRANSFORM
	return balloon

/obj/effect/extraction_holder/proc/fulton_expand(atom/movable/A, turf/landing)
	add_overlay(fulton_balloon("fulton_expand"))
	after(src, 0.4 SECONDS, PROC_REF(fulton_inflate), with = list(A, landing), keeps_dead = TRUE)

/obj/effect/extraction_holder/proc/fulton_inflate(atom/movable/A, turf/landing)
	cut_overlays()
	add_overlay(fulton_balloon("fulton_balloon"))
	play_sfx(src, SFX_ITEMS_FULEXT_DEPLOY)
	animate(src, pixel_z = 10, time = 20)
	animate(pixel_z = 15, time = 10)
	animate(pixel_z = 10, time = 10)
	animate(pixel_z = 15, time = 10)
	animate(pixel_z = 10, time = 10)
	after(src, 6 SECONDS, PROC_REF(fulton_launch), with = list(A, landing), keeps_dead = TRUE)

/obj/effect/extraction_holder/proc/fulton_launch(atom/movable/A, turf/landing)
	play_sfx(src, SFX_ITEMS_FULTEXT_LAUNCH)
	animate(src, pixel_z = 1000, time = 30)
	if(ishuman(A))
		var/mob/living/carbon/human/L = A
		L.status_adjust(STAT_STUNNED, 20)
		L.status_set(STAT_DROWSY, 0)
	after(src, 3 SECONDS, PROC_REF(fulton_arrive), with = list(A, landing), keeps_dead = TRUE)

/obj/effect/extraction_holder/proc/fulton_arrive(atom/movable/A, turf/landing)
	forceMove(landing)
	animate(src, pixel_z = 10, time = 50)
	animate(pixel_z = 15, time = 10)
	animate(pixel_z = 10, time = 10)
	after(src, 7 SECONDS, PROC_REF(fulton_retract), with = list(A), keeps_dead = TRUE)

/obj/effect/extraction_holder/proc/fulton_retract(atom/movable/A)
	cut_overlays()
	add_overlay(fulton_balloon("fulton_retract"))
	after(src, 0.4 SECONDS, PROC_REF(fulton_land), with = list(A), keeps_dead = TRUE)

/obj/effect/extraction_holder/proc/fulton_land(atom/movable/A)
	cut_overlays()
	if(A)
		A.set_anchored(FALSE) // An item has to be unanchored to be extracted in the first place.
		A.set_density(initial(A.density))
	animate(src, pixel_z = 0, time = 0.5 SECONDS)
	after(src, 0.5 SECONDS, PROC_REF(fulton_release), with = list(A), keeps_dead = TRUE)

/obj/effect/extraction_holder/proc/fulton_release(atom/movable/A)
	if(A)
		A.forceMove(loc)
	consume(src)

// Makes fultons work pretty much anywhere.

/obj/item/fulton_core
	name = "bluespace extraction beacon signaller"
	desc = "Emits a signal which bluespace Fulton recovery devices can lock onto. Activate in hand to create a beacon. Cannot be moved after placing!"
	icon = 'icons/obj/fulton.dmi'
	icon_state = "extraction_pointoff"

MSG_DEF_SELF(fulton/needs_ground, "you must be standing on solid ground to deploy an extraction beacon")

CAPABILITIES(/obj/item/fulton_core)
	op("self", in_hand(), priority(OP_PRIORITY_DEFAULT - 1), needs(req(PROC_REF(actor_on_turf_holds), because = MSG(fulton/needs_ground))), wait(1.5 SECONDS), then(PROC_REF(deploy_done)))

/// Requirement: the actor stands on a real turf.
/obj/item/fulton_core/proc/actor_on_turf_holds(datum/act/op/A)
	return !!get_turf(A.actor)

/obj/item/fulton_core/proc/deploy_done(datum/act/op/A)
	replace_with(src, /obj/structure/extraction_point)

/obj/structure/extraction_point
	name = "fulton recovery beacon"
	desc = "A beacon for the bluespace Fulton recovery system. Activate a pack in your hand to link it to a beacon."
	icon = 'icons/obj/fulton.dmi'
	icon_state = "extraction_point"
	anchored = TRUE
	density = FALSE
	var/beacon_network = "station"

REGISTRY_MEMBERSHIP(/obj/structure/extraction_point, REGISTRY_EXTRACTION_BEACONS)

CAPABILITIES(/obj/structure/extraction_point)
	rolls(nameof(name), PROC_REF(roll_name))

/// Rolled before init (rolls()): the beacon's number, and where it was set up.
/obj/structure/extraction_point/proc/roll_name(datum/roller/R)
	return "[name] ([R.number(100, 999)]) ([get_area_name(src, TRUE)])"

/obj/effect/extraction_holder
	name = "extraction holder"
	desc = "you shouldn't see this"
	var/tmp/atom/movable/stored_obj

/obj/item/extraction_pack/proc/check_for_living_mobs(atom/A)
	if(isliving(A))
		var/mob/living/L = A
		if(L.stat != DEAD)
			return 1
	for(var/thing in A.GetAllContents())
		if(isliving(thing))
			var/mob/living/L = thing
			if(L.stat != DEAD)
				return 1
	return 0

/obj/effect/extraction_holder/singularity_pull()
	return

/// Accessor for the beacon var.
/obj/item/extraction_pack/proc/beacon() as /obj/structure/extraction_point
	return beacon

/// Accessor for the stored_obj var.
/obj/effect/extraction_holder/proc/stored_obj() as /atom/movable
	return stored_obj
