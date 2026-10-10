MATERIAL_MIX(/obj/item/reagent_containers/spray, list(MAT_GLASS = 300, MAT_STEEL = 300))
/obj/item/reagent_containers/spray
	name = "spray bottle"
	desc = "A spray bottle, with an unscrewable top."
	icon = 'icons/obj/janitor.dmi'
	icon_state = "cleaner"
	item_state = "cleaner"
	center_of_mass_x = 16
	center_of_mass_y = 10
	flags = NOBLUDGEON
	slot_flags = SLOT_BELT
	throwforce = 3
	w_class = ITEMSIZE_SMALL
	throw_speed = 2
	throw_range = 10
	amount_per_transfer_from_this = 10
	unacidable = TRUE //plastic
	max_transfer_amount = 10 //Set to null instead of list, if there is only one.
	var/spray_size = 3
	var/static/list/spray_sizes = list(1,3)
	volume = 250

// A spray bottle sprays one amount at what it is clicked on, near or far (a puff of it at the floor and at the air, a splash over a dense thing next to
// the one who sprays), after a click cooldown. A closed tank fills it by the tank's own amount. It leaves alone what it is put on or in: a table, a
// closet, a sink, a janitor's cart, storage and other containers. The Empty verb pours it out over the floor. Its amount is fixed.
CAPABILITIES(/obj/item/reagent_containers/spray)
	reagent_container(
		volume = nameof(volume),
		spray = TRUE,
		settable = FALSE,
		shows_contents = FALSE,
		transfer_default = nameof(amount_per_transfer_from_this),
		taps = list(/obj/structure/reagent_dispensers),
		rests_on = list(/obj/item/storage, /obj/structure/table, /obj/structure/closet, /obj/item/reagent_containers, /obj/structure/sink, /obj/structure/janitorialcart))
	op("empty", menu(), label("Empty Spray Bottle"), confirms("Are you sure you want to empty that?"), then(PROC_REF(emptied)))
	examine_line(PROC_REF(units_left))
	extend("reagent_container.spray", reach(REACH_ANY), then(PROC_REF(spray_logged)))

MSG_DEF_SELF(spray/safety_on, "The safety is on!")

/// What a spray makes of one amount aimed at `target`: a splash over a dense thing next to the sprayer, else a puff of it travelling to the target.
/obj/item/reagent_containers/spray/reagent_spray_at(atom/target, mob/user, amount)
	play_sfx(src, SFX_EFFECTS_SPRAY2, 0.5)
	if(target.density && user?.Adjacent(target))
		act_message(user, target, others = "%U% sprays %T% with [src].")
		reagents.splash(target, amount, user = user)
	else
		var/obj/effect/effect/water/chempuff/D = new/obj/effect/effect/water/chempuff(get_turf(src))
		var/turf/my_target = get_turf(target)
		D.create_reagents(amount)
		reagents.trans_to_obj(D, amount, user = user)
		D.set_color()
		D.set_up(my_target, spray_size, 1 SECOND, user)

/// A spray of a few reagents is told to the admins.
/obj/item/reagent_containers/spray/proc/spray_logged(datum/act/op/A)
	if(reagents.has_reagent(REAGENT_ID_SACID))
		log_and_message_admins("fired sulphuric acid from \a [src].", A.actor)
	if(reagents.has_reagent(REAGENT_ID_PACID))
		log_and_message_admins("fired Polyacid from \a [src].", A.actor)
	if(reagents.has_reagent(REAGENT_ID_LUBE))
		log_and_message_admins("fired Space lube from \a [src].", A.actor)
	return OP_OK

/// How much is left, to whoever holds it.
/obj/item/reagent_containers/spray/proc/units_left(datum/act/op/A)
	if(loc != A.actor)
		return null
	return "[round(reagents.total_volume)] units left."

/// The Empty verb: the whole bottle onto the floor under whoever does it.
/obj/item/reagent_containers/spray/proc/emptied(datum/act/op/A)
	var/mob/user = A.actor
	if(!isturf(user.loc))
		return OP_REFUSED
	balloon_alert(user, "emptied \the [src] onto the floor.")
	reagents.splash(user.loc, reagents.total_volume, user = user)
	return OP_OK

//space cleaner
/obj/item/reagent_containers/spray/cleaner
	name = "space cleaner"
	desc = "BLAM!-brand non-foaming space cleaner!"

/obj/item/reagent_containers/spray/cleaner/drone
	name = "space cleaner"
	desc = "BLAM!-brand non-foaming space cleaner!"
	volume = 50

CAPABILITIES(/obj/item/reagent_containers/spray/cleaner)
	configure(reagents(add = list(REAGENT_ID_CLEANER = nameof(volume))))

