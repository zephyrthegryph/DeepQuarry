/*
 * Daka SMG (Code Base)
 */
/obj/item/gun/projectile/automatic //This should never be spawned in, it is just here because of code necessities.
	name = "daka SMG"
	desc = "A small SMG. You really shouldn't be able to get this gun. Uses 9mm rounds."
	icon_state = "c05r"	//Used because it's not used anywhere else
	load_method = SPEEDLOADER
	ammo_type = /obj/item/ammo_casing/a9mm
	projectile_type = /obj/item/projectile/bullet/pistol

//Burst is the number of bullets fired; Fire delay is the time you have to wait to shoot the gun again, Move delay is the same but for moving after shooting. .
//Burst accuracy is the accuracy of each bullet fired in the burst. Dispersion is how much the bullets will 'spread' away from where you aimed.

	firemodes = list(
		list(mode_name="semiauto",       burst=1, fire_delay=0.1,    move_delay=null, burst_accuracy=null, dispersion=null),
		list(mode_name="3-round bursts", burst=3, fire_delay=null, move_delay=4,    burst_accuracy=list(0,-15,-15), dispersion=list(0.0, 0.6, 1.0)))

/*
 * Advanced SMG
 */

/obj/item/gun/projectile/automatic/advanced_smg
	name = "advanced SMG"
	desc = "An advanced submachine gun with a reflective laser optic that makes burst fire less inaccurate than other SMGs. Uses 9mm rounds."
	icon = 'icons/obj/gun.dmi'
	icon_state = "advanced_smg-e"
	w_class = ITEMSIZE_NORMAL
	load_method = MAGAZINE
	caliber = "9mm"
	slot_flags = SLOT_BELT
	magazine_type = null // R&D builds this. Starts unloaded.
	allowed_magazines = list(/obj/item/ammo_magazine/m9mmAdvanced, /obj/item/ammo_magazine/m9mm)
	fire_sound = "sound/weapons/gunshot_pathetic.ogg"

	firemodes = list(
		list(mode_name="semiauto",       burst=1, fire_delay=0.1,    move_delay=null, burst_accuracy=null, dispersion=null),
		list(mode_name="3-round bursts", burst=3, fire_delay=null, move_delay=4,    burst_accuracy=list(0,-10,-10), dispersion=list(0.0, 0.3, 0.6))
	)

/obj/item/gun/projectile/automatic/advanced_smg/update_icon()
	..()
	if(ammo_magazine)
		icon_state = "advanced_smg"
	else
		icon_state = "advanced_smg-e"

/obj/item/gun/projectile/automatic/advanced_smg/loaded
	magazine_type = /obj/item/ammo_magazine/m9mmAdvanced

/*
 * C-20r
 */

/* remove: Moved to automatic_ch.dm. *

/obj/item/gun/projectile/automatic/c20r
	name = "submachine gun"
	desc = "The C-20r is a lightweight and rapid firing SMG, for when you REALLY need someone dead. It has 'Scarborough Arms - Per falcis, per pravitas', inscribed on the stock. Uses 10mm rounds."
	description_fluff = "The C-20r is produced by Scarborough Arms, a specialist high-end weapons manufacturer based out of Titan, Sol. Scarborough has resisted numerous efforts by Trans-Stellars to acquire the brand since its founding in 2511, and has gained a dedicated following among a certain flavor of private operative."
	icon = 'icons/obj/64x32guns_ch.dmi' //Chomp Edit
	icon_expected_width = 64 //Chomp EDIT
	icon_state = "c20r"
	item_state = "c20r"
	w_class = ITEMSIZE_NORMAL
	force = 10
	caliber = "10mm"
	slot_flags = SLOT_BELT|SLOT_BACK
	load_method = MAGAZINE
	magazine_type = /obj/item/ammo_magazine/m10mm
	allowed_magazines = list(/obj/item/ammo_magazine/m10mm)
	projectile_type = /obj/item/projectile/bullet/pistol/medium
	auto_eject = 1
	auto_eject_sound = 'sound/weapons/smg_empty_alarm.ogg'

/obj/item/gun/projectile/automatic/c20r/rubber
	magazine_type = /obj/item/ammo_magazine/m10mm/rubber

/obj/item/gun/projectile/automatic/c20r/empty
	magazine_type = null

/obj/item/gun/projectile/automatic/c20r/update_icon()
	..()
	if(ammo_magazine)
		icon_state = "c20r-[round(ammo_magazine.stored_ammo.len,4)]"
	else
		icon_state = "c20r"
	return

 * remove: Moved to automatic_ch.dm. */

/*
 * Assault Carbine (STS-35)
 */
