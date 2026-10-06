/obj/item/implant
	name = "implant"
	icon = 'icons/obj/device.dmi'
	icon_state = "implant"
	w_class = ITEMSIZE_TINY
	show_messages = TRUE

	var/implanted = null
	var/mob/imp_in
	var/obj/item/organ/external/part = null
	var/implant_color = "b"
	var/allow_reagents = 0
	var/malfunction = 0
	var/initialize_loc = BP_TORSO
	var/known_implant = FALSE
	pickup_sound = SFX_ITEMS_PICKUP_DEVICE
	drop_sound = SFX_ITEMS_DROP_DEVICE

/// The implant site slot is keyed by implant type (organ_external.dm): at
/// most one implant of a given kind per organ.
/obj/item/implant/slot_key()
	return type

/// Self-initiated emotes pass the host as actor; involuntary emotes pass null.
/obj/item/implant/proc/trigger(emote, source as mob, mob/actor)
	return

/obj/item/implant/proc/activate()
	return

// Moves the implant where it needs to go, and tells it if there's more to be done in post_implant
/obj/item/implant/proc/handle_implant(mob/source, target_zone = BP_TORSO)
	. = TRUE
	implanted = TRUE
	var/obj/item/organ/external/affected
	if(ishuman(source))
		var/mob/living/carbon/human/H = source
		affected = H.get_organ(target_zone)
	if(affected)
		// The implant site slot (organ_external.dm, OM relations step 2) is
		// the implanted_in relation: this move sets part/imp_in and the
		// organ's implants membership, same as the physical placement.
		move_into(affected, ORGAN_SLOT_IMPLANTS, src)
	else
		// No organ to embed in (a non-human host, or no matching limb):
		// imp_in has no relation to keep it in sync with, since there's no
		// reverse list on a bare mob the way an organ's `implants` is one.
		rel_set(src, nameof(imp_in), source)
		forceMove(source)

	registry_join(REGISTRY_LISTENING_OBJECTS, src)

// Takes place after handle_implant, if that returns TRUE
/obj/item/implant/proc/post_implant(mob/source, mob/user = null)

/obj/item/implant/proc/get_data()
	return "No information available"

/obj/item/implant/proc/hear(message, source as mob)
	return

/obj/item/implant/proc/islegal()
	return 0

/obj/item/implant/proc/meltdown()	//breaks it down, making implant unrecongizible
	to_chat(imp_in(), span_warning("You feel something melting inside [part ? "your [part.name]" : "you"]!"))
	var/mob/living/M = imp_in()
	M?.injure(INJURY_BURN, 15, part, src)
	name = "melted implant"
	desc = "Charred circuit in melted plastic case. Wonder what that used to be..."
	icon_state = "implant_melted"
	malfunction = MALFUNCTION_PERMANENT

/obj/item/implant/proc/implant_loadout(mob/living/carbon/human/H)
	. = istype(H) && handle_implant(H, initialize_loc)
	if(.)
		invisibility = initial(invisibility)
		known_implant = TRUE
		post_implant(H)

CAPABILITIES(/obj/item/implant)
	op("load_implanter", item(/obj/item/implanter), passes(), label("Load implanter"), then(PROC_REF(load_implanter)))

