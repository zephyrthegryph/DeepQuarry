#define ICON_CELL 1
#define ICON_CAP 2
#define ICON_BAD 4
#define ICON_CHARGE 8
#define ICON_READY 16
#define ICON_LOADED 32

/obj/item/gun/magnetic
	name = "improvised coilgun"
	desc = "A coilgun hastily thrown together out of a basic frame and advanced power storage components. Is it safe for it to be duct-taped together like that?"
	icon_state = "coilgun"
	item_state = "coilgun"
	icon = 'icons/obj/railgun.dmi'
	w_class = ITEMSIZE_HUGE //.

	var/removable_components = TRUE                            // Whether or not the gun can be dismantled.
	var/gun_unreliable = 15                                    // Percentage chance of detonating in your hands.

	var/obj/item/loaded                                        // Currently loaded object, for retrieval/unloading.
	var/load_type = /obj/item/stack/rods                       // Type of stack to load with.
	projectile_type = /obj/item/projectile/bullet/magnetic 	   // Actual fire type, since this isn't throw_at rod launcher.

	var/power_cost = 950                                       // Cost per fire, should consume almost an entire basic cell.
	var/power_per_tick                                         // Capacitor charge per process(). Updated based on capacitor rating.

TRACKED(/obj/item/gun/magnetic, removable_components)

/// Currently installed powercell.
/obj/item/gun/magnetic/var/obj/item/cell/cell
/// Installed capacitor. Higher rating == faster charge between shots. Set to a path to spawn with one of that type.
/obj/item/gun/magnetic/var/obj/item/stock_parts/capacitor/capacitor

CAPABILITIES(/obj/item/gun/magnetic)
	every(2 SECONDS, then(PROC_REF(magnetic_step)), when = PROC_REF(steps_now))
	owns_one(nameof(capacitor), /obj/item/stock_parts/capacitor)
	owns_one(nameof(loaded), /obj/item, starts = nameof(loaded))
	owns_one(nameof(cell), /obj/item/cell, starts = nameof(cell))
	op("interaction_hand", hand(), then(PROC_REF(interaction_hand)))

/// The capacitor still has somewhere to go: charging from the cell, or bleeding without one.
/// Swapping parts goes through rel_set()/own_take() (and a destroyed part is cleared by the
/// ownership framework), all of which raise the part fields; the capacitor's charge is a cross-entity
/// input (max_charge is fixed at the part's Initialize).
/obj/item/gun/magnetic/proc/capacitor_unsettled()
	return capacitor && (cell ? capacitor.charge < capacitor.max_charge : capacitor.charge)

/// The gate of the magnetic gun's step: polled, the capacitor's charge is another entity's state.
/obj/item/gun/magnetic/proc/steps_now(datum/act/A)
	return capacitor || cell

/obj/item/gun/magnetic/Initialize(mapload)
	. = ..()
	// So you can have some spawn with components
	if(ispath(capacitor))
		rel_set(src, nameof(capacitor), new capacitor(src))
		capacitor.set_charge(capacitor.max_charge)

	if(capacitor)
		power_per_tick = (power_cost*0.15) * capacitor.rating

/obj/item/gun/magnetic/get_cell()
	return cell

/// Charges its capacitor from its cell (or bleeds it without one) every 2 s while it isn't settled
/// (declared on capacitor_unsettled); firing drains the capacitor, which restarts it.
/obj/item/gun/magnetic/proc/magnetic_step(datum/act/timer/A)
	if(!capacitor_unsettled())
		return // it charged (or bled) itself settled
	if(capacitor)
		if(cell)
			if(capacitor.charge < capacitor.max_charge && cell.checked_use(power_per_tick))
				capacitor.charge(power_per_tick)
		else
			capacitor.use(capacitor.charge * 0.05)

/// The indicator flags (ICON_*) of the gun's parts and charge, read by its look and its examine.
/obj/item/gun/magnetic/proc/magnetic_flags()
	var/newstate = 0

	// Parts or lack thereof
	if(removable_components)
		if(cell)
			newstate |= ICON_CELL
		if(capacitor)
			newstate |= ICON_CAP

	// Functional state
	if(!cell || !capacitor)
		newstate |= ICON_BAD
	else if(capacitor.charge < power_cost)
		newstate |= ICON_CHARGE
	else
		newstate |= ICON_READY

	// Ammo indicator
	if(loaded)
		newstate |= ICON_LOADED

	return newstate

