/obj/item/clothing/suit/space/void/responseteam
	name = "Mark VII Emergency Response Suit"
	desc = "Utilizing cutting edge tech from Hephaestus, the Mark VII is the latest and greatest in semi-powered personal protection systems; like the civilian AutoLok suit, the Mark VII can automatically adapt to fit most species without issue via RFID tags. This significantly reduces the time required for response teams to suit up, as it eliminates the need for dedicated cycler units. It also has an integrated, unremovable helmet. Standard air tanks, suit coolers, and magboots may be installed and removed as needed."
	icon_state = "ertsuit"
	item_state = "ertsuit"
	armor_spec = "melee=65;bullet=55;laser=55;energy=15;bomb=50;bio=100;rad=100;cold=60"
	slowdown = 0.5
	siemens_coefficient = 0.5
	default_worn_icon = 'icons/inventory/suit/mob.dmi'
	w_class = ITEMSIZE_NORMAL //the mark vii packs itself down when not in use, thanks future-materials
	breach_threshold = 16 //Extra Thicc
	resilience = 0.05 //Military Armor
	min_pressure_protection = 0 * ONE_ATMOSPHERE
	max_pressure_protection = 15* ONE_ATMOSPHERE
	max_heat_protection_temperature = SPACE_SUIT_MAX_HEAT_PROTECTION_TEMPERATURE+10000

TYPE_TABLE(/obj/item/clothing/suit/space/void/responseteam, fit_spec, list(REQ_FITS_BODYTYPES(list("exclude",SPECIES_DIONA,SPECIES_VOX,SPECIES_TESHARI,SPECIES_ALTEVIAN))))

TYPE_TABLE(/obj/item/clothing/suit/space/void/responseteam, suit_storage_spec, list(HOLD_ONLY(list(POCKET_GENERIC, POCKET_EMERGENCY, POCKET_ALL_TANKS, POCKET_SUIT_REGULATORS, POCKET_SECURITY))))

/obj/item/clothing/suit/space/void/responseteam/command
	name = "Mark VII-C Emergency Response Team Commander Suit"

/obj/item/clothing/suit/space/void/responseteam/command/Initialize(mapload)
	. = ..()
	attach_helmet(new /obj/item/clothing/head/helmet/space/void/responseteam/command) //autoinstall the helmet

/obj/item/clothing/suit/space/void/responseteam/medical
	name = "Mark VII-M Emergency Medical Response Suit"
	icon_state = "ertsuit_m"
	item_state = "ertsuit_m"

/obj/item/clothing/suit/space/void/responseteam/medical/Initialize(mapload)
	. = ..()
	attach_helmet(new /obj/item/clothing/head/helmet/space/void/responseteam/medical) //autoinstall the helmet

/obj/item/clothing/suit/space/void/responseteam/engineer
	name = "Mark VII-E Emergency Engineering Response Suit"
	icon_state = "ertsuit_e"
	item_state = "ertsuit_e"

/obj/item/clothing/suit/space/void/responseteam/engineer/Initialize(mapload)
	. = ..()
	attach_helmet(new /obj/item/clothing/head/helmet/space/void/responseteam/engineer) //autoinstall the helmet

/obj/item/clothing/suit/space/void/responseteam/security
	name = "Mark VII-S Emergency Security Response Suit"
	icon_state = "ertsuit_s"
	item_state = "ertsuit_s"

/obj/item/clothing/suit/space/void/responseteam/security/Initialize(mapload)
	. = ..()
	attach_helmet(new /obj/item/clothing/head/helmet/space/void/responseteam/security) //autoinstall the helmet

/obj/item/clothing/suit/space/void/responseteam/janitor
	name = "Mark VII-J Emergency Cleanup Response Suit"
	icon_state = "ertsuit_j"
	item_state = "ertsuit_j"
	armor_spec = "melee=30;bullet=20;laser=20;energy=20;bomb=20;bio=100;rad=100;cold=60" //awful armor
	slowdown = 0 //light armor means no slowdown
	item_flags = NOSLIP //INBUILT NANOGALOSHES

