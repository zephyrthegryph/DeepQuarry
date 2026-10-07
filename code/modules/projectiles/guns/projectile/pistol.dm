/*
 * M1911
 */
/obj/item/gun/projectile/colt
	var/unique_reskin
	name = ".45 pistol"
	desc = "A typical modern handgun produced for law enforcement. Uses .45 rounds."
	magazine_type = /obj/item/ammo_magazine/m45
	allowed_magazines = list(/obj/item/ammo_magazine/m45)
	projectile_type = /obj/item/projectile/bullet/pistol/medium
	icon_state = "colt"
	caliber = ".45"
	load_method = MAGAZINE
	move_delay = 0 // Pistols have move_delay of 0

/*
 * Detective M1911
 */
/obj/item/gun/projectile/colt/detective
	desc = "A standard law enforcement issue pistol. Uses .45 rounds."
	magazine_type = /obj/item/ammo_magazine/m45/rubber

CAPABILITIES(/obj/item/gun/projectile/colt/detective)
	op("rename", menu(), label("Name Gun"), needs(carried()),
		asks(/datum/prompt/text, fields = list("question" = "What do you want to name the gun?", "title" = "Rename Gun", "max_len" = MAX_NAME_LEN, "encode" = FALSE, "name_text" = TRUE, "timeout" = 0), step = "name"),
		then(PROC_REF(det_colt_verb_rename)))
	op("reskin", menu(), label("Resprite gun"), needs(carried()),
		asks(/datum/prompt/choice, fields = list("question" = "Choose your sprite!", "title" = "Resprite Gun", "choices" = computed(PROC_REF(reskin_choices)), "timeout" = 0), step = "sprite"),
		then(PROC_REF(det_colt_verb_reskin)))

/// Old Name Gun verb: Rename your gun. If you're Security.
/obj/item/gun/projectile/colt/detective/proc/det_colt_verb_rename(datum/act/op/A)
	var/mob/M = A.actor
	if(!security_naming_ok(M))
		to_chat(M, span_warning("You don\'t feel cool enough to name this gun, chump."))
		return OP_DECLINE
	if(!M.mind)
		return OP_DECLINE
	var/input = sanitizeSafe(A.step_value("name"))

	if(src && input && !M.stat && in_range(M,src))
		name = input
		to_chat(M, "You name the gun [input]. Say hello to your new friend.")
		return OP_OK
	return OP_DECLINE

/obj/item/gun/projectile/colt/detective/reskin_options()
	var/list/options = list()
	options["MarsTech P11 Spur (Bubba'd)"] = "mod_colt"
	options["MarsTech P11 Spur (Blued)"] = "blued_colt"
	options["MarsTech P11 Spur (Gold)"] = "gold_colt"
	options["MarsTech P11 Spur (Stainless)"] = "stainless_colt"
	options["MarsTech P11 Spur (Dark)"] = "dark_colt"
	options["MarsTech P11 Spur (Green)"] = "green_colt"
	options["MarsTech P11 Spur (Blue)"] = "blue_colt"
	return options

/// Old Resprite gun verb: Click to choose a sprite for your gun.
/obj/item/gun/projectile/colt/detective/proc/det_colt_verb_reskin(datum/act/op/A)
	var/mob/M = A.actor
	var/choice = A.step_value("sprite")
	var/list/options = reskin_options()
	if(src && choice && !M.stat && in_range(M,src))
		icon_state = options[choice]
		unique_reskin = options[choice]
		to_chat(M, "Your gun is now sprited as [choice]. Say hello to your new friend.")
		return OP_OK
	return OP_DECLINE

/*
 * Security Sidearm
 */
/obj/item/gun/projectile/sec
	name = ".45 pistol"
	desc = "The MT Mk58 is a cheap, ubiquitous sidearm, produced by MarsTech. Found pretty much everywhere humans are. Uses .45 rounds."
	description_fluff = "The leading civilian-sector high-quality small arms brand of Hephaestus Industries, \
	MarsTech has been the provider of choice for law enforcement and security forces for over 300 years."
	icon_state = "secguncomp"
	magazine_type = /obj/item/ammo_magazine/m45/rubber
	allowed_magazines = list(/obj/item/ammo_magazine/m45)
	projectile_type = /obj/item/projectile/bullet/pistol/medium
	caliber = ".45"
	load_method = MAGAZINE
	move_delay = 0 // Pistols have move_delay of 0

