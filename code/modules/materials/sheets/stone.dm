/obj/item/stack/material/sandstone
	name = MAT_SANDSTONE + " brick"
	icon_state = "sheet-sandstone"
	default_type = MAT_SANDSTONE
	no_variants = FALSE

CAPABILITIES(/obj/item/stack/material/sandstone)
	configure(uses_power(drop = SFX_ITEMS_DROP_BOOTS, pickup = SFX_ITEMS_PICKUP_BOOTS))

/obj/item/stack/material/marble
	name = MAT_MARBLE + " brick"
	icon_state = "sheet-marble"
	default_type = MAT_MARBLE
	no_variants = FALSE

CAPABILITIES(/obj/item/stack/material/marble)
	configure(uses_power(drop = SFX_ITEMS_DROP_BOOTS, pickup = SFX_ITEMS_PICKUP_BOOTS))

/obj/item/stack/material/flint
	name = MAT_FLINT + " piece"
	icon_state = "sheet-rock"
	default_type = MAT_FLINT
	no_variants = FALSE
	pass_color = TRUE
	apply_colour = TRUE

CAPABILITIES(/obj/item/stack/material/flint)
	configure(uses_power(drop = SFX_ITEMS_DROP_BOOTS, pickup = SFX_ITEMS_PICKUP_BOOTS))

/obj/item/stack/material/concrete
	name = MAT_CONCRETE + " brick"
	icon_state = "sheet-brick"
	default_type = MAT_CONCRETE
	no_variants = FALSE
	apply_colour = 1
