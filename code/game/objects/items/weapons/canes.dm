/obj/item/cane
	name = "cane"
	desc = "A cane used by a true gentleman."
	icon = 'icons/obj/weapons.dmi'
	icon_state = "cane"
	item_icons = list(
			slot_l_hand_str = 'icons/mob/items/lefthand_melee.dmi',
			slot_r_hand_str = 'icons/mob/items/righthand_melee.dmi',
			)
	force = 5.0
	throwforce = 7.0
	w_class = ITEMSIZE_NORMAL
	MATERIAL_BULK(MAT_STEEL, 50)
	attack_verb = list("bludgeoned", "whacked", "disciplined", "thrashed")

/obj/item/cane/crutch
	name ="crutch"
	desc = "A long stick with a crosspiece at the top, used to help with walking."
	icon_state = "crutch"
	item_state = "crutch"

/obj/item/cane/concealed
	var/obj/item/material/sword/katana/caneblade/concealed_blade


DECLARE_INTERACTIONS(/obj/item/cane/concealed, \
	INTERACT_USE(null, PROC_REF(interaction_self)), \
	INTERACT_ITEM(null, PROC_REF(interaction_item)), \
)

/// Old attack_self.
/obj/item/cane/concealed/proc/interaction_self(mob/user, obj/item/held, datum/interaction/interaction)
	if(concealed_blade)
		act_message(user, src, MSG_SELF("You unsheathe \the [concealed_blade] from %T%."), MSG_OTHERS(span_warning("%U% has unsheathed \a [concealed_blade] from %THEIR% %T%!")))
		// Calling drop/put in hands to properly call item drop/pickup procs
		play_sfx(src, SFX_WEAPONS_HOLSTER_SHEATHOUT)
		user.drop_from_inventory(src)
		user.put_in_hands(concealed_blade)
		user.put_in_hands(src)
		user.update_inv_l_hand(0)
		user.update_inv_r_hand()
		own_take(src, nameof(concealed_blade))
		update_icon()
	return TRUE

/// Old attackby.
/obj/item/cane/concealed/proc/interaction_item(mob/user, obj/item/material/butterfly/W, datum/interaction/interaction)
	if(!src.concealed_blade && istype(W))
		act_message(user, src, MSG_SELF("You sheathe \the [W] into %T%."), MSG_OTHERS(span_warning("%U% has sheathed \a [W] into %THEIR% %T%!")))
		play_sfx(src, SFX_WEAPONS_HOLSTER_SHEATHIN)
		user.drop_from_inventory(W)
		W.forceMove(src)
		own_set(src, nameof(concealed_blade), W)
		update_icon()
	else
		return FALSE
	return INTERACTION_HANDLED_PASS

DECLARE_APPEARANCE_PROC(/obj/item/cane/concealed, TYPE_PROC_REF(/atom, appearance_overlays), list())
/obj/item/cane/concealed/appearance_overlays()
	. = list()
	if(concealed_blade)
		name = initial(name)
		icon_state = initial(icon_state)
		item_state = initial(icon_state)
	else
		name = "cane shaft"
		icon_state = "nullrod"
		item_state = "foldcane"

/obj/item/cane/white
	name = "white cane"
	desc = "A white cane. They are commonly used by the blind or visually impaired as a mobility tool or as a courtesy to others."
	icon_state = "whitecane"

/obj/item/cane/white/attack(mob/living/M, mob/living/user, target_zone, attack_modifier, stance = I_HURT)
	if(stance == I_HELP)
		act_message(user, M, others = span_notice("%U% has lightly tapped %T% on the ankle with their white cane!"))
		return ITEM_INTERACT_SUCCESS
	else
		. = ..()


//Code for Telescopic White Cane writen by Gozulio

/obj/item/cane/white/collapsible
	name = "telescopic white cane"
	desc = "A telescopic white cane. They are commonly used by the blind or visually impaired as a mobility tool or as a courtesy to others."
	icon_state = "whitecane1in"
	item_icons = list(
			slot_l_hand_str = 'icons/mob/items/lefthand_melee.dmi',
			slot_r_hand_str = 'icons/mob/items/righthand_melee.dmi',
		)
	slot_flags = SLOT_BELT
	w_class = ITEMSIZE_SMALL
	force = 3
	var/on = 0

DECLARE_INTERACTIONS(/obj/item/cane/white/collapsible, INTERACT_USE(null, PROC_REF(interaction_self)))

/// Old attack_self.
/obj/item/cane/white/collapsible/proc/interaction_self(mob/user, obj/item/held, datum/interaction/interaction)
	on = !on
	if(on)
		act_message(user, null, MSG_SELF(span_warning("You extend the white cane.")), \
			MSG_OTHERS(span_infoplain(span_bold("%U%") + " extends the white cane.")), \
			MSG_BLIND("You hear an ominous click."))
		icon_state = "whitecane1out"
		item_state_slots = list(slot_r_hand_str = "whitecane", slot_l_hand_str = "whitecane")
		w_class = ITEMSIZE_NORMAL
		force = 5
		attack_verb = list("smacked", "struck", "cracked", "beaten")
	else
		act_message(user, null, MSG_SELF(span_notice("You collapse the white cane.")), \
			MSG_OTHERS(span_infoplain(span_bold("%U%") + " collapses the white cane.")), \
			MSG_BLIND("You hear a click."))
		icon_state = "whitecane1in"
		item_state_slots = list(slot_r_hand_str = null, slot_l_hand_str = null)
		w_class = ITEMSIZE_SMALL
		force = 3
		attack_verb = list("hit", "poked", "prodded")

	if(ishuman(user))
		var/mob/living/carbon/human/H = user
		H.update_inv_l_hand()
		H.update_inv_r_hand()

	play_sfx(src, SFX_WEAPONS_EMPTY)
	add_fingerprint(user)
	return TRUE

/obj/item/cane/concealed/declare_ownership(decl)
	..()
	own(decl, nameof(concealed_blade), policy = OWN_CONTAINED)
DECLARE_DEFAULT_CHILD(/obj/item/cane/concealed, "concealed_blade", /obj/item/material/sword/katana/caneblade)