/// The look (the draw sweep: from its template).
/obj/item/gun/projectile/sec/draw(datum/look/look)
	..()
	look.state("secguncomp[ammo_magazine ? "" : "-e"]")

/obj/item/gun/projectile/sec/flash
	magazine_type = /obj/item/ammo_magazine/m45/flash
	move_delay = 0 // Pistols have move_delay of 0

/obj/item/gun/projectile/sec/wood
	name = "custom .45 pistol"
	desc = "The MT Mk58 is a cheap, ubiquitous sidearm, produced by MarsTech. This one has a sweet wooden grip. Uses .45 rounds."
	icon_state = "secgundark"

/// The look (the draw sweep: from its template).
/obj/item/gun/projectile/sec/wood/draw(datum/look/look)
	..()
	look.state("secgundark[ammo_magazine ? "" : "-e"]")

/*
 * Silenced Pistol
 */
/obj/item/gun/projectile/silenced
	name = "silenced pistol"
	desc = "A small, quiet, easily concealable gun with a built-in silencer. Uses .45 rounds."
	icon_state = "silenced_pistol"
	w_class = ITEMSIZE_NORMAL
	caliber = ".45"
	silenced = 1
	fire_delay = 1
	move_delay = 0 // Pistols have move_delay of 0
	recoil = 0
	load_method = MAGAZINE
	magazine_type = /obj/item/ammo_magazine/m45
	allowed_magazines = list(/obj/item/ammo_magazine/m45)
	projectile_type = /obj/item/projectile/bullet/pistol/medium

/obj/item/gun/projectile/silenced/empty
	magazine_type = null

/// The look (the draw sweep: from its template).
/obj/item/gun/projectile/silenced/draw(datum/look/look)
	..()
	look.state("silenced_pistol[ammo_magazine ? "" : "-e"]")

/*
 * Deagle
 */
/obj/item/gun/projectile/deagle
	name = "hand cannon"
	desc = "The PCA-55 Rarkajar perfect handgun for shooters with a need to hit targets through a wall and behind a fridge in your neighbor's house. Uses .44 rounds."
	description_fluff = "Pearlshield Consolidated Armories are far from the most cutting edge firearm manufacturer, but the Tajaran’s long tradition of war is rivaled only by humanity, \
	and the introduction of human technology to the Tajaran arms market has resulted in something of a revolution in finding new ways to kill each other at long distances with bullets. \
	Usually made with mass-production in mind, PCA weapons combine an eye for design with a great desire to make people dead."
	icon_state = "deagle"
	item_state = "deagle"
	force = 14.0
	caliber = ".44"
	fire_sound = SFX_WEAPONS_GUNSHOT_DEAGLE
	load_method = MAGAZINE
	magazine_type = /obj/item/ammo_magazine/m44
	allowed_magazines = list(/obj/item/ammo_magazine/m44)

/// The look (the draw sweep: from its template).
/obj/item/gun/projectile/deagle/draw(datum/look/look)
	..()
	look.state("[initial(icon_state)][ammo_magazine ? "" : "-e"]")

/obj/item/gun/projectile/deagle/gold
	desc = "A gold plated gun folded over a million times by superior Tajaran gunsmiths. Uses .44 rounds."
	icon_state = "deagleg"
	item_state = "deagleg"

/obj/item/gun/projectile/deagle/camo
	desc = "An off-brand non-Deagle for operators not operating operationally. Uses .44 rounds."
	icon_state = "deaglecamo"
	item_state = "deagleg"

/*
 * Gyro Pistol (Admin Abuse in gun form)
 */
