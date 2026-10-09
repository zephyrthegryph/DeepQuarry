// Unique areas were requested for each superpose map for future use. The plain superpose area is for future varedits to all superpose submaps.
/area/survivalpod/superpose
	requires_power = TRUE

/area/survivalpod/superpose/CrashedInfestedShip

/area/survivalpod/superpose/CrashedQurantineShip

/area/survivalpod/superpose/CultShip

/area/survivalpod/superpose/DemonPool
	requires_power = FALSE

/area/survivalpod/superpose/Dinner

/area/survivalpod/superpose/DragonCave

/area/survivalpod/superpose/ExplorerHome

/area/survivalpod/superpose/Farm

/area/survivalpod/superpose/FieldLab

/area/survivalpod/superpose/HellCave

/area/survivalpod/superpose/HydroCave

/area/survivalpod/superpose/LargeAlienShip

/area/survivalpod/superpose/LoneHome

/area/survivalpod/superpose/LoneHomeclean

/area/survivalpod/superpose/MechFabShip

/area/survivalpod/superpose/MechStorageFab

/area/survivalpod/superpose/MercShip

/area/survivalpod/superpose/MethLab

/area/survivalpod/superpose/OldHotel

/area/survivalpod/superpose/NewHotel

/area/survivalpod/superpose/ScienceShip

/area/survivalpod/superpose/SmallCombatShip

/area/survivalpod/superpose/SurvivalBarracks
	requires_power = FALSE

/area/survivalpod/superpose/SurvivalCargo
	requires_power = FALSE

/area/survivalpod/superpose/SurvivalDIY_11x11

/area/survivalpod/superpose/SurvivalDIY_11x11lite

/area/survivalpod/superpose/SurvivalDIY_7x7

/area/survivalpod/superpose/SurvivalDIY_9x9

/area/survivalpod/superpose/SurvivalDinner
	requires_power = FALSE

/area/survivalpod/superpose/SurvivalEngineering
	requires_power = FALSE

/area/survivalpod/superpose/SurvivalHome
	requires_power = FALSE

/area/survivalpod/superpose/SurvivalHydro
	requires_power = FALSE

/area/survivalpod/superpose/SurvivalJanitor
	requires_power = FALSE

/area/survivalpod/superpose/SurvivalLeisure
	requires_power = FALSE

/area/survivalpod/superpose/SurvivalLuxuryBar
	requires_power = FALSE

/area/survivalpod/superpose/SurvivalLuxuryHome
	requires_power = FALSE

/area/survivalpod/superpose/SurvivalMedical
	requires_power = FALSE

/area/survivalpod/superpose/SurvivalPool
	requires_power = FALSE

/area/survivalpod/superpose/SurvivalQuarters
	requires_power = FALSE

/area/survivalpod/superpose/SurvivalScience
	requires_power = FALSE

/area/survivalpod/superpose/SurvivalSecurity
	requires_power = FALSE

/area/survivalpod/superpose/TinyCombatShip

/area/survivalpod/superpose/TradingShip

/area/survivalpod/superpose/WoodenCamp

/area/survivalpod/superpose/AnimalHospital

/area/survivalpod/superpose/RestaurationBar
	requires_power = FALSE

/area/survivalpod/superpose/BroadcastingPod

/area/survivalpod/superpose/DemonPoolV2
	requires_power = FALSE

/area/survivalpod/superpose/PirateShip

/area/survivalpod/superpose/SurvivalHomeV2
	requires_power = FALSE

/area/survivalpod/superpose/SurvivalMechFab
	requires_power = FALSE

/area/survivalpod/superpose/SurvivalMethLab
	requires_power = FALSE

/area/survivalpod/superpose/SurvivalScienceV2
	requires_power = FALSE

/area/survivalpod/superpose/SurvivalSecurityV2
	requires_power = FALSE

/area/survivalpod/superpose/HillOutpost

/area/survivalpod/superpose/PizzaParlor

/area/survivalpod/superpose/GrandLibrary

/area/survivalpod/superpose/logcabin

/area/survivalpod/superpose/hotel

/area/survivalpod/superpose/XenoBotanySetup

/area/survivalpod/superpose/secondlifebar
	flags = AREA_ALLOW_LARGE_SIZE

/area/survivalpod/superpose/secondlifebar/dorms
	icon_state = "toilet"
	flags = AREA_ALLOW_LARGE_SIZE | AREA_SOUNDPROOF

/area/survivalpod/superpose/ripperdocpod

/obj/item/survivalcapsule/superpose
	name = "superposed surfluid shelter capsule"
	desc = "A proprietary hyperstructure of many three-dimensional spaces superposed around a supermatter nano crystal; right-click to reset the pod. There's a license for use printed on the bottom."
	description_fluff = "The capsule contains pockets of compressed space in a super position stabilized by a miniscule supermatter crystal. \
	NanoTrasen stresses the safety of this model over previous prototypes but assumes no liability for sub-kiloton explosions."
	template_id = null
	var/list/template_ids
	var/pod_initialized = FALSE

