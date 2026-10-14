/*
 * Sidearm Lethal
 */
/obj/item/gunbox
	name = "sidearm box"
	desc = "A secure box containing a lethal sidearm."
	icon = 'icons/obj/storage.dmi'
	icon_state = "gunbox"
	w_class = ITEMSIZE_HUGE

CAPABILITIES(/obj/item/gunbox)
	op("open", in_hand(), label("Open"), wait(0),
		asks(/datum/prompt/choice, fields = list("question" = computed(PROC_REF(kit_question)), "title" = computed(PROC_REF(kit_title)), "choices" = computed(PROC_REF(kit_names)))),
		then(PROC_REF(kit_chosen)))

/// The kits the box offers: a name mapped to the types it spawns (the gun first).
/obj/item/gunbox/proc/kit_options()
	var/list/options = list()
	options["M1911 (.45)"] = list(/obj/item/gun/projectile/colt/detective, /obj/item/ammo_magazine/m45/rubber, /obj/item/ammo_magazine/m45/rubber)
	options["MT Mk58 (.45)"] = list(/obj/item/gun/projectile/sec, /obj/item/ammo_magazine/m45/rubber, /obj/item/ammo_magazine/m45/rubber)
	options["MarsTech R1 (.45)"] = list(/obj/item/gun/projectile/revolver/detective45, /obj/item/ammo_magazine/s45/rubber, /obj/item/ammo_magazine/s45/rubber)
	options["MarsTech P92X (9mm)"] = list(/obj/item/gun/projectile/p92x/rubber, /obj/item/ammo_magazine/m9mm/rubber, /obj/item/ammo_magazine/m9mm/rubber)
	return options

/// The question the window asks.
/obj/item/gunbox/proc/kit_question(datum/act/A)
	return "Would you prefer a pistol or a revolver?"

/// The title of the window.
/obj/item/gunbox/proc/kit_title(datum/act/A)
	return "Gun!"

/// What the box says when the gun is unpacked.
/obj/item/gunbox/proc/kit_greeting()
	return "Say hello to your new friend."

/// The names the window lists.
/obj/item/gunbox/proc/kit_names(datum/act/A)
	var/list/names = list()
	for(var/kit in kit_options())
		names += kit
	return names

/// A kit was picked: the box is used up and its things land where it was.
/obj/item/gunbox/proc/kit_chosen(datum/act/op/A)
	var/mob/user = A.actor
	var/datum/prompt/R = A.answer
	var/list/things_to_spawn = kit_options()[R?.value]
	if(!things_to_spawn)
		return OP_REFUSED
	var/turf/delivery_turf = get_turf(src)
	if(!consume(src, user))
		return OP_REFUSED
	for(var/new_type in things_to_spawn) // Spawn all the things, the gun and the ammo.
		var/atom/movable/AM = new new_type(delivery_turf)
		if(istype(AM, /obj/item/gun))
			to_chat(user, "You have chosen \the [AM]. [kit_greeting()]")
	return OP_OK

/*
 * Sidearm Stun
 */
/obj/item/gunbox/stun
	name = "non-lethal sidearm box"
	desc = "A secure box containing a non-lethal sidearm."

/// The kits of this box.
/obj/item/gunbox/stun/kit_options()
	var/list/options = list()
	options["Stun Revolver"] = list(/obj/item/gun/energy/stunrevolver/detective, /obj/item/cell/device/weapon, /obj/item/cell/device/weapon)
	options["Taser"] = list(/obj/item/gun/energy/taser, /obj/item/cell/device/weapon, /obj/item/cell/device/weapon)
	return options

/obj/item/gunbox/stun/kit_question(datum/act/A)
	return "Please, select an option."

/obj/item/gunbox/stun/kit_title(datum/act/A)
	return "Stun Gun!"

/*
 * CentCom Pistol
 */
/obj/item/gunbox/centcom
	name = "centcom sidearm box"
	desc = "A secure box containing a lethal sidearm used by Central Command."
	w_class = ITEMSIZE_HUGE