/obj/item/gun/projectile/gyropistol
	name = "gyrojet pistol"
	desc = "Speak softly, and carry a big gun. Fires rare .75 caliber self-propelled exploding bolts--because fuck you and everything around you."
	icon_state = "gyropistol"
	max_shells = 8
	caliber = ".75"
	fire_sound = SFX_WEAPONS_RAILGUN
	ammo_type = "/obj/item/ammo_casing/a75"
	load_method = MAGAZINE
	magazine_type = /obj/item/ammo_magazine/m75
	allowed_magazines = list(/obj/item/ammo_magazine/m75)
	auto_eject = 1
	auto_eject_sound = SFX_WEAPONS_SMG_EMPTY_ALARM
	move_delay = 0 // Pistols have move_delay of 0

/// The look (the draw sweep: from its template).
/obj/item/gun/projectile/gyropistol/draw(datum/look/look)
	..()
	look.state("gyropistol[ammo_magazine ? "loaded" : ""]")

/*
 * Silencer
 */
/obj/item/silencer
	name = "silencer"
	desc = "a silencer"
	icon = 'icons/obj/gun.dmi'
	icon_state = "silencer"
	w_class = ITEMSIZE_SMALL

/*
 * Compact Pistol
 */
/obj/item/gun/projectile/pistol
	name = "compact pistol"
	desc = "The Lumoco Arms P3 \"Whisper\". A compact, easily concealable gun, though it's only compatible with compact magazines. Uses 9mm rounds."
	icon_state = "pistol"
	item_state = null
	w_class = ITEMSIZE_SMALL
	caliber = "9mm"
	silenced = 0
	load_method = MAGAZINE
	magazine_type = /obj/item/ammo_magazine/m9mm/compact
	allowed_magazines = list(/obj/item/ammo_magazine/m9mm/compact)
	projectile_type = /obj/item/projectile/bullet/pistol
	move_delay = 0 // Pistols have move_delay of 0

/obj/item/gun/projectile/pistol/flash
	magazine_type = /obj/item/ammo_magazine/m9mm/compact/flash

/// Old attack_hand.
/obj/item/gun/projectile/pistol/gun_hand(datum/act/op/A)
	var/mob/living/user = A.actor
	if(user.get_inactive_hand() == src)
		if(silenced)
			if(!user.item_is_in_hands(src))
				return ..()
			to_chat(user, span_notice("You unscrew [silenced] from [src]."))
			user.put_in_hands(silenced)
			silenced = 0
			w_class = ITEMSIZE_SMALL
			changed(src)
			return OP_OK
	return ..()

/// Old attackby.
/obj/item/gun/projectile/pistol/gun_item(datum/act/op/A)
	var/mob/living/user = A.actor
	var/obj/item/I = A.held
	if(istype(I, /obj/item/silencer))
		if(!user.item_is_in_hands(src))	//if we're not in his hands
			to_chat(user, span_notice("You'll need [src] in your hands to do that."))
			return OP_PASS
		user.drop_item()
		to_chat(user, span_notice("You screw [I] onto [src]."))
		silenced = I	//dodgy?
		w_class = ITEMSIZE_NORMAL
		I.forceMove(src) //put the silencer into the gun
		changed(src)
		return OP_PASS
	return ..()

/// The look (the draw sweep: from its template).
/obj/item/gun/projectile/pistol/draw(datum/look/look)
	..()
	look.state("pistol[silenced ? "-s" : ""][ammo_magazine ? "" : "-e"]")

/*
 * Pistol
 */
/obj/item/gun/projectile/aps
	name = "pistol"
	desc = "The Lumoco Arms P6 \"Rustle\". A standard self-defense pistol that takes standard magazines. Uses 9mm rounds."
	icon_state = "aps"
	item_state = null
	caliber = "9mm"
	silenced = 0
	load_method = MAGAZINE
	magazine_type = /obj/item/ammo_magazine/m9mm
	allowed_magazines = list(/obj/item/ammo_magazine/m9mm)
	projectile_type = /obj/item/projectile/bullet/pistol

