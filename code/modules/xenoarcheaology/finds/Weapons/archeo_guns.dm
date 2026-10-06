//snowflake guns for xenoarch because you can't override the update_icon() proc inside the giant mess that is find creation
/obj/item/gun/projectile/artifact
	name = "artifact gun"
	icon = 'icons/obj/xenoarchaeology.dmi'
	icon_state = "gun1"
	caliber = ".357"
	max_shells = 12
	ammo_type = /obj/item/ammo_casing/artifact
	load_method = SINGLE_CASING //One. At. A. Time.
	auto_eject = 0

/obj/item/gun/projectile/artifact/get_ammo_type() //Handles the HUD overlay.
	var/obj/item/projectile/P = src.projectile_type
	return list(initial(P.hud_state), initial(P.hud_state_empty))

/obj/item/gun/projectile/artifact/unload_ammo(mob/user, allow_dump=0) //No taking the bullets out!
	if(length(loaded))
		var/obj/item/ammo_casing/C = own_take_member(src, nameof(loaded), loaded[length(loaded)])
		act_message(user, src, MSG_SELF(span_notice("You remove \a casing from %T%, the casing fizzling in the air before evaporating into dust")), \
			MSG_OTHERS("%U% removes \a casing from %T%, the casing fizzling in the air before evaporating into dust."))
		C.moveToNullspace() //Into the void!
		consume(C) //And begone!
		play_sfx(src, SFX_WEAPONS_EMPTY)
		new /obj/effect/effect/sparks(src)
		user.hud_used.update_ammo_hud(user, src)
	else
		to_chat(user, span_warning("[src] is empty."))
	user.hud_used.update_ammo_hud(user, src)

/obj/item/ammo_casing/artifact
	name = "artifact bullet casing"
	desc = "A MYSTERIOUS bullet casing!!! (You should not see this. If you do, blame adminbus or contact your nearest coder.)"
	drop_sound = SFX_ITEMS_DROP_RING
	pickup_sound = SFX_ITEMS_PICKUP_RING
	projectile_type = /obj/item/projectile/bullet/cap //Just a placeholder. Doesn't actually matter what this is. All that matters is what the projecttile_type of our BB is.
	caseless = TRUE

/obj/item/ammo_casing/artifact/Initialize(mapload) //These should ONLY ever be in artifact weapons. If you spawn outside of artifact weapons, it'll have a riot foam dart inside of it as the bullet.
	. = ..()
	// The casing owns BB: replace the default bullet (rel_set deletes it).
	if(istype(loc, /obj/item/gun/projectile/artifact)) //If we are IN an artifact gun
		var/obj/item/gun/projectile/artifact/our_gun = loc
		if(ispath(our_gun.projectile_type))
			rel_set(src, nameof(BB), new our_gun.projectile_type(src)) //Then we create the bullet inside of us that is the projectile_type that the gun shoots!
		else
			rel_set(src, nameof(BB), new /obj/item/projectile/bullet/foam_dart_riot(src)) // ALLOW(decl): bullet type comes from the gun's projectile_type, which a declared child cannot name; should never happen
	else //The bullet was adminspawned in outside of an artifact gun.
		rel_set(src, nameof(BB), new /obj/item/projectile/bullet/foam_dart_riot(src)) // ALLOW(decl): adminspawned casing outside a gun has no projectile_type to declare from
	randpixel_xy()
