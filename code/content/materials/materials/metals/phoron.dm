/transformation/stack/phoron__phoron_floor_tile
CAPABILITIES(/transformation/stack/phoron__phoron_floor_tile)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/item/stack/tile/floor/phoron, 4)),
		chosen = chosen(title = "phoron floor tile",
			subject = /datum/material/phoron,
			max_made = 20,
			recycle = STACK_MATERIAL_SELF,
			group = "floor tiles")))

