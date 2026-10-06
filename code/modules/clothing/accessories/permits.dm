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

TRACKED(/obj/item/clothing/accessory/permit, owner)

MSG_DEF_SELF(permit/already_registered, "%T% already has an owner!")
MSG_DEF_SELF(permit/reset, "You reset the naming locks on %T%!")

CAPABILITIES(/obj/item/clothing/accessory/permit)
	op("register", in_hand(), label("Register"),
		needs(req_actor_kind(/mob/living), req_is(nameof(owner), FALSE, because = MSG(permit/already_registered))), then(PROC_REF(registered)))
	emag(then(PROC_REF(naming_reset)), say = MSG(permit/reset), repeatable = TRUE)

/obj/item/clothing/accessory/permit/proc/registered(datum/act/op/A)
	set_name(A.actor.name)
	to_chat(A.actor, "[src] registers your name.")
	return OP_OK

/obj/item/clothing/accessory/permit/proc/set_name(new_name)
	set_owner(TRUE)
	if(new_name)
		src.name = "[initial(name)] ([new_name])"
		desc = "[initial(desc)] It belongs to [new_name]."

/obj/item/clothing/accessory/permit/proc/naming_reset(datum/act/op/A)
	set_owner(FALSE)
	return OP_OK

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
	name = "explorer gun permit"
	desc = "A card indicating that the owner is allowed to carry a firearm during active exploration missions."
