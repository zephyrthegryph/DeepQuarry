/obj/item/rocksliver
	name = "rock sliver"
	desc = "It looks extremely delicate."
	icon = 'icons/obj/xenoarchaeology.dmi'
	icon_state = "sliver1"
	randpixel = 8
	w_class = ITEMSIZE_TINY
	sharp = TRUE
	injury_kind = INJURY_PIERCE
	/// The sliver's own geosample (a private copy of the sampled one; owned).
	var/tmp/datum/geosample/geological_data_static

CAPABILITIES(/obj/item/rocksliver)
	owns_one(nameof(geological_data_static), /datum/geosample)
	rolls(nameof(icon_state), PROC_REF(roll_icon_state))
	rolls(ROLL_PIXEL, PIXEL_JITTER(nameof(randpixel)))

/// Rolled before init (rolls(), code/engine/lifeforms/rolls.dm): what the old Initialize() drew from the world RNG.
/obj/item/rocksliver/proc/roll_icon_state(datum/roller/R)
	return "sliver[R.number(1, 3)]"

/datum/geosample
	var/age = 0
	var/age_thousand = 0
	var/age_million = 0
	var/age_billion = 0
	var/artifact_id = ""
	var/artifact_distance = -1
	var/source_mineral = REAGENT_ID_CHLORINE
	var/list/find_presence

/datum/geosample/New(turf/simulated/mineral/container)
	UpdateTurf(container)

/// A private copy: a mine turf, each ore dug from it and each sample own their own geosample
/// (never one shared owned instance).
/datum/geosample/proc/copy()
	var/datum/geosample/G = new /datum/geosample(null)
	G.age = age
	G.age_thousand = age_thousand
	G.age_million = age_million
	G.age_billion = age_billion
	G.artifact_id = artifact_id
	G.artifact_distance = artifact_distance
	G.source_mineral = source_mineral
	G.find_presence = LAZYCOPY(find_presence)
	return G

/datum/geosample/proc/UpdateTurf(turf/simulated/mineral/container)
	if(!istype(container))
		return

	age = rand(1, 999)

	if(container.mineral())
		var/list/ages = TYPE_TABLE_GET(container.mineral(), ore_xarch_ages)
		if(islist(ages))
			if(ages["thousand"])
				age_thousand = rand(1, ages["thousand"])
			if(ages["million"])
				age_million = rand(1, ages["million"])
			if(ages["billion"])
				if(ages["billion_lower"])
					age_billion = rand(ages["billion_lower"], ages["billion"])
				else
					age_billion = rand(1, ages["billion"])
		if(container.mineral().xarch_source_mineral)
			source_mineral = container.mineral().xarch_source_mineral

	if(prob(75))
		LAZYSET(find_presence, REAGENT_ID_PHOSPHORUS, rand(1, 500) / 100)
	if(prob(25))
		LAZYSET(find_presence, REAGENT_ID_MERCURY, rand(1, 500) / 100)
	LAZYSET(find_presence, REAGENT_ID_CHLORINE, rand(500, 2500) / 100)

	for(var/datum/find/F in container.finds)
		var/responsive_reagent = get_responsive_reagent(F.find_type)
		LAZYSET(find_presence, responsive_reagent, 25) //Just making this phoron because this this feature was axed 8 years ago.

	var/total_presence = 0
	for(var/carrier in find_presence)
		total_presence += LAZYACCESS(find_presence, carrier)
	for(var/carrier in find_presence)
		LAZYSET(find_presence, carrier, LAZYACCESS(find_presence, carrier) / total_presence)

/datum/geosample/proc/UpdateNearbyArtifactInfo(turf/simulated/mineral/container)
	if(!container || !istype(container))
		return

	if(container.artifact_find)
		artifact_distance = rand()
		artifact_id = container.artifact_find.artifact_id
	else
		if(SSxenoarch) //Sanity check due to runtimes ~Z
			for(var/turf/simulated/mineral/T in SSxenoarch.artifact_spawning_turfs)
				if(T.artifact_find)
					var/cur_dist = get_dist(container, T) * 2
					if( (artifact_distance < 0 || cur_dist < artifact_distance))
						artifact_distance = cur_dist + rand() * 2 - 1
						artifact_id = T.artifact_find.artifact_id
				else
					rel_remove(SSxenoarch, nameof(/datum/system/xenoarch::artifact_spawning_turfs), T)

