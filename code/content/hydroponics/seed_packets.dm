REGISTRY_MEMBERSHIP(/obj/item/seeds, REGISTRY_SEED_PACKS)

//Seed packet object/procs.
/obj/item/seeds
	name = "packet of seeds"
	icon = 'icons/obj/seeds.dmi'
	icon_state = "blank"
	w_class = ITEMSIZE_SMALL

	var/seed_type
	var/tmp/datum/seed/seed_static
	var/modified = 0

/// Applied at init from its constructor param (param(apply =), code/engine/lifeforms/params.dm). A packet of an unknown seed keeps its own.
/obj/item/seeds/proc/seed_made(given_type)
	if(!(seed_type in SSplants.seeds))
		var/list/row = dq_variant_vars(/obj/item/seeds, variant)
		set_seed_type(row ? row["seed_type"] : initial(seed_type))
	update_seed()

//Grabs the appropriate seed datum from the global list.
/obj/item/seeds/proc/update_seed()
	if(!seed() && seed_type && !isnull(SSplants.seeds) && SSplants.seeds[seed_type])
		proto_set(src, nameof(seed_static), SSplants.seeds[seed_type])
	update_appearance()

//Updates strings and icon appropriately based on seed datum.
/obj/item/seeds/proc/update_appearance()
	if(!seed()) return

	var/is_seeds = ((seed().seed_noun in list("seeds","pits","nodes")) ? 1 : 0)
	if(is_seeds)
		src.name = "packet of [seed().seed_name] [seed().seed_noun]"
		src.desc = "It has a picture of [seed().display_name] on the front."
	else
		src.name = "sample of [seed().seed_name] [seed().seed_noun]"
		src.desc = "It's labelled as coming from [seed().display_name]."

/// The packet shows the mask of its seed (coloured like the plant) and a picture of the product.
/obj/item/seeds/draw(datum/look/look)
	..()
	if(!seed())
		return
	var/is_seeds = ((seed().seed_noun in list("seeds","pits","nodes")) ? 1 : 0)
	var/mask_colour = is_seeds ? seed().get_trait(TRAIT_PLANT_COLOUR) : null // Spore glass bits aren't coloured.
	look.overlay(look_cached_image("seedmask-[is_seeds ? "seed" : "spore"]-[mask_colour]", 'icons/obj/seeds.dmi', "[is_seeds ? "seed" : "spore"]-mask", mask_colour))
	look.overlay(look_cached_image("seedpic-[seed().get_trait(TRAIT_PRODUCT_ICON)]-[seed().get_trait(TRAIT_PRODUCT_COLOUR)]", 'icons/obj/seeds.dmi', "[seed().get_trait(TRAIT_PRODUCT_ICON)]", seed().get_trait(TRAIT_PRODUCT_COLOUR)))

/obj/item/seeds/examine(mob/user)
	. = ..()
	if(seed() && !seed().roundstart)
		. += "It's tagged as variety #[seed().uid]."

/obj/item/seeds/cutting
	name = "cuttings"
	desc = "Some plant cuttings."

/obj/item/seeds/cutting/update_appearance()
	..()
	src.name = "packet of [seed().seed_name] cuttings"

/obj/item/seeds/random
	seed_type = null

/// A random packet is a seed of its own making whatever it was given (the param's apply, at init).
/obj/item/seeds/random/seed_made(given_type)
	proto_set(src, nameof(seed_static), SSplants.create_random_seed())
	set_seed_type(seed().name)
	update_appearance()

/obj/item/seeds/rose
	seed_type = PLANT_ROSE

/obj/item/seeds/rose/blood
	seed_type = PLANT_BLOODROSE


/// The variant rows (variants(), code/engine/lifeforms/variants.dm).
/obj/item/seeds/proc/variant_table()
	return GLOB.dq_variants_seeds

/// The seed (PROTO): a registered line, or this holder's own private copy.
/obj/item/seeds/proc/seed() as /datum/seed
	return seed_static

CAPABILITIES(/obj/item/seeds)
	variants(nameof(variant), PROC_REF(variant_table))
	owns_one(nameof(seed_static), on_destroy = ON_DESTROY_PRIVATE_COPY)
	param(nameof(seed_type), pos = 1, apply = PROC_REF(seed_made))