/// Old attack_hand.
/obj/item/gun/projectile/aps/gun_hand(datum/act/op/A)
	var/mob/living/user = A.actor
	if(user.get_inactive_hand() == src)
		if(silenced)
			if(!user.item_is_in_hands(src))
				return ..()
			to_chat(user, span_notice("You unscrew [silenced] from [src]."))
			user.put_in_hands(silenced)
			silenced = 0
			changed(src)
			return OP_OK
	return ..()

/// Old attackby.
/obj/item/gun/projectile/aps/gun_item(datum/act/op/A)
	var/mob/living/user = A.actor
	var/obj/item/I = A.held
	if(istype(I, /obj/item/silencer))
		if(!user.item_is_in_hands(src))	//if we're not in his hands
			to_chat(user, span_notice("You'll need [src] in your hands to do that."))
			return OP_PASS
		user.drop_item()
		to_chat(user, span_notice("You screw [I] onto [src]."))
		silenced = I	//dodgy?
		I.forceMove(src) //put the silencer into the gun
		changed(src)
		return OP_PASS
	return ..()

/// The look (the draw sweep: from its template).
/obj/item/gun/projectile/aps/draw(datum/look/look)
	..()
	look.state("aps[silenced ? "-s" : ""][ammo_magazine ? "" : "-e"]")

/*
 * Zip Gun (yar har)
 */
/obj/item/gun/projectile/pirate
	name = "zip gun"
	desc = "Little more than a barrel, handle, and firing mechanism, cheap makeshift firearms like this one are not uncommon in frontier systems."
	icon_state = "zipgun"
	item_state = "sawnshotgun"
	handle_casings = CYCLE_CASINGS //player has to take the old casing out manually before reloading
	load_method = SINGLE_CASING
	max_shells = 1 //literally just a barrel

/obj/item/gun/projectile/pirate/Initialize(mapload)
	ammo_type = pick(GLOB.global_ammo_types)
	desc += " Uses [GLOB.global_ammo_types[ammo_type]] rounds."

	var/obj/item/ammo_casing/ammo = ammo_type
	caliber = initial(ammo.caliber)
	. = ..()

/*
 * Derringer
 */
/obj/item/gun/projectile/derringer
	name = "derringer"
	desc = "It's not size of your gun that matters, just the size of your load. Uses .357 rounds." //OHHH MYYY~
	icon_state = "derringer"
	item_state = "concealed"
	w_class = ITEMSIZE_SMALL
	handle_casings = CYCLE_CASINGS //player has to take the old casing out manually before reloading
	load_method = SINGLE_CASING
	max_shells = 2
	ammo_type = /obj/item/ammo_casing/a357
	projectile_type = /obj/item/projectile/bullet/pistol/strong

/*
 * Luger
 */
/obj/item/gun/projectile/luger
	name = "\improper Jindal T15 \"Mäuse\""
	desc = "Almost seventy percent guaranteed not to be a cheap rimworld knockoff! Accuracy, easy handling, and its distinctive appearance \
	make it popular among gun collectors. Uses 9mm rounds."
	description_fluff = "While Jindal’s rugged, affordable weapons intended for the colonial sector are a major export of Tau Ceti, \
	the Jindal Arms company is perhaps best known for its liberal sale of production licenses to just about any fledgling rimworld \
	venture who asks, and has cash to spare. While Jindal’s 'authentic' Binma-built weapons are renowned for their reliability, the \
	same cannot be said for the hundreds of low-grade (But technically legal) copies circulating the squalid habitats and smoke-filled \
	junk ships of the frontier."
	icon_state = "p08a"
	caliber = "9mm"
	load_method = MAGAZINE
	magazine_type = /obj/item/ammo_magazine/m9mm/luger
	allowed_magazines = list(/obj/item/ammo_magazine/m9mm/luger)
	projectile_type = /obj/item/projectile/bullet/pistol

/// The look (the draw sweep: from its template).
/obj/item/gun/projectile/luger/draw(datum/look/look)
	..()
	look.state("[initial(icon_state)][ammo_magazine ? "" : "-e"]")

