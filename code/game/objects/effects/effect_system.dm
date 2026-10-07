/* This is an attempt to make some easily reusable "particle" type effect, to stop the code
constantly having to be rewritten. An item like the jetpack that uses the ion_trail_follow system, just has one
defined, then set up when it is created with New(). Then this same system can just be reused each time
it needs to create more trails.A beaker could have a steam_trail_follow system set up, then the steam
would spawn and follow the beaker, even if it is carried or thrown.
*/
/obj/effect
	light_on = TRUE
	uses_integrity = FALSE

/obj/effect/effect
	name = "effect"
	icon = 'icons/effects/effects.dmi'
	mouse_opacity = 0
	unacidable = TRUE//So effect are not targeted by alien acid.
	pass_flags = PASSTABLE | PASSGRILLE
	blocks_emissive = EMISSIVE_BLOCK_GENERIC
	light_on = TRUE
	plane = ABOVE_OBJ_PLANE

/datum/effect/effect/system
	var/number = 3
	var/cardinals = 0
	var/turf/location
	var/atom/holder
	var/setup = 0

/datum/effect/effect/system/proc/set_up(n = 3, c = 0, turf/loc)
	if(n > 10)
		n = 10
	number = n
	cardinals = c
	rel_set(src, nameof(location), loc)
	setup = 1

/datum/effect/effect/system/proc/attach(atom/atom)
	rel_set(src, nameof(holder), atom)

/datum/effect/effect/system/proc/start()

/////////////////////////////////////////////
// GENERIC STEAM SPREAD SYSTEM

//Usage: set_up(number of bits of steam, use North/South/East/West only, spawn location)
// The attach(atom/atom) proc is optional, and can be called to attach the effect
// to something, like a smoking beaker, so then you can just call start() and the steam
// will always spawn at the items location, even if it's moved.

/** Example:
 * var/datum/effect/system/steam_spread/steam = new /datum/effect/system/steam_spread() -- creates new system
 * steam.set_up(5, 0, mob.loc) -- sets up variables
 * OPTIONAL: steam.attach(mob)
 * steam.start() -- spawns the effect
 **/
/////////////////////////////////////////////
/obj/effect/effect/steam
	name = "steam"
	icon = 'icons/effects/effects.dmi'
	icon_state = "extinguish"
	density = FALSE

/datum/effect/effect/system/steam_spread/set_up(n = 3, c = 0, turf/loc)
	if(n > 10)
		n = 10
	number = n
	cardinals = c
	rel_set(src, nameof(location), loc)

/datum/effect/effect/system/steam_spread/proc/emit_one_steam()
	if(holder)
		rel_set(src, nameof(location), get_turf(holder))
	var/obj/effect/effect/steam/steam = new /obj/effect/effect/steam(src.get_location())
	var/direction
	if(src.cardinals)
		direction = pick(GLOB.cardinal)
	else
		direction = pick(GLOB.alldirs)
	var/steps = pick(1,2,3)
	steam.drift(direction, steps, 5)
	steam.expire(20 + steps * 5)

/datum/effect/effect/system/steam_spread/start()
	var/i = 0
	for(i=0, i<src.number, i++)
		emit_one_steam()

/////////////////////////////////////////////
// SPARKS (doc/rewrite/systems.md section 16)
// fx_sparks(atom, amount, cardinals) throws sparks from the atom's turf. Every spark shares one
// live budget (the pool), so there is no per-call system datum to create, set up and start.
/////////////////////////////////////////////

/// Most sparks one fx_sparks() call throws.
#define FX_SPARKS_MAX_PER_CALL 10
/// Most sparks alive at once, world-wide; further calls throw nothing until some burn out.
#define FX_SPARKS_MAX_LIVE 100

GLOBAL_VAR_INIT(fx_live_sparks, 0)

/proc/fx_sparks(atom/where, amount = 3, cardinals = TRUE)
	var/turf/origin = get_turf(where)
	if(!origin)
		return
	amount = min(amount, FX_SPARKS_MAX_PER_CALL)
	for(var/i in 1 to amount)
		if(GLOB.fx_live_sparks >= FX_SPARKS_MAX_LIVE)
			return
		var/obj/effect/effect/sparks/spark = new(origin)
		spark.drift(pick(cardinals ? GLOB.cardinal : GLOB.alldirs), pick(1, 2, 3), 5)