// Override since the parent proc has a sanity check to delete the capsule if no template is found, which doesn't exactly work with this item considering examining calls this proc.
/obj/item/survivalcapsule/superpose/get_template()
	if(template())
		return
	template_static = SSmapping.shelter_templates[template_id]
	if(!template())
		template_static = null

/// Old attack_self (virtual: /obj/item/survivalcapsule/proc/survivalcapsule_self()): pick a template first.
/obj/item/survivalcapsule/superpose/survivalcapsule_self(mob/user, obj/item/held = null, selected_template = null)
	if(!pod_initialized) // Populate list after round start as map templates might not exist when this item is created.
		for(var/datum/map_template/shelter/superpose/shelter_type as anything in subtypesof(/datum/map_template/shelter))
			if(!(initial(shelter_type.mappath)) || !(initial(shelter_type.superpose))) // Limits map templates to those marked for the superpose capsule.
				continue
			LAZYADD(template_ids, initial(shelter_type.shelter_id))
		pod_initialized = TRUE
	if(!template_id)
		if(isnull(selected_template))
			open_template_request(user, held)
			return TRUE
		var/answer = selected_template
		if(isnull(answer))
			return TRUE
		if(!answer)
			return
		else
			src.template_id = answer
			return // Return here or the pod will activate as soon as a selection is made.

	// Now we call super to run the rest of the parent proc since the choice has been handled.
	return ..(user, held)

// Allows resetting the capsule if the wrong template is chosen.
CAPABILITIES(/obj/item/survivalcapsule/superpose)
	op("superpose_capsule_verb_reset", menu(), label("Reset Active Pod"), needs(carried()), then(PROC_REF(superpose_capsule_verb_reset)))

/// Old Reset Active Pod verb: Resets the pod back to factory settings.
/obj/item/survivalcapsule/superpose/proc/superpose_capsule_verb_reset(datum/act/op/A)
	var/mob/user = A.actor
	if(!used)
		template_id = null
		template_static = null // Important to reset both, otherwise the template cannot be reset once the pod has been deployed.
		unique_id = null
		to_chat(user, span_notice("You reset the pod's selection."))

/obj/item/survivalcapsule/superpose/shuttle
	name = "superposed surfluid shuttle capsule"
	is_ship = TRUE //So you cant just make holes in planets

/// Old attack_self (virtual: /obj/item/survivalcapsule/proc/survivalcapsule_self()): pick a shuttle template first.
/obj/item/survivalcapsule/superpose/shuttle/survivalcapsule_self(mob/user, obj/item/held = null, selected_template = null)
	if(!pod_initialized)
		for(var/datum/map_template/shelter/superpose/shelter_type as anything in subtypesof(/datum/map_template/shelter/))
			if(!(initial(shelter_type.mappath)) || !(initial(shelter_type.shuttle)))
				continue
			LAZYADD(template_ids, initial(shelter_type.shelter_id))
		pod_initialized = TRUE
	if(!template_id)
		if(isnull(selected_template))
			open_template_request(user, held)
			return TRUE
		var/answer = selected_template
		if(isnull(answer))
			return TRUE
		if(!answer)
			return
		else
			template_id = answer
			unique_id = answer
			return
	return ..(user, held)

GLOBAL_LIST_EMPTY(unique_deployable)
/*****************************Survival Pod********************************/
/area/survivalpod
	name = "\improper Emergency Shelter"
	icon_state = "away"
	dynamic_lighting = TRUE
	requires_power = FALSE
	has_gravity = TRUE
	flags = AREA_ALWAYS_HAS_GRAVITY

/area/survivalpod/dorms
	name = "\improper Emergency Shelter Dorm"
	icon_state = "away1"
	flags = RAD_SHIELDED | BLUE_SHIELDED | AREA_FLAG_IS_NOT_PERSISTENT | AREA_FORBID_EVENTS | AREA_FORBID_SINGULO | AREA_SOUNDPROOF | AREA_ALLOW_LARGE_SIZE | AREA_BLOCK_SUIT_SENSORS | AREA_BLOCK_TRACKING | AREA_ALWAYS_HAS_GRAVITY

/area/survivalpod/dorms/bathroom
	name = "\improper Emergency Shelter Bathroom"
	icon_state = "away2"

/area/survivalpod/redspace
	name = "\improper Redspace Capsule Shelter"
	icon_state = "darkred"

//Custom survival pod areas

/area/survivalpod/holly
	name = "\improper Holly's Emergency Shelter"

/area/survivalpod/dorms/holly
	name = "\improper Holly's Emergency Shelter Dorm"

//Survival Capsule
/obj/item/survivalcapsule
	name = "surfluid shelter capsule"
	desc = "An emergency shelter programmed into construction nanomachines. It has a license for use printed on the bottom."
	icon_state = "houseball"
	icon = 'icons/obj/device_alt.dmi'
	w_class = ITEMSIZE_TINY
	var/template_id = "shelter_alpha"
	var/tmp/datum/map_template/shelter/template_static
	var/used = FALSE
	var/is_ship = FALSE
	var/unique_id = null
	var/admin_log_verb = "activated a bluespace capsule" // Just to make the blue/redspace ones distinct for admin logs

