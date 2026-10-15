//This file was auto-corrected by findeclaration.exe on 25.5.2012 20:42:32

/obj/item/implantcase
	name = "glass case"
	desc = "A case containing an implant."
	icon = 'icons/obj/items.dmi'
	icon_state = "implantcase-0"
	item_state = "implantcase"
	throw_speed = 1
	throw_range = 5
	w_class = ITEMSIZE_TINY
	var/obj/item/implant/imp = null

/obj/item/implantcase/proc/update()
	if (imp)
		set_icon_state(text("implantcase-[]", imp.implant_color))
	else
		set_icon_state("implantcase-0")
	return

/// Labelling a case with a pen. Re-checked on the answer: the pen is still in hand, the case still in reach.
/obj/item/implantcase/proc/label_in_reach(datum/request/R)
	var/mob/M = R.answerer
	return in_range(src, M) || loc == M

/obj/item/implantcase/proc/label_entered(datum/act/request/A)
	if(!A.answer)
		return
	var/t = sanitizeSafe(A.answer.value, MAX_NAME_LEN)
	if(t)
		name = text("Glass Case - '[]'", t)
	else
		name = "Glass Case"

CAPABILITIES(/obj/item/implantcase)
	op("label", item(/obj/item/pen), passes(), label("Label"), then(PROC_REF(label_asked)))
	op("fill_from_syringe", item(/obj/item/reagent_containers/syringe), passes(), label("Fill"), then(PROC_REF(syringe_used)))
	op("swap_implant", item(/obj/item/implanter), passes(), label("Swap implant"), then(PROC_REF(implanter_used)))
	owns_one(nameof(imp), on_destroy = ON_DESTROY_CONTAINED)

/// A pen labels the case.
/obj/item/implantcase/proc/label_asked(datum/act/op/A)
	var/mob/user = A.actor
	open_request(src, /datum/prompt/text, PROC_REF(label_entered), answerer = user, title = "[name]", question = "What would you like the label to be?", max_len = MAX_NAME_LEN, name_text = TRUE, ask_flags = ASK_HELD | ASK_CAPABLE, subject = A.held, valid = PROC_REF(label_in_reach), timeout = 0)
	return OP_OK

