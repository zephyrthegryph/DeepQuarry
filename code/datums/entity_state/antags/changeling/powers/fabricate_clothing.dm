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
	set category = VERB_CAT_CHANGELING
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

CAPABILITIES(/obj/item/clothing/under/chameleon/changeling)
	op("changeling_under_shred_verb", menu(), label("Shred Jumpsuit"), needs(carried()), then(PROC_REF(changeling_under_shred_verb)))

/// Old verb "Shred Jumpsuit".
/obj/item/clothing/under/chameleon/changeling/proc/changeling_under_shred_verb(datum/act/op/A)
	if(ishuman(loc))
		var/mob/living/carbon/human/H = loc
		play_sfx(src, SFX_EFFECTS_SPLAT, 0.6)
		visible_message(span_warning("[H] tears off [src]!"),
		span_notice("We remove [src]."))
		spent(src)

/obj/item/clothing/head/chameleon/changeling
	emp_protection_flags = EMP_PROTECT_SELF
	name = "malformed head"
	icon_state = "lingchameleon"
	desc = "Our head is swelled with a large quanity of rapidly shifting skin cells.  We can reform our head to resemble various hats and \
	helmets that biologicals are so fond of wearing."
	canremove = FALSE


CAPABILITIES(/obj/item/clothing/head/chameleon/changeling)
	op("changeling_head_shred_verb", menu(), label("Shred Helmet"), needs(carried()), then(PROC_REF(changeling_head_shred_verb)))

/// Old verb "Shred Helmet".
/obj/item/clothing/head/chameleon/changeling/proc/changeling_head_shred_verb(datum/act/op/A)
	if(ishuman(loc))
		var/mob/living/carbon/human/H = loc
		play_sfx(src, SFX_EFFECTS_SPLAT, 0.6)
		visible_message(span_warning("[H] tears off [src]!"),
		span_notice("We remove [src]."))
		spent(src)

/obj/item/clothing/suit/chameleon/changeling
	emp_protection_flags = EMP_PROTECT_SELF
	name = "chitinous chest"
	icon_state = "lingchameleon"
	item_icons = list(
			slot_l_hand_str = 'icons/mob/items/lefthand_suits.dmi',
			slot_r_hand_str = 'icons/mob/items/righthand_suits.dmi',
			)
	item_state = "armor"
	desc = "The cells in our chest are rapidly shifting, ready to reform into material that can resemble most pieces of clothing."
	canremove = FALSE


CAPABILITIES(/obj/item/clothing/suit/chameleon/changeling)
	op("changeling_suit_shred_verb", menu(), label("Shred Suit"), needs(carried()), then(PROC_REF(changeling_suit_shred_verb)))

/// Old verb "Shred Suit".
/obj/item/clothing/suit/chameleon/changeling/proc/changeling_suit_shred_verb(datum/act/op/A)
	if(ishuman(loc))
		var/mob/living/carbon/human/H = loc
		play_sfx(src, SFX_EFFECTS_SPLAT, 0.6)
		visible_message(span_warning("[H] tears off [src]!"),
		span_notice("We remove [src]."))
		spent(src)

/obj/item/clothing/shoes/chameleon/changeling
	emp_protection_flags = EMP_PROTECT_SELF
	name = "malformed feet"
	icon_state = "lingchameleon"
	item_icons = list(
			slot_l_hand_str = 'icons/mob/items/lefthand_shoes.dmi',
			slot_r_hand_str = 'icons/mob/items/righthand_shoes.dmi',
			)
	item_state = "black"
	desc = "Our feet are overlayed with another layer of flesh and bone on top.  We can reform our feet to resemble various boots and shoes."
	canremove = FALSE


CAPABILITIES(/obj/item/clothing/shoes/chameleon/changeling)
	op("changeling_shoes_shred_verb", menu(), label("Shred Shoes"), needs(carried()), then(PROC_REF(changeling_shoes_shred_verb)))