/obj/item/clothing/suit/space/void/responseteam/janitor/Initialize(mapload)
	. = ..()
	attach_helmet(new /obj/item/clothing/head/helmet/space/void/responseteam/janitor) //autoinstall the helmet


// Overrides the voidsuit screwdriver so people can't remove the helmet.
/obj/item/clothing/suit/space/void/responseteam/screwdriver_act(mob/user, obj/item/tool, obj/item/answered_component = null)
	if(!isliving(user))
		return ITEM_INTERACT_BLOCKING
	if(user.inventory_slot_id(src) == SLOT_ID_SUIT)
		to_chat(user, span_warning("You cannot modify \the [src] while it is being worn."))
		return ITEM_INTERACT_SUCCESS
	if(boots || tank || cooler)
		if(isnull(answered_component))
			open_component_request(user, tool, list(boots,tank,cooler))
			return ITEM_INTERACT_BLOCKING
		var/choice = answered_component
		if(isnull(choice))
			return ITEM_INTERACT_BLOCKING
		if(!choice) return ITEM_INTERACT_SUCCESS

		if(choice == tank)	//No, a switch doesn't work here. Sorry. ~Techhead
			to_chat(user, "You pop \the [tank] out of \the [src]'s storage compartment.")
			tank.forceMove(get_turf(src))
			playsound(src, tool.usesound, 50, 1)
			rel_take(src, nameof(tank))
		else if(choice == cooler)
			to_chat(user, "You pop \the [cooler] out of \the [src]'s storage compartment.")
			cooler.forceMove(get_turf(src))
			playsound(src, tool.usesound, 50, 1)
			rel_take(src, nameof(cooler))
		else if(choice == boots)
			to_chat(user, "You detach \the [boots] from \the [src]'s boot mounts.")
			boots.forceMove(get_turf(src))
			playsound(src, tool.usesound, 50, 1)
			rel_take(src, nameof(boots))
	else
		to_chat(user, "\The [src] does not have anything installed.")
	return ITEM_INTERACT_SUCCESS


/obj/item/clothing/head/helmet/space/void/responseteam
	name = "Mark VII Emergency Response Helmet"
	desc = "As a vital part of the Mark VII suit, the integral helmet cannot be removed - so don't try."
	icon_state = "erthelmet"
	item_state = "erthelmet"
	armor_spec = "melee=60;bullet=50;laser=30;energy=15;bomb=30;bio=100;rad=100;cold=60"
	siemens_coefficient = 0.5
	enables_planes = list(VIS_CH_ID,VIS_CH_HEALTH_VR,VIS_AUGMENTED)
	var/away_planes = null
	plane_slots = list(SLOT_ID_HEAD)
	var/hud_active = 1
	var/activation_sound = SFX_ITEMS_NIF_CLICK
	min_pressure_protection = 0 * ONE_ATMOSPHERE
	max_pressure_protection = 15* ONE_ATMOSPHERE
	max_heat_protection_temperature = SPACE_SUIT_MAX_HEAT_PROTECTION_TEMPERATURE+10000

TYPE_TABLE(/obj/item/clothing/head/helmet/space/void/responseteam, fit_spec, list(REQ_FITS_BODYTYPES(list("exclude",SPECIES_DIONA,SPECIES_VOX,SPECIES_TESHARI,SPECIES_ALTEVIAN))))

CAPABILITIES(/obj/item/clothing/head/helmet/space/void/responseteam)
	op("responseteam_toggle_verb", menu(), label("Toggle Mark 7 Suit HUD"), needs(carried()), then(PROC_REF(responseteam_toggle_verb)))

/// Old verb "Toggle Mark 7 Suit HUD".
/obj/item/clothing/head/helmet/space/void/responseteam/proc/responseteam_toggle_verb(datum/act/op/A)
	var/mob/user = A.actor
	if(user.canmove && !user.stat && !user.restrained())
		if(src.hud_active)
			away_planes = enables_planes
			enables_planes = null
			to_chat(user, "You disable the inbuilt heads-up display.")
			hud_active = 0
		else
			enables_planes = away_planes
			away_planes = null
			to_chat(user, "You enable the inbuilt heads-up display.")
			hud_active = 1
		user << sound(get_sfx(activation_sound))
		user.recalculate_vis()

