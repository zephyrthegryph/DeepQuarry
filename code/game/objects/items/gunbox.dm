/*
 * Sidearm Lethal
 */
/obj/item/gunbox
	name = "sidearm box"
	desc = "A secure box containing a lethal sidearm."
	icon = 'icons/obj/storage.dmi'
	icon_state = "gunbox"
	w_class = ITEMSIZE_HUGE
	///If the gunbox has custom attack_self code
	var/variant_gunbox = FALSE
DECLARE_INTERACTIONS(/obj/item/gunbox, INTERACT_USE("Open", PROC_REF(interaction_self)))

/// Old attack_self.
/obj/item/gunbox/proc/interaction_self(mob/user, obj/item/held, datum/interaction/interaction)
	if(variant_gunbox)
		return
	var/list/options = list()
	options["M1911 (.45)"] = list(/obj/item/gun/projectile/colt/detective, /obj/item/ammo_magazine/m45/rubber, /obj/item/ammo_magazine/m45/rubber)
	options["MT Mk58 (.45)"] = list(/obj/item/gun/projectile/sec, /obj/item/ammo_magazine/m45/rubber, /obj/item/ammo_magazine/m45/rubber)
	options["MarsTech R1 (.45)"] = list(/obj/item/gun/projectile/revolver/detective45, /obj/item/ammo_magazine/s45/rubber, /obj/item/ammo_magazine/s45/rubber)
	options["MarsTech P92X (9mm)"] = list(/obj/item/gun/projectile/p92x/rubber, /obj/item/ammo_magazine/m9mm/rubber, /obj/item/ammo_magazine/m9mm/rubber)
	offer_guns(user, "Would you prefer a pistol or a revolver?", "Gun!", options)

/// Asks which kit to unpack; `options` maps a name to the types it spawns (the gun first).
/obj/item/gunbox/proc/offer_guns(mob/user, message, title, list/options, greeting = "Say hello to your new friend.")
	om_ask(user, /datum/om/prompt/choice/gunbox, PROC_REF(gun_chosen), title = title, message = message, choices = options, greeting = greeting)

/// Picking a kit out of a gun box. Re-checked on the answer: the box is still carried.
/datum/om/prompt/choice/gunbox
	ask_flags = ASK_CARRIED | ASK_CAPABLE
	var/greeting

/obj/item/gunbox/proc/gun_chosen(datum/om/prompt/choice/gunbox/ask)
	var/mob/user = ask.answerer
	var/list/things_to_spawn = ask.choices[ask.choice]
	for(var/new_type in things_to_spawn) // Spawn all the things, the gun and the ammo.
		var/atom/movable/AM = new new_type(get_turf(src))
		if(istype(AM, /obj/item/gun))
			to_chat(user, "You have chosen \the [AM]. [ask.greeting]")
	consume(src, user)

/*
 * Sidearm Stun
 */
/obj/item/gunbox/stun
	name = "non-lethal sidearm box"
	desc = "A secure box containing a non-lethal sidearm."
	variant_gunbox = TRUE
DECLARE_INTERACTIONS(/obj/item/gunbox/stun, INTERACT_USE("Open", PROC_REF(stun_interaction_self)))

/// Old attack_self.
/obj/item/gunbox/stun/proc/stun_interaction_self(mob/user, obj/item/held, datum/interaction/interaction)
	var/list/options = list()
	options["Stun Revolver"] = list(/obj/item/gun/energy/stunrevolver/detective, /obj/item/cell/device/weapon, /obj/item/cell/device/weapon)
	options["Taser"] = list(/obj/item/gun/energy/taser, /obj/item/cell/device/weapon, /obj/item/cell/device/weapon)
	offer_guns(user, "Please, select an option.", "Stun Gun!", options)

/*
 * CentCom Pistol
 */
/obj/item/gunbox/centcom
	name = "centcom sidearm box"
	desc = "A secure box containing a lethal sidearm used by Central Command."
	w_class = ITEMSIZE_HUGE
	variant_gunbox = TRUE
DECLARE_INTERACTIONS(/obj/item/gunbox/centcom, INTERACT_USE("Open", PROC_REF(centcom_interaction_self)))

