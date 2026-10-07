/obj/item/reagent_containers/food/snacks/grown/sif
	var/seeds = 0

CAPABILITIES(/obj/item/reagent_containers/food/snacks/grown/sif)
	rolls(nameof(seeds), range_of(1, 2))
	op("sif_grown_item", item(/obj/item), priority(OP_PRIORITY_DEFAULT), label("Sif grown item"), then(PROC_REF(sif_grown_item)))

/obj/item/reagent_containers/food/snacks/grown/sif/examine(mob/user)
	. = ..()
	if(seeds)
		to_chat(user, span_notice("You can see [seeds] seed\s in \the [src]. You might be able to extract them with a sharp object."))

/// Old attackby. FALSE falls to the grown handling, as the old ..() did.
/obj/item/reagent_containers/food/snacks/grown/sif/proc/sif_grown_item(datum/act/op/A)
	var/mob/living/user = A.actor
	var/obj/item/W = A.held
	if(seed() && W.sharp && seeds > 0)
		var/take_seeds = min(seeds, rand(1,2))
		seeds -= take_seeds
		to_chat(user, span_notice("You stick \the [W] into \the [src] and lever out [take_seeds] seed\s."))
		for(var/i = 1 to take_seeds)
			new /obj/item/seeds(get_turf(src), seed().name)
		return OP_PASS
	return OP_DECLINE

/obj/item/reagent_containers/food/snacks/grown/sif/sifpod
	plantname = PLANT_SIFBULB

/obj/item/reagent_containers/food/snacks/grown/sif/wabback
	plantname = PLANT_WHITEWABBACK

/obj/item/reagent_containers/food/snacks/grown/sif/blackwabback
	plantname = PLANT_BLACKWABBACK

/obj/item/reagent_containers/food/snacks/grown/sif/wildwabback
	plantname = PLANT_WILDWABBACK

/obj/item/reagent_containers/food/snacks/grown/sif/eyebulbs
	plantname = "eyebulbs"

/obj/item/reagent_containers/food/snacks/grown/sif/cavebulbs
	plantname = "cavebulbs"
