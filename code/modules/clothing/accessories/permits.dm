//This'll be used for gun permits, such as for heads of staff, antags, and bartenders

/obj/item/clothing/accessory/permit
	name = "permit"
	desc = "A permit for something."
	icon = 'icons/obj/card_new.dmi'
	icon_state = "permit-generic"
	w_class = ITEMSIZE_TINY
	slot = ACCESSORY_SLOT_MEDAL
	var/owner = 0	//To prevent people from just renaming the thing if they steal it
	special_handling = TRUE

EXTEND_INTERACTIONS(/obj/item/clothing/accessory/permit, INTERACT_USE("Register", PROC_REF(permit_register_self)))

/// Old attack_self: register the owner.
/obj/item/clothing/accessory/permit/proc/permit_register_self(mob/user, obj/item/held, datum/interaction/interaction)
	if(isliving(user))
		if(!owner)
			set_name(user.name)
			to_chat(user, "[src] registers your name.")
		else
			to_chat(user, "[src] already has an owner!")

/obj/item/clothing/accessory/permit/proc/set_name(new_name)
	owner = 1
	if(new_name)
		src.name += " ([new_name])"
		desc += " It belongs to [new_name]."

DECLARE_EMAG_REPEATABLE(/obj/item/clothing/accessory/permit, PROC_REF(on_emag), null)
/obj/item/clothing/accessory/permit/proc/on_emag(remaining_charges, mob/user, obj/item/emag_source)
	to_chat(user, "You reset the naming locks on [src]!")
	owner = 0

/obj/item/clothing/accessory/permit/gun
	name = "weapon permit"
	desc = "A card indicating that the owner is allowed to carry a firearm."
	icon_state = "permit-security"

/obj/item/clothing/accessory/permit/gun/bar
	name = "bar shotgun permit"
	desc = "A card indicating that the owner is allowed to carry a shotgun in the bar."

/obj/item/clothing/accessory/permit/gun/planetside
	name = "planetside gun permit"
	desc = "A card indicating that the owner is allowed to carry a firearm while on the surface."
	icon_state = "permit-science"

/obj/item/clothing/accessory/permit/drone
	name = "drone identification card"
	desc = "A card issued by the EIO, indicating that the owner is a Drone Intelligence. Drones are mandated to carry this card within SolGov space, by law."
	icon_state = "permit-drone"


/obj/item/clothing/accessory/permit/drone
	desc = "A card issued by the EIO, indicating that the owner is a Drone Intelligence. Drones are mandated to carry this card within SolGov space, by law." // SolGov

/obj/item/clothing/accessory/permit/gun/planetside
	name = "explorer gun permit" //CHOMP keep explo
	desc = "A card indicating that the owner is allowed to carry a firearm during active exploration missions." //CHOMP keep explo