/obj/item/gun/projectile/luger/brown
	name = "\improper Jindal T15b \"Mäuse\""
	description_fluff = "While wholly owned by Hephaestus Industries, the Jindal Arms brand does not appear prominently in most company catalogues \
	(Perhaps owing to its less than prestigious image), instead being sold almost exclusively through retailers and advertising platforms targeting \
	the 'independent roughneck' demographic."
	icon_state = "p08b"

/*
 * P92X (9mm Pistol)
 */
/obj/item/gun/projectile/p92x
	name = "9mm pistol"
	desc = "A widespread MarsTech sidearm called the P92X which is used by military, police, and security forces across the galaxy. Uses 9mm rounds."
	icon_state = "p92x"
	caliber = "9mm"
	load_method = MAGAZINE
	magazine_type = /obj/item/ammo_magazine/m9mm
	allowed_magazines = list(/obj/item/ammo_magazine/m9mm) // Can accept illegal large capacity magazines, or compact magazines.
	move_delay = 0 // Pistols have move_delay of 0

/// The look (the draw sweep: from its template).
/obj/item/gun/projectile/p92x/draw(datum/look/look)
	..()
	look.state("[initial(icon_state)][ammo_magazine ? "" : "-e"]")

/obj/item/gun/projectile/p92x/rubber
	magazine_type = /obj/item/ammo_magazine/m9mm/rubber

/obj/item/gun/projectile/p92x/brown
	icon_state = "p92xb"

/obj/item/gun/projectile/p92x/large
	magazine_type = /obj/item/ammo_magazine/m9mm/large // Spawns with illegal magazines.

/obj/item/gun/projectile/p92x/large/preban
	magazine_type = /obj/item/ammo_magazine/m9mm/large/preban // Spawns with big magazines that are legal.

/obj/item/gun/projectile/p92x/large/preban/hp
	magazine_type = /obj/item/ammo_magazine/m9mm/large/preban/hp // Spawns with legal hollow-point mag

/*
 * Giskard (Eris Port)
 */
/obj/item/gun/projectile/giskard
	name = "\improper \"Giskard\" holdout pistol"
	desc = "The FS HG .38 \"Giskard\" can even fit into the pocket! Uses .38 rounds."
	icon_state = "giskardcivil"
	item_state = "giskardcivil"
	caliber = ".38"
	magazine_type = /obj/item/ammo_magazine/m38
	allowed_magazines = list(/obj/item/ammo_magazine/m38)
	load_method = MAGAZINE
	w_class = ITEMSIZE_SMALL
	fire_sound = SFX_WEAPONS_GUNSHOT_PATHETIC

/// TRUE when a magazine with rounds in it is loaded.
/obj/item/gun/projectile/giskard/proc/appearance_loaded()
	return !!(ammo_magazine && length(ammo_magazine.stored_ammo))
/// The look (the draw sweep: from its template).
/obj/item/gun/projectile/giskard/draw(datum/look/look)
	..()
	look.state("giskardcivil[appearance_loaded() ? "" : "_empty"]")

/obj/item/gun/projectile/giskard/olivaw
	name = "\improper \"Olivaw\" holdout burst-pistol"
	desc = "The FS HG .38 \"Olivaw\" is a more advanced version of the \"Giskard\". \
	This one seems to have a two-round burst-fire mode. Uses .38 rounds."
	icon_state = "olivawcivil"
	item_state = "giskardcivil"
	firemodes = list(
		list(mode_name="semiauto",       burst=1, fire_delay=1.2,    move_delay=null, burst_accuracy=null, dispersion=null),
		list(mode_name="2-round bursts", burst=2, fire_delay=0.2, move_delay=4,    burst_accuracy=list(0,-15),       dispersion=list(1.2, 1.8)),
		)

/// The look (the draw sweep: from its template).
/obj/item/gun/projectile/giskard/olivaw/draw(datum/look/look)
	..()
	look.state("olivawcivil[appearance_loaded() ? "" : "-e"]")

/*
 * Makarov
 */
