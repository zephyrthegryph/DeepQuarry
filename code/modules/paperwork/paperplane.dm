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
	/// The stamps its paper carries, as the plane's overlay states (kept here so the look reads only the plane's own state).
	var/list/stamp_marks

CAPABILITIES(/obj/item/paperplane)
	owns_one(nameof(internalPaper), /obj/item/paper)
	param(nameof(internalPaper), pos = 1, apply = PROC_REF(fold_from))
	rolls(nameof(pixel_x), range_of(-9, 9))
	rolls(nameof(pixel_y), range_of(-8, 8))
	op("self", in_hand(), label("Use"), then(PROC_REF(interaction_self)))
	op("item", item(/obj/item), label("Use"), then(PROC_REF(interaction_item)))

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
	sync_stamps()


TRACKED(/obj/item/paperplane, stamp_marks)

/// Copies the stamps of the plane's paper into stamp_marks. Called when the paper is folded in and after a stamp lands on it.
/obj/item/paperplane/proc/sync_stamps()
	var/list/marks = list()
	for(var/obj/item/stamp/stamp as anything in internalPaper?.stamped)
		marks += initial(stamp.icon_state)
	set_stamp_marks(marks)

/// A plane shows the stamps its paper carries.
/obj/item/paperplane/draw(datum/look/look)
	..()
	for(var/mark in stamp_marks)
		look.overlay("paperplane_[mark]")

/// Old attack_self.
/obj/item/paperplane/proc/interaction_self(datum/act/op/A)
	var/mob/user = A.actor
	to_chat(user, span_notice("You unfold [src]."))
	var/atom/movable/internal_paper_tmp = internalPaper
	internal_paper_tmp.forceMove(loc)
	rel_take(src, nameof(internalPaper))
	consume(src, user)
	user.put_in_hands(internal_paper_tmp)
	return TRUE

/// Old attackby.
/obj/item/paperplane/proc/interaction_item(datum/act/op/A)
	var/mob/living/carbon/human/user = A.actor
	var/obj/item/P = A.held
	if(istype(P, /obj/item/pen))
		to_chat(user, span_notice("You should unfold [src] before changing it."))
		return OP_PASS

	else if(istype(P, /obj/item/stamp)) 	//we don't randomize stamps on a paperplane
		internalPaper.attackby(P, user) //spoofed attack to update internal paper.
		sync_stamps()

	else if(is_hot(P))
		if(user.disabilities & CLUMSY && prob(10))
			act_message(user, src, MSG_SELF(span_userdanger("You miss %T% and accidentally light yourself on fire!")), \
				MSG_OTHERS(span_warning("%U% accidentally ignites themselves!")))
			user.unEquip(P)
			user.adjust_fire_stacks(1)
			user.ignite_mob()
			return OP_PASS

		if(!(in_range(user, src))) //to prevent issues as a result of telepathically lighting a paper
			return OP_PASS
		user.unEquip(src)
		act_message(user, src, MSG_SELF(span_danger("You light %T% on fire!")), MSG_OTHERS(span_danger("%U% lights %T% ablaze with [P]!")))
		fire_act()

	add_fingerprint(user)
	return OP_PASS

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
/obj/item/paper/proc/interaction_fold_plane(datum/act/op/A)
	var/mob/living/carbon/user = A.actor
	if(!plane_foldable)
		return OP_OK
	if ( istype(user) )
		if( (!in_range(src, user)) || user.stat || user.restrained() )
			return OP_OK
		to_chat(user, span_notice("You fold [src] into the shape of a plane!"))
		user.unEquip(src)
		var/obj/item/I = new /obj/item/paperplane(user, src)
		user.put_in_hands(I)
	else
		to_chat(user, span_notice(" You lack the dexterity to fold \the [src]. "))
	return OP_OK
