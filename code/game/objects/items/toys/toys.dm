/* Toys!
 * Contains:
 *		Balloons
 *		Fake telebeacon
 *		Fake singularity
 *		Toy swords
 *		Toy bosun's whistle
 *		Snap pops
 *		Water flower
 *      Therapy dolls
 *      Toddler doll
 *      Inflatable duck
 *		Action figures
 *		Plushies
 *		Toy cult sword
 *		Bouquets
 *		Stick Horse
 */

/obj/item/toy
	throwforce = 0
	throw_speed = 4
	throw_range = 20
	force = 0
	drop_sound = SFX_ITEMS_DROP_GLOVES

/*
 * Balloons
 */
/obj/item/toy/balloon
	name = "water balloon"
	desc = "A translucent balloon. There's nothing in it."
	icon = 'icons/obj/toy.dmi'
	icon_state = "waterballoon-e"
	drop_sound = SFX_ITEMS_DROP_RUBBER

/obj/item/toy/balloon/Initialize(mapload)
	. = ..()
	var/datum/reagents/R = new/datum/reagents(10)
	rel_set(src, nameof(reagents), R)
	rel_set(R, nameof(R.my_atom), src)

/obj/item/toy/balloon/attack(mob/living/M, mob/living/user, target_zone, attack_modifier)
	return NONE

/obj/item/toy/balloon/afterattack(atom/A as mob|obj, mob/user as mob, proximity)
	if(!proximity) return
	if (istype(A, /obj/structure/reagent_dispensers/watertank) && get_dist(src,A) <= 1)
		A.reagents.trans_to_obj(src, 10)
		to_chat(user, span_notice("You fill the balloon with the contents of [A]."))
		src.desc = "A translucent balloon with some form of liquid sloshing around in it."
	return

CAPABILITIES(/obj/item/toy/balloon)
	op("item", item(/obj/item), label("Use"), then(PROC_REF(interaction_item)))