/// Old verb "Shred Shoes".
/obj/item/clothing/shoes/chameleon/changeling/proc/changeling_shoes_shred_verb(datum/act/op/A)
	if(ishuman(loc))
		var/mob/living/carbon/human/H = loc
		play_sfx(src, SFX_EFFECTS_SPLAT, 0.6)
		visible_message(span_warning("[H] tears off [src]!"),
		span_notice("We remove [src]."))
		spent(src)

/obj/item/storage/backpack/chameleon/changeling
	emp_protection_flags = EMP_PROTECT_SELF
	name = "backpack"
	icon_state = "backpack"
	item_icons = list(
			slot_l_hand_str = 'icons/mob/items/lefthand_storage.dmi',
			slot_r_hand_str = 'icons/mob/items/righthand_storage.dmi',
			)
	item_state = "backpack"
	desc = "A large pouch imbedded in our back, it can shift form to resemble many common backpacks that other biologicals are fond of using."
	canremove = FALSE


CAPABILITIES(/obj/item/storage/backpack/chameleon/changeling)
	op("changeling_backpack_shred_verb", menu(), label("Shred Backpack"), needs(carried()), then(PROC_REF(changeling_backpack_shred_verb)))

/// Old verb "Shred Backpack".
/obj/item/storage/backpack/chameleon/changeling/proc/changeling_backpack_shred_verb(datum/act/op/A)
	if(ishuman(loc))
		var/mob/living/carbon/human/H = loc
		play_sfx(src, SFX_EFFECTS_SPLAT, 0.6)
		visible_message(span_warning("[H] tears off [src]!"),
		span_notice("We remove [src]."))
		latent_materialize_all() // a walk needs real things (C5)
		for(var/atom/movable/AM in contents_of(src)) //Dump whatever's in the bag before deleting. // ALLOW(latent): the contents were materialized by an earlier latent_materialize_all() in this proc, so this scan sees real objects
			AM.forceMove(get_turf(loc))
		spent(src)

/obj/item/clothing/gloves/chameleon/changeling
	emp_protection_flags = EMP_PROTECT_SELF
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


CAPABILITIES(/obj/item/clothing/gloves/chameleon/changeling)
	op("changeling_gloves_shred_verb", menu(), label("Shred Gloves"), needs(carried()), then(PROC_REF(changeling_gloves_shred_verb)))

/// Old verb "Shred Gloves".
/obj/item/clothing/gloves/chameleon/changeling/proc/changeling_gloves_shred_verb(datum/act/op/A)
	if(ishuman(loc))
		var/mob/living/carbon/human/H = loc
		play_sfx(src, SFX_EFFECTS_SPLAT, 0.6)
		visible_message(span_warning("[H] tears off [src]!"),
		span_notice("We remove [src]."))
		spent(src)

/obj/item/clothing/mask/chameleon/changeling
	emp_protection_flags = EMP_PROTECT_SELF
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


CAPABILITIES(/obj/item/clothing/mask/chameleon/changeling)
	op("changeling_mask_shred_verb", menu(), label("Shred Mask"), needs(carried()), then(PROC_REF(changeling_mask_shred_verb)))

/// Old verb "Shred Mask".
/obj/item/clothing/mask/chameleon/changeling/proc/changeling_mask_shred_verb(datum/act/op/A)
	if(ishuman(loc))
		var/mob/living/carbon/human/H = loc
		play_sfx(src, SFX_EFFECTS_SPLAT, 0.6)
		visible_message(span_warning("[H] tears off [src]!"),
		span_notice("We remove [src]."))
		spent(src)

/obj/item/clothing/glasses/chameleon/changeling
	emp_protection_flags = EMP_PROTECT_SELF
	name = "chitin goggles"
	icon_state = "lingchameleon"
	item_state = "glasses"
	desc = "A transparent piece of eyewear made out of brittle chitin.  We can reform it to resemble various glasses and goggles."
	canremove = FALSE