/obj/effect/effect/sparks
	name = "sparks"
	icon_state = "sparks"
	var/amount = 6.0
	anchored = TRUE
	mouse_opacity = 0

// the pool counts a spark from when it exists until on_destroy().
/obj/effect/effect/sparks/on_materialize()
	. = ..()
	GLOB.fx_live_sparks++

/obj/effect/effect/sparks/Initialize(mapload)
	. = ..()
	play_sfx(src, SFX_SPARKS, 2)
	var/turf/T = src.loc
	if (istype(T, /turf))
		T.hotspot_expose(1000,100)
	expire(5 SECONDS)

// a dying spark can still light its tile.
/obj/effect/effect/sparks/on_destroy(force)
	GLOB.fx_live_sparks--
	var/turf/T = src.loc
	if (istype(T, /turf))
		T.hotspot_expose(1000,100)
	..()

/obj/effect/effect/sparks/Moved(atom/old_loc, direction, forced = FALSE)
	. = ..()
	if(isturf(loc))
		var/turf/T = loc
		T.hotspot_expose(1000,100)

#undef FX_SPARKS_MAX_PER_CALL
#undef FX_SPARKS_MAX_LIVE

/////////////////////////////////////////////
//// SMOKE SYSTEMS
// direct can be optinally added when set_up, to make the smoke always travel in one direction
// in case you wanted a vent to always smoke north for example
/////////////////////////////////////////////

/obj/effect/effect/smoke
	name = "smoke"
	icon_state = "smoke"
	opacity = 1
	anchored = FALSE
	mouse_opacity = 0
	var/amount = 6.0
	var/time_to_live = 100

	//Remove this bit to use the old smoke
	icon = 'icons/effects/96x96.dmi'
	pixel_x = -32
	pixel_y = -32

/obj/effect/effect/smoke/Initialize(mapload)
	. = ..()
	if(time_to_live)
		expire(time_to_live)

/obj/effect/effect/smoke/Crossed(mob/living/carbon/M as mob )
	if(M.is_incorporeal())
		return
	..()
	if(istype(M))
		affect(M)

/obj/effect/effect/smoke/proc/affect(mob/living/carbon/M)
	if (!istype(M))
		return 0
	if(M.get_equipped_item(SLOT_ID_MASK) && (M.get_equipped_item(SLOT_ID_MASK).item_flags & AIRTIGHT))
		return 0
	if(ishuman(M))
		var/mob/living/carbon/human/H = M
		if(!M.get_organ(O_LUNGS)) // Making sure smoke doesn't affect lungless people
			return 0
		if(H.get_equipped_item(SLOT_ID_HEAD) && (H.get_equipped_item(SLOT_ID_HEAD).item_flags & AIRTIGHT))
			return 0
	return 1

/////////////////////////////////////////////
// Illumination
/////////////////////////////////////////////

/obj/effect/effect/smoke/illumination
	name = "illumination"
	opacity = 0
	icon = 'icons/effects/effects.dmi'
	icon_state = "sparks"

CAPABILITIES(/obj/effect/effect/smoke/illumination)
	param(nameof(time_to_live), pos = 1, default = 10)
	param(nameof(glow_range), pos = 2)
	param(nameof(glow_power), pos = 3)
	param(nameof(glow_color), pos = 4, apply = PROC_REF(glow))

/// The light the smoke gives (its constructor params).
/obj/effect/effect/smoke/illumination/var/glow_range
/obj/effect/effect/smoke/illumination/var/glow_power
/obj/effect/effect/smoke/illumination/var/glow_color

/// Applied at init from its constructor param (param(apply =), code/engine/lifeforms/params.dm).
/obj/effect/effect/smoke/illumination/proc/glow(colour)
	set_light(glow_range, glow_power, glow_color)

/////////////////////////////////////////////
// Bad smoke
/////////////////////////////////////////////

/obj/effect/effect/smoke/bad
	time_to_live = 600

/obj/effect/effect/smoke/bad/Moved(atom/old_loc, direction, forced = FALSE)
	. = ..()
	for(var/mob/living/L in get_turf(src))
		affect(L)

