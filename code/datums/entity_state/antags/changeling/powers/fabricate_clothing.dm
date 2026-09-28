/datum/power/changeling/fabricate_clothing
	name = "Fabricate Clothing"
	desc = "We reform our flesh to resemble various cloths, leathers, and other materials, allowing us to quickly create a disguise.  \
	We cannot be relieved of this clothing by others."
	helptext = "The disguise we create offers no defensive ability.  Each equipment slot that is empty will be filled with fabricated equipment. \
	To remove our new fabricated clothing, use this ability again."
	ability_icon_state = "ling_fabricate_clothing"
	genomecost = 1
	verbpath = /mob/proc/changeling_fabricate_clothing

//Grows biological versions of chameleon clothes.
/mob/proc/changeling_fabricate_clothing()
	set category = "Changeling"
	set name = "Fabricate Clothing (10)"

	if(changeling_generic_equip_all_slots(GLOB.changeling_fabricated_clothing, cost = 10))
		return 1
	return 0

/obj/item/clothing/under/chameleon/changeling
	name = "malformed flesh"
	icon_state = "lingchameleon"
	item_icons = list(
			slot_l_hand_str = 'icons/mob/items/lefthand_uniforms.dmi',
			slot_r_hand_str = 'icons/mob/items/righthand_uniforms.dmi',
			)
	item_state = "lingchameleon"
	worn_state = "lingchameleon"
	desc = "The flesh all around us has grown a new layer of cells that can shift appearance and create a biological fabric that cannot be distinguished from \
	ordinary cloth, allowing us to make ourselves appear to wear almost anything."
	canremove = FALSE //Since this is essentially flesh impersonating clothes, tearing someone's skin off as if it were clothing isn't possible.
	has_sensor = FALSE // Reveals ling, and doesn't make sense anyway!

/obj/item/clothing/under/chameleon/changeling/emp_act(severity, recursive) //As these are purely organic, EMP does nothing to them.
	. = ..()
	return

EXTEND_INTERACTIONS(/obj/item/clothing/under/chameleon/changeling, \
	INTERACT_VERB("Shred Jumpsuit", PROC_REF(changeling_under_shred_verb), REQ_IN_INVENTORY), \
)

/// Old verb "Shred Jumpsuit".
/obj/item/clothing/under/chameleon/changeling/proc/changeling_under_shred_verb(mob/user, obj/item/held, datum/interaction/interaction)
	if(ishuman(loc))
		var/mob/living/carbon/human/H = loc
		playsound(src, 'sound/effects/splat.ogg', 30, 1)
		visible_message(span_warning("[H] tears off [src]!"),
		span_notice("We remove [src]."))
		qdel(src)

/obj/item/clothing/head/chameleon/changeling
	name = "malformed head"
	icon_state = "lingchameleon"
	desc = "Our head is swelled with a large quanity of rapidly shifting skin cells.  We can reform our head to resemble various hats and \
	helmets that biologicals are so fond of wearing."
	canremove = FALSE

/obj/item/clothing/head/chameleon/changeling/Initialize(mapload)
	. = ..()
	emp_protection_flags |= EMP_PROTECT_SELF

EXTEND_INTERACTIONS(/obj/item/clothing/head/chameleon/changeling, \
	INTERACT_VERB("Shred Helmet", PROC_REF(changeling_head_shred_verb), REQ_IN_INVENTORY), \
)

/// Old verb "Shred Helmet".
/obj/item/clothing/head/chameleon/changeling/proc/changeling_head_shred_verb(mob/user, obj/item/held, datum/interaction/interaction)
	if(ishuman(loc))
		var/mob/living/carbon/human/H = loc
		playsound(src, 'sound/effects/splat.ogg', 30, 1)
		visible_message(span_warning("[H] tears off [src]!"),
		span_notice("We remove [src]."))
		qdel(src)

/obj/item/clothing/suit/chameleon/changeling
	name = "chitinous chest"
	icon_state = "lingchameleon"
	item_icons = list(
			slot_l_hand_str = 'icons/mob/items/lefthand_suits.dmi',
			slot_r_hand_str = 'icons/mob/items/righthand_suits.dmi',
			)
	item_state = "armor"
	desc = "The cells in our chest are rapidly shifting, ready to reform into material that can resemble most pieces of clothing."
	canremove = FALSE

/obj/item/clothing/suit/chameleon/changeling/Initialize(mapload)
	. = ..()
	emp_protection_flags |= EMP_PROTECT_SELF

EXTEND_INTERACTIONS(/obj/item/clothing/suit/chameleon/changeling, \
	INTERACT_VERB("Shred Suit", PROC_REF(changeling_suit_shred_verb), REQ_IN_INVENTORY), \
)

/// Old verb "Shred Suit".
/obj/item/clothing/suit/chameleon/changeling/proc/changeling_suit_shred_verb(mob/user, obj/item/held, datum/interaction/interaction)
	if(ishuman(loc))
		var/mob/living/carbon/human/H = loc
		playsound(src, 'sound/effects/splat.ogg', 30, 1)
		visible_message(span_warning("[H] tears off [src]!"),
		span_notice("We remove [src]."))
		qdel(src)