/// An implanter takes the implant (when it is empty); the click goes on.
/obj/item/implant/proc/load_implanter(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/implanter/implanter = A.held
	if(implanter.imp)
		return OP_OK
	if(!move_into(implanter, nameof(implanter.imp), src, user))
		return OP_OK
	implanter.update()
	return OP_OK

//////////////////////////////
//	Tracking Implant
//////////////////////////////
REGISTRY_MEMBERSHIP(/obj/item/implant/tracking, REGISTRY_TRACKING_IMPLANTS)

/obj/item/implant/tracking
	name = "tracking implant"
	desc = "An implant normally given to dangerous criminals. Allows security to track your location."
	known_implant = TRUE
	var/id = 1
	var/degrade_time = 10 MINUTES	//How long before the implant stops working outside of a living body.

/obj/item/implant/tracking/weak	//This is for the loadout
	degrade_time = 2.5 MINUTES

/// Watches its host every 2 s from implantation until it melts down.
/obj/item/implant/tracking/var/tracking_active = FALSE
TRACKED(/obj/item/implant/tracking, tracking_active)
CAPABILITIES(/obj/item/implant/tracking)
	every(2 SECONDS, then(PROC_REF(tracking_step)), when = nameof(tracking_active))
	extend(/datum/act/hit/emp, instead(then(PROC_REF(tracking_implant_emp))))
	rolls(nameof(id), range_of(1, 1000))

/obj/item/implant/tracking/post_implant(mob/source)
	set_tracking_active(TRUE)

// leaves its limb's implant list.

/obj/item/implant/tracking/proc/tracking_step(datum/act/timer/A)
	var/mob/living/implant_mob // Get implant's mob from our host organ
	if(istype(loc, /obj/item/organ))
		var/obj/item/organ/O = loc
		implant_mob = O.owner

	if(ismob(implant_mob) && implant_mob.stat == DEAD)
		if(ELAPSED(implant_mob, timeofdeath, CLOCK_WORLD) >= degrade_time)
			name = "melted implant"
			desc = "Charred circuit in melted plastic case. Wonder what that used to be..."
			icon_state = "implant_melted"
			malfunction = MALFUNCTION_PERMANENT
			set_tracking_active(FALSE)
	return 1

/obj/item/implant/tracking/get_data()
	var/dat = {""} +span_bold("Implant Specifications:") + {"<BR>
"} + span_bold("Name:") + {"Tracking Beacon<BR>
"} + span_bold("Life:") + {"10 minutes after death of host<BR>
"} + span_bold("Important Notes:") + {"None<BR>
<HR>
"} + span_bold("Implant Details:") + {"<BR>
"} + span_bold("Function:") + {"Continuously transmits low power signal. Useful for tracking.<BR>
"} + span_bold("Special Features:") + {"<BR>
"} + span_italics("Neuro-Safe") + {"- Specialized shell absorbs excess voltages self-destructing the chip if
a malfunction occurs thereby securing safety of subject. The implant will melt and
disintegrate into bio-safe elements.<BR>
"} + span_bold("Integrity:") + {"Gradient creates slight risk of being overcharged and frying the
circuitry. As a result neurotoxins can cause massive damage.<HR>
Implant Specifics:<BR>"}
	return dat

/// An EMP makes the tracker malfunction for a while, maybe melting it down.
/obj/item/implant/tracking/proc/tracking_implant_emp(datum/act/hit/emp/A)
	var/datum/damage_packet/packet = A.packet
	if(malfunction) //no, dawg, you can't malfunction while you are malfunctioning
		return HOOK_DECLINE
	malfunction = MALFUNCTION_TEMPORARY

	var/delay = 20
	switch(packet.severity)
		if(1)
			if(prob(60))
				meltdown()
		if(2)
			delay = rand(5*60*10,15*60*10)	//from 5 to 15 minutes of free time
		if(3)
			delay = rand(2*60*10,5*60*10)	//from 2 to 5 minutes of free time
		if(4)
			delay = rand(0.5*60*10,1*60*10)	//from .5 to 1 minutes of free time

	after(src, delay, PROC_REF(malfunction_recover))
	return HOOK_DECLINE

//////////////////////////////
//	Death Explosive Implant
//////////////////////////////
/obj/item/implant/dexplosive
	name = "explosive"
	desc = "And boom goes the weasel."
	icon_state = "implant_evil"

/obj/item/implant/dexplosive/get_data()
	var/dat = {"
"} + span_bold("Implant Specifications:") + {"<BR>
"} + span_bold("Name:") + {"Robust Corp RX-78 Employee Management Implant<BR>
"} + span_bold("Life:") + {"Activates upon death.<BR>
"} + span_bold("Important Notes:") + {"Explodes<BR>
<HR>
"} + span_bold("Implant Details:") + {"<BR>
"} + span_bold("Function:") + {"Contains a compact, electrically detonated explosive that detonates upon receiving a specially encoded signal or upon host death.<BR>
"} + span_bold("Special Features:") + {"Explodes<BR>
"} + span_bold("Integrity:") + {"Implant will occasionally be degraded by the body's immune system and thus will occasionally malfunction."}
	return dat

/obj/item/implant/dexplosive/trigger(emote, source as mob, mob/actor)
	if(emote == "deathgasp")
		src.activate("death")
	return

/obj/item/implant/dexplosive/activate(cause)
	if((!cause) || (!src.imp_in()))	return 0
	explosion(src, -1, 0, 2, 3, 0)//This might be a bit much, dono will have to see.
	if(src.imp_in())
		src.imp_in().gib()

/obj/item/implant/dexplosive/islegal()
	return 0

//////////////////////////////
//	Explosive Implant
//////////////////////////////
/obj/item/implant/explosive
	name = "explosive implant"
	desc = "A military grade micro bio-explosive. Highly dangerous."
	var/elevel = "Localized Limb"
	var/phrase = "supercalifragilisticexpialidocious"
	icon_state = "implant_evil"

/obj/item/implant/explosive/get_data()
	var/dat = {"
"} + span_bold("Implant Specifications:") + {"<BR>
"} + span_bold("Name:") + {"Robust Corp RX-78 Intimidation Class Implant<BR>
"} + span_bold("Life:") + {"Activates upon codephrase.<BR>
"} + span_bold("Important Notes:") + {"Explodes<BR>
<HR>
"} + span_bold("Implant Details:") + {"<BR>
"} + span_bold("Function:") + {"Contains a compact, electrically detonated explosive that detonates upon receiving a specially encoded signal or upon host death.<BR>
"} + span_bold("Special Features:") + {"Explodes<BR>
"} + span_bold("Integrity:") + {"Implant will occasionally be degraded by the body's immune system and thus will occasionally malfunction."}
	return dat

/obj/item/implant/explosive/hear_talk(mob/M, list/message_pieces, verb)
	var/msg = multilingual_to_message(message_pieces)
	hear(msg)
	return

/obj/item/implant/explosive/hear(msg)
	var/list/replacechars = list("'" = "","\"" = "",">" = "","<" = "","(" = "",")" = "")
	msg = replace_characters(msg, replacechars)
	if(findtext(msg,phrase))
		activate()
		spent(src)

/obj/item/implant/explosive/proc/limb_boom()
	if(!part)
		return
	if (istype(part,/obj/item/organ/external/chest) ||	\
		istype(part,/obj/item/organ/external/groin) ||	\
		istype(part,/obj/item/organ/external/head))
		part.owner?.injure(INJURY_BLUNT, 80, part.organ_tag, src, flags = INJURE_IGNORE_RESISTANCE)	//mangle them instead
		explosion(get_turf(imp_in()), -1, -1, 1, 3)
		spent(src)
	else
		explosion(get_turf(imp_in()), -1, -1, 1, 3)
		part.droplimb(0,DROPLIMB_BLUNT)
		spent(src)

/obj/item/implant/explosive/activate()
	if (malfunction == MALFUNCTION_PERMANENT)
		return

	if(istype(imp_in(), /mob/))
		var/mob/T = imp_in()
		message_admins("Explosive implant triggered in [T] ([T.key]). (<A href='byond://?_src_=holder;[HrefToken()];adminplayerobservecoodjump=1;X=[T.x];Y=[T.y];Z=[T.z]'>JMP</a>) ")
		log_game("Explosive implant triggered in [T] ([T.key]).")

		if(ishuman(imp_in()))
			if (elevel == "Localized Limb")
				if(part) //For some reason, small_boom() didn't work. So have this bit of working copypaste.
					imp_in().visible_message(span_warning("Something beeps inside [imp_in()][part ? "'s [part.name]" : ""]!"))
					play_sfx(src, SFX_ITEMS_COUNTDOWN)
					after(src, 2.5 SECONDS, PROC_REF(limb_boom))
			if (elevel == "Destroy Body")
				explosion(get_turf(T), -1, 0, 1, 6)
				T.gib()
			if (elevel == "Full Explosion")
				explosion(get_turf(T), 0, 1, 3, 6)
				T.gib()

		else
			explosion(get_turf(imp_in()), 0, 1, 3, 6)

	var/turf/t = get_turf(imp_in())

	if(t)
		t.hotspot_expose(3500,125)

/obj/item/implant/explosive/post_implant(mob/source as mob, mob/user = null)
	if(user && !QDELETED(user))
		open_request(src, /datum/prompt/choice/explosive_implant_level, PROC_REF(explosive_level_chosen), answerer = user, source = source)

/// The explosive implant's yield, then its phrase; `source` is the implantee.
/datum/prompt/choice/explosive_implant_level
	title = "Implant Intent"
	question = "What sort of explosion would you prefer?"
	timeout = 0
	buttons = TRUE
	var/mob/source

CAPABILITIES(/datum/prompt/choice/explosive_implant_level)
	ref_one(nameof(source), /mob)

/datum/prompt/choice/explosive_implant_level/prepare(datum/act/A)
	..()
	var/mob/captured_source = source
	rel_clear(src, nameof(source))
	rel_set(src, nameof(source), captured_source)
	var/static/list/levels = list("Localized Limb", "Destroy Body", "Full Explosion")
	choices = levels

/datum/prompt/text/explosive_implant_phrase
	question = "Choose activation phrase:"
	timeout = 0
	var/mob/source
	var/level

CAPABILITIES(/datum/prompt/text/explosive_implant_phrase)
	ref_one(nameof(source), /mob)

/datum/prompt/text/explosive_implant_phrase/prepare(datum/act/A)
	..()
	var/mob/captured_source = source
	rel_clear(src, nameof(source))
	rel_set(src, nameof(source), captured_source)

/obj/item/implant/explosive/proc/explosive_level_chosen(datum/act/request/A)
	var/datum/prompt/choice/explosive_implant_level/ask = A.request
	if(!A.answer || QDELETED(ask.answerer) || QDELETED(ask.source))
		return
	open_request(src, /datum/prompt/text/explosive_implant_phrase, PROC_REF(explosive_configured), answerer = ask.answerer, source = ask.source, level = ask.value)

/obj/item/implant/explosive/proc/explosive_configured(datum/act/request/A)
	var/datum/prompt/text/explosive_implant_phrase/ask = A.request
	if(!A.answer || QDELETED(ask.answerer) || QDELETED(ask.source))
		return
	var/mob/user = ask.answerer
	var/mob/source = ask.source
	elevel = ask.level
	phrase = ask.value
	var/list/replacechars = list("'" = "","\"" = "",">" = "","<" = "","(" = "",")" = "")
	phrase = replace_characters(phrase, replacechars)
	user.mind?.store_memory("Explosive implant in [source] can be activated by saying something containing the phrase ''[src.phrase]'', <B>say [src.phrase]</B> to attempt to activate.", 0, 0)
	to_chat(user, "The implanted explosive implant in [source] can be activated by saying something containing the phrase ''[src.phrase]'', <B>say [src.phrase]</B> to attempt to activate.")

CAPABILITIES(/obj/item/implant/explosive)
	extend(/datum/act/hit/emp, instead(then(PROC_REF(explosive_implant_emp))))
/// An EMP may set the charge off, or melt it down.
/obj/item/implant/explosive/proc/explosive_implant_emp(datum/act/hit/emp/A)
	var/datum/damage_packet/packet = A.packet
	if(malfunction)
		return HOOK_DECLINE
	malfunction = MALFUNCTION_TEMPORARY
	switch (packet.severity)
		if (4)	//Weak EMP will make implant tear limbs off.
			if (prob(25))
				small_boom()
		if (3)	//Weak EMP will make implant tear limbs off.
			if (prob(50))
				small_boom()
		if (2)	//strong EMP will melt implant either making it go off, or disarming it
			if (prob(70))
				if (prob(75))
					small_boom()
				else
					if (prob(13))
						activate()		//chance of bye bye
					else
						meltdown()		//chance of implant disarming
		if (1)	//strong EMP will melt implant either making it go off, or disarming it
			if (prob(70))
				if (prob(50))
					small_boom()
				else
					if (prob(50))
						activate()		//50% chance of bye bye
					else
						meltdown()		//50% chance of implant disarming
	after(src, 2 SECONDS, PROC_REF(malfunction_recover))
	return HOOK_DECLINE

/obj/item/implant/explosive/islegal()
	return 0

/obj/item/implant/explosive/proc/small_boom()
	if (ishuman(imp_in()) && part)
		imp_in().visible_message(span_warning("Something beeps inside [imp_in()][part ? "'s [part.name]" : ""]!"))
		play_sfx(src, SFX_ITEMS_COUNTDOWN)
		after(src, 2.5 SECONDS, PROC_REF(small_boom_goes))

//////////////////////////////
//	Chemical Implant
//////////////////////////////
REGISTRY_MEMBERSHIP(/obj/item/implant/chem, REGISTRY_CHEM_IMPLANTS)

/obj/item/implant/chem
	name = "chemical implant"
	desc = "Injects things."
	allow_reagents = 1
	known_implant = TRUE

/obj/item/implant/chem/get_data()
	var/dat = {"
"} + span_bold("Implant Specifications:") + {"<BR>
"} + span_bold("Name:") + {"Robust Corp MJ-420 Prisoner Management Implant<BR>
"} + span_bold("Life:") + {"Deactivates upon death but remains within the body.<BR>
"} + span_bold("Important Notes: Due to the system functioning off of nutrients in the implanted subject's body, the subject") + {"<BR>
"} + span_bold("will suffer from an increased appetite.") + {"<BR>
<HR>
"} + span_bold("Implant Details:") + {"<BR>
"} + span_bold("Function:") + {"Contains a small capsule that can contain various chemicals. Upon receiving a specially encoded signal<BR>
the implant releases the chemicals directly into the blood stream.<BR>
Special Features:
"} + span_italics("Micro-Capsule") + {"- Can be loaded with any sort of chemical agent via the common syringe and can hold 50 units.<BR>
Can only be loaded while still in its original case.<BR>
"} + span_bold("Integrity:") + {"Implant will last so long as the subject is alive. However, if the subject suffers from malnutrition,<BR>
the implant may become unstable and either pre-maturely inject the subject or simply break."}
	return dat

/obj/item/implant/chem/Initialize(mapload)
	. = ..()
	var/datum/reagents/R = new/datum/reagents(50)
	rel_set(src, nameof(reagents), R)
	rel_set(R, nameof(R.my_atom), src)

/obj/item/implant/chem/trigger(emote, source as mob, mob/actor)
	if(emote == "deathgasp")
		src.activate(src.reagents.total_volume)
	return

/obj/item/implant/chem/activate(cause)
	if((!cause) || (!src.imp_in()))	return 0
	var/mob/living/carbon/R = src.imp_in()
	src.reagents.trans_to_mob(R, cause, CHEM_BLOOD)
	to_chat(R, "You hear a faint *beep*.")
	if(!src.reagents.total_volume)
		to_chat(R, "You hear a faint click from your chest.")
		play_sfx(R, SFX_WEAPONS_EMPTY, 0.2)
		expire(0)
	return

CAPABILITIES(/obj/item/implant/chem)
	extend(/datum/act/hit/emp, instead(then(PROC_REF(chem_implant_emp))))
/// An EMP may make the implant release its chemicals.
/obj/item/implant/chem/proc/chem_implant_emp(datum/act/hit/emp/A)
	var/datum/damage_packet/packet = A.packet
	if(malfunction)
		return HOOK_DECLINE
	malfunction = MALFUNCTION_TEMPORARY

	switch(packet.severity)
		if(1)
			if(prob(60))
				activate(20)
		if(2)
			if(prob(40))
				activate(20)
		if(3)
			if(prob(40))
				activate(5)
		if(4)
			if(prob(20))
				activate(5)

	after(src, 2 SECONDS, PROC_REF(malfunction_recover))
	return HOOK_DECLINE

//////////////////////////////
//	Loyalty Implant
//////////////////////////////
/obj/item/implant/loyalty
	name = "loyalty implant"
	desc = "Makes you loyal or such."
	known_implant = TRUE

/obj/item/implant/loyalty/get_data()
	var/dat = {"
"} + span_bold("Implant Specifications:") + {"<BR>
"} + span_bold("Name:") + {"[using_map.company_name] Employee Management Implant<BR>
"} + span_bold("Life:") + {"Ten years.<BR>
"} + span_bold("Important Notes:") + {"Personnel injected with this device tend to be much more loyal to the company.<BR>
<HR>
"} + span_bold("Implant Details:") + {"<BR>
"} + span_bold("Function:") + {"Contains a small pod of nanobots that manipulate the host's mental functions.<BR>
"} + span_bold("Special Features:") + {"Will prevent and cure most forms of brainwashing.<BR>
"} + span_bold("Integrity:") + {"Implant will last so long as the nanobots are inside the bloodstream."}
	return dat

/obj/item/implant/loyalty/handle_implant(mob/M, target_zone = BP_TORSO)
	. = ..(M, target_zone)
	if(!ishuman(M))
		return FALSE
	var/mob/living/carbon/human/H = M
	if(!H.mind)
		return
	var/datum/antagonist/antag_data = SSantag.get_antag_data(H.mind.special_role)
	if(antag_data && (antag_data.flags & ANTAG_IMPLANT_IMMUNE))
		act_message(H, null, MSG_SELF("You feel the corporate tendrils of [using_map.company_name] try to invade your mind!"), MSG_OTHERS("%U% seems to resist the implant!"))
		. = FALSE

/obj/item/implant/loyalty/post_implant(mob/M)
	var/mob/living/carbon/human/H = M
	SSantag.clear_antag_roles(H.mind, 1)
	to_chat(H, span_notice("You feel a surge of loyalty towards [using_map.company_name]."))

//////////////////////////////
//	Adrenaline Implant
//////////////////////////////
/obj/item/implant/adrenalin
	name = "adrenalin"
	desc = "Removes all stuns and knockdowns."
	var/uses

/obj/item/implant/adrenalin/get_data()
	var/dat = {"
"} + span_bold("Implant Specifications:") + {"<BR>
"} + span_bold("Name:") + {"Cybersun Industries Adrenalin Implant<BR>
"} + span_bold("Life:") + {"Five days.<BR>
"} + span_bold("Important Notes: ") + span_red("llegal") + {"<BR>
<HR>
"} + span_bold("Implant Details:") + {"Subjects injected with implant can activate a massive injection of adrenalin.<BR>
"} + span_bold("Function:") + {"Contains nanobots to stimulate body to mass-produce adrenalin.<BR>
"} + span_bold("Special Features:") + {"Will prevent and cure most forms of brainwashing.<BR>
"} + span_bold("Integrity:") + {"Implant can only be used three times before the nanobots are depleted."}
	return dat

/obj/item/implant/adrenalin/trigger(emote, mob/source as mob, mob/actor)
	if (src.uses < 1)	return 0
	if (emote == "pale")
		src.uses--
		to_chat(source, span_notice("You feel a sudden surge of energy!"))
		source.status_set(STAT_STUNNED, 0)
		source.status_set(STAT_WEAKENED, 0)
		source.status_set(STAT_PARALYZED, 0)

	return

/obj/item/implant/adrenalin/post_implant(mob/source)
	source.mind.store_memory("A implant can be activated by using the pale emote, <B>say *pale</B> to attempt to activate.", 0, 0)
	to_chat(source, "The implanted freedom implant can be activated by using the pale emote, <B>say *pale</B> to attempt to activate.")

//////////////////////////////
//	Death Alarm Implant
//////////////////////////////
/obj/item/implant/death_alarm
	name = "death alarm implant"
	desc = "An alarm which monitors host vital signs and transmits a radio message upon death."
	known_implant = TRUE
	var/mobname = "Will Robinson"

/obj/item/implant/death_alarm/get_data()
	var/dat = {"
"} + span_bold("Implant Specifications:") + {"<BR>
"} + span_bold("Name:") + {"[using_map.company_name] \"Profit Margin\" Class Employee Lifesign Sensor<BR>
"} + span_bold("Life:") + {"Activates upon death.<BR>
"} + span_bold("Important Notes:") + {"Alerts crew to crewmember death.<BR>
<HR>
"} + span_bold("Implant Details:") + {"<BR>
"} + span_bold("Function:") + {"Contains a compact radio signaler that triggers when the host's lifesigns cease.<BR>
"} + span_bold("Special Features:") + {"Alerts crew to crewmember death.<BR>
"} + span_bold("Integrity:") + {"Implant will occasionally be degraded by the body's immune system and thus will occasionally malfunction."}
	return dat

/// Monitors its host every 2 s from implantation until it has raised its alarm (or broke).
/obj/item/implant/death_alarm/var/alarm_armed = FALSE
TRACKED(/obj/item/implant/death_alarm, alarm_armed)
CAPABILITIES(/obj/item/implant/death_alarm)
	every(2 SECONDS, then(PROC_REF(death_alarm_step)), when = nameof(alarm_armed))
	extend(/datum/act/hit/emp, instead(then(PROC_REF(death_alarm_emp))))

/obj/item/implant/death_alarm/proc/death_alarm_step(datum/act/timer/A)
	if (!implanted) return
	var/mob/M = imp_in()

	if(isnull(M)) // If the mob got gibbed
		activate()
	else if(M.stat == 2)
		activate("death")

/obj/item/implant/death_alarm/activate(cause)
	var/mob/M = imp_in()
	var/area/t = get_area(M)
	if(!t) // Failsafe
		set_alarm_armed(FALSE)
		return
	switch (cause)
		if("death")
			var/obj/item/radio/headset/a = new /obj/item/radio/headset/heads/captain(null)
			if(istype(t, /area/syndicate_station) || istype(t, /area/syndicate_mothership) || istype(t, /area/shuttle/syndicate_elite) )
				//give the syndies a bit of stealth
				a.autosay("[mobname] has died in Space!", "[mobname]'s Death Alarm")
			else
				a.autosay("[mobname] has died in [t.name]!", "[mobname]'s Death Alarm")
			consume(a)
			set_alarm_armed(FALSE)
		if ("emp")
			var/obj/item/radio/headset/a = new /obj/item/radio/headset/heads/captain(null)
			var/name = prob(50) ? t.name : pick(GLOB.teleportlocs)
			a.autosay("[mobname] has died in [name]!", "[mobname]'s Death Alarm")
			consume(a)
		else
			var/obj/item/radio/headset/a = new /obj/item/radio/headset/heads/captain(null)
			a.autosay("[mobname] has died-zzzzt in-in-in...", "[mobname]'s Death Alarm")
			consume(a)
			set_alarm_armed(FALSE)

/// For some reason alarms stop going off in case they are emp'd, even without this.
/obj/item/implant/death_alarm/proc/death_alarm_emp(datum/act/hit/emp/A)
	var/datum/damage_packet/packet = A.packet
	if(malfunction) //so I'm just going to add a meltdown chance here
		return HOOK_DECLINE
	malfunction = MALFUNCTION_TEMPORARY
	if(prob(40)) // Make the malfunction a probability because annoying
		activate("emp")	//let's shout that this dude is dead
	if(packet.severity == 1)
		if(prob(40))	//small chance of obvious meltdown
			meltdown()
		else if (prob(60))	//but more likely it will just quietly die
			malfunction = MALFUNCTION_PERMANENT
		set_alarm_armed(FALSE)

	after(src, 2 SECONDS, PROC_REF(malfunction_recover))
	return HOOK_DECLINE

/obj/item/implant/death_alarm/post_implant(mob/source as mob)
	mobname = source.real_name
	set_alarm_armed(TRUE)

//////////////////////////////
//	Compressed Matter Implant
//////////////////////////////
/obj/item/implant/compressed
	name = "compressed matter implant"
	desc = "Based on compressed matter technology, can store a single item."
	icon_state = "implant_evil"
	var/activation_emote = "sigh"
	var/obj/item/scanned

/obj/item/implant/compressed/get_data()
	var/dat = {"
"} + span_bold("Implant Specifications:") + {"<BR>
"} + span_bold("Name:") + {"[using_map.company_name] \"Profit Margin\" Class Employee Lifesign Sensor<BR>
"} + span_bold("Life:") + {"Activates upon death.<BR>
"} + span_bold("Important Notes:") + {"Alerts crew to crewmember death.<BR>
<HR>
"} + span_bold("Implant Details:") + {"<BR>
"} + span_bold("Function:") + {"Contains a compact radio signaler that triggers when the host's lifesigns cease.<BR>
"} + span_bold("Special Features:") + {"Alerts crew to crewmember death.<BR>
"} + span_bold("Integrity:") + {"Implant will occasionally be degraded by the body's immune system and thus will occasionally malfunction."}
	return dat

/obj/item/implant/compressed/trigger(emote, mob/source as mob, mob/actor)
	if (src.scanned() == null)
		return 0

	if (emote == src.activation_emote)
		to_chat(source, "The air glows as \the [src.scanned().name] uncompresses.")
		activate()

/obj/item/implant/compressed/activate()
	var/turf/t = get_turf(src)
	if (imp_in())
		imp_in().put_in_hands(scanned())
	else
		scanned().forceMove(t)
	consume(src)

/obj/item/implant/compressed/post_implant(mob/source, mob/user = null)
	var/choices = list("blink", "blink_r", "eyebrow", "chuckle", "twitch", "frown", "nod", "blush", "giggle", "grin", "groan", "shrug", "smile", "pale", "sniff", "whimper", "wink")
	activation_emote = pick(choices)
	announce_activation(source)
	if(user && !QDELETED(user))
		open_request(src, /datum/prompt/choice/implant_emote, PROC_REF(emote_chosen), answerer = user, choices = choices, source = source)

/// An emote-triggered implant's activation emote (compressed matter, uplink); `source` is the implantee.
/datum/prompt/choice/implant_emote
	title = "Implant Activation"
	question = "Choose activation emote. If you cancel this, one will be picked at random."
	timeout = 0
	var/mob/source

CAPABILITIES(/datum/prompt/choice/implant_emote)
	ref_one(nameof(source), /mob)

/datum/prompt/choice/implant_emote/prepare(datum/act/A)
	..()
	var/mob/captured_source = source
	rel_clear(src, nameof(source))
	rel_set(src, nameof(source), captured_source)

/obj/item/implant/compressed/proc/emote_chosen(datum/act/request/A)
	var/datum/prompt/choice/implant_emote/ask = A.request
	if(!A.answer || QDELETED(ask.answerer) || QDELETED(ask.source))
		return
	activation_emote = ask.value
	announce_activation(ask.source)

/obj/item/implant/compressed/proc/announce_activation(mob/source)
	if (source.mind)
		source.mind.store_memory("Compressed matter implant can be activated by using the [src.activation_emote] emote, <B>say *[src.activation_emote]</B> to attempt to activate.", 0, 0)
	to_chat(source, "The implanted compressed matter implant can be activated by using the [src.activation_emote] emote, <B>say *[src.activation_emote]</B> to attempt to activate.")

/obj/item/implant/compressed/islegal()
	return 0

/obj/item/implant/vrlanguage
	name = "language"
	desc = "Allows the user to understand and speak almost all known languages.."
	var/uses = 1

/obj/item/implant/vrlanguage/get_data()
	var/dat = {"
		<b>Implant Specifications:</b><BR>
		<b>Name:</b> Language Implant<BR>
		<b>Life:</b> One day.<BR>
		<b>Important Notes:</b> Personnel with this implant can speak almost all known languages.<BR>
		<HR>
		<b>Implant Details:</b> Subjects injected with implant can understand and speak almost all known languages.<BR>
		<b>Function:</b> Contains specialized nanobots to stimulate the brain so the user can speak and understand previously unknown languages.<BR>
		<b>Special Features:</b> Will allow the user to understand almost all languages.<BR>
		<b>Integrity:</b> Implant can only be used once before the nanobots are depleted."}
	return dat

/obj/item/implant/vrlanguage/trigger(emote, mob/source as mob, mob/actor)
	if (src.uses < 1)
		return 0
	if (emote == "smile")
		src.uses--
		to_chat(source,span_notice("You suddenly feel as if you can understand other languages!"))
		source.add_language(LANGUAGE_UNATHI)
		source.add_language(LANGUAGE_SIIK)
		source.add_language(LANGUAGE_SKRELLIAN)
		source.add_language(LANGUAGE_ANIMAL)
		source.add_language(LANGUAGE_SCHECHI)
		source.add_language(LANGUAGE_BIRDSONG)
		source.add_language(LANGUAGE_SAGARU)
		source.add_language(LANGUAGE_CANILUNZT)
		source.add_language(LANGUAGE_SLAVIC) //CHOMP reAdd
		source.add_language(LANGUAGE_SOL_COMMON) //In case they're giving a xenomorph an implant or something.
		source.add_language(LANGUAGE_TAVAN)

/obj/item/implant/vrlanguage/post_implant(mob/source)
	source.mind.store_memory("A implant can be activated by using the smile emote, <B>say *smile</B> to attempt to activate.", 0, 0)
	to_chat(source,"The implanted language implant can be activated by using the smile emote, <B>say *smile</B> to attempt to activate.")
	return 1

//////////////////////////////
//	Size Control Implant
//////////////////////////////
/obj/item/implant/sizecontrol
	name = "size control implant"
	desc = "Implant which allows to control host size via voice commands."
	icon_state = "implant_evil"
	var/mob/owner
	var/active = TRUE

/obj/item/implant/sizecontrol/get_data()
	var/dat = {"
<b>Implant Specifications:</b><BR>
<b>Name:</b>L3-WD Size Controlling Implant<BR>
<b>Life:</b>1-2 weeks after implanting<BR>
<HR>
<b>Function:</b> Resizes the host whenever specific verbal command is received<BR>"}
	return dat

/obj/item/implant/sizecontrol/hear_talk(mob/M, list/message_pieces)
	if(M == imp_in())
		return
	if(owner)
		if(M != owner)
			return
	var/msg = multilingual_to_message(message_pieces)
	if(findtext(msg,"ignore"))
		return
	var/list/replacechars = list("&#39;" = "",">" = "","<" = "","(" = "",")" = "", "~" = "")
	msg = replace_characters(msg, replacechars)
	hear(msg)
	return

/obj/item/implant/sizecontrol/see_emote(mob/living/M, message, m_type)
	if(M == imp_in())
		return
	if(owner)
		if(M != owner)
			return
	var/list/replacechars = list("&#39;" = "",">" = "","<" = "","(" = "",")" = "", "~" = "")
	message = replace_characters(message, replacechars)
	var/static/regex/say_in_me = new/regex("(&#34;)(.*?)(&#)", "g")
	while(say_in_me.Find(message))
		if(findtext(say_in_me.match,"ignore"))
			return
		hear(say_in_me.group[2])

/obj/item/implant/sizecontrol/hear(msg)
	if (malfunction)
		return

	if(isliving(imp_in()))
		var/mob/living/H = imp_in()
		if(findtext(msg,"implant-toggle"))
			active = !active
		if(active)
			if(findtext(msg,"grow"))
				H.resize(min(H.size_multiplier*1.5, RESIZE_MAXIMUM))
			else if(findtext(msg,"shrink"))
				H.resize(max(H.size_multiplier*0.5, RESIZE_MINIMUM))
			else if(findtext(msg, "resize"))
				var/static/regex/size_mult = new/regex("\\d+")
				if(size_mult.Find(msg))
					var/resizing_value = text2num(size_mult.match)
					H.resize(CLAMP(resizing_value/100 , RESIZE_MINIMUM_DORMS, RESIZE_MAXIMUM_DORMS), uncapped = H.has_large_resize_bounds()) // Let resize handle size limits. It's meant to do that.

/obj/item/implant/sizecontrol/post_implant(mob/source, mob/user = null)
	if(source != user)
		rel_set(src, nameof(owner), user)

CAPABILITIES(/obj/item/implant/sizecontrol)
	extend(/datum/act/hit/emp, instead(then(PROC_REF(sizecontrol_emp))))
/// An EMP resizes the implantee at random.
/obj/item/implant/sizecontrol/proc/sizecontrol_emp(datum/act/hit/emp/A)
	if(isliving(imp_in()))
		var/newsize = pick(RESIZE_HUGE,RESIZE_BIG,RESIZE_NORMAL,RESIZE_SMALL,RESIZE_TINY,RESIZE_A_HUGEBIG,RESIZE_A_BIGNORMAL,RESIZE_A_NORMALSMALL,RESIZE_A_SMALLTINY)
		var/mob/living/H = imp_in()
		H.resize(newsize)
	return HOOK_DECLINE

/obj/item/implanter/sizecontrol
	name = "size control implant"
	desc = "Implant which allows to control host size via voice commands."

/obj/item/implanter/sizecontrol/ownership()
	. = ..()
	. += owns(nameof(imp), policy = OWN_CONTAINED, starts = /obj/item/implant/sizecontrol)

/obj/item/implanter/sizecontrol
	icon_state = "implanter1_1" // loaded: what update() would show

//////////////////////////////
//	Compliance Implant
//////////////////////////////
/obj/item/implanter/compliance
	name = "compliance implant"
	desc = "Implant which allows for implanting 'laws' or 'commands' in the host. Has a miniature keyboard for typing laws into."

	description_fluff = "Due to the illegality of these types of implants, they are often made in clandestine facilities with a complete lack of quality control \
	and as such, may malfunction or simply not work whatsoever. After loyalty implants were outlawed in many civilized areas of space, an abundance of readily \
	available implanters and implants became available for purchase on the black market, with some deciding to modify them. Now, they are often used by illegal \
	entities to perform espionage and in some parts of space are used off the books for interrogation. Most of the makers of these modified implants have put in \
	safeties to prevent lethal or actively harmful commands from being input to lessen the severity of the crime if they are caught. This one has a golden stamp \
	with the shape of a star on it, the letters 'KE' in black text on it."
	special_handling = TRUE

/obj/item/implanter/compliance/ownership()
	. = ..()
	. += owns(nameof(imp), policy = OWN_CONTAINED, starts = /obj/item/implant/compliance)

/obj/item/implanter/compliance
	icon_state = "implanter1_1" // loaded: what update() would show

/// The compliance implant's laws. Re-checked on the answer: the implanter is still carried and still loaded with that implant.
/datum/prompt/text/compliance_laws
	timeout = 0
	title = "Compliance Laws"
	question = "Please Input Laws"
	default = ""
	multiline = TRUE
	ask_flags = ASK_CARRIED | ASK_CAPABLE
	var/obj/item/implant/compliance/implant

CAPABILITIES(/datum/prompt/text/compliance_laws)
	ref_one(nameof(implant), /obj/item/implant/compliance)

/datum/prompt/text/compliance_laws/prepare(datum/act/A)
	..()
	var/obj/item/implant/compliance/captured_implant = implant
	rel_clear(src, nameof(implant))
	rel_set(src, nameof(implant), captured_implant)

/datum/prompt/text/compliance_laws/recheck_extra()
	. = ..()
	if(.)
		return
	var/obj/item/implanter/compliance/implanter = owner
	return !QDELETED(implanter) && !QDELETED(implant) && implanter.imp == implant ? null : "implant changed"

/obj/item/implanter/compliance/proc/laws_entered(datum/act/request/A)
	var/datum/prompt/text/compliance_laws/ask = A.request
	if(!A.answer || QDELETED(ask.answerer) || QDELETED(ask.implant))
		return
	var/mob/user = ask.answerer
	var/obj/item/implant/compliance/implant = ask.implant
	var/newlaws = sanitize(ask.value, 2048)
	if(newlaws)
		to_chat(user,"You set the laws to: <br>" + span_notice("[newlaws]"))
		implant.laws = newlaws //Organic

CAPABILITIES(/obj/item/implanter/compliance)
	without("toggle")
	op("compliance_implanter_self", in_hand(), label("Set laws"), then(PROC_REF(compliance_implanter_self)))

/// Old attack_self.
/obj/item/implanter/compliance/proc/compliance_implanter_self(datum/act/op/A)
	var/mob/user = A.actor
	if(istype(imp,/obj/item/implant/compliance))
		var/obj/item/implant/compliance/implant = imp
		open_request(src, /datum/prompt/text/compliance_laws, PROC_REF(laws_entered), answerer = user, implant = implant)
	else //No using other implants.
		to_chat(user,span_notice("A red warning pops up on the implanter's micro-screen: 'INVALID IMPLANT DETECTED.'"))

/obj/item/implant/compliance
	name = "compliance implant"
	desc = "Implant which allows for forcing obedience in the host."
	icon_state = "implant_evil"
	var/active = TRUE
	var/laws = "CHANGE BEFORE IMPLANTATION"
	var/nif_payload = /datum/nifsoft/compliance

/obj/item/implant/compliance/get_data()
	var/dat = {"
<b>Implant Specifications:</b><BR>
<b>Name:</b>Compliance Implant<BR>
<b>Life:</b>24 Hours<BR>
<HR>
<b>Function:</b> Forces a subject to follow a set of laws.<BR>
<HR>
<b>Set Laws:</b>[laws]"}
	return dat

/obj/item/implant/compliance/post_implant(mob/source, mob/user = null)
	if(!ishuman(source)) //No compliance implanting non-humans.
		return

	var/mob/living/carbon/human/target = source
	if(!target.nif || target.nif.stat != NIF_WORKING) //No nif or their NIF is broken.
		to_chat(target, span_notice("You suddenly feel compelled to follow the following commands: [laws]"))
		to_chat(target, span_notice("((OOC NOTE: Commands that go against server rules should be disregarded and ahelped.))"))
		to_chat(target, span_notice("((OOC NOTE: Your new commands can be checked at any time by using the 'notes' command in chat. Additionally, if you did not agree to this, you are not compelled to follow the implant.))"))
		target.add_memory(laws)
		return
	else //You got a nif...Upload time.
		new nif_payload(target.nif,laws)
		to_chat(target, span_notice("((OOC NOTE: Commands that go against server rules should be disregarded and ahelped.))"))
		to_chat(target, span_notice("((OOC NOTE: If you did not agree to this, you are not compelled to follow the laws.))"))

/// after() target: one step of a temporary malfunction wears off.
/obj/item/implant/proc/malfunction_recover()
	malfunction--

/obj/item/implant/explosive/proc/small_boom_goes()
	if (ishuman(imp_in()) && part)
		//No tearing off these parts since it's pretty much killing
		//and you can't replace groins
		if (istype(part,/obj/item/organ/external/chest) ||	\
			istype(part,/obj/item/organ/external/groin) ||	\
			istype(part,/obj/item/organ/external/head))
			part.owner?.injure(INJURY_BLUNT, 80, part.organ_tag, src, flags = INJURE_IGNORE_RESISTANCE)	//mangle them instead
		else
			part.droplimb(0,DROPLIMB_BLUNT)
	explosion(get_turf(imp_in()), -1, -1, 1, 3)
	spent(src)

/// Relation view: imp in (reads null once it is gone).
/obj/item/implant/proc/imp_in() as /mob
	return imp_in

/// Relation view: scanned (reads null once it is gone).
/obj/item/implant/compressed/proc/scanned() as /obj/item
	return scanned

// part is the organ the implant sits in: a view kept by the organ's implant slot (containment), not owned.
