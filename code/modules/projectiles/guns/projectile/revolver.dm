/*
 * Revolver
 */
/obj/item/gun/projectile/revolver
	name = "revolver"
	desc = "The MarsTech HE Colt is a choice revolver for when you absolutely, positively need to put a hole in the other guy. Uses .357 rounds."
	description_fluff = "MarsTech first made their name in the Second Cold War as the 'Lunar Arms Company' providing home-grown arms to the Selene Federation, \
	but after the formation of the SCG rebranded and relocated to Mars where they remain based to this day. \
	The company was acquired by Hephaestus in the mid 23rd century, and its branding used to present an image of historical prestige and Solar unity for their latest product line. \
	MarsTech operates production facilities out of many of the SCG’s larger colonies."
	icon_state = "revolver"
	item_state = "revolver"
	caliber = ".357"
	handle_casings = CYCLE_CASINGS
	max_shells = 6
	ammo_type = /obj/item/ammo_casing/a357
	projectile_type = /obj/item/projectile/bullet/pistol/strong
	var/chamber_offset = 0 //how many empty chambers in the cylinder until you hit a round
	fire_sound = SFX_WEAPONS_GUNSHOT4

CAPABILITIES(/obj/item/gun/projectile/revolver)
	op("revolver_verb_spin_cylinder", menu(), label("Spin cylinder"), needs(carried()), then(PROC_REF(revolver_verb_spin_cylinder)))

/// Old Spin cylinder verb: Fun when you're bored out of your skull.
/obj/item/gun/projectile/revolver/proc/revolver_verb_spin_cylinder(datum/act/op/A)
	var/mob/user = A.actor
	chamber_offset = 0
	act_message(user, src, others = span_warning("%U% spins the cylinder of %T%!"), blind = span_notice("You hear something metallic spin and click."))
	play_sfx(src, SFX_WEAPONS_REVOLVER_SPIN)
	if(length(loaded))
		shuffle_inplace(loaded)
	if(rand(1,max_shells) > length(loaded))
		chamber_offset = rand(0,max_shells - length(loaded))

/obj/item/gun/projectile/revolver/consume_next_projectile()
	if(chamber_offset)
		chamber_offset--
		return
	return ..()

/obj/item/gun/projectile/revolver/load_ammo(obj/item/A, mob/user)
	chamber_offset = 0
	return ..()

/obj/item/gun/projectile/revolver/stainless
	icon_state = "revolver_stainless"

/*
 * Detective Revolver
 */
/obj/item/gun/projectile/revolver/detective
	name = "revolver"
	desc = "A standard MarsTech R1 snubnose revolver, popular among some law enforcement agencies for its simple, long-lasting construction. Uses .38-Special rounds."
	description_fluff = "The leading civilian-sector high-quality small arms brand of Hephaestus Industries, MarsTech has been the provider of choice for law enforcement and security forces for over 300 years."
	icon_state = "detective"
	caliber = ".38"
	ammo_type = /obj/item/ammo_casing/a38

EXTEND_INTERACTIONS(/obj/item/gun/projectile/revolver/detective, INTERACT_VERB("Name Gun", PROC_REF(det_revolver_verb_rename), REQ_IN_INVENTORY, REQ_PROC(/proc/dq_actor_is_detective_for_naming, "you don't feel cool enough to name this gun, chump")))

/// Requirement for naming the detective's gun: the actor is the detective. No mind is left to the verb, which does nothing.
/proc/dq_actor_is_detective_for_naming(mob/actor, atom/target, obj/item/held)
	return !actor?.mind || actor.mind.assigned_role == JOB_DETECTIVE

/// Requirement for naming a security sidearm: the actor holds a security job. No mind is left to the verb.
/proc/dq_actor_is_security_for_naming(mob/actor, atom/target, obj/item/held)
	if(!actor?.mind)
		return TRUE
	var/job = actor.mind.assigned_role
	return job == JOB_DETECTIVE || job == JOB_SECURITY_OFFICER || job == JOB_WARDEN || job == JOB_HEAD_OF_SECURITY