/obj/item/gun/projectile/automatic/sts35
	name = "assault rifle"
	desc = "The rugged Jindal Arms STS-35 is a durable automatic weapon of a make popular on the frontier worlds. Uses 5.45mm rounds."
	description_fluff = "A subsidiary of Hephaestus Industries, While Jindal’s rugged, affordable weapons intended for the colonial sector are a major export of Tau Ceti, \
	the Jindal Arms company is perhaps best known for its liberal sale of production licenses to just about any fledgling rimworld venture who asks, and has cash to spare. \
	While Jindal’s 'authentic' Binma-built weapons are renowned for their reliability, the same cannot be said for the hundreds of low-grade (But technically legal) \
	copies circulating the squalid habitats and smoke-filled junk ships of the frontier."
	icon_state = "arifle"
	item_state = "arifle"
	wielded_item_state = "arifle-wielded"
	item_state = null
	w_class = ITEMSIZE_HUGE //.
	force = 10
	caliber = "5.45mm"
	slot_flags = SLOT_BACK
	load_method = MAGAZINE
	magazine_type = /obj/item/ammo_magazine/m545
	allowed_magazines = list(/obj/item/ammo_magazine/m545)
	projectile_type = /obj/item/projectile/bullet/rifle/a545
	fire_sound = "sound/weapons/ballistics/a762.ogg"

	one_handed_penalty = 30

	firemodes = list(
		list(mode_name="semiauto",       burst=1, fire_delay=0.1,    move_delay=null, burst_accuracy=null, dispersion=null),
		list(mode_name="3-round bursts", burst=3, fire_delay=null, move_delay=6,    burst_accuracy=list(0,-15,-30), dispersion=list(0.0, 0.6, 0.6))
		)

/obj/item/gun/projectile/automatic/sts35/update_icon(ignore_inhands)
	..()
	if(istype(ammo_magazine,/obj/item/ammo_magazine/m545/small))
		icon_state = "arifle-small" // If using the small magazines, use the small magazine sprite.
	else
		icon_state = (ammo_magazine)? "arifle" : "arifle-empty"
	if(!ignore_inhands) update_held_icon()

/*
 * X-9mm (PDW)
 */
/obj/item/gun/projectile/automatic/pdw
	name = "personal defense weapon"
	desc = "The X-9mm is a select-fire personal defense weapon designed in-house by Xing Private Security. It was made to compete with the WT550 Saber, \
	but never caught on with NanoTrasen. Uses 9mm rounds."
	icon_state = "pdw"
	item_state = "c20r"
	w_class = ITEMSIZE_NORMAL
	caliber = "9mm"
	slot_flags = SLOT_BELT
	load_method = MAGAZINE
	magazine_type = /obj/item/ammo_magazine/m9mmAdvanced
	allowed_magazines = list(/obj/item/ammo_magazine/m9mmAdvanced)
	fire_sound = "sound/weapons/gunshot_pathetic.ogg"

	firemodes = list(
		list(mode_name="semiauto",       burst=1, fire_delay=0.1,    move_delay=null, burst_accuracy=null, dispersion=null),
		list(mode_name="3-round bursts", burst=3, fire_delay=null, move_delay=6,    burst_accuracy=list(0,-15,-30), dispersion=list(0.0, 0.6, 0.6))
		)

/obj/item/gun/projectile/automatic/pdw/update_icon(ignore_inhands)
	..()
	if(ammo_magazine)
		icon_state = "pdw"
	else
		icon_state = "pdw-e"
	return

/*
 * Machine Pistol (WT550)
 */
/obj/item/gun/projectile/automatic/wt550
	name = "machine pistol"
	desc = "The WT550 Saber is a cheap self-defense weapon mass-produced by Ward-Takahashi for paramilitary and private use. Uses 9mm rounds."
	icon = 'icons/obj/64x32guns_ch.dmi' //Chomp EDIT
	icon_expected_width = 64 //Chomp EDIT
	icon_state = "wt550"
	item_state = "wt550"
	w_class = ITEMSIZE_NORMAL
	caliber = "9mm"
	slot_flags = SLOT_BELT
	ammo_type = "/obj/item/ammo_casing/a9mmr"
	load_method = MAGAZINE
	magazine_type = /obj/item/ammo_magazine/m9mmt/rubber
	allowed_magazines = list(/obj/item/ammo_magazine/m9mmt)
	projectile_type = /obj/item/projectile/bullet/pistol/medium
	move_delay = 0 // Pistols have move_delay of 0
	fire_sound = "sound/weapons/gunshot_pathetic.ogg"

/obj/item/gun/projectile/automatic/wt550/update_icon()
	..()
	if(ammo_magazine)
		icon_state = "wt550-[round(ammo_magazine.stored_ammo.len,4)]"
	else
		icon_state = "wt550"
	return

/*
 * Battle Rifle (Z8)
 */
