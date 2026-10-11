// Ok, technically not stones, but the snowbrick's function is similar to sandstone and marble
/obj/item/stack/material/snow
	name = MAT_SNOW
	desc = "The temptation to build a snowman rises."
	icon_state = "sheet-snow"
	default_type = MAT_SNOW

CAPABILITIES(/obj/item/stack/material/snow)
	configure(item_sounds(drop = SFX_ITEMS_DROP_GLOVES, pickup = SFX_ITEMS_PICKUP_CLOTHING))

/obj/item/stack/material/snowbrick
	name = "snow brick"
	desc = "For all of your igloo building needs."
	icon_state = "sheet-snowbrick"
	default_type = MAT_SNOWBRICK

CAPABILITIES(/obj/item/stack/material/snowbrick)
	configure(item_sounds(drop = SFX_ITEMS_DROP_GLOVES, pickup = SFX_ITEMS_PICKUP_CLOTHING))