/// Old Name Gun verb: Click to rename your gun. If you're the detective.
/obj/item/gun/projectile/revolver/detective/proc/det_revolver_verb_rename(mob/user, obj/item/held, datum/interaction/interaction)
	return weapon_label_detective_name_stage(user, held, interaction)

/obj/item/gun/projectile/revolver/detective/proc/weapon_label_detective_name_stage(mob/user, obj/item/held, datum/interaction/interaction, weapon_answer, weapon_answer_ready = FALSE)
	var/mob/M = user
	if(!M.mind)	return 0

	if(!weapon_answer_ready)
		open_request(src, /datum/prompt/text/weapon_label_review, PROC_REF(weapon_label_detective_name_answered), answerer = M, weapon_operator = user, weapon_held = held, weapon_interaction = interaction, question = "What do you want to name the gun?", title = "Rename Revolver", max_len = MAX_NAME_LEN, encode = FALSE, name_text = TRUE)
		return
	var/_answer_k69 = weapon_answer
	if(isnull(_answer_k69))
		return
	var/input = sanitizeSafe(_answer_k69)

	if(src && input && !M.stat && in_range(M,src))
		name = input
		to_chat(M, "You name the gun [input]. Say hello to your new friend.")
		return 1

/obj/item/gun/projectile/revolver/detective45
	name = ".45 revolver"
	desc = "A basic revolver, popular among some law enforcement agencies for its simple, long-lasting construction, modified for .45 rounds and a seven-shot cylinder."
	icon_state = "detective"
	caliber = ".45"
	ammo_type = /obj/item/ammo_casing/a45/rubber
	max_shells = 6

EXTEND_INTERACTIONS(/obj/item/gun/projectile/revolver/detective45, \
	INTERACT_VERB("Name Gun", PROC_REF(det45_revolver_verb_rename), REQ_IN_INVENTORY, REQ_PROC(/proc/dq_actor_is_detective_for_naming, "you don't feel cool enough to name this gun, chump")), \
	INTERACT_VERB("Resprite gun", PROC_REF(det45_revolver_verb_reskin), REQ_IN_INVENTORY), \
)

/// Old Name Gun verb: rename your gun, if you are the detective.
/obj/item/gun/projectile/revolver/detective45/proc/det45_revolver_verb_rename(mob/user, obj/item/held, datum/interaction/interaction)
	return weapon_label_detective45_name_stage(user, held, interaction)

/obj/item/gun/projectile/revolver/detective45/proc/weapon_label_detective45_name_stage(mob/user, obj/item/held, datum/interaction/interaction, weapon_answer, weapon_answer_ready = FALSE)
	var/mob/M = user
	if(!M.mind)	return 0
	if(!weapon_answer_ready)
		open_request(src, /datum/prompt/text/weapon_label_review, PROC_REF(weapon_label_detective45_name_answered), answerer = M, weapon_operator = user, weapon_held = held, weapon_interaction = interaction, question = "What do you want to name the gun?", title = "Rename Revolver", max_len = MAX_NAME_LEN, encode = FALSE, name_text = TRUE)
		return
	var/_answer_k96 = weapon_answer
	if(isnull(_answer_k96))
		return
	var/input = sanitizeSafe(_answer_k96, MAX_NAME_LEN)

	if(src && input && !M.stat && in_range(M,src))
		name = input
		to_chat(M, "You name the gun [input]. Say hello to your new friend.")
		return 1

/// Old Resprite gun verb: Click to choose a sprite for your gun.
/obj/item/gun/projectile/revolver/detective45/proc/det45_revolver_verb_reskin(mob/user, obj/item/held, datum/interaction/interaction)
	return weapon_label_detective45_style_stage(user, held, interaction)