/obj/item/gun/magnetic/draw(datum/look/look)
	..()
	var/flags = magnetic_flags()
	var/base = initial(icon_state)
	look.overlay("[base]_cell", when = flags & ICON_CELL)
	look.overlay("[base]_capacitor", when = flags & ICON_CAP)
	look.overlay("[base]_red", when = flags & ICON_BAD)
	look.overlay("[base]_amber", when = flags & ICON_CHARGE)
	look.overlay("[base]_green", when = flags & ICON_READY)
	look.overlay("[base]_loaded", when = flags & ICON_LOADED)

/obj/item/gun/magnetic/proc/show_ammo()
	var/list/ammotext = list()
	if(loaded)
		ammotext += span_notice("It has \a [loaded] loaded.")

	return ammotext

/obj/item/gun/magnetic/examine(mob/user)
	. = ..()
	if(get_dist(user, src) <= 2)
		. += show_ammo()

		if(cell)
			. += span_notice("The installed [cell.name] has a charge level of [round((cell.charge/cell.maxcharge)*100)]%.")
		if(capacitor)
			. += span_notice("The installed [capacitor.name] has a charge level of [round((capacitor.charge/capacitor.max_charge)*100)]%.")

		var/flags = magnetic_flags()
		if(flags & ICON_BAD)
			. += span_notice("The capacitor charge indicator is blinking [span_red("red")]. Maybe you should check the cell or capacitor.")
		else
			if(flags & ICON_CHARGE)
				. += span_notice("The capacitor charge indicator is [span_orange("amber")].")
			else
				. += span_notice("The capacitor charge indicator is [span_green("green")].")