/obj/item/gun/projectile/automatic/z8
	name = "battle rifle"
	desc = "The Z8 Bulldog is an older model battle rifle, made by the now defunct Zendai Foundries. Makes you feel like an old-school badass when you hold it, \
	even though it can only hold 10 round magazines. Uses 7.62mm rounds and has an under barrel grenade launcher."
	description_fluff = "Zendai Foundries was a well-respected mid-sized arms company that operated until 2508, when it was acquired by Hephaestus Industries. \
	Plans to integrate the brand into wider corporate operations were brought to an abrupt halt by the SolGov-Hegemony war, and the company was left by the wayside. \
	Hephaestus still produces replacement parts for many of Zendai's most popular weapons, including the Z8 Bulldog, and a great detail remain in service."
	icon = 'icons/obj/64x32guns_ch.dmi' //Chomp EDIT
	icon_expected_width = 64 //Chomp EDIT
	icon_state = "carbine" // This isn't a carbine. :T
	item_state = "z8carbine"
	wielded_item_state = "z8bulldog-wielded"
	w_class = ITEMSIZE_HUGE //.
	force = 10
	caliber = "7.62mm"
	slot_flags = SLOT_BACK
	load_method = MAGAZINE
	magazine_type = /obj/item/ammo_magazine/m762
	allowed_magazines = list(/obj/item/ammo_magazine/m762)
	projectile_type = /obj/item/projectile/bullet/rifle/a762
	auto_eject = 1
	auto_eject_sound = 'sound/weapons/smg_empty_alarm.ogg'
	fire_sound = "sound/weapons/ballistics/a762.ogg"

	one_handed_penalty = 60

	burst_delay = 4
	firemodes = list(
		list(mode_name="semiauto",       burst=1,    fire_delay=0.1,    move_delay=null, use_launcher=null, burst_accuracy=null, dispersion=null),
		list(mode_name="2-round bursts", burst=2,    fire_delay=null, move_delay=6,    use_launcher=null, burst_accuracy=list(0,-15), dispersion=list(0.0, 0.6)),
		list(mode_name="fire grenades",  burst=null, fire_delay=null, move_delay=null, use_launcher=1,    burst_accuracy=null, dispersion=null)
		)

	var/use_launcher = 0
	var/obj/item/gun/launcher/grenade/underslung/launcher

/obj/item/gun/projectile/automatic/z8/Initialize(mapload)
	. = ..()
	launcher = new(src)

/obj/item/gun/projectile/automatic/z8/attackby(obj/item/I, mob/user)
	if((istype(I, /obj/item/grenade)))
		launcher.load(I, user)
	else
		..()

/obj/item/gun/projectile/automatic/z8/attack_hand(mob/user)
	if(user.get_inactive_hand() == src && use_launcher)
		launcher.unload(user)
	else
		..()

/obj/item/gun/projectile/automatic/z8/Fire(atom/target, mob/living/user, params, pointblank=0, reflex=0)
	if(use_launcher)
		launcher.Fire(target, user, params, pointblank, reflex)
		if(!launcher.chambered)
			switch_firemodes(user) //switch back automatically
	else
		..()

/obj/item/gun/projectile/automatic/z8/update_icon(ignore_inhands)
	..()
	if(ammo_magazine)
		icon_state = "carbine-[round(ammo_magazine.stored_ammo.len,2)]"
	else
		icon_state = "carbine"
	if(!ignore_inhands) update_held_icon()
	return

/obj/item/gun/projectile/automatic/z8/examine(mob/user)
	. = ..()
	if(launcher.chambered)
		. += "\The [launcher] has \a [launcher.chambered] loaded."
	else
		. += "\The [launcher] is empty."

/obj/item/gun/projectile/automatic/z8/empty
	magazine_type = null

/*
 * LMG (L6 SAW)
 */
/obj/item/gun/projectile/automatic/l6_saw
	name = "light machine gun"
	desc = "A rather sturdily made L6 SAW with a reassuringly ergonomic pistol grip. 'Hephaestus Industries' is engraved on the receiver. Uses 5.45mm rounds. It's also compatible with magazines from STS-35 assault rifles."
	description_fluff = "The leading arms producer in the SCG, Hephaestus typically only uses its 'top level' branding for its military-grade equipment used by professional armed forces across human space."
	icon = 'icons/obj/64x32guns_ch.dmi' //Chomp EDIT
	icon_expected_width = 64 //Chomp EDIT
	icon_state = "l6closed100"
	item_state = "l6closed"
	wielded_item_state = "genericLMG-wielded"
	w_class = ITEMSIZE_HUGE //.
	force = 10
	slot_flags = 0
	max_shells = 50
	caliber = "5.45mm"
	slot_flags = SLOT_BACK
	load_method = MAGAZINE
	magazine_type = /obj/item/ammo_magazine/m545saw
	allowed_magazines = list(/obj/item/ammo_magazine/m545saw, /obj/item/ammo_magazine/m545)
	projectile_type = /obj/item/projectile/bullet/rifle/a545
	fire_sound = "sound/weapons/gunshot_light.ogg"

	one_handed_penalty = 90

	var/cover_open = 0

	firemodes = list(
		list(mode_name="semiauto",       burst=1, fire_delay=0.1,    move_delay=null, burst_accuracy=null, dispersion=null),
		list(mode_name="3-round bursts", burst=3,burst_delay=1 ,fire_delay=null, move_delay=4,    burst_accuracy=list(0,-15,-15), dispersion=list(0.0, 0.6, 1.0)), // firerate buff
		list(mode_name="short bursts",	burst=5,burst_delay=1 ,move_delay=3, burst_accuracy = list(0,-15,-15,-30,-30), dispersion = list(0.6, 1.0, 1.0, 1.0, 1.2)) // firerate buff
		)

	special_weapon_handling = TRUE

/obj/item/gun/projectile/automatic/l6_saw/special_check(mob/user)
	if(cover_open)
		to_chat(user, span_warning("[src]'s cover is open! Close it before firing!"))
		return 0
	return ..()

