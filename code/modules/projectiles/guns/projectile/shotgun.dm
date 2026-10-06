/*
 * Shotgun
 */

/obj/item/gun/projectile/shotgun/pump
	name = "shotgun"
//	desc = "The mass-produced MarsTech Meteor 29 shotgun is a favourite of police and security forces on many worlds. Uses 12g rounds." //CHOMP Disable
	desc = "I used the shotgun. You know why? Cause the shotgun doesn't miss, and unlike the shitty hybrid taser it stops \
	a criminal in their tracks in two hits. Bang, bang, and they're fucking done. I use four shots just to make damn sure. \
	Because, once again, I'm not there to coddle a buncha criminal scum sucking losers, I'm there to 1) Survive the fucking round. \
	2) Guard the armory. So you can absolutely get fucked. If I get unbanned, which I won't, you can guarantee I will continue to use \
	the shotgun to apprehend criminals. Because it's quick, clean and effective as fuck. Why in the seven hells would I fuck around \
	with the disabler shots, which take half a clip just to bring someone down, or with the tazer bolts which are slow as balls, \
	impossible to aim and do about next to jack shit, fuck all. The shotgun is the superior law enforcement weapon. Because it stops crime. \
	And it stops crime by reducing the number of criminals roaming the fucking halls." //CHOMP Add
	description_fluff = "The leading civilian-sector high-quality small arms brand of Hephaestus Industries, \
	MarsTech has been the provider of choice for law enforcement and security forces for over 300 years."
	icon_state = "shotgun"
	item_state = "shotgun"
	max_shells = 4
	w_class = ITEMSIZE_HUGE //.
	force = 10
	slot_flags = SLOT_BACK
	caliber = "12g"
	load_method = SINGLE_CASING|SPEEDLOADER
	ammo_type = /obj/item/ammo_casing/a12g/beanbag
	projectile_type = /obj/item/projectile/bullet/shotgun
	handle_casings = HOLD_CASINGS
	COOLDOWN_DECLARE(pump_cooldown) 			//To prevent spammage
	var/action_sound = SFX_WEAPONS_SHOTGUNPUMP
	var/empty_sprite = 0 		//This is just a dirty var so it doesn't fudge up.
	var/pump_animation = "shotgun-pump"	//You put the reference to the animation in question here. Frees up namming. Ex: "shotgun_old_pump" or "sniper_cycle"

	special_weapon_handling = TRUE

/obj/item/gun/projectile/shotgun/pump/consume_next_projectile()
	if(chambered)
		return chambered.BB
	return null

/// Old attack_self (the gun self-use chain: /obj/item/gun/proc/gun_self()).
/obj/item/gun/projectile/shotgun/pump/gun_self(mob/user, obj/item/held, datum/interaction/interaction, callback)
	. = ..()
	if(.)
		return TRUE
	if(COOLDOWN_FINISHED(src, pump_cooldown))
		pump(user)
		COOLDOWN_START(src, pump_cooldown, 1 SECOND)

/obj/item/gun/projectile/shotgun/pump/proc/pump(mob/M as mob)
	playsound(src, action_sound, 60, 1)

	// We have a shell in the chamber
	if(chambered)
		if(chambered.caseless)
			spent(chambered, M) // Delete casing
		else
			chambered.forceMove(get_turf(src)) // Eject casing
		rel_clear(src, nameof(chambered))
		M.hud_used?.update_ammo_hud(M, src) // TGMC Ammo HUD Port

	// Load next shell
	if(length(loaded))
		var/obj/item/ammo_casing/AC = loaded[1] // Load next casing.
		own_take_member(src, nameof(loaded), AC) // Remove casing from loaded list.
		rel_set(src, nameof(chambered), AC)
		M.hud_used?.update_ammo_hud(M, src) // TGMC Ammo HUD Port

	if(pump_animation) // This affects all bolt action and shotguns.
		flick("[pump_animation]", src) // This plays any pumping


/obj/item/gun/projectile/shotgun/pump/draw(datum/look/look)
	..()
	var/drawn_state = look.state_so_far(src)
	if(!empty_sprite)//Just a dirty check
		return
	if((length(loaded)) || (chambered))
		drawn_state = look.state("[drawn_state]")
	else
		drawn_state = look.state("[drawn_state]-empty")