/// The kits of this box.
/obj/item/gunbox/centcom/kit_options()
	var/list/options = list()
	options["Écureuil (10mm)"] = list(/obj/item/gun/projectile/ecureuil, /obj/item/ammo_magazine/m10mm/pistol, /obj/item/ammo_magazine/m10mm/pistol)
	options["Écureuil Olive (10mm)"] = list(/obj/item/gun/projectile/ecureuil/tac, /obj/item/ammo_magazine/m10mm/pistol, /obj/item/ammo_magazine/m10mm/pistol)
	options["Écureuil Tan (10mm)"] = list(/obj/item/gun/projectile/ecureuil/tac2, /obj/item/ammo_magazine/m10mm/pistol, /obj/item/ammo_magazine/m10mm/pistol)
	return options

/obj/item/gunbox/centcom/kit_question(datum/act/A)
	return "Please, select an option."

/obj/item/gunbox/centcom/kit_title(datum/act/A)
	return "Gun!"


/*
 * Shotgun Box
 */
/obj/item/gunbox/warden
	name = "warden's shotgun case"
	desc = "A secure guncase containing the warden's beloved shotgun."
	icon = 'icons/obj/storage_vr.dmi'
	icon_state = "gunboxw"


/// The kits of this box.
/obj/item/gunbox/warden/kit_options()
	var/list/options = list()
	options["Warden's combat shotgun"] = list(/obj/item/gun/projectile/shotgun/pump/combat/warden, /obj/item/ammo_magazine/ammo_box/b12g/beanbag)
	options["Warden's compact shotgun"] = list(/obj/item/gun/projectile/shotgun/compact/warden, /obj/item/ammo_magazine/ammo_box/b12g/beanbag)
	return options

/obj/item/gunbox/warden/kit_question(datum/act/A)
	return "Choose your boomstick!"

/obj/item/gunbox/warden/kit_title(datum/act/A)
	return "Shotgun!"

/obj/item/gunbox/warden/kit_greeting()
	return "Say hello to your new best friend."

/*
 * Site Manager's Box
 */
/obj/item/gunbox/captain
	name = "Captain's sidearm box"
	desc = "A secure box containing a sidearm befitting of the site manager. Includes both lethal and non-lethal munitions, beware what's loaded!"
	icon = 'icons/obj/storage.dmi'
	icon_state = "gunbox"

/// The kits of this box.
/obj/item/gunbox/captain/kit_options()
	var/list/options = list()
	options["M1911 (.45)"] = list(/obj/item/gun/projectile/colt/detective, /obj/item/ammo_magazine/m45/rubber, /obj/item/ammo_magazine/m45)
	options["MT Mk58 (.45)"] = list(/obj/item/gun/projectile/sec, /obj/item/ammo_magazine/m45/rubber, /obj/item/ammo_magazine/m45)
	options["LAEP80 \"Thor\" (Stun/Laser)"] = list(/obj/item/gun/energy/gun, /obj/item/cell/device/weapon, /obj/item/cell/device/weapon)
	options["MarsTech P92X (9mm)"] = list(/obj/item/gun/projectile/p92x/rubber, /obj/item/ammo_magazine/m9mm/rubber, /obj/item/ammo_magazine/m9mm)
	return options

/obj/item/gunbox/captain/kit_question(datum/act/A)
	return "Would you prefer a ballistic pistol or an energy gun?"

/obj/item/gunbox/captain/kit_title(datum/act/A)
	return "Gun!"


/obj/item/gunbox/sec_officer
	name = "lethal armament box"
	desc = "A secure box containing a lethal sidearm."


/// The kits of this box.
/obj/item/gunbox/sec_officer/kit_options()
	var/list/options = list()
	options["Laser Pistol"] = list(/obj/item/gun/energy/gun, /obj/item/cell/device/weapon, /obj/item/cell/device/weapon)
	options["Normal Pistol"] = list(/obj/item/gun/projectile/pistol, /obj/item/ammo_magazine/m9mm/compact, /obj/item/ammo_magazine/m9mm/compact, /obj/item/ammo_magazine/m9mm/compact, /obj/item/ammo_magazine/m9mm/compact)
	return options

/obj/item/gunbox/sec_officer/kit_question(datum/act/A)
	return "Please, select an option."

/obj/item/gunbox/sec_officer/kit_title(datum/act/A)
	return "Lethal Gun!"