/obj/item/gun/projectile/revolver/detective45/proc/weapon_label_detective45_style_stage(mob/user, obj/item/held, datum/interaction/interaction, weapon_answer, weapon_answer_ready = FALSE)
	var/mob/M = user
	var/list/options = list()
	options["MarsTech R1 Snubnose"] = "detective"
	options["MarsTech R1 Snubnose (Blued)"] = "detective_blued"
	options["MarsTech R1 Snubnose (Stainless)"] = "detective_stainless"
	options["MarsTech R1 Snubnose (Gold)"] = "detective_stainless"
	options["MarsTech R1 Snubnose (Leopard)"] = "detective_leopard"
	options["MarsTech Frontiersman Classic"] = "detective_peacemaker"
	options["MarsTech Frontiersman Shadow"] = "detective_peacemaker_dark"
	options["Jindal Duke"] = "detective_fitz"
	options["H-H M1895"] = "nagant"
	if(!weapon_answer_ready)
		open_request(src, /datum/prompt/choice/weapon_label_review, PROC_REF(weapon_label_detective45_style_answered), answerer = M, weapon_operator = user, weapon_held = held, weapon_interaction = interaction, question = "Choose your sprite!", title = "Resprite Gun", choices = options)
		return
	var/choice = weapon_answer
	if(isnull(choice))
		return
	if(src && choice && !M.stat && in_range(M,src))
		icon_state = options[choice]
		to_chat(M, "Your gun is now sprited as [choice]. Say hello to your new friend.")
		return 1

/*
 * Lombardi Revolvers
 * 		Use to be detective revolvers until seperated
 */
/obj/item/gun/projectile/revolver/lombardi
	name = "Lombardi Buzzard"
	desc = "A rugged revolver that is mostly used by small law enforcement agencies across the frontier as a cheap, reliable sidearm. Uses .357 rounds."
	icon_state = "lombardi_police"

/obj/item/gun/projectile/revolver/lombardi/panther
	name = "Lombardi Panther"
	icon_state = "lombardi_panther"

/obj/item/gun/projectile/revolver/lombardi/gold
	name = "Lombardi Deluxe 2502"
	desc = "A sweet looking revolver that is decorated with false gold and silver plating. Favored among by gamblers and criminals alike. Uses .357 rounds."
	icon_state = "lombardi_gold"

/*
 * Captain's Peacekeeper
 */
/obj/item/gun/projectile/revolver/cappeacekeeper
	name = "decorated peacekeeper"
	desc = "A MarsTech Frontiersman revolver that has been heavily modified. It has been decorated for personal use by command officers. Uses .44 rounds."
	description_fluff = "The leading civilian-sector high-quality small arms brand of Hephaestus Industries, \
	MarsTech has been the provider of choice for law enforcement and security forces for over 300 years."
	icon_state = "captains_peacemaker"
	caliber = ".44"
	ammo_type = /obj/item/ammo_casing/a44

/*
 * Mateba
 */
/obj/item/gun/projectile/revolver/mateba
	name = "mateba"
	desc = "This unique looking handgun is named after an Italian company famous for the original manufacture of \
	these revolvers, and pasta kneading machines. Uses .357 rounds." // Yes I'm serious. -Spades
	icon_state = "mateba"

/*
 * Deckard (Blade Runner)
 */
/obj/item/gun/projectile/revolver/deckard
	name = "\improper \"Deckard\" .38"
	desc = "A custom-built revolver, based off the semi-popular Detective Special model. Uses .38-Special rounds."
	icon_state = "deckard-empty"
	caliber = ".38"
	ammo_type = /obj/item/ammo_casing/a38
	move_delay = 0 // Pistols have move_delay of 0

/obj/item/gun/projectile/revolver/deckard/emp
	ammo_type = /obj/item/ammo_casing/a38/emp


/// TRUE while any rounds are loaded.
/obj/item/gun/projectile/revolver/deckard/proc/appearance_loaded()
	return length(loaded) > 0