/obj/item/core_sampler
	name = "core sampler"
	desc = "Used to extract geological core samples."
	icon = 'icons/obj/device.dmi'
	icon_state = "sampler0"
	item_state = "screwdriver_brown"
	w_class = ITEMSIZE_TINY

	var/sampled_turf = ""
	var/num_stored_bags = 10
	var/obj/item/evidencebag/filled_bag
	pickup_sound = SFX_ITEMS_PICKUP_DEVICE
	drop_sound = SFX_ITEMS_DROP_DEVICE

CAPABILITIES(/obj/item/core_sampler)
	owns_one(nameof(filled_bag), /obj/item/evidencebag)

/obj/item/core_sampler/examine(mob/user)
	. = ..()
	if(get_dist(user, src) <= 2)
		. += span_notice("Used to extract geological core samples - this one is [sampled_turf ? "full" : "empty"], and has [num_stored_bags] bag[num_stored_bags != 1 ? "s" : ""] remaining.")

/// Old attackby.
/obj/item/core_sampler/proc/interaction_item(mob/living/user, obj/item/I, datum/interaction/interaction)
	if(istype(I, /obj/item/evidencebag))
		if(contents_count(I))
			to_chat(user, span_warning("\The [I] is full."))
			return INTERACTION_HANDLED_PASS
		if(num_stored_bags < 10)
			consume(I, user)
			num_stored_bags += 1
			to_chat(user, span_notice("You insert \the [I] into \the [src]."))
		else
			to_chat(user, span_warning("\The [src] can not fit any more bags."))
	else
		return FALSE
	return INTERACTION_HANDLED_PASS

/obj/item/core_sampler/proc/sample_item(item_to_sample, mob/user)
	var/datum/geosample/geo_data

	if(ismineralturf(item_to_sample))
		var/turf/simulated/mineral/T = item_to_sample
		T.geologic_data.UpdateNearbyArtifactInfo(T)
		geo_data = T.geologic_data
	else if(istype(item_to_sample, /obj/item/ore/archeology_debris))
		var/obj/item/ore/archeology_debris/O = item_to_sample
		geo_data = O.geologic_data

	if(geo_data)
		if(filled_bag)
			to_chat(user, span_warning("The core sampler is full."))
		else if(num_stored_bags < 1)
			to_chat(user, span_warning("The core sampler is out of sample bags."))
		else
			//create a new sample bag which we'll fill with rock samples
			rel_set(src, nameof(filled_bag), new /obj/item/evidencebag(src))
			filled_bag.name = "sample bag"
			filled_bag.desc = "a bag for holding research samples."

			icon_state = "sampler1"
			--num_stored_bags

			//put in a rock sliver
			var/obj/item/rocksliver/R = new(filled_bag)
			rel_set(R, nameof(R.geological_data_static), geo_data.copy())

			//update the sample bag
			filled_bag.icon_state = "evidence"
			var/image/I = image("icon"=R, "layer"=FLOAT_LAYER)
			add_overlay(I)
			add_overlay("evidence")
			filled_bag.w_class = ITEMSIZE_TINY

			to_chat(user, span_notice("You take a core sample of the [item_to_sample]."))
	else
		to_chat(user, span_warning("You are unable to take a sample of [item_to_sample]."))

DECLARE_INTERACTIONS(/obj/item/core_sampler, \
	INTERACT_USE(null, PROC_REF(interaction_self)), \
	INTERACT_ITEM(null, PROC_REF(interaction_item)), \
)

/// Old attack_self.
/obj/item/core_sampler/proc/interaction_self(mob/user, obj/item/held, datum/interaction/interaction)
	if(filled_bag)
		to_chat(user, span_notice("You eject the full sample bag."))
		var/success = 0
		if(istype(src.loc, /mob))
			var/mob/M = src.loc
			success = M.put_in_inactive_hand(filled_bag)
		if(!success)
			filled_bag.forceMove(get_turf(src))
		rel_take(src, nameof(filled_bag))
		icon_state = "sampler0"
	else
		to_chat(user, span_warning("The core sampler is empty."))


/// Accessor for the owned value.
/obj/item/rocksliver/proc/geological_data() as /datum/geosample
	return geological_data_static
