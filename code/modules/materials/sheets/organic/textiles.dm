/obj/item/stack/material/leather
	name = MAT_LEATHER
	desc = "The by-product of mob grinding."
	icon_state = "sheet-leather"
	default_type = MAT_LEATHER
	no_variants = FALSE
	pass_color = TRUE
	strict_color_stacking = TRUE
	resistance_flags = FLAMMABLE

CAPABILITIES(/obj/item/stack/material/leather)
	configure(uses_power(drop = SFX_ITEMS_DROP_LEATHER, pickup = SFX_ITEMS_PICKUP_LEATHER))

/obj/item/stack/material/cloth
	name = MAT_CLOTH
	desc = "Individual fibers woven into a cloth."
	icon_state = "sheet-cloth"
	default_type = MAT_CLOTH
	no_variants = FALSE
	pass_color = TRUE
	strict_color_stacking = TRUE
	resistance_flags = FLAMMABLE

CAPABILITIES(/obj/item/stack/material/cloth)
	configure(uses_power(drop = SFX_ITEMS_DROP_CLOTHING, pickup = SFX_ITEMS_PICKUP_CLOTHING))

/obj/item/stack/material/cloth/diyaab
	color = "#c6ccf0"


/obj/item/stack/material/cotton
	name = MAT_COTTON
	desc = "It's so FLUFFY!"
	icon_state = "sheet-cloth"
	default_type = MAT_COTTON
	no_variants = FALSE
	pass_color = TRUE
	strict_color_stacking = TRUE
	resistance_flags = FLAMMABLE

CAPABILITIES(/obj/item/stack/material/cotton)
	configure(uses_power(drop = SFX_ITEMS_DROP_CLOTHING, pickup = SFX_ITEMS_PICKUP_CLOTHING))

/obj/item/stack/material/fiber
	name = "plant fiber"
	desc = "Some all-natural plant fibers."
	icon_state = "sheet-fiber"
	default_type = MAT_FIBERS
	pass_color = TRUE
	apply_colour = TRUE
	resistance_flags = FLAMMABLE

CAPABILITIES(/obj/item/stack/material/fiber)
	configure(uses_power(drop = SFX_ITEMS_DROP_CLOTHING, pickup = SFX_ITEMS_PICKUP_CLOTHING))
