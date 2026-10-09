//Also contains /obj/structure/closet/body_bag because I doubt anyone would think to look for bodybags in /object/structures

/obj/item/bodybag
	name = "body bag"
	desc = "A folded bag designed for the storage and transportation of cadavers."
	icon = 'icons/obj/closets/bodybag.dmi'
	icon_state = "bodybag_folded"
	w_class = ITEMSIZE_SMALL

	//Used for cryogenic bodybags
	var/obj/item/reagent_containers/syringe/syringe
	var/cryogenic = FALSE
	var/robotic = FALSE
	var/mass_grave = FALSE

// A folded bag used in hand is unfolded onto the floor (a refused folded bag keeps its owned injector).
CAPABILITIES(/obj/item/bodybag)
	owns_one(nameof(syringe), /obj/item/reagent_containers/syringe)
	op("unfold", in_hand(), label("Unfold"), needs(req(PROC_REF(can_unfold), because = PROC_REF(unfold_refusal))), then(PROC_REF(unfolded)))

/// Unfolding must leave a refused folded bag and its owned injector intact: where it is carried must let it go.
/obj/item/bodybag/proc/can_unfold(datum/act/op/A)
	return isnull(loc?.release_refusal(src, A.actor)) // ALLOW(reads): where the bag is carried and whether that lets it go are read when it is unfolded

/obj/item/bodybag/proc/unfold_refusal(datum/act/op/A)
	return loc?.release_refusal(src, A.actor) || /datum/msg/op/not_available

/// The floor structure this folded bag makes.
/obj/item/bodybag/proc/unfolded_type()
	if(cryogenic)
		return /obj/structure/closet/body_bag/cryobag
	if(robotic)
		return /obj/structure/closet/body_bag/cryobag/robobag
	return /obj/structure/closet/body_bag

/// The folded item is released from where it is carried, the floor structure is made (and takes the injector the folded bag owned), and the folded bag is used up.
/obj/item/bodybag/proc/unfolded(datum/act/op/A)
	var/mob/user = A.actor
	if(!loc.release_to(src, user.loc, null, user))
		return OP_REFUSED
	var/made_type = unfolded_type()
	var/obj/structure/closet/body_bag/R = new made_type(user.loc)
	R.add_fingerprint(user)
	if(syringe && istype(R, /obj/structure/closet/body_bag/cryobag))
		rel_move(src, nameof(syringe), R, nameof(/obj/structure/closet/body_bag/cryobag::syringe)) // stays in nullspace, now the unfolded bag's
	consume(src, user)
	return OP_OK

/obj/item/storage/box/bodybags
	name = "body bags"
	desc = "This box contains body bags."
	icon_state = "bodybags"
	starts_with = list(/obj/item/bodybag = 7)

/obj/structure/closet/body_bag
	name = "body bag"
	collects_in_play = FALSE // unfolded on the floor, it takes nothing lying there (a mapped bag still holds what was mapped into it)
	desc = "A plastic bag designed for the storage and transportation of cadavers."
	icon = 'icons/obj/closets/bodybag.dmi'
	closet_appearance = null
	open_sound = SFX_ITEMS_ZIP
	close_sound = SFX_ITEMS_ZIP
	var/item_path = /obj/item/bodybag
	density = FALSE
	storage_capacity = (MOB_MEDIUM * 2) - 1
	var/contains_body = FALSE
	var/has_label = FALSE

TRACKED(/obj/structure/closet/body_bag, has_label)

/obj/item/bodybag/large
	name = "mass grave body bag"
	desc = "A large folded bag designed for the storage and transportation of cadavers."
	icon = 'icons/obj/closets/bodybag_large.dmi'
	w_class = ITEMSIZE_LARGE
	mass_grave = TRUE

/obj/item/bodybag/large/unfolded_type()
	return /obj/structure/closet/body_bag/large

/obj/structure/closet/body_bag/large
	name = "mass grave body bag"
	desc = "A massive body bag that holds as much as it does due to bluespace lining on its zipper. Shockingly compact for its storage."
	icon = 'icons/obj/closets/bodybag_large.dmi'
	storage_capacity = (MOB_MEDIUM * 12) - 1 //Holds 12 bodys
	item_path = /obj/item/bodybag/large