/// The look (the draw sweep: from its template).
/obj/item/gun/projectile/revolver/deckard/draw(datum/look/look)
	..()
	look.state("deckard-[appearance_loaded() ? "loaded" : "empty"]")

/obj/item/gun/projectile/revolver/deckard/load_ammo(obj/item/A, mob/user)
	if(istype(A, /obj/item/ammo_magazine))
		flick("deckard-reload",src)
	..()

/*
 * Judge
 */
/obj/item/gun/projectile/revolver/judge
	name = "\"The Judge\""
	desc = "A revolving hand-shotgun by Jindal Arms that packs the power of a 12 guage in the palm of your hand (if you don't break your wrist). Uses 12g rounds."
	description_fluff = "While wholly owned by Hephaestus Industries, the Jindal Arms brand does not appear \
	prominently in most company catalogues (Perhaps owing to its less than prestigious image), \
	instead being sold almost exclusively through retailers and advertising platforms targeting the \
	'independent roughneck' demographic."
	icon_state = "judge"
	caliber = "12g"
	max_shells = 5
	recoil = 2 // ow my fucking hand
	accuracy = -15 // smooth bore + short barrel = shit accuracy
	ammo_type = /obj/item/ammo_casing/a12g
	projectile_type = /obj/item/projectile/bullet/shotgun
	// ToDo: Remove accuracy debuf in exchange for slightly injuring your hand every time you fire it.

/*
 * Mako
 */
/obj/item/gun/projectile/revolver/lemat
	name = "Mako revolver"
	desc = "The Bishamonten P100 Mako is a 9 shot revolver with a secondary firing barrel loading shotgun shells. For when you really need something dead. A rare yet deadly collector's item. Uses .38-Special and 12g rounds depending on the barrel."
	description_fluff = "The Bishamonten Company operated from roughly 2150-2280 - the height of the first extrasolar colonisation boom - before filing for bankruptcy and selling off its assets to various companies that would go on to become today’s TSCs. \
	Focused on sleek ‘futurist’ designs which have largely fallen out of fashion but remain popular with collectors and people hoping to make some quick thalers from replica weapons. \
	Bishamonten weapons tended to be form over function - despite their flashy looks, most were completely unremarkable one way or another as weapons, and used very standard firing mechanisms - \
	the Mako was a notable exception, so original examples are much sought after."
	icon_state = "combatrevolver"
	item_state = "revolver"
	handle_casings = CYCLE_CASINGS
	max_shells = 9
	caliber = ".38"
	ammo_type = /obj/item/ammo_casing/a38
	projectile_type = /obj/item/projectile/bullet/pistol
	var/secondary_max_shells = 1
	var/secondary_caliber = "12g"
	var/secondary_ammo_type = /obj/item/ammo_casing/a12g
	var/flipped_firing = 0
	/// Owned rounds of the cylinder not being fired (swapped with loaded when the firing mode flips).
	var/list/secondary_loaded
	/// Owned rounds of the primary cylinder while the secondary one is being fired.
	var/list/tertiary_loaded

CAPABILITIES(/obj/item/gun/projectile/revolver/lemat)
	owns_many(nameof(secondary_loaded))
	owns_many(nameof(tertiary_loaded))
	op("lemat_verb_swap_firing_mode", menu(), label("Swap Firing Mode"), needs(carried()), then(PROC_REF(lemat_verb_swap_firing_mode)))


/obj/item/gun/projectile/revolver/lemat/Initialize(mapload)
	. = ..()
	for(var/i in 1 to secondary_max_shells)
		rel_add(src, nameof(secondary_loaded), new secondary_ammo_type(src))