/obj/item/gun/projectile/makarov
	name = "makarov"
	desc = "A small, rugged pistol from a bygone era. Uses .38 rounds."
	icon_state = "makarov"
	item_state = "gun"
	caliber = ".38"
	magazine_type = /obj/item/ammo_magazine/m38
	allowed_magazines = list(/obj/item/ammo_magazine/m38)
	projectile_type = /obj/item/projectile/bullet/pistol/medium
	load_method = MAGAZINE
	w_class = ITEMSIZE_SMALL

/// The look (the draw sweep: from its template).
/obj/item/gun/projectile/makarov/draw(datum/look/look)
	..()
	look.state("Makarov[ammo_magazine ? "" : "-e"]")

/*
 * N99 (Fallout)
 */
/obj/item/gun/projectile/n99
	name = "promotional pistol"
	desc = "A very robust looking pistol that was made to promote 'Radius: Legend of the Demon Core', a popular \
	post-apocolyptic TV series. It's rare to come across as marketing swiftly switched to a toy version as \
	opposed to a live weapon due to safety concerns. Uses 10mm rounds."
	icon_state = "n99"
	item_state = "gun"
	caliber = "10mm"
	magazine_type = /obj/item/ammo_magazine/m10mm/pistol
	allowed_magazines = list(/obj/item/ammo_magazine/m10mm/pistol)
	projectile_type = /obj/item/projectile/bullet/pistol/medium
	load_method = MAGAZINE
	w_class = ITEMSIZE_NORMAL

/// The look (the draw sweep: from its template).
/obj/item/gun/projectile/n99/draw(datum/look/look)
	..()
	look.state("n99[ammo_magazine ? "" : "-e"]")

/obj/item/gun/projectile/n80
	icon_state = "n80"

/// The look (the draw sweep: from its template).
/obj/item/gun/projectile/n80/draw(datum/look/look)
	..()
	look.state("n80[ammo_magazine ? "" : "-e"]")

/*
 * Écureuil 10mm Pistol (Skyrat Port)
 */
/obj/item/gun/projectile/ecureuil
	name = "\improper \"Écureuil\" 10mm pistol"
	desc = "The 10mm MarsTech sidearm \"Écureuil\" is a well known military grade pistol. \
	It's mostly used by ranking members of NanoTrasen as a means of self defense. Uses 10mm rounds."
	icon_state = "ecureuil"
	item_state = "gun"
	caliber = "10mm"
	magazine_type = /obj/item/ammo_magazine/m10mm/pistol
	allowed_magazines = list(/obj/item/ammo_magazine/m10mm/pistol)
	projectile_type = /obj/item/projectile/bullet/pistol/medium
	load_method = MAGAZINE
	w_class = ITEMSIZE_NORMAL

/// The look (the draw sweep: from its template).
/obj/item/gun/projectile/ecureuil/draw(datum/look/look)
	..()
	look.state("ecureuil[ammo_magazine ? "" : "-e"]")

/obj/item/gun/projectile/ecureuil/tac
	name = "\improper Tactical \"Écureuil\" 10mm pistol"
	icon_state = "tac_ecureuil"

/// The look (the draw sweep: from its template).
/obj/item/gun/projectile/ecureuil/tac/draw(datum/look/look)
	..()
	look.state("tac_ecureuil[ammo_magazine ? "" : "-e"]")

/obj/item/gun/projectile/ecureuil/tac2
	name = "\improper Tactical \"Écureuil\" 10mm pistol"
	icon_state = "tac_ecureuil"

/// The look (the draw sweep: from its template).
/obj/item/gun/projectile/ecureuil/tac2/draw(datum/look/look)
	..()
	look.state("tac2_ecureuil[ammo_magazine ? "" : "-e"]")

/*
 * Lamia (Eris Port)
 */
/obj/item/gun/projectile/lamia
	name = "\improper FS HG .44 \"Lamia\""
	desc = "The FS HG .44 \"Lamia\" is the epitome of power in a handheld device. Uses .44 rounds."
	icon_state = "lamia"
	item_state = "revolver"
	caliber = ".44"
	magazine_type = /obj/item/ammo_magazine/m44/rubber
	allowed_magazines = list(/obj/item/ammo_magazine/m44,/obj/item/ammo_magazine/m44/rubber)
	load_method = MAGAZINE
	auto_eject = 1
	auto_eject_sound = SFX_WEAPONS_SMG_EMPTY_ALARM
	move_delay = 0 // Pistols have move_delay of 0

