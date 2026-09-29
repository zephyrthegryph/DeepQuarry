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
		icon_state = text("implantcase-[]", imp.implant_color)
	else
		icon_state = "implantcase-0"
	return

/// Labelling a case with a pen. Re-checked on the answer: the pen is still in hand, the case still in reach.
/datum/om/prompt/text/implantcase_label
	message = "What would you like the label to be?"
	max_length = MAX_NAME_LEN
	ask_flags = ASK_HELD | ASK_CAPABLE
	var/obj/item/implantcase/case

/datum/om/prompt/text/implantcase_label/valid()
	if(!in_range(case, answerer) && case.loc != answerer)
		return "too far away"
	return null

/obj/item/implantcase/proc/label_entered(datum/om/prompt/text/implantcase_label/ask)
	var/t = sanitizeSafe(ask.text, MAX_NAME_LEN)
	if(t)
		name = text("Glass Case - '[]'", t)
	else
		name = "Glass Case"

DECLARE_INTERACTIONS(/obj/item/implantcase, INTERACT_ITEM(null, PROC_REF(interaction_item)))

/// Old attackby.
/obj/item/implantcase/proc/interaction_item(mob/user, obj/item/I, datum/interaction/interaction)
	if (istype(I, /obj/item/pen))
		om_ask(user, /datum/om/prompt/text/implantcase_label, PROC_REF(label_entered), title = "[name]", subject = I, case = src)
	else if(istype(I, /obj/item/reagent_containers/syringe))
		if(!imp)	return INTERACTION_HANDLED_PASS
		if(!imp.allow_reagents)	return INTERACTION_HANDLED_PASS
		if(imp.reagents.total_volume >= imp.reagents.maximum_volume)
			to_chat(user, span_warning("\The [src] is full."))
		else
			om_after(src, 5, PROC_REF(inject_from), I, user)
	else if (istype(I, /obj/item/implanter))
		var/obj/item/implanter/M = I
		if (M.imp)
			if ((imp || M.imp.implanted))
				return INTERACTION_HANDLED_PASS
			M.imp.forceMove(src)
			imp = M.imp
			M.imp = null
			update()
			M.update()
		else
			if (imp)
				imp.forceMove(M)
				M.imp = imp
				imp = null
				update()
			M.update()
	return INTERACTION_HANDLED_PASS


/obj/item/implantcase/tracking
	name = "glass case - 'tracking'"
	desc = "A case containing a tracking implant."
	icon_state = "implantcase-b"

DECLARE_DEFAULT_CHILD(/obj/item/implantcase/tracking, "imp", /obj/item/implant/tracking)


/obj/item/implantcase/explosive
	name = "glass case - 'explosive'"
	desc = "A case containing an explosive implant."
	icon_state = "implantcase-r"

DECLARE_DEFAULT_CHILD(/obj/item/implantcase/explosive, "imp", /obj/item/implant/explosive)


/obj/item/implantcase/chem
	name = "glass case - 'chem'"
	desc = "A case containing a chemical implant."
	icon_state = "implantcase-b"

DECLARE_DEFAULT_CHILD(/obj/item/implantcase/chem, "imp", /obj/item/implant/chem)


/obj/item/implantcase/loyalty
	name = "glass case - 'loyalty'"
	desc = "A case containing a loyalty implant."
	icon_state = "implantcase-r"

DECLARE_DEFAULT_CHILD(/obj/item/implantcase/loyalty, "imp", /obj/item/implant/loyalty)


/obj/item/implantcase/death_alarm
	name = "glass case - 'death alarm'"
	desc = "A case containing a death alarm implant."
	icon_state = "implantcase-b"

DECLARE_DEFAULT_CHILD(/obj/item/implantcase/death_alarm, "imp", /obj/item/implant/death_alarm)


/obj/item/implantcase/freedom
	name = "glass case - 'freedom'"
	desc = "A case containing a freedom implant."
	icon_state = "implantcase-r"

DECLARE_DEFAULT_CHILD(/obj/item/implantcase/freedom, "imp", /obj/item/implant/freedom)


/obj/item/implantcase/adrenalin
	name = "glass case - 'adrenalin'"
	desc = "A case containing an adrenalin implant."
	icon_state = "implantcase-b"

DECLARE_DEFAULT_CHILD(/obj/item/implantcase/adrenalin, "imp", /obj/item/implant/adrenalin)


/obj/item/implantcase/dexplosive
	name = "glass case - 'explosive'"
	desc = "A case containing an explosive."
	icon_state = "implantcase-r"

DECLARE_DEFAULT_CHILD(/obj/item/implantcase/dexplosive, "imp", /obj/item/implant/dexplosive)


/obj/item/implantcase/health
	name = "glass case - 'health'"
	desc = "A case containing a health tracking implant."
	icon_state = "implantcase-b"

DECLARE_DEFAULT_CHILD(/obj/item/implantcase/health, "imp", /obj/item/implant/health)

/obj/item/implantcase/language
	name = "glass case - 'GalCom'"
	desc = "A case containing a GalCom language implant."
	icon_state = "implantcase-b"

DECLARE_DEFAULT_CHILD(/obj/item/implantcase/language, "imp", /obj/item/implant/language)

/obj/item/implantcase/language/eal
	name = "glass case - 'EAL'"
	desc = "A case containing an Encoded Audio Language implant."
	icon_state = "implantcase-b"

