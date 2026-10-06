/*
 * Augments. This file contains the base, and organic-targeting augments.
 */

/obj/item/organ/internal/augment
	name = "augment"

	icon_state = "cell_bay"

	robotic = ORGAN_ROBOT
	parent_organ = BP_TORSO

	organ_verbs = list(/mob/living/carbon/human/proc/augment_menu)	// Verbs added by the organ when present in the body.
	forgiving_class = TRUE	// Will the organ give its verbs when it isn't a perfect match? I.E., assisted in organic, synthetic in organic.

	butcherable = FALSE

	var/obj/item/integrated_object	// Objects held by the organ, used for re-usable, deployable things.
	var/integrated_object_type	// Object type the organ will spawn.
	var/target_slot = null

	var/silent_deploy = FALSE

	var/image/my_radial_icon = null
	var/radial_icon = null	// DMI for the augment's radial icon.
	var/radial_name = null	// The augment's name in the Radial Menu.
	var/radial_state = null	// Icon state for the augment's radial icon.

	var/aug_cooldown = 1 SECONDS // no reason for it to be 30 seconds, the powerful implants already have their own values
	var/cooldown = null

	description_fluff = "If attempting to implant a compatible augment into a synthetic limb, the limb must be screwdrivered open and then the augment port opened with a crowbar before insertion can begin."


CAPABILITIES(/obj/item/organ/internal/augment)
	owns_one(nameof(integrated_object), starts = nameof(integrated_object_type))

/obj/item/organ/internal/augment/Initialize(mapload)
	. = ..()
	setup_radial_icon()
	if(integrated_object) // declared child
		integrated_object.canremove = FALSE

/obj/item/organ/internal/augment/proc/setup_radial_icon()
	if(!radial_icon)
		radial_icon = icon
	if(!radial_name)
		radial_name = name
	if(!radial_state)
		radial_state = icon_state
	my_radial_icon = image(icon = radial_icon, icon_state = radial_state)

/obj/item/organ/internal/augment/handle_organ_mod_special(removed = FALSE)
	if(removed && integrated_object && integrated_object.loc != src)
		if(isliving(integrated_object.loc))
			var/mob/living/L = integrated_object.loc
			L.drop_from_inventory(integrated_object)
		integrated_object.forceMove(src)
	..(removed)

/obj/item/organ/internal/augment/proc/augment_action()
	if(!owner)
		return

	if(aug_cooldown)
		if(COOLDOWN_FINISHED(src, cooldown))
			COOLDOWN_START(src, cooldown, aug_cooldown)
		else
			return

	if(robotic && owner.get_restraining_bolt())
		to_chat(owner, span_warning("\The [src] doesn't respond."))
		return

	var/item_to_equip = integrated_object
	if(!item_to_equip && integrated_object_type)
		item_to_equip = integrated_object_type

	if(ispath(item_to_equip))
		owner.equip_augment_item(target_slot, item_to_equip, silent_deploy)
	else if(item_to_equip)
		owner.equip_augment_item(target_slot, item_to_equip, silent_deploy, src)

/*
 * Human-specific mob procs.
 */

// The next two procs simply handle the radial menu for augment activation.

/mob/living/carbon/human/proc/augment_menu()
	set name = "Open Augment Menu"
	set desc = "Toggle your augment menu."
	set category = VERB_CAT_AUGMENTS

	enable_augments(src)

/mob/living/carbon/human/proc/enable_augments(mob/living/user)
	var/list/options = list()

	var/list/present_augs = list()

	for(var/obj/item/organ/internal/augment/Aug in internal_organ_list())
		if(Aug.my_radial_icon && !Aug.is_broken() && Aug.check_verb_compatability())
			present_augs[Aug.radial_name] = Aug

	for(var/augname in present_augs)
		var/obj/item/organ/internal/augment/iconsource = present_augs[augname]
		options[augname] = iconsource.my_radial_icon

	if(length(options) && user && !QDELETED(user))
		open_request(src, /datum/prompt/choice/augment_activation, PROC_REF(augment_chosen), answerer = user, choices = options, anchor = src, present_augs = present_augs)

/// The name -> augment snapshot is a list, as in the original radial request.
/datum/prompt/choice/augment_activation
	timeout = 0
	radial = TRUE
	autopick_single_option = TRUE
	var/list/present_augs

/// Answer to enable_augments(): activate the picked augment.
/mob/living/carbon/human/proc/augment_chosen(datum/act/request/context)
	if(!context.answer)
		return
	var/datum/prompt/choice/augment_activation/ask = context.request
	var/list/present_augs = ask.present_augs
	if(isnull(ask.value) || !islist(present_augs))
		return
	var/obj/item/organ/internal/augment/A = present_augs[ask.value]
	if(!istype(A) || QDELETED(A) || A.owner != src || A.is_broken())
		return
	A.augment_action(ask.answerer)

/* equip_augment_item
 * Used to equip an organ's augment items when possible.
 * slot is the target equip slot, if it's not a generic either-hand deployable,
 * equipping is either the target object, or a path for the target object,
 * cling_to_organ is a reference to the organ object itself, so they can easily return to their organ when removed by any means.
 */

/mob/living/carbon/human/proc/equip_augment_item(slot, obj/item/equipping = null, make_sound = TRUE, obj/item/organ/cling_to_organ = null)
	if(!ishuman(src))
		return 0

	if(!equipping)
		return 0

	var/mob/living/carbon/human/M = src

	if(src?.buckled_to())
		var/obj/Ob = src?.buckled_to()
		if(Ob.buckle_lying)
			to_chat(M, span_notice("You cannot use your augments when restrained."))
			return 0

	if((slot == SLOT_ID_HAND_L && get_equipped_item(SLOT_ID_HAND_L)) || (slot == SLOT_ID_HAND_R && get_equipped_item(SLOT_ID_HAND_R)))
		to_chat(M,span_warning("Your hand is full.  Drop something first."))
		return 0

	var/del_if_failure = FALSE
	if(ispath(equipping))
		del_if_failure = TRUE
		equipping = new equipping(src)

	if(!slot)
		put_in_any_hand_if_possible(equipping, del_if_failure)

	else
		if(slot_is_accessible(slot, equipping, src))
			equip_to_slot(equipping, slot, 1, 1)
		else if(del_if_failure)
			spent(equipping)
			return 0

	if(cling_to_organ) // Does the object automatically return to the organ?
		rel_set(equipping, nameof(equipping.my_augment), cling_to_organ)

	if(make_sound)
		play_sfx(src, SFX_ITEMS_CHANGE_JAWS, 0.6)

	if(equipping.loc != src)
		equipping.dropped(src)

	return 1
