/transformation/stack/diamond__diamond_floor_tile
CAPABILITIES(/transformation/stack/diamond__diamond_floor_tile)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/item/stack/tile/floor/diamond, 4)),
		chosen = chosen(title = "diamond floor tile",
			subject = /datum/material/diamond,
			max_made = 20,
			recycle = STACK_MATERIAL_SELF,
			group = "floor tiles")))

