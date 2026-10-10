#define MODKIT_HELMET 1
#define MODKIT_SUIT 2
#define MODKIT_FULL 3

/obj/item/modkit
	name = "hardsuit modification kit"
	desc = "A kit containing all the needed tools and parts to modify a hardsuit for another user."
	icon = 'icons/obj/device.dmi'
	icon_state = "modkit"
	var/parts = MODKIT_FULL
	var/target_species = SPECIES_HUMAN

	var/static/list/permitted_types = list(
		/obj/item/clothing/head/helmet/space/void,
		/obj/item/clothing/suit/space/void
		)
	pickup_sound = SFX_ITEMS_PICKUP_DEVICE
	drop_sound = SFX_ITEMS_DROP_DEVICE

TRACKED(/obj/item/modkit, parts)

CAPABILITIES(/obj/item/modkit)
	examine_line(PROC_REF(refit_description))
	op("refit", at_target(), priority(OP_PRIORITY_PART), answers(INTENT_USE, INTENT_ATTACK), label("Refit hardsuit"),
		when(PROC_REF(has_refit_parts)), needs(req_adjacent(), req(PROC_REF(refit_allowed))), then(PROC_REF(refitted)))
	op("discard_spent", at_target(), priority(OP_PRIORITY_PART), answers(INTENT_USE, INTENT_ATTACK), label("Discard spent kit"),
		when(cond_not(PROC_REF(has_refit_parts))), needs(req_adjacent()), then(PROC_REF(spent_discarded)))

/obj/item/modkit/proc/has_refit_parts(datum/act/op/A)
	return !!parts

/obj/item/modkit/proc/refit_allowed(datum/act/op/A)
	if(!target_species)
		return "This kit has no target species."
	if(!istype(A.target, /obj/item/clothing))
		return span_notice("[src] is unable to modify that.")
	var/obj/item/clothing/I = A.target
	var/allowed = FALSE
	for(var/permitted_type in permitted_types)
		if(istype(I, permitted_type))
			allowed = TRUE
			break
	if(!allowed)
		return span_notice("[src] is unable to modify that.")
	if((istype(I, /obj/item/clothing/head/helmet) && !(parts & MODKIT_HELMET)) || (istype(I, /obj/item/clothing/suit) && !(parts & MODKIT_SUIT)))
		return span_warning("This kit has no parts for this modification left.")
	var/list/bodytypes = dq_fit_bodytypes(I)
	var/excluding = ("exclude" in bodytypes)
	var/in_list = (target_species in bodytypes)
	if(excluding ^ in_list)
		return span_notice("[I] is already modified.")
	if(!isturf(I.loc)) // ALLOW(reads): native target location is rechecked immediately before this instant refit with no wait or prompt
		return span_warning("[I] must be safely placed on the ground for modification.")
	return null

/// All eligibility checks run before refitting changes the original target or spends kit parts.
/obj/item/modkit/proc/refitted(datum/act/op/A)
	var/obj/item/clothing/O = A.target
	if(O.usesound)
		play_sfx(src, O.usesound, volume = 100, vary = TRUE)
	act_message(A.actor, src, MSG_SELF(span_notice("You open %T% and modify \the [O].")), MSG_OTHERS(span_infoplain(span_bold("%U%") + " opens %T% and modifies \the [O].")))
	O.refit_for_species(target_species)
	if(istype(O, /obj/item/clothing/head/helmet))
		set_parts(parts & ~MODKIT_HELMET)
	if(istype(O, /obj/item/clothing/suit))
		set_parts(parts & ~MODKIT_SUIT)
	if(!parts)
		consume(src, A.actor)
	return OP_OK

/obj/item/modkit/proc/spent_discarded(datum/act/op/A)
	to_chat(A.actor, span_warning("This kit has no parts for this modification left."))
	return consume(src, A.actor) ? OP_OK : OP_REFUSED

/obj/item/modkit/proc/refit_description(datum/act/A)
	return "It looks as though it modifies hardsuits to fit [target_species] users."

#undef MODKIT_HELMET
#undef MODKIT_SUIT
#undef MODKIT_FULL

/obj/item/modkit/tajaran
	name = "tajaran hardsuit modification kit"
	desc = "A kit containing all the needed tools and parts to modify a hardsuit for another user. This one looks like it's meant for Tajaran."
	target_species = SPECIES_TAJARAN
