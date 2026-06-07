/obj/item/stack/material/steel/hull
	name = MAT_STEELHULL
	default_type = MAT_STEELHULL

/obj/item/stack/material/steel/hull/reagents_per_sheet()
	return REAGENTS_PER_HULL

/obj/item/stack/material/plasteel/hull
	name = MAT_PLASTEELHULL
	default_type = MAT_PLASTEELHULL

/obj/item/stack/material/plasteel/hull/reagents_per_sheet()
	return REAGENTS_PER_HULL

/obj/item/stack/material/durasteel/hull
	name = MAT_DURASTEELHULL
	default_type = MAT_DURASTEELHULL

/obj/item/stack/material/durasteel/hull/reagents_per_sheet()
	return REAGENTS_PER_HULL

/obj/item/stack/material/titanium/hull
	name = MAT_TITANIUMHULL
	default_type = MAT_TITANIUMHULL

/obj/item/stack/material/titanium/hull/reagents_per_sheet()
	return REAGENTS_PER_HULL

/obj/item/stack/material/morphium/hull
	name = MAT_MORPHIUMHULL
	default_type = MAT_MORPHIUMHULL

/obj/item/stack/material/morphium/hull/reagents_per_sheet()
	return REAGENTS_PER_HULL


// === merged from hull_vr.dm during hard-fork de-suffix (verified no override-order change) ===
/obj/item/stack/material/plastitanium/hull
	name = "plastitanium hull sheets"
	icon = 'icons/obj/stacks_vr.dmi'
	icon_state = "sheet-plastitanium"
	item_state = "sheet-silver"
	no_variants = FALSE
	default_type = MAT_PLASTITANIUMHULL

/obj/item/stack/material/gold/hull
	name = "gold hull sheets"
	icon = 'icons/obj/stacks_vr.dmi'
	icon_state = "sheet-plastitanium"
	item_state = "sheet-silver"
	no_variants = FALSE
	default_type = MAT_GOLDHULL
