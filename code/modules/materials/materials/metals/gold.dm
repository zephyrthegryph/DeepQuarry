/transformation/stack/gold__gold_floor_tile
CAPABILITIES(/transformation/stack/gold__gold_floor_tile)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/item/stack/tile/floor/gold, 4)),
		chosen = chosen(title = "gold floor tile",
			subject = /datum/material/gold,
			max_made = 20,
			recycle = STACK_MATERIAL_SELF,
			group = "floor tiles")))

