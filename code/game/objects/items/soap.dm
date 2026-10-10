/obj/item/soap
	name = "soap"
	desc = "A cheap bar of soap. Doesn't smell."
	gender = PLURAL
	icon = 'icons/obj/soap.dmi'
	icon_state = "soap"
	flags = NOCONDUCT | NOBLUDGEON
	w_class = ITEMSIZE_SMALL
	slot_flags = SLOT_HOLSTER
	throwforce = 0
	throw_speed = 4
	throw_range = 20

	var/randomize = TRUE
	var/square_chance = 10
	var/cleanspeed = 35
	var/bites = 0


/// Rolled before init (rolls(), code/engine/lifeforms/rolls.dm): what the old Initialize() drew from the world RNG.
/obj/item/soap/proc/roll_icon_state(datum/roller/R)
	return randomize && R.chance(square_chance) ? "[icon_state]-alt" : icon_state

/obj/item/soap/proc/wet(cleaner = FALSE)
	if(cleaner)
		reagents.add_reagent(REAGENT_ID_CLEANER, 5)
	else
		reagents.add_reagent(REAGENT_ID_WATER, 5) //full of wet...

/obj/item/soap/Crossed(atom/movable/AM as mob|obj)
	if(AM.is_incorporeal())
		return
	if(isliving(AM))
		var/mob/living/M =	AM
		M.slip("\the [src.name]",3)

MSG_DEF_SELF(soap/bite_begin, span_warning("You raise the soap to your mouth and prepare to take a bite..."))
MSG_DEF(soap/scrub_begin, span_warning("You begin to scrub %T% out with %I%..."), "%U% begins to scrub %T% out with %I%.")
MSG_DEF(soap/clean_begin, span_notice("You begin to clean %T% with %I%..."), "%U% begins to clean %T% with %I%...")

/// Soap used on something close by: a bite of itself, a decal scrubbed out, a dry floor scrubbed, anything else cleaned.
CAPABILITIES(/obj/item/soap)
	reagents(5)
	rolls(nameof(icon_state), PROC_REF(roll_icon_state))
	op("bite", at_target(/mob/living/carbon/human), priority(OP_PRIORITY_PART + 3), answers(INTENT_USE, INTENT_ATTACK), label("Take a bite"), when(req(PROC_REF(bites_own_mouth))),
		begins(MSG(soap/bite_begin)), wait(0.5 SECONDS), then(PROC_REF(bite_done)))
	op("scrub_decal", at_target(/obj/effect/decal/cleanable), priority(OP_PRIORITY_PART + 2), answers(INTENT_USE, INTENT_ATTACK), label("Scrub out"), when(req(PROC_REF(plain_click))), needs(req_adjacent()),
		begins(MSG(soap/scrub_begin)), wait(PROC_REF(clean_time)), then(PROC_REF(scrub_decal_done)))
	op("scrub_floor", at_target(/turf), priority(OP_PRIORITY_PART + 1), answers(INTENT_USE, INTENT_ATTACK), label("Scrub the floor"), when(req(PROC_REF(plain_click))), when(req(PROC_REF(floor_is_dry))), needs(req_adjacent()),
		begins(MSG(soap/scrub_begin)), wait(PROC_REF(clean_time)), then(PROC_REF(scrub_floor_done)))
	op("clean", at_target(/atom), priority(OP_PRIORITY_PART), answers(INTENT_USE, INTENT_ATTACK), label("Clean"), when(req(PROC_REF(plain_click))), when(req(PROC_REF(not_decal_or_turf))), needs(req_adjacent()),
		begins(MSG(soap/clean_begin)), wait(PROC_REF(clean_time)), then(PROC_REF(clean_done)))

/// The click aims at a human's mouth.
/obj/item/soap/proc/mouth_aimed(datum/act/op/A)
	return ishuman(A.target) && read_once(A.actor.zone_sel?.selecting) == O_MOUTH

/obj/item/soap/proc/bites_own_mouth(datum/act/op/A)
	return mouth_aimed(A) && A.target == A.actor

