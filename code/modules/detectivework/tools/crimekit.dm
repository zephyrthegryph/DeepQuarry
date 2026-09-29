//crime scene kit
/obj/item/storage/briefcase/crimekit
	name = "crime scene kit"
	desc = "A stainless steel-plated carrycase for all your forensic needs. Feels heavy."
	icon = 'icons/obj/forensics.dmi'
	icon_state = "case"
	storage_slots = 14
	drop_sound = SFX_ITEMS_DROP_TOOLBOX
	pickup_sound = SFX_ITEMS_PICKUP_TOOLBOX

/obj/item/storage/briefcase/crimekit/Initialize(mapload)
	. = ..()
	new /obj/item/storage/box/swabs(src)
	new /obj/item/storage/box/fingerprints(src)
	new /obj/item/reagent_containers/spray/luminol(src)
	new /obj/item/uv_light(src)
	new /obj/item/forensics/sample_kit(src)
	new /obj/item/forensics/sample_kit/powder(src)