/// Magazine fill rounded to the nearest 33%, or null with no magazine.
/obj/item/gun/projectile/lamia/proc/appearance_fill()
	if(!ammo_magazine)
		return null
	return round(length(ammo_magazine.stored_ammo) * 100 / ammo_magazine.max_ammo, 33)
/// The look (the draw sweep: from its layers).
/obj/item/gun/projectile/lamia/draw(datum/look/look)
	..()
	switch("[appearance_fill()]")
		if("0")
			look.overlay("lamia_0")
		if("33")
			look.overlay("lamia_33")
		if("66")
			look.overlay("lamia_66")
		if("99")
			look.overlay("lamia_99")

/******GLOCK******/
/obj/item/gun/projectile/automatic/glock
	name = "Glock G18"
	desc = "A automatic handgun that uses .9mm rounds."
	icon_state = "glock"
	item_state = "glock"
	icon = 'icons/obj/gun_yw.dmi'
	caliber = "9mm"
	load_method = MAGAZINE
	fire_sound = SFX_WEAPONS_45PISTOL_VR
	magazine_type = /obj/item/ammo_magazine/m9mm
	allowed_magazines = list(/obj/item/ammo_magazine/m9mm)

	firemodes = list(
	list(mode_name="semiauto",       burst=1, fire_delay=0,    move_delay=null, burst_accuracy=null, dispersion=null),
	list(mode_name="short bursts",	burst=5, move_delay=6, burst_accuracy = list(0,-1,-1,-2,-2), dispersion = list(0.6, 1.0, 1.0, 1.0, 1.2))
	)

/// The look (the draw sweep: from its template).
/obj/item/gun/projectile/automatic/glock/draw(datum/look/look)
	..()
	look.state("[initial(icon_state)][ammo_magazine ? "" : "-empty"]")

/*******PPK*******/
/obj/item/gun/projectile/ppk
	name = "PPK"
	desc = "A handgun that uses .9mm rounds."
	icon_state = "ppk"
	item_state = "ppk"
	icon = 'icons/obj/gun_yw.dmi'
	caliber = "9mm"
	load_method = MAGAZINE
	fire_sound = SFX_WEAPONS_45PISTOL_VR
	magazine_type = /obj/item/ammo_magazine/m9mm
	allowed_magazines = list(/obj/item/ammo_magazine/m9mm)

/// The look (the draw sweep: from its template).
/obj/item/gun/projectile/ppk/draw(datum/look/look)
	..()
	look.state("[initial(icon_state)][ammo_magazine ? "" : "-empty"]")

/*******M2024*******/
/obj/item/gun/projectile/m2024
	name = "Custom M2024"
	desc = "Customized model of old yet reliable sol .45 handgun with the name 'M2024'. Used to be popular, still appreciated for it's effectiveness."
	icon_state = "m2024"
	item_state = "m2024"
	icon = 'icons/obj/gun_yw.dmi'
	caliber = ".45"
	load_method = MAGAZINE
	fire_sound = SFX_WEAPONS_45PISTOL_VR
	magazine_type = /obj/item/ammo_magazine/m2024
	allowed_magazines = list(/obj/item/ammo_magazine/m2024,/obj/item/ammo_magazine/m45)

/// The look (the draw sweep: from its template).
/obj/item/gun/projectile/m2024/draw(datum/look/look)
	..()
	look.state("[initial(icon_state)][ammo_magazine ? "" : "-empty"]")