/obj/item/clothing/head/helmet/space/void/responseteam/command
	name = "Mark VII-C Emergency Response Team Commander Helmet"
	enables_planes = list(VIS_CH_ID,VIS_CH_HEALTH_VR,VIS_CH_STATUS_R,VIS_CH_BACKUP,VIS_CH_WANTED,VIS_AUGMENTED)

/obj/item/clothing/head/helmet/space/void/responseteam/medical
	name = "Mark VII-M Emergency Medical Response Helmet"
	icon_state = "erthelmet_m"
	item_state = "erthelmet_m"
	enables_planes = list(VIS_CH_ID,VIS_CH_HEALTH_VR,VIS_CH_STATUS_R,VIS_CH_BACKUP,VIS_AUGMENTED)

/obj/item/clothing/head/helmet/space/void/responseteam/engineer
	name = "Mark VII-E Emergency Engineering Response Helmet"
	icon_state = "erthelmet_e"
	item_state = "erthelmet_e"

/obj/item/clothing/head/helmet/space/void/responseteam/security
	name = "Mark VII-S Emergency Security Response Helmet"
	icon_state = "erthelmet_s"
	item_state = "erthelmet_s"
	enables_planes = list(VIS_CH_ID,VIS_CH_HEALTH_VR,VIS_CH_WANTED,VIS_AUGMENTED)

/obj/item/clothing/head/helmet/space/void/responseteam/janitor
	name = "Mark VII-J Emergency Cleanup Response Helmet"
	icon_state = "erthelmet_j"
	item_state = "erthelmet_j"

/obj/item/clothing/suit/space/void/responseteam
	sprite_sheets = list(
		SPECIES_HUMAN			= 'icons/inventory/suit/mob.dmi',
		SPECIES_TAJARAN 			= 'icons/inventory/suit/mob_tajaran.dmi',
		SPECIES_LLEILL 			= 'icons/inventory/suit/mob_tajaran.dmi',
		SPECIES_SKRELL 			= 'icons/inventory/suit/mob_skrell.dmi',
		SPECIES_UNATHI 			= 'icons/inventory/suit/mob_unathi.dmi',
		SPECIES_XENOHYBRID 		= 'icons/inventory/suit/mob_unathi.dmi',
		SPECIES_AKULA			= 'icons/inventory/suit/mob_akula.dmi',
		SPECIES_SERGAL			= 'icons/inventory/suit/mob_sergal.dmi',
		SPECIES_VULPKANIN		= 'icons/inventory/suit/mob_vulpkanin.dmi',
		SPECIES_ZORREN_HIGH		= 'icons/inventory/suit/mob_vulpkanin.dmi',
		SPECIES_FENNEC			= 'icons/inventory/suit/mob_vulpkanin.dmi',
		SPECIES_SHADEKIN		= 'icons/inventory/suit/mob_vulpkanin.dmi',
		SPECIES_VASILISSAN		= 'icons/inventory/suit/mob.dmi',
		SPECIES_NEVREAN			= 'icons/inventory/suit/mob.dmi',
		SPECIES_RAPALA			= 'icons/inventory/suit/mob.dmi',
		SPECIES_ALRAUNE			= 'icons/inventory/suit/mob.dmi',
		SPECIES_ZADDAT			= 'icons/inventory/suit/mob.dmi'
		)
	sprite_sheets_obj = list(
		SPECIES_TAJARAN			= 'icons/inventory/suit/item.dmi',
		SPECIES_SKRELL			= 'icons/inventory/suit/item.dmi',
		SPECIES_UNATHI			= 'icons/inventory/suit/item.dmi',
		SPECIES_XENOHYBRID		= 'icons/inventory/suit/item.dmi',
		SPECIES_AKULA			= 'icons/inventory/suit/item.dmi',
		SPECIES_SERGAL			= 'icons/inventory/suit/item.dmi',
		SPECIES_VULPKANIN		= 'icons/inventory/suit/item.dmi',
		SPECIES_ZORREN_HIGH		= 'icons/inventory/suit/item.dmi',
		SPECIES_FENNEC			= 'icons/inventory/suit/item.dmi',
		SPECIES_SHADEKIN		= 'icons/inventory/suit/item.dmi',
		SPECIES_VASILISSAN		= 'icons/inventory/suit/item.dmi',
		SPECIES_NEVREAN			= 'icons/inventory/suit/item.dmi',
		SPECIES_RAPALA			= 'icons/inventory/suit/item.dmi',
		SPECIES_ALRAUNE			= 'icons/inventory/suit/item.dmi',
		SPECIES_ZADDAT			= 'icons/inventory/suit/item.dmi',
		SPECIES_LLEILL			= 'icons/inventory/suit/item.dmi'
		)