MSG_DEF(bodybag/folded, "You fold up %T%.", "%U% folds up %T%.")
MSG_DEF(bodybag/cut_label, "You cut the tag off %T%.", "%U% cuts the tag off %T%.")

// A body bag is a closet that never blocks the tile, is never sealed, holds one person (a mass grave bag a dozen less one), is labelled with a pen (the
// label is asked for, and cut off with wirecutters) and folds up when somebody drags it onto themselves while it is shut and empty.
CAPABILITIES(/obj/structure/closet/body_bag)
	op("label", item(/obj/item/pen), label("Label"), priority(OP_PRIORITY_PART),
		asks(/datum/prompt/text, fields = list("question" = "What would you like the label to be?", "max_len" = MAX_NAME_LEN)), then(PROC_REF(labelled)))
	op("cut_label", tool(TOOL_WIRECUTTER), label("Cut the tag off"), priority(OP_PRIORITY_PART), wait(0), then(PROC_REF(label_cut)), says(MSG(bodybag/cut_label)))
	op("fold", at_target(/mob/living), gesture(GESTURE_DRAG), label("Fold up"), when(req(PROC_REF(dragged_onto_self))), then(PROC_REF(folded_up)))

/// The label the pen was asked for is put on the bag (an empty one leaves the bag as it was).
/obj/structure/closet/body_bag/proc/labelled(datum/act/op/A)
	var/mob/user = A.actor
	if(!(in_range(src, user) || loc == user))
		return OP_REFUSED
	var/datum/prompt/R = A.answer
	var/t = sanitizeSafe(R?.value, MAX_NAME_LEN)
	if(t)
		name = "body bag - [t]"
		set_has_label(TRUE)
	else
		name = "body bag"
	return OP_OK

/// The tag comes off.
/obj/structure/closet/body_bag/proc/label_cut(datum/act/op/A)
	name = "body bag"
	set_has_label(FALSE)
	return OP_OK

/obj/structure/closet/body_bag/store_mobs()
	contains_body = ..()
	return contains_body

/obj/structure/closet/body_bag/close()
	if(..())
		set_density(FALSE)
		return 1
	return 0

/// The bag is dragged onto the one dragging it.
/obj/structure/closet/body_bag/proc/dragged_onto_self(datum/act/op/A)
	return A.target == A.actor

/// The bag folds back into its item where it lay (a human only, and only while it is shut and empty). A cryo bag keeps its injector.
/obj/structure/closet/body_bag/proc/folded_up(datum/act/op/A)
	var/mob/user = A.actor
	if(!(in_range(src, user) || user.contents.Find(src)))
		return OP_OK
	if(!ishuman(user) || opened)
		return OP_OK
	if(contents_count(src) || has_latent()) // ALLOW(latent): latent entries checked
		return OP_OK
	act_message(user, src, others = "%U% folds up %T%")
	fold_into_item(new item_path(get_turf(src)))
	expire(0)
	return OP_OK

/// What the folded item takes from the bag it comes from (a stasis bag hands its injector on).
/obj/structure/closet/body_bag/proc/fold_into_item(obj/item/bodybag/folded)
	return folded

/obj/structure/closet/body_bag/relaymove(mob/user,direction)
	if(src.loc != get_turf(src))
		src.loc.relaymove(user,direction)
	else
		..()

/obj/structure/closet/body_bag/proc/get_occupants()
	var/list/occupants = list()
	for(var/mob/living/carbon/human/H in contents) // ALLOW(latent): mobs are never latent
		occupants += H
	return occupants

/obj/structure/closet/body_bag/proc/update(broadcast=0)
	if(istype(loc, /obj/structure/morgue))
		var/obj/structure/morgue/M = loc
		M.update(broadcast)

/// A body bag draws itself entirely: open or shut, with its label.
/obj/structure/closet/body_bag/closet_look(datum/look/look)
	look.state(opened ? "open" : "base")
	look.overlay("bodybag_label", when = has_label)

/obj/item/bodybag/cryobag
	name = "stasis bag"
	desc = "A non-reusable plastic bag designed to slow down bodily functions such as circulation and breathing, \
	especially useful if short on time or in a hostile environment."		// CHOMPEDIT : purdev (spelling fix)
	icon = 'icons/obj/closets/cryobag.dmi'
	icon_state = "bodybag_folded"
	item_state = "bodybag_cryo_folded"
	cryogenic = TRUE

