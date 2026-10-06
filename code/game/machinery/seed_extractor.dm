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

// ALLOW(init/INSTANCE_STATE): takes the parts it was built with
/obj/machinery/seed_extractor/Initialize(mapload)
	. = ..()
	default_apply_parts()

/* Currently part upgrades do nothing
/obj/machinery/seed_extractor/RefreshParts()
	..()
*/

EXTEND_INTERACTIONS(/obj/machinery/seed_extractor, \
	INTERACT_INSERT(list(/obj/item/reagent_containers/food/snacks/grown, /obj/item/grown), PROC_REF(interaction_extract_grown), "Extract seeds"), \
	INTERACT_INSERT(/obj/item/stack/tile/grass, PROC_REF(interaction_extract_grass), "Extract seeds"), \
	INTERACT_INSERT(/obj/item/fossil/plant, PROC_REF(interaction_pulverize_fossil), "Pulverize"), \
	INTERACT_INSERT(/obj/item/storage/part_replacer, TYPE_PROC_REF(/obj/machinery, interaction_part_replacement), "Replace parts"), \
	INTERACT_INSERT(/obj/item, TYPE_PROC_REF(/atom, interaction_swallow), "Use"), \
)

/obj/machinery/seed_extractor/proc/interaction_extract_grown(mob/user, obj/item/O, datum/interaction/interaction)
	var/datum/seed/new_seed_type
	if(istype(O, /obj/item/grown))
		var/obj/item/grown/F = O
		new_seed_type = SSplants.seeds[F.plantname]
	else
		var/obj/item/reagent_containers/food/snacks/grown/F = O
		new_seed_type = SSplants.seeds[F.plantname]

	var/produce_name = "[O]"
	if(!consume(O, user))
		return TRUE
	if(new_seed_type)
		to_chat(user, span_notice("You extract some seeds from [produce_name]."))
		var/produce = rand(1,4)
		for(var/i = 0;i<=produce;i++)
			var/obj/item/seeds/seeds = new(get_turf(src))
			seeds.seed_type = new_seed_type.name
			seeds.update_seed()
	else
		to_chat(user, "[produce_name] doesn't seem to have any usable seeds inside it.")
	return TRUE

/obj/machinery/seed_extractor/proc/interaction_extract_grass(mob/user, obj/item/O, datum/interaction/interaction)
	var/obj/item/stack/tile/grass/S = O
	if(S.use(1))
		to_chat(user, span_notice("You extract some seeds from the grass tile."))
		new /obj/item/seeds/grassseed(loc)
	return TRUE

/obj/machinery/seed_extractor/proc/interaction_pulverize_fossil(mob/user, obj/item/O, datum/interaction/interaction)
	var/fossil_name = "\the [O]"
	if(!consume(O, user))
		return TRUE
	var/obj/item/seeds/random/R = new(get_turf(src))
	to_chat(user, "\The [src] pulverizes [fossil_name] and spits out \the [R].")
	return TRUE

