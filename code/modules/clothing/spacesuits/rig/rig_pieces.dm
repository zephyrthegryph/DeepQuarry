/*
 * Defines the helmets, gloves and shoes for rigs.
 */

/obj/item/clothing/head/helmet/space/rig
	name = "helmet"
	item_flags = THICKMATERIAL|ALLOW_SURVIVALFOOD
	flags_inv = HIDEEARS|HIDEEYES|HIDEFACE|BLOCKHAIR
	light_range = 4
	sprite_sheets = list(
		SPECIES_TAJARAN 		= 'icons/inventory/head/mob_tajaran.dmi',
		SPECIES_SKRELL 			= 'icons/inventory/head/mob_skrell.dmi',
		SPECIES_UNATHI 			= 'icons/inventory/head/mob_unathi.dmi',
		SPECIES_XENOHYBRID 		= 'icons/inventory/head/mob_unathi.dmi',
		SPECIES_AKULA 			= 'icons/inventory/head/mob_akula.dmi',
		SPECIES_SERGAL			= 'icons/inventory/head/mob_sergal.dmi',
		SPECIES_NEVREAN			= 'icons/inventory/head/mob_sergal.dmi',
		SPECIES_VULPKANIN 		= 'icons/inventory/head/mob_vulpkanin.dmi',
		SPECIES_ZORREN_HIGH 	= 'icons/inventory/head/mob_vulpkanin.dmi',
		SPECIES_FENNEC 			= 'icons/inventory/head/mob_vulpkanin.dmi',
		SPECIES_PROMETHEAN		= 'icons/inventory/head/mob_skrell.dmi',
		SPECIES_VOX 			= 'icons/inventory/head/mob_vox.dmi',
		SPECIES_TESHARI 		= 'icons/inventory/head/mob_teshari.dmi',
		SPECIES_ALTEVIAN 		= 'icons/inventory/head/mob_altevian.dmi'
		)
	max_pressure_protection = null
	min_pressure_protection = null
	resistance_flags = FIRE_PROOF | ACID_PROOF

TYPE_TABLE(/obj/item/clothing/head/helmet/space/rig, fit_spec, list(REQ_FITS_BODYTYPES(list(SPECIES_HUMAN, SPECIES_SKRELL, SPECIES_TAJARAN, SPECIES_UNATHI, SPECIES_NEVREAN, SPECIES_AKULA, SPECIES_SERGAL, SPECIES_ZORREN_HIGH, SPECIES_VULPKANIN, SPECIES_PROMETHEAN, SPECIES_VOX, SPECIES_TESHARI, SPECIES_VASILISSAN, SPECIES_RAPALA, SPECIES_ALRAUNE, SPECIES_FENNEC, SPECIES_XENOHYBRID, SPECIES_ALTEVIAN, SPECIES_SHADEKIN))))

/obj/item/clothing/gloves/gauntlets/rig
	name = "gauntlets"
	icon_state = "security_rig"
	flags = PHORONGUARD
	item_flags = THICKMATERIAL
	resistance_flags = FIRE_PROOF | ACID_PROOF

TYPE_TABLE(/obj/item/clothing/gloves/gauntlets/rig, fit_spec, list(REQ_FITS_BODYTYPES(list(SPECIES_HUMAN, SPECIES_SKRELL, SPECIES_TAJARAN, SPECIES_UNATHI, SPECIES_NEVREAN, SPECIES_AKULA, SPECIES_SERGAL, SPECIES_ZORREN_HIGH, SPECIES_VULPKANIN, SPECIES_PROMETHEAN, SPECIES_VOX, SPECIES_TESHARI, SPECIES_VASILISSAN, SPECIES_RAPALA, SPECIES_ALRAUNE, SPECIES_FENNEC, SPECIES_XENOHYBRID, SPECIES_ALTEVIAN, SPECIES_SHADEKIN))))
/obj/item/clothing/shoes/magboots/rig
	name = "boots"
	icon_base = null
	resistance_flags = FIRE_PROOF | ACID_PROOF