CAPABILITIES(/obj/item/clothing/glasses/chameleon/changeling)
	op("changeling_glasses_shred_verb", menu(), label("Shred Glasses"), needs(carried()), then(PROC_REF(changeling_glasses_shred_verb)))

/// Old verb "Shred Glasses".
/obj/item/clothing/glasses/chameleon/changeling/proc/changeling_glasses_shred_verb(datum/act/op/A)
	if(ishuman(loc))
		var/mob/living/carbon/human/H = loc
		play_sfx(src, SFX_EFFECTS_SPLAT, 0.6)
		visible_message(span_warning("[H] tears off [src]!"),
		span_notice("We remove [src]."))
		spent(src)

/obj/item/storage/belt/chameleon/changeling
	emp_protection_flags = EMP_PROTECT_SELF
	name = "waist pouch"
	desc = "We can store objects in this, as well as shift it's appearance, so that it resembles various common belts."
	icon_state = "lingchameleon"
	item_icons = list(
			slot_l_hand_str = 'icons/mob/items/lefthand_storage.dmi',
			slot_r_hand_str = 'icons/mob/items/righthand_storage.dmi',
			)
	item_state = "utility"
	canremove = FALSE


CAPABILITIES(/obj/item/storage/belt/chameleon/changeling)
	op("changeling_belt_shred_verb", menu(), label("Shred Belt"), needs(carried()), then(PROC_REF(changeling_belt_shred_verb)))

/// Old verb "Shred Belt".
/obj/item/storage/belt/chameleon/changeling/proc/changeling_belt_shred_verb(datum/act/op/A)
	if(ishuman(loc))
		var/mob/living/carbon/human/H = loc
		play_sfx(src, SFX_EFFECTS_SPLAT, 0.6)
		visible_message(span_warning("[H] tears off [src]!"),
		span_notice("We remove [src]."))
		spent(src)

/obj/item/card/id/syndicate/changeling
	name = "chitinous card"
	desc = "A card that we can reform to resemble identification cards.  Due to the nature of the material this is made of, it cannot store any access codes."
	icon_state = "changeling"
	assignment = "Harvester"
	electronic_warfare = 1 //The lack of RFID stuff makes it hard for AIs to track, I guess. *handwaves*
	access = null
	canremove = FALSE

/obj/item/card/id/syndicate/changeling/Initialize(mapload)
	. = ..()
	if(ismob(loc))
		rel_set(src, nameof(registered_user), loc)
	access = null

CAPABILITIES(/obj/item/card/id/syndicate/changeling)
	op("changeling_syndicate_shred_verb", menu(), label("Shred ID Card"), needs(carried()), then(PROC_REF(changeling_syndicate_shred_verb)))
	click_on(PROC_REF(click_input))

/// Old verb "Shred ID Card".
/obj/item/card/id/syndicate/changeling/proc/changeling_syndicate_shred_verb(datum/act/op/A)
	if(ishuman(loc))
		var/mob/living/carbon/human/H = loc
		play_sfx(src, SFX_EFFECTS_SPLAT, 0.6)
		visible_message(span_warning("[H] tears off [src]!"),
		span_notice("We remove [src]."))
		spent(src)

/// The native Click's actor and arguments, handed over by the engine (click_on(), code/engine/lifeforms/input.dm). Since we can't hold it in our hands, and
/// attack_hand() doesn't work while it is in the inventory, a click registers or shows it, then goes on to the native parent.
/obj/item/card/id/syndicate/changeling/proc/click_input(datum/act/input/A)
	register_and_show_with_actor(A.actor)
	return INPUT_FALLTHROUGH

/obj/item/card/id/syndicate/changeling/proc/register_and_show_with_actor(mob/user)
	if(!registered_user())
		if(!user)
			return
		rel_set(src, nameof(registered_user), user)
		user.set_id_info(src)
	tgui_interact(registered_user())