/obj/item/survivalcapsule/proc/get_template()
	if(template())
		return
	template_static = SSmapping.shelter_templates[get_template_id()]
	if(!template())
		throw EXCEPTION("Shelter template ([template_id]) not found!")

/obj/item/survivalcapsule/proc/get_template_id()
	return template_id

/obj/item/survivalcapsule/proc/get_template_info()
	var/ret = ""
	if(!template())
		get_template()
	if(template())
		ret += "This capsule has the [template().name] stored:\n"
		ret += template().description
	else
		ret += "This capsule has an unknown template stored."
	return ret

/// Creates and shows to the user a preview of the pod's shape, like the admin load template verb does. However, this one shows valid deploy turfs in blue, and invalid turfs in red.
/obj/item/survivalcapsule/proc/preview_template(mob/user, turf/deploy_turf, show_doors = FALSE)
	if(!deploy_turf)
		return
	var/preview_render = list()
	template().preload_size(template().mappath)
	// Get origin (bottom-left) of shelter template relative to where we are on the map
	var/turf/origin = locate(user.x - round((template().width)/2) , user.y - round((template().height)/2) , user.z)
	var/turf/topright = locate(user.x + round((template().width)/2) , user.y + round((template().height)/2) , user.z)
	if(!origin || !topright)
		return
	for(var/turf/S in template().get_affected_turfs(deploy_turf, centered = TRUE))
		if(template().get_turf_deployability(S, is_ship) != SHELTER_DEPLOY_ALLOWED)
			preview_render += image('icons/misc/debug_group.dmi',S ,"red")
		else if(show_doors)
			var/is_door_here = FALSE
			for(var/list/door_coord in template().door_locations)
				// If we're at a spot where a door is going to appear, display a green spot!
				var/dX = origin.x + door_coord[1] - 1
				var/dY = origin.y + door_coord[2] - 1
				if(S.x == dX && S.y == dY)
					preview_render += image('icons/misc/debug_group.dmi',S ,"green")
					is_door_here = TRUE
					break
			if(!is_door_here)
				preview_render += image('icons/misc/debug_group.dmi',S ,"blue")
		else
			preview_render += image('icons/misc/debug_group.dmi',S ,"blue")
	user.client.images += preview_render
	return preview_render

/obj/item/survivalcapsule/proc/remove_preview(mob/user, list/preview_render, fade_time = 1 SECOND)
	if(fade_time > 0)
		for(var/image/I in preview_render)
			animate(I, alpha = 0, fade_time)
		after(src, fade_time, PROC_REF(delete_preview_render), with = list(user, preview_render))
	else
		delete_preview_render(user, preview_render)

/obj/item/survivalcapsule/proc/delete_preview_render(mob/user, list/preview_render)
	if(user?.client)
		user.client.images -= preview_render

/obj/item/survivalcapsule/proc/can_deploy(turf/deploy_location, turf/above_location)
	var/status = template().check_deploy(deploy_location, is_ship)
	switch(status)
		//Not allowed due to /area technical reasons
		if(SHELTER_DEPLOY_BAD_AREA)
			src.loc.visible_message(span_warning("\The [src]'s safety mechanisms prevent it from activating in this area. You'll need to find an area that would be less disruptive to activate it!"))

		//Anchored objects or no space
		if(SHELTER_DEPLOY_BAD_TURFS, SHELTER_DEPLOY_ANCHORED_OBJECTS)
			var/width = template().width
			var/height = template().height
			src.loc.visible_message(span_warning("\The [src] can be activated here, but doesn't have room to deploy! You need to clear a [width]x[height] area!"))

		if(SHELTER_DEPLOY_SHIP_SPACE)
			src.loc.visible_message(span_warning("\The [src] can only be deployed in space."))

	if(status != SHELTER_DEPLOY_ALLOWED)
		return FALSE

	return TRUE

// First step: Warn and cancel deployment if necessary conditions aren't met. Otherwise generate smoke and wait a moment.
/obj/item/survivalcapsule/proc/deploy_step_one(mob/user)
	var/turf/deploy_location = get_turf(src)
	// We might have moved since the last check, so we check again!
	if(!can_deploy(deploy_location, GetAbove(deploy_location)))
		used = FALSE
		return

	var/datum/effect/effect/system/smoke_spread/smoke = new /datum/effect/effect/system/smoke_spread()
	smoke.attach(deploy_location)
	smoke.set_up(10, 0, deploy_location)
	smoke.start()

	after(src, 4 SECONDS, PROC_REF(deploy_step_two), with = list(user))

// Second step: Load shelter template at location
/obj/item/survivalcapsule/proc/deploy_step_two(mob/user)
	var/turf/deploy_location = get_turf(src)
	var/turf/above_location = GetAbove(deploy_location)
	// We might have moved since the last check, so we check again!
	if(!can_deploy(deploy_location, above_location))
		used = FALSE
		return

	if(unique_id)
		GLOB.unique_deployable += unique_id

	log_and_message_admins("[admin_log_verb] at [get_area(deploy_location)]!", user)

	play_sfx(src, SFX_EFFECTS_PHASEIN)

	// Load shelter template
	if(above_location)
		template().add_roof(above_location)
	template().annihilate_plants(deploy_location)
	// The template loads as a job; its lighting is built when it has (the capsule is consumed meanwhile).
	template().load_async(deploy_location, TRUE, TYPE_PROC_REF(/datum/map_template/shelter, shelter_loaded), template(), list(deploy_location.x, deploy_location.y, deploy_location.z))
	consume(src, user)

