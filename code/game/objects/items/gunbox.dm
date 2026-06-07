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
/obj/item/gunbox/attack_self(mob/living/user)
	. = ..(user)
	if(.)
		return TRUE
	if(variant_gunbox)
		return
	var/list/options = list()
	options["M1911 (.45)"] = list(/obj/item/gun/projectile/colt/detective, /obj/item/ammo_magazine/m45/rubber, /obj/item/ammo_magazine/m45/rubber)
	options["MT Mk58 (.45)"] = list(/obj/item/gun/projectile/sec, /obj/item/ammo_magazine/m45/rubber, /obj/item/ammo_magazine/m45/rubber)
	options["MarsTech R1 (.45)"] = list(/obj/item/gun/projectile/revolver/detective45, /obj/item/ammo_magazine/s45/rubber, /obj/item/ammo_magazine/s45/rubber)
	options["MarsTech P92X (9mm)"] = list(/obj/item/gun/projectile/p92x/rubber, /obj/item/ammo_magazine/m9mm/rubber, /obj/item/ammo_magazine/m9mm/rubber)
	var/choice = tgui_input_list(user,"Would you prefer a pistol or a revolver?", "Gun!", options)
	if(!choice)
		return
	if(src && choice)
		var/list/things_to_spawn = options[choice]
		for(var/new_type in things_to_spawn) // Spawn all the things, the gun and the ammo.
			var/atom/movable/AM = new new_type(get_turf(src))
			if(istype(AM, /obj/item/gun))
				to_chat(user, "You have chosen \the [AM]. Say hello to your new friend.")
		qdel(src)

/*
 * Sidearm Stun
 */
/obj/item/gunbox/stun
	name = "non-lethal sidearm box"
	desc = "A secure box containing a non-lethal sidearm."
	variant_gunbox = TRUE
/obj/item/gunbox/stun/attack_self(mob/living/user)
	. = ..(user)
	if(.)
		return TRUE
	var/list/options = list()
	options["Stun Revolver"] = list(/obj/item/gun/energy/stunrevolver/detective, /obj/item/cell/device/weapon, /obj/item/cell/device/weapon)
	options["Taser"] = list(/obj/item/gun/energy/taser, /obj/item/cell/device/weapon, /obj/item/cell/device/weapon)
	var/choice = tgui_input_list(user,"Please, select an option.", "Stun Gun!", options)
	if(!choice)
		return
	if(src && choice)
		var/list/things_to_spawn = options[choice]
		for(var/new_type in things_to_spawn) // Spawn all the things, the gun and the ammo.
			var/atom/movable/AM = new new_type(get_turf(src))
			if(istype(AM, /obj/item/gun))
				to_chat(user, "You have chosen \the [AM]. Say hello to your new friend.")
		qdel(src)

/*
 * CentCom Pistol
 */
/obj/item/gunbox/centcom
	name = "centcom sidearm box"
	desc = "A secure box containing a lethal sidearm used by Central Command."
	w_class = ITEMSIZE_HUGE
	variant_gunbox = TRUE
/obj/item/gunbox/centcom/attack_self(mob/living/user)
	. = ..(user)
	if(.)
		return TRUE
	var/list/options = list()
	options["Écureuil (10mm)"] = list(/obj/item/gun/projectile/ecureuil, /obj/item/ammo_magazine/m10mm/pistol, /obj/item/ammo_magazine/m10mm/pistol)
	options["Écureuil Olive (10mm)"] = list(/obj/item/gun/projectile/ecureuil/tac, /obj/item/ammo_magazine/m10mm/pistol, /obj/item/ammo_magazine/m10mm/pistol)
	options["Écureuil Tan (10mm)"] = list(/obj/item/gun/projectile/ecureuil/tac2, /obj/item/ammo_magazine/m10mm/pistol, /obj/item/ammo_magazine/m10mm/pistol)
	var/choice = tgui_input_list(user,"Please, select an option.", "Gun!", options)
	if(!choice)
		return
	if(src && choice)
		var/list/things_to_spawn = options[choice]
		for(var/new_type in things_to_spawn) // Spawn all the things, the gun and the ammo.
			var/atom/movable/AM = new new_type(get_turf(src))
			if(istype(AM, /obj/item/gun))
				to_chat(user, "You have chosen \the [AM]. Say hello to your new friend.")
		qdel(src)


// === merged from gunbox_vr.dm during hard-fork de-suffix (verified no override-order change) ===
/*
 * Shotgun Box
 */