/// A click that is neither the mouth nor something worn (what afterattack() says about those it answers itself).
/obj/item/soap/proc/plain_click(datum/act/op/A)
	if(mouth_aimed(A))
		return FALSE
	return !read_once(A.actor.client && (A.target in A.actor.client.screen))

/obj/item/soap/proc/floor_is_dry(datum/act/op/A)
	return !read_once(reagents.has_reagent(REAGENT_ID_WATER, 1) || reagents.has_reagent(REAGENT_ID_CLEANER, 1))

/obj/item/soap/proc/not_decal_or_turf(datum/act/op/A)
	return !istype(A.target, /obj/effect/decal/cleanable) && !isturf(A.target)

/obj/item/soap/proc/clean_time(datum/act/op/A)
	return cleanspeed

/obj/item/soap/afterattack(atom/target, mob/user as mob, proximity)
	. = ..()
	if(ishuman(target) && user.zone_sel.selecting == O_MOUTH)
		if(target != user)
			act_message(user, src, others = span_danger("%U% washes 	he [target]'s mouth out with %T%!"))
			//Add pieface cleaning here if that ever gets ported.
		user.setClickCooldown(DEFAULT_QUICK_COOLDOWN)
		return
	if(!proximity)
		return
	//I couldn't feasibly  fix the overlay bugs caused by cleaning items we are wearing.
	//So this is a workaround. This also makes more sense from an IC standpoint. ~Carn
	if(user.client && (target in user.client.screen))
		to_chat(user, span_warning("You need to take that [target] off before cleaning it."))
	else if(istype(target,/turf))
		if(reagents.has_reagent(REAGENT_ID_WATER, 1) || reagents.has_reagent(REAGENT_ID_CLEANER, 1)) //Instant floorcleaning with wetness
			act_message(user, src, MSG_SELF(span_notice("You effortlessly scrub 	he [target]")), MSG_OTHERS("%U% effortlessly scrubs 	he [target] out with wet [src]"))
			var/turf/T = target
			T.wash(CLEAN_SCRUB)
			reagents.trans_to_turf(T, 1, 10)
	return

/obj/item/soap/proc/bite_done(datum/act/op/A)
	var/mob/user = A.actor
	act_message(user, src, MSG_SELF(span_notice("You gnaw on %T%! This can't be good for you...")), MSG_OTHERS(span_notice("%U% takes a bite out of %T%!")))
	var/mob/living/carbon/C = user
	play_sfx(get_turf(C), SFX_ITEMS_EATFOOD, volume = 25, vary = FALSE)
	C.ingested.add_reagent(REAGENT_ID_TOXIN, 0.5) //normally formaldehyde, and 2 units of it. Toxin is being subsituted and is 4 times as toxic, hence a quarter of the normal amount.
	C.ingested.add_reagent(REAGENT_ID_CHLORALHYDRATE, 3)
	reagents.trans_to_holder(C.ingested, 1)
	bites++
	if(bites >= 5)
		consume(src, user)
	return OP_OK

/obj/item/soap/proc/scrub_decal_done(datum/act/op/A)
	var/atom/target = A.target
	A.actor.balloon_alert(A.actor, "you scrub 	he [target] out.")
	consumed(target, src)
	return OP_OK

/obj/item/soap/proc/scrub_floor_done(datum/act/op/A)
	var/turf/T = A.target
	A.actor.balloon_alert(A.actor, "you scrub 	he [T] clean.")
	T.wash(CLEAN_SCRUB)
	reagents.trans_to_turf(T, 1, 10)
	return OP_OK

/obj/item/soap/proc/clean_done(datum/act/op/A)
	var/atom/target = A.target
	target.wash(CLEAN_SCRUB)
	return OP_OK

/obj/item/soap/nanotrasen
	name = "Soap (Nanotrasen)"
	desc = ""
	icon_state = "soapnt"
	cleanspeed = 28 //janitor gets this

/obj/item/soap/nanotrasen/examine(mob/user)
	. = ..()
	if(prob(1)) // Mandela effect
		. += "A heavy duty bar of Nanotrasen brand soap. Smells of plasma, a years-old marketing gimmick."
	else
		. += "A heavy duty bar of Nanotrasen brand soap. Smells of phoron, a years-old marketing gimmick."

