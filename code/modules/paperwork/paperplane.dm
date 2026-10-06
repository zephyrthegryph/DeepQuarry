// Ported from TG. Known issue: Throw hit can possibly double-proc. Seems to be throw code.
/obj/item/paperplane
	name = "paper plane"
	desc = "Paper folded into the shape of a plane."
	icon = 'icons/obj/bureaucracy.dmi'
	icon_state = "paperplane"
	throw_range = 7
	throw_speed = 1
	throwforce = 0
	w_class = ITEMSIZE_TINY

	var/obj/item/paper/internalPaper

CAPABILITIES(/obj/item/paperplane)
	owns_one(nameof(internalPaper), /obj/item/paper)
	param(nameof(internalPaper), pos = 1, apply = PROC_REF(fold_from))
	rolls(nameof(pixel_x), range_of(-9, 9))
	rolls(nameof(pixel_y), range_of(-8, 8))

/// Applied at init from its constructor param (param(apply =), code/engine/lifeforms/params.dm). A plane folded from a paper takes it in; one made bare folds a blank sheet.
/obj/item/paperplane/proc/fold_from(obj/item/paper/newPaper)
	if(newPaper)
		flags = newPaper.flags
		color = newPaper.color
		if(isstorage(newPaper.loc))
			var/obj/item/storage/S = newPaper.loc
			S.remove_from_storage(newPaper, src)
		else
			newPaper.forceMove(src)
	else
		rel_set(src, nameof(internalPaper), new /obj/item/paper(src))
	update_icon()


DECLARE_APPEARANCE_PROC(/obj/item/paperplane, TYPE_PROC_REF(/atom, appearance_overlays), list())
/obj/item/paperplane/appearance_overlays()
	. = list()
	var/list/stamped = internalPaper.stamped
	if(!stamped)
		stamped = new
	else if(stamped)
		for(var/obj/item/stamp/stamp as anything in stamped)
			var/image/stampoverlay = image('icons/obj/bureaucracy.dmi', "paperplane_[initial(stamp.icon_state)]")
			. += stampoverlay

DECLARE_INTERACTIONS(/obj/item/paperplane, \
	INTERACT_USE(null, PROC_REF(interaction_self)), \
	INTERACT_ITEM(null, PROC_REF(interaction_item)), \
)

/// Old attack_self.
/obj/item/paperplane/proc/interaction_self(mob/user, obj/item/held, datum/interaction/interaction)
	to_chat(user, span_notice("You unfold [src]."))
	var/atom/movable/internal_paper_tmp = internalPaper
	internal_paper_tmp.forceMove(loc)
	own_take(src, nameof(internalPaper))
	consume(src, user)
	user.put_in_hands(internal_paper_tmp)
	return TRUE

/// Old attackby.
/obj/item/paperplane/proc/interaction_item(mob/living/carbon/human/user, obj/item/P, datum/interaction/interaction)
	if(istype(P, /obj/item/pen))
		to_chat(user, span_notice("You should unfold [src] before changing it."))
		return INTERACTION_HANDLED_PASS

	else if(istype(P, /obj/item/stamp)) 	//we don't randomize stamps on a paperplane
		internalPaper.attackby(P, user) //spoofed attack to update internal paper.
		update_icon()

	else if(is_hot(P))
		if(user.disabilities & CLUMSY && prob(10))
			act_message(user, src, MSG_SELF(span_userdanger("You miss %T% and accidentally light yourself on fire!")), \
				MSG_OTHERS(span_warning("%U% accidentally ignites themselves!")))
			user.unEquip(P)
			user.adjust_fire_stacks(1)
			user.ignite_mob()
			return INTERACTION_HANDLED_PASS

		if(!(in_range(user, src))) //to prevent issues as a result of telepathically lighting a paper
			return INTERACTION_HANDLED_PASS
		user.unEquip(src)
		act_message(user, src, MSG_SELF(span_danger("You light %T% on fire!")), MSG_OTHERS(span_danger("%U% lights %T% ablaze with [P]!")))
		fire_act()

	add_fingerprint(user)
	return INTERACTION_HANDLED_PASS

/obj/item/paperplane/throw_impact(atom/hit_atom)
	if(..() || !ishuman(hit_atom))//if the plane is caught or it hits a nonhuman
		return
	var/mob/living/carbon/human/H = hit_atom
	if(prob(2))
		if((H.get_equipped_item(SLOT_ID_HEAD) && H.get_equipped_item(SLOT_ID_HEAD).body_parts_covered & EYES) || (H.get_equipped_item(SLOT_ID_MASK) && H.get_equipped_item(SLOT_ID_MASK).body_parts_covered & EYES) || (H.get_equipped_item(SLOT_ID_EYES) && H.get_equipped_item(SLOT_ID_EYES).body_parts_covered & EYES))
			return
		visible_message(span_danger("\The [src] hits [H] in the eye!"))
		H.status_adjust(STAT_BLURRY, 10)
		var/obj/item/organ/internal/eyes/E = H.organ_in(O_EYES)
		if(E)
			H.injure(INJURY_BLUNT, 2.5, E, src, flags = INJURE_SILENT)
		H.emote("scream")

/// Old click_alt: fold the paper into a plane.
/obj/item/paper/proc/interaction_fold_plane(mob/living/carbon/user, obj/item/held, datum/interaction/interaction)
	if(!plane_foldable)
		return TRUE
	if ( istype(user) )
		if( (!in_range(src, user)) || user.stat || user.restrained() )
			return TRUE
		to_chat(user, span_notice("You fold [src] into the shape of a plane!"))
		user.unEquip(src)
		var/obj/item/I = new /obj/item/paperplane(user, src)
		user.put_in_hands(I)
	else
		to_chat(user, span_notice(" You lack the dexterity to fold \the [src]. "))
	return TRUE