/obj/item/gun/projectile/automatic/l6_saw/proc/toggle_cover(mob/user)
	cover_open = !cover_open
	to_chat(user, span_notice("You [cover_open ? "open" : "close"] [src]'s cover."))
	update_icon()
	update_held_icon()

/obj/item/gun/projectile/automatic/l6_saw/attack_self(mob/user)
	. = ..(user)
	if(.)
		return TRUE
	if(cover_open)
		toggle_cover(user) //close the cover
	else
		return ..(user, TRUE) //once closed, behave like normal

/obj/item/gun/projectile/automatic/l6_saw/attack_hand(mob/user as mob)
	if(!cover_open && user.get_inactive_hand() == src)
		toggle_cover(user) //open the cover
	else
		return ..() //once open, behave like normal

/obj/item/gun/projectile/automatic/l6_saw/update_icon()
	if(istype(ammo_magazine,/obj/item/ammo_magazine/m762))
		icon_state = "l6[cover_open ? "open" : "closed"]mag"
		item_state = icon_state
	else
		icon_state = "l6[cover_open ? "open" : "closed"][ammo_magazine ? round(ammo_magazine.stored_ammo.len, 25) : "-empty"]"
		item_state = "l6[cover_open ? "open" : "closed"][ammo_magazine ? "" : "-empty"]"
	update_held_icon()

/obj/item/gun/projectile/automatic/l6_saw/load_ammo(obj/item/A, mob/user)
	if(!cover_open)
		to_chat(user, span_warning("You need to open the cover to load [src]."))
		return
	..()

/obj/item/gun/projectile/automatic/l6_saw/unload_ammo(mob/user, allow_dump=1)
	if(!cover_open)
		to_chat(user, span_warning("You need to open the cover to unload [src]."))
		return
	..()

/*
 * Automatic Shotgun (AS-24)
 */
/obj/item/gun/projectile/automatic/as24
	name = "automatic shotgun"
	desc = "The AS-24 is a rugged looking automatic shotgun produced exclusively for the SCG Fleet by Hephaestus \
	Industries. For very obvious reasons, it's illegal to own in many juristictions. Uses 12g rounds."
	description_fluff = "The leading arms producer in the SCG, Hephaestus typically only uses its 'top level' \
	branding for its military-grade equipment used by professional armed forces across human space."
	icon_state = "ashot"
	item_state = "ashot"
	wielded_item_state = "ashot-wielded"
	w_class = ITEMSIZE_HUGE //.
	force = 10
	caliber = "12g"
	slot_flags = SLOT_BACK
	load_method = MAGAZINE
	magazine_type = /obj/item/ammo_magazine/m12gdrum
	allowed_magazines = list(/obj/item/ammo_magazine/m12gdrum)
	projectile_type = /obj/item/projectile/bullet/shotgun

	one_handed_penalty = 60

	firemodes = list(
		list(mode_name="semiauto", burst=1, fire_delay=0.1),
		list(mode_name="3-round bursts", burst=3, move_delay=6, burst_accuracy = list(0,-15,-15,-30,-30), dispersion = list(0.0, 0.6, 0.6))
		)

/obj/item/gun/projectile/automatic/as24/update_icon()
	..()
	if(ammo_magazine)
		icon_state = "ashot"
	else
		icon_state = "ashot-empty"
	return

/*
 * Uzi
 */
/obj/item/gun/projectile/automatic/mini_uzi
	name = "micro-smg"
	desc = "The infamous ProTek Spitz is a lightweight, compact, fast firing machine pistol. Cheaply produced under the ProTek consumer brand, the Spitz seems to find its way into every corner of the galaxy. Uses .45 rounds."
	description_fluff = "Budget-grade weapons for the budget-grade consumer! Hephaestus’ low-end brand of cheaply made, low-maintenance personal defense weapons for those who just need a handgun with absolutely no frills. \
	Early ProTek weapons were notoriously unsafe and unreliable, though more recent designs have improved somewhat - they still aren’t very good. \
	Though sold for a pittance, the profit margin is too irresistible for Hephaestus to discontinue the brand."
	icon = 'icons/obj/64x32guns_ch.dmi' //Chomp EDIT
	icon_expected_width = 64 //Chomp EDIT
	icon_state = "mini-uzi" //Chomp EDIT - uzi --> mini-uzi
	w_class = ITEMSIZE_NORMAL
	load_method = MAGAZINE
	caliber = ".45"
	magazine_type = /obj/item/ammo_magazine/m45uzi
	allowed_magazines = list(/obj/item/ammo_magazine/m45uzi)
	move_delay = 0 // Pistols have move_delay of 0
	var/is64x32 = TRUE
	var/is_picked_up = FALSE
	fire_sound = "sound/weapons/gunshot_pathetic.ogg"

	firemodes = list(
		list(mode_name="semiauto", burst=1, fire_delay=0.1),
		list(mode_name="3-round bursts", burst=3, burst_delay=1, fire_delay=4, move_delay=4, burst_accuracy = list(0,-15,-15,-30,-30), dispersion = list(0.6, 1.0, 1.0))
		)

/obj/item/gun/projectile/automatic/mini_uzi/update_icon()
	..()
	if(ammo_magazine)
		icon_state = "mini-uzi"
	else
		icon_state = "mini-uzi-empty"