/obj/item/survivalcapsule/examine(mob/user)
	. = ..()
	var/temp_info = get_template_info()
	if(length(temp_info))
		. += temp_info

CAPABILITIES(/obj/item/survivalcapsule)
	op("deploy", in_hand(), priority(OP_PRIORITY_DEFAULT - 1), label("Deploy"), then(PROC_REF(survivalcapsule_deploy)))

/// Old attack_self: deploy the shelter (survivalcapsule_self() asks its questions by re-running itself with the same arguments). It does not work in VR.
/obj/item/survivalcapsule/proc/survivalcapsule_deploy(datum/act/op/A)
	if(istype(get_area(A.actor), /area/vr))
		to_chat(A.actor, span_warning("It doesn't work in VR."))
		return OP_OK
	survivalcapsule_self(A.actor, A.held)
	return OP_OK

/// Old attack_self: deploy the shelter. Virtual: the superpose capsules override it with ..() last.
/obj/item/survivalcapsule/proc/survivalcapsule_self(mob/user, obj/item/held = null, selected_template = null)
	get_template()
	if(!used)
		if(unique_id && (unique_id in GLOB.unique_deployable))
			loc.visible_message(span_warning("There can only be one [src] deployed at a time."))
			return
		var/turf/deploy_location = get_turf(src)
		// Warn the user in advance if the capsule can't work from where they're standing.
		var/preview_render = preview_template(user, deploy_location)
		// If there's no preview render, that means it couldn't get the bottom-left or top-right corner of the shelter template area
		// So this is prooooobably somewhere outside the map bounds!
		if(!preview_render)
			loc.visible_message(span_warning("\The [src] is too close to the edge of this map to deploy!"))
			return
		if(!can_deploy(get_turf(src), GetAbove(deploy_location)))
			after(src, 1 SECONDS, PROC_REF(remove_preview), with = list(user, preview_render))
			return
		// We only show where the doors will be on a successful deploy check to avoid player confusion.
		remove_preview(user, preview_render, 0)
		preview_render = preview_template(user, deploy_location, show_doors = TRUE)
		var/_answer_k433 = rerun_ask(user, "k433", PROC_REF(survivalcapsule_self), args, /datum/prompt/choice, question = "Confirm location. (The shelter's exterior doors are highlighted in green!)", title = "Shelter Deploy Confirm", choices = list("No","Yes"), buttons = TRUE)
		if(isnull(_answer_k433))
			return TRUE
		if(_answer_k433 == "Yes")
			// We might have moved since the last check, so we check again!
			if(!can_deploy(deploy_location, GetAbove(deploy_location)))
				used = FALSE
				return
			loc.visible_message(span_warning("\The [src] begins to shake. Stand back!"))
			user.drop_from_inventory(src)
			used = TRUE

			after(src, 5 SECONDS, PROC_REF(deploy_step_one), with = list(user))
		remove_preview(user, preview_render, 0)

/obj/item/survivalcapsule/luxury
	name = "luxury surfluid shelter capsule"
	desc = "An exorbitantly expensive luxury suite programmed into construction nanomachines. There's a license for use printed on the bottom."
	template_id = "shelter_beta"

/obj/item/survivalcapsule/luxuryalt
	name = "luxury alt surfluid shelter capsule"
	desc = "An exorbitantly expensive luxury suite programmed into construction nanomachines. There's a license for use printed on the bottom."
	template_id = "shelter_luxury_alt"

/obj/item/survivalcapsule/pocketdorm
	name = "pocket dorm surfluid shelter capsule"
	desc = "A little dorm programmed into construction nanomachines. There's a license for use printed on the bottom."
	template_id = "shelter_pocket_dorm"

/obj/item/survivalcapsule/kitchen
	name = "pocket dorm surfluid shelter capsule"
	desc = "A kitchen programmed into construction nanomachines. There's a license for use printed on the bottom."
	template_id = "shelter_kitchen"

/obj/item/survivalcapsule/luxurybar
	name = "luxury surfluid bar capsule"
	desc = "A luxury bar in a capsule. " + JOB_BARTENDER + " required and not included. There's a license for use printed on the bottom."
	template_id = "shelter_gamma"

/obj/item/survivalcapsule/luxurycabin
	name = "luxury surfluid cabin capsule"
	desc = "A luxury cabin and kitchen in a capsule. There's a license for use printed on the bottom."
	template_id = "shelter_cab_deluxe"

/obj/item/survivalcapsule/luxurycafe
	name = "luxury surfluid cafe capsule"
	desc = "A luxury cafe in a capsule. There's a license for use printed on the bottom."
	template_id = "shelter_cafe"