/obj/item/gun/magnetic/screwdriver_used(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/tool = A.held
	if(!removable_components)
		return OP_DECLINE
	if(!capacitor)
		to_chat(user, span_warning("\The [src] has no capacitor installed."))
		return OP_OK
	user.put_in_hands(capacitor)
	act_message(user, src, others = span_infoplain(span_bold("%U%") + " unscrews \the [capacitor] from %T%."))
	playsound(src, tool.usesound, 50, 1)
	rel_take(src, nameof(capacitor))
	return OP_OK

/// Old attackby.
/obj/item/gun/magnetic/gun_item(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/thing = A.held
	. = OP_PASS
	if(removable_components)
		if(istype(thing, /obj/item/cell))
			if(cell)
				to_chat(user, span_warning("\The [src] already has \a [cell] installed."))
				return
			if(!move_into(src, nameof(src.cell), thing, user))
				return
			play_sfx(src, SFX_MACHINES_CLICK, 0.2)
			act_message(user, src, others = span_infoplain(span_bold("%U%") + " slots %I% into %T%."), item = cell)
			return

		if(istype(thing, /obj/item/stock_parts/capacitor))
			if(capacitor)
				to_chat(user, span_warning("\The [src] already has \a [capacitor] installed."))
				return
			if(!move_into(src, nameof(src.capacitor), thing, user))
				return
			play_sfx(src, SFX_MACHINES_CLICK, 0.2)
			power_per_tick = (power_cost*0.15) * capacitor.rating
			act_message(user, src, others = span_infoplain(span_bold("%U%") + " slots %I% into %T%."), item = capacitor)
			return

	if(istype(thing, load_type))

		if(loaded)
			to_chat(user, span_warning("\The [src] already has \a [loaded] loaded."))
			return

		// This is not strictly necessary for the magnetic gun but something using
		// specific ammo types may exist down the track.
		var/obj/item/stack/ammo = thing
		if(!istype(ammo))
			if(!move_into(src, nameof(src.loaded), thing, user))
				return
		else
			rel_set(src, nameof(loaded), new load_type(src, 1))
			ammo.use(1)

		act_message(user, src, others = span_infoplain(span_bold("%U%") + " loads %T% with \the [loaded]."))
		play_sfx(src, SFX_WEAPONS_FLIPBLADE)
		return
	return ..()

/// Old attack_hand.
/obj/item/gun/magnetic/proc/interaction_hand(datum/act/op/A)
	var/mob/user = A.actor
	if(user.get_inactive_hand() == src)
		var/obj/item/removing

		if(loaded)
			removing = loaded
			rel_take(src, nameof(loaded))
		else if(cell && removable_components)
			removing = cell
			rel_take(src, nameof(cell))

		if(removing)
			removing.forceMove(get_turf(src))
			user.put_in_hands(removing)
			act_message(user, src, others = span_infoplain(span_bold("%U%") + " removes %I% from %T%."), item = removing)
			play_sfx(src, SFX_MACHINES_CLICK, 0.2)
			return TRUE
	return OP_DECLINE

/obj/item/gun/magnetic/proc/check_ammo()
	return loaded

/obj/item/gun/magnetic/proc/use_ammo()
	rel_clear(src, nameof(loaded))

/obj/item/gun/magnetic/consume_next_projectile()

	if(!check_ammo() || !capacitor || capacitor.charge < power_cost)
		return

	use_ammo()
	capacitor.use(power_cost)

	if(gun_unreliable && prob(gun_unreliable))
		after(src, 0.3 SECONDS, PROC_REF(unreliable_explode)) // So that it will still fire - considered modifying Fire() to return a value but burst fire makes that annoying.

	return new projectile_type(src)

/obj/item/gun/magnetic/fuelrod
	name = "Fuel-Rod Cannon"
	cell = /obj/item/cell/high // the declared default child (owns_one starts on /obj/item/gun/magnetic)
	capacitor = /obj/item/stock_parts/capacitor
	desc = "A bulky weapon designed to fire reactor core fuel rods at absurd velocities... who thought this was a good idea?!"
	description_antag = "This device is capable of firing reactor fuel assemblies, acquired from a R-UST fuel compressor and an appropriate fueltype. Be warned, Supermatter rods may have unforseen consequences."
	description_fluff = "Morpheus' second entry into the arms manufacturing field, the Morpheus B.F.G, or 'Big Fuel-rod Gun' made some noise when it was initially sent to the market. By noise, they mean it was rapidly declared 'incredibly dangerous to the wielder and civilians within a mile radius alike'."
	icon_state = "fuelrodgun"
	item_state = "coilgun"
	icon = 'icons/obj/railgun.dmi'
	w_class = ITEMSIZE_LARGE

	removable_components = TRUE
	gun_unreliable = 0

	load_type = /obj/item/fuel_assembly
	projectile_type = /obj/item/projectile/bullet/magnetic/fuelrod

	power_cost = 500

/obj/item/gun/magnetic/fuelrod/consume_next_projectile()
	if(!check_ammo() || !capacitor || capacitor.charge < power_cost)
		return

	if(loaded) //Safety.
		if(istype(loaded, /obj/item/fuel_assembly))
			var/obj/item/fuel_assembly/rod = loaded
			switch(rod.fuel_type)
				if(MAT_COMPOSITE) //Safety check for rods spawned in without a fueltype.
					projectile_type = /obj/item/projectile/bullet/magnetic/fuelrod
				if(MAT_DEUTERIUM)
					projectile_type = /obj/item/projectile/bullet/magnetic/fuelrod
				if(MAT_TRITIUM)
					projectile_type = /obj/item/projectile/bullet/magnetic/fuelrod/tritium
				if(MAT_PHORON)
					projectile_type = /obj/item/projectile/bullet/magnetic/fuelrod/phoron
				if(MAT_SUPERMATTER)
					projectile_type = /obj/item/projectile/bullet/magnetic/fuelrod/supermatter
					visible_message(span_danger("The barrel of \the [src] glows a blinding white!"))
					after(src, 0.5 SECONDS, PROC_REF(fuelrod_collapse))
				if("blitz")
					var/max_range = 6																// -- Polymorph
					var/banglet = 0
					projectile_type = /obj/item/projectile/bullet/magnetic/fuelrod/blitz
					visible_message(span_critical("\The [src] explodes in a blinding white light with a deafening bang!"))
					for(var/obj/structure/closet/L in hear(max_range, get_turf(src)))
						if(locate(/mob/living/carbon/, L))
							for(var/mob/living/carbon/M in L) // ALLOW(latent): mobs are never latent
								blitzed(get_turf(src), M, max_range, banglet)
					for(var/mob/living/carbon/M in hear(max_range, get_turf(src)))
						blitzed(get_turf(src), M, max_range, banglet)
					new/obj/effect/effect/sparks(src.loc)
					new/obj/effect/effect/smoke/illumination(loc, 5, 30, 30, "#FFFFFF")
					expire(0.2 SECONDS)
				if("blitzu")
					visible_message(span_critical("\The [src] explodes in a blinding white light with a deafening bang!"))
					explosion(get_turf(src),1,2,4,6)
					destroyed(src, null, "explosion")
					return
				else
					projectile_type = /obj/item/projectile/bullet/magnetic/fuelrod
	use_ammo()
	capacitor.use(power_cost)
	if(projectile_type)
		return new projectile_type(src)
	else
		return

/obj/item/gun/magnetic/fuelrod/proc/blitzed(turf/T, mob/living/carbon/M, max_range, banglet)					// Added a new proc called 'bang' that takes a location and a person to be banged.
	to_chat(M, span_danger("BANG"))						// Called during the loop that bangs people in lockers/containers and when banging
	play_sfx(src, SFX_EFFECTS_BANG, extrarange = 30)		// people in normal view.  Could theroetically be called during other explosions.

	//Checking for protections
	var/eye_safety = 0
	var/ear_safety = 0
	if(iscarbon(M))
		eye_safety = M.eyecheck()
		ear_safety = M.get_ear_protection()

	//Flashing everyone
	var/mob/living/carbon/human/H = M
	var/flash_effectiveness = 1
	var/bang_effectiveness = 1
	if(ishuman(M))
		flash_effectiveness = H.species.flash_mod
		bang_effectiveness = H.species.sound_mod
	if(eye_safety < 1 && get_dist(M, T) <= round(max_range * 0.7 * flash_effectiveness))
		M.flash_eyes()
		M.status_at_least(STAT_CONFUSED, 2 * flash_effectiveness)
		M.status_at_least(STAT_WEAKENED, 5 * flash_effectiveness)

	//Now applying sound
	if((get_dist(M, T) <= round(max_range * 0.3 * bang_effectiveness) || src.loc == M.loc || src.loc == M))
		if(ear_safety > 0)
			M.status_at_least(STAT_CONFUSED, 2)
			M.status_at_least(STAT_WEAKENED, 1)
		else
			M.status_at_least(STAT_CONFUSED, 10)
			M.status_at_least(STAT_WEAKENED, 3)
			if ((prob(14) || (M == src.loc && prob(70))))
				M.set_ear_damage(M.ear_damage + (rand(1, 10)))
			else
				M.set_ear_damage(M.ear_damage + (rand(0, 5)))
				M.status_at_least(STAT_DEAFENED, 15)
				M.deaf_loop.start() // Ear Ringing/Deafness

	else if(get_dist(M, T) <= round(max_range * 0.5 * bang_effectiveness))
		if(!ear_safety)
			M.status_at_least(STAT_CONFUSED, 8)
			M.set_ear_damage(M.ear_damage + (rand(0, 3)))
			M.status_at_least(STAT_DEAFENED, 10)
			M.deaf_loop.start() // Ear Ringing/Deafness

	else if(!ear_safety && get_dist(M, T) <= (max_range * 0.7 * bang_effectiveness))
		M.status_at_least(STAT_CONFUSED, 4)
		M.set_ear_damage(M.ear_damage + (rand(0, 1)))
		M.status_at_least(STAT_DEAFENED, 5)
		M.deaf_loop.start() // Ear Ringing/Deafness

	//This really should be in mob not every check
	if(ishuman(M))
		var/obj/item/organ/internal/eyes/E = H.organ_in(O_EYES)
		if (E && E.damage >= E.min_bruised_damage)
			to_chat(M, span_danger("Your eyes start to burn badly!"))
			if(!banglet && !(istype(src , /obj/item/grenade/flashbang/clusterbang)))
				if (E.damage >= E.min_broken_damage)
					to_chat(M, span_danger("You can't see anything!"))
	if (M.ear_damage >= 15)
		to_chat(M, span_danger("Your ears start to ring badly!"))
		if(!banglet && !(istype(src , /obj/item/grenade/flashbang/clusterbang)))
			if (prob(M.ear_damage - 10 + 5))
				to_chat(M, span_danger("You can't hear anything!"))
				M.set_sdisabilities(M.sdisabilities | (DEAF))
	else if(M.ear_damage >= 5)
		to_chat(M, span_danger("Your ears start to ring!"))


#undef ICON_CELL
#undef ICON_CAP
#undef ICON_BAD
#undef ICON_CHARGE
#undef ICON_READY
#undef ICON_LOADED

/obj/item/gun/magnetic/proc/unreliable_explode()
	visible_message(span_danger("\The [src] explodes with the force of the shot!"))
	explosion(get_turf(src), -1, 0, 2)
	destroyed(src, null, "explosion")

/// A supermatter rod's aftermath: the acceleration chamber collapses, the power supply
/// overloads, and the gun blows.
/obj/item/gun/magnetic/fuelrod/proc/fuelrod_collapse()
	visible_message(span_danger("\The [src] begins to rattle, its acceleration chamber collapsing in on itself!"))
	set_removable_components(FALSE)
	after(src, 1.5 SECONDS, PROC_REF(fuelrod_overload))

/obj/item/gun/magnetic/fuelrod/proc/fuelrod_overload()
	audible_message(span_critical("\The [src]'s power supply begins to overload as the device crumples!"), runemessage = "VWRRRRRRRR")
	play_sfx(src, SFX_EFFECTS_GRILLEHIT, 0.2)
	var/turf/T = get_turf(src)
	fx_sparks(T, 2)
	after(src, 1.5 SECONDS, PROC_REF(fuelrod_blows))

/obj/item/gun/magnetic/fuelrod/proc/fuelrod_blows()
	visible_message(span_critical("\The [src] explodes in a blinding white light!"))
	explosion(src.loc, -1, 1, 2, 3)
	destroyed(src, null, "explosion")