// Uzi tilting
/obj/item/gun/projectile/automatic/mini_uzi/Initialize(mapload)
	. = ..()
	if(is64x32)
		update_transform()

/obj/item/gun/projectile/automatic/mini_uzi/equipped(mob/living/user, slot)
	. = ..()
	is_picked_up = TRUE
	update_transform()

/obj/item/gun/projectile/automatic/mini_uzi/pickup()
	. = ..()
	is_picked_up = TRUE
	update_transform()

/obj/item/gun/projectile/automatic/mini_uzi/dropped(mob/user, equipping, slot)
	. = ..()
	is_picked_up = FALSE
	update_transform()

/obj/item/gun/projectile/automatic/mini_uzi/update_transform()
	. = ..()
	if(is64x32)
		if(is_picked_up)
			transform = transform.Turn(-45)
		transform = transform.Translate(-16,0)
// end: Uzi tilting

/* Commented out, moved to automatic_ch.dm *
/obj/item/gun/projectile/automatic/p90
	name = "personal defense weapon"
	desc = "The H90K is a compact, large capacity submachine gun produced by MarsTech. Despite its fierce reputation, it still manages to feel like a toy. Uses 9mm rounds."
	description_fluff = "The leading civilian-sector high-quality small arms brand of Hephaestus Industries, MarsTech has been the provider of choice for law enforcement and security forces for over 300 years."
	icon_state = "p90smg"
	item_state = "p90"
	w_class = ITEMSIZE_NORMAL
	caliber = "9mm"
	slot_flags = SLOT_BELT // ToDo: Belt sprite.
	load_method = MAGAZINE
	magazine_type = /obj/item/ammo_magazine/m9mmp90
	allowed_magazines = list(/obj/item/ammo_magazine/m9mmp90, /obj/item/ammo_magazine/m9mmt) // ToDo: New sprite for the different mag.

	firemodes = list(
		list(mode_name="semiauto", burst=1, fire_delay=0.1),
		list(mode_name="3-round bursts", burst=3, fire_delay=null, move_delay=4,    burst_accuracy=list(0,-15,-15), dispersion=list(0.0, 0.6, 1.0))
		)

/obj/item/gun/projectile/automatic/p90/update_icon()
	icon_state = "p90smg-[ammo_magazine ? round(ammo_magazine.stored_ammo.len, 6) : "empty"]"
* Commented out, moved to automatic_ch.dm */

/*
 * Tommy Gun
 */
/obj/item/gun/projectile/automatic/tommygun
	name = "\improper Tommy Gun"
	desc = "This weapon was made famous by gangsters in the 20th century. Cybersun Industries is currently reproducing these for a target market of historic gun collectors and classy criminals. Uses .45 rounds."
	description_fluff = "Cybersun Industries is a minor arms manufacturer specialising in replica firearms from eras past. Though they offer a wide selection of made-to-order models, their products are seen as little more than novelty items to most serious collectors."
	icon_state = "tommygun"
	item_state = "stg44"
	w_class = ITEMSIZE_NORMAL
	caliber = ".45"
	slot_flags = SLOT_BELT // ToDo: Belt sprite.
	load_method = MAGAZINE
	magazine_type = /obj/item/ammo_magazine/m45tommy
	allowed_magazines = list(/obj/item/ammo_magazine/m45tommy, /obj/item/ammo_magazine/m45tommydrum)
	fire_sound = "sound/weapons/gunshot1.ogg"

	firemodes = list(
		list(mode_name="semiauto", burst=1, fire_delay=0.1),
		list(mode_name="3-round bursts", burst=3, fire_delay=null, move_delay=4,    burst_accuracy=list(0,-15,-15), dispersion=list(0.0, 0.6, 1.0))
		)

/obj/item/gun/projectile/automatic/tommygun/update_icon()
	if(istype(ammo_magazine,/obj/item/ammo_magazine/m45tommy))
		icon_state = "tommygun-mag"
	else if(istype(ammo_magazine,/obj/item/ammo_magazine/m45tommydrum))
		icon_state = "tommygun-drum"
	else
		icon_state = "tommygun-empty"
	update_held_icon()

/*
 * Bullpup Rifle
 */
/obj/item/gun/projectile/automatic/bullpup // Admin abuse assault rifle. ToDo: Make this less shit. Maybe remove its autofire, and make it spawn with only 10 rounds at start.
	name = "bullpup rifle"
	desc = "The bullpup configured GP3000 is a battle rifle produced by Gurov Projectile Weapons LLC. It is sold almost exclusively to standing armies. Uses 7.62mm rounds."
	icon_state = "bullpup-small"
	item_state = "bullpup"
	wielded_item_state = "sexyrifle-wielded" //Placeholder, this is a bullpup at least
	w_class = ITEMSIZE_LARGE
	force = 10
	caliber = "7.62mm"
	slot_flags = SLOT_BACK
	load_method = MAGAZINE
	magazine_type = /obj/item/ammo_magazine/m762
	allowed_magazines = list(/obj/item/ammo_magazine/m762, /obj/item/ammo_magazine/m762/ext)
	projectile_type = /obj/item/projectile/bullet/rifle/a762
	fire_sound = "sound/weapons/ballistics/a762.ogg"

	one_handed_penalty = 45

	firemodes = list(
		list(mode_name="semiauto",       burst=1, fire_delay=0.1,    move_delay=null, burst_accuracy=null, dispersion=null),
		list(mode_name="2-round bursts", burst=2, fire_delay=null, move_delay=6,    burst_accuracy=list(0,-15), dispersion=list(0.0, 0.6))
		)