/obj/effect/effect/smoke/bad/affect(mob/living/L)
	if (!..())
		return 0
	if(L.needs_to_breathe())
		// Choking smoke in the lungs: gas exchange falters while it's breathed.
		L.body?.add_restriction(src, BF_GAS_EXCHANGE, 0.5, 4 SECONDS)
		if(prob(25))
			L.emote("cough")

/obj/effect/effect/smoke/bad/noxious
	opacity = 0

/obj/effect/effect/smoke/bad/noxious/affect(mob/living/L)
	if (!..())
		return 0
	if(L.needs_to_breathe())
		L.injure(INJURY_TOXIN, 1, null, src)

/* Not feasile until a later date
/obj/effect/effect/smoke/bad/Crossed(atom/movable/M as mob|obj)
	..()
	if(istype(M, /obj/item/projectile/beam))
		var/obj/item/projectile/beam/B = M
		if(!(B in projectiles))
			B.damage = (B.damage/2)
			projectiles += B
			destroyed_event.register(B, src, /obj/effect/effect/smoke/bad/proc/on_projectile_delete)
		to_world("Damage is: [B.damage]")
	return 1

/obj/effect/effect/smoke/bad/proc/on_projectile_delete(obj/item/projectile/beam/proj)
	projectiles -= proj
*/

// Burnt Food Smoke (Specialty for Cooking Failures)
/obj/effect/effect/smoke/bad/burntfood
	color = "#000000"
	time_to_live = 600

/obj/effect/effect/smoke/bad/burntfood/periodic_step()
	for(var/mob/living/L in get_turf(src))
		affect(L)

/obj/effect/effect/smoke/bad/burntfood/affect(mob/living/L) // This stuff is extra-vile.
	if (!..())
		return 0
	if(L.needs_to_breathe())
		L.emote("cough")

/////////////////////////////////////////////
// 'Elemental' smoke
/////////////////////////////////////////////

/obj/effect/effect/smoke/elemental
	name = "cloud"
	desc = "A cloud of some kind that seems really generic and boring."
	opacity = FALSE
	var/strength = 5 // How much damage to do inside each affect()

CAPABILITIES(/obj/effect/effect/smoke/elemental)
	every(2 SECONDS, then(PROC_REF(elemental_step)))

/obj/effect/effect/smoke/elemental/Moved(atom/old_loc, direction, forced = FALSE)
	. = ..()
	for(var/mob/living/L in range(1, src))
		affect(L)

/obj/effect/effect/smoke/elemental/proc/elemental_step(datum/act/timer/A)
	for(var/mob/living/L in range(1, src))
		affect(L)

/obj/effect/effect/smoke/elemental/fire
	name = "burning cloud"
	desc = "A cloud of something that is on fire."
	color = "#FF9933"
	light_color = "#FF0000"
	light_range = 2
	light_power = 5

/obj/effect/effect/smoke/elemental/fire/affect(mob/living/L)
	L.inflict_heat_damage(strength)
	L.adjust_fire_stacks(10)
	L.ignite_mob()

/obj/effect/effect/smoke/elemental/frost
	name = "freezing cloud"
	desc = "A cloud filled with brutally cold mist."
	color = "#00CCFF"

/obj/effect/effect/smoke/elemental/frost/affect(mob/living/L)
	L.inflict_cold_damage(strength)

/obj/effect/effect/smoke/elemental/shock
	name = "charged cloud"
	desc = "A cloud charged with electricity."
	color = "#4D4D4D"

/obj/effect/effect/smoke/elemental/shock/affect(mob/living/L)
	L.inflict_shock_damage(strength)

/obj/effect/effect/smoke/elemental/mist
	name = "misty cloud"
	desc = "A cloud filled with water vapor."
	color = "#F0FFFF"
	alpha = 128
	strength = 1
	plane = MOB_PLANE
	layer = ABOVE_MOB_LAYER

/obj/effect/effect/smoke/elemental/mist/affect(mob/living/L)
	L.water_act(strength)

/////////////////////////////////////////////
// Smoke spread
/////////////////////////////////////////////