/obj/item/survivalcapsule/luxuryrecroom
	name = "luxury rec room cafe capsule"
	desc = "A luxury rec room in a capsule. There's a license for use printed on the bottom."
	template_id = "shelter_luxury_recroom"

/obj/item/survivalcapsule/military
	name = "military surfluid shelter capsule"
	desc = "A prefabricated firebase in a capsule. Contains basic weapons, building materials, and combat suits. There's a license for use printed on the bottom."
	template_id = "shelter_delta"

/obj/item/survivalcapsule/escapepod
	name = "escape surfluid shelter capsule"
	desc = "A prefabricated escape pod in a capsule. Contains a basic escape pod for survival purposes. There's a license for use printed on the bottom."
	template_id = "shelter_epsilon"
	unique_id = "shelter_5"
	is_ship = TRUE

/obj/item/survivalcapsule/popcabin
	name = "pop-out cabin shelter capsule"
	desc = "A cozy cabin; crammed into a survival capsule."
	template_id = "shelter_cab"

/obj/item/survivalcapsule/dropship
	name = "dropship surfluid shelter capsule"
	desc = "A military dropship in a capsule. Contains everything an assault squad would need, minus the squad itself. This capsule is significantly larger than most. There's a license for use printed on the bottom."
	template_id = "shelter_zeta"
	unique_id = "shelter_6"
	is_ship = TRUE
	w_class = ITEMSIZE_SMALL

/obj/item/survivalcapsule/recroom
	name = "pop-out rec room shelter capsule"
	desc = "A recreational room stuffed into a survival capsule."
	template_id = "shelter_recroom"

/obj/item/survivalcapsule/sauna
	name = "pop-out sauna shelter capsule"
	desc = "A cozy sauna room stuffed into a survival capsule."
	template_id = "shelter_sauna"

/obj/item/survivalcapsule/cafe
	name = "pop-out cafe shelter capsule"
	desc = "A cozy cafe stuffed into a survival capsule."
	template_id = "shelter_cafe"

//Custom Shelter Capsules
/obj/item/survivalcapsule/tabiranth
	name = "silver-trimmed surfluid shelter capsule"
	desc = "An exorbitantly expensive luxury suite programmed into construction nanomachines. This one is a particularly rare and expensive model. There's a license for use printed on the bottom."
	template_id = "shelter_phi"
	unique_id = "shelter_a"

/obj/item/survivalcapsule/holly
	name = "vaguely festive surfluid shelter capsule"
	desc = "A \"homemade\" luxury suite crammed into a capsule. There's a license for use printed on the bottom. For some reason, the license's text is written in festive colors."
	template_id = "shelter_chi"
	unique_id = "shelter_h"

//Stupid
/obj/item/survivalcapsule/loss_1
	name = "clinical surfluid shelter capsule"
	desc = "A strange-looking shelter capsule. It looks rather crudely thrown together..."
	template_id = "shelter_loss1"

/obj/item/survivalcapsule/loss_2
	name = "clinical surfluid shelter capsule"
	desc = "A strange-looking shelter capsule. It looks rather crudely thrown together..."
	template_id = "shelter_loss2"

/obj/item/survivalcapsule/loss_3
	name = "clinical surfluid shelter capsule"
	desc = "A strange-looking shelter capsule. It looks rather crudely thrown together..."
	template_id = "shelter_loss3"

/obj/item/survivalcapsule/loss_4
	name = "clinical surfluid shelter capsule"
	desc = "A strange-looking shelter capsule. It looks rather crudely thrown together..."
	template_id = "shelter_loss4"

//Redspace Capsule
//Spawns a randomized shelter from a curated selection of possibilities
/obj/item/survivalcapsule/randomized
	name = "redspace shelter capsule"
	desc = "A strange-looking shelter capsule. Should the surfluid inside it be bubbling like that? There's a license for use printed on the bottom, as well as a warning about the unpredictable nature of redspace."
	template_id = "placeholder_id_do_not_change"
	admin_log_verb = "activated a redspace capsule"
	var/possible_shelter_ids = list(
		// "Normal" map table - Most common table.
		// Meant to be actually inhabitable spots with neat things in them.
		list(
			"shelter_pizza_kitchen",
			"shelter_nerd_dungeon_good",
			"shelter_gallery",
			"shelter_garden",
			"shelter_off_color",
			"shelter_living_room",
			"shelter_candlelit_dinner",
		) = 65, // 65% chance

		// "Weird" map table - Less common.
		// Here, we get a little silly with it. Not dangerous, but weird, kinda like redgates.
		list(
			"shelter_nerd_dungeon_evil",
			"shelter_tiny_space",
			"shelter_christmas",
			"shelter_blacksmith",
		) = 30, // 30% chance

		// "Dangerous" map table - Least common by far, and for good reason.
		// Places that have dangerous/illegal stuff in them.
		list(
			"shelter_dangerous_pool",
			"shelter_methlab",
			"shelter_mimic_hell",
		) = 5, // 5% chance
	)

/obj/item/survivalcapsule/randomized/get_template_id()
	// Choose which table of maps we're gonna be choosing from, then pick a map in those
	return pick(pickweight(possible_shelter_ids))