/obj/item/soap/homemade
	desc = "A homemade bar of soap. Smells of... well..."
	icon_state = "soapgibs"
	cleanspeed = 30 // faster to reward chemists for going to the effort
	randomize = FALSE //No square sprite for it.

/obj/item/soap/deluxe
	name = "Soap (Deluxe)"
	desc =  "A deluxe Waffle Co. brand bar of soap. Smells of high-class luxury."
	icon_state = "soapdeluxe"
	cleanspeed = 20 //captain gets one of these

/obj/item/soap/syndie
	name = "Soap (Syndicate)"
	desc = "An untrustworthy bar of soap made of strong chemical agents that dissolve blood faster. Smells of fear."
	icon_state = "soapsyndie"
	cleanspeed = 5 //faster than mop so it is useful for traitors who want to clean crime scenes

/obj/item/soap/space_soap
	name = "Soap (Space)"
	desc = "A space-like bar of soap. Smells like hot metal and walnuts."
	icon_state = "space_soap"

/obj/item/soap/water_soap
	name = "Soap (Pool)"
	desc = "A watery bar of soap. Smells like chlorine."
	icon_state = "water_soap"

/obj/item/soap/fire_soap
	name = "Soap (Fire)"
	desc = "A firey bar of soap. Smells like a campfire."
	icon_state = "fire_soap"

/obj/item/soap/rainbow_soap
	name = "Soap (Rainbow)"
	desc = "A rainbow bar of soap. Smells sickly sweet."
	icon_state = "rainbow_soap"

/obj/item/soap/diamond_soap
	name = "Soap (Diamond)"
	desc = "A diamond-like bar of soap. Smells like saffron and vanilla."
	icon_state = "diamond_soap"

/obj/item/soap/uranium_soap
	name = "Soap (Uranium)"
	desc = "An irradiated bar of soap. Smells not great... Not terrible."
	icon_state = "uranium_soap"

/obj/item/soap/silver_soap
	name = "Soap (Silver)"
	desc = "A silvery bar of soap. Smells like birch and amaranth."
	icon_state = "silver_soap"

/obj/item/soap/brown_soap
	name = "Soap (Brown)"
	desc = "A brown bar of soap. Smells like cinnamon and cognac."
	icon_state = "brown_soap"

/obj/item/soap/white_soap
	name = "Soap (White)"
	desc = "A white bar of soap. Smells like nutmeg and oats."
	icon_state = "white_soap"

/obj/item/soap/grey_soap
	name = "Soap (Grey)"
	desc = "A grey bar of soap. Smells like bergamot and lilies."
	icon_state = "grey_soap"

/obj/item/soap/pink_soap
	name = "Soap (Pink)"
	desc = "A pink bar of soap. Smells like bubblegum."
	icon_state = "pink_soap"

/obj/item/soap/purple_soap
	name = "Soap (Purple)"
	desc = "A purple bar of soap. Smells like lavender."
	icon_state = "purple_soap"

/obj/item/soap/blue_soap
	name = "Soap (Blue)"
	desc = "A blue bar of soap. Smells like cardamom."
	icon_state = "blue_soap"

/obj/item/soap/cyan_soap
	name = "Soap (Cyan)"
	desc = "A cyan bar of soap. Smells like bluebells and peaches."
	icon_state = "cyan_soap"

/obj/item/soap/green_soap
	name = "Soap (Green)"
	desc = "A green bar of soap. Smells like a freshly mowed lawn."
	icon_state = "green_soap"

/obj/item/soap/yellow_soap
	name = "Soap (Yellow)"
	desc = "A yellow bar of soap. Smells like citron and ginger."
	icon_state = "yellow_soap"

/obj/item/soap/orange_soap
	name = "Soap (Orange)"
	desc = "An orange bar of soap. Smells like oranges and dark chocolate."
	icon_state = "orange_soap"

/obj/item/soap/red_soap
	name = "Soap (Red)"
	desc = "A red bar of soap. Smells like cherries."
	icon_state = "red_soap"

/obj/item/soap/golden_soap
	name = "Soap (Gold)"
	desc = "A golden bar of soap. Smells like honey."
	icon_state = "golden_soap"