/// A syringe fills a reagent implant in the case.
/obj/item/implantcase/proc/syringe_used(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/I = A.held
	if(!imp)
		return OP_OK
	if(!imp.allow_reagents)
		return OP_OK
	if(imp.reagents.total_volume >= imp.reagents.maximum_volume)
		to_chat(user, span_warning("\The [src] is full."))
	else
		after(src, 0.5 SECONDS, PROC_REF(inject_from), with = list(I, user))
	return OP_OK

/// An implanter and the case trade their implants.
/obj/item/implantcase/proc/implanter_used(datum/act/op/A)
	var/obj/item/implanter/M = A.held
	if (M.imp)
		if ((imp || M.imp.implanted))
			return OP_OK
		M.imp.forceMove(src)
		rel_move(M, nameof(M.imp), src, nameof(imp))
		update()
		M.update()
	else
		if (imp)
			imp.forceMove(M)
			rel_move(src, nameof(imp), M, nameof(M.imp))
			update()
		M.update()
	return OP_OK


/obj/item/implantcase/tracking
	name = "glass case - 'tracking'"
	desc = "A case containing a tracking implant."
	icon_state = "implantcase-b"

CAPABILITIES(/obj/item/implantcase/tracking)
	owns_one(nameof(imp), starts = /obj/item/implant/tracking, on_destroy = ON_DESTROY_CONTAINED)


/obj/item/implantcase/explosive
	name = "glass case - 'explosive'"
	desc = "A case containing an explosive implant."
	icon_state = "implantcase-r"

CAPABILITIES(/obj/item/implantcase/explosive)
	owns_one(nameof(imp), starts = /obj/item/implant/explosive, on_destroy = ON_DESTROY_CONTAINED)


/obj/item/implantcase/chem
	name = "glass case - 'chem'"
	desc = "A case containing a chemical implant."
	icon_state = "implantcase-b"

CAPABILITIES(/obj/item/implantcase/chem)
	owns_one(nameof(imp), starts = /obj/item/implant/chem, on_destroy = ON_DESTROY_CONTAINED)


/obj/item/implantcase/loyalty
	name = "glass case - 'loyalty'"
	desc = "A case containing a loyalty implant."
	icon_state = "implantcase-r"

CAPABILITIES(/obj/item/implantcase/loyalty)
	owns_one(nameof(imp), starts = /obj/item/implant/loyalty, on_destroy = ON_DESTROY_CONTAINED)


/obj/item/implantcase/death_alarm
	name = "glass case - 'death alarm'"
	desc = "A case containing a death alarm implant."
	icon_state = "implantcase-b"

CAPABILITIES(/obj/item/implantcase/death_alarm)
	owns_one(nameof(imp), starts = /obj/item/implant/death_alarm, on_destroy = ON_DESTROY_CONTAINED)


/obj/item/implantcase/freedom
	name = "glass case - 'freedom'"
	desc = "A case containing a freedom implant."
	icon_state = "implantcase-r"

CAPABILITIES(/obj/item/implantcase/freedom)
	owns_one(nameof(imp), starts = /obj/item/implant/freedom, on_destroy = ON_DESTROY_CONTAINED)


/obj/item/implantcase/adrenalin
	name = "glass case - 'adrenalin'"
	desc = "A case containing an adrenalin implant."
	icon_state = "implantcase-b"

CAPABILITIES(/obj/item/implantcase/adrenalin)
	owns_one(nameof(imp), starts = /obj/item/implant/adrenalin, on_destroy = ON_DESTROY_CONTAINED)


/obj/item/implantcase/dexplosive
	name = "glass case - 'explosive'"
	desc = "A case containing an explosive."
	icon_state = "implantcase-r"

CAPABILITIES(/obj/item/implantcase/dexplosive)
	owns_one(nameof(imp), starts = /obj/item/implant/dexplosive, on_destroy = ON_DESTROY_CONTAINED)


/obj/item/implantcase/health
	name = "glass case - 'health'"
	desc = "A case containing a health tracking implant."
	icon_state = "implantcase-b"

CAPABILITIES(/obj/item/implantcase/health)
	owns_one(nameof(imp), starts = /obj/item/implant/health, on_destroy = ON_DESTROY_CONTAINED)

/obj/item/implantcase/language
	name = "glass case - 'GalCom'"
	desc = "A case containing a GalCom language implant."
	icon_state = "implantcase-b"

CAPABILITIES(/obj/item/implantcase/language)
	owns_one(nameof(imp), starts = /obj/item/implant/language, on_destroy = ON_DESTROY_CONTAINED)

/obj/item/implantcase/language/eal
	name = "glass case - 'EAL'"
	desc = "A case containing an Encoded Audio Language implant."
	icon_state = "implantcase-b"

CAPABILITIES(/obj/item/implantcase/language/eal)
	owns_one(nameof(imp), starts = /obj/item/implant/language/eal, on_destroy = ON_DESTROY_CONTAINED)

/obj/item/implantcase/shades
	name = "glass case - 'Integrated Shades'"
	desc = "A case containing a nanite fabricator implant."
	icon_state = "implantcase-b"

CAPABILITIES(/obj/item/implantcase/shades)
	owns_one(nameof(imp), starts = /obj/item/implant/organ, on_destroy = ON_DESTROY_CONTAINED)

/obj/item/implantcase/taser
	name = "glass case - 'Taser'"
	desc = "A case containing a nanite fabricator implant."
	icon_state = "implantcase-b"

CAPABILITIES(/obj/item/implantcase/taser)
	owns_one(nameof(imp), starts = /obj/item/implant/organ/limbaugment, on_destroy = ON_DESTROY_CONTAINED)

/obj/item/implantcase/laser
	name = "glass case - 'Laser'"
	desc = "A case containing a nanite fabricator implant."
	icon_state = "implantcase-b"

CAPABILITIES(/obj/item/implantcase/laser)
	owns_one(nameof(imp), starts = /obj/item/implant/organ/limbaugment/laser, on_destroy = ON_DESTROY_CONTAINED)

/obj/item/implantcase/dart
	name = "glass case - 'Dart'"
	desc = "A case containing a nanite fabricator implant."
	icon_state = "implantcase-b"

CAPABILITIES(/obj/item/implantcase/dart)
	owns_one(nameof(imp), starts = /obj/item/implant/organ/limbaugment/dart, on_destroy = ON_DESTROY_CONTAINED)

/obj/item/implantcase/toolkit
	name = "glass case - 'Toolkit'"
	desc = "A case containing a nanite fabricator implant."
	icon_state = "implantcase-b"

CAPABILITIES(/obj/item/implantcase/toolkit)
	owns_one(nameof(imp), starts = /obj/item/implant/organ/limbaugment/upperarm, on_destroy = ON_DESTROY_CONTAINED)

/obj/item/implantcase/medkit
	name = "glass case - 'Toolkit'"
	desc = "A case containing a nanite fabricator implant."
	icon_state = "implantcase-b"

CAPABILITIES(/obj/item/implantcase/medkit)
	owns_one(nameof(imp), starts = /obj/item/implant/organ/limbaugment/upperarm/medkit, on_destroy = ON_DESTROY_CONTAINED)

/obj/item/implantcase/surge
	name = "glass case - 'Muscle Overclocker'"
	desc = "A case containing a nanite fabricator implant."
	icon_state = "implantcase-b"

CAPABILITIES(/obj/item/implantcase/surge)
	owns_one(nameof(imp), starts = /obj/item/implant/organ/limbaugment/upperarm/surge, on_destroy = ON_DESTROY_CONTAINED)

/obj/item/implantcase/analyzer
	name = "glass case - 'Scanner'"
	desc = "A case containing a nanite fabricator implant."
	icon_state = "implantcase-b"

CAPABILITIES(/obj/item/implantcase/analyzer)
	owns_one(nameof(imp), starts = /obj/item/implant/organ/limbaugment/wrist, on_destroy = ON_DESTROY_CONTAINED)

/obj/item/implantcase/sword
	name = "glass case - 'Scanner'"
	desc = "A case containing a nanite fabricator implant."
	icon_state = "implantcase-b"

CAPABILITIES(/obj/item/implantcase/sword)
	owns_one(nameof(imp), starts = /obj/item/implant/organ/limbaugment/wrist/sword, on_destroy = ON_DESTROY_CONTAINED)

/obj/item/implantcase/sprinter
	name = "glass case - 'Sprinter'"
	desc = "A case containing a nanite fabricator implant."
	icon_state = "implantcase-b"

CAPABILITIES(/obj/item/implantcase/sprinter)
	owns_one(nameof(imp), starts = /obj/item/implant/organ/pelvic/sprint, on_destroy = ON_DESTROY_CONTAINED)

/obj/item/implantcase/med_scanner
	name = "glass case - 'Scanner'"
	desc = "A case containing a nanite fabricator implant."
	icon_state = "implantcase-b"

CAPABILITIES(/obj/item/implantcase/med_scanner)
	owns_one(nameof(imp), starts = /obj/item/implant/organ/pelvic/scanner, on_destroy = ON_DESTROY_CONTAINED)

/obj/item/implantcase/armblade
	name = "glass case - 'Armblade'"
	desc = "A case containing a nanite fabricator implant."
	icon_state = "implantcase-b"

CAPABILITIES(/obj/item/implantcase/armblade)
	owns_one(nameof(imp), starts = /obj/item/implant/organ/limbaugment/upperarm/blade, on_destroy = ON_DESTROY_CONTAINED)

/obj/item/implantcase/handblade
	name = "glass case - 'Handblade'"
	desc = "A case containing a nanite fabricator implant."
	icon_state = "implantcase-b"

CAPABILITIES(/obj/item/implantcase/handblade)
	owns_one(nameof(imp), starts = /obj/item/implant/organ/limbaugment/wrist/blade, on_destroy = ON_DESTROY_CONTAINED)

/obj/item/implantcase/restrainingbolt
	name = "glass case - 'Restraining Bolt'"
	desc = "A case containing a restraining bolt."
	icon_state = "implantcase-b"

CAPABILITIES(/obj/item/implantcase/restrainingbolt)
	owns_one(nameof(imp), starts = /obj/item/implant/restrainingbolt, on_destroy = ON_DESTROY_CONTAINED)


/obj/item/implantcase/vrlanguage
	name = "glass case - 'language'"
	desc = "A case containing a language implant."
	icon_state = "implantcase-r"

CAPABILITIES(/obj/item/implantcase/vrlanguage)
	owns_one(nameof(imp), starts = /obj/item/implant/vrlanguage, on_destroy = ON_DESTROY_CONTAINED)

/obj/item/implantcase/proc/inject_from(obj/item/reagent_containers/syringe/I, mob/user)
	if(QDELETED(I))
		return
	I.reagents.trans_to_obj(imp, 5)
	to_chat(user, span_notice("You inject 5 units of the solution. The syringe now contains [I.reagents.total_volume] units."))