/obj/item/survivalcapsule/randomized/get_template_info()
	var/ret = "It has a chaotic redspace bubble inside. The label reads:\n"
	ret += "(7x7) This capsule utilizes experimental technology to replicate copies of redspace pockets within realspace. " + span_underline("The contents of this capsule are prone to change upon activation") + ", and are highly unlikely to remain the same as when previously used. Efforts have been made to ensure *likely* safety when using these capsules. However, due to the unpredictable nature of redspace, that safety cannot be fully guaranteed. " + span_underline("Use at your own risk!")
	return ret

// TERRIBLE AWFUL CAPSULE DO NOT MAKE THIS PLAYER ACCESSIBLE, I made this for a BIT -Ryumi
/obj/item/survivalcapsule/tesla
	name = "tesla in a shelter capsule"
	desc = "This is a terrible, terrible idea."
	template_id = "shelter_tesla"
	admin_log_verb = "activated a TESLA capsule"

/obj/item/survivalcapsule/tesla/get_template_info()
	var/ret = ..()
	ret += ("\n" + span_boldwarning("Do not."))
	return ret

//Pod objects
//Walls
/turf/simulated/shuttle/wall/voidcraft/survival
	name = "survival shelter"
	stripe_color = "#efbc3b"

/turf/simulated/shuttle/wall/voidcraft/survival/hard_corner
	hard_corner = 1
	icon_state = "void-hc"

//Doors
/obj/machinery/door/airlock/voidcraft/survival_pod
	name = "survival airlock"
	block_air_zones = 1

/obj/machinery/door/airlock/voidcraft/survival_pod/vertical
	icon = 'icons/obj/doors/shuttledoors_vertical.dmi'

//Door access setter button
/obj/machinery/button/remote/airlock/survival_pod
	name = "shelter privacy control"
	desc = "You can secure yourself inside the shelter here."
	specialfunctions = 4 // 4 is bolts
	id = "placeholder_id_do_not_use" //This has to be this way, otherwise it will control ALL doors if left blank.
	var/tmp/obj/machinery/door/airlock/voidcraft/survival_pod/door

// A hand on it works the glass of the pod's door (it does not press the remote button: the airlocks it names are a placeholder).
CAPABILITIES(/obj/machinery/button/remote/airlock/survival_pod)
	without("press_hand")
	op("pod_use", hand(), label("Use"), wait(0), needs(req(PROC_REF(hand_ok), because = PROC_REF(hand_refusal))), then(PROC_REF(pod_used)))

/obj/machinery/button/remote/airlock/survival_pod/proc/pod_used(datum/act/op/A)
	pod_glass()
	return OP_OK

/obj/machinery/button/remote/airlock/survival_pod/proc/pod_glass()
	if(!linked_door())
		var/turf/dT = get_step(src,dir)
		rel_set(src, nameof(src.door), locate_within(dT, /obj/machinery/door/airlock/voidcraft/survival_pod))
	if(linked_door())
		linked_door().glass = !linked_door().glass
		linked_door().opacity = !linked_door().opacity

//Subtype that actually bolts doors!
/obj/machinery/button/remote/airlock/survival_pod/bolts
	name = "shelter privacy control"
	desc = "You can ensure some privacy with this."

/// The glass first, then the bolts.
/obj/machinery/button/remote/airlock/survival_pod/bolts/pod_used(datum/act/op/A)
	pod_glass()
	if(linked_door())
		if(is_bolted(linked_door()))
			set_bolted(linked_door(), FALSE)
			linked_door().stop_blocking_light()
		else
			set_bolted(linked_door(), TRUE)
			// Block light when bolted, since the door is effectively functioning like polarized glass
			linked_door().start_blocking_light()
	return OP_OK

// Capsule-specific light switch
// Turns off only one light in a given direction from its source turf.
/obj/machinery/light_switch/survival_pod
	name = "shelter light switch"
	var/tmp/obj/machinery/light/target_light

// Deliberately override base light switch behavior because we don't want to toggle ALL lights in the area - just one!
CAPABILITIES(/obj/machinery/light_switch/survival_pod)
	op("toggle_impl", hand(), ungated(), priority(OP_PRIORITY_DEFAULT - 1), label("Use"), then(PROC_REF(interaction_toggle_impl)))

/obj/machinery/light_switch/survival_pod/proc/interaction_toggle_impl(datum/act/op/A)
	set_on(!on)
	play_sfx(src, SFX_MACHINES_BUTTON, volume = 100)
	if(!target_light())
		var/turf/dT = get_step(src, dir)
		rel_set(src, nameof(target_light), locate_within(dT, /obj/machinery/light))
	if(target_light())
		target_light().on = on
		target_light().refresh_light()
		// I'm so sorry but for some ungodly reason calling update() simply isn't
		// enough to make the light actually set its lighting.
		// So I guess we're doing this manually! :')
		if(target_light().on)
			target_light().set_light(target_light().brightness_range, target_light().brightness_power, target_light().brightness_color)
			target_light().overlay_color = target_light().brightness_color
		else
			target_light().set_light(0)

	GLOB.lights_switched_on_roundstat++
	return OP_OK

