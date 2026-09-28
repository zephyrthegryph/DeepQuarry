/obj/item/extraction_pack
	name = "bluespace fulton extraction pack"
	desc = "A balloon that can be used to extract equipment or personnel to anywhere a bluespace Fulton Recovery Beacon is. Anything not bolted down can be moved. Link the pack to a beacon by using the pack in hand."
	icon = 'icons/obj/fulton.dmi'
	icon_state = "extraction_pack"
	w_class = ITEMSIZE_NORMAL
	var/obj/structure/extraction_point/beacon
	var/static/list/beacon_networks = list("station")
	var/uses_left = 3
	var/can_use_indoors = TRUE // Can be used anywhere.
	var/safe_for_living_creatures = 1

/obj/item/extraction_pack/examine()
	. = ..()
	. += "It has [uses_left] use\s remaining."

/obj/item/extraction_pack/attack_self(mob/user)
	. = ..(user)
	if(.)
		return TRUE
	var/list/possible_beacons = list()
	for(var/obj/structure/extraction_point/EP as anything in REGISTRY_MEMBERS(REGISTRY_EXTRACTION_BEACONS))
		if(EP.beacon_network in beacon_networks)
			possible_beacons += EP

	if(!possible_beacons.len)
		to_chat(user, "There are no extraction beacons in existence!")
		return

	else
		var/A

		var/_answer_k33 = rerun_prompt(user, "k33", list("kind" = "list", "message" = "Select a beacon to connect to", "title" = "Balloon Extraction Pack", "choices" = possible_beacons), PROC_REF(attack_self), args)
		if(isnull(_answer_k33))
			return TRUE
		A = _answer_k33

		if(!A)
			return
		beacon = A
		to_chat(user, "You link the extraction pack to the beacon system.")

/obj/item/extraction_pack/afterattack(atom/movable/A, mob/living/carbon/human/user, flag, params)
	if(!beacon)
		to_chat(user, "[src] is not linked to a beacon, and cannot be used.")
		return
	if(!can_use_indoors)
		var/turf/T = get_turf(A)
		if(T && !T.is_outdoors())
			to_chat(user, "[src] can only be used on things that are outdoors!")
			return
	if(!flag)
		return
	if(!istype(A))
		return
	else
		if(!safe_for_living_creatures && check_for_living_mobs(A))
			to_chat(user, "[src] is not safe for use with living creatures, they wouldn't survive the trip back!")
			return
		if(!isturf(A.loc)) // no extracting stuff inside other stuff
			return
		if(A.anchored)
			return
		to_chat(user, span_notice("You start attaching the pack to [A]..."))
		om_do_after(user, 5 SECONDS, A, src, PROC_REF(attach_done), list(user, A))

/// The pack is on: the balloon lifts `A` off (a sequence of steps on the holder, fulton_*()).
/obj/item/extraction_pack/proc/attach_done(mob/living/carbon/human/user, atom/movable/A)
	if(!beacon || A.anchored || !isturf(A.loc))
		return
	to_chat(user, span_notice("You attach the pack to [A] and activate it."))
	uses_left--
	if(isliving(A))
		var/mob/living/M = A
		M.status_adjust(EFFECT_STUNNED, 20) // Keep them from moving during the duration of the extraction
		if(M?.buckled_to())
			var/atom/movable/_tmp_buck_15 = M?.buckled_to()
			_tmp_buck_15.unbuckle_mob(M)
	else
		A.anchored = TRUE
		A.density = FALSE
	var/list/flooring_near_beacon = list()
	for(var/turf/simulated/floor/floor in orange(1, beacon))
		flooring_near_beacon += floor
	var/turf/landing = length(flooring_near_beacon) ? pick(flooring_near_beacon) : get_turf(beacon)
	var/obj/effect/extraction_holder/holder_obj = new(A.loc)
	holder_obj.appearance = A.appearance
	A.forceMove(holder_obj)
	holder_obj.fulton_expand(A, landing)
	if(uses_left <= 0)
		consume(src, user)