/obj/item/gun/projectile/automatic/bullpup/update_icon(ignore_inhands)
	..()
	if(istype(ammo_magazine,/obj/item/ammo_magazine/m762))
		icon_state = "bullpup-small"
	else if(istype(ammo_magazine,/obj/item/ammo_magazine/m762/ext))
		icon_state = "bullpup"
	else
		item_state = "bullpup-empty"
	if(!ignore_inhands)
		update_held_icon()

/*
 * Combat SMG (PP3 Ten)
 */
/obj/item/gun/projectile/automatic/combatsmg
	name = "\improper PP3 Ten"
	desc = "The Bishamonten PP3 Ten personal defense weapon is a rare design much sought after - though more for its looks than its functionality. Uses 9mm rounds."
	description_fluff = "The Bishamonten Company operated from roughly 2150-2280 - the height of the first extrasolar colonisation boom - before filing for bankruptcy and selling off its assets to various companies that would go on to become today’s TSCs. \
	Focused on sleek ‘futurist’ designs which have largely fallen out of fashion but remain popular with collectors and people hoping to make some quick thalers from replica weapons. \
	Bishamonten weapons tended to be form over function - despite their flashy looks, most were completely unremarkable one way or another as weapons and used very standard firing mechanisms."
	icon_state = "combatsmg"
	w_class = ITEMSIZE_NORMAL
	load_method = MAGAZINE
	caliber = "9mm"
	magazine_type = /obj/item/ammo_magazine/m9mmt
	allowed_magazines = list(/obj/item/ammo_magazine/m9mmt)
	fire_sound = "sound/weapons/gunshot1.ogg"

	firemodes = list(
		list(mode_name="semiauto", burst=1, fire_delay=0.1),
		list(mode_name="3-round bursts", burst=3, burst_delay=1, fire_delay=4, move_delay=4, burst_accuracy=list(0,-15,-30), dispersion=list(0.0, 0.6, 0.6))
		)

/obj/item/gun/projectile/automatic/combatsmg/update_icon()
	..()
	if(ammo_magazine)
		icon_state = "combatsmg"
	else
		icon_state = "combatsmg-empty"


// === merged from automatic_ch.dm during hard-fork de-suffix (verified no override-order change) ===
//
///
/// This is where reworked automatic weapons will be moved to. The P90 is an example of how these weapons should be laid out for readability (without all the comments).
/// Please make sure to categorize the weapons properly!
///
//

/*
 * SUBMACHINE GUNS
*/

// P90K

/obj/item/gun/projectile/automatic/p90
	name = "\improper P90K PDW"
	desc = "The P90K Personal Defense Weapon is a MarsTech-assembled modernized variation of the ancient FN P90, a compact, high-capacity submachine gun of human origin. Its fierce reputation owes to its minimal recoil and ergonomic design. Chambered in 9mm rounds."
	description_fluff = "The leading civilian-sector high-quality small arms subsidiary of Hephaestus Industries, MarsTech has been the provider of choice for law enforcement and security forces for over 300 years."

	item_icons = list(
		slot_l_hand_str = 'icons/mob/items/lefthand_guns_ch.dmi',
		slot_r_hand_str = 'icons/mob/items/righthand_guns_ch.dmi',
		)
	icon_state = "p90smgnew" // Defines the name for the icon (inventory) state.
	item_state = "p90new" // Defines the name for the item (visibly held) state.
	wielded_item_state = "p90new-wielded" // Defines the name for the wielded (two-handed) state.
	slot_flags = SLOT_BELT|SLOT_BACK // The inventory slots this weapon can occupy. Most weapons can go on the suit slot by default, so long as you're wearing a vest.

	w_class = ITEMSIZE_LARGE // Takes up more space in inventories than a pistol.

	recoil = 0 // No screenshake on firing.
	one_handed_penalty = 15 // Slight accuracy penalty when firing one-handed.
	auto_eject = 1 // Auto-ejects magazine when it's empty.
	auto_eject_sound = 'sound/weapons/smg_empty_alarm.ogg'

	caliber = "9mm" // The type of caliber the gun accepts. Will not accept magazines loaded with the wrong caliber, even if they're listed in allowed_magazines.
	ammo_type = /obj/item/ammo_casing/a9mm // Should always be an ammo casing that uses the same caliber as the gun's listed for.
	load_method = MAGAZINE
	magazine_type = /obj/item/ammo_magazine/m9mmp90 // The magazine type it spawns with.
	allowed_magazines = list(/obj/item/ammo_magazine/m9mmp90, /obj/item/ammo_magazine/m9mmt) // What kind of magazine(s) it can load.
	fire_sound = "sound/weapons/gunshot1.ogg"

	firemodes = list(
		list(mode_name="semi-automatic", burst=1, fire_delay=0, move_delay=0),
		list(mode_name="three-round burst", burst=3, fire_delay=null, burst_delay=1, move_delay=0, burst_accuracy=list(0,-15,-20), dispersion=list(0.0, 1.0, 1.5))
		)