/obj/item/gun/projectile/shotgun/pump/empty
	ammo_type = null

/obj/item/gun/projectile/shotgun/pump/slug
	ammo_type = /obj/item/ammo_casing/a12g
	pump_animation = null

/*
 * Combat Shotgun
 */
/obj/item/gun/projectile/shotgun/pump/combat
	name = "combat shotgun"
	desc = "Built for close quarters combat, the Hephaestus Industries KS-40 is widely regarded as a weapon of choice for repelling boarders. Uses 12g rounds."
	description_fluff = "The leading arms producer in the SCG, Hephaestus typically only uses its 'top level' \
	branding for its military-grade equipment used by armed forces across human space."
	icon_state = "cshotgun"
	item_state = "cshotgun"
	max_shells = 7 //match the ammo box capacity, also it can hold a round in the chamber anyways, for a total of 8.
	ammo_type = /obj/item/ammo_casing/a12g
	load_method = SINGLE_CASING|SPEEDLOADER
	pump_animation = "cshotgun-pump"

/obj/item/gun/projectile/shotgun/pump/combat/empty
	ammo_type = null

/*
 * Double-Barreled Shotgun
 */
/obj/item/gun/projectile/shotgun/doublebarrel
	name = "double-barreled shotgun"
	desc = "A truely classic weapon. No need to change what works. Uses 12g rounds."
	icon_state = "dshotgun"
	item_state = "dshotgun"
	//SPEEDLOADER because rapid unloading.
	//In principle someone could make a speedloader for it, so it makes sense.
	load_method = SINGLE_CASING|SPEEDLOADER
	handle_casings = CYCLE_CASINGS
	max_shells = 2
	w_class = ITEMSIZE_LARGE
	force = 10
	slot_flags = SLOT_BACK
	caliber = "12g"
	ammo_type = /obj/item/ammo_casing/a12g/beanbag

	var/sawn_off = FALSE

	burst_delay = 0
	firemodes = list(
		list(mode_name="fire one barrel at a time", burst=1),
		list(mode_name="fire both barrels at once", burst=2),
		)

/obj/item/gun/projectile/shotgun/doublebarrel/pellet
	ammo_type = /obj/item/ammo_casing/a12g/pellet

/obj/item/gun/projectile/shotgun/doublebarrel/flare
	name = "signal shotgun"
	desc = "A double-barreled shotgun meant to fire signal flash shells. Uses 12g rounds."
	ammo_type = /obj/item/ammo_casing/a12g/flash

/obj/item/gun/projectile/shotgun/doublebarrel/unload_ammo(user, allow_dump)
	..(user, allow_dump=1)
//this is largely hacky and bad :(	-Pete //less hacky and bad now :) -Ghost
/// Old attackby.
/obj/item/gun/projectile/shotgun/doublebarrel/gun_item(mob/user, obj/item/A, datum/interaction/interaction)
	if(istype(A, /obj/item/surgical/circular_saw) || istype(A, /obj/item/melee/energy) || istype(A, /obj/item/pickaxe/plasmacutter))
		. = INTERACTION_HANDLED_PASS
		if(sawn_off)
			to_chat(user, span_warning("The [src] is already shortened!"))
			return
		to_chat(user, span_notice("You begin to shorten the barrel of \the [src]."))
		if(length(loaded))
			var/burstsetting = burst
			burst = 2
			act_message(user, null, MSG_SELF(span_danger("The shotgun goes off in your face!")), MSG_OTHERS(span_danger("The shotgun goes off!")))
			Fire_userless(user)
			user.hud_used?.update_ammo_hud(user, src) // TGMC Ammo HUD Port
			burst = burstsetting
			return
		om_task_timed(user, 3 SECONDS, src, src, PROC_REF(saw_off_done), list(user)) // SHIT IS STEALTHY EYYYYY
	else
		return ..()