/// Old Swap Firing Mode verb: Click to swap from one method of firing to another.
/obj/item/gun/projectile/revolver/lemat/proc/lemat_verb_swap_firing_mode(datum/act/op/A)
	var/mob/user = A.actor
	var/mob/living/carbon/human/M = user
	if(!M.mind)
		return 0

	to_chat(M, span_notice("You change the firing mode on \the [src]."))
	if(!flipped_firing)
		if(max_shells && secondary_max_shells)
			max_shells = secondary_max_shells

		if(caliber && secondary_caliber)
			caliber = secondary_caliber

		if(ammo_type && secondary_ammo_type)
			ammo_type = secondary_ammo_type

		swap_cylinder("secondary_loaded", "tertiary_loaded")

		flipped_firing = 1

	else
		if(max_shells)
			max_shells = initial(max_shells)

		if(caliber && secondary_caliber)
			caliber = initial(caliber)

		if(ammo_type && secondary_ammo_type)
			ammo_type = initial(ammo_type)

		swap_cylinder("tertiary_loaded", "secondary_loaded")

		flipped_firing = 0

/// The rounds in `incoming_var` become loaded; the rounds loaded now move to `stash_var`.
/obj/item/gun/projectile/revolver/lemat/proc/swap_cylinder(incoming_var, stash_var)
	var/list/current = own_take_all(src, nameof(loaded))
	var/list/incoming = own_take_all(src, incoming_var)
	for(var/obj/item/ammo_casing/casing as anything in current)
		rel_add(src, stash_var, casing)
	for(var/obj/item/ammo_casing/casing as anything in incoming)
		rel_add(src, nameof(loaded), casing)

/// Old Spin cylinder verb override: the LeMat spins whichever cylinder it is firing from.
/obj/item/gun/projectile/revolver/lemat/revolver_verb_spin_cylinder(datum/act/op/A)
	var/mob/user = A.actor
	chamber_offset = 0
	act_message(user, src, others = span_warning("%U% spins the cylinder of %T%!"), blind = span_notice("You hear something metallic spin and click."))
	play_sfx(src, SFX_WEAPONS_REVOLVER_SPIN)
	if(!flipped_firing)
		if(length(loaded))
			shuffle_inplace(loaded)
		if(rand(1,max_shells) > length(loaded))
			chamber_offset = rand(0,max_shells - length(loaded))

/obj/item/gun/projectile/revolver/lemat/examine(mob/user)
	. = ..()
	if(secondary_loaded)
		var/to_print
		for(var/round in secondary_loaded)
			to_print += round
		. += "It has a secondary barrel loaded with \a [to_print]"
	else
		. += "It has a secondary barrel that is empty."


/*
 * Webley (Bay Port)
 */
/obj/item/gun/projectile/revolver/webley
	name = "patrol revolver"
	desc = "A rugged top break revolver commonly issued to planetary law enforcement offices. Uses .44 magnum rounds."
	description_fluff = "The Heberg-Hammarstrom Althing is a simple, head-wearing revolver made with an anti-corrosive alloy. \
	The Althing is advertised as being 'able to survive six months on the bottom of a frozen river and emerge full ready to \
	save a life'. Issued as standard sidearms to SifGuard frontier patrol."
	icon_state = "webley2"
	item_state = "webley2"
	caliber = ".44"
	handle_casings = CYCLE_CASINGS
	ammo_type = /obj/item/ammo_casing/a44

/*
 * Webley (Eris Port)
 */
/obj/item/gun/projectile/revolver/consul
	name = "\improper \"Consul\" Revolver"
	desc = "Are you feeling lucky, punk? Uses .44 rounds."
	icon_state = "inspector"
	item_state = "revolver"
	caliber = ".44"
	handle_casings = CYCLE_CASINGS
	ammo_type = /obj/item/ammo_casing/a44/rubber

/obj/item/gun/projectile/revolver/consul/proc/update_charge()
	cut_overlays()
	if(length(loaded)==0)
		add_overlay("inspector_off")
	else
		add_overlay("inspector_on")

DECLARE_APPEARANCE_PROC(/obj/item/gun/projectile/revolver/consul, TYPE_PROC_REF(/atom, appearance_overlays), list())
/obj/item/gun/projectile/revolver/consul/appearance_overlays()
	. = list()
	update_charge()