/obj/structure/closet/body_bag/cryobag
	name = "stasis bag"
	desc = "A non-reusable plastic bag designed to slow down bodily functions such as circulation and breathing, \
	especially useful if short on time or in a hostile enviroment."
	icon = 'icons/obj/closets/cryobag.dmi'
	item_path = /obj/item/bodybag/cryobag
	store_misc = 0
	store_items = 0
	var/used = 0
	var/obj/item/tank/tank = null
	var/tank_type = /obj/item/tank/stasis/oxygen
	/// Stasis modifier (/datum/body_effect/stasis/*) applied to whoever lies inside.
	var/stasis_level = /datum/body_effect/stasis/deep
	var/obj/item/reagent_containers/syringe/syringe

TRACKED(/obj/structure/closet/body_bag/cryobag, used)

MSG_DEF_SELF(cryobag/has_injector, "It already has an injector! Remove it first.")
MSG_DEF_SELF(cryobag/no_injector, "It has no injector in it.")
MSG_DEF_SELF(cryobag/injector_stuck, "The injector cannot be removed now that the stasis bag has been used!")
MSG_DEF(cryobag/injector_in, "You insert %I% into %T%, and it locks into place.", "%U% inserts %I% into %T%.")
MSG_DEF(cryobag/injector_out, "You pry the injector out of %T%.", "%U% pries the injector out of %T%.")

// A stasis bag takes only people (the first one zips it up for good), keeps its own air, and has an injector slot for a syringe. A shut one is scanned through
// its skin (a health analyzer), takes a syringe with an item and gives it back to a screwdriver until somebody has been zipped in. Opening a used one asks first.
CAPABILITIES(/obj/structure/closet/body_bag/cryobag)
	owns_one(nameof(tank), /obj/item/tank)
	owns_one(nameof(syringe), /obj/item/reagent_containers/syringe)
	extend("door", when(cond_not(nameof(used))))
	op("door_used", inputs(hand(), menu()), answers(INTENT_USE), label("Toggle Open"), when(nameof(used)), when(req(PROC_REF(bare_hand_or_menu))),
		confirms("Are you sure you want to open it? It will expire upon opening it."),
		needs(req(PROC_REF(door_ready), because = MSG(closet/wont_budge))), then(PROC_REF(door_toggled)))
	op("scan", item(/obj/item/healthanalyzer), label("Scan"), when(cond_not(nameof(opened))), priority(OP_PRIORITY_PART), then(PROC_REF(analyser_used)))
	op("insert_injector", item(/obj/item/reagent_containers/syringe), label("Insert injector"), when(cond_not(nameof(opened))), priority(OP_PRIORITY_PART),
		needs(req(PROC_REF(can_insert_injector), because = PROC_REF(injector_refusal))), then(PROC_REF(injector_inserted)), says(MSG(cryobag/injector_in)))
	op("remove_injector", tool(TOOL_SCREWDRIVER), label("Remove injector"), when(cond_not(nameof(opened))), priority(OP_PRIORITY_PART), wait(0),
		needs(req(PROC_REF(injector_removable), because = PROC_REF(remove_refusal))), then(PROC_REF(injector_removed)), says(MSG(cryobag/injector_out)))

/obj/structure/closet/body_bag/cryobag/Initialize(mapload)
	rel_set(src, nameof(tank), new tank_type(null)) // ALLOW(decl): made in nullspace, not in src. It's in nullspace to prevent ejection when the bag is opened.
	..()

/obj/structure/closet/body_bag/cryobag/open()
	. = ..()
	if(used)
		replace_with(src, /obj/item/usedcryobag)

/// The stasis bag adds its indicator lamp.
/obj/structure/closet/body_bag/cryobag/closet_look(datum/look/look)
	..()
	look.overlay(look_overlay_image(icon, "indicator[opened]", color = COLOR_LIME, appearance_flags = RESET_COLOR))

/obj/structure/closet/body_bag/cryobag/fold_into_item(obj/item/bodybag/folded)
	if(syringe)
		rel_move(src, nameof(syringe), folded, nameof(folded.syringe))
	return folded

