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

DECLARE_INTERACTIONS(/obj/item/extraction_pack, INTERACT_USE(null, PROC_REF(interaction_self)))

/// Old attack_self.
/obj/item/extraction_pack/proc/interaction_self(mob/user, obj/item/held, datum/interaction/interaction)
	var/list/possible_beacons = list()
	for(var/obj/structure/extraction_point/EP as anything in REGISTRY_MEMBERS(REGISTRY_EXTRACTION_BEACONS))
		if(EP.beacon_network in beacon_networks)
			possible_beacons += EP

	if(!possible_beacons.len)
		to_chat(user, "There are no extraction beacons in existence!")
		return TRUE

	var/original_client_ckey
	if(istype(user, /client))
		var/client/C = user
		original_client_ckey = C.ckey
		user = C.mob
	if(!ismob(user) || QDELETED(user))
		return TRUE
	open_request(src, /datum/prompt/choice/extraction_beacon, PROC_REF(beacon_selected), answerer = user, choices = possible_beacons, captured_item = held, captured_interaction = interaction, item_expected = !isnull(held), interaction_expected = !isnull(interaction), original_client_ckey = original_client_ckey)
	return TRUE

/obj/item/extraction_pack/proc/beacon_selected(datum/act/request/A)
	var/datum/prompt/choice/extraction_beacon/request = A.request
	if(!A.answer || request.captures_gone())
		return
	apply_beacon_selection(A)
	SStgui.update_uis(src)

/obj/item/extraction_pack/proc/apply_beacon_selection(datum/act/request/A)
	var/datum/prompt/choice/extraction_beacon/request = A.request
	var/mob/user = request.original_client_ckey ? GLOB.directory[request.original_client_ckey] : request.answerer
	var/list/possible_beacons = list()
	for(var/obj/structure/extraction_point/EP as anything in REGISTRY_MEMBERS(REGISTRY_EXTRACTION_BEACONS))
		if(EP.beacon_network in beacon_networks)
			possible_beacons += EP
	if(!possible_beacons.len)
		to_chat(user, "There are no extraction beacons in existence!")
		return TRUE
	var/obj/structure/extraction_point/selected = A.answer.value
	if(!istype(selected) || QDELETED(selected))
		return TRUE
	rel_set(src, nameof(beacon), selected)
	to_chat(user, "You link the extraction pack to the beacon system.")
	return TRUE

/datum/prompt/choice/extraction_beacon
	question = "Select a beacon to connect to"
	title = "Balloon Extraction Pack"
	timeout = 0
	var/obj/item/captured_item
	var/datum/interaction/captured_interaction
	var/item_expected = FALSE
	var/interaction_expected = FALSE
	var/original_client_ckey

CAPABILITIES(/datum/prompt/choice/extraction_beacon)
	ref_one(nameof(captured_item), /obj/item)
	ref_one(nameof(captured_interaction), /datum/interaction)

/datum/prompt/choice/extraction_beacon/prepare(datum/act/A)
	. = ..()
	var/obj/item/item = captured_item
	var/datum/interaction/interaction = captured_interaction
	rel_clear(src, nameof(captured_item))
	rel_clear(src, nameof(captured_interaction))
	rel_set(src, nameof(captured_item), item)
	rel_set(src, nameof(captured_interaction), interaction)

/datum/prompt/choice/extraction_beacon/proc/captures_gone()
	return QDELETED(answerer) || (item_expected && QDELETED(captured_item)) || (interaction_expected && QDELETED(captured_interaction)) || (original_client_ckey && !GLOB.directory[original_client_ckey])

/datum/prompt/choice/extraction_beacon/recheck_extra()
	. = ..()
	if(.)
		return
	if(captures_gone())
		return "gone"
	if(!isnull(value))
		var/obj/structure/extraction_point/selected = value
		if(!istype(selected) || QDELETED(selected))
			return "the extraction beacon is gone"
	return null

/obj/item/extraction_pack/afterattack(atom/movable/A, mob/living/carbon/human/user, flag, params)
	if(!beacon())
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
		task_timed(user, 5 SECONDS, A, src, PROC_REF(attach_done), list(user, A))

/// The pack is on: the balloon lifts `A` off (a sequence of steps on the holder, fulton_*()).
/obj/item/extraction_pack/proc/attach_done(mob/living/carbon/human/user, atom/movable/A)
	if(!beacon() || A.anchored || !isturf(A.loc))
		return
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

/obj/effect/extraction_holder/proc/fulton_balloon(state)
	var/mutable_appearance/balloon = mutable_appearance('icons/obj/fulton_balloon.dmi', state)
	balloon.pixel_y = 10
	balloon.appearance_flags = RESET_COLOR | RESET_ALPHA | RESET_TRANSFORM
	return balloon

/obj/effect/extraction_holder/proc/fulton_expand(atom/movable/A, turf/landing)
	add_overlay(fulton_balloon("fulton_expand"))
	after(src, 0.4 SECONDS, PROC_REF(fulton_inflate), with = list(A, landing))

/obj/effect/extraction_holder/proc/fulton_inflate(atom/movable/A, turf/landing)
	cut_overlays()
	add_overlay(fulton_balloon("fulton_balloon"))
	play_sfx(src, SFX_ITEMS_FULEXT_DEPLOY)
	animate(src, pixel_z = 10, time = 20)
	animate(pixel_z = 15, time = 10)
	animate(pixel_z = 10, time = 10)
	animate(pixel_z = 15, time = 10)
	animate(pixel_z = 10, time = 10)
	after(src, 6 SECONDS, PROC_REF(fulton_launch), with = list(A, landing))

/obj/effect/extraction_holder/proc/fulton_launch(atom/movable/A, turf/landing)
	play_sfx(src, SFX_ITEMS_FULTEXT_LAUNCH)
	animate(src, pixel_z = 1000, time = 30)
	if(ishuman(A))
		var/mob/living/carbon/human/L = A
		L.status_adjust(STAT_STUNNED, 20)
		L.status_set(STAT_DROWSY, 0)
	after(src, 3 SECONDS, PROC_REF(fulton_arrive), with = list(A, landing))

/obj/effect/extraction_holder/proc/fulton_arrive(atom/movable/A, turf/landing)
	forceMove(landing)
	animate(src, pixel_z = 10, time = 50)
	animate(pixel_z = 15, time = 10)
	animate(pixel_z = 10, time = 10)
	after(src, 7 SECONDS, PROC_REF(fulton_retract), with = list(A))

/obj/effect/extraction_holder/proc/fulton_retract(atom/movable/A)
	cut_overlays()
	add_overlay(fulton_balloon("fulton_retract"))
	after(src, 0.4 SECONDS, PROC_REF(fulton_land), with = list(A))

/obj/effect/extraction_holder/proc/fulton_land(atom/movable/A)
	cut_overlays()
	if(A)
		A.set_anchored(FALSE) // An item has to be unanchored to be extracted in the first place.
		A.set_density(initial(A.density))
	animate(src, pixel_z = 0, time = 0.5 SECONDS)
	after(src, 0.5 SECONDS, PROC_REF(fulton_release), with = list(A))

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

DECLARE_INTERACTIONS(/obj/item/fulton_core, INTERACT_USE(null, PROC_REF(interaction_self), REQ_BECAUSE(REQ_ON_TURF, "you must be standing on solid ground to deploy an extraction beacon")))

/// Old attack_self.
/obj/item/fulton_core/proc/interaction_self(mob/user, obj/item/held, datum/interaction/interaction)
	task_timed(user, 1.5 SECONDS, user, src, PROC_REF(deploy_done), list(user))
	return TRUE

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