/obj/item/clothing/shoes/chameleon/changeling
	name = "malformed feet"
	icon_state = "lingchameleon"
	item_icons = list(
			slot_l_hand_str = 'icons/mob/items/lefthand_shoes.dmi',
			slot_r_hand_str = 'icons/mob/items/righthand_shoes.dmi',
			)
	item_state = "black"
	desc = "Our feet are overlayed with another layer of flesh and bone on top.  We can reform our feet to resemble various boots and shoes."
	canremove = FALSE

/obj/item/clothing/shoes/chameleon/changeling/Initialize(mapload)
	. = ..()
	emp_protection_flags |= EMP_PROTECT_SELF

EXTEND_INTERACTIONS(/obj/item/clothing/shoes/chameleon/changeling, \
	INTERACT_VERB("Shred Shoes", PROC_REF(changeling_shoes_shred_verb), REQ_IN_INVENTORY), \
)

/// Old verb "Shred Shoes".
/obj/item/clothing/shoes/chameleon/changeling/proc/changeling_shoes_shred_verb(mob/user, obj/item/held, datum/interaction/interaction)
	if(ishuman(loc))
		var/mob/living/carbon/human/H = loc
		playsound(src, 'sound/effects/splat.ogg', 30, 1)
		visible_message(span_warning("[H] tears off [src]!"),
		span_notice("We remove [src]."))
		qdel(src)

/obj/item/storage/backpack/chameleon/changeling
	name = "backpack"
	icon_state = "backpack"
	item_icons = list(
			slot_l_hand_str = 'icons/mob/items/lefthand_storage.dmi',
			slot_r_hand_str = 'icons/mob/items/righthand_storage.dmi',
			)
	item_state = "backpack"
	desc = "A large pouch imbedded in our back, it can shift form to resemble many common backpacks that other biologicals are fond of using."
	canremove = FALSE

/obj/item/storage/backpack/chameleon/changeling/Initialize(mapload)
	. = ..()
	emp_protection_flags |= EMP_PROTECT_SELF

EXTEND_INTERACTIONS(/obj/item/storage/backpack/chameleon/changeling, \
	INTERACT_VERB("Shred Backpack", PROC_REF(changeling_backpack_shred_verb), REQ_IN_INVENTORY), \
)

/// Old verb "Shred Backpack".
/obj/item/storage/backpack/chameleon/changeling/proc/changeling_backpack_shred_verb(mob/user, obj/item/held, datum/interaction/interaction)
	if(ishuman(loc))
		var/mob/living/carbon/human/H = loc
		playsound(src, 'sound/effects/splat.ogg', 30, 1)
		visible_message(span_warning("[H] tears off [src]!"),
		span_notice("We remove [src]."))
		latent_materialize_all() // a walk needs real things (C5)
		for(var/atom/movable/AM in src.contents) //Dump whatever's in the bag before deleting. // ALLOW(latent): materialized above
			AM.forceMove(get_turf(loc))
		qdel(src)

/obj/item/clothing/gloves/chameleon/changeling
	name = "malformed hands"
	icon_state = "ling"
	item_icons = list(
			slot_l_hand_str = 'icons/mob/items/lefthand_gloves.dmi',
			slot_r_hand_str = 'icons/mob/items/righthand_gloves.dmi',
			)
	item_state = "ling"
	desc = "Our hands have a second layer of flesh on top.  We can reform our hands to resemble a large variety of fabrics and materials that biologicals \
	tend to wear on their hands.  Remember that these won't protect your hands from harm."
	canremove = FALSE

/obj/item/clothing/gloves/chameleon/changeling/Initialize(mapload)
	. = ..()
	emp_protection_flags |= EMP_PROTECT_SELF

EXTEND_INTERACTIONS(/obj/item/clothing/gloves/chameleon/changeling, \
	INTERACT_VERB("Shred Gloves", PROC_REF(changeling_gloves_shred_verb), REQ_IN_INVENTORY), \
)

/// Old verb "Shred Gloves".
/obj/item/clothing/gloves/chameleon/changeling/proc/changeling_gloves_shred_verb(mob/user, obj/item/held, datum/interaction/interaction)
	if(ishuman(loc))
		var/mob/living/carbon/human/H = loc
		playsound(src, 'sound/effects/splat.ogg', 30, 1)
		visible_message(span_warning("[H] tears off [src]!"),
		span_notice("We remove [src]."))
		qdel(src)

/obj/item/clothing/mask/chameleon/changeling
	name = "chitin visor"
	icon_state = "lingchameleon"
	item_icons = list(
			slot_l_hand_str = 'icons/mob/items/lefthand_masks.dmi',
			slot_r_hand_str = 'icons/mob/items/righthand_masks.dmi',
			)
	item_state = "gas_alt"
	desc = "A transparent visor of brittle chitin covers our face.  We can reform it to resemble various masks that biologicals use.  It can also utilize internal \
	tanks.."
	canremove = FALSE