/// Old attack_self.
/obj/item/gunbox/centcom/proc/centcom_interaction_self(mob/user, obj/item/held, datum/interaction/interaction)
	var/list/options = list()
	options["Écureuil (10mm)"] = list(/obj/item/gun/projectile/ecureuil, /obj/item/ammo_magazine/m10mm/pistol, /obj/item/ammo_magazine/m10mm/pistol)
	options["Écureuil Olive (10mm)"] = list(/obj/item/gun/projectile/ecureuil/tac, /obj/item/ammo_magazine/m10mm/pistol, /obj/item/ammo_magazine/m10mm/pistol)
	options["Écureuil Tan (10mm)"] = list(/obj/item/gun/projectile/ecureuil/tac2, /obj/item/ammo_magazine/m10mm/pistol, /obj/item/ammo_magazine/m10mm/pistol)
	offer_guns(user, "Please, select an option.", "Gun!", options)


/*
 * Shotgun Box
 */
/obj/item/gunbox/warden
	name = "warden's shotgun case"
	desc = "A secure guncase containing the warden's beloved shotgun."
	icon = 'icons/obj/storage_vr.dmi'
	icon_state = "gunboxw"
	variant_gunbox = TRUE

DECLARE_INTERACTIONS(/obj/item/gunbox/warden, INTERACT_USE("Open", PROC_REF(warden_interaction_self)))

/// Old attack_self.
/obj/item/gunbox/warden/proc/warden_interaction_self(mob/user, obj/item/held, datum/interaction/interaction)
	var/list/options = list()
	options["Warden's combat shotgun"] = list(/obj/item/gun/projectile/shotgun/pump/combat/warden, /obj/item/ammo_magazine/ammo_box/b12g/beanbag)
	options["Warden's compact shotgun"] = list(/obj/item/gun/projectile/shotgun/compact/warden, /obj/item/ammo_magazine/ammo_box/b12g/beanbag)
	offer_guns(user, "Choose your boomstick!", "Shotgun!", options, "Say hello to your new best friend.")

/*
 * Site Manager's Box
 */
/obj/item/gunbox/captain
	name = "Captain's sidearm box"
	desc = "A secure box containing a sidearm befitting of the site manager. Includes both lethal and non-lethal munitions, beware what's loaded!"
	icon = 'icons/obj/storage.dmi'
	icon_state = "gunbox"
	variant_gunbox = TRUE
DECLARE_INTERACTIONS(/obj/item/gunbox/captain, INTERACT_USE("Open", PROC_REF(captain_interaction_self)))

/// Old attack_self.
/obj/item/gunbox/captain/proc/captain_interaction_self(mob/user, obj/item/held, datum/interaction/interaction)
	var/list/options = list()
	options["M1911 (.45)"] = list(/obj/item/gun/projectile/colt/detective, /obj/item/ammo_magazine/m45/rubber, /obj/item/ammo_magazine/m45)
	options["MT Mk58 (.45)"] = list(/obj/item/gun/projectile/sec, /obj/item/ammo_magazine/m45/rubber, /obj/item/ammo_magazine/m45)
	options["LAEP80 \"Thor\" (Stun/Laser)"] = list(/obj/item/gun/energy/gun, /obj/item/cell/device/weapon, /obj/item/cell/device/weapon)
	options["MarsTech P92X (9mm)"] = list(/obj/item/gun/projectile/p92x/rubber, /obj/item/ammo_magazine/m9mm/rubber, /obj/item/ammo_magazine/m9mm)
	offer_guns(user, "Would you prefer a ballistic pistol or an energy gun?", "Gun!", options)


/obj/item/gunbox/sec_officer
	name = "lethal armament box"
	desc = "A secure box containing a lethal sidearm."
	variant_gunbox = TRUE

DECLARE_INTERACTIONS(/obj/item/gunbox/sec_officer, INTERACT_USE("Open", PROC_REF(sec_officer_interaction_self)))

/// Old attack_self.
/obj/item/gunbox/sec_officer/proc/sec_officer_interaction_self(mob/user, obj/item/held, datum/interaction/interaction)
	var/list/options = list()
	options["Laser Pistol"] = list(/obj/item/gun/energy/gun, /obj/item/cell/device/weapon, /obj/item/cell/device/weapon)
	options["Normal Pistol"] = list(/obj/item/gun/projectile/pistol, /obj/item/ammo_magazine/m9mm/compact, /obj/item/ammo_magazine/m9mm/compact, /obj/item/ammo_magazine/m9mm/compact, /obj/item/ammo_magazine/m9mm/compact)
	offer_guns(user, "Please, select an option.", "Lethal Gun!", options)