//Windows
/obj/structure/window/reinforced/survival_pod
	name = "pod window"
	icon = 'icons/obj/survival_pod.dmi'
	icon_state = "pwindow"
	basestate = "pwindow"

//The windows have diagonal versions, and will never be a full window
/obj/structure/window/reinforced/survival_pod/is_fulltile()
	return FALSE

DECLARE_APPEARANCE_PROC(/obj/structure/window/reinforced/survival_pod, TYPE_PROC_REF(/atom, appearance_overlays), list())
/obj/structure/window/reinforced/survival_pod/appearance_overlays()
	. = list()
	icon_state = basestate

//Polarized windows
/obj/structure/window/reinforced/polarized/survival_pod
	name = "polarized pod window"
	icon = 'icons/obj/survival_pod.dmi'
	icon_state = "pwindow"
	basestate = "pwindow"

//The windows have diagonal versions, and will never be a full window
/obj/structure/window/reinforced/polarized/survival_pod/is_fulltile()
	return FALSE

//Windoor
/obj/machinery/door/window/survival_pod
	icon = 'icons/obj/survival_pod.dmi'
	icon_state = "windoor"
	base_state = "windoor"

//Table
/obj/structure/table/survival_pod
	name = "table"
	icon = 'icons/obj/survival_pod.dmi'
	icon_state = "table"
	plating_id = MAT_STEEL
	can_reinforce = FALSE
	can_plate = FALSE
	can_flip_verb = FALSE
	can_dismantle = FALSE

/obj/structure/table/survival_pod/draws_layers()
	return FALSE

/obj/structure/table/survival_pod/draw(datum/look/look)
	..()
	look.state("table")

//Sleeper
/obj/machinery/sleeper/survival_pod
	desc = "A limited functionality sleeper, all it can do is put patients into stasis. It lacks the medication and configuration of the larger units."
	icon = 'icons/obj/survival_pod.dmi'
	icon_state = "sleeper"

/// The pod's own sprite: its cover closes over an occupant.
/obj/machinery/sleeper/survival_pod/draw(datum/look/look)
	..()
	look.state("sleeper")
	look.overlay("sleeper_cover", when = !!occupant_of(src))

//Computer
/obj/item/gps/computer
	name = "pod computer"
	icon_state = "pod_computer"
	icon = 'icons/obj/survival_pod_comp.dmi'
	anchored = TRUE
	density = TRUE
	pixel_y = -32

CAPABILITIES(/obj/item/gps/computer)
	op("disassemble", tool(TOOL_WRENCH), label("Disassemble"), begins(PROC_REF(disassemble_begins)), wait(4 SECONDS), then(PROC_REF(disassemble_done)))
	op("hand", hand(), ungated(), label("Use"), then(PROC_REF(interaction_hand)))

/obj/item/gps/computer/proc/disassemble_begins(datum/act/op/A)
	return msg_text(span_notice("You start to disassemble %T%..."), span_warning("%U% disassembles %T%."), "You hear clanking and banging noises.")

/obj/item/gps/computer/proc/disassemble_done(datum/act/op/A)
	replace_with(src, /obj/item/gps)
	return OP_OK

/// Old attack_hand.
/obj/item/gps/computer/proc/interaction_hand(datum/act/op/A)
	var/mob/user = A.actor
	attack_self(user)
	return TRUE

//Bed
/obj/structure/bed/pod
	icon = 'icons/obj/survival_pod.dmi'
	icon_state = "bed"

/obj/structure/bed/pod
	material_key = MAT_STEEL
	padding_key = MAT_CLOTH

//Survival Storage Unit
/obj/machinery/smartfridge/survival_pod
	name = "survival pod storage"
	desc = "A heated storage unit."
	icon_state = "donkvendor"
	icon_base = "donkvendor"
	icon_contents = null
	icon = 'icons/obj/survival_pod_vend.dmi'
	light_range = 5
	light_power = 1.2
	light_color = "#DDFFD3"
	light_on = TRUE
	pixel_y = -4
	max_n_of_items = 100

// ALLOW(init/INSTANCE_STATE): stocks the items the map placed on its tile
/obj/machinery/smartfridge/survival_pod/Initialize(mapload)
	. = ..()
	for(var/obj/item/O in contents_of(loc))
		if(accept_check(O))
			stock(O)

/obj/machinery/smartfridge/survival_pod/accept_check(obj/item/O)
	return isitem(O)

/obj/machinery/smartfridge/survival_pod/empty
	name = "dusty survival pod storage"
	desc = "A heated storage unit. This one's seen better days."

//Fans
/obj/structure/fans
	icon = 'icons/obj/survival_pod.dmi'
	icon_state = "fans"
	name = "environmental regulation system"
	desc = "A large machine releasing a constant gust of air."
	anchored = TRUE
	density = TRUE
	can_atmos_pass = ATMOS_PASS_NO
	var/buildstacktype = /obj/item/stack/material/steel
	var/buildstackamount = 5

// start - fans weren't updating atmos when destroyed or placed

