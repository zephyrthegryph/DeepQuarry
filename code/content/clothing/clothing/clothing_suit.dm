///////////////////////////////////////////////////////////////////////
//Suit
/obj/item/clothing/suit
	name = DEVELOPER_WARNING_NAME // "suit"
	icon = 'icons/inventory/suit/item.dmi'
	item_icons = list(
		slot_l_hand_str = 'icons/mob/items/lefthand_suits.dmi',
		slot_r_hand_str = 'icons/mob/items/righthand_suits.dmi',
		)
	var/fire_resist = T0C+100
	//Switch to taur sprites if a taur equips
	sprite_sheets = list(
		SPECIES_TESHARI = 'icons/inventory/suit/mob_teshari.dmi',
		SPECIES_VOX = 'icons/inventory/suit/mob_vox.dmi',
		SPECIES_WEREBEAST = 'icons/inventory/suit/mob_werebeast.dmi')
	var/blood_overlay_type = "suit"
	blood_sprite_state = "suitblood" //Defaults to the suit's blood overlay, so that some blood renders instead of no blood.

	//Hood stuff. See hooded.dm for more info. This should be expanded so all suits can have hoods if desired.
	//Currently only used by /obj/item/clothing/suit/storage/hooded.
	var/obj/item/clothing/head/hood // owned: the attached hood, kept in the suit's contents while down
	var/hoodtype = null //so the chaplain hoodie or other hoodies can override this
	var/hood_up = FALSE
	var/has_hood_sprite = FALSE
	var/special_hood_handling = FALSE
	var/toggleicon

	var/taurized = FALSE
	w_class = ITEMSIZE_NORMAL

	sprite_sheets = list(
		SPECIES_TESHARI = 'icons/inventory/suit/mob_teshari.dmi',
		SPECIES_VOX = 'icons/inventory/suit/mob_vox.dmi'
		)

	valid_accessory_slots = (ACCESSORY_SLOT_OVER | ACCESSORY_SLOT_ARMBAND)
	restricted_accessory_slots = (ACCESSORY_SLOT_ARMBAND)

	update_icon_define_digi = 'icons/inventory/suit/mob_digi.dmi'

CAPABILITIES(/obj/item/clothing/suit)
	configure(atom_rules(armor_spec = ""))
	configure(item_rules(actions_types = list()))
	configure(item_handling(preserve = 1))
	extend(/datum/act/equip, needs(req(PROC_REF(limb_clearance))))
	suit_storage(list(POCKET_EMERGENCY))
	configure(item_worn(covers = CHEST|ARMS|LEGS, slots = SLOT_OCLOTHING))
	configure(item_protection(max_heat = T0C+100, heat_parts = ARMS|LEGS|CHEST, cold_parts = ARMS|LEGS|CHEST, siemens = 0.9))
	configure(item_sounds(equip = SFX_ITEMS_JUMPSUIT_EQUIP))
	owns_one(nameof(hood), /obj/item/clothing/head, starts = PROC_REF(start_hood), early = TRUE) // made before the init chain reads the actions (the action buttons come from actions_types)
	setup(PROC_REF(take_toggle_icon))

/// The sprite name its hood toggle shows follows the type's own icon state.
/obj/item/clothing/suit/proc/take_toggle_icon()
	set_toggleicon("[initial(icon_state)]")

/obj/item/clothing/suit/draw(datum/look/look)
	..()
	look_parts(look)

/// What this chain's providers drew: each type's own part of the look, a subtype replacing or extending it (..()).
/obj/item/clothing/suit/proc/look_parts(datum/look/look)
	if(has_hood_sprite) //If we have a special hood_sprite, great, let's use it! Only used by /obj/item/clothing/suit/storage/hooded atm.
		look.state("[toggleicon][hood_up ? "_t" : ""]")

/obj/item/clothing/suit/dropped(mob/user, equipping, slot)
	RemoveHood()
	..()

/obj/item/clothing/suit/ui_action_click(mob/user, actiontype)
	if(..())
		return TRUE
	ToggleHood()

