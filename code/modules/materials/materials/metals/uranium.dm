/transformation/stack/uranium__uranium_floor_tile
CAPABILITIES(/transformation/stack/uranium__uranium_floor_tile)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/item/stack/tile/floor/uranium, 4)),
		chosen = chosen(title = "uranium floor tile",
			subject = /datum/material/uranium,
			max_made = 20,
			recycle = STACK_MATERIAL_SELF,
			group = "floor tiles")))