/obj/structure/fans/Initialize(mapload)
	.=..()
	update_nearby_tiles()
// end

/obj/structure/fans/atom_deconstruct()
	replace_with(src, buildstacktype, buildstackamount)

CAPABILITIES(/obj/structure/fans)
	op("disassemble", tool(TOOL_WRENCH), label("Disassemble"), begins(PROC_REF(disassemble_begins)), wait(4 SECONDS), then(PROC_REF(disassemble_done)))

/obj/structure/fans/proc/disassemble_begins(datum/act/op/A)
	return msg_text(span_notice("You start to disassemble %T%..."), span_warning("%U% disassembles %T%."), "You hear clanking and banging noises.")

/obj/structure/fans/proc/disassemble_done(datum/act/op/A)
	atom_deconstruct(TRUE)
	return OP_OK

/obj/structure/fans/tiny
	name = "tiny fan"
	desc = "A tiny fan, releasing a thin gust of air."
	plane = TURF_PLANE
	layer = ABOVE_TURF_LAYER
	density = FALSE
	icon_state = "fan_tiny"
	buildstackamount = 2

/obj/structure/fans/hardlight
	resistance_flags = BOMB_PROOF
	name = "hardlight shield"
	desc = "Retains air, allows passage."
	plane = TURF_PLANE
	layer = ABOVE_TURF_LAYER
	density = FALSE
	icon = 'icons/effects/effects_vr.dmi'
	icon_state = "hardlight"
	buildstackamount = 2

	light_range = 3
	light_power = 1
	light_color = "#FFFFFF"
	light_on = TRUE

/obj/structure/fans/hardlight/colorable
	name = "hardlight shield"
	icon_state = "hardlight_colorable"

/obj/structure/fans/hardlight/colorable/abductor
	name = "hardlight shield"
	icon_state = "hardlight_colorable"
	color = "#ff0099"

//Signs
/obj/structure/sign/mining
	name = "nanotrasen mining corps sign"
	desc = "A sign of relief for weary miners, and a warning for would-be competitors to Nanotrasen's mining claims."
	icon = 'icons/obj/survival_pod.dmi'
	icon_state = "ntpod"

/obj/structure/sign/mining/survival
	name = "shelter sign"
	desc = "A high visibility sign designating a safe shelter."
	icon = 'icons/obj/survival_pod.dmi'
	icon_state = "survival"

//Fluff
/obj/structure/tubes
	icon_state = "tubes"
	icon = 'icons/obj/survival_pod.dmi'
	name = "tubes"
	anchored = TRUE
	layer = BELOW_MOB_LAYER
	density = FALSE

/// Accessor for a shared definition.
/obj/item/survivalcapsule/proc/template() as /datum/map_template/shelter
	return template_static

/// Accessor for the door var.
/obj/machinery/button/remote/airlock/survival_pod/proc/linked_door() as /obj/machinery/door/airlock/voidcraft/survival_pod
	return door

/// Accessor for the target_light var.
/obj/machinery/light_switch/survival_pod/proc/target_light() as /obj/machinery/light
	return target_light

/obj/item/survivalcapsule/superpose/proc/open_template_request(mob/user, obj/item/held)
	var/original_client_ckey
	if(istype(user, /client))
		var/client/C = user
		original_client_ckey = C.ckey
		user = C.mob
	if(!ismob(user) || QDELETED(user))
		return
	open_request(src, /datum/prompt/choice/shelter_template, PROC_REF(template_chosen), answerer = user, captured_item = held, item_expected = !isnull(held), choices = template_ids, original_client_ckey = original_client_ckey)

/obj/item/survivalcapsule/superpose/proc/template_chosen(datum/act/request/A)
	if(!A.answer)
		return
	apply_template_answer(A)
	SStgui.update_uis(src)

/obj/item/survivalcapsule/superpose/proc/apply_template_answer(datum/act/request/A)
	var/datum/prompt/choice/shelter_template/request = A.request
	if(request.captures_gone())
		return
	var/mob/user = request.original_client_ckey ? GLOB.directory[request.original_client_ckey] : request.answerer
	return survivalcapsule_self(user, request.captured_item, A.answer.value)

/datum/prompt/choice/shelter_template
	question = "Which template would you like to load?"
	title = "Available Templates"
	timeout = 0
	var/obj/item/captured_item
	var/item_expected = FALSE
	var/original_client_ckey

CAPABILITIES(/datum/prompt/choice/shelter_template)
	ref_one(nameof(captured_item), /obj/item)

/datum/prompt/choice/shelter_template/prepare(datum/act/A)
	. = ..()
	var/obj/item/item = captured_item
	rel_clear(src, nameof(captured_item))
	rel_set(src, nameof(captured_item), item)

/datum/prompt/choice/shelter_template/proc/captures_gone()
	return QDELETED(answerer) || (item_expected && QDELETED(captured_item)) || (original_client_ckey && !GLOB.directory[original_client_ckey])

/datum/prompt/choice/shelter_template/recheck_extra()
	. = ..()
	if(.)
		return
	if(captures_gone())
		return "gone"
	return null