/obj/item/reagent_containers/spray/sterilizine
	name = REAGENT_ID_STERILIZINE
	desc = "Great for hiding incriminating bloodstains and sterilizing scalpels."

CAPABILITIES(/obj/item/reagent_containers/spray/sterilizine)
	configure(reagents(add = list(REAGENT_ID_STERILIZINE = nameof(volume))))

/obj/item/reagent_containers/spray/pepper
	name = "pepperspray"
	desc = "Manufactured by UhangInc, used to blind and down an opponent quickly."
	icon = 'icons/obj/weapons.dmi'
	icon_state = "pepperspray"
	item_state = "pepperspray"
	center_of_mass_x = 16
	center_of_mass_y = 16
	max_transfer_amount = null
	volume = 40
	var/safety = TRUE

// The pepper spray has a safety, worked in hand: while it is on nothing comes out. It is loaded with 40 units of condensed capsaicin.
CAPABILITIES(/obj/item/reagent_containers/spray/pepper)
	configure(reagent_container(starts = list(REAGENT_ID_CONDENSEDCAPSAICIN = 40)))
	op("safety", in_hand(), label("Toggle safety"), toggles(nameof(safety)), then(PROC_REF(safety_toggled)))
	examine_line(PROC_REF(safety_text))
	extend("reagent_container.spray", needs(req_is(nameof(safety), FALSE, because = MSG(spray/safety_on))))

/obj/item/reagent_containers/spray/pepper/proc/safety_toggled(datum/act/op/A)
	balloon_alert(A.actor, "safety [safety ? "on" : "off"].")
	return OP_OK

/// Whoever is next to it can see its safety.
/obj/item/reagent_containers/spray/pepper/proc/safety_text(datum/act/op/A)
	if(!Adjacent(A.actor))
		return null
	return "The safety is [safety ? "on" : "off"]."

/obj/item/reagent_containers/spray/waterflower
	name = "water flower"
	desc = "A seemingly innocent sunflower...with a twist."
	icon = 'icons/obj/device.dmi'
	icon_state = "sunflower"
	item_state = "sunflower"
	amount_per_transfer_from_this = 1
	max_transfer_amount = null
	volume = 10
	drop_sound = SFX_ITEMS_DROP_HERB
	pickup_sound = SFX_ITEMS_PICKUP_HERB

CAPABILITIES(/obj/item/reagent_containers/spray/waterflower)
	configure(reagent_container(starts = list(REAGENT_ID_WATER = 10)))

/obj/item/reagent_containers/spray/chemsprayer
	name = "chem sprayer"
	desc = "A utility used to spray large amounts of reagent in a given area."
	icon = 'icons/obj/gun.dmi'
	icon_state = "chemsprayer"
	item_state = "chemsprayer"
	item_icons = list(slot_l_hand_str = 'icons/mob/items/lefthand_guns.dmi', slot_r_hand_str = 'icons/mob/items/righthand_guns.dmi')
	center_of_mass_x = 16
	center_of_mass_y = 16
	throwforce = 3
	w_class = ITEMSIZE_NORMAL
	max_transfer_amount = null
	volume = 600

/// Three puffs in a click: at the target and to each side of it.
/obj/item/reagent_containers/spray/chemsprayer/reagent_spray_at(atom/target, mob/user, amount)
	play_sfx(src, SFX_EFFECTS_SPRAY3, volume = rand(50,1))
	var/direction = get_dir(src, target)
	var/turf/T = get_turf(target)
	var/turf/T1 = get_step(T,turn(direction, 90))
	var/turf/T2 = get_step(T,turn(direction, -90))
	var/list/the_targets = list(T, T1, T2)

	for(var/a = 1 to 3)
		if(reagents.total_volume < 1) break
		var/obj/effect/effect/water/chempuff/D = new/obj/effect/effect/water/chempuff(get_turf(src))
		var/turf/my_target = the_targets[a]
		D.create_reagents(amount_per_transfer_from_this)
		if(!src)
			return
		reagents.trans_to_obj(D, amount_per_transfer_from_this, user = user)
		D.set_color()
		D.set_up(my_target, rand(6, 8), 0.2 SECONDS, user)

/obj/item/reagent_containers/spray/plantbgone
	name = REAGENT_PLANTBGONE
	desc = "Kills those pesky weeds!"
	icon = 'icons/obj/hydroponics_machines.dmi'
	icon_state = "plantbgone"
	item_state = "plantbgone"
	volume = 100

CAPABILITIES(/obj/item/reagent_containers/spray/plantbgone)
	configure(reagent_container(starts = list(REAGENT_ID_PLANTBGONE = 100)))