TYPE_TABLE(/obj/item/clothing/shoes/magboots/rig, fit_spec, list(REQ_FITS_BODYTYPES(list(SPECIES_HUMAN, SPECIES_SKRELL, SPECIES_TAJARAN, SPECIES_UNATHI, SPECIES_NEVREAN, SPECIES_AKULA, SPECIES_SERGAL, SPECIES_ZORREN_HIGH, SPECIES_VULPKANIN, SPECIES_PROMETHEAN, SPECIES_VOX, SPECIES_TESHARI, SPECIES_VASILISSAN, SPECIES_RAPALA, SPECIES_ALRAUNE, SPECIES_FENNEC, SPECIES_XENOHYBRID, SPECIES_ALTEVIAN, SPECIES_SHADEKIN))))

/obj/item/clothing/suit/space/rig
	name = "chestpiece"
	body_parts_covered = CHEST|LEGS|ARMS
	heat_protection =	 CHEST|LEGS|ARMS
	cold_protection =	 CHEST|LEGS|ARMS
	flags_inv =			 HIDEJUMPSUIT|HIDETAIL
	item_flags =		 THICKMATERIAL | AIRTIGHT
	slowdown = 0
	//will reach 10 breach damage after 25 laser carbine blasts, 3 revolver hits, or ~1 PTR hit. Completely immune to smg or sts hits.
	breach_threshold = 38
	resilience = 0.2
	can_breach = 1
	sprite_sheets = list(
		SPECIES_TAJARAN 		= 'icons/inventory/suit/mob_tajaran.dmi',
		SPECIES_SKRELL 			= 'icons/inventory/suit/mob_skrell.dmi',
		SPECIES_UNATHI 			= 'icons/inventory/suit/mob_unathi.dmi',
		SPECIES_XENOHYBRID 		= 'icons/inventory/suit/mob_unathi.dmi',
		SPECIES_AKULA 			= 'icons/inventory/suit/mob_akula.dmi',
		SPECIES_SERGAL			= 'icons/inventory/suit/mob_sergal.dmi',
		SPECIES_NEVREAN			= 'icons/inventory/suit/mob_sergal.dmi',
		SPECIES_VULPKANIN		= 'icons/inventory/suit/mob_vulpkanin.dmi',
		SPECIES_ZORREN_HIGH		= 'icons/inventory/suit/mob_vulpkanin.dmi',
		SPECIES_FENNEC			= 'icons/inventory/suit/mob_vulpkanin.dmi',
		SPECIES_PROMETHEAN		= 'icons/inventory/suit/mob_skrell.dmi',
		SPECIES_VOX 			= 'icons/inventory/suit/mob_vox.dmi',
		SPECIES_TESHARI 		= 'icons/inventory/suit/mob_teshari.dmi',
		SPECIES_ALTEVIAN 		= 'icons/inventory/suit/mob_altevian.dmi'
		)
	supports_limbs = TRUE
	var/obj/item/material/knife/tacknife
	max_pressure_protection = null
	min_pressure_protection = null
	resistance_flags = FIRE_PROOF | ACID_PROOF

TYPE_TABLE(/obj/item/clothing/suit/space/rig, fit_spec, list(REQ_FITS_BODYTYPES(list(SPECIES_HUMAN, SPECIES_SKRELL, SPECIES_TAJARAN, SPECIES_UNATHI, SPECIES_NEVREAN, SPECIES_AKULA, SPECIES_SERGAL, SPECIES_ZORREN_HIGH, SPECIES_VULPKANIN, SPECIES_PROMETHEAN, SPECIES_VOX, SPECIES_TESHARI, SPECIES_VASILISSAN, SPECIES_RAPALA, SPECIES_ALRAUNE, SPECIES_FENNEC, SPECIES_XENOHYBRID, SPECIES_ALTEVIAN, SPECIES_SHADEKIN))))

TYPE_TABLE(/obj/item/clothing/suit/space/rig, suit_storage_spec, list(HOLD_ONLY(list(POCKET_GENERIC, POCKET_ALL_TANKS, POCKET_SUIT_REGULATORS,/obj/item/storage))))