/obj/item/gun/projectile/shotgun/doublebarrel/proc/saw_off_done(mob/user)
	if(sawn_off)
		return
	item_state = "sawnshotgun"
	w_class = ITEMSIZE_NORMAL
	force = 5
	slot_flags &= ~SLOT_BACK // you can't sling it on your back
	slot_flags |= (SLOT_BELT|SLOT_HOLSTER) // but you can wear it on your belt (poorly concealed under a trenchcoat, ideally) - or in a holster, why not.
	name = "sawn-off shotgun"
	desc = "Omar's coming!"
	to_chat(user, span_warning("You shorten the barrel of \the [src]!"))
	sawn_off = TRUE

/*
 * Sawn-Off Shotgun
 */
/obj/item/gun/projectile/shotgun/doublebarrel/sawn
	name = "sawn-off shotgun"
	desc = "Omar's coming!" // I'm not gonna add "Uses 12g rounds." to this one. I'll just let this reference go undisturbed.
	icon_state = "dshotgun_sawn"
	item_state = "sawnshotgun"
	slot_flags = SLOT_BELT|SLOT_HOLSTER
	ammo_type = /obj/item/ammo_casing/a12g/pellet
	w_class = ITEMSIZE_NORMAL
	force = 5
	sawn_off = TRUE

//Sjorgen Inertial Shotgun
/obj/item/gun/projectile/shotgun/semi
	name = "semi-automatic shotgun"
	desc = "A shotgun with a simple, yet effective recoil inertia loading mechanism for semi-automatic fire. This gun uses 12 gauge ammunition."
	description_fluff = "Looking back on yet another venerable design, Hedberg-Hammarstrom settled on a pattern of shotgun that both had the reliability of a well proven semi-automatic loading system in addition to a striking visual aesthetic that would be appealing to even the most discerning of firearm collectors."
	icon_state = "sjorgen"
	item_state = "shotgun"
	w_class = ITEMSIZE_LARGE
	caliber = "12g"
	slot_flags = SLOT_BACK
	load_method = SINGLE_CASING
	max_shells = 5
	ammo_type = /obj/item/ammo_casing/a12g/beanbag

/obj/item/gun/projectile/shotgun/doublebarrel/quad
	name = "quad-barreled shotgun"
	desc = "A shotgun pattern designed to make the most out of the limited machining capability of the frontier. 4 Whole barrels of death, loads using 12 gauge rounds."
	icon = 'icons/obj/gun.dmi'
	icon_state = "shotgun_q"
	item_state = "qshotgun"
	recoil = 2
	load_method = SINGLE_CASING|SPEEDLOADER
	handle_casings = CYCLE_CASINGS
	max_shells = 4
	w_class = ITEMSIZE_LARGE
	force = 5
	accuracy = 40
	slot_flags = SLOT_BACK
	ammo_type = /obj/item/ammo_casing/a12g/pellet
	caliber = "12g"
	ammo_type = /obj/item/ammo_casing/a12g/pellet
	sawn_off = 1

	burst_delay = 0

	firemodes = list(
		list(mode_name="fire one barrel at a time", burst=1),
		)

/obj/item/gun/projectile/shotgun/doublebarrel/sawn/alt
	icon = 'icons/obj/gun.dmi'
	sawn_off = 1
	icon_state = "shotpistol"
	accuracy = 40

/obj/item/gun/projectile/shotgun/doublebarrel/sawn/alt/holy
	ammo_type = /obj/item/ammo_casing/a12g/silver

// For general use
/obj/item/gun/projectile/shotgun/pump/USDF
	name = "\improper USDF tactical shotgun"
	desc = "All you greenhorns who wanted to see Xenomorphs up close... this is your lucky day. Uses 12g rounds."
	icon_state = "haloshotgun"
	icon_override = 'icons/obj/gun.dmi'
	item_state = "haloshotgun_i"
	item_icons = null
	ammo_type = /obj/item/ammo_casing/a12g
	max_shells = 12

//Warden's shotgun gets it's own entry now, rather than being handled by the maps
/obj/item/gun/projectile/shotgun/pump/combat/warden
	name = "warden's shotgun"
	desc = "Built for close quarters combat, the Hephaestus Industries KS-40 is widely regarded as a weapon of choice for repelling boarders. This one has 'Property of the Warden' inscribed on the stock."
	description_fluff = "The leading arms producer in the SCG, Hephaestus typically only uses its 'top level' branding for its military-grade equipment used by armed forces across human space."
	ammo_type = /obj/item/ammo_casing/a12g/beanbag

