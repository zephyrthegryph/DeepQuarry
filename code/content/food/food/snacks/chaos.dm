/obj/item/reagent_containers/food/snacks/donut/chaos
	name = "Chaos Donut"
	desc = "Like life, it never quite tastes the same."
	icon_state = "donut_chaos"
	filling_color = "#ED11E6"
	nutriment_amt = 2
	bitesize = 10
	overlay_state = "donut_chaos_inbox"

CAPABILITIES(/obj/item/reagent_containers/food/snacks/donut/chaos)
	configure(atom_rules(price_tag = 5))
	rolls(nameof(chaos_filling), pick_one(list(REAGENT_ID_NUTRIMENT, REAGENT_ID_CAPSAICIN, REAGENT_ID_FROSTOIL, REAGENT_ID_SPRINKLES, REAGENT_ID_PHORON, REAGENT_ID_COCO, REAGENT_ID_SLIMEJELLY, REAGENT_ID_BANANA, REAGENT_ID_BERRYJUICE, REAGENT_ID_TRICORDRAZINE)))
	configure(reagents(contents_from = PROC_REF(chaos_filling_contents)))
	configure(reagents(add = list(REAGENT_ID_SPRINKLES = 1)))

/obj/item/reagent_containers/food/snacks/donut/chaos
	/// The filling this donut rolled (rolls()): 3 units of it.
	var/chaos_filling

/obj/item/reagent_containers/food/snacks/donut/chaos/proc/chaos_filling_contents()
	return chaos_filling ? list("[chaos_filling]" = 3) : null