/obj/item/reagent_containers/spray/chemsprayer/hosed
	name = "hose nozzle"
	desc = "A heavy spray nozzle that must be attached to a hose."
	icon = 'icons/obj/janitor.dmi'
	icon_state = "cleaner-industrial"
	item_state = "cleaner"
	center_of_mass_x = 16
	center_of_mass_y = 10

	max_transfer_amount = 20

	var/heavy_spray = FALSE
	var/spray_particles = 3

/obj/item/reagent_containers/spray/chemsprayer/hosed/Initialize(mapload)
	. = ..()
	dq_add_recursive_move(src)
	add_hose_connector(/datum/hose_connector/input)
	observe(src, /datum/notice/movable_attempted_move, src, then(PROC_REF(update_hose)))

/obj/item/reagent_containers/spray/chemsprayer/hosed/proc/update_hose(datum/act/notice/A)
	SHOULD_NOT_SLEEP(TRUE)
	for(var/datum/hose_connector/HC as anything in get_hose_connectors())
		HC.update_hose_beam()

/// The hose, while one is attached.
/obj/item/reagent_containers/spray/chemsprayer/hosed/draw(datum/look/look)
	. = ..()
	for(var/datum/hose_connector/HC as anything in get_hose_connectors())
		look.watch(HC)
		look.watch(HC.hose())
		if(HC.get_pairing())
			look.overlay("[icon_state]+hose")
			break

// The dial is turned by an alt-click (1, 2, 3 streams of a heavy spray), and a control-click, held, switches between the light spray and the heavy one.
CAPABILITIES(/obj/item/reagent_containers/spray/chemsprayer/hosed)
	op("dial", hand(), answers(INTENT_TOGGLE), label("Turn dial"), then(PROC_REF(dial_turned)))
	op("heavy", in_hand(), gesture(GESTURE_CTRL), label("Switch the spray"), then(PROC_REF(spray_switched)))

/obj/item/reagent_containers/spray/chemsprayer/hosed/proc/dial_turned(datum/act/op/A)
	if(++spray_particles > 3) spray_particles = 1

	balloon_alert(A.actor, "dial turned to [spray_particles].")
	return OP_OK

/obj/item/reagent_containers/spray/chemsprayer/hosed/proc/spray_switched(datum/act/op/A)
	heavy_spray = !heavy_spray
	return OP_OK

/obj/item/reagent_containers/spray/chemsprayer/hosed/reagent_spray_at(atom/target, mob/user, amount)
	var/direction = get_dir(src, target)
	var/turf/T = get_turf(target)
	var/turf/T1 = get_step(T,turn(direction, 90))
	var/turf/T2 = get_step(T,turn(direction, -90))
	var/list/the_targets = list(T, T1, T2)

	if(src.reagents.total_volume < 1)
		balloon_alert(user, "\the [src] is empty.")
		return

	if(!heavy_spray)
		for(var/a = 1 to 3)
			if(reagents.total_volume < 1) break
			play_sfx(src, SFX_EFFECTS_SPRAY2, 0.5)
			var/obj/effect/effect/water/chempuff/D = new/obj/effect/effect/water/chempuff(get_turf(src))
			var/turf/my_target = the_targets[a]
			D.create_reagents(amount_per_transfer_from_this)
			if(!src)
				return
			reagents.trans_to_obj(D, amount_per_transfer_from_this, user = user)
			D.set_color()
			D.set_up(my_target, rand(6, 8), 0.2 SECONDS, user)
		return

	else
		play_sfx(src, SFX_EFFECTS_EXTINGUISH)

		for(var/a = 1 to spray_particles)
			if(!src || !reagents.total_volume) return

			var/obj/effect/effect/water/W = new /obj/effect/effect/water(get_turf(src))
			var/turf/my_target
			if(a <= the_targets.len)
				my_target = the_targets[a]
			else
				my_target = pick(the_targets)
			W.create_reagents(amount_per_transfer_from_this)
			reagents.trans_to_obj(W, amount_per_transfer_from_this, user = user)
			W.set_color()
			W.set_up(my_target, user = user)

		return

/obj/item/reagent_containers/spray/windowsealant
	name = "Krak-b-gone"
	desc = "A spray bottle of silicate sealant for rapid window repair."
	icon = 'icons/obj/items.dmi'
	icon_state = "windowsealant"
	item_state = "spraycan"
	max_transfer_amount = null
	volume = 80

CAPABILITIES(/obj/item/reagent_containers/spray/windowsealant)
	configure(reagent_container(starts = list(REAGENT_ID_SILICATE = 80)))