/datum/effect/effect/system/smoke_spread
	var/total_smoke = 0 // To stop it being spammed and lagging!
	var/direction
	var/smoke_type = /obj/effect/effect/smoke

/datum/effect/effect/system/smoke_spread/set_up(n = 5, c = 0, loca, direct)
	if(n > 10)
		n = 10
	number = n
	cardinals = c
	if(istype(loca, /turf/))
		rel_set(src, nameof(location), loca)
	else
		rel_set(src, nameof(location), get_turf(loca))
	if(direct)
		direction = direct

/datum/effect/effect/system/smoke_spread/proc/emit_one_smoke(color_override)
	if(holder)
		rel_set(src, nameof(location), get_turf(holder))
	var/obj/effect/effect/smoke/smoke = new smoke_type(src.get_location())
	src.total_smoke++
	if(color_override)
		smoke.color = color_override
	var/direction = src.direction
	if(!direction)
		if(src.cardinals)
			direction = pick(GLOB.cardinal)
		else
			direction = pick(GLOB.alldirs)
	var/steps = pick(0,1,1,1,2,2,2,3)
	smoke.drift(direction, steps, 1 SECOND)
	after(src, steps * 1 SECOND + smoke.time_to_live*0.75+rand(1 SECOND, 3 SECONDS), PROC_REF(expire_smoke), with = list(smoke), keeps_dead = TRUE)

/datum/effect/effect/system/smoke_spread/proc/expire_smoke(obj/effect/effect/smoke/smoke)
	if(smoke)
		consume(smoke)
	src.total_smoke--

/datum/effect/effect/system/smoke_spread/start(I)
	var/i = 0
	for(i=0, i<src.number, i++)
		if(src.total_smoke > 20)
			return
		emit_one_smoke(I)

/datum/effect/effect/system/smoke_spread/bad
	smoke_type = /obj/effect/effect/smoke/bad

/datum/effect/effect/system/smoke_spread/bad/burntfood
	smoke_type = /obj/effect/effect/smoke/bad/burntfood

/datum/effect/effect/system/smoke_spread/noxious
	smoke_type = /obj/effect/effect/smoke/bad/noxious

/datum/effect/effect/system/smoke_spread/fire
	smoke_type = /obj/effect/effect/smoke/elemental/fire

/datum/effect/effect/system/smoke_spread/frost
	smoke_type = /obj/effect/effect/smoke/elemental/frost

/datum/effect/effect/system/smoke_spread/shock
	smoke_type = /obj/effect/effect/smoke/elemental/shock

/datum/effect/effect/system/smoke_spread/mist
	smoke_type = /obj/effect/effect/smoke/elemental/mist

/////////////////////////////////////////////
//////// Attach an Ion trail to any object, that spawns when it moves (like for the jetpack)
/// just pass in the object to attach it to in set_up
/// Then do start() to start it and stop() to stop it, obviously
/// and don't call start() in a loop that will be repeated otherwise it'll get spammed!
/////////////////////////////////////////////

/obj/effect/effect/ion_trails
	name = "ion trails"
	icon_state = "ion_trails"
	anchored = TRUE

/datum/effect/effect/system/ion_trail_follow
	var/turf/oldposition
	var/processing = 1
	var/on = 1

/datum/effect/effect/system/ion_trail_follow/set_up(atom/atom)
	attach(atom)
	rel_set(src, nameof(oldposition), get_turf(atom))

/datum/effect/effect/system/ion_trail_follow/proc/trail_step()
	var/turf/T
	if(istype(holder, /atom/movable))
		var/atom/movable/AM = holder
		if(AM.locs && AM.locs.len)
			T = get_turf(pick(AM.locs))
		else
			T = get_turf(AM)
	else //when would this ever be attached a non-atom/movable?
		T = get_turf(src.holder)
	if(T != src.oldposition())
		if(isturf(T))
			var/obj/effect/effect/ion_trails/I = new /obj/effect/effect/ion_trails(src.oldposition())
			rel_set(src, nameof(oldposition), T)
			I.set_dir(src.holder.dir)
			flick("ion_fade", I)
			I.icon_state = "blank"
			I.expire(20)
	after(src, 0.2 SECONDS, PROC_REF(reschedule_trail))