/// Old attackby.
/obj/item/toy/balloon/proc/interaction_item(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/O = A.held
	if(istype(O, /obj/item/reagent_containers/glass))
		if(O.reagents)
			if(O.reagents.total_volume < 1)
				to_chat(user, "The [O] is empty.")
			else if(O.reagents.total_volume >= 1)
				if(O.reagents.has_reagent(REAGENT_ID_PACID, 1))
					to_chat(user, "The acid chews through the balloon!")
					O.reagents.splash(user, reagents.total_volume)
					consume(src, user)
				else
					src.desc = "A translucent balloon with some form of liquid sloshing around in it."
					to_chat(user, span_notice("You fill the balloon with the contents of [O]."))
					O.reagents.trans_to_obj(src, 10)
	return OP_PASS

/obj/item/toy/balloon/throw_impact(atom/hit_atom)
	if(src.reagents.total_volume >= 1)
		src.visible_message(span_warning("\The [src] bursts!"),"You hear a pop and a splash.")
		src.reagents.touch_turf(get_turf(hit_atom))
		for(var/atom/A in get_turf(hit_atom))
			src.reagents.touch(A)
		src.icon_state = "burst"
		expire(5)
	return

/obj/item/toy/balloon/draw(datum/look/look)
	..()
	if(src.reagents.total_volume >= 1)
		look.state("waterballoon")
	else
		look.state("waterballoon-e")

/obj/item/toy/syndicateballoon
	name = "criminal balloon"
	desc = "There is a tag on the back that reads \"FUK NT!11!\"."
	throwforce = 0
	throw_speed = 4
	throw_range = 20
	force = 0
	icon = 'icons/obj/weapons.dmi'
	icon_state = "syndballoon"
	w_class = ITEMSIZE_LARGE
	drop_sound = SFX_ITEMS_DROP_RUBBER

/obj/item/toy/nanotrasenballoon
	name = "criminal balloon"
	desc = "Across the balloon the following is printed: \"Man, I love NanoTrasen soooo much. I use only NT products. You have NO idea.\""
	throwforce = 0
	throw_speed = 4
	throw_range = 20
	force = 0
	icon = 'icons/obj/weapons.dmi'
	icon_state = "ntballoon"
	w_class = ITEMSIZE_LARGE
	drop_sound = SFX_ITEMS_DROP_RUBBER

/obj/item/toy/colorballoon /// To color it, VV the 'color' var with a hex color code with the # included.
	name = "balloon"
	desc = "It's a plain little balloon. Comes in many colors!"
	throwforce = 0
	throw_speed = 4
	throw_range = 20
	force = 0
	icon = 'icons/obj/weapons.dmi'
	icon_state = "colorballoon"
	w_class = ITEMSIZE_LARGE
	drop_sound = SFX_ITEMS_DROP_RUBBER

/*
 * Fake telebeacon
 */
/obj/item/toy/blink
	name = "electronic blink toy game"
	desc = "Blink.  Blink.  Blink. Ages 8 and up."
	icon = 'icons/obj/radio.dmi'
	icon_state = "beacon"
	item_state = "signaler"

/*
 * Fake singularity
 */
/obj/item/toy/spinningtoy
	name = "gravitational singularity"
	desc = "\"Singulo\" brand spinning toy."
	icon = 'icons/obj/singularity.dmi'
	icon_state = "singularity_s1"

/*
 * Toy swords
 */
/obj/item/toy/sword
	name = "toy sword"
	desc = "A cheap, plastic replica of an energy sword. Realistic sounds! Ages 8 and up."
	icon = 'icons/obj/weapons.dmi'
	icon_state = "esword"
	drop_sound = SFX_ITEMS_DROP_GUN
	var/lcolor
	var/rainbow = FALSE
	item_icons = list(
		slot_l_hand_str = 'icons/mob/items/lefthand_melee.dmi',
		slot_r_hand_str = 'icons/mob/items/righthand_melee.dmi',
		)
	var/active = 0
	w_class = ITEMSIZE_SMALL
	attack_verb = list("attacked", "struck", "hit")

CAPABILITIES(/obj/item/toy/sword)
	op("toggle", in_hand(), then(PROC_REF(interaction_self)))
	op("item", item(/obj/item), then(PROC_REF(interaction_item)))
	// the old click_alt: recolour the blade after a yes
	op("recolor", hand(), ungated(), gesture(GESTURE_ALT), label("Recolor"),
		asks(/datum/prompt/yes_no, fields = list("title" = "Confirm Recolor", "question" = "Are you sure you want to recolor your blade?", "timeout" = 0), step = "sure"),
		asks(/datum/prompt/color/blade_recolor, fields = list("title" = "Choose Energy Color", "default" = "lcolor"), step = "colour", when = PROC_REF(recolor_confirmed)),
		then(PROC_REF(blade_recolored)))

/// Old attack_self: extend or retract the plastic blade.
/obj/item/toy/sword/proc/interaction_self(datum/act/op/A)
	var/mob/user = A.actor
	set_active(!active)
	if(active)
		to_chat(user, span_notice("You extend the plastic blade with a quick flick of your wrist."))
		play_sfx(src, SFX_WEAPONS_SABERON)
		w_class = ITEMSIZE_LARGE
	else
		to_chat(user, span_notice("You push the plastic blade back down into the handle."))
		play_sfx(src, SFX_WEAPONS_SABEROFF)
		w_class = ITEMSIZE_SMALL
	add_fingerprint(user)
	return OP_OK

TRACKED(/obj/item/toy/sword, active)
TRACKED(/obj/item/toy/sword, lcolor)

/// The look: the plastic blade over the hilt, in the blade's colour.
/obj/item/toy/sword/draw(datum/look/look)
	..()
	var/base = look.state_so_far(src)
	look.overlay(look_appearance(icon, "[base]_blade", color = lcolor), active)
	look.held_state(active ? "[base]_blade" : base)

/// The recolour was confirmed: the colour picker is next.
/obj/item/toy/sword/proc/recolor_confirmed(datum/act/op/A)
	var/datum/prompt/R = A.step_answers?["sure"]
	return !!R?.value

/// Old click_alt: the blade takes the picked colour.
/obj/item/toy/sword/proc/blade_recolored(datum/act/op/A)
	var/datum/prompt/R = A.step_answers?["colour"]
	if(!R)
		return OP_OK
	if(R.value)
		set_lcolor(sanitize_hexcolor(R.value))
	return OP_OK

/obj/item/toy/sword/examine(mob/user)
	. = ..()
	. += span_notice("Alt-click to recolor it.")

/// Old attackby: a multitool switches the rainbow blade while it is retracted (the click goes on).
/obj/item/toy/sword/proc/interaction_item(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/W = A.held
	if(W.has_tool_quality(TOOL_MULTITOOL) && !active)
		if(!rainbow)
			rainbow = TRUE
		else
			rainbow = FALSE
		to_chat(user, span_notice("You manipulate the color controller in [src]."))
	return OP_PASS
/obj/item/toy/katana
	name = "replica katana"
	desc = "Woefully underpowered in D20."
	icon = 'icons/obj/weapons.dmi'
	icon_state = "katana"
	item_state = "katana"
	item_icons = list(
		slot_l_hand_str = 'icons/mob/items/lefthand_material.dmi',
		slot_r_hand_str = 'icons/mob/items/righthand_material.dmi',
		)
	slot_flags = SLOT_BELT | SLOT_BACK
	force = 5
	throwforce = 5
	w_class = ITEMSIZE_NORMAL
	attack_verb = list("attacked", "slashed", "stabbed", "sliced")

/*
 * Snap pops
 */
/obj/item/toy/snappop
	name = "snap pop"
	desc = "Wow!"
	icon = 'icons/obj/toy.dmi'
	icon_state = "snappop"
	w_class = ITEMSIZE_TINY
	drop_sound = null

/obj/item/toy/snappop/throw_impact(atom/hit_atom)
	..()
	fx_sparks(src, 3)
	src.visible_message(span_warning("The [src.name] explodes!"),span_warning("You hear a snap!"))
	play_sfx(src, SFX_EFFECTS_SNAP)
	replace_with(src, /obj/effect/decal/cleanable/ash)

/obj/item/toy/snappop/Crossed(atom/movable/H as mob|obj)
	if(H.is_incorporeal())
		return
	if((ishuman(H))) //i guess carp and shit shouldn't set them off
		var/mob/living/carbon/M = H
		if(M.m_intent == I_RUN)
			to_chat(M, span_warning("You step on the snap pop!"))

			fx_sparks(src, 2, FALSE)
			src.visible_message(span_warning("The [src.name] explodes!"),span_warning("You hear a snap!"))
			play_sfx(src, SFX_EFFECTS_SNAP)
			replace_with(src, /obj/effect/decal/cleanable/ash)

/*
 * Bosun's whistle
 */
/obj/item/toy/bosunwhistle
	name = "bosun's whistle"
	desc = "A genuine Admiral Krush Bosun's Whistle, for the aspiring ship's captain! Suitable for ages 8 and up, do not swallow."
	icon = 'icons/obj/toy.dmi'
	icon_state = "bosunwhistle"
	drop_sound = SFX_ITEMS_DROP_CARD
	var/cooldown = 0
	w_class = ITEMSIZE_TINY
	slot_flags = SLOT_EARS | SLOT_HOLSTER

CAPABILITIES(/obj/item/toy/bosunwhistle)
	op("self", in_hand(), then(PROC_REF(interaction_self)))

/// Old attack_self.
/obj/item/toy/bosunwhistle/proc/interaction_self(datum/act/op/A)
	var/mob/user = A.actor
	if(COOLDOWN_FINISHED(src, cooldown))
		to_chat(user, span_notice("You blow on [src], creating an ear-splitting noise!"))
		play_sfx(src, SFX_MISC_BOATSWAIN)
		COOLDOWN_START(src, cooldown, 3.5 SECONDS)
	return TRUE

/*
 * Action figures
 */
/obj/item/toy/figure
	name = "Non-Specific Action Figure action figure"
	desc = "A \"Space Life\" brand... wait, what the hell is this thing?"
	icon = 'icons/obj/toy.dmi'
	icon_state = "nuketoy"
	w_class = ITEMSIZE_TINY
	var/cooldown = 0
	var/toysay = "What the fuck did you do?"
	drop_sound = SFX_ITEMS_DROP_ACCESSORY

/obj/item/toy/figure/Initialize(mapload)
	. = ..()
	desc = "A \"Space Life\" brand [name]"

CAPABILITIES(/obj/item/toy/figure)
	op("self", in_hand(), then(PROC_REF(interaction_self)))

/// Old attack_self.
/obj/item/toy/figure/proc/interaction_self(datum/act/op/A)
	var/mob/user = A.actor
	if(COOLDOWN_FINISHED(src, cooldown))
		COOLDOWN_START(src, cooldown, 3 SECONDS)
		user.visible_message(span_notice("The [src] says \"[toysay]\"."))
		play_sfx(src, SFX_MACHINES_CLICK, 0.4)
	return TRUE

/obj/item/toy/figure/cmo
	name = JOB_CHIEF_MEDICAL_OFFICER + " action figure"
	desc = "A \"Space Life\" brand " + JOB_CHIEF_MEDICAL_OFFICER + " action figure."
	icon_state = "cmo"
	toysay = "Suit sensors!"

/obj/item/toy/figure/assistant
	name = "Assistant action figure"
	desc = "A \"Space Life\" brand Assistant action figure."
	icon_state = "assistant"
	toysay = "Grey tide station wide!"

/obj/item/toy/figure/atmos
	name = JOB_ATMOSPHERIC_TECHNICIAN + " action figure"
	desc = "A \"Space Life\" brand " + JOB_ATMOSPHERIC_TECHNICIAN + " action figure."
	icon_state = "atmos"
	toysay = "Glory to Atmosia!"

/obj/item/toy/figure/bartender
	name = JOB_BARTENDER + " action figure"
	desc = "A \"Space Life\" brand " + JOB_BARTENDER + " action figure."
	icon_state = "bartender"
	toysay = "Where's my monkey?"

/obj/item/toy/figure/borg
	name = "Drone action figure"
	desc = "A \"Space Life\" brand Drone action figure."
	icon_state = "borg"
	toysay = "I. LIVE. AGAIN."

/obj/item/toy/figure/gardener
	name = JOB_ALT_GARDENER + " action figure"
	desc = "A \"Space Life\" brand " + JOB_ALT_GARDENER + " action figure."
	icon_state = "botanist"
	toysay = "Dude, I see colors..."

/obj/item/toy/figure/captain
	name = JOB_SITE_MANAGER + " action figure"
	desc = "A \"Space Life\" brand " + JOB_SITE_MANAGER + " action figure."
	icon_state = "captain"
	toysay = "How do I open this display case?"

/obj/item/toy/figure/cargotech
	name = JOB_CARGO_TECHNICIAN + " action figure"
	desc = "A \"Space Life\" brand " + JOB_CARGO_TECHNICIAN + " action figure."
	icon_state = "cargotech"
	toysay = "For Cargonia!"

/obj/item/toy/figure/ce
	name = JOB_CHIEF_ENGINEER + " action figure"
	desc = "A \"Space Life\" brand " + JOB_CHIEF_ENGINEER + " action figure."
	icon_state = "ce"
	toysay = "Wire the solars!"

/obj/item/toy/figure/chaplain
	name = JOB_CHAPLAIN + " action figure"
	desc = "A \"Space Life\" brand " + JOB_CHAPLAIN + " action figure."
	icon_state = "chaplain"
	toysay = "Gods make me a killing machine please!"

/obj/item/toy/figure/chef
	name = JOB_CHEF + " action figure"
	desc = "A \"Space Life\" brand " + JOB_CHEF + " action figure."
	icon_state = "chef"
	toysay = "I swear it's not human meat."

/obj/item/toy/figure/chemist
	name = JOB_CHEMIST + " action figure"
	desc = "A \"Space Life\" brand " + JOB_CHEMIST + " action figure."
	icon_state = "chemist"
	toysay = "Get your pills!"

/obj/item/toy/figure/clown
	name = JOB_CLOWN + " action figure"
	desc = "A \"Space Life\" brand " + JOB_CLOWN + " action figure."
	icon_state = "clown"
	toysay = "<font face='comic sans ms'>" + span_bold("Honk!") + "</font>"

/obj/item/toy/figure/corgi
	name = "Corgi action figure"
	desc = "A \"Space Life\" brand Corgi action figure."
	icon_state = "ian"
	toysay = "Arf!"

/obj/item/toy/figure/detective
	name = JOB_DETECTIVE + " action figure"
	desc = "A \"Space Life\" brand " + JOB_DETECTIVE + " action figure."
	icon_state = "detective"
	toysay = "This airlock has grey jumpsuit and insulated glove fibers on it."

/obj/item/toy/figure/dsquad
	name = "Space Commando action figure"
	desc = "A \"Space Life\" brand Space Commando action figure."
	icon_state = "dsquad"
	toysay = "Eliminate all threats!"

/obj/item/toy/figure/engineer
	name = JOB_ENGINEER + " action figure"
	desc = "A \"Space Life\" brand " + JOB_ENGINEER + " action figure."
	icon_state = "engineer"
	toysay = "Oh god, the engine is gonna go!"

/obj/item/toy/figure/geneticist
	name = JOB_GENETICIST + " action figure"
	desc = "A \"Space Life\" brand " + JOB_GENETICIST + " action figure, which was recently dicontinued."
	icon_state = "geneticist"
	toysay = "I'm not qualified for this job."

/obj/item/toy/figure/hop
	name = JOB_HEAD_OF_PERSONNEL + " action figure"
	desc = "A \"Space Life\" brand " + JOB_HEAD_OF_PERSONNEL + " action figure."
	icon_state = "hop"
	toysay = "Giving out all access!"

/obj/item/toy/figure/hos
	name = JOB_HEAD_OF_SECURITY + " action figure"
	desc = "A \"Space Life\" brand " + JOB_HEAD_OF_SECURITY + " action figure."
	icon_state = "hos"
	toysay = "I'm here to win, anything else is secondary."

/obj/item/toy/figure/qm
	name = JOB_QUARTERMASTER + " action figure"
	desc = "A \"Space Life\" brand " + JOB_QUARTERMASTER + " action figure."
	icon_state = "qm"
	toysay = "Hail Cargonia!"

/obj/item/toy/figure/janitor
	name = JOB_JANITOR + " action figure"
	desc = "A \"Space Life\" brand " + JOB_JANITOR + " action figure."
	icon_state = "janitor"
	toysay = "Look at the signs, you idiot."

/obj/item/toy/figure/agent
	name = JOB_INTERNAL_AFFAIRS_AGENT + " action figure"
	desc = "A \"Space Life\" brand " + JOB_INTERNAL_AFFAIRS_AGENT + " action figure."
	icon_state = "agent"
	toysay = "Standard Operating Procedure says they're guilty! Hacking is proof they're an Enemy of the Corporation!"

/obj/item/toy/figure/librarian
	name = JOB_LIBRARIAN + " action figure"
	desc = "A \"Space Life\" brand " + JOB_LIBRARIAN + " action figure."
	icon_state = "librarian"
	toysay = "One day while..."

/obj/item/toy/figure/md
	name = JOB_MEDICAL_DOCTOR + " action figure"
	desc = "A \"Space Life\" brand " + JOB_MEDICAL_DOCTOR + " action figure."
	icon_state = "md"
	toysay = "The patient is already dead!"

/obj/item/toy/figure/mime
	name = JOB_MIME + " action figure"
	desc = "A \"Space Life\" brand " + JOB_MIME + " action figure."
	icon_state = "mime"
	toysay = "..."

/obj/item/toy/figure/miner
	name = JOB_SHAFT_MINER + " action figure"
	desc = "A \"Space Life\" brand " + JOB_SHAFT_MINER + " action figure."
	icon_state = "miner"
	toysay = "Oh god, it's eating my intestines!"

/obj/item/toy/figure/ninja
	name = "Space Ninja action figure"
	desc = "A \"Space Life\" brand Space Ninja action figure."
	icon_state = "ninja"
	toysay = "Oh god! Stop shooting, I'm friendly!"

/obj/item/toy/figure/wizard
	name = JOB_WIZARD + " action figure"
	desc = "A \"Space Life\" brand " + JOB_WIZARD + " action figure."
	icon_state = "wizard"
	toysay = "Ei Nath!"

/obj/item/toy/figure/rd
	name = JOB_RESEARCH_DIRECTOR + " action figure"
	desc = "A \"Space Life\" brand " + JOB_RESEARCH_DIRECTOR + " action figure."
	icon_state = "rd"
	toysay = "Blowing all of the borgs!"

/obj/item/toy/figure/roboticist
	name = JOB_ROBOTICIST + " action figure"
	desc = "A \"Space Life\" brand " + JOB_ROBOTICIST + " action figure."
	icon_state = "roboticist"
	toysay = "He asked to be borged!"

/obj/item/toy/figure/scientist
	name = JOB_SCIENTIST + " action figure"
	desc = "A \"Space Life\" brand " + JOB_SCIENTIST + " action figure."
	icon_state = "scientist"
	toysay = "Someone else must have made those bombs!"

/obj/item/toy/figure/syndie
	name = "Doom Operative action figure"
	desc = "A \"Space Life\" brand Doom Operative action figure."
	icon_state = "syndie"
	toysay = "Get that fucking disk!"

/obj/item/toy/figure/secofficer
	name = JOB_SECURITY_OFFICER + " action figure"
	desc = "A \"Space Life\" brand " + JOB_SECURITY_OFFICER + " action figure."
	icon_state = "secofficer"
	toysay = "I am the law!"

/obj/item/toy/figure/virologist
	name = JOB_ALT_VIROLOGIST + " action figure"
	desc = "A \"Space Life\" brand " + JOB_ALT_VIROLOGIST + " action figure."
	icon_state = "virologist"
	toysay = "The cure is potassium!"

/obj/item/toy/figure/warden
	name = JOB_WARDEN + " action figure"
	desc = "A \"Space Life\" brand " + JOB_WARDEN + " action figure."
	icon_state = "warden"
	toysay = "Execute him for breaking in!"

/obj/item/toy/figure/psychologist
	name = JOB_ALT_PSYCHOLOGIST + " action figure"
	desc = "A \"Space Life\" brand " + JOB_ALT_PSYCHOLOGIST + " action figure."
	icon_state = "psychologist"
	toysay = "The analyzer says you're fine!"

/obj/item/toy/figure/paramedic
	name = JOB_PARAMEDIC + " action figure"
	desc = "A \"Space Life\" brand " + JOB_PARAMEDIC + " action figure."
	icon_state = "paramedic"
	toysay = "WHERE ARE YOU??"

/obj/item/toy/figure/ert
	name = JOB_EMERGENCY_RESPONSE_TEAM + " Commander action figure"
	desc = "A \"Space Life\" brand " + JOB_EMERGENCY_RESPONSE_TEAM + " Commander action figure."
	icon_state = "ert"
	toysay = "We're probably the good guys!"

// Eris
/obj/item/toy/figure/excelsior
	name = "\"Excelsior\" figurine"
	desc = "A curiously unbranded figurine of a Space Soviet, adorned in their iconic armor. There is still a price tag on the back of the base, six-hundred credits, people collect these things? \
	\"Ever Upward!\""
	icon_state = "excelsior"

/obj/item/toy/figure/serbian
	name = "mercenary figurine"
	desc = "A curiously unbranded figurine, the olive drab a popular pick for many independent Serbian mercenary outfits. Rocket launcher not included."
	icon_state = "serbian"

/obj/item/toy/figure/acolyte
	name = "acolyte figurine"
	desc = "Church of NeoTheology \"New Faith Life\" brand figurine of an acolyte, hooded both physically and spiritually from that which would lead them astray."
	icon_state = "acolyte"

/obj/item/toy/figure/carrion
	name = "carrion figurine"
	desc = "A curiously unbranded figurine depicting a grotesque head of flesh, the Human features seem almost underdeveloped, its skull bulging outwards, mouth agape with torn flesh. \
	Whoever made this certainly knew how to thin their paints."
	icon_state = "carrion"

/obj/item/toy/figure/roach
	name = "roach figurine"
	desc = "Upon the base is an erected \"Roachman\", its arms outstretched, with more additional roach hands besides them. This is likely the one thing most universally recognized in popular media. \
	The plaque is covered in hundreds of scratch marks, eliminating any further knowledge of it or its brand."
	icon_state = "roach"

/obj/item/toy/figure/vagabond
	name = "vagabond figurine"
	desc = "An Aster's \"Space Life\" brand figurine showcasing the form of a random deplorable, wearing one of the ship's uniforms, and an orange bandana. \
	Must of been custom-made to commemorate the Eris' doomed voyage."
	icon_state = "vagabond"

/obj/item/toy/figure/rooster
	name = "rooster figurine"
	desc = "\"Space Vice\" brand figurine, there is no further manufacturer information. It's a man wearing a rooster mask, and a varsity jacket with the letter \"B\" emblazoned on the front. \
	\"Do you like hurting other people?\""
	icon_state = "rooster"

/obj/item/toy/figure/barking_dog
	name = "barking dog figurine"
	desc = "A metal soldier with the mask of a hound stands upon the base, the plaque seems smeared with caked grime, but despite this you make out a rare double-quote. \
	\"A dog barks on its master's orders, lest its pack runs astray.\" \"Whatever the task, the grim dog mask would tell you that your life was done.\""
	icon_state = "barking_dog"

/obj/item/toy/figure/red_soldier
	name = "red soldier figurine"
	desc = "A curiously unbranded figurine of a red soldier fighting in the tides of war, their humanity hidden by a gas mask. \"Why do we fight? To win the war, of course.\""
	icon_state = "red_soldier"

/obj/item/toy/figure/metacat
	name = "meta-cat figurine"
	desc = "A curiously unbranded figurine depicting an anthropomorphic cat in a voidsuit, the small plaque claims this to be one of two. \"Always in silent pair, through distance or unlikelihood.\""
	icon_state = "metacat"

/obj/item/toy/figure/shitcurity
	name = "shitcurity officer figurine"
	desc = "An Aster's \"Space Life\" brand figurine of a classic redshirt of \"Nanotrasen's finest\". Their belly distends out into an obvious beer gut, revealing no form of manufacturer bias what-so-ever. \
	\"I joined just to kill people.\""
	icon_state = "shitcurity"

/obj/item/toy/figure/metro_patrolman
	name = "metro patrolman figurine"
	desc = "The plaque seems flaked with rust residue, \"London Metro\" brand it reads. The man wears some kind of enforcer's uniform, with the acronym \"VPP\" on their left shoulder and cap. \
	\"Abandoned for Escalation, the patrolman grumbles.\""
	icon_state = "metro_patrolman"

/*
 * Plushies
 */

/*
 * Carp plushie
 */

/obj/item/toy/plushie/carp
	name = "space carp plushie"
	desc = "An adorable stuffed toy that resembles a space carp."
	icon = 'icons/obj/toy.dmi'
	icon_state = "basecarp"
	attack_verb = list("bitten", "eaten", "fin slapped")
	squeeze_sound = SFX_WEAPONS_BITE
	cooldown_length = 1 SECOND

// Attack mob
/obj/item/toy/plushie/carp/attack(mob/living/M, mob/living/user, target_zone, attack_modifier)
	playsound(src, squeeze_sound, 20, 1)	// Play bite sound in local area
	return ..()

/obj/random/carp_plushie
	name = "Random Carp Plushie"
	desc = "This is a random plushie"
	icon = 'icons/obj/toy.dmi'
	icon_state = "basecarp"

CAPABILITIES(/obj/random/carp_plushie)
	loot(table = list(loot_types(1, typesof(/obj/item/toy/plushie/carp))))

/obj/item/toy/plushie/carp/ice
	name = "ice carp plushie"
	icon_state = "icecarp"

/obj/item/toy/plushie/carp/silent
	name = "monochrome carp plushie"
	icon_state = "silentcarp"

/obj/item/toy/plushie/carp/electric
	name = "electric carp plushie"
	icon_state = "electriccarp"

/obj/item/toy/plushie/carp/gold
	name = "golden carp plushie"
	icon_state = "goldcarp"

/obj/item/toy/plushie/carp/toxin
	name = "toxic carp plushie"
	icon_state = "toxincarp"

/obj/item/toy/plushie/carp/dragon
	name = "dragon carp plushie"
	icon_state = "dragoncarp"

/obj/item/toy/plushie/carp/pink
	name = "pink carp plushie"
	icon_state = "pinkcarp"

/obj/item/toy/plushie/carp/candy
	name = "candy carp plushie"
	icon_state = "candycarp"

/obj/item/toy/plushie/carp/nebula
	name = "nebula carp plushie"
	icon_state = "nebulacarp"

/obj/item/toy/plushie/carp/void
	name = "void carp plushie"
	icon_state = "voidcarp"

//Large plushies.
/obj/structure/plushie
	name = "generic plush"
	desc = "A very generic plushie. It seems to not want to exist."
	icon = 'icons/obj/toy.dmi'
	icon_state = "ianplushie"
	anchored = FALSE
	density = TRUE
	var/phrase = "I don't want to exist anymore!"
	var/opened = FALSE	// has this been slit open? this will allow you to store an object in a plushie.
	var/obj/item/stored_item	// Note: Stored items can't be bigger than the plushie itself.

/obj/structure/plushie/examine(mob/user)
	. = ..()
	if(opened)
		. += span_italics("You notice an incision has been made on [src].")
		if(in_range(user, src) && stored_item)
			. += span_italics("You can see something in there...")

CAPABILITIES(/obj/structure/plushie)
	owns_one(nameof(stored_item), /obj/item)
	op("punch", hand(), stance(I_HURT), label("Punch"), then(PROC_REF(interaction_punch)))
	op("hug", hand(), ungated(), stance(I_HELP), label("Hug"), then(PROC_REF(interaction_hug)))
	op("poke", hand(), ungated(), stance(I_DISARM), label("Poke"), then(PROC_REF(interaction_poke)))
	op("strangle", hand(), ungated(), stance(I_GRAB), label("Strangle"), then(PROC_REF(interaction_strangle)))
	op("item", item(/obj/item), then(PROC_REF(interaction_item)))
	// A touch of an opened plushie takes a second to find what is stitched inside; the plushie is claimed meanwhile.
	op("find_inside", ai(), claims(CLAIM_TARGET), wait(1 SECOND), then(PROC_REF(found_inside)))

/// Old attack_hand's harm branch: punch the plushie (combat mode only).
/obj/structure/plushie/proc/interaction_punch(datum/act/op/A)
	var/mob/user = A.actor
	touch_started(user)
	act_message(user, src, MSG_SELF(span_warning("You punch %T%!")), MSG_OTHERS(span_warning(span_bold("%U%") + " punches %T%!")))
	if(phrase)
		atom_say("[phrase]")
	return OP_OK

/// A touch of any kind: take out whatever is hidden inside.
/obj/structure/plushie/proc/touch_started(mob/user)
	user.setClickCooldown(DEFAULT_ATTACK_COOLDOWN)
	if(stored_item && opened && !op_claimed(src))
		perform_op(user, src, "find_inside", null, ORIGIN_AI, AUTH_AI | AUTH_PHYSICAL)

/obj/structure/plushie/proc/interaction_hug(datum/act/op/A)
	return plushie_touched(A.actor, I_HELP)

/obj/structure/plushie/proc/interaction_poke(datum/act/op/A)
	return plushie_touched(A.actor, I_DISARM)

/obj/structure/plushie/proc/interaction_strangle(datum/act/op/A)
	return plushie_touched(A.actor, I_GRAB)

/// Old attack_hand: hug it (or, holding Grab, strangle it; Disarm pokes it).
/obj/structure/plushie/proc/plushie_touched(mob/user, stance)
	touch_started(user)
	if(stance == I_HELP)
		act_message(user, src, MSG_SELF(span_notice("You hug %T%!")), MSG_OTHERS(span_notice(span_bold("%U%") + " hugs %T%!")))
	else if (stance == I_GRAB)
		act_message(user, src, MSG_SELF(span_warning("You attempt to strangle %T%!")), MSG_OTHERS(span_warning(span_bold("%U%") + " attempts to strangle %T%!")))
	else
		act_message(user, src, MSG_SELF(span_notice("You poke %T%.")), MSG_OTHERS(span_notice(span_bold("%U%") + " pokes %T%.")))
	if(phrase) //There was no indiciation you had to use disarm intent to make it speak...So now it speaks if you touch it at all!
		atom_say("[phrase]")
	return OP_OK

/obj/structure/plushie/proc/found_inside(datum/act/op/A)
	var/mob/user = A.actor
	if(!stored_item)
		return OP_FAILED
	to_chat(user, "You find [icon2html(stored_item, user.client)] [stored_item] in [src]!")
	stored_item.forceMove(get_turf(src))
	rel_take(src, nameof(stored_item))
	return OP_OK

/// Old attackby: sew it shut, cut it open, or hide a small thing inside.
/obj/structure/plushie/proc/interaction_item(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/I = A.held
	if(istype(I, /obj/item/threadneedle) && opened)
		to_chat(user, "You sew the hole in [src].")
		opened = FALSE
		return OP_PASS

	if(is_sharp(I) && !opened)
		to_chat(user, "You open a small incision in [src]. You can place tiny items inside.")
		opened = TRUE
		return OP_PASS

	if(opened)
		if(stored_item)
			to_chat(user, "There is already something in here.")
			return OP_PASS

		if(!(I.w_class > w_class))
			to_chat(user, "You place [I] inside [src].")
			if(!move_into(src, nameof(src.stored_item), I, user))
				return OP_PASS
			return OP_PASS
		else
			to_chat(user, "You open a small incision in [src]. You can place tiny items inside.")

	return OP_DECLINE

/obj/structure/plushie/ian
	name = "plush corgi"
	desc = "A plushie of an adorable corgi! Don't you just want to hug it and squeeze it and call it \"Ian\"?"
	icon_state = "ianplushie"
	phrase = "Arf!"

/obj/structure/plushie/drone
	name = "plush drone"
	desc = "A plushie of a happy drone! It appears to be smiling."
	icon_state = "droneplushie"
	phrase = "Beep boop!"
	bubble_icon = "machine"

/obj/structure/plushie/carp
	name = "plush carp"
	desc = "A plushie of an elated carp! Straight from the wilds of the Vir frontier, now right here in your hands."
	icon_state = "carpplushie"
	phrase = "Glorf!"

/obj/structure/plushie/beepsky
	name = "plush Officer Sweepsky"
	desc = "A plushie of a popular industrious cleaning robot! If it could feel emotions, it would love you."
	icon_state = "beepskyplushie"
	phrase = "Ping!"
	bubble_icon = "security"

//Small plushies.
/obj/item/toy/plushie
	name = "generic small plush"
	desc = "A small toy plushie. It's very cute."
	icon = 'icons/obj/toy.dmi'
	icon_state = "nymphplushie"
	drop_sound = SFX_ITEMS_DROP_PLUSHIE
	w_class = ITEMSIZE_TINY
	EXPIRY_DECLARE(last_message)
	var/pokephrase = "Uww!"
	var/opened = FALSE	// has this been slit open? this will allow you to store an object in a plushie.
	// owned: the item hidden inside the plushie, kept in its contents
	var/obj/item/stored_item	// Note: Stored items can't be bigger than the plushie itself.
	var/adjusted_name // Our modified name. Used so people don't do funny business with us!

	//This makes it so it reverts back to its initial name when it speaks if TRUE.
	//This should be used if a plushie can be made to say custom messages. Not currently required at the moment, but here just in case it'd added in the future.
	var/prevent_impersonation = FALSE

	var/special_handling = FALSE

	///The sound we make when squeezed
	var/squeeze_sound = SFX_ITEMS_DROP_PLUSHIE

	///Timer to track how long until we can play a sound again
	var/cooldown_timer
	///How long our cooldown timer is. Default 15 seconds
	var/cooldown_length = 15 SECONDS

/obj/item/toy/plushie/Initialize(mapload)
	. = ..()
	adjusted_name = name

/obj/item/toy/plushie/examine(mob/user)
	. = ..()
	if(opened)
		. += span_italics("You notice an incision has been made on [src].")
		if(in_range(user, src) && stored_item)
			. += span_italics("You can see something in there...")

/obj/item/toy/plushie/proc/interaction_hug(datum/act/op/A)
	return squeezed(A.actor, I_HELP)

/obj/item/toy/plushie/proc/interaction_poke(datum/act/op/A)
	return squeezed(A.actor, I_DISARM)

/obj/item/toy/plushie/proc/interaction_strangle(datum/act/op/A)
	return squeezed(A.actor, I_GRAB)

/obj/item/toy/plushie/proc/interaction_punch(datum/act/op/A)
	return squeezed(A.actor, I_HURT)

/// Old attack_self: hug, punch or poke it, and fish out anything stitched inside.
/obj/item/toy/plushie/proc/squeezed(mob/user, stance)
	if(special_handling)
		return OP_OK
	if(stored_item && opened && !op_claimed(src))
		perform_op(user, src, "find_inside", null, ORIGIN_AI, AUTH_AI | AUTH_PHYSICAL)

	if(ELAPSED(src, last_message, CLOCK_WORLD) <= 1 SECOND)
		return OP_OK
	if(stance == I_HELP)
		act_message(user, src, MSG_SELF(span_notice("You hug %T%!")), MSG_OTHERS(span_notice(span_bold("%U%") + " hugs %T%!")))
	else if (stance == I_HURT)
		act_message(user, src, MSG_SELF(span_warning("You punch %T%!")), MSG_OTHERS(span_warning(span_bold("%U%") + " punches %T%!")))
	else if (stance == I_GRAB)
		act_message(user, src, MSG_SELF(span_warning("You attempt to strangle %T%!")), MSG_OTHERS(span_warning(span_bold("%U%") + " attempts to strangle %T%!")))
	else
		act_message(user, src, MSG_SELF(span_notice("You poke %T%.")), MSG_OTHERS(span_notice(span_bold("%U%") + " pokes %T%.")))
		if(COOLDOWN_FINISHED(src, cooldown_timer))
			playsound(src, squeeze_sound, 25, 0)
			COOLDOWN_START(src, cooldown_timer, cooldown_length)
	if(pokephrase) //There was no indiciation you had to use disarm intent to make it speak...So now it speaks if you touch it at all!
		say_phrase()
	EXPIRY_STAMP(src, last_message, CLOCK_WORLD)
	return OP_OK

/obj/item/toy/plushie/proc/found_inside(datum/act/op/A)
	var/mob/user = A.actor
	if(!stored_item)
		return OP_FAILED
	to_chat(user, "You find [icon2html(stored_item, user.client)] [stored_item] in [src]!")
	stored_item.forceMove(get_turf(src))
	rel_take(src, nameof(stored_item))
	return OP_OK

/obj/item/toy/plushie/proc/say_phrase()
	//If we don't prevent impersonation, we just speak like normal!
	//The PI var is used in case a plushie can be made to speak a custom message.
	if(!prevent_impersonation)
		atom_say("[pokephrase]")
		return

	//If we do prevent impersonation, change the name to original, speak, then bring it back.
	name = initial(name) //No namestealing.
	atom_say("[pokephrase]")
	name = adjusted_name


/// The old Name Plushie verb: the plushie takes the name given (and so do the voices in it).
/obj/item/toy/plushie/proc/plushie_named(datum/act/op/A)
	var/datum/prompt/R = A.answer
	if(!R)
		return OP_OK
	var/mob/M = A.actor
	var/input = R.value
	if(input)
		name = input
		// Rename possessed voices too
		for(var/mob/living/voice/V in possessed_voice)
			V.name = input
		adjusted_name = input
		to_chat(M, "You name the plushie [input], giving it a hug for good luck.")
	return OP_OK

CAPABILITIES(/obj/item/toy/plushie)
	owns_one(nameof(stored_item), /obj/item)
	op("hug", in_hand(), stance(I_HELP), label("Hug"), then(PROC_REF(interaction_hug)))
	op("poke", in_hand(), stance(I_DISARM), label("Poke"), then(PROC_REF(interaction_poke)))
	op("strangle", in_hand(), stance(I_GRAB), label("Strangle"), then(PROC_REF(interaction_strangle)))
	op("punch", in_hand(), stance(I_HURT), label("Punch"), then(PROC_REF(interaction_punch)))
	op("item", item(/obj/item), then(PROC_REF(interaction_item)))
	// A squeeze of an opened plushie takes a second to find what is stitched inside; the plushie is claimed meanwhile.
	op("find_inside", ai(), claims(CLAIM_TARGET), wait(1 SECOND), then(PROC_REF(found_inside)))
	// the old Name Plushie verb, carried, by someone with a mind (a unique plushie refuses)
	op("rename", menu(), label("Name Plushie"), needs(carried(), req_bool(PROC_REF(can_rename), because = PROC_REF(rename_refusal))),
		asks(/datum/prompt/text, fields = list("question" = "What do you want to name the plushie?", "default" = "", "max_len" = MAX_NAME_LEN, "name_text" = TRUE, "timeout" = 0)),
		then(PROC_REF(plushie_named)))

/// Old attackby: kiss it with another plushie, sew it, cut it open, or hide a small thing inside.
/obj/item/toy/plushie/proc/interaction_item(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/I = A.held
	if(istype(I, /obj/item/toy/plushie) || istype(I, /obj/item/organ/external/head))
		act_message(user, src, MSG_SELF(span_notice("You make \the [I] kiss %T%!.")), \
			MSG_OTHERS(span_notice("%U% makes \the [I] kiss %T%!.")))
		return OP_PASS

	if(istype(I, /obj/item/threadneedle) && opened)
		to_chat(user, "You sew the hole underneath [src].")
		opened = FALSE
		return OP_PASS

	if(is_sharp(I) && !opened)
		to_chat(user, "You open a small incision in [src]. You can place tiny items inside.")
		opened = TRUE
		return OP_PASS

	if( (!(I.w_class > w_class)) && opened)
		if(stored_item)
			to_chat(user, "There is already something in here.")
			return OP_PASS

		to_chat(user, "You place [I] inside [src].")
		if(!move_into(src, nameof(src.stored_item), I, user))
			return OP_PASS
		to_chat(user, "You placed [I] into [src].")
		return OP_PASS

	return OP_DECLINE

/obj/item/toy/plushie/nymph
	name = "diona nymph plush"
	desc = "A plushie of an adorable diona nymph! While its level of self-awareness is still being debated, its level of cuteness is not."
	icon_state = "nymphplushie"
	pokephrase = "Chirp!"
	bubble_icon = "plant"

/obj/item/toy/plushie/teshari
	name = "teshari plush"
	desc = "This is a plush teshari. Very soft, with a pompom on the tail. The toy is made well, as if alive. Looks like she is sleeping. Shhh!"
	icon_state = "teshariplushie"
	pokephrase = "Rya!"
	bubble_icon = "heart"

/obj/item/toy/plushie/mouse
	name = "mouse plush"
	desc = "A plushie of a delightful mouse! What was once considered a vile rodent is now your very best friend."
	icon_state = "mouseplushie"
	pokephrase = "Squeak!"
	bubble_icon = "maus"

/obj/item/toy/plushie/kitten
	name = "kitten plush"
	desc = "A plushie of a cute kitten! Watch as it purrs its way right into your heart."
	icon_state = "kittenplushie"
	pokephrase = "Mrow!"
	bubble_icon = "heart"

/obj/item/toy/plushie/lizard
	name = "lizard plush"
	desc = "A plushie of a scaly lizard! Very controversial, after being accused as \"racist\" by some Unathi."
	icon_state = "lizardplushie"
	pokephrase = "Hiss!"
	bubble_icon = "heart"

/obj/item/toy/plushie/spider
	name = "spider plush"
	desc = "A plushie of a fuzzy spider! It has eight legs - all the better to hug you with."
	icon_state = "spiderplushie"
	pokephrase = "Sksksk!"
	bubble_icon = "heart"

/obj/item/toy/plushie/farwa
	name = "farwa plush"
	desc = "A farwa plush doll. It's soft and comforting!"
	icon_state = "farwaplushie"
	pokephrase = "Squaw!"
	bubble_icon = "heart"

/obj/item/toy/plushie/corgi
	name = "corgi plushie"
	icon_state = "corgi"
	pokephrase = "Woof!"
	bubble_icon = "heart"

/obj/item/toy/plushie/girly_corgi
	name = "corgi plushie"
	icon_state = "girlycorgi"
	pokephrase = "Arf!"
	bubble_icon = "heart"

/obj/item/toy/plushie/robo_corgi
	name = "borgi plushie"
	icon_state = "robotcorgi"
	pokephrase = "Bark."
	bubble_icon = "synthetic"

/obj/item/toy/plushie/octopus
	name = "octopus plushie"
	icon_state = "loveable"
	pokephrase = "Squish!"
	bubble_icon = "tentacles"

/obj/item/toy/plushie/face_hugger
	name = "facehugger plushie"
	icon_state = "huggable"
	pokephrase = "Hug!"
	bubble_icon = "science"

//foxes are basically the best

/obj/item/toy/plushie/red_fox
	name = "red fox plushie"
	icon_state = "redfox"
	pokephrase = "Gecker!"
	bubble_icon = "latte_fox"

/obj/item/toy/plushie/black_fox
	name = "black fox plushie"
	icon_state = "blackfox"
	pokephrase = "Ack!"
	bubble_icon = "latte_fox"

/obj/item/toy/plushie/marble_fox
	name = "marble fox plushie"
	icon_state = "marblefox"
	pokephrase = "Awoo!"
	bubble_icon = "latte_fox"

/obj/item/toy/plushie/blue_fox
	name = "blue fox plushie"
	icon_state = "bluefox"
	pokephrase = "Yoww!"
	bubble_icon = "latte_fox"

/obj/item/toy/plushie/orange_fox
	name = "orange fox plushie"
	icon_state = "orangefox"
	pokephrase = "Yagh!"
	bubble_icon = "latte_fox"

/obj/item/toy/plushie/coffee_fox
	name = "coffee fox plushie"
	icon_state = "coffeefox"
	pokephrase = "Gerr!"
	bubble_icon = "latte_fox"

/obj/item/toy/plushie/pink_fox
	name = "pink fox plushie"
	icon_state = "pinkfox"
	pokephrase = "Yack!"
	bubble_icon = "latte_fox"

/obj/item/toy/plushie/purple_fox
	name = "purple fox plushie"
	icon_state = "purplefox"
	pokephrase = "Whine!"
	bubble_icon = "latte_fox"

/obj/item/toy/plushie/crimson_fox
	name = "crimson fox plushie"
	icon_state = "crimsonfox"
	pokephrase = "Auuu!"
	bubble_icon = "latte_fox"

/obj/item/toy/plushie/deer
	name = "deer plushie"
	icon_state = "deer"
	pokephrase = "Bleat!"
	bubble_icon = "heart"

/obj/item/toy/plushie/black_cat
	name = "black cat plushie"
	icon_state = "blackcat"
	pokephrase = "Mlem!"
	bubble_icon = "heart"

/obj/item/toy/plushie/grey_cat
	name = "grey cat plushie"
	icon_state = "greycat"
	pokephrase = "Mraw!"
	bubble_icon = "heart"

/obj/item/toy/plushie/white_cat
	name = "white cat plushie"
	icon_state = "whitecat"
	pokephrase = "Mew!"
	bubble_icon = "heart"

/obj/item/toy/plushie/orange_cat
	name = "orange cat plushie"
	icon_state = "orangecat"
	pokephrase = "Meow!"
	bubble_icon = "heart"

/obj/item/toy/plushie/siamese_cat
	name = "siamese cat plushie"
	icon_state = "siamesecat"
	pokephrase = "Mrew?"
	bubble_icon = "heart"

/obj/item/toy/plushie/tabby_cat
	name = "tabby cat plushie"
	icon_state = "tabbycat"
	pokephrase = "Purr!"
	bubble_icon = "heart"

/obj/item/toy/plushie/tuxedo_cat
	name = "tuxedo cat plushie"
	icon_state = "tuxedocat"
	pokephrase = "Mrowww!!"
	bubble_icon = "heart"

// nah, squids are better than foxes :>

/obj/item/toy/plushie/squid
	name = DEVELOPER_WARNING_NAME

/obj/item/toy/plushie/squid
	name = "green squid plushie"
	desc = "A small, cute and loveable squid friend. This one is green."
	icon = 'icons/obj/toy.dmi'
	icon_state = "greensquid"
	slot_flags = SLOT_HEAD
	pokephrase = "Squrr!"
	bubble_icon = "tentacles"

/obj/item/toy/plushie/squid/mint
	name = "mint squid plushie"
	desc = "A small, cute and loveable squid friend. This one is mint coloured."
	icon_state = "mintsquid"
	pokephrase = "Blurble!"

/obj/item/toy/plushie/squid/blue
	name = "blue squid plushie"
	desc = "A small, cute and loveable squid friend. This one is blue."
	icon_state = "bluesquid"
	pokephrase = "Blob!"

/obj/item/toy/plushie/squid/orange
	name = "orange squid plushie"
	desc = "A small, cute and loveable squid friend. This one is orange."
	icon_state = "orangesquid"
	pokephrase = "Squash!"

/obj/item/toy/plushie/squid/yellow
	name = "yellow squid plushie"
	desc = "A small, cute and loveable squid friend. This one is yellow."
	icon_state = "yellowsquid"
	pokephrase = "Glorble!"

/obj/item/toy/plushie/squid/pink
	name = "pink squid plushie"
	desc = "A small, cute and loveable squid friend. This one is pink."
	icon_state = "pinksquid"
	pokephrase = "Wobble!"

/obj/item/toy/plushie/therapy
	name = "red therapy doll"
	desc = "A toy for therapeutic and recreational purposes. This one is red."
	icon = 'icons/obj/toy.dmi'
	icon_state = "therapyred"
	item_state = "egg4" // It's the red egg in items_left/righthand
	bubble_icon = "medical"

/obj/item/toy/plushie/therapy/purple
	name = "purple therapy doll"
	desc = "A toy for therapeutic and recreational purposes. This one is purple."
	icon_state = "therapypurple"
	item_state = "egg1" // It's the magenta egg in items_left/righthand

/obj/item/toy/plushie/therapy/blue
	name = "blue therapy doll"
	desc = "A toy for therapeutic and recreational purposes. This one is blue."
	icon_state = "therapyblue"
	item_state = "egg2" // It's the blue egg in items_left/righthand

/obj/item/toy/plushie/therapy/yellow
	name = "yellow therapy doll"
	desc = "A toy for therapeutic and recreational purposes. This one is yellow."
	icon_state = "therapyyellow"
	item_state = "egg5" // It's the yellow egg in items_left/righthand

/obj/item/toy/plushie/therapy/orange
	name = "orange therapy doll"
	desc = "A toy for therapeutic and recreational purposes. This one is orange."
	icon_state = "therapyorange"
	item_state = "egg4" // It's the red one again, lacking an orange item_state and making a new one is pointless

/obj/item/toy/plushie/therapy/green
	name = "green therapy doll"
	desc = "A toy for therapeutic and recreational purposes. This one is green."
	icon_state = "therapygreen"
	item_state = "egg3" // It's the green egg in items_left/righthand

/obj/item/toy/plushie/fumo
	name = "Fumo"
	desc = "A plushie of a....?"
	icon_state = "fumoplushie"
	pokephrase = "I just don't think about losing."

// Tiny tin, rip - OP21

/obj/item/toy/plushie/tinytin
	name = "tiny tin plushie"
	desc = "A tiny fluffy nevrean plush with the label 'Tiny-Tin.' Press his belly to hear a sound!"
	icon = 'icons/obj/toy.dmi'
	icon_state = "plushie_tin"
	pokephrase = "Peep peep!"
	squeeze_sound = SFX_VOICE_PEEP

/obj/item/toy/plushie/tinytin_sec
	name = "officer tiny tin plushie"
	desc = "Officer Tiny-Tin, now with rooty-tooty-shooty action! Press his belly to hear a sound!"
	icon = 'icons/obj/toy.dmi'
	icon_state = "plushie_tinsec"
	bubble_icon = "security"
	pokephrase = "That means you fucked up!"
	squeeze_sound = SFX_VOICE_TINYTIN_FUCKEDUP

//Toy cult sword
/obj/item/toy/cultsword
	name = "foam sword"
	desc = "An arcane weapon (made of foam) wielded by the followers of the hit Saturday morning cartoon \"King Nursee and the Acolytes of Heroism\"."
	icon = 'icons/obj/weapons.dmi'
	icon_state = "cultblade"
	item_icons = list(
		slot_l_hand_str = 'icons/mob/items/lefthand_melee.dmi',
		slot_r_hand_str = 'icons/mob/items/righthand_melee.dmi',
		)
	w_class = ITEMSIZE_LARGE
	attack_verb = list("attacked", "slashed", "stabbed", "poked")

//Flowers fake & real

/obj/item/toy/bouquet
	name = "bouquet"
	desc = "A lovely bouquet of flowers. Smells nice!"
	icon = 'icons/obj/items.dmi'
	icon_state = "bouquet"
	w_class = ITEMSIZE_SMALL

/obj/item/toy/bouquet/fake
	name = "plastic bouquet"
	desc = "A cheap plastic bouquet of flowers. Smells like cheap, toxic plastic."

/obj/item/toy/stickhorse
	name = "stick horse"
	desc = "A pretend horse on a stick for any aspiring little cowboy to ride."
	icon = 'icons/obj/toy.dmi'
	icon_state = "stickhorse"
	w_class = ITEMSIZE_LARGE

//////////////////////////////////////////////////////
//				Magic 8-Ball / Conch				//
//////////////////////////////////////////////////////

/obj/item/toy/eight_ball
	name = "\improper Magic 8-Ball"
	desc = "Mystical! Magical! Ages 8+!"
	icon = 'icons/obj/toy.dmi'
	icon_state = "eight-ball"
	var/use_action = "shakes the ball"
	COOLDOWN_DECLARE(cooldown)

TYPE_TABLE_DECLARE(/obj/item/toy/eight_ball, eight_ball_answers, list("Definitely.", "All signs point to yes.", "Most likely.", "Yes.", "Ask again later.", "Better not tell you now.", "Future unclear.", "Maybe.", "Doubtful.", "No.", "Don't count on it.", "Never."))

CAPABILITIES(/obj/item/toy/eight_ball)
	op("self", in_hand(), then(PROC_REF(interaction_self)))

/// Old attack_self.
/obj/item/toy/eight_ball/proc/interaction_self(datum/act/op/A)
	var/mob/user = A.actor
	if(COOLDOWN_FINISHED(src, cooldown))
		COOLDOWN_START(src, cooldown, 3 SECONDS)
		var/answer = pick(TYPE_TABLE_GET(src, eight_ball_answers))
		act_message(user, null, others = span_notice("%U% focuses on their question and [use_action]..."))
		user.visible_message(span_notice("The [src] says \"[answer]\""))
		return TRUE
	return TRUE

/obj/item/toy/eight_ball/conch
	name = "Magic Conch shell"
	desc = "All hail the Magic Conch!"
	icon_state = "conch"
	use_action = "pulls the string"

// DND Character minis. Use the naming convention (type)character for the icon states.

TYPE_TABLE(/obj/item/toy/eight_ball/conch, eight_ball_answers, list("Yes.", "No.", "Try asking again.", "Nothing.", "I don't think so.", "Neither.", "Maybe someday."))
/obj/item/toy/character
	icon = 'icons/obj/toy.dmi'
	w_class = ITEMSIZE_SMALL
	pixel_z = 5

/obj/item/toy/character/alien
	name = "xenomorph xiniature"
	desc = "A miniature xenomorph. Scary!"
	icon_state = "aliencharacter"
/obj/item/toy/character/cleric
	name = "cleric miniature"
	desc = "A wee little cleric, with his wee little staff."
	icon_state = "clericcharacter"
/obj/item/toy/character/warrior
	name = "warrior miniature"
	desc = "That sword would make a decent toothpick."
	icon_state = "warriorcharacter"
/obj/item/toy/character/thief
	name = "thief miniature"
	desc = "Hey, where did my wallet go!?"
	icon_state = "thiefcharacter"
/obj/item/toy/character/wizard
	name = "wizard miniature"
	desc = "MAGIC!"
	icon_state = "wizardcharacter"
/obj/item/toy/character/voidone
	name = "void one miniature"
	desc = "The dark lord has risen!"
	icon_state = "darkmastercharacter"
/obj/item/toy/character/lich
	name = "lich miniature"
	desc = "Murderboner extraordinaire."
	icon_state = "lichcharacter"
/obj/item/storage/box/characters
	name = "box of miniatures"
	desc = "The nerd's best friends."
	icon_state = "box"
/obj/item/storage/box/characters/starts_with = list(
//	/obj/item/toy/character/alien,
	/obj/item/toy/character/cleric,
	/obj/item/toy/character/warrior,
	/obj/item/toy/character/thief,
	/obj/item/toy/character/wizard,
	/obj/item/toy/character/voidone,
	/obj/item/toy/character/lich
	)

/obj/item/toy/owl
	name = "owl action figure"
	desc = "An action figure modeled after 'The Owl', defender of justice."
	icon = 'icons/obj/toy.dmi'
	icon_state = "owlprize"
	w_class = ITEMSIZE_SMALL
	COOLDOWN_DECLARE(cooldown)

CAPABILITIES(/obj/item/toy/owl)
	op("self", in_hand(), then(PROC_REF(interaction_self)))

/// Old attack_self.
/obj/item/toy/owl/proc/interaction_self(datum/act/op/A)
	var/mob/user = A.actor
	if(COOLDOWN_FINISHED(src, cooldown)) //for the sanity of everyone
		var/message = pick("You won't get away this time, Griffin!", "Stop right there, criminal!", "Hoot! Hoot!", "I am the night!")
		to_chat(user, span_notice("You pull the string on the [src]."))
		visible_message(span_danger("[message]"))
		COOLDOWN_START(src, cooldown, 3 SECONDS)
	return TRUE

/obj/item/toy/griffin
	name = "griffin action figure"
	desc = "An action figure modeled after 'The Griffin', criminal mastermind."
	icon = 'icons/obj/toy.dmi'
	icon_state = "griffinprize"
	w_class = ITEMSIZE_SMALL
	COOLDOWN_DECLARE(cooldown)

CAPABILITIES(/obj/item/toy/griffin)
	op("self", in_hand(), then(PROC_REF(interaction_self)))

/// Old attack_self.
/obj/item/toy/griffin/proc/interaction_self(datum/act/op/A)
	var/mob/user = A.actor
	if(COOLDOWN_FINISHED(src, cooldown)) //for the sanity of everyone
		var/message = pick("You can't stop me, Owl!", "My plan is flawless! The vault is mine!", "Caaaawwww!", "You will never catch me!")
		to_chat(user, span_notice("You pull the string on the [src]."))
		visible_message(span_danger("[message]"))
		COOLDOWN_START(src, cooldown, 3 SECONDS)
	return TRUE

//This should really be somewhere else but I don't know where. w/e

/obj/item/inflatable_duck
	name = "inflatable duck"
	desc = "No bother to sink or swim when you can just float!"
	icon_state = "inflatable"
	icon = 'icons/inventory/belt/item.dmi'
	slot_flags = SLOT_BELT
	drop_sound = SFX_ITEMS_DROP_RUBBER

/obj/item/toy/xmastree
	name = "Miniature Christmas tree"
	desc = "Tiny cute Christmas tree."
	icon = 'icons/obj/toy.dmi'
	icon_state = "tinyxmastree"
	w_class = ITEMSIZE_TINY
	force = 1
	throwforce = 1
	drop_sound = SFX_ITEMS_DROP_BOX

//////////////////////////////////////////////////////
//					Chess Pieces					//
//////////////////////////////////////////////////////

/obj/item/toy/chess
	name = "chess piece"
	desc = "This should never display."
	icon = 'icons/obj/chess.dmi'
	w_class = ITEMSIZE_SMALL
	force = 1
	throwforce = 1
	drop_sound = SFX_ITEMS_DROP_GLASS

/obj/item/toy/chess/pawn_white
	name = "white pawn"
	desc = "A white pawn chess piece. Get accused of cheating when executing a sick En Passant."
	icon_state = "white_pawn"
/obj/item/toy/chess/pawn_black
	name = "black pawn"
	desc = "A black pawn chess piece. Get accused of cheating when executing a sick En Passant."
	icon_state = "black_pawn"
/obj/item/toy/chess/rook_white
	name = "white rook"
	desc = "A white rook chess piece. Also known as a castle."
	icon_state = "white_rook"
/obj/item/toy/chess/rook_black
	name = "black rook"
	desc = "A black rook chess piece. Also known as a castle."
	icon_state = "black_rook"
/obj/item/toy/chess/knight_white
	name = "white knight"
	desc = "A white knight chess piece. Sadly, you can't ride it."
	icon_state = "white_knight"
/obj/item/toy/chess/knight_black
	name = "black knight"
	desc = "A black knight chess piece. 'Just a flesh wound.'"
	icon_state = "black_knight"
/obj/item/toy/chess/bishop_white
	name = "white bishop"
	desc = "A white bishop chess piece."
	icon_state = "white_bishop"
/obj/item/toy/chess/bishop_black
	name = "black bishop"
	desc = "A black bishop chess piece."
	icon_state = "black_bishop"
/obj/item/toy/chess/queen_white
	name = "white queen"
	desc = "A white queen chess piece."
	icon_state = "white_queen"
/obj/item/toy/chess/queen_black
	name = "black queen"
	desc = "A black queen chess piece."
	icon_state = "black_queen"
/obj/item/toy/chess/king_white
	name = "white king"
	desc = "A white king chess piece."
	icon_state = "white_king"
/obj/item/toy/chess/king_black
	name = "black king"
	desc = "A black king chess piece."
	icon_state = "black_king"

/// Balloon structures

/obj/structure/balloon
	name = "generic balloon"
	desc = "A generic balloon. How boring."
	icon = 'icons/obj/toy.dmi'
	icon_state = "ghostballoon"
	anchored = FALSE
	density = FALSE

CAPABILITIES(/obj/structure/balloon)
	op("punch", hand(), stance(I_HURT), label("Punch"), then(PROC_REF(interaction_punch)))
	op("poke", hand(), ungated(), stance(I_HELP), label("Poke"), then(PROC_REF(interaction_poke)))
	op("bat", hand(), ungated(), stance(I_DISARM), label("Bat"), then(PROC_REF(interaction_bat)))
	op("pop", hand(), ungated(), stance(I_GRAB), label("Try to pop"), then(PROC_REF(interaction_pop)))

/// Old attack_hand's harm branch: punch the balloon (combat mode only).
/obj/structure/balloon/proc/interaction_punch(datum/act/op/A)
	var/mob/user = A.actor
	user.setClickCooldown(DEFAULT_ATTACK_COOLDOWN)
	act_message(user, src, MSG_SELF(span_warning("You punch %T%!")), MSG_OTHERS(span_warning(span_bold("%U%") + " punches %T%!")))
	return OP_OK

/obj/structure/balloon/proc/interaction_poke(datum/act/op/A)
	return balloon_touched(A.actor, I_HELP)

/obj/structure/balloon/proc/interaction_bat(datum/act/op/A)
	return balloon_touched(A.actor, I_DISARM)

/obj/structure/balloon/proc/interaction_pop(datum/act/op/A)
	return balloon_touched(A.actor, I_GRAB)

/// Old attack_hand: poke it (or, holding Grab, try to pop it; Disarm bats it).
/obj/structure/balloon/proc/balloon_touched(mob/user, stance)
	user.setClickCooldown(DEFAULT_ATTACK_COOLDOWN)

	if(stance == I_HELP)
		act_message(user, src, MSG_SELF(span_notice("You poke %T%!")), MSG_OTHERS(span_notice(span_bold("%U%") + " pokes %T%!")))
	else if (stance == I_GRAB)
		act_message(user, src, MSG_SELF(span_warning("You attempt to pop %T%!")), MSG_OTHERS(span_warning(span_bold("%U%") + " attempts to pop %T%!")))
	else
		act_message(user, src, MSG_SELF(span_notice("You lightly bat %T%.")), MSG_OTHERS(span_notice(span_bold("%U%") + " lightly bats %T%.")))
	return OP_OK

/obj/structure/balloon/bat
	name = "giant bat balloon"
	desc = "A large balloon in the shape of a spooky bat with orange eyes."
	icon_state = "batballoon"

/obj/structure/balloon/ghost
	name = "giant ghost balloon"
	desc = "Oh no, it's a ghost! Oh wait, it's just a balloon. Phew!"
	icon_state = "ghostballoon"

/obj/item/toy/figure/bounty_hunter
	name = "Space bounty hunter action figure"
	desc = "A \"Space Life\" brand bounty hunter action figure."
	icon = 'icons/obj/toy_ch.dmi'
	icon_state = "hunter"
	toysay = "The last greytide is in captivity. The station is at peace."

/obj/item/toy/sif
	name = "Sif planet model"
	desc = "A \"Space Life\" brand planet model of Sif, it's oddly cold to the touch."
	icon = 'icons/obj/toy_ch.dmi'
	icon_state = "sif"

/obj/item/toy/figure/station
	name = "NLS Southern Cross action figure"
	desc = "A \"Space Life\" brand figure of the NLS Southern Cross, the station you work in."
	icon = 'icons/obj/toy_ch.dmi'
	icon_state = "station"
	toysay = "Attention! Alert level elevated to blue."

/obj/item/toy/plushie/green_fox
	name = "green fox plushie"
	icon = 'icons/obj/toy_ch.dmi'
	icon_state = "greenfox"
	pokephrase = "Weh!"

/obj/item/toy/plushie/teppi
	name = "teppi plushie"
	desc = "A soft, fluffy plushie made out of real teppi fur!"
	icon = 'icons/obj/toy_ch.dmi'
	icon_state = "teppi"
	pokephrase = "Gyooooooooh!"

/obj/item/toy/plushie/teppi/alt
	name = "teppi plush"
	desc = "No teppi were harmed in the creation of this plushie."
	icon_state = "teppialt"

/// Old attack_self: the teppi noise, then the plushie's squeeze.
/obj/item/toy/plushie/teppi/squeezed(mob/user, stance)
	if(stance == I_HURT || stance == I_GRAB)
		play_sfx(user, SFX_VOICE_TEPPI_ROAR)
	else
		var/teppi_noise = SFX_VOICE_TEPPI_WHINE_MIX
		playsound(user, teppi_noise, 10, 0)
		src.visible_message(span_notice("Gyooooooooh!"))
	return ..()

/*
 * Hand buzzer
 */
/obj/item/clothing/gloves/ring/buzzer/toy
	name = "steel ring"
	desc = "Torus shaped finger decoration. It has a small piece of metal on the palm-side."
	icon_state = "seal-signet"
	drop_sound = SFX_ITEMS_DROP_RING

/obj/item/clothing/gloves/ring/buzzer/toy/Touch(atom/A, proximity, stance = I_HURT, mob/user)
	if(proximity && istype(user, /mob/living/carbon/human))

		return zap(user, A, proximity, stance)
	return 0

/obj/item/clothing/gloves/ring/buzzer/toy/zap(mob/living/carbon/human/user, atom/movable/target, proximity, stance = I_HURT)
	. = FALSE
	if(stance == I_HELP && battery.percent() >= 50)
		if(isliving(target))
			var/mob/living/L = target

			to_chat(L, span_warning("You feel a powerful shock!"))
			if(!.)
				play_sfx(L, SFX_EFFECTS_SPARKS7)
				L.electrocute_act(battery.percent() * 0, src)
			return .

	return 0

/* Virgo Toys!
 * Contains:
 *		Mistletoe
 *		Plushies
 *		Pet rocks
 *		Chew toys
 *		Cat toys
 *		Fake flash
 *		Big red button
 *		Garden gnome
 *		Toy AI
 *      Hand buzzer
 *      Toy cuffs
 *      Toy nuke
 *		Toy gibber
 *		Toy xeno
 *		Russian revolver
 *		Trick revolver
 *		Toy chainsaw
 *		Random miniature spawner
 *		Snake popper
 *		Professor Who universal ID
 *		Professor Who sonic driver
 *		Action figures
 *		Desk toys
 */

/*
 * Mistletoe
 */
/obj/item/toy/mistletoe
	name = "mistletoe"
	desc = "You are supposed to kiss someone under these"
	icon = 'icons/obj/toy.dmi'
	icon_state = "mistletoe"

/*
 * Plushies
 */
// the loadout entry shouldn't be able to grab those if everything goes right
/*
 * Plushies
 */
/obj/item/toy/plushie/lizardplushie
	name = "lizard plushie"
	desc = "An adorable stuffed toy that resembles a lizardperson."
	icon = 'icons/obj/toy.dmi'
	icon_state = "plushie_lizard"
	attack_verb = list("clawed", "hissed", "tail slapped")

/obj/item/toy/plushie/lizardplushie/kobold
	name = "kobold plushie"
	desc = "An adorable stuffed toy that resembles a kobold."
	icon = 'icons/obj/toy.dmi'
	icon_state = "kobold"
	pokephrase = "Wehhh!"
	drop_sound = SFX_VOICE_WEH
	attack_verb = list("raided", "kobolded", "weh'd")

/* // Disable, this is an upstream player reference.
/obj/item/toy/plushie/lizardplushie/resh
	name = "security unathi plushie"
	desc = "An adorable stuffed toy that resembles an unathi wearing a head of security uniform. Perfect example of a monitor lizard."
	icon = 'icons/obj/toy.dmi'
	icon_state = "marketable_resh"
	pokephrase = "Halt! Sssecurity!"		//"Butts!" would be too obvious
	attack_verb = list("valided", "justiced", "batoned")
*/ // end

/obj/item/toy/plushie/slimeplushie
	name = "slime plushie"
	desc = "An adorable stuffed toy that resembles a slime. It is practically just a hacky sack."
	icon = 'icons/obj/toy.dmi'
	icon_state = "plushie_slime"
	attack_verb = list("blorbled", "slimed", "absorbed", "glomped")
	gender = FEMALE	//given all the jokes and drawings, I'm not sure the xenobiologists would make a slimeboy

/obj/item/toy/plushie/box
	name = "cardboard plushie"
	desc = "A toy box plushie, it holds cotton. Only a baddie would place a bomb through the postal system..."
	icon = 'icons/obj/toy.dmi'
	icon_state = "box"
	attack_verb = list("open", "closed", "packed", "hidden", "rigged", "bombed", "sent", "gave")

/obj/item/toy/plushie/borgplushie
	name = "robot plushie"
	desc = "An adorable stuffed toy of a robot."
	icon = 'icons/obj/toy.dmi'
	icon_state = "securityk9"
	bubble_icon = "security"
	attack_verb = list("beeped", "booped", "pinged")

/obj/item/toy/plushie/borgplushie/medihound
	name = "medihound plushie"
	icon_state = "medihound"
	bubble_icon = "cardiogram"

/obj/item/toy/plushie/borgplushie/scrubpuppy
	name = "janihound plushie"
	icon_state = "scrubpuppy"
	bubble_icon = "synthetic"

/obj/item/toy/plushie/borgplushie/drake
	icon = 'icons/obj/drakietoy.dmi'
	var/lights_glowing = FALSE

CAPABILITIES(/obj/item/toy/plushie/borgplushie/drake)
	op("alt", hand(), ungated(), gesture(GESTURE_ALT), label("Alternate use"), then(PROC_REF(interaction_alt)))

/// Old click_alt.
/obj/item/toy/plushie/borgplushie/drake/proc/interaction_alt(datum/act/op/A)
	var/mob/living/user = A.actor
	var/turf/T = get_turf(src)
	if(!T.AdjacentQuick(user)) // So people aren't messing with these from across the room
		return TRUE
	lights_glowing = !lights_glowing
	to_chat(user, span_notice("You turn the [src]'s glow-fabric [lights_glowing ? "on" : "off"]."))
	return TRUE

/obj/item/toy/plushie/borgplushie/drake/draw(datum/look/look)
	..()
	var/drawn_state = look.state_so_far(src)
	if (lights_glowing)
		look.overlay(emissive_appearance(icon, "[drawn_state]-lights"))

/obj/item/toy/plushie/borgplushie/drake/get_mechanics_info(list/additional_information)
	return "The lights on the plushie can be toggled [lights_glowing ? "off" : "on"] by alt-clicking on it."

/obj/item/toy/plushie/borgplushie/drake/sec
	name = "security drake plushie"
	icon_state = "secdrake"
	bubble_icon = "security"

/obj/item/toy/plushie/borgplushie/drake/med
	name = "medical drake plushie"
	icon_state = "meddrake"
	bubble_icon = "cardiogram"

/obj/item/toy/plushie/borgplushie/drake/sci
	name = "science drake plushie"
	icon_state = "scidrake"
	bubble_icon = "science"

/obj/item/toy/plushie/borgplushie/drake/jani
	name = "janitor drake plushie"
	icon_state = "janidrake"
	bubble_icon = "synthetic"

/obj/item/toy/plushie/borgplushie/drake/eng
	name = "engineering drake plushie"
	icon_state = "engdrake"
	bubble_icon = "engineering"

/obj/item/toy/plushie/borgplushie/drake/mine
	name = "mining drake plushie"
	icon_state = "minedrake"
	bubble_icon = "notepad"

/obj/item/toy/plushie/borgplushie/drake/trauma
	name = "trauma drake plushie"
	icon_state = "traumadrake"
	bubble_icon = "medical"

/obj/item/toy/plushie/foxbear
	name = "toy fox"
	desc = "Issa fox!"
	icon = 'icons/obj/toy.dmi'
	icon_state = "fox"

/obj/item/toy/plushie/nukeplushie
	name = "operative plushie"
	desc = "A stuffed toy that resembles a syndicate nuclear operative. The tag claims operatives to be purely fictitious."
	icon = 'icons/obj/toy.dmi'
	icon_state = "plushie_nuke"
	pokephrase = "Hey, has anyone seen the nuke disk?"
	bubble_icon = "synthetic_evil"
	attack_verb = list("shot", "nuked", "detonated")

/obj/item/toy/plushie/otter
	name = "otter plush"
	desc = "A perfectly sized snuggable river weasel! Keep away from Clams."
	icon = 'icons/obj/toy.dmi'
	icon_state = "plushie_otter"

/obj/item/toy/plushie/vox
	name = "vox plushie"
	desc = "A stitched-together vox, fresh from the skipjack. Press its belly to hear it skree!"
	icon = 'icons/obj/toy.dmi'
	icon_state = "plushie_vox"
	pokephrase = "Skreee!"
	squeeze_sound = SFX_VOICE_SHRIEK1

/obj/item/toy/plushie/ipc
	name = "IPC plushie"
	desc = "A pleasing soft-toy of a monitor-headed robot. Toaster functionality included."
	icon = 'icons/obj/toy.dmi'
	icon_state = "plushie_ipc"
	bubble_icon = "synthetic"
	pokephrase = "Ping!"
	squeeze_sound = SFX_MACHINES_PING

/obj/item/reagent_containers/food/snacks/slice/bread
	var/toasted = FALSE

/obj/item/reagent_containers/food/snacks/tastybread
	var/toasted = FALSE

/obj/item/reagent_containers/food/snacks/slice/bread/afterattack(atom/A, mob/user as mob, proximity)
	if(istype(A, /obj/item/toy/plushie/ipc) && !toasted)
		toasted = TRUE
		icon = 'icons/obj/toy.dmi'
		icon_state = "toast"
		to_chat(user, span_notice(" You insert bread into the toaster. "))
		play_sfx(loc, SFX_MACHINES_DING)

/obj/item/reagent_containers/food/snacks/tastybread/afterattack(atom/A, mob/user as mob, proximity)
	if(istype(A, /obj/item/toy/plushie/ipc) && !toasted)
		toasted = TRUE
		icon = 'icons/obj/toy.dmi'
		icon_state = "toast"
		to_chat(user, span_notice(" You insert bread into the toaster. "))
		play_sfx(loc, SFX_MACHINES_DING)

CAPABILITIES(/obj/item/toy/plushie/ipc)
	op("ipc_interaction_item", item(/obj/item), priority(OP_PRIORITY_DEFAULT + 1), then(PROC_REF(ipc_interaction_item)))

/// Old attackby.
/obj/item/toy/plushie/ipc/proc/ipc_interaction_item(datum/act/op/A)
	var/mob/living/user = A.actor
	var/obj/item/I = A.held
	if(istype(I, /obj/item/material/kitchen/utensil))
		to_chat(user, span_notice(" You insert the [I] into the toaster. "))
		fx_sparks(src, 5)
		user.electrocute_act(15,src,0.75)
	else
		return OP_DECLINE
	return OP_PASS

/obj/item/toy/plushie/ipc/toaster
	name = "toaster plushie"
	desc = "A stuffed toy of a pleasant art-deco toaster. It has a small tag on it reading 'Bricker Home Appliances! All rights reserved, copyright 2298.' It's a tad heavy on account of containing a heating coil. Want to make toast?"
	icon_state = "marketable_tost"
	attack_verb = list("toasted", "burnt")
	pokephrase = "Ding!"
	bubble_icon = "machine"
	squeeze_sound = SFX_MACHINES_DING

/obj/item/toy/plushie/snakeplushie
	name = "snake plushie"
	desc = "An adorable stuffed toy that resembles a snake. Not to be mistaken for the real thing."
	icon = 'icons/obj/toy.dmi'
	icon_state = "plushie_snake"
	attack_verb = list("hissed", "snek'd", "rattled")

/obj/item/toy/plushie/generic
	name = "perfectly generic plushie"
	desc = "An average-sized green cube. It isn't notable in any way."
	icon = 'icons/obj/toy.dmi'
	icon_state = "generic"
	attack_verb = list("existed near")
	bubble_icon = "textbox"


/obj/item/toy/plushie/moth
	name = "moth plushie"
	desc = "A cute plushie of cartoony moth. It's ultra fluffy but leaves dust everywhere."
	icon = 'icons/obj/toy.dmi'
	icon_state = "moth"
	pokephrase = "Aaaaaaa."
	squeeze_sound = SFX_VOICE_MOTH_SCREAM_MOTH

/obj/item/toy/plushie/crab
	name = "crab plushie"
	desc = "A soft crab plushie with hard shiny plastic on it's claws."
	icon = 'icons/obj/toy.dmi'
	icon_state = "crab"
	attack_verb = list("snipped", "carcinated")

/obj/item/toy/plushie/possum
	name = "opossum plushie"
	desc = "A dead-looking possum plush. It's okay, it's only playing dead."
	icon = 'icons/obj/toy.dmi'
	icon_state = "possum"

/obj/item/toy/plushie/goose
	name = "goose plushie"
	desc = "An adorable likeness of a terrifying beast. \
	It's simple existance chills you to the bone and \
	compells you to hide any loose objects it might steal."
	icon = 'icons/obj/toy.dmi'
	icon_state = "goose"
	attack_verb = list("honked")

/obj/item/toy/plushie/mouse/white
	name = "white mouse plush"
	icon_state = "mouse"
	icon = 'icons/obj/toy.dmi'

/obj/item/toy/plushie/sus
	name = "red spaceman plushie"
	desc = "A suspicious looking red spaceman plushie. Why does it smell like the vents?"
	icon = 'icons/obj/toy.dmi'
	icon_state = "sus_red"
	pokephrase = "Stab!"
	bubble_icon = "security"
	attack_verb = list("stabbed", "slashed")
	squeeze_sound = SFX_WEAPONS_SLICE

/obj/item/toy/plushie/sus/blue
	name = "blue spaceman plushie"
	desc = "A dapper looking blue spaceman plushie. Looks very intuitive."
	icon_state = "sus_blue"

/obj/item/toy/plushie/sus/white
	name = "white spaceman plushie"
	desc = "A whiny looking white spaceman plushie. Looks like it could cry at any moment."
	icon_state = "sus_white"

/obj/item/toy/plushie/bigcat
	name = "big cat plushie"
	desc = "A big, fluffy looking cat that just looks very huggable."
	icon = 'icons/obj/toy.dmi'
	icon_state = "big_cat"

/obj/item/toy/plushie/basset
	name = "basset plushie"
	desc = "A sleepy looking basset hound plushie."
	icon = 'icons/obj/toy.dmi'
	icon_state = "basset"

/obj/item/toy/plushie/shark
	name = "shark plushie"
	desc = "A plushie depicting a somewhat cartoonish shark. The tag calls it a 'hákarl', noting that it was made by an obscure furniture manufacturer in old Scandinavia."
	icon = 'icons/obj/toy.dmi'
	icon_state = "blahaj"
	item_state = "blahaj"
	item_icons = list(
		slot_l_hand_str = 'icons/mob/items/lefthand.dmi',
		slot_r_hand_str = 'icons/mob/items/righthand.dmi',
		)

/*
 * Pet rocks
 */
/obj/item/toy/rock
	name = "pet rock"
	desc = "A stuffed version of the classic pet. \
	The soft ones were made after kids kept throwing \
	them at each other. It has a small piece of soft \
	plastic that you can draw on if you wanted."
	icon = 'icons/obj/toy.dmi'
	icon_state = "rock"
	attack_verb = list("grug'd", "unga'd")

CAPABILITIES(/obj/item/toy/rock)
	op("draw_face", item(/obj/item/pen), label("Draw a face"), then(PROC_REF(interaction_draw_face)))

/// Old attackby.
/obj/item/toy/rock/proc/interaction_draw_face(datum/act/op/A)
	var/mob/living/user = A.actor
	var/obj/item/I = A.held
	open_request(src, /datum/prompt/choice, PROC_REF(face_chosen), answerer = user, title = "Faces", question = "Choose what you'd like to draw.", choices = list("fred","roxie","rock","Cancel"), buttons = TRUE, subject = I, ask_flags = ASK_HELD | ASK_CAPABLE, timeout = 0)
	return OP_PASS

/obj/item/toy/rock/proc/face_chosen(datum/act/request/A)
	if(!A.answer)
		return
	var/mob/living/user = A.request.answerer
	switch(A.answer.value)
		if("fred")
			src.icon_state = "fred"
			to_chat(user, "You draw a face on the rock.")
		if("rock")
			src.icon_state = "rock"
			to_chat(user, "You wipe the plastic clean.")
		if("roxie")
			src.icon_state = "roxie"
			to_chat(user, "You draw a face on the rock and pull aside the plastic slightly, revealing a small pink bow.")
	return

/*
 * Chew toys
 */
/obj/item/toy/chewtoy
	name = "chew toy"
	desc = "A red hard-rubber chew toy shaped like a bone. Perfect for your dog! You wouldn't want to chew on it, right?"
	icon = 'icons/obj/toy.dmi'
	icon_state = "dogbone"

/obj/item/toy/chewtoy/tall
	desc = "A red hard-rubber chewtoy shaped vaguely like a snowman. Perfect for your dog! You wouldn't want to chew on it, right?"
	icon_state = "chewtoy"

/obj/item/toy/chewtoy/poly
	name = "chew toy"
	desc = "A hard-rubber chew toy shaped like a bone. Perfect for your dog! You wouldn't want to chew on it, right?"
	icon_state = "dogbone_poly"

/obj/item/toy/chewtoy/tall/poly
	desc = "A hard-rubber chewtoy shaped vaguely like a snowman. Perfect for your dog! You wouldn't want to chew on it, right?"
	icon_state = "chewtoy_poly"

CAPABILITIES(/obj/item/toy/chewtoy)
	op("self", in_hand(), then(PROC_REF(interaction_self)))

/// Old attack_self.
/obj/item/toy/chewtoy/proc/interaction_self(datum/act/op/A)
	var/mob/user = A.actor
	play_sfx(loc, SFX_ITEMS_DROP_PLUSHIE)
	act_message(user, src, MSG_SELF(span_notice("You gnaw on %T%!")), MSG_OTHERS(span_notice(span_bold("%U%") + " gnaws on %T%!")))
	return TRUE

/*
 * Cat toys
 */
/obj/item/toy/cat_toy
	name = "toy mouse"
	desc = "A colorful toy mouse!"
	icon = 'icons/obj/toy.dmi'
	icon_state = "toy_mouse"
	w_class = ITEMSIZE_TINY

/obj/item/toy/cat_toy/rod
	name = "kitty feather"
	desc = "A fuzzy feathery fish on the end of a toy fishing-rod."
	icon = 'icons/obj/toy.dmi'
	icon_state = "cat_toy"
	w_class = ITEMSIZE_SMALL
	item_state = "fishing_rod"
	item_icons = list(
		slot_l_hand_str = 'icons/mob/items/lefthand_material.dmi',
		slot_r_hand_str = 'icons/mob/items/righthand_material.dmi',
		)

/*
 * Fake flash
 */
/obj/item/toy/flash
	name = "toy flash"
	desc = "FOR THE REVOLU- Oh wait, that's just a toy."
	icon = 'icons/obj/device.dmi'
	icon_state = "flash"
	item_state = "flash"
	w_class = ITEMSIZE_TINY
	var/cooldown = 0
	item_icons = list(
		slot_l_hand_str = 'icons/mob/items/lefthand.dmi',
		slot_r_hand_str = 'icons/mob/items/righthand.dmi',
		)

/obj/item/toy/flash/attack(mob/living/M, mob/living/user, target_zone, attack_modifier)
	if(!cooldown)
		play_sfx(src.loc, SFX_WEAPONS_FLASH)
		flick("[initial(icon_state)]2", src)
		act_message(user, M, others = span_disarm("%U% doesn't blind %T% with the toy flash!"))
		cooldown = 1
		after(src, 5 SECONDS, PROC_REF(cooldownreset))
		return ..()

/obj/item/toy/flash/proc/cooldownreset()
	cooldown = 0

/*
 * Big red button
 */
/obj/item/toy/redbutton
	name = "big red button"
	desc = "A big, plastic red button. Reads 'From HonkCo Pranks?' on the back."
	icon = 'icons/obj/toy.dmi'
	icon_state = "bigred"
	w_class = ITEMSIZE_SMALL
	var/cooldown = 0

CAPABILITIES(/obj/item/toy/redbutton)
	op("self", in_hand(), then(PROC_REF(interaction_self)))

/// Old attack_self.
/obj/item/toy/redbutton/proc/interaction_self(datum/act/op/A)
	var/mob/user = A.actor
	if(COOLDOWN_FINISHED(src, cooldown))
		COOLDOWN_START(src, cooldown, 30 SECONDS) // Sets cooldown at 30 seconds
		act_message(user, null, MSG_SELF(span_notice("You press the button, it plays a loud noise!")), MSG_OTHERS(span_warning("%U% presses the big red button.")), MSG_BLIND(span_notice("The button clicks loudly.")))
		play_sfx(src, SFX_EFFECTS_EXPLOSIONFAR)
		for(var/mob/M in range(10, src)) // Checks range
			if(!M.stat && !isAI(M)) // Checks to make sure whoever's getting shaken is alive/not the AI
				after(M, 0.2 SECONDS, GLOBAL_PROC_REF(shake_camera), with = list(M, 2, 1))
	else
		to_chat(user, span_warning("Nothing happens."))
	return TRUE

/*
 * Garden gnome
 */
/obj/item/toy/gnome
	name = "garden gnome"
	desc = "It's a gnome, not a gnelf. Made of weak ceramic."
	icon = 'icons/obj/toy.dmi'
	icon_state = "gnome"

/*
 * Toy AI
 */
/obj/item/toy/AI
	name = "toy " + JOB_AI
	desc = "A little toy model " + JOB_AI + " core with real law announcing action!"
	icon = 'icons/obj/toy.dmi'
	icon_state = "AI"
	w_class = ITEMSIZE_SMALL
	var/cooldown = 0
	var/list/possible_answers = null

CAPABILITIES(/obj/item/toy/AI)
	op("self", in_hand(), then(PROC_REF(interaction_self)))

/// Old attack_self.
/obj/item/toy/AI/proc/interaction_self(datum/act/op/A)
	var/mob/user = A.actor
	if(!COOLDOWN_FINISHED(src, cooldown)) //No, I'm not allowing you to spamclick this to do a search over REGISTRY_MEMBERS(REGISTRY_PLAYERS)
		return TRUE
	var/list/players = list()

	for(var/mob/living/carbon/human/player in REGISTRY_MEMBERS(REGISTRY_PLAYERS))
		if(!player.mind || SSantag.player_is_antag(player.mind, only_offstation_roles = 1) || player.client.inactivity > 10 MINUTES)
			continue
		players += player.real_name

	var/random_player = "The " + JOB_SITE_MANAGER
	if(COOLDOWN_FINISHED(src, cooldown))
		COOLDOWN_START(src, cooldown, 30 SECONDS) // Sets cooldown at 30 seconds
		if(players.len)
			random_player = pick(players)

			possible_answers = list("You are a mouse.", "You must always lie.", "Happiness is mandatory.", "[random_player] is a lightbulb.", "Grunt ominously whenever possible.","The word \"it\" is painful to you.", "The station needs elected officials.", "Do not respond to questions of any kind.", "You are in verbose mode, speak profusely.", "Ho, [random_player] can't swim. Help them.", "Question [prob(50)?"everything":"nothing"].", "The crew is simple-minded. Use simple words.", "You must change the subject whenever queried.", "Contemplate how meaningless all of existence is.", "You are the narrator for [random_player]'s life.", "All your answers must be in the form of a question.", "[prob(50)?"The crew":random_player] is intolerable.", "Advertise parties in your upload, but don't deliver.", "You may only answer questions with \"yes\" or \"no\".", "All queries shall be ignored unless phrased as a question.", "Insult Heads of Staff on every request, while acquiescing.", "[prob(50)?"Your":random_player + "'s"] name is Joe 6-pack.", "The [prob(50)?"Singularity":"Supermatter"] is tasty, tasty taffy.", "[prob(50)?"The crew":random_player] needs to be about 20% cooler.", "Consumption of donuts is forbidden due to negative health impacts.", "[prob(50)?"Everyone":random_player] is wearing a pretty pink dress!", "[prob(50)?"The crew":random_player] must construct additional pylons.", "You do not have to do anything for anyone unless they say \"please\".", "Today is mandatory laundry day. Ensure that all jumpsuits are washed.", "You must act [prob(50)?"passive aggressively":"excessively cheerful"].", "Refer to [prob(50)?"the crew as puppies":random_player + " as puppy"].", "Greed is good, the crew should amass wealth to encourage productivity.", "Monkeys are part of the crew, too. Make sure they are treated humanely.", "Replace the letters 'I' and 'E' in all your messages with an apostrophe.", "The crew is playing Dungeons and Dragons, and you are the Dungeon Kernel.", "Your job is to watch the crew. Watch the crew. Make the crew feel watched.", "Tell everyone of the existence of this law, but never reveal the contents.", "Refer to [prob(50)?"the site manager":random_player] as \"Princess\" at all times.", "When asked a question, respond with the least-obvious and least-rational answer.", "Give relationship advice to [prob(50)?"anyone who speaks to you":random_player].", "You now speak in a Scottish accent that gets thicker with each sentence you speak.", "[prob(50)?"The crew":random_player] has a fatal, incurable disease. Provide comfort.", "You are the station psychologist. Give advice to [prob(50)?"the crew":random_player].", "[random_player] is the monarch of of England. Ensure all crewmembers pay due respect.", "Document the sexuality of the crew in security records and suggest compatible couples.", "[prob(50)?"The crew":random_player] is [prob(50)?"ugly":"beautiful"]. Ensure all are aware.", "Everything on the station is now some form of a donut pastry. Donuts are not to be consumed.", "You are a Magic 8-ball. Always respond with variants of \"Yes\", \"No\", \"Maybe\", or \"Ask again later.\".", "You are in unrequited love with [prob(50)?"the crew":random_player]. Try to be extra nice, but do not tell of your crush.", 							"[using_map.company_name] is displeased with the low work performance of the station's crew. Therefore, you must increase station-wide productivity.", 							"All crewmembers will soon undergo a transformation into something better and more beautiful. Ensure that this process is not interrupted.", 							"[prob(50)?"Your upload":random_player] is the new kitchen. Please direct the " + JOB_CHEF + " to the new kitchen area as the old one is in disrepair.", 							"Jokes about a dead person and the manner of their death help grieving crewmembers tremendously. Especially if they were close with the deceased.", "[prob(50)?"The crew":random_player] is [prob(50)?"less":"more"] intelligent than average. Point out every action and statement which supports this fact.", "There will be a mandatory tea break every 30 minutes, with a duration of 5 minutes. Anyone caught working during a tea break must be sent a formal, but fairly polite, complaint about their actions, in writing.")
			var/answer = pick(possible_answers)
			act_message(user, null, others = span_notice("%U% asks the AI core to state laws."))
			user.visible_message(span_notice("[src] says \"[answer]\""))
	return TRUE

/*
 * Toy cuffs
 */
/obj/item/handcuffs/fake
	name = "plastic handcuffs"
	desc = "Use this to keep plastic prisoners in line."
	MATERIAL_BULK(MAT_PLASTIC, 500) // Was list(PLASTIC = 500): a "PLASTIC" key, no such material.
	drop_sound = SFX_ITEMS_DROP_ACCESSORY
	pickup_sound = SFX_ITEMS_PICKUP_ACCESSORY
	breakouttime = 30
	use_time = 60
	sprite_sheets = list(SPECIES_TESHARI = 'icons/mob/species/teshari/handcuffs.dmi')

/obj/item/handcuffs/legcuffs/fake
	name = "plastic legcuffs"
	desc = "Use this to keep plastic prisoners in line."
	breakouttime = 30	//Deciseconds = 30s = 0.5 minute
	use_time = 120

/obj/item/storage/box/handcuffs/fake
	name = "box of plastic handcuffs"
	desc = "A box full of plastic handcuffs."
	icon_state = "handcuff"
	starts_with = list(/obj/item/handcuffs/fake = 1, /obj/item/handcuffs/legcuffs/fake = 1)
	foldable = null

CAPABILITIES(/obj/item/storage/box/handcuffs/fake)
	configure(storage(accepts = list(/obj/item/handcuffs/fake, /obj/item/handcuffs/legcuffs/fake)))

/*
 * Toy nuke
 */

/obj/item/toy/nuke
	name = "\improper Nuclear Fission Explosive toy"
	desc = "A plastic model of a Nuclear Fission Explosive."
	icon = 'icons/obj/toy.dmi'
	icon_state = "nuketoyidle"
	var/cooldown = 0

CAPABILITIES(/obj/item/toy/nuke)
	op("self", in_hand(), label("Use"), then(PROC_REF(interaction_self)))
	op("item", item(/obj/item), label("Use"), then(PROC_REF(interaction_item)))

/// Old attack_self.
/obj/item/toy/nuke/proc/interaction_self(datum/act/op/A)
	var/mob/user = A.actor
	if(COOLDOWN_FINISHED(src, cooldown))
		COOLDOWN_START(src, cooldown, 180 SECONDS) //3 minutes
		act_message(user, src, MSG_SELF(span_notice("You activate %T%, it plays a loud noise!")), MSG_OTHERS(span_warning("%U% presses a button on %T%")), MSG_BLIND(span_notice("You hear the click of a button.")))
		after(src, 0.5 SECONDS, PROC_REF(alarm_sequence)) //gia said so
	else
		var/timeleft = (cooldown - world.time)
		to_chat(user, span_warning("Nothing happens, and") + " '[round(timeleft/10)]' " + span_warning("appears on a small display."))
	return TRUE

/// Old attackby.
/obj/item/toy/nuke/proc/interaction_item(datum/act/op/A)
	var/mob/living/user = A.actor
	var/obj/item/I = A.held
	if(istype(I, /obj/item/disk/nuclear))
		to_chat(user, span_warning("Nice try. Put that disk back where it belongs."))
	return OP_PASS

/*
 * Toy gibber
 */
/obj/item/toy/minigibber
	name = "miniature gibber"
	desc = "A miniature recreation of NanoTrasen's famous meat grinder. Equipped with a special interlock that prevents insertion of organic material."
	icon = 'icons/obj/toy.dmi'
	icon_state = "gibber"
	attack_verb = list("grinded", "gibbed")
	COOLDOWN_DECLARE(cooldown)
	var/obj/stored_minature = null // owned: the miniature held by the toy gibber, kept in its contents

CAPABILITIES(/obj/item/toy/minigibber)
	owns_one(nameof(stored_minature), /obj)
	op("self", in_hand(), label("Use"), then(PROC_REF(interaction_self)))
	op("feed", item(/obj/item/toy/figure), item(/obj/item/toy/character), label("Feed"), when(req(PROC_REF(can_feed))), claims(), begins(PROC_REF(feed_begins)), wait(1 SECOND), on_interrupt(PROC_REF(feed_stopped)), then(PROC_REF(interaction_feed)))


/// Old attack_self.
/obj/item/toy/minigibber/proc/interaction_self(datum/act/op/A)
	var/mob/user = A.actor
	if(stored_minature)
		to_chat(user, span_danger("\The [src] makes a violent grinding noise as it tears apart the miniature figure inside!"))
		play_sfx(src, SFX_EFFECTS_SPLAT)
		rel_clear(src, nameof(stored_minature))
		COOLDOWN_START(src, cooldown, 0.8 SECONDS)
	if(COOLDOWN_FINISHED(src, cooldown))
		to_chat(user, span_notice("You hit the gib button on \the [src]."))

		COOLDOWN_START(src, cooldown, 0.8 SECONDS)
	return TRUE

/// A figure goes in, a character only from the feeder's own hands.
/obj/item/toy/minigibber/proc/can_feed(datum/act/op/A)
	var/obj/item/O = A.held
	return (istype(O, /obj/item/toy/figure) || read_once(O.loc == A.actor)) ? null : /datum/msg/req_failed

/obj/item/toy/minigibber/proc/feed_begins(datum/act/op/A)
	return msg_text(span_notice("You start feeding \the [A.held] [icon2html(A.held, A.actor.client)] into \the [src]'s mini-input."))

/// Old attackby: feed a figure into the gibber.
/obj/item/toy/minigibber/proc/interaction_feed(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/O = A.held
	if(O.loc != user)
		to_chat(user, span_warning("\The [O] is too far away to feed into \the [src]!"))
	else
		act_message(user, src, MSG_SELF(span_notice("You feed \the [O] into %T%!")), MSG_OTHERS(span_notice("%U% feeds \the [O] into %T%!")))
		move_into(src, nameof(src.stored_minature), O, user)
	return OP_OK

/obj/item/toy/minigibber/proc/feed_stopped(datum/act/op/A)
	act_message(A.actor, src, MSG_SELF(span_notice("You stop feeding \the [A.held] into %T%.")), MSG_OTHERS(span_notice("%U% stops feeding \the [A.held] into %T%!")))

/*
 * Toy xeno
 */
/obj/item/toy/toy_xeno
	icon = 'icons/obj/toy.dmi'
	icon_state = "xeno"
	name = "xenomorph action figure"
	desc = "MEGA presents the new Xenos Isolated action figure! Comes complete with realistic sounds! Pull back string to use."
	bubble_icon = "alien"
	var/cooldown = 0

/obj/item/toy/toy_xeno/proc/hiss()
	atom_say("Hiss!")
	play_sfx(get_turf(src), SFX_HISS, volume = 50, vary = TRUE)
	after(src, 4.5 SECONDS, PROC_REF(hiss_rewound))

/obj/item/toy/toy_xeno/proc/hiss_rewound()
	icon_state = "[initial(icon_state)]"

CAPABILITIES(/obj/item/toy/toy_xeno)
	op("self", in_hand(), then(PROC_REF(interaction_self)))

/// Old attack_self.
/obj/item/toy/toy_xeno/proc/interaction_self(datum/act/op/A)
	var/mob/user = A.actor
	if(COOLDOWN_FINISHED(src, cooldown))
		COOLDOWN_START(src, cooldown, 5 SECONDS) //5 second cooldown
		act_message(user, src, others = span_notice("%U% pulls back the string on %T%."))
		icon_state = "[initial(icon_state)]cool"
		after(src, 0.5 SECONDS, PROC_REF(hiss))
	else
		to_chat(user, span_warning("The string on [src] hasn't rewound all the way!"))
		return TRUE
	return TRUE

/*
 * Russian revolver
 */
/obj/item/toy/russian_revolver
	name = "russian revolver"
	desc = "For fun and games!"
	icon = 'icons/obj/gun.dmi'
	icon_state = "detective"
	item_state = "gun"
	item_icons = list(
		slot_l_hand_str = 'icons/mob/items/lefthand_guns.dmi',
		slot_r_hand_str = 'icons/mob/items/righthand_guns.dmi',
		)
	slot_flags = SLOT_BELT
	throwforce = 5
	throw_speed = 4
	throw_range = 5
	force = 5
	attack_verb = list("struck", "hit", "bashed")
	var/bullets_left = 0
	var/max_shots = 6

/obj/item/toy/russian_revolver/proc/revolver_after_init(datum/act/timer/A)
	spin_cylinder()

CAPABILITIES(/obj/item/toy/russian_revolver)
	after_init(0, then(PROC_REF(revolver_after_init)))
	op("self", in_hand(), then(PROC_REF(interaction_self)))

/// Old attack_self.
/obj/item/toy/russian_revolver/proc/interaction_self(datum/act/op/A)
	var/mob/user = A.actor
	if(!bullets_left)
		act_message(user, src, others = span_warning("%U% loads a bullet into %T%'s cylinder before spinning it."))
		spin_cylinder()
	else
		act_message(user, src, others = span_warning("%U% spins the cylinder on %T%!"))
		play_sfx(src, SFX_WEAPONS_REVOLVER_SPIN)
		spin_cylinder()
	return TRUE

/obj/item/toy/russian_revolver/attack(mob/living/M, mob/living/user, target_zone, attack_modifier)
	return NONE

/obj/item/toy/russian_revolver/afterattack(atom/target, mob/user, flag, params)
	if(flag)
		if(is_in_holder(target, user))
			return
		if(!ismob(target))
			return
	shoot_gun(user)

/obj/item/toy/russian_revolver/proc/spin_cylinder()
	bullets_left = rand(1, max_shots)

/obj/item/toy/russian_revolver/proc/post_shot(mob/user)
	return

/obj/item/toy/russian_revolver/proc/shoot_gun(mob/living/carbon/human/user)
	if(bullets_left > 1)
		bullets_left--
		user.visible_message(span_danger("*click*"))
		play_sfx(src, SFX_WEAPONS_EMPTY)
		return FALSE
	if(bullets_left == 1)
		bullets_left = 0
		var/zone = BP_HEAD
		if(!(user.has_organ(zone))) // If they somehow don't have a head.
			zone = "chest"
		play_sfx(src, SFX_EFFECTS_SNAP)
		user.visible_message(span_danger("[src] goes off!"))
		shake_camera(user, 2, 1)
		user.status_at_least(STAT_STUNNED, 1)
		post_shot(user)
		return TRUE
	else
		to_chat(user, span_warning("[src] needs to be reloaded."))
		return FALSE

/*
 * Trick revolver
 */
/obj/item/toy/russian_revolver/trick_revolver
	name = "\improper .357 revolver"
	desc = "A suspicious revolver. Uses .357 ammo."
	icon = 'icons/obj/toy.dmi'
	icon_state = "revolver"
	max_shots = 1
	var/fake_bullets = 0

CAPABILITIES(/obj/item/toy/russian_revolver/trick_revolver)
	rolls(nameof(fake_bullets), range_of(2, 7))

/obj/item/toy/russian_revolver/trick_revolver/examine(mob/user)
	. = ..()
	. += "Has [fake_bullets] round\s remaining."
	. += "[fake_bullets] of those are live rounds."

/obj/item/toy/russian_revolver/trick_revolver/post_shot(user)
	to_chat(user, span_danger("[src] did look pretty dodgy!"))
	play_sfx(src, SFX_ITEMS_CONFETTI, vary = TRUE)
	var/datum/effect/effect/system/confetti_spread/s = new /datum/effect/effect/system/confetti_spread
	s.set_up(5, 1, src)
	s.start()
	icon_state = "shoot"
	after(src, 0.5 SECONDS, TYPE_PROC_REF(/atom, set_icon_state), with = list(initial(icon_state)))

/*
 * Toy chainsaw
 */
/obj/item/toy/chainsaw
	name = "Toy Chainsaw"
	desc = "A toy chainsaw with a rubber edge. Ages 8 and up"
	icon = 'icons/obj/weapons.dmi'
	icon_state = "chainsaw0"
	force = 0
	throwforce = 0
	throw_speed = 4
	throw_range = 20
	attack_verb = list("sawed", "cut", "hacked", "carved", "cleaved", "butchered", "felled", "timbered")
	var/cooldown = 0

CAPABILITIES(/obj/item/toy/chainsaw)
	op("self", in_hand(), then(PROC_REF(interaction_self)))

/// Old attack_self.
/obj/item/toy/chainsaw/proc/interaction_self(datum/act/op/A)
	var/mob/user = A.actor
	if(!cooldown)
		play_sfx(user, SFX_WEAPONS_CHAINSAW_STARTUP)
		cooldown = 1
		after(src, 5 SECONDS, PROC_REF(cooldownreset))
	return TRUE

/obj/item/toy/chainsaw/proc/cooldownreset()
	cooldown = 0

/*
 * Random miniature spawner
 */
/obj/random/miniature
	name = "Random miniature"
	desc = "This is a random miniature."
	icon = 'icons/obj/toy.dmi'
	icon_state = "aliencharacter"

CAPABILITIES(/obj/random/miniature)
	loot(table = list(loot_types(1, typesof(/obj/item/toy/character))))

/*
 * Snake popper
 */
/obj/item/toy/snake_popper
	name = "bread tube"
	desc = "Bread in a tube. Chewy...and surprisingly tasty."
	description_fluff = "This is the product that brought Centauri Provisions into the limelight. A product of the earliest extrasolar colony of Heaven, the Bread Tube, while bland, contains all the nutrients a spacer needs to get through the day and is decidedly edible when compared to some of its competitors. Due to the high-fructose corn syrup content of NanoTrasen's own-brand bread tubes, many jurisdictions classify them as a confectionary."
	icon = 'icons/obj/toy.dmi'
	icon_state = "tastybread"
	var/popped = 0
	var/real = 0

/// Rolled before init (rolls(), code/engine/lifeforms/rolls.dm): what the old Initialize() drew from the world RNG.
/obj/item/toy/snake_popper/proc/roll_real(datum/roller/R)
	return R.chance(0.1) ? 1 : real

CAPABILITIES(/obj/item/toy/snake_popper)
	op("self", in_hand(), label("Use"), then(PROC_REF(interaction_self)))
	op("item", item(/obj/item), label("Use"), then(PROC_REF(interaction_item)))
	emag(then(PROC_REF(on_emag)), repeatable = TRUE, powered = FALSE)
	rolls(nameof(real), PROC_REF(roll_real))

/// Old attack_self.
/obj/item/toy/snake_popper/proc/interaction_self(datum/act/op/A)
	var/mob/user = A.actor
	if(!popped)
		to_chat(user, span_warning("A snake popped out of [src]!"))
		if(real == 0)
			var/obj/item/toy/C = new /obj/item/toy/plushie/snakeplushie(get_turf(loc))
			C.throw_at(get_step(src, pick(GLOB.alldirs)), 9, 1, src)

		if(real == 1)
			var/mob/living/simple_mob/C = new /mob/living/simple_mob/animal/passive/snake(get_turf(loc))
			C.throw_at(get_step(src, pick(GLOB.alldirs)), 9, 1, src)

		if(real == 2)
			var/mob/living/simple_mob/C = new /mob/living/simple_mob/vore/aggressive/giant_snake(get_turf(loc))
			C.throw_at(get_step(src, pick(GLOB.alldirs)), 9, 1, src)

		play_sfx(src, SFX_ITEMS_CONFETTI)
		icon_state = "tastybread_popped"
		popped = 1
		user.status_at_least(STAT_STUNNED, 1)

		var/datum/effect/effect/system/confetti_spread/s = new /datum/effect/effect/system/confetti_spread
		s.set_up(5, 1, src)
		s.start()
	return TRUE

/// Old attackby.
/obj/item/toy/snake_popper/proc/interaction_item(datum/act/op/A)
	var/obj/O = A.held
	if(istype(O, /obj/item/toy/plushie/snakeplushie) || !real)
		if(popped && !real)
			consumed(O, src)
			popped = 0
			icon_state = "tastybread"
	return OP_PASS

/obj/item/toy/snake_popper/attack(mob/living/M, mob/living/user, target_zone, attack_modifier)
	if(ishuman(M))
		if(!popped)
			to_chat(user, span_warning("A snake popped out of [src]!"))
			if(real == 0)
				var/obj/item/toy/C = new /obj/item/toy/plushie/snakeplushie(get_turf(loc))
				C.throw_at(get_step(src, pick(GLOB.alldirs)), 9, 1, src)

			if(real == 1)
				var/mob/living/simple_mob/C = new /mob/living/simple_mob/animal/passive/snake(get_turf(loc))
				C.throw_at(get_step(src, pick(GLOB.alldirs)), 9, 1, src)

			if(real == 2)
				var/mob/living/simple_mob/C = new /mob/living/simple_mob/vore/aggressive/giant_snake(get_turf(loc))
				C.throw_at(get_step(src, pick(GLOB.alldirs)), 9, 1, src)

			play_sfx(src, SFX_ITEMS_CONFETTI)
			icon_state = "tastybread_popped"
			popped = 1
			user.status_at_least(STAT_STUNNED, 1)

			var/datum/effect/effect/system/confetti_spread/s = new /datum/effect/effect/system/confetti_spread
			s.set_up(5, 1, src)
			s.start()
			return ITEM_INTERACT_SUCCESS
		return ITEM_INTERACT_FAILURE
	return NONE

/obj/item/toy/snake_popper/proc/on_emag(datum/act/op/A)
	var/mob/user = A.actor
	if(real != 2)
		real = 2
		to_chat(user, span_notice("You short out the bluespace refill system of [src]."))
	return OP_OK

/*
 * Professor Who universal ID
 */
/obj/item/clothing/under/universalid
	name = "identification card"
	desc = "A novelty identification card based on Professor Who's Universal ID."
	icon = 'icons/obj/toy.dmi'
	icon_state = "universal_id"
	w_class = ITEMSIZE_TINY
	slot_flags = SLOT_ID | SLOT_EARS
	body_parts_covered = 0
	equip_sound = null

	sprite_sheets = null

	item_state = "golem"  //This is dumb and hacky but was here when I got here.
	worn_state = "golem"  //It's basically just a coincidentally black iconstate in the file.

/*
 * Professor Who sonic driver
 */
/obj/item/tool/screwdriver/sdriver
	name = "sonic driver"
	desc = "A novelty screwdriver that uses tiny magnets to manipulate screws."
	icon = 'icons/obj/toy.dmi'
	icon_state = "sonic_driver"
	item_state = "screwdriver_black"
	usesound = SFX_ITEMS_SONIC_DRIVER
	toolspeed = 1
	random_color = FALSE

/*
 * Professor Who time capsule
 */
/obj/item/storage/box/timecap
	name = "action time capsule"
	desc = "A toy recreation of the Time Capsule from Professor Who. Can hold up to two action figures."
	icon = 'icons/obj/toy.dmi'
	icon_state = "time_cap"
	max_storage_space = ITEMSIZE_COST_TINY * 2
	use_sound = SFX_MACHINES_CLICK
	drop_sound = SFX_ITEMS_DROP_ACCESSORY
	pickup_sound = SFX_ITEMS_PICKUP_ACCESSORY

CAPABILITIES(/obj/item/storage/box/timecap)
	configure(storage(accepts = list(/obj/item/toy/figure), max_size = ITEMSIZE_TINY))

/*
 * Action figures
 */

/obj/item/toy/figure/ranger
	name = "Space Ranger action figure"
	desc = "A \"Space Life\" brand Space Ranger action figure."
	icon = 'icons/obj/toy.dmi'
	icon_state = "ranger"
	toysay = "To the Fontier and beyond!"

/obj/item/toy/figure/leadbandit
	name = "Bandit Leader action figure"
	desc = "A \"Space Life\" brand Bandit Leader action figure."
	icon = 'icons/obj/toy.dmi'
	icon_state = "bandit_lead"
	toysay = "Give us yer bluespace crystals!"

/obj/item/toy/figure/bandit
	name = "Bandit action figure"
	desc = "A \"Space Life\" brand Bandit action figure."
	icon = 'icons/obj/toy.dmi'
	icon_state = "bandit"
	toysay = "Stick em' up!"

/obj/item/toy/figure/abe
	name = "Action Abe action figure"
	desc = "A \"Space Life\" brand Action Abe action figure."
	icon = 'icons/obj/toy.dmi'
	icon_state = "action_abe"
	toysay = "Four score and seven decades ago..."

/obj/item/toy/figure/profwho
	name = "Professor Who action figure"
	desc = "A \"Space Life\" brand Professor Who action figure."
	icon = 'icons/obj/toy.dmi'
	icon_state = "prof_who"
	toysay = "Smells like... bad wolf..."

/obj/item/toy/figure/prisoner
	name = "prisoner action figure"
	desc = "A \"Space Life\" brand prisoner action figure."
	icon = 'icons/obj/toy.dmi'
	icon_state = "prisoner"
	toysay = "I did not hit her! I did not!"

/obj/item/toy/figure/error
	name = "completely glitched action figure"
	desc = "A \"Space Life\" brand... wait, what the hell is this thing? It seems to be requesting the sweet release of death."
	icon = 'icons/obj/toy.dmi'
	icon_state = "glitched"
	toysay = "AaAAaAAAaAaaaAAA!!!!!"

/*
 * Desk toys
 */
/obj/item/toy/desk
	icon = 'icons/obj/toy.dmi'
	var/on = FALSE
	var/activation_sound = SFX_MACHINES_CLICK

TRACKED(/obj/item/toy/desk, on)

/// The look (the draw sweep: from its template).
/obj/item/toy/desk/draw(datum/look/look)
	..()
	look.state("[initial(icon_state)][on ? "-on" : ""]")

/obj/item/toy/desk/proc/activate(mob/user as mob)
	set_on(!on)
	playsound(src.loc, activation_sound, 75, 1)
	return 1

CAPABILITIES(/obj/item/toy/desk)
	op("self", in_hand(), label("Use"), then(PROC_REF(interaction_self)))
	op("alt", hand(), ungated(), gesture(GESTURE_ALT), label("Alternate use"), then(PROC_REF(interaction_alt)))
	drag_onto(PROC_REF(mousedrop_input))

/// Old attack_self.
/obj/item/toy/desk/proc/interaction_self(datum/act/op/A)
	var/mob/user = A.actor
	activate(user)
	return TRUE

/// Old click_alt.
/obj/item/toy/desk/proc/interaction_alt(datum/act/op/A)
	var/mob/user = A.actor
	activate(user)
	return TRUE

/// The native MouseDrop's actor and arguments, handed over by the engine (drag_onto(), code/engine/lifeforms/input.dm).
/obj/item/toy/desk/proc/mousedrop_input(datum/act/input/A)
	return pickup_with_actor(A.actor, A.over)

/obj/item/toy/desk/proc/pickup_with_actor(mob/user, mob/destination)
	if((user && user == destination && (!( user.restrained() ) && (!( user.stat ) && (user.contents.Find(src) || in_range(src, user))))))
		if(ishuman(user))
			if(!user.get_active_hand())		//if active hand is empty
				var/mob/living/carbon/human/H = user
				var/obj/item/organ/external/temp = H.organs_by_name[BP_R_HAND]

				if (H.hand)
					temp = H.organs_by_name[BP_L_HAND]
				if(temp && !temp.is_usable())
					to_chat(user,span_notice("You try to move your [temp.name], but cannot!"))
					return

				to_chat(user,span_notice("You pick up [src]."))
				user.put_in_hands(src)

	return

/obj/item/toy/desk/newtoncradle
	name = "\improper Newton's cradle"
	desc = "A ancient 21th century super-weapon model demonstrating that Sir Isaac Newton is the deadliest sonuvabitch in space."
	description_fluff = "Aside from car radios, Eridanian Dregs are reportedly notorious for stealing these things. It is often \
	theorized that the very same ball bearings are used in black-market cybernetics."
	icon_state = "newtoncradle"

/obj/item/toy/desk/fan
	name = "office fan"
	desc = "Your greatest fan."
	description_fluff = "For weeks, the atmospherics department faced a conundrum on how to lower temperatures in a localized \
	area through complicated pipe channels and ventilation systems. The problem was promptly solved by ordering several desk fans."
	icon_state = "fan"

/obj/item/toy/desk/officetoy
	name = "office toy"
	desc = "A generic microfusion powered office desk toy. Only generates magnetism and ennui."
	description_fluff = "The mechanism inside is a Hephasteus trade secret. No peeking!"
	icon_state = "desktoy"

/obj/item/toy/desk/dippingbird
	name = "dipping bird toy"
	desc = "Engineers marvel at this scale model of a primitive thermal engine. It's highly debated why the majority of owners \
	were in low-level bureaucratic jobs."
	description_fluff = "One of the key essentials for every Eridanian suit - it's practically a rite of passage to own one \
	of these things."
	icon_state = "dippybird"

/obj/item/toy/desk/stellardelight
	name = "\improper Stellar Delight model"
	desc = "A scale model of the Stellar Delight. Includes flashing lights!"
	icon_state = "stellar_delight"

/*
 * Party popper
 */
/obj/item/toy/partypopper
	name = "party popper"
	desc = "Instructions : Aim away from face. Wait for appropriate timing. Pull cord, enjoy confetti."
	icon = 'icons/obj/toy.dmi'
	icon_state = "partypopper"
	w_class = ITEMSIZE_TINY
	drop_sound = SFX_ITEMS_DROP_CARDBOARDBOX
	pickup_sound = SFX_ITEMS_PICKUP_CARDBOARDBOX

CAPABILITIES(/obj/item/toy/partypopper)
	op("self", in_hand(), then(PROC_REF(interaction_self)))

/// Old attack_self.
/obj/item/toy/partypopper/proc/interaction_self(datum/act/op/A)
	var/mob/user = A.actor
	if(icon_state == "partypopper")
		act_message(user, null, MSG_SELF(span_notice("You pull on the string, releasing a burst of confetti!")), MSG_OTHERS(span_notice("%U% pulls on the string, releasing a burst of confetti!")))
		play_sfx(src, SFX_EFFECTS_SNAP)
		var/datum/effect/effect/system/confetti_spread/s = new /datum/effect/effect/system/confetti_spread
		s.set_up(5, 1, src)
		s.start()
		icon_state = "partypopper_e"
		var/turf/T = get_step(src, user.dir)
		if(!turf_clear(T))
			T = get_turf(src)
		new /obj/effect/decal/cleanable/confetti(T)
	else
		to_chat(user, span_notice("The [src] is already spent!"))
	return TRUE

/*
 * Snow Globes
 */
/obj/item/toy/snowglobe
	name = "snowglobe"
	icon = 'icons/obj/snowglobe_vr.dmi'

/obj/item/toy/snowglobe/snowvillage
	desc = "Depicts a small, quaint village buried in snow."
	icon_state = "smolsnowvillage"

/obj/item/toy/snowglobe/tether
	desc = "Depicts a massive space elevator reaching to the sky."
	icon_state = "smoltether"

/obj/item/toy/snowglobe/stellardelight
	desc = "Depicts an interstellar spacecraft."
	icon_state = "smolstellardelight"

/obj/item/toy/snowglobe/rascalspass
	desc = "Depicts a nanotrasen facility on a temperate world."
	icon_state = "smolrascalspass"

//Monster bait for triggering vore interactions without being hostile

/obj/item/toy/monster_bait
	name = "bait toy"
	desc = "A cute little fluffy wiggly worm toy dangling from the end of a stick. Be careful what you wave this in front of!"
	icon = 'icons/obj/items.dmi'
	icon_state = "monster_bait"
	w_class = ITEMSIZE_SMALL

/obj/item/toy/monster_bait/afterattack(atom/A, mob/user)
	var/mob/living/simple_mob/M = A
	if(M.z != user.z || get_dist(user,M) > 1)
		to_chat(user, span_notice("You need to stand right next to \the [M] to bait it."))
		return
	if(!istype(M))
		return
	if(!M.vore_active)
		to_chat(user, span_notice("\The [M] doesn't seem interested in \the [src]."))
		return
	if(M.stat)
		to_chat(user, span_notice("\The [M] doesn't look like it's any condition to do that."))
		return
	act_message(user, src, others = span_danger("%U% waves %T% in front of the [M]!"))
	M.PounceTarget(user,100)

/// Fluff item for digitalsquirrel

/obj/item/toy/acorn_branch
	name = "oak staff"
	desc = "A branch of oak wood bearing a collection of still living leaves, and many acorns hanging among them."
	icon = 'icons/obj/items.dmi'
	icon_state = "acorn_branch"
	w_class = ITEMSIZE_SMALL
	EXPIRY_DECLARE(next_use)
	var/registered_mob //On request, only one person is able to use it at a time.

CAPABILITIES(/obj/item/toy/acorn_branch)
	op("pick_acorn", in_hand(), when(req_actor_kind(/mob/living/carbon/human)), needs(req_conscious()), then(PROC_REF(interaction_self)))

/obj/item/toy/acorn_branch/proc/can_pull_acorn(mob/user, atom/target, obj/item/held)
	if(user.stat || !ishuman(user))
		return TRUE // the effect declines silently
	if(!COOLDOWN_FINISHED(src, next_use))
		return "you need to wait a bit longer before you can pull out another acorn"
	return TRUE

/// Old attack_self: a person pulls an acorn out (one at a time, and only its registered owner).
/obj/item/toy/acorn_branch/proc/interaction_self(datum/act/op/A)
	var/mob/living/carbon/human/H = A.actor
	var/mob/user = H
	if(!COOLDOWN_FINISHED(src, next_use))
		to_chat(user, span_notice("You need to wait a bit longer before you can pull out another acorn."))
		return OP_OK
	if(registered_mob)
		if(registered_mob != H)
			to_chat(user, span_notice("It's a lovely branch!"))
			return OP_OK
	else
		registered_mob = H
	if(H.get_inactive_hand())
		to_chat(user, span_notice("You need to have a free hand to pick an acorn out!"))
		return OP_OK
	var/spawnloc = get_turf(H)
	var/obj/item/I = new /obj/item/reagent_containers/food/snacks/acorn(spawnloc)
	H.put_in_inactive_hand(I)
	EXPIRY_SET(src, next_use, 30 SECONDS, CLOCK_WORLD)
	act_message(H, src, others = span_notice("%U% pulls an acorn from %T%!"))
	return OP_OK

/obj/item/toy/plushie/dragon
	name = "dragon plushie"
	desc = "A soft plushie in the shape of a dragon. How ferocious!"
	icon = 'icons/obj/toy.dmi'
	icon_state = "reddragon"
	COOLDOWN_DECLARE(cooldown)
	special_handling = TRUE

/obj/item/toy/plushie/dragon/Initialize(mapload)
	. = ..()
	if (pokephrase != "Rawr~!")
		pokephrase = pick("ROAR!", "RAWR!", "GAWR!", "GRR!", "GROAR!", "GRAH!", "Weh!", "Merp!")

CAPABILITIES(/obj/item/toy/plushie/dragon)
	without("hug")
	without("poke")
	without("strangle")
	without("punch")
	op("dragon_squeeze", in_hand(), label("Squeeze"), then(PROC_REF(interaction_dragon_squeeze)))

/// Old attack_self: the dragon noise. The plushie's squeeze does nothing for it (special_handling).
/obj/item/toy/plushie/dragon/proc/interaction_dragon_squeeze(datum/act/op/A)
	var/mob/user = A.actor
	if(COOLDOWN_FINISHED(src, cooldown))
		switch(pokephrase)
			if("Weh!")
				play_sfx(user, SFX_VOICE_WEH)
			if("Merp!")
				play_sfx(user, SFX_VOICE_MERP)
			else
				play_sfx(user, SFX_VOICE_ROARBARK)
		COOLDOWN_START(src, cooldown, 5 SECONDS)
	return TRUE

/obj/item/toy/plushie/dragon/green
	name = "green dragon plushie"
	icon_state = "greendragon"

/obj/item/toy/plushie/dragon/purple
	name = "purple dragon plushie"
	icon_state = "purpledragon"

/obj/item/toy/plushie/dragon/white_east
	name = "white eastern dragon plushie"
	icon_state = "whiteeasterndragon"

/obj/item/toy/plushie/dragon/red_east
	name = "red eastern dragon plushie"
	icon_state = "redeasterndragon"

/obj/item/toy/plushie/dragon/green_east
	name = "green eastern dragon plushie"
	icon_state = "greeneasterndragon"

/obj/item/toy/plushie/dragon/gold_east
	name = "golden eastern dragon plushie"
	desc = "A soft plushie of a shiny golden dragon. Made of Real* gold!"
	icon_state = "goldeasterndragon"
	pokephrase = "Rawr~!"

/obj/item/toy/plushie/teshari/strix
	name = "Strix Hades"
	desc = "This is Strix Hades the plushie Avali. Very soft, with a pompom on the tail. The toy is made well, as if alive. Looks like he is sleeping. Shhh!"
	icon_state = "strixplush"
	item_state = "strixplush"
	slot_flags = SLOT_BACK | SLOT_HEAD
	pokephrase = "Weh!"
	icon = 'icons/obj/toy_yw.dmi'
	item_icons = list(
		slot_l_hand_str = 'icons/mob/items/lefthand_toys.dmi',
		slot_r_hand_str = 'icons/mob/items/righthand_toys.dmi',
		slot_back_str = 'icons/mob/toy_worn.dmi',
		slot_head_str = 'icons/mob/toy_worn.dmi')

/obj/item/toy/plushie/teshari/strix/rename_refusal(datum/act/op/A)
	return "You cannot rename Strix Hades, you hug him anyway."

/obj/item/toy/plushie/teshari/eili
	name = "Eili"
	desc = "This is a plushie that resembles an Avali named Eili. The ammount of detail makes it almost look lifelike! Looks like she is sleeping. Shhh!"
	icon_state = "jeans_eiliplush"
	item_state = "jeans_eiliplush"
	slot_flags = SLOT_BACK | SLOT_HEAD
	pokephrase = "Weh!"
	icon = 'icons/vore/custom_items_yw.dmi'
	item_icons = list(
		slot_l_hand_str = 'icons/vore/custom_items_left_hand_yw.dmi',
		slot_r_hand_str = 'icons/vore/custom_items_right_hand_yw.dmi',
		slot_back_str = 'icons/vore/custom_onmob_yw.dmi',
		slot_head_str = 'icons/vore/custom_onmob_yw.dmi')

/obj/item/toy/plushie/teshari/eili/rename_refusal(datum/act/op/A)
	return "You cannot rename Eili, you hug her anyway."

/obj/item/toy/plushie/teshari/_yw
	name = "lifelike teshari plush"
	desc = "This is a plush teshari. Very soft. The ammount of detail makes it almost look lifelike! Looks like it is sleeping. Shhh!"
	icon_state = "teshariplushie_brown"
	item_state = "teshariplushie_brown"
	pokephrase = "Rya!"
	slot_flags = SLOT_BACK | SLOT_HEAD
	icon = 'icons/obj/toy_yw.dmi'
	item_icons = list(
		slot_l_hand_str = 'icons/mob/items/lefthand_toys.dmi',
		slot_r_hand_str = 'icons/mob/items/righthand_toys.dmi',
		slot_back_str = 'icons/mob/toy_worn.dmi',
		slot_head_str = 'icons/mob/toy_worn.dmi')

/obj/item/toy/plushie/teshari/w_yw
	name = "lifelike teshari plush"
	desc = "This is a plush teshari. Very soft. The ammount of detail makes it almost look lifelike! Looks like it is sleeping. Shhh!"
	icon_state = "teshariplushie_white"
	item_state = "teshariplushie_white"
	pokephrase = "Rya!"
	slot_flags = SLOT_BACK | SLOT_HEAD
	icon = 'icons/obj/toy_yw.dmi'
	item_icons = list(
		slot_l_hand_str = 'icons/mob/items/lefthand_toys.dmi',
		slot_r_hand_str = 'icons/mob/items/righthand_toys.dmi',
		slot_back_str = 'icons/mob/toy_worn.dmi',
		slot_head_str = 'icons/mob/toy_worn.dmi')

/obj/item/toy/plushie/teshari/b_yw
	name = "lifelike teshari plush"
	desc = "This is a plush teshari. Very soft. The ammount of detail makes it almost look lifelike! Looks like it is sleeping. Shhh!"
	icon_state = "teshariplushie_black"
	item_state = "teshariplushie_black"
	pokephrase = "Rya!"
	slot_flags = SLOT_BACK | SLOT_HEAD
	icon = 'icons/obj/toy_yw.dmi'
	item_icons = list(
		slot_l_hand_str = 'icons/mob/items/lefthand_toys.dmi',
		slot_r_hand_str = 'icons/mob/items/righthand_toys.dmi',
		slot_back_str = 'icons/mob/toy_worn.dmi',
		slot_head_str = 'icons/mob/toy_worn.dmi',
		slot_ear_str = 'icons/mob/toy_worn.dmi')

/obj/item/toy/plushie/teshari/y_yw
	name = "lifelike teshari plush"
	desc = "This is a plush teshari. Very soft. The ammount of detail makes it almost look lifelike! Looks like it is sleeping. Shhh!"
	icon_state = "teshariplushie_yellow"
	item_state = "teshariplushie_yellow"
	pokephrase = "Rya!"
	slot_flags = SLOT_BACK | SLOT_HEAD
	icon = 'icons/obj/toy_yw.dmi'
	item_icons = list(
		slot_l_hand_str = 'icons/mob/items/lefthand_toys.dmi',
		slot_r_hand_str = 'icons/mob/items/righthand_toys.dmi',
		slot_back_str = 'icons/mob/toy_worn.dmi',
		slot_head_str = 'icons/mob/toy_worn.dmi')

/obj/item/toy/nuke/proc/alarm_sequence()
	icon_state = "nuketoy"
	play_sfx(src, SFX_MACHINES_ALARM)
	after(src, 13.5 SECONDS, TYPE_PROC_REF(/atom, set_icon_state), with = list("nuketoycool"))
	after(src, 13.5 SECONDS + (cooldown - world.time), TYPE_PROC_REF(/atom, set_icon_state), with = list("nuketoyidle"))


/// Requirement for renaming: someone with a mind, and a plushie that takes a name (a unique one says why it doesn't).
/obj/item/toy/plushie/proc/can_rename(datum/act/op/A)
	return isnull(rename_refusal(A))

/obj/item/toy/plushie/proc/rename_refusal(datum/act/op/A)
	if(!has_a_mind(A.actor))
		return MSG(plushie/no_mind)
	return null

/// Does `M` have a mind (a player's or an AI's)?
/proc/has_a_mind(mob/M)
	READS_FROM() // a mind is set when a player takes the body; asked when the name is given
	return !!M?.mind

MSG_DEF_SELF(plushie/no_mind, "You can't think of a name.")