/obj/structure/closet/body_bag/cryobag/Entered(atom/movable/AM)
	if(isliving(AM))
		var/mob/living/L = AM
		L.set_stasis(stasis_level, src)
	if(ishuman(AM))
		var/mob/living/carbon/human/H = AM
		set_used(TRUE)
		inject_occupant(H)

	if(istype(AM, /obj/item/organ))
		var/obj/item/organ/O = AM
		O.preserved = 1
		for(var/obj/item/organ/organ in O)
			organ.preserved = 1
	..()

/obj/structure/closet/body_bag/cryobag/Exited(atom/movable/AM)
	if(isliving(AM))
		var/mob/living/L = AM
		L.set_stasis(null, src)

	if(istype(AM, /obj/item/organ))
		var/obj/item/organ/O = AM
		O.preserved = 0
		for(var/obj/item/organ/organ in O)
			organ.preserved = 0
	..()

/obj/structure/closet/body_bag/cryobag/return_air() //Used to make stasis bags protect from vacuum.
	if(tank)
		return tank.air_contents
	..()

/obj/structure/closet/body_bag/cryobag/proc/inject_occupant(mob/living/carbon/human/H)
	if(!syringe)
		return

	if(H.reagents)
		syringe.reagents.trans_to_mob(H, 30, CHEM_BLOOD)

/obj/structure/closet/body_bag/cryobag/examine(mob/user)
	. = ..()
	if(Adjacent(user)) //The bag's rather thick and opaque from a distance.
		. += span_info("You peer into \the [src].")
		if(syringe)
			. += span_info("It has a syringe added to it.")
		FOR_REAL_CONTENTS(var/mob/living/L, src)
			. += L.examine(user)

/// Loading an injector must respect its current holder's release rules, and the bag takes one.
/obj/structure/closet/body_bag/cryobag/proc/can_insert_injector(datum/act/op/A)
	if(syringe)
		return FALSE
	return isnull(A.held.loc?.release_refusal(A.held, A.actor)) // ALLOW(reads): where the injector is carried and whether that lets it go are read when it is put in

/obj/structure/closet/body_bag/cryobag/proc/injector_refusal(datum/act/op/A)
	if(syringe)
		return /datum/msg/cryobag/has_injector
	return A.held.loc?.release_refusal(A.held, A.actor) || /datum/msg/op/not_available

/// A shut stasis bag is scanned through its skin: every one inside is read by the analyzer.
/obj/structure/closet/body_bag/cryobag/proc/analyser_used(datum/act/op/A)
	var/obj/item/healthanalyzer/analyzer = A.held
	for(var/mob/living/L in contents) // ALLOW(latent): mobs are never latent
		analyzer.attack(L, A.actor)
	return OP_OK

/// The injector goes into the bag's slot, out of the hand, and into whoever is already zipped in.
/obj/structure/closet/body_bag/cryobag/proc/injector_inserted(datum/act/op/A)
	var/obj/item/reagent_containers/syringe/loaded = A.held
	if(!loaded.loc.release_to(loaded, get_turf(src), null, A.actor))
		return OP_REFUSED
	if(!own_move(loaded, src, nameof(src.syringe)))
		return OP_REFUSED
	loaded.moveToNullspace()
	for(var/mob/living/carbon/human/H in contents) // ALLOW(latent): mobs are never latent
		inject_occupant(H)
		break
	return OP_OK

/// There is an injector to take out, and the bag has not been used.
/obj/structure/closet/body_bag/cryobag/proc/injector_removable(datum/act/op/A)
	return !!syringe && !used

/obj/structure/closet/body_bag/cryobag/proc/remove_refusal(datum/act/op/A)
	return used ? /datum/msg/cryobag/injector_stuck : /datum/msg/cryobag/no_injector

/// The injector is pried out onto the floor.
/obj/structure/closet/body_bag/cryobag/proc/injector_removed(datum/act/op/A)
	syringe.forceMove(src.loc)
	rel_take(src, nameof(syringe))
	return OP_OK

/obj/item/usedcryobag
	name = "used stasis bag"
	desc = "Pretty useless now.."
	icon_state = "bodybag_used"
	icon = 'icons/obj/closets/cryobag.dmi'

// The injector is kept in nullspace (never ejected with the contents): owned (implicit OWN,
// deleted with the bag) by the folded bag or the unfolded cryobag, moved with own_transfer().
