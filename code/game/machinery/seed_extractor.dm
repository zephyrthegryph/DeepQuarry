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

/* Currently part upgrades do nothing
/obj/machinery/seed_extractor/RefreshParts()
	..()
*/

CAPABILITIES(/obj/machinery/seed_extractor)
	op("extract_grown", inputs(item(/obj/item/reagent_containers/food/snacks/grown), item(/obj/item/grown)), priority(OP_PRIORITY_DEFAULT - 1), label("Extract seeds"), then(PROC_REF(interaction_extract_grown)))
	op("extract_grass", item(/obj/item/stack/tile/grass), priority(OP_PRIORITY_DEFAULT - 1), label("Extract seeds"), then(PROC_REF(interaction_extract_grass)))
	op("pulverize_fossil", item(/obj/item/fossil/plant), priority(OP_PRIORITY_DEFAULT - 1), label("Pulverize"), then(PROC_REF(interaction_pulverize_fossil)))
	op("part_replacement", item(/obj/item/storage/part_replacer), priority(OP_PRIORITY_DEFAULT - 1), label("Replace parts"), then(TYPE_PROC_REF(/obj/machinery, op_part_replacement)))
	default_parts()

/obj/machinery/seed_extractor/proc/interaction_extract_grown(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/O = A.held
	var/datum/seed/new_seed_type
	if(istype(O, /obj/item/grown))
		var/obj/item/grown/F = O
		new_seed_type = SSplants.seeds[F.plantname]
	else
		var/obj/item/reagent_containers/food/snacks/grown/F = O
		new_seed_type = SSplants.seeds[F.plantname]

	var/produce_name = "[O]"
	if(!consume(O, user))
		return OP_OK
	if(new_seed_type)
		to_chat(user, span_notice("You extract some seeds from [produce_name]."))
		var/produce = rand(1,4)
		for(var/i = 0;i<=produce;i++)
			var/obj/item/seeds/seeds = new(get_turf(src))
			seeds.seed_type = new_seed_type.name
			seeds.update_seed()
	else
		to_chat(user, "[produce_name] doesn't seem to have any usable seeds inside it.")
	return OP_OK

/obj/machinery/seed_extractor/proc/interaction_extract_grass(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/O = A.held
	var/obj/item/stack/tile/grass/S = O
	if(S.use(1))
		to_chat(user, span_notice("You extract some seeds from the grass tile."))
		new /obj/item/seeds/grassseed(loc)
	return OP_OK

/obj/machinery/seed_extractor/proc/interaction_pulverize_fossil(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/O = A.held
	var/fossil_name = "\the [O]"
	if(!consume(O, user))
		return OP_OK
	var/obj/item/seeds/random/R = new(get_turf(src))
	to_chat(user, "\The [src] pulverizes [fossil_name] and spits out \the [R].")
	return OP_OK
