/obj/item/stack/material/glass
	name = MAT_GLASS
	icon_state = "sheet-glass" // replace materials update
	default_type = MAT_GLASS
	no_variants = FALSE
	apply_colour = TRUE

CAPABILITIES(/obj/item/stack/material/glass)
	configure(item_sounds(drop = SFX_ITEMS_DROP_GLASS, pickup = SFX_ITEMS_PICKUP_GLASS))

/obj/item/stack/material/glass/reinforced
	name = "reinforced glass"
	icon_state = "sheet-rglass" // replace materials update
	default_type = MAT_RGLASS
	no_variants = FALSE
	apply_colour = TRUE

/obj/item/stack/material/glass/phoronglass
	name = MAT_PGLASS
	desc = "This sheet is special platinum-glass alloy designed to withstand large temperatures"
	singular_name = "borosilicate glass sheet"
	icon_state = "sheet-phoronglass" // replace materials update
	default_type = MAT_PGLASS
	no_variants = FALSE
	apply_colour = TRUE

/obj/item/stack/material/glass/phoronrglass
	name = MAT_RPGLASS
	desc = "This sheet is special platinum-glass alloy designed to withstand large temperatures. It is reinforced with few rods."
	singular_name = "reinforced borosilicate glass sheet"
	icon_state = "sheet-phoronrglass" // replace materials update
	default_type = MAT_RPGLASS
	no_variants = FALSE
	apply_colour = TRUE


/obj/item/stack/material/glass/titanium
	name = "ti-glass sheets"
	icon = 'icons/obj/stacks_vr.dmi'
	icon_state = "sheet-titaniumglass"
	item_state = "sheet-silver"
	no_variants = FALSE
	default_type = MAT_TITANIUMGLASS

CAPABILITIES(/obj/item/stack/material/glass/titanium)
	configure(item_sounds(drop = SFX_ITEMS_DROP_GLASS))

/obj/item/stack/material/glass/plastitanium
	name = "plastitanium glass sheets"
	icon = 'icons/obj/stacks_vr.dmi'
	icon_state = "sheet-plastitaniumglass"
	item_state = "sheet-silver"
	no_variants = FALSE
	default_type = MAT_PLASTITANIUMGLASS

CAPABILITIES(/obj/item/stack/material/glass/plastitanium)
	configure(item_sounds(drop = SFX_ITEMS_DROP_GLASS))