/obj/item/gunbox/warden
	name = "warden's shotgun case"
	desc = "A secure guncase containing the warden's beloved shotgun."
	icon = 'icons/obj/storage_vr.dmi'
	icon_state = "gunboxw"
	variant_gunbox = TRUE

/obj/item/gunbox/warden/attack_self(mob/living/user)
	. = ..(user)
	if(.)
		return TRUE
	var/list/options = list()
	options["Warden's combat shotgun"] = list(/obj/item/gun/projectile/shotgun/pump/combat/warden, /obj/item/ammo_magazine/ammo_box/b12g/beanbag)
	options["Warden's compact shotgun"] = list(/obj/item/gun/projectile/shotgun/compact/warden, /obj/item/ammo_magazine/ammo_box/b12g/beanbag)
	var/choice = tgui_input_list(user,"Choose your boomstick!", "Shotgun!", options)
	if(!choice)
		return
	if(src && choice)
		var/list/things_to_spawn = options[choice]
		for(var/new_type in things_to_spawn) // Spawn all the things, the gun and the ammo.
			var/atom/movable/AM = new new_type(get_turf(src))
			if(istype(AM, /obj/item/gun))
				to_chat(user, "You have chosen \the [AM]. Say hello to your new best friend.")
		qdel(src)

/*
 * Site Manager's Box
 */
/obj/item/gunbox/captain
	name = "Captain's sidearm box"
	desc = "A secure box containing a sidearm befitting of the site manager. Includes both lethal and non-lethal munitions, beware what's loaded!"
	icon = 'icons/obj/storage.dmi'
	icon_state = "gunbox"
	variant_gunbox = TRUE
/obj/item/gunbox/captain/attack_self(mob/living/user)
	. = ..(user)
	if(.)
		return TRUE
	var/list/options = list()
	options["M1911 (.45)"] = list(/obj/item/gun/projectile/colt/detective, /obj/item/ammo_magazine/m45/rubber, /obj/item/ammo_magazine/m45)
	options["MT Mk58 (.45)"] = list(/obj/item/gun/projectile/sec, /obj/item/ammo_magazine/m45/rubber, /obj/item/ammo_magazine/m45)
	options["LAEP80 \"Thor\" (Stun/Laser)"] = list(/obj/item/gun/energy/gun, /obj/item/cell/device/weapon, /obj/item/cell/device/weapon)
	options["MarsTech P92X (9mm)"] = list(/obj/item/gun/projectile/p92x/rubber, /obj/item/ammo_magazine/m9mm/rubber, /obj/item/ammo_magazine/m9mm)
	var/choice = tgui_input_list(user,"Would you prefer a ballistic pistol or an energy gun?", "Gun!", options)
	if(!choice)
		return
	if(src && choice)
		var/list/things_to_spawn = options[choice]
		for(var/new_type in things_to_spawn) // Spawn all the things, the gun and the ammo.
			var/atom/movable/AM = new new_type(get_turf(src))
			if(istype(AM, /obj/item/gun))
				to_chat(user, "You have chosen \the [AM]. Say hello to your new friend.")
		qdel(src)


// === merged from gunbox_chomp.dm during hard-fork de-suffix (verified no override-order change) ===
/obj/item/gunbox/sec_officer
	name = "lethal armament box"
	desc = "A secure box containing a lethal sidearm."
	variant_gunbox = TRUE

/obj/item/gunbox/sec_officer/attack_self(mob/living/user)
	. = ..(user)
	if(.)
		return TRUE
	var/list/options = list()
	options["Laser Pistol"] = list(/obj/item/gun/energy/gun, /obj/item/cell/device/weapon, /obj/item/cell/device/weapon)
	options["Normal Pistol"] = list(/obj/item/gun/projectile/pistol, /obj/item/ammo_magazine/m9mm/compact, /obj/item/ammo_magazine/m9mm/compact, /obj/item/ammo_magazine/m9mm/compact, /obj/item/ammo_magazine/m9mm/compact)
	var/choice = tgui_input_list(user,"Please, select an option.", "Lethal Gun!", options)
	if(!choice)
		return
	if(src && choice)
		var/list/things_to_spawn = options[choice]
		for(var/new_type in things_to_spawn) // Spawn all the things, the gun and the ammo.
			var/atom/movable/AM = new new_type(get_turf(src))
			if(istype(AM, /obj/item/gun))
				to_chat(user, "You have chosen \the [AM]. Say hello to your new friend.")
		qdel(src)
