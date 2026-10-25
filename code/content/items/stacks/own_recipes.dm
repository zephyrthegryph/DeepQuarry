// The stack recipes of stacks that have a list of their own (not their material's): rods, sandbags, wax and the cyborg recyclers
// (code/library/transformations/stack_recipes.dm). The subject is the key the stack asks stack_own_recipes() for.

/transformation/stack/sandbags__barricade
CAPABILITIES(/transformation/stack/sandbags__barricade)
	configure(transformation(takes = list(stack_term(STACK_SELF, 3)), makes = list(item_term(/obj/structure/barricade/sandbag, 1)),
		chosen = chosen(title = "barricade", subject = STACK_RECIPES_SANDBAGS, build_time = 5 SECONDS, one_per_turf = 1, on_floor = 1, pass_color = TRUE)))

/transformation/stack/wax__candle
CAPABILITIES(/transformation/stack/wax__candle)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/item/flame/candle, 1)),
		chosen = chosen(title = "candle", subject = STACK_RECIPES_WAX)))

/transformation/stack/rods__grille
CAPABILITIES(/transformation/stack/rods__grille)
	configure(transformation(takes = list(stack_term(STACK_SELF, 2)), makes = list(item_term(/obj/structure/grille, 1)),
		chosen = chosen(title = "grille", subject = STACK_RECIPES_RODS, build_time = 1 SECOND, one_per_turf = 1, on_floor = 0)))

/transformation/stack/rods__catwalk
CAPABILITIES(/transformation/stack/rods__catwalk)
	configure(transformation(takes = list(stack_term(STACK_SELF, 2)), makes = list(item_term(/obj/structure/catwalk, 1)),
		chosen = chosen(title = "catwalk", subject = STACK_RECIPES_RODS, build_time = 8 SECONDS, one_per_turf = 1, on_floor = 1)))

/transformation/stack/steel_recycler__steel_sheet
CAPABILITIES(/transformation/stack/steel_recycler__steel_sheet)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/item/stack/material/steel, 1)),
		chosen = chosen(title = "steel sheet", subject = STACK_RECIPES_STEEL_RECYCLER, max_made = 20)))

/transformation/stack/glass_recycler__glass_sheet
CAPABILITIES(/transformation/stack/glass_recycler__glass_sheet)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/item/stack/material/glass, 1)),
		chosen = chosen(title = "glass sheet", subject = STACK_RECIPES_GLASS_RECYCLER, max_made = 20)))