/obj/item/gun/projectile/automatic/p90/update_icon() // Code for visually updating the item depending on current magazine capacity.
	icon_state = "p90smgnew-[ammo_magazine ? round(ammo_magazine.stored_ammo.len, 6) : "empty"]"

// C-20R

/obj/item/gun/projectile/automatic/c20r
	name = "\improper C-20R"
	desc = "The C-20R is a lightweight, heavy-hitting submachine gun with an infamous reputation for being the weapon of choice among mercenary outfits and insurgent cabals. It has 'Scarborough Arms - Per Falcis, Per Pravitas' inscribed on the stock. Chambered in 10mm caseless rounds."
	description_fluff = "The C-20R is produced by Scarborough Arms, a specialist high-end weapons manufacturer based out of Titan, Sol. Scarborough has resisted numerous efforts by Trans-Stellars to acquire the brand since its founding in 2511, and has gained a dedicated following among a certain flavor of private operative."

	icon = 'icons/obj/64x32guns_ch.dmi'
	icon_expected_width = 64
	item_icons = list(
		slot_l_hand_str = 'icons/mob/items/lefthand_guns_ch.dmi',
		slot_r_hand_str = 'icons/mob/items/righthand_guns_ch.dmi',
		)
	icon_state = "c20r"
	item_state = "c20rnew"
	wielded_item_state = "c20rnew-wielded"
	slot_flags = SLOT_BELT|SLOT_BACK

	w_class = ITEMSIZE_LARGE

	recoil = 0
	one_handed_penalty = 30
	auto_eject = 1
	auto_eject_sound = 'sound/weapons/smg_empty_alarm.ogg'

	caliber = "10mm"
	ammo_type = /obj/item/ammo_casing/a10mm
	load_method = MAGAZINE
	magazine_type = /obj/item/ammo_magazine/m10mm
	allowed_magazines = list(/obj/item/ammo_magazine/m10mm)
	fire_sound = "sound/weapons/gunshot1.ogg"

	firemodes = list(
		list(mode_name="semi-automatic", burst=1, fire_delay=0, move_delay=0),
		list(mode_name="two-shot rapidfire", burst=2, fire_delay=null, burst_delay=1, move_delay=0, burst_accuracy=list(-5,-10), dispersion=list(0.5, 1.0)),
		)

/obj/item/gun/projectile/automatic/c20r/update_icon()
	icon_state = "c20r-[ammo_magazine ? round(ammo_magazine.stored_ammo.len,4) : "empty"]"

/obj/item/gun/projectile/automatic/c20r/rubber
	magazine_type = /obj/item/ammo_magazine/m10mm/rubber

/obj/item/gun/projectile/automatic/c20r/empty
	magazine_type = null

/*
 * RIFLES
*/

/obj/item/gun/projectile/automatic/fal
	name = "FN-FAL"
	desc = "A 20th century Assault Rifle originally designed by Fabrique National. Famous for its use by mercs in grinding proxy wars in backwater nations. This reproduction was probably made for similar purposes."
	icon_state = "fal"
	item_state = "fal"
	w_class = ITEMSIZE_LARGE
	force = 10
	caliber = "7.62mm"
	slot_flags = SLOT_BACK
	load_method = MAGAZINE
	magazine_type = /obj/item/ammo_magazine/m762/ext
	allowed_magazines = list(/obj/item/ammo_magazine/m762, /obj/item/ammo_magazine/m762/ext)
	projectile_type = /obj/item/projectile/bullet/rifle/a762
	fire_sound = "sound/weapons/ballistics/a762.ogg"

	firemodes = list(
		list(mode_name="semiauto",       burst=1, fire_delay=0,    move_delay=null, burst_accuracy=null, dispersion=null),
		list(mode_name="2-round bursts", burst=2, fire_delay=null, move_delay=6,    burst_accuracy=list(60,35), dispersion=list(0.0, 0.6))
		)

/obj/item/gun/projectile/automatic/fal/update_icon(ignore_inhands)
	..()
	if(ammo_magazine)
		icon_state = initial(icon_state)
	else
		icon_state = "[initial(icon_state)]-empty"


// === merged from automatic_vr.dm during hard-fork de-suffix (verified no override-order change) ===
/obj/item/gun/projectile/automatic/wt550/lethal
	magazine_type = /obj/item/ammo_magazine/m9mmt

////////////////////////////////////////////////////////////
//////////////////// Projectile Weapons ////////////////////
////////////////////////////////////////////////////////////
// For general use
/obj/item/gun/projectile/automatic/battlerifle
	name = "\improper USDF service rifle"
	desc = "You had your chance to be afraid before you joined my beloved Corps! But, to guide you back to the true path, I have brought this motivational device! Uses 9.5x40mm rounds."
	icon_state = "battlerifle"
	icon_override = 'icons/obj/gun.dmi'
	item_state = "battlerifle_i"
	item_icons = null
	w_class = ITEMSIZE_HUGE //.
	recoil = 2 // The battlerifle was known for its nasty recoil.
	max_shells = 36
	caliber = "9.5x40mm"
	magazine_type = /obj/item/ammo_magazine/m95
	allowed_magazines = list(/obj/item/ammo_magazine/m95)
	fire_sound = 'sound/weapons/battlerifle.ogg'
	load_method = MAGAZINE
	slot_flags = SLOT_BACK
	one_handed_penalty = 60 // The weapon itself is heavy