CAPABILITIES(/obj/item/clothing/suit/space/rig)
	op("rig_suit_draw_knife_hand", hand(), ungated(), label("Rig suit draw knife hand"), then(PROC_REF(rig_suit_draw_knife_hand)))
	op("rig_suit_sheathe_knife_item", item(/obj/item), label("Rig suit sheathe knife item"), then(PROC_REF(rig_suit_sheathe_knife_item)))

/// Old attack_hand: slide the tactical knife out.
/obj/item/clothing/suit/space/rig/proc/rig_suit_draw_knife_hand(datum/act/op/A)
	var/mob/living/M = A.actor
	if(tacknife())
		tacknife().forceMove(get_turf(src))
		if(M.put_in_active_hand(tacknife()))
			to_chat(M, span_notice("You slide \the [tacknife()] out of [src]."))
			play_sfx(src, SFX_WEAPONS_FLIPBLADE, 0.8)
			rel_clear(src, nameof(tacknife))
			update_icon()
		return TRUE
	return OP_DECLINE

/// Old attackby: slide a tactical knife in. Always fell through to ..() afterwards.
/obj/item/clothing/suit/space/rig/proc/rig_suit_sheathe_knife_item(datum/act/op/A)
	var/mob/living/M = A.actor
	var/obj/item/I = A.held
	if(istype(I, /obj/item/material/knife/tacknife))
		if(tacknife())
			return OP_PASS
		M.drop_item()
		rel_set(src, nameof(tacknife), I)
		I.forceMove(src)
		to_chat(M, span_notice("You slide the [I] into [src]."))
		play_sfx(src, SFX_WEAPONS_FLIPBLADE, 0.8)
		update_icon()
	return OP_DECLINE

//TODO: move this to modules
/obj/item/clothing/head/helmet/space/rig/proc/prevent_track()
	return 0

/obj/item/clothing/gloves/gauntlets/rig/Touch(atom/A, proximity, stance = I_HURT, mob/user)

	if(!A || !proximity)
		return 0

	var/mob/living/carbon/human/H = loc
	if(!istype(H) || (!H.get_equipped_item(SLOT_ID_BACK) && !H.get_equipped_item(SLOT_ID_BELT)))
		return 0

	var/obj/item/rig/suit = H.get_equipped_item(SLOT_ID_BACK)
	if(!suit || !istype(suit) || !length(suit.installed_modules))
		return 0

	for(var/obj/item/rig_module/module in suit.installed_modules)
		if(module.active && module.activates_on_touch)
			if(module.engage(A, FALSE, user))
				return 1

	return 0

//Rig pieces for non-spacesuit based rigs

/obj/item/clothing/head/lightrig
	name = DEVELOPER_WARNING_NAME // "mask"
	body_parts_covered = HEAD|FACE|EYES
	flags =              THICKMATERIAL|AIRTIGHT
	resistance_flags = FIRE_PROOF | ACID_PROOF

/obj/item/clothing/suit/lightrig
	name = DEVELOPER_WARNING_NAME // "suit"
	flags_inv =          HIDEJUMPSUIT
	flags =              THICKMATERIAL
	resistance_flags = FIRE_PROOF | ACID_PROOF

TYPE_TABLE(/obj/item/clothing/suit/lightrig, suit_storage_spec, list(HOLD_ONLY(list(POCKET_GENERIC, POCKET_EMERGENCY))))

/obj/item/clothing/shoes/lightrig
	name = DEVELOPER_WARNING_NAME // "boots"
	resistance_flags = FIRE_PROOF | ACID_PROOF

/obj/item/clothing/gloves/gauntlets/lightrig
	flags = THICKMATERIAL
	resistance_flags = FIRE_PROOF | ACID_PROOF

/// the tacknife this refers to (a relation view: null once it is deleted).
/obj/item/clothing/suit/space/rig/proc/tacknife() as /obj/item/material/knife
	return tacknife