//Compact shotgun, this version's for usage later by mappers/coders/w.e.
/obj/item/gun/projectile/shotgun/compact
	name = "compact shotgun"
	desc = "Built for <i>extremely</i>-close quarters combat, the Hephaestus Industries KS-55 \"semi-auto shorty\" is a relatively rare sight to see, usually in the hands of elite troops that specialize in boarding. Uses 12g rounds."
	description_fluff = "The leading arms producer in the SCG, Hephaestus typically only uses its 'top level' branding for its military-grade equipment used by armed forces across human space."
	icon = 'icons/obj/gun.dmi'
	icon_state = "compshotc"
	item_state = "cshotgun"
	max_shells = 4 //short magazine tube means small capacity
	w_class = ITEMSIZE_NORMAL //Starts folded, becomes large when stock is extended
	force = 10
	slot_flags = SLOT_BELT|SLOT_BACK
	caliber = "12g"
	load_method = SINGLE_CASING|SPEEDLOADER
	handle_casings = EJECT_CASINGS //However, it's semi-automatic to make up for that
	ammo_type = /obj/item/ammo_casing/a12g
	projectile_type = /obj/item/projectile/bullet/shotgun
	one_handed_penalty = 30 //You madman, one-handing a 12g shotgun.
	recoil = 5 //Unfold the damn stock you fool!
	actions_types = list(/datum/action/item_action/toggle_stock)
	var/stock = FALSE

/obj/item/gun/projectile/shotgun/compact/proc/toggle_stock()
	var/mob/living/user = loc
	stock = !stock
	if(stock)
		act_message(user, null, MSG_SELF(span_warning("You unfold the shotgun's stock and foregrip.")), \
			MSG_OTHERS(span_warning("With a fluid movement, %U% unfolds their shotgun's stock and foregrip.")), \
			MSG_BLIND("You hear an ominous click."))
		icon_state = "compshot"
		item_state = icon_state
		w_class = ITEMSIZE_LARGE
		one_handed_penalty = 15 //Stock extended to steady it, even with just the one hand.
		recoil = 1 //As above, stock and foregrip would help with the kick
	else
		act_message(user, null, MSG_SELF(span_notice("You fold the shotgun's stock and foregrip.")), \
			MSG_OTHERS(span_infoplain(span_bold("%U%") + " collapses their shotgun's stock and fold it's foregrip.")), \
			MSG_BLIND("You hear a click."))
		icon_state = "compshotc"
		item_state = icon_state
		w_class = ITEMSIZE_NORMAL
		one_handed_penalty = 30
		recoil = 5

	if(ishuman(user))
		var/mob/living/carbon/human/H = user
		H.update_inv_l_hand()
		H.update_inv_r_hand()

	play_sfx(src, SFX_WEAPONS_TARGETON)
	user.update_mob_action_buttons()

CAPABILITIES(/obj/item/gun/projectile/shotgun/compact)
	op("compact_shotgun_verb_toggle_stock", menu(), label("Toggle stock"), needs(carried()), then(PROC_REF(compact_shotgun_verb_toggle_stock)))

/// Old Toggle stock verb.
/obj/item/gun/projectile/shotgun/compact/proc/compact_shotgun_verb_toggle_stock(datum/act/op/A)
	var/mob/user = A.actor
	if(issilicon(user))
		return

	if (isliving(user))
		toggle_stock()
	else
		to_chat(user, span_notice("You cannot do this in your current state."))

/obj/item/gun/projectile/shotgun/compact/ui_action_click(mob/unused_user, actiontype)
	var/mob/living/user = loc
	if(!isliving(user))
		return
	else
		toggle_stock()

/obj/item/gun/projectile/shotgun/compact/warden
	name = "warden's compact shotgun"
	desc = "Built for <i>extremely</i>-close quarters combat, the Hephaestus Industries KS-55 \"semi-auto shorty\" is a relatively rare sight to see, usually in the hands of elite troops that specialize in boarding. This one has 'Property of the Warden' inscribed on the upper receiver."
	description_fluff = "The leading arms producer in the SCG, Hephaestus typically only uses its 'top level' branding for its military-grade equipment used by armed forces across human space."
	ammo_type = /obj/item/ammo_casing/a12g/beanbag