// For general use
/obj/item/gun/projectile/automatic/stg
	name = "\improper Sturmgewehr"
	desc = "An STG-560 built by RauMauser. Experience the terror of the Siegfried line, redone for the 26th century! The Kaiser would be proud. Uses unique 7.92x33mm Kurz rounds." // 24th->26th
	icon_state = "stg60"
	item_state = "arifle"
	w_class = ITEMSIZE_LARGE
	max_shells = 30
	caliber = "7.92x33mm"
	magazine_type = /obj/item/ammo_magazine/mtg
	allowed_magazines = list(/obj/item/ammo_magazine/mtg)
	load_method = MAGAZINE

/obj/item/gun/projectile/automatic/stg/update_icon(ignore_inhands)
	..()
	icon_state = (ammo_magazine)? "stg60" : "stg60-empty"
	item_state = (ammo_magazine)? "arifle" : "arifle-empty"
	if(!ignore_inhands) update_held_icon()

//////////////////// Eris Ported Guns ////////////////////
// No idea what this is for.
/obj/item/gun/projectile/automatic/sol
	name = "\improper \"Sol\" SMG"
	desc = "The FS 9x19mm \"Sol\" is a compact and reliable submachine gun. Uses 9mm rounds."
	icon_state = "SMG-IS"
	item_state = "wt550"
	w_class = ITEMSIZE_LARGE
	slot_flags = SLOT_BELT
	caliber = "9mm"
	magazine_type = /obj/item/ammo_magazine/m9mm
	allowed_magazines = list(/obj/item/ammo_magazine/m9mm)
	load_method = MAGAZINE
	multi_aim = 1
	burst_delay = 2
	firemodes = list(
		list(mode_name="semiauto",       burst=1, fire_delay=0.1,    move_delay=null, burst_accuracy=null, dispersion=null),
		list(mode_name="3-round bursts", burst=3, fire_delay=null, move_delay=4,    burst_accuracy=list(0,-15,-15),       dispersion=list(0.0, 0.6, 1.0)),
		)

/obj/item/gun/projectile/automatic/sol/proc/update_charge()
	if(!ammo_magazine)
		return
	var/ratio = ammo_magazine.stored_ammo.len / ammo_magazine.max_ammo
	if(ratio < 0.25 && ratio != 0)
		ratio = 0.25
	ratio = round(ratio, 0.25) * 100
	add_overlay("smg_[ratio]")

/obj/item/gun/projectile/automatic/sol/update_icon()
	icon_state = (ammo_magazine)? "SMG-IS" : "SMG-IS-empty"
	cut_overlays()
	update_charge()

//--------------- StG-60 ----------------
/obj/item/ammo_magazine/m792
	name = "box mag (7.92x33mm Kurz)"
	icon = 'icons/obj/ammo_vr.dmi'
	icon_state = "stg_30rnd"
	caliber = "7.92x33mm"
	ammo_type = /obj/item/ammo_casing/a792
	max_ammo = 30
	mag_type = MAGAZINE

/obj/item/ammo_casing/a792
	desc = "A 7.92x33mm Kurz casing."
	icon_state = "rifle-casing"
	caliber = "7.92x33mm"
	projectile_type = /obj/item/projectile/bullet/rifle/a762

/obj/item/ammo_magazine/mtg/empty
	initial_ammo = 0

//------------- Battlerifle -------------
/obj/item/ammo_magazine/m95
	name = "box mag (9.5x40mm)"
	icon = 'icons/obj/ammo_vr.dmi'
	icon_state = "battlerifle"
	caliber = "9.5x40mm"
	ammo_type = /obj/item/ammo_casing/a95
	max_ammo = 36
	mag_type = MAGAZINE
	multiple_sprites = 1

/obj/item/ammo_casing/a95
	desc = "A 9.5x40mm bullet casing."
	icon_state = "rifle-casing"
	caliber = "9.5x40mm"
	projectile_type = /obj/item/projectile/bullet/rifle/a95

/obj/item/projectile/bullet/rifle/a95
	damage = 40

/obj/item/ammo_magazine/m95/empty
	initial_ammo = 0

//---------------- PDW ------------------
/obj/item/ammo_magazine/m9mml
	name = "\improper SMG magazine (9mm)"
	icon = 'icons/obj/ammo_vr.dmi'
	icon_state = "smg"
	mag_type = MAGAZINE
	matter = list(MAT_STEEL = 1800)
	caliber = "9mm"
	ammo_type = /obj/item/ammo_casing/a9mm
	max_ammo = 30
	multiple_sprites = 1

/obj/item/ammo_magazine/m9mml/empty
	initial_ammo = 0

/obj/item/ammo_magazine/m9mml/ap
	name = "\improper SMG magazine (9mm armor-piercing)"
	ammo_type = /obj/item/ammo_casing/a9mm/ap