//Dunno why .380 ammo was in here but Im not touching it. Rest was moved to other files.

//.380
/obj/item/ammo_casing/a380
	desc = "A .380 bullet casing."
	caliber = ".380"
	projectile_type = /obj/item/projectile/bullet/pistol

/obj/item/ammo_magazine/m380
	name = "magazine (.380)"
	icon_state = "m92"
	mag_type = MAGAZINE
	MATERIAL_BULK(MAT_STEEL, 480)
	caliber = ".380"
	ammo_type = /obj/item/ammo_casing/a380
	max_ammo = 8
	multiple_sprites = 1


/obj/item/gun/projectile/revolver/slab
	name = "slab revolver"
	desc = "No coins. Cope."
	caliber = "14.5mm" //This will ultrakill anything in front of it
	ammo_type = /obj/item/ammo_casing/a145
	projectile_type = /obj/item/projectile/bullet/rifle/a145
	icon_state = "ukr"
	item_state = "ukr"
	icon = 'icons/obj/guns/altmarksman/altmarksman.dmi'
	fire_sound = SFX_WEAPONS_MARKSMANALT
	item_icons = list(
		slot_l_hand_str = 'icons/obj/guns/altmarksman/lefthand_guns.dmi',
		slot_r_hand_str = 'icons/obj/guns/altmarksman/righthand_guns.dmi',
		)

/obj/item/gun/projectile/revolver/nova
	name = "Nova"
	desc = "Heavily modified revolver, with alas only 6 round chamber but fiery firepower of 357 calibre. Make it count. Uses .357 rounds." // Yes I'm serious. -Spades
	icon_state = "nova"
	icon = 'icons/obj/gun_yw.dmi'

/obj/item/gun/projectile/revolver/cerberus
	name = "Cerberus"
	desc = "A high-power, fancy looking revolver that can stop nearly everything it's pointed at. Comes with a standard six-round-cylinder. There is ,Hesphiastos Industries, stamped along it's cylinder." // Yes I'm serious. -Spades
	icon_state = "cerb"
	icon = 'icons/obj/gun_yw.dmi'

/obj/item/gun/projectile/revolver/detective/proc/weapon_label_detective_name_answered(datum/act/request/A)
	if(!A.answer)
		return
	. = weapon_label_detective_name_apply(A)
	SStgui.update_uis(src)

/obj/item/gun/projectile/revolver/detective/proc/weapon_label_detective_name_apply(datum/act/request/A)
	var/datum/prompt/text/weapon_label_review/ask = A.answer
	return weapon_label_detective_name_stage(ask.weapon_operator, ask.weapon_held, ask.weapon_interaction, ask.value, TRUE)

/obj/item/gun/projectile/revolver/detective45/proc/weapon_label_detective45_name_answered(datum/act/request/A)
	if(!A.answer)
		return
	. = weapon_label_detective45_name_apply(A)
	SStgui.update_uis(src)

/obj/item/gun/projectile/revolver/detective45/proc/weapon_label_detective45_name_apply(datum/act/request/A)
	var/datum/prompt/text/weapon_label_review/ask = A.answer
	return weapon_label_detective45_name_stage(ask.weapon_operator, ask.weapon_held, ask.weapon_interaction, ask.value, TRUE)

/obj/item/gun/projectile/revolver/detective45/proc/weapon_label_detective45_style_answered(datum/act/request/A)
	if(!A.answer)
		return
	. = weapon_label_detective45_style_apply(A)
	SStgui.update_uis(src)

/obj/item/gun/projectile/revolver/detective45/proc/weapon_label_detective45_style_apply(datum/act/request/A)
	var/datum/prompt/choice/weapon_label_review/ask = A.answer
	return weapon_label_detective45_style_stage(ask.weapon_operator, ask.weapon_held, ask.weapon_interaction, ask.value, TRUE)