/datum/effect/effect/system/ion_trail_follow/proc/reschedule_trail()
	if(src.on)
		src.processing = 1
		src.start()

/datum/effect/effect/system/ion_trail_follow/start()
	if(!src.on)
		src.on = 1
		src.processing = 1
	if(src.processing)
		src.processing = 0
		trail_step()

/datum/effect/effect/system/ion_trail_follow/proc/stop()
		src.processing = 0
		src.on = 0

/////////////////////////////////////////////
//////// Attach a steam trail to an object (eg. a reacting beaker) that will follow it
// even if it's carried of thrown.
/////////////////////////////////////////////

/datum/effect/effect/system/steam_trail_follow
	var/turf/oldposition
	var/processing = 1
	var/on = 1

/datum/effect/effect/system/steam_trail_follow/set_up(atom/atom)
	attach(atom)
	rel_set(src, nameof(oldposition), get_turf(atom))

/datum/effect/effect/system/steam_trail_follow/proc/steam_step()
	if(src.number < 3)
		var/obj/effect/effect/steam/I = new /obj/effect/effect/steam(src.oldposition())
		src.number++
		rel_set(src, nameof(oldposition), get_turf(holder))
		I.set_dir(src.holder.dir)
		after(src, 1 SECOND, PROC_REF(expire_steam_trail), with = list(I))
	after(src, 0.2 SECONDS, PROC_REF(reschedule_steam))

/datum/effect/effect/system/steam_trail_follow/proc/expire_steam_trail(obj/effect/effect/steam/I)
	consume(I)
	src.number--

/datum/effect/effect/system/steam_trail_follow/proc/reschedule_steam()
	if(src.on)
		src.processing = 1
		src.start()

/datum/effect/effect/system/steam_trail_follow/start()
	if(!src.on)
		src.on = 1
		src.processing = 1
	if(src.processing)
		src.processing = 0
		steam_step()

/datum/effect/effect/system/steam_trail_follow/proc/stop()
	src.processing = 0
	src.on = 0

/datum/effect/effect/system/reagents_explosion
	var/amount 						// TNT equivalent
	var/flashing = 0			// does explosion creates flash effect?
	var/flashing_factor = 0		// factor of how powerful the flash effect relatively to the explosion

/datum/effect/effect/system/reagents_explosion/set_up(amt, loc, flash = 0, flash_fact = 0)
	amount = amt
	if(istype(loc, /turf/))
		rel_set(src, nameof(location), loc)
	else
		rel_set(src, nameof(location), get_turf(loc))

	flashing = flash
	flashing_factor = flash_fact

	return

/datum/effect/effect/system/reagents_explosion/start()
	if (amount <= 2)
		fx_sparks(get_location(), 2)

		for(var/mob/M in viewers(5, get_location()))
			to_chat(M, span_warning("The solution violently explodes."))
		for(var/mob/M in viewers(1, get_location()))
			if (prob (50 * amount))
				to_chat(M, span_warning("The explosion knocks you down."))
				M.status_at_least(STAT_WEAKENED, rand(1,5))
		return
	else
		var/devst = -1
		var/heavy = -1
		var/light = -1
		var/flash = -1

		// Clamp all values to fractions of max_explosion_range, following the same pattern as for tank transfer bombs
		if (round(amount/12) > 0)
			devst = devst + amount/12

		if (round(amount/6) > 0)
			heavy = heavy + amount/6

		if (round(amount/3) > 0)
			light = light + amount/3

		if (flashing && flashing_factor)
			flash = (amount/4) * flashing_factor

		for(var/mob/M in viewers(8, get_location()))
			to_chat(M, span_warning("The solution violently explodes."))

		explosion(
			get_location(),
			round(min(devst, BOMBCAP_DVSTN_RADIUS)),
			round(min(heavy, BOMBCAP_HEAVY_RADIUS)),
			round(min(light, BOMBCAP_LIGHT_RADIUS)),
			round(min(flash, BOMBCAP_FLASH_RADIUS))
			)

/obj/effect/effect/teleport_greyscale
	name = "teleportation"
	icon = 'icons/effects/effects.dmi'
	icon_state = "teleport_greyscale"
	anchored = 1
	mouse_opacity = 0
	plane = MOB_PLANE
	layer = ABOVE_MOB_LAYER