/obj/effect/extraction_holder/proc/fulton_balloon(state)
	var/mutable_appearance/balloon = mutable_appearance('icons/obj/fulton_balloon.dmi', state)
	balloon.pixel_y = 10
	balloon.appearance_flags = RESET_COLOR | RESET_ALPHA | RESET_TRANSFORM
	return balloon

/obj/effect/extraction_holder/proc/fulton_expand(atom/movable/A, turf/landing)
	add_overlay(fulton_balloon("fulton_expand"))
	om_after(src, 0.4 SECONDS, PROC_REF(fulton_inflate), A, landing)

/obj/effect/extraction_holder/proc/fulton_inflate(atom/movable/A, turf/landing)
	cut_overlays()
	add_overlay(fulton_balloon("fulton_balloon"))
	playsound(src, 'sound/items/fulext_deploy.wav', 50, 1, -3)
	animate(src, pixel_z = 10, time = 20)
	animate(pixel_z = 15, time = 10)
	animate(pixel_z = 10, time = 10)
	animate(pixel_z = 15, time = 10)
	animate(pixel_z = 10, time = 10)
	om_after(src, 6 SECONDS, PROC_REF(fulton_launch), A, landing)

/obj/effect/extraction_holder/proc/fulton_launch(atom/movable/A, turf/landing)
	playsound(src, 'sound/items/fultext_launch.wav', 50, 1, -3)
	animate(src, pixel_z = 1000, time = 30)
	if(ishuman(A))
		var/mob/living/carbon/human/L = A
		L.status_adjust(EFFECT_STUNNED, 20)
		L.status_set(EFFECT_DROWSY, 0)
	om_after(src, 3 SECONDS, PROC_REF(fulton_arrive), A, landing)

/obj/effect/extraction_holder/proc/fulton_arrive(atom/movable/A, turf/landing)
	forceMove(landing)
	animate(src, pixel_z = 10, time = 50)
	animate(pixel_z = 15, time = 10)
	animate(pixel_z = 10, time = 10)
	om_after(src, 7 SECONDS, PROC_REF(fulton_retract), A)

/obj/effect/extraction_holder/proc/fulton_retract(atom/movable/A)
	cut_overlays()
	add_overlay(fulton_balloon("fulton_retract"))
	om_after(src, 0.4 SECONDS, PROC_REF(fulton_land), A)

/obj/effect/extraction_holder/proc/fulton_land(atom/movable/A)
	cut_overlays()
	A.anchored = FALSE // An item has to be unanchored to be extracted in the first place.
	A.density = initial(A.density)
	animate(src, pixel_z = 0, time = 5)
	om_after(src, 0.5 SECONDS, PROC_REF(fulton_release), A)

/obj/effect/extraction_holder/proc/fulton_release(atom/movable/A)
	A.forceMove(loc)
	qdel(src)

// Makes fultons work pretty much anywhere.

/obj/item/fulton_core
	name = "bluespace extraction beacon signaller"
	desc = "Emits a signal which bluespace Fulton recovery devices can lock onto. Activate in hand to create a beacon. Cannot be moved after placing!"
	icon = 'icons/obj/fulton.dmi'
	icon_state = "extraction_pointoff"

/obj/item/fulton_core/attack_self(mob/user)
	. = ..(user)
	if(.)
		return TRUE
	var/turf/T = get_turf(user)
	if(!T)
		to_chat(user, span_warning("You must be standing on solid ground to deploy an extraction beacon!"))
		return
	om_do_after(user, 1.5 SECONDS, user, src, PROC_REF(deploy_done), list(user))

/obj/item/fulton_core/proc/deploy_done(mob/user)
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

/obj/structure/extraction_point/Initialize(mapload)
	. = ..()
	name += " ([rand(100,999)]) ([get_area_name(src, TRUE)])"

/obj/effect/extraction_holder
	name = "extraction holder"
	desc = "you shouldn't see this"
	var/atom/movable/stored_obj

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
