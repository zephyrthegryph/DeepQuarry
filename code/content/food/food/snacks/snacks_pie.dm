/obj/item/reagent_containers/food/snacks/pie
	name = "Banana Cream Pie"
	desc = "Just like back home, on clown planet! HONK!"
	icon_state = "pie"
	trash = /obj/item/trash/plate
	filling_color = "#FBFFB8"
	nutriment_amt = 4
	nutriment_desc = list("pie" = 3, REAGENT_ID_CREAM = 2)
	bitesize = 3

CAPABILITIES(/obj/item/reagent_containers/food/snacks/pie)
	configure(atom_rules(price_tag = 4, description_fluff = "One of the more esoteric terms of the Nanotrasen-Centauri Noncompetition Agreement of 2545 was a requirement that Nanotrasen stock these pies on all their stations. They're calibrated for comedic value, not taste."))
	configure(item_handling(center_x = 16, center_y = 13))
	configure(reagents(add = list(REAGENT_ID_BANANA = 5)))

/obj/item/reagent_containers/food/snacks/pie/throw_impact(atom/hit_atom)
	. = ..()
	src.visible_message(span_danger("\The [src.name] splats."),span_danger("You hear a splat."))
	replace_with(src, /obj/effect/decal/cleanable/pie_smudge)