/obj/effect/effect/teleport_greyscale/Initialize(mapload)
	. = ..()
	expire(2 SECONDS)

/datum/effect/effect/system/teleport_greyscale
	var/color = "#FFFFFF"

/datum/effect/effect/system/teleport_greyscale/set_up(cl, loca)
	if(istype(loca, /turf/))
		rel_set(src, nameof(location), loca)
	else
		rel_set(src, nameof(location), get_turf(loca))
	color = cl

/datum/effect/effect/system/teleport_greyscale/start()
	var/obj/effect/effect/teleport_greyscale/tele = new /obj/effect/effect/teleport_greyscale(src.get_location())
	tele.color = color


/////////////////////////////////////////////
// Confetti and Glitter
// Uses same system as smoke so can have directional travel
/////////////////////////////////////////////

/obj/effect/effect/confetti
	name = "confetti"
	icon = 'icons/effects/effects.dmi'
	icon_state = "confetti"
	opacity = 0
	anchored = 0.0
	mouse_opacity = 0
	var/amount = 6.0
	var/time_to_live = 500

/obj/effect/effect/confetti/Initialize(mapload)
	. = ..()
	if(time_to_live)
		expire(time_to_live)
				//make confetti on ground cleanable decal to spawn

/datum/effect/effect/system/confetti_spread
	var/total_confetti = 0 // To stop it being spammed and lagging!
	var/direction
	var/confetti_type = /obj/effect/effect/confetti

/datum/effect/effect/system/confetti_spread/set_up(n = 5, c = 0, loca, direct)
	if(n > 10)
		n = 10
	number = n
	cardinals = c
	if(istype(loca, /turf/))
		rel_set(src, nameof(location), loca)
	else
		rel_set(src, nameof(location), get_turf(loca))
	if(direct)
		direction = direct

/datum/effect/effect/system/confetti_spread/proc/emit_one_confetti(color_override)
	if(holder)
		rel_set(src, nameof(location), get_turf(holder))
	var/obj/effect/effect/confetti/confetti = new confetti_type(src.get_location())
	src.total_confetti++
	if(color_override)
		confetti.color = color_override
	var/direction = src.direction
	if(!direction)
		if(src.cardinals)
			direction = pick(GLOB.cardinal)
		else
			direction = pick(GLOB.alldirs)
	var/steps = pick(0,1,1,1,2,2,2,3)
	confetti.drift(direction, steps, 1 SECOND)
	after(src, steps * 1 SECOND + confetti.time_to_live*0.75+rand(1 SECOND, 3 SECONDS), PROC_REF(expire_confetti), with = list(confetti), keeps_dead = TRUE)

/datum/effect/effect/system/confetti_spread/proc/expire_confetti(obj/effect/effect/confetti/confetti)
	if(confetti)
		consume(confetti)
	src.total_confetti--

/datum/effect/effect/system/confetti_spread/start(I)
	var/i = 0
	for(i=0, i<src.number, i++)
		if(src.total_confetti > 20)
			return
		emit_one_confetti(I)

/////////////////////////////////////////////
// Snow fall
// Permanent mood snow
/////////////////////////////////////////////

/obj/effect/effect/snow
	name = "light snowfall"
	icon = 'icons/effects/weather.dmi'
	icon_state = "snowfall_light"

	layer = 4.2
	opacity = 0
	anchored = 0.0
	mouse_opacity = 0

/obj/effect/effect/snow/medium
	name = "medium snowfall"
	icon_state = "snowfall_med"

/obj/effect/effect/snow/heavy
	name = "heavy snowfall"
	icon_state = "snowfall_heavy"

/// Relation view: location (reads null once it is gone).
/datum/effect/effect/system/proc/get_location() as /turf
	return location

/// Relation view: oldposition (reads null once it is gone).
/datum/effect/effect/system/ion_trail_follow/proc/oldposition() as /turf
	return oldposition

/// Relation view: oldposition (reads null once it is gone).
/datum/effect/effect/system/steam_trail_follow/proc/oldposition() as /turf
	return oldposition

