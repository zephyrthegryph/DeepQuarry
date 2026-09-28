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

/obj/item/paperplane/Initialize(mapload, obj/item/paper/newPaper)
	. = ..()
	pixel_y = rand(-8, 8)
	pixel_x = rand(-9, 9)
	if(newPaper)
		internalPaper = newPaper
		flags = newPaper.flags
		color = newPaper.color
		if(isstorage(newPaper.loc))
			var/obj/item/storage/S = newPaper.loc
			S.remove_from_storage(newPaper, src)
		else
			newPaper.forceMove(src)
	else
		internalPaper = new /obj/item/paper(src)
	update_icon()

REF_OWNED(/obj/item/paperplane, "internalPaper")

/obj/item/paperplane/update_icon()
	cut_overlays()
	var/list/stamped = internalPaper.stamped
	if(!stamped)
		stamped = new
	else if(stamped)
		for(var/obj/item/stamp/stamp as anything in stamped)
			var/image/stampoverlay = image('icons/obj/bureaucracy.dmi', "paperplane_[initial(stamp.icon_state)]")
			add_overlay(stampoverlay)

DECLARE_INTERACTIONS(/obj/item/paperplane, \
	INTERACT_USE(null, PROC_REF(interaction_self)), \
	INTERACT_ITEM(null, PROC_REF(interaction_item)), \
)

/// Old attack_self.
/obj/item/paperplane/proc/interaction_self(mob/user, obj/item/held, datum/interaction/interaction)
	to_chat(user, span_notice("You unfold [src]."))
	var/atom/movable/internal_paper_tmp = internalPaper
	internal_paper_tmp.forceMove(loc)
	internalPaper = null
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
			user.visible_message(span_warning("[user] accidentally ignites themselves!"), \
				span_userdanger("You miss the [src] and accidentally light yourself on fire!"))
			user.unEquip(P)
			user.adjust_fire_stacks(1)
			user.ignite_mob()
			return INTERACTION_HANDLED_PASS

		if(!(in_range(user, src))) //to prevent issues as a result of telepathically lighting a paper
			return INTERACTION_HANDLED_PASS
		user.unEquip(src)
		user.visible_message(span_danger("[user] lights [src] ablaze with [P]!"), span_danger("You light [src] on fire!"))
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
		H.status_adjust(EFFECT_BLURRY, 10)
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