/*******M1911 Custom fluff*******/
/obj/item/gun/projectile/fluff/m1911
	name = "M1911 Custom"
	desc = "A modernized, customized M1911 pistol with a rail for attachments such as flashlight or laser sight (fooken laser sights). It's engraved, and the engraving says, 'For honorable duty.' It's original, Sol Gov firearm from Earth, not a cheap mars replica."
	icon_state = "m1911"
	item_state = "m1911"
	icon = 'icons/obj/gun_yw.dmi'
	caliber = ".45"
	load_method = MAGAZINE
	fire_sound = SFX_WEAPONS_45PISTOL_VR
	magazine_type = /obj/item/ammo_magazine/m45
	allowed_magazines = list(/obj/item/ammo_magazine/m45)

/datum/prompt/text/weapon_setting_review
	timeout = 0
	var/mob/settings_operator
	var/settings_operator_expected = FALSE
	var/obj/item/settings_held
	var/settings_held_expected = FALSE
	var/datum/interaction/settings_interaction
	var/settings_interaction_expected = FALSE

CAPABILITIES(/datum/prompt/text/weapon_setting_review)
	ref_one(nameof(settings_operator), /mob)
	ref_one(nameof(settings_held), /obj/item)
	ref_one(nameof(settings_interaction), /datum/interaction)

/datum/prompt/text/weapon_setting_review/prepare(datum/act/context)
	. = ..()
	var/mob/captured_operator = settings_operator
	settings_operator_expected = !isnull(captured_operator)
	rel_clear(src, nameof(settings_operator))
	if(captured_operator && !QDELETED(captured_operator))
		rel_set(src, nameof(settings_operator), captured_operator)
	var/obj/item/captured_held = settings_held
	settings_held_expected = !isnull(captured_held)
	rel_clear(src, nameof(settings_held))
	if(captured_held && !QDELETED(captured_held))
		rel_set(src, nameof(settings_held), captured_held)
	var/datum/interaction/captured_interaction = settings_interaction
	settings_interaction_expected = !isnull(captured_interaction)
	rel_clear(src, nameof(settings_interaction))
	if(captured_interaction && !QDELETED(captured_interaction))
		rel_set(src, nameof(settings_interaction), captured_interaction)

/datum/prompt/text/weapon_setting_review/recheck_extra()
	if((settings_operator_expected && QDELETED(settings_operator)) || (settings_held_expected && QDELETED(settings_held)) || (settings_interaction_expected && QDELETED(settings_interaction)))
		return "gone"

/datum/prompt/choice/weapon_setting_review
	timeout = 0
	var/mob/settings_operator
	var/settings_operator_expected = FALSE
	var/obj/item/settings_held
	var/settings_held_expected = FALSE
	var/datum/interaction/settings_interaction
	var/settings_interaction_expected = FALSE

CAPABILITIES(/datum/prompt/choice/weapon_setting_review)
	ref_one(nameof(settings_operator), /mob)
	ref_one(nameof(settings_held), /obj/item)
	ref_one(nameof(settings_interaction), /datum/interaction)

/datum/prompt/choice/weapon_setting_review/prepare(datum/act/context)
	. = ..()
	var/mob/captured_operator = settings_operator
	settings_operator_expected = !isnull(captured_operator)
	rel_clear(src, nameof(settings_operator))
	if(captured_operator && !QDELETED(captured_operator))
		rel_set(src, nameof(settings_operator), captured_operator)
	var/obj/item/captured_held = settings_held
	settings_held_expected = !isnull(captured_held)
	rel_clear(src, nameof(settings_held))
	if(captured_held && !QDELETED(captured_held))
		rel_set(src, nameof(settings_held), captured_held)
	var/datum/interaction/captured_interaction = settings_interaction
	settings_interaction_expected = !isnull(captured_interaction)
	rel_clear(src, nameof(settings_interaction))
	if(captured_interaction && !QDELETED(captured_interaction))
		rel_set(src, nameof(settings_interaction), captured_interaction)

/datum/prompt/choice/weapon_setting_review/recheck_extra()
	if((settings_operator_expected && QDELETED(settings_operator)) || (settings_held_expected && QDELETED(settings_held)) || (settings_interaction_expected && QDELETED(settings_interaction)))
		return "gone"
	if(!isnull(value) && isdatum(value))
		var/datum/selected = value
		if(QDELETED(selected))
			return "gone"