/obj/item/clothing/mask/chameleon/changeling/Initialize(mapload)
	. = ..()
	emp_protection_flags |= EMP_PROTECT_SELF

EXTEND_INTERACTIONS(/obj/item/clothing/mask/chameleon/changeling, \
	INTERACT_VERB("Shred Mask", PROC_REF(changeling_mask_shred_verb), REQ_IN_INVENTORY), \
)

/// Old verb "Shred Mask".
/obj/item/clothing/mask/chameleon/changeling/proc/changeling_mask_shred_verb(mob/user, obj/item/held, datum/interaction/interaction)
	if(ishuman(loc))
		var/mob/living/carbon/human/H = loc
		playsound(src, 'sound/effects/splat.ogg', 30, 1)
		visible_message(span_warning("[H] tears off [src]!"),
		span_notice("We remove [src]."))
		qdel(src)

/obj/item/clothing/glasses/chameleon/changeling
	name = "chitin goggles"
	icon_state = "lingchameleon"
	item_state = "glasses"
	desc = "A transparent piece of eyewear made out of brittle chitin.  We can reform it to resemble various glasses and goggles."
	canremove = FALSE

/obj/item/clothing/glasses/chameleon/changeling/Initialize(mapload)
	. = ..()
	emp_protection_flags |= EMP_PROTECT_SELF

EXTEND_INTERACTIONS(/obj/item/clothing/glasses/chameleon/changeling, \
	INTERACT_VERB("Shred Glasses", PROC_REF(changeling_glasses_shred_verb), REQ_IN_INVENTORY), \
)

/// Old verb "Shred Glasses".
/obj/item/clothing/glasses/chameleon/changeling/proc/changeling_glasses_shred_verb(mob/user, obj/item/held, datum/interaction/interaction)
	if(ishuman(loc))
		var/mob/living/carbon/human/H = loc
		playsound(src, 'sound/effects/splat.ogg', 30, 1)
		visible_message(span_warning("[H] tears off [src]!"),
		span_notice("We remove [src]."))
		qdel(src)

/obj/item/storage/belt/chameleon/changeling
	name = "waist pouch"
	desc = "We can store objects in this, as well as shift it's appearance, so that it resembles various common belts."
	icon_state = "lingchameleon"
	item_icons = list(
			slot_l_hand_str = 'icons/mob/items/lefthand_storage.dmi',
			slot_r_hand_str = 'icons/mob/items/righthand_storage.dmi',
			)
	item_state = "utility"
	canremove = FALSE

/obj/item/storage/belt/chameleon/changeling/Initialize(mapload)
	. = ..()
	emp_protection_flags |= EMP_PROTECT_SELF

EXTEND_INTERACTIONS(/obj/item/storage/belt/chameleon/changeling, \
	INTERACT_VERB("Shred Belt", PROC_REF(changeling_belt_shred_verb), REQ_IN_INVENTORY), \
)

/// Old verb "Shred Belt".
/obj/item/storage/belt/chameleon/changeling/proc/changeling_belt_shred_verb(mob/user, obj/item/held, datum/interaction/interaction)
	if(ishuman(loc))
		var/mob/living/carbon/human/H = loc
		playsound(src, 'sound/effects/splat.ogg', 30, 1)
		visible_message(span_warning("[H] tears off [src]!"),
		span_notice("We remove [src]."))
		qdel(src)

/obj/item/card/id/syndicate/changeling
	name = "chitinous card"
	desc = "A card that we can reform to resemble identification cards.  Due to the nature of the material this is made of, it cannot store any access codes."
	icon_state = "changeling"
	assignment = "Harvester"
	electronic_warfare = 1 //The lack of RFID stuff makes it hard for AIs to track, I guess. *handwaves*
	registered_user_handle = null
	access = null
	canremove = FALSE

/obj/item/card/id/syndicate/changeling/Initialize(mapload)
	. = ..()
	if(ismob(loc))
		registered_user_handle = om_handle(loc)
	access = null

EXTEND_INTERACTIONS(/obj/item/card/id/syndicate/changeling, \
	INTERACT_VERB("Shred ID Card", PROC_REF(changeling_syndicate_shred_verb), REQ_IN_INVENTORY), \
)

/// Old verb "Shred ID Card".
/obj/item/card/id/syndicate/changeling/proc/changeling_syndicate_shred_verb(mob/user, obj/item/held, datum/interaction/interaction)
	if(ishuman(loc))
		var/mob/living/carbon/human/H = loc
		playsound(src, 'sound/effects/splat.ogg', 30, 1)
		visible_message(span_warning("[H] tears off [src]!"),
		span_notice("We remove [src]."))
		qdel(src)

/obj/item/card/id/syndicate/changeling/Click() //Since we can't hold it in our hands, and attack_hand() doesn't work if it in inventory...
	if(!registered_user())
		registered_user_handle = om_handle(usr)
		usr.set_id_info(src)
	tgui_interact(registered_user())
	..()
