/obj/item/stack/material/plastic
	name = MAT_PLASTIC
	icon_state = "sheet-plastic"
	default_type = MAT_PLASTIC
	no_variants = FALSE

/obj/item/stack/material/cardboard
	name = MAT_CARDBOARD
	icon_state = "sheet-card"
	default_type = MAT_CARDBOARD
	no_variants = FALSE
	pass_color = TRUE
	strict_color_stacking = TRUE
	resistance_flags = FLAMMABLE

CAPABILITIES(/obj/item/stack/material/cardboard)
	configure(uses_power(drop = SFX_ITEMS_DROP_CARDBOARDBOX, pickup = SFX_ITEMS_PICKUP_CARDBOARDBOX))
