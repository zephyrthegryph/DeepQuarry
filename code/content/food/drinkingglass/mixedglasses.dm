/obj/item/storage/box/mixedglasses
	name = "glassware box"
	desc = "A box of assorted glassware"
	icon_state = "glass"
	starts_with = list(
		/obj/item/reagent_containers/food/drinks/glass2/square,
		/obj/item/reagent_containers/food/drinks/glass2/rocks,
		/obj/item/reagent_containers/food/drinks/glass2/shake,
		/obj/item/reagent_containers/food/drinks/glass2/cocktail,
		/obj/item/reagent_containers/food/drinks/glass2/shot,
		/obj/item/reagent_containers/food/drinks/glass2/pint,
		/obj/item/reagent_containers/food/drinks/glass2/mug,
		/obj/item/reagent_containers/food/drinks/glass2/wine,
		/obj/item/reagent_containers/food/drinks/metaglass,
		/obj/item/reagent_containers/food/drinks/metaglass/metapint
	)


CAPABILITIES(/obj/item/storage/box/mixedglasses)
	configure(storage(accepts = list(/obj/item/reagent_containers/food/drinks/glass2)))