/obj/item/clothing/head/helmet/space/void/responseteam
	sprite_sheets = list(
		SPECIES_HUMAN			= 'icons/inventory/head/mob.dmi',
		SPECIES_TAJARAN 			= 'icons/inventory/head/mob_tajaran.dmi',
		SPECIES_LLEILL 			= 'icons/inventory/suit/mob_tajaran.dmi',
		SPECIES_SKRELL 			= 'icons/inventory/head/mob_skrell.dmi',
		SPECIES_UNATHI 			= 'icons/inventory/head/mob_unathi.dmi',
		SPECIES_XENOHYBRID 		= 'icons/inventory/head/mob_unathi.dmi',
		SPECIES_AKULA			= 'icons/inventory/head/mob_unathi.dmi',
		SPECIES_SERGAL			= 'icons/inventory/head/mob_unathi.dmi',
		SPECIES_VULPKANIN		= 'icons/inventory/head/mob_vulpkanin.dmi',
		SPECIES_ZORREN_HIGH		= 'icons/inventory/head/mob_vulpkanin.dmi',
		SPECIES_FENNEC			= 'icons/inventory/head/mob_vulpkanin.dmi',
		SPECIES_SHADEKIN		= 'icons/inventory/head/mob_vulpkanin.dmi',
		SPECIES_VASILISSAN		= 'icons/inventory/head/mob.dmi',
		SPECIES_NEVREAN			= 'icons/inventory/head/mob.dmi',
		SPECIES_RAPALA			= 'icons/inventory/head/mob.dmi',
		SPECIES_ALRAUNE			= 'icons/inventory/head/mob.dmi',
		SPECIES_ZADDAT			= 'icons/inventory/head/mob.dmi'
		)
	sprite_sheets_obj = list(
		SPECIES_TAJARAN 			= 'icons/inventory/head/item.dmi',
		SPECIES_SKRELL			= 'icons/inventory/head/item.dmi',
		SPECIES_UNATHI			= 'icons/inventory/head/item.dmi',
		SPECIES_XENOHYBRID		= 'icons/inventory/head/item.dmi',
		SPECIES_AKULA			= 'icons/inventory/head/item.dmi',
		SPECIES_SERGAL			= 'icons/inventory/head/item.dmi',
		SPECIES_VULPKANIN		= 'icons/inventory/head/item.dmi',
		SPECIES_ZORREN_HIGH		= 'icons/inventory/head/item.dmi',
		SPECIES_FENNEC			= 'icons/inventory/head/item.dmi',
		SPECIES_SHADEKIN		= 'icons/inventory/head/item.dmi',
		SPECIES_VASILISSAN		= 'icons/inventory/head/item.dmi',
		SPECIES_NEVREAN			= 'icons/inventory/head/item.dmi',
		SPECIES_RAPALA			= 'icons/inventory/head/item.dmi',
		SPECIES_ALRAUNE			= 'icons/inventory/head/item.dmi',
		SPECIES_ZADDAT			= 'icons/inventory/head/item.dmi',
		SPECIES_LLEILL			= 'icons/inventory/suit/item.dmi'
		)