DECLARE_DEFAULT_CHILD(/obj/item/implantcase/language/eal, "imp", /obj/item/implant/language/eal)

/obj/item/implantcase/shades
	name = "glass case - 'Integrated Shades'"
	desc = "A case containing a nanite fabricator implant."
	icon_state = "implantcase-b"

DECLARE_DEFAULT_CHILD(/obj/item/implantcase/shades, "imp", /obj/item/implant/organ)

/obj/item/implantcase/taser
	name = "glass case - 'Taser'"
	desc = "A case containing a nanite fabricator implant."
	icon_state = "implantcase-b"

DECLARE_DEFAULT_CHILD(/obj/item/implantcase/taser, "imp", /obj/item/implant/organ/limbaugment)

/obj/item/implantcase/laser
	name = "glass case - 'Laser'"
	desc = "A case containing a nanite fabricator implant."
	icon_state = "implantcase-b"

DECLARE_DEFAULT_CHILD(/obj/item/implantcase/laser, "imp", /obj/item/implant/organ/limbaugment/laser)

/obj/item/implantcase/dart
	name = "glass case - 'Dart'"
	desc = "A case containing a nanite fabricator implant."
	icon_state = "implantcase-b"

DECLARE_DEFAULT_CHILD(/obj/item/implantcase/dart, "imp", /obj/item/implant/organ/limbaugment/dart)

/obj/item/implantcase/toolkit
	name = "glass case - 'Toolkit'"
	desc = "A case containing a nanite fabricator implant."
	icon_state = "implantcase-b"

DECLARE_DEFAULT_CHILD(/obj/item/implantcase/toolkit, "imp", /obj/item/implant/organ/limbaugment/upperarm)

/obj/item/implantcase/medkit
	name = "glass case - 'Toolkit'"
	desc = "A case containing a nanite fabricator implant."
	icon_state = "implantcase-b"

DECLARE_DEFAULT_CHILD(/obj/item/implantcase/medkit, "imp", /obj/item/implant/organ/limbaugment/upperarm/medkit)

/obj/item/implantcase/surge
	name = "glass case - 'Muscle Overclocker'"
	desc = "A case containing a nanite fabricator implant."
	icon_state = "implantcase-b"

DECLARE_DEFAULT_CHILD(/obj/item/implantcase/surge, "imp", /obj/item/implant/organ/limbaugment/upperarm/surge)

/obj/item/implantcase/analyzer
	name = "glass case - 'Scanner'"
	desc = "A case containing a nanite fabricator implant."
	icon_state = "implantcase-b"

DECLARE_DEFAULT_CHILD(/obj/item/implantcase/analyzer, "imp", /obj/item/implant/organ/limbaugment/wrist)

/obj/item/implantcase/sword
	name = "glass case - 'Scanner'"
	desc = "A case containing a nanite fabricator implant."
	icon_state = "implantcase-b"

DECLARE_DEFAULT_CHILD(/obj/item/implantcase/sword, "imp", /obj/item/implant/organ/limbaugment/wrist/sword)

/obj/item/implantcase/sprinter
	name = "glass case - 'Sprinter'"
	desc = "A case containing a nanite fabricator implant."
	icon_state = "implantcase-b"

DECLARE_DEFAULT_CHILD(/obj/item/implantcase/sprinter, "imp", /obj/item/implant/organ/pelvic/sprint)

/obj/item/implantcase/med_scanner
	name = "glass case - 'Scanner'"
	desc = "A case containing a nanite fabricator implant."
	icon_state = "implantcase-b"

DECLARE_DEFAULT_CHILD(/obj/item/implantcase/med_scanner, "imp", /obj/item/implant/organ/pelvic/scanner)

/obj/item/implantcase/armblade
	name = "glass case - 'Armblade'"
	desc = "A case containing a nanite fabricator implant."
	icon_state = "implantcase-b"

DECLARE_DEFAULT_CHILD(/obj/item/implantcase/armblade, "imp", /obj/item/implant/organ/limbaugment/upperarm/blade)

/obj/item/implantcase/handblade
	name = "glass case - 'Handblade'"
	desc = "A case containing a nanite fabricator implant."
	icon_state = "implantcase-b"

DECLARE_DEFAULT_CHILD(/obj/item/implantcase/handblade, "imp", /obj/item/implant/organ/limbaugment/wrist/blade)

/obj/item/implantcase/restrainingbolt
	name = "glass case - 'Restraining Bolt'"
	desc = "A case containing a restraining bolt."
	icon_state = "implantcase-b"

DECLARE_DEFAULT_CHILD(/obj/item/implantcase/restrainingbolt, "imp", /obj/item/implant/restrainingbolt)


/obj/item/implantcase/vrlanguage
	name = "glass case - 'language'"
	desc = "A case containing a language implant."
	icon_state = "implantcase-r"

DECLARE_DEFAULT_CHILD(/obj/item/implantcase/vrlanguage, "imp", /obj/item/implant/vrlanguage)

/obj/item/implantcase/proc/inject_from(obj/item/reagent_containers/syringe/I, mob/user)
	I.reagents.trans_to_obj(imp, 5)
	to_chat(user, span_notice("You inject 5 units of the solution. The syringe now contains [I.reagents.total_volume] units."))

OWN(/obj/item/implantcase, imp, OWN_CONTAINED)
