/obj/machinery/seed_extractor
	maintenance_flags = MACHINE_MAINT_STANDARD_MOVABLE
	maintenance_wrench_time = 20
	name = "seed extractor"
	desc = "Extracts and bags seeds from produce."
	icon = 'icons/obj/hydroponics_machines.dmi'
	icon_state = "sextractor"
	density = TRUE
	anchored = TRUE
	circuit = /obj/item/circuitboard/botany_seedextractor

/obj/machinery/seed_extractor/Initialize(mapload)
	. = ..()
	default_apply_parts()

/* Currently part upgrades do nothing
/obj/machinery/seed_extractor/RefreshParts()
	..()
*/

/obj/machinery/seed_extractor/declare_interactions(list/into)
	into += list(
		/datum/interaction/machine_item/seed_extractor_grown,
		/datum/interaction/machine_item/seed_extractor_grass,
		/datum/interaction/machine_item/seed_extractor_fossil,
		/datum/interaction/machine_item/part_replacement,
		/datum/interaction/machine_item/seed_extractor_swallow,
	)
	..()

/// Fruits and vegetables.
/datum/interaction/machine_item/seed_extractor_grown
	id = "seed_extractor_grown"
	name = "Extract seeds"
	held_type = list(/obj/item/reagent_containers/food/snacks/grown, /obj/item/grown)
	effect = /obj/machinery/seed_extractor/proc/interaction_extract_grown

/obj/machinery/seed_extractor/proc/interaction_extract_grown(mob/user, obj/item/O, datum/interaction/interaction)
	user.remove_from_mob(O)

	var/datum/seed/new_seed_type
	if(istype(O, /obj/item/grown))
		var/obj/item/grown/F = O
		new_seed_type = SSplants.seeds[F.plantname]
	else
		var/obj/item/reagent_containers/food/snacks/grown/F = O
		new_seed_type = SSplants.seeds[F.plantname]

	if(new_seed_type)
		to_chat(user, span_notice("You extract some seeds from [O]."))
		var/produce = rand(1,4)
		for(var/i = 0;i<=produce;i++)
			var/obj/item/seeds/seeds = new(get_turf(src))
			seeds.seed_type = new_seed_type.name
			seeds.update_seed()
	else
		to_chat(user, "[O] doesn't seem to have any usable seeds inside it.")

	qdel(O)
	return TRUE

/// Grass.
/datum/interaction/machine_item/seed_extractor_grass
	id = "seed_extractor_grass"
	name = "Extract seeds"
	held_type = /obj/item/stack/tile/grass
	effect = /obj/machinery/seed_extractor/proc/interaction_extract_grass

/obj/machinery/seed_extractor/proc/interaction_extract_grass(mob/user, obj/item/O, datum/interaction/interaction)
	var/obj/item/stack/tile/grass/S = O
	if(S.use(1))
		to_chat(user, span_notice("You extract some seeds from the grass tile."))
		new /obj/item/seeds/grassseed(loc)
	return TRUE

/// Fossils.
/datum/interaction/machine_item/seed_extractor_fossil
	id = "seed_extractor_fossil"
	name = "Pulverize"
	held_type = /obj/item/fossil/plant
	effect = /obj/machinery/seed_extractor/proc/interaction_pulverize_fossil

/obj/machinery/seed_extractor/proc/interaction_pulverize_fossil(mob/user, obj/item/O, datum/interaction/interaction)
	var/obj/item/seeds/random/R = new(get_turf(src))
	to_chat(user, "\The [src] pulverizes \the [O] and spits out \the [R].")
	qdel(O)
	return TRUE

/// Anything else: the old attackby never chained to ..(), so it silently swallowed the hit.
/datum/interaction/machine_item/seed_extractor_swallow
	id = "seed_extractor_swallow"
	name = "Use"
	held_type = /obj/item
	effect = /obj/machinery/seed_extractor/proc/interaction_swallow

/obj/machinery/seed_extractor/proc/interaction_swallow(mob/user, obj/item/held, datum/interaction/interaction)
	return TRUE