/obj/item/gun/projectile/revolvershotgun
	name = "Jackhammer"
	desc = "Uses 12g rounds."
	icon = 'icons/obj/gun_yw.dmi'
	icon_state = "revolvshot"
	item_state = null
	w_class = ITEMSIZE_HUGE //.
	force = 10
	caliber = "12g"
	slot_flags = SLOT_BACK|SLOT_BELT|SLOT_HOLSTER
	handle_casings = EJECT_CASINGS
	load_method = MAGAZINE
	magazine_type = /obj/item/ammo_magazine/m12gdrumjack/beanbag
	allowed_magazines = list(/obj/item/ammo_magazine/m12gdrumjack)
	projectile_type = /obj/item/projectile/bullet/shotgun

/// The look (the draw sweep: from its template).
/obj/item/gun/projectile/revolvershotgun/draw(datum/look/look)
	..()
	look.state("revolvshot[ammo_magazine ? "" : "-empty"]")

/obj/item/ammo_magazine/m12gdrumjack
	name = "drum magazine (12 gauge slug)"
	desc = "A magazine for a revolver shotgun."
	icon = 'icons/obj/ammo_yw.dmi'
	icon_state = "c12g"
	mag_type = MAGAZINE
	caliber = "12g"
	MATERIAL_BULK(DEFAULT_WALL_MATERIAL, 1300) //did the math. now fixed the exploityness of this thing. Have fun!
	ammo_type = /obj/item/ammo_casing/a12g
	max_ammo = 4
	multiple_sprites = 1

/obj/item/ammo_magazine/m12gdrumjack/beanbag
	name = "drum magazine (12 gauge beanbag)"
	ammo_type = /obj/item/ammo_casing/a12g/beanbag

/obj/item/ammo_magazine/m12gdrumjack/pellet
	name = "drum magazine (12 gauge pellet)"
	ammo_type = /obj/item/ammo_casing/a12g/pellet

/obj/item/ammo_magazine/m12gdrumjack/flash
	name = "drum magazine (12 gauge flash)"
	ammo_type = /obj/item/ammo_casing/a12g/flash

/obj/item/ammo_magazine/m12gdrumjack/empty
	name = "drum magazine (12 gauge)"
	initial_ammo = 0
	MATERIAL_BULK(DEFAULT_WALL_MATERIAL, 1625) //Why these cost so much ? the normal ones have 13000 matter so i just multiplied by 1.25(default) don't know why it costs so much

//scattering shots, old buckshot
/obj/item/ammo_casing/a12g/scatter
	name = "scatter shotgun shell"
	desc = "A 12 gauge scattering shell"
	icon = 'icons/obj/ammo_yw.dmi'
	icon_state = "scattershell"
	projectile_type = /obj/item/projectile/scatter/shotgun
	MATERIAL_BULK(DEFAULT_WALL_MATERIAL, 450)

/obj/item/projectile/scatter/shotgun
	name = "shotgun scatter projectile"
	spread_submunition_damage = FALSE
	submunition_spread_max = 100
	submunition_spread_min = 90
	submunitions = list(
		/obj/item/projectile/bullet/shotgun/scatterprojectile = 6
		)

/obj/item/projectile/bullet/shotgun/scatterprojectile
	name = "pellet"
	icon_state = "bullet"
	fire_sound = SFX_WEAPONS_GUNSHOT_SHOTGUN
	damage = 13

/obj/item/storage/box/scattershot
	name = "box of shotgun scatter shells"
	desc = "It has a picture of a shell and several warning symbols on the front.<br>WARNING: Live ammunition. Misuse may result in serious injury or death. High spread factor, just shoot and pray."
	icon = 'icons/obj/ammo_yw.dmi'
	icon_state = "scattershot_box"
	item_state_slots = list(slot_r_hand_str = "syringe_kit", slot_l_hand_str = "syringe_kit")
	starts_with = list(/obj/item/ammo_casing/a12g/scatter = 8)

/obj/item/storage/box/scattershot/large
	starts_with = list(/obj/item/ammo_casing/a12g/scatter = 16)
