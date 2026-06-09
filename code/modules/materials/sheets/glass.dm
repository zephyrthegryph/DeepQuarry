/obj/item/stack/material/glass
	name = MAT_GLASS
	icon_state = "sheet-glass" // replace materials update
	default_type = MAT_GLASS
	no_variants = FALSE
	drop_sound = 'sound/items/drop/glass.ogg'
	pickup_sound = 'sound/items/pickup/glass.ogg'
	apply_colour = TRUE

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


// === merged from glass_vr.dm during hard-fork de-suffix (verified no override-order change) ===
/obj/item/stack/material/glass/titanium
	name = "ti-glass sheets"
	icon = 'icons/obj/stacks_vr.dmi'
	icon_state = "sheet-titaniumglass"
	item_state = "sheet-silver"
	no_variants = FALSE
	drop_sound = 'sound/items/drop/glass.ogg'
	default_type = MAT_TITANIUMGLASS

/obj/item/stack/material/glass/plastitanium
	name = "plastitanium glass sheets"
	icon = 'icons/obj/stacks_vr.dmi'
	icon_state = "sheet-plastitaniumglass"
	item_state = "sheet-silver"
	no_variants = FALSE
	drop_sound = 'sound/items/drop/glass.ogg'
	default_type = MAT_PLASTITANIUMGLASS