/// HOOD STUFF BELOW HERE.
/// The starting hood (owns_one starts, phase 0): the type its hoodtype names, and the toggle action it brings when the suit has no special one.
/obj/item/clothing/suit/proc/start_hood(current, mapload)
	if(!hoodtype)
		return null
	if(!item_rules_of(src).actions_types.len) //If we don't already have a special action type, let's add it.
		set_actions_types(item_rules_of(src).actions_types | (/datum/action/item_action/toggle_hood))
	return hoodtype

/obj/item/clothing/suit/proc/RemoveHood()
	set_hood_up(FALSE)
	if(hood)
		hood.set_canremove(TRUE) // This shouldn't matter anyways but just incase.
		if(ishuman(hood.loc))
			var/mob/living/carbon/H = hood.loc
			H.unEquip(hood, 1)
		hood.forceMove(src)

/obj/item/clothing/suit/proc/ToggleHood()
	if(!hood || special_hood_handling) //Some suits have special handling (See: void.dm with it's ui_action_click doing void_toggle_helmet_verb())
		return //In that case, we return and allow it to do it's special handling!
	if(hood_up)
		RemoveHood()
		return
	if(ishuman(loc))
		var/mob/living/carbon/human/H = src.loc
		if(H.get_equipped_item(SLOT_ID_SUIT) != src)
			to_chat(H, span_warning("You must be wearing [src] to put up the hood!"))
			return
		if(H.get_equipped_item(SLOT_ID_HEAD))
			to_chat(H, span_warning("You're already wearing something on your head!"))
			return
		else
			if(color != hood.color)
				hood.color = color
			H.equip_to_slot_if_possible(hood,SLOT_ID_HEAD,0,0,1)
			set_hood_up(TRUE)
			hood.set_canremove(FALSE)

///Hood stuff end.

/obj/item/clothing/suit/proc/taurize(mob/living/carbon/human/taur, has_taur_tail = FALSE)
	if(has_taur_tail)
		var/datum/sprite_accessory/tail/taur/taurtail = taur.tail_style
		if(taurtail.suit_sprites && (icon_exists(taurtail.suit_sprites, get_worn_icon_state(slot_wear_suit_str))))
			set_icon_override(taurtail.suit_sprites)
			taurized = TRUE
	// means that if a taur puts on an already taurized suit without a taur sprite
	// for their taur type, but the previous taur type had a sprite, it stays
	// taurized and they end up with that taur style which is funny
	else
		taurized = FALSE

	if(!taurized)
		set_icon_override(initial(icon_override))
		taurized = FALSE

// Taur suits need to be shifted so its centered on their taur half.
/obj/item/clothing/suit/make_worn_icon(body_type,slot_name,inhands,default_icon,default_layer = 0,icon/clip_mask, mob/living/carbon/human/wearer = null)
	var/image/standing = ..()
	if(taurized) //Special snowflake var on suits
		standing.pixel_x = -16
		standing.layer = BODY_LAYER + TAIL_UPPER_LAYER + 1
	return standing

/obj/item/clothing/suit/apply_accessories(image/standing)
	if(LAZYLEN(accessories) && taurized)
		var/list/worn
		for(var/obj/item/clothing/accessory/A in accessories)
			var/image/I = new(A.get_mob_overlay())
			I.pixel_x = 16 //Opposite of the pixel_x on the suit (-16) from taurization to cancel it out and puts the accessory in the correct place on the body.
			LAZYADD(worn, I)
		return look_composed_image(standing, worn)
	else
		return ..()

/obj/item/clothing/suit/equipped(mob/user, slot)
	if(slot != SLOT_ID_SUIT)
		RemoveHood()

	if(ishuman(user))
		var/mob/living/carbon/human/H = user
		var/taurtail = istaurtail(H.tail_style)
		if((taurized && !taurtail) || (!taurized && taurtail))
			taurize(user, taurtail)

	. = ..()
	handle_digitigrade(user)
