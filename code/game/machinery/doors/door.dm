// The door (doc/rewrite/final_api.html, section 16.2; doc/rewrite/conversion_guide.md).
//
// What a door is, declared: a machine that works (machine_basics), the doors() capability (two touches, open and close, with the door's own access),
// the emag, and the base door's own ops: plasteel reinforcement, a welder's repair, a weapon's strike. What a door DOES is its mechanism, below: the
// animation, the density flip, the tiles, the autoclose timer. Each kind of door adds its own beside its type (bolts and electrification are the
// airlock's stats, a firedoor opens through a prompt, a blast door answers a button).

/obj/machinery/door
	announce_damage_bands = TRUE
	name = "Door"
	desc = "It opens and closes."
	icon = 'icons/obj/doors/doorint.dmi'
	icon_state = "door1"
	anchored = TRUE
	opacity = 1
	density = TRUE
	can_atmos_pass = ATMOS_PASS_PROC
	layer = DOOR_OPEN_LAYER
	blocks_emissive = EMISSIVE_BLOCK_UNIQUE
	var/open_layer = DOOR_OPEN_LAYER
	var/closed_layer = DOOR_CLOSED_LAYER

	var/visible = 1
	/// 0: still. 1: mid-swing. -1: emagged open for good (a windoor swings a second time with 1 on an emag).
	var/operating = 0
	var/autoclose = 0
	var/glass = 0
	var/normalspeed = 1
	var/heat_proof = FALSE // For glass airlocks/opacity firedoors
	var/air_properties_vary_with_direction = 0
	max_integrity = 300
	integrity_failure = 0.25
	var/min_force = 10 //minimum amount of force needed to damage the door with a melee weapon
	var/hitsound = SFX_WEAPONS_SMASH //sound door makes when hit with a weapon
	var/block_air_zones = 1 //If set, air zones cannot merge across the door even when it is opened.
	var/list/autoclose_blockers

	var/anim_length_before_density = 0.3 SECONDS
	var/anim_length_before_finalize = 0.7 SECONDS

	//Multi-tile doors
	dir = EAST
	var/width = 1

	// turf animation
	var/atom/movable/overlay/c_animation

	/// Sheets of plasteel fitted so far (0 to 2): welded into place they make the door heat proof.
	var/reinforcing = 0
	var/tintable = 0
	var/icon_tinted
	var/id_tint

	var/update_adjacent_tiles = TRUE

TRACKED(/obj/machinery/door, operating)
TRACKED(/obj/machinery/door, reinforcing)
TRACKED(/obj/machinery/door, autoclose)
TRACKED(/obj/machinery/door, normalspeed)

MSG_DEF_SELF(door/already_reinforced, "It is already reinforced.")
MSG_DEF_SELF(door/repair_first, "It looks broken. Repair it before reinforcing it.")
MSG_DEF_SELF(door/close_first, "It must be closed first.")
MSG_DEF_SELF(door/need_more_plasteel, "You will need more plasteel to reinforce it.")
MSG_DEF_SELF(door/no_damage, "It isn't damaged.")
MSG_DEF(door/reinforced, "You finish reinforcing %T%.", "%U% finishes reinforcing %T%.")
MSG_DEF(door/repaired, "You finish repairing the damage to %T%.", "%U% repairs %T%.")
MSG_DEF(door/unreinforced, "You remove the plasteel from %T%.", "%U% removes the plasteel from %T%.")

CAPABILITIES(/obj/machinery/door)
	extend(/datum/act/hit/generic, instead(then(PROC_REF(smashed_by))))
	machine_basics(null, repair = NONE, frame = NONE)
	doors()
	emag(list(needs(req_is(nameof(density), because = MSG(door/close_first))), then(PROC_REF(door_emag))), repeatable = TRUE)
	op("strike", item(/obj/item), hostile(), when(req_on_origin(ORIGIN_CLICK | ORIGIN_MENU, req_stance(I_HURT))), when(nameof(density)), when(cond_not(req(/obj/item/card))), when(cond_not(req(/obj/item/stack/material/plasteel))), then(PROC_REF(strike_with)))
	op("reinforce", item(/obj/item/stack/material/plasteel), priority(OP_PRIORITY_PART), then(PROC_REF(add_plasteel)),
		needs(req_is(nameof(heat_proof), FALSE, because = MSG(door/already_reinforced)), req(PROC_REF(not_damaged)), req_is(nameof(density), because = MSG(door/close_first))))
	op("weld_plasteel", tool(TOOL_WELDER), when(nameof(reinforcing)), priority(OP_PRIORITY_PART + 2), wait(1 SECOND), costs(RES_FUEL, 0),
		needs(req_is(nameof(density), because = MSG(door/close_first)), req_at_least(nameof(reinforcing), 2, because = MSG(door/need_more_plasteel))),
		then(PROC_REF(plasteel_welded)), says(MSG(door/reinforced)))
	op("unreinforce", tool(TOOL_CROWBAR), when(nameof(reinforcing)), priority(OP_PRIORITY_PART + 2), wait(0), then(PROC_REF(remove_plasteel)))
	op("repair", tool(TOOL_WELDER), when(PROC_REF(repairable)), priority(OP_PRIORITY_PART), wait(PROC_REF(repair_time)),
		needs(req_is(nameof(density), because = MSG(door/close_first))), fixes(), says(MSG(door/repaired)))
	on_notice(/datum/notice/hit, then(PROC_REF(door_thrown_at)))
	on_notice(/datum/notice/bumped, then(PROC_REF(door_bumped)))
	extend(/datum/act/hit/blob, instead(then(PROC_REF(door_blobbed))))

/// A simple mob's (or a xeno's) generic hit on it, taken over (the hit/generic action): HOOK_DECLINE lets the default generic attack land.
/obj/machinery/door/proc/smashed_by(datum/act/hit/generic/A)
	var/mob/user = A.attacker
	var/damage = A.damage
	if(isanimal(user))
		var/mob/living/simple_mob/S = user
		if(damage >= STRUCTURE_MIN_DAMAGE_THRESHOLD)
			act_message(user, src, others = span_danger("%U% smashes into %T%!"))
			playsound(src, S.attack_sound, 75, 1)
			receive_generic_attack(user, damage)
		else
			act_message(user, src, others = span_infoplain(span_bold("%U%") + " bonks %T% harmlessly."))
	user.do_attack_animation(src)
	return OP_OK

// ALLOW(init/INSTANCE_STATE): a door's layer, blast resistance and bounds follow whether the map placed it shut or open and how wide it is
/obj/machinery/door/Initialize(mapload)
	. = ..()
	apply_rad_shield_material()
	if(density)
		layer = closed_layer
		explosion_resistance = initial(explosion_resistance)
		update_heat_protection(get_turf(src))
	else
		layer = open_layer
		explosion_resistance = 0

	if(width > 1)
		if(dir in list(EAST, WEST))
			bound_width = width * world.icon_size
			bound_height = world.icon_size
		else
			bound_width = world.icon_size
			bound_height = width * world.icon_size


	update_nearby_tiles(need_rebuild=1)

/// Phase 2: stops waiting on whatever blocked its autoclose.
/obj/machinery/door/lifecycle_dematerialize()
	. = ..()
	clear_autoclose_blockers()

// ---- the autoclose timer: one keyed after() on the door's clock ----

/// Arms the autoclose `wait` deciseconds from now (a still-pending one is replaced).
/obj/machinery/door/proc/autoclose_in(wait)
	clear_autoclose_blockers()
	after(src, max(wait, 0), PROC_REF(autoclose_due), key = "autoclose", clock = CLOCK_WORLD)

/// Stops waiting to autoclose.
/obj/machinery/door/proc/autoclose_cancel()
	cancel_after(src, "autoclose")

/// Is an autoclose pending?
/obj/machinery/door/proc/autoclose_pending()
	return after_pending(src, "autoclose")

/// The autoclose came due: a door that is already shut or swinging lets go of it, an autoclosing one tries again after the next wait whatever
/// this try does, and any other forgets it. Subtypes add what keeps theirs open.
/obj/machinery/door/proc/autoclose_due()
	if(density && !operating)
		return
	if(!autoclose)
		return
	after(src, next_close_wait(), PROC_REF(autoclose_due), key = "autoclose", clock = CLOCK_WORLD)
	close()

/// Waits for `blocker` to move away (or be deleted) instead of polling: the autoclose is dropped and one is armed at once when it does.
/obj/machinery/door/proc/sleep_until_autoclose_blocker_moves(atom/movable/blocker)
	if(!blocker)
		return
	rel_add(src, nameof(autoclose_blockers), blocker)
	observe(blocker, /datum/notice/moved, src, then(PROC_REF(on_autoclose_blocker_changed)))
	observe(blocker, /datum/notice/qdeleting, src, then(PROC_REF(on_autoclose_blocker_changed)))
	autoclose_cancel()

/obj/machinery/door/proc/clear_autoclose_blockers()
	for(var/atom/movable/blocker as anything in autoclose_blockers)
		unobserve(blocker, /datum/notice/moved, src)
		unobserve(blocker, /datum/notice/qdeleting, src)
	rel_clear(src, nameof(autoclose_blockers))

/obj/machinery/door/proc/on_autoclose_blocker_changed(datum/act/A)
	clear_autoclose_blockers()
	autoclose_in(0)

/obj/machinery/door/proc/can_open()
	if(!density || operating || !SSticker)
		return FALSE
	return TRUE

/obj/machinery/door/proc/can_close()
	if(density || operating || !SSticker)
		return FALSE
	return TRUE

// ---- the bump: something walked into the door (the bump action, on_notice(/datum/notice/bumped)) ----

/// Whether a bump by mob `M` reaches the door's own answer (bumpopen()): the panel is shut, the door is still, `M` has not bumped a door in the last
/// second (a bump counts once a second: shock spam), a restrained mob may not unless the door is public, and a pest nobody plays never does.
/// Stamps the second when it gets past the cooldown, as the old Bumped() did.
/obj/machinery/door/proc/bump_reaches(mob/M)
	if(panel_is_open(src) || operating)
		return FALSE
	if(ELAPSED(M, last_bumped, CLOCK_WORLD) <= 1 SECOND)
		return FALSE //Can bump-open one airlock per second. This is to prevent shock spam.
	EXPIRY_STAMP(M, last_bumped, CLOCK_WORLD)
	return bump_allowed(M)

/// bump_reaches() without the stamp: what a takeover asks before it answers the bump itself (the airlock's shock).
/obj/machinery/door/proc/bump_reaches_without_stamp(mob/M)
	if(panel_is_open(src) || operating)
		return FALSE
	if(ELAPSED(M, last_bumped, CLOCK_WORLD) <= 1 SECOND)
		return FALSE
	return bump_allowed(M)

/// A restrained mob bumps open only a public door; a pest nobody plays bumps nothing open.
/obj/machinery/door/proc/bump_allowed(mob/M)
	if(M.restrained() && !check_access(null))
		return FALSE
	if(has_trait(M, TRAIT_AMBIENT_PEST_MOB) && !(M.ckey))
		return FALSE
	return TRUE

/// Something walked into the door: a mob opens it with its access (bumpopen()), a drone or a bot with its card, a mech with its pilot's access, a
/// wheelchair with whoever pushes it. Subtypes narrow it (a blast door ignores bumps while shut).
/obj/machinery/door/proc/door_bumped(datum/act/A)
	var/datum/notice/bumped/N = A
	var/atom/movable/AM = N.bumper
	if(!AM || panel_is_open(src) || operating)
		return

	if(ismob(AM))
		var/mob/M = AM
		if(bump_reaches(M))
			bumpopen(M)
		return

	if(istype(AM, /obj/item/uav))
		if(check_access(null))
			open()
		else
			do_animate("deny")
		return

	if(isbot(AM))
		var/mob/living/bot/bot = AM
		if(check_access(bot.botcard))
			if(density)
				open()
		return

	if(istype(AM, /obj/mecha))
		var/obj/mecha/mecha = AM
		if(density)
			if(mecha?.slot_item(MECHA_SLOT_PILOT) && (allowed(mecha?.slot_item(MECHA_SLOT_PILOT)) || check_access_list(mecha.operation_req_access)))
				open()
			else
				do_animate("deny")
		return

	if(istype(AM, /obj/structure/bed/chair/wheelchair))
		var/obj/structure/bed/chair/wheelchair/wheel = AM
		if(density)
			if(wheel?.pulling_target() && (allowed(wheel?.pulling_target())))
				open()
			else
				do_animate("deny")
		return

/obj/machinery/door/CanPass(atom/movable/mover, turf/target)
	if(istype(mover) && mover.checkpass(PASSGLASS))
		return !opacity
	return !density

// CanZASPass was a ZAS zone-graph hook that controlled whether the door
// allowed adjacent zones to merge. LINDA tracks adjacency via /turf flags and
// SSair.add_to_active, not through this hook. The override is dead under LINDA;
// stub returns the old block-zones semantics so any callers from CHOMP machinery
// still get a meaningful answer (matters until they're migrated to LINDA APIs).
// was `proc/CanZASPass` declaration; the parent proc lives on /atom in
// code/atmospherics/tg_infra_stubs.dm. This is the door override.
/obj/machinery/door/CanZASPass(turf/T, is_zone)
	if(is_zone)
		return !block_air_zones
	return !density // Block airflow unless density = FALSE

/// A mob walked into the door: it opens for whoever may, and flashes its denial for whoever may not.
/obj/machinery/door/proc/bumpopen(mob/user)
	if(!user)
		return
	if(operating)
		return
	add_fingerprint(user)
	if(density)
		if(allowed(user))
			open()
		else
			do_animate("deny")
	return

/// A throw that lands is loud.
/obj/machinery/door/proc/door_thrown_at(datum/act/A)
	var/datum/notice/hit/N = A
	if(N.packet?.entry != DAMAGE_ENTRY_THROWN)
		return
	visible_message(span_danger("[name] was hit by [N.packet?.source]."))
	playsound(src, hitsound, 100, 1)

/// An EMP may pop the door open (the airlock and the windoor hook it: on_notice(/datum/notice/hit/emp, then(PROC_REF(door_emp)))).
/obj/machinery/door/proc/door_emp(datum/act/A)
	var/datum/notice/hit/emp/N = A
	if(prob(20 / max(N.packet?.severity, 1)))
		open()

/// A blob reaching a shut door: a broken one gives way, a sound one takes the hit (the hit goes on); an open door is not in its way.
/obj/machinery/door/proc/door_blobbed(datum/act/A)
	if(!density)
		return OP_OK
	if(broken_now())
		open(TRUE)
		return OP_OK
	return HOOK_DECLINE

// ---- strike: a weapon on a closed door (cards open it, plasteel reinforces it) ----

/obj/machinery/door/proc/strike_with(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/W = A.held
	add_fingerprint(user)
	user.setClickCooldown(user.get_attack_speed(W))
	if(W.obj_damage_type())
		user.do_attack_animation(src)
		if(W.force < min_force)
			act_message(user, src, others = span_danger("%U% hits %T% with %I% with no visible effect."), item = W)
		else
			act_message(user, src, others = span_danger("%U% forcefully strikes %T% with %I%!"), item = W)
			playsound(src, hitsound, 100, 1)
			receive_weapon_hit(W, user, silent = FALSE)
	return OP_OK

// ---- plasteel: sheets fitted, welded into place, or taken back ----

/// A door that has taken no damage (reinforcing it is allowed).
/obj/machinery/door/proc/not_damaged(datum/act/A)
	return (!broken_now() && get_integrity() >= max_integrity) ? null : MSG(door/repair_first) // ALLOW(reads): a door's max_integrity is its type's constant

/// Fits sheets of plasteel on the door (up to two in all, over as many visits as it takes).
/obj/machinery/door/proc/add_plasteel(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/stack/stack = A.held
	add_fingerprint(user)
	var/amount_needed = 2
	var/amount_given = amount_needed - reinforcing
	var/mats_given = stack.get_amount()
	var/singular_name = stack.singular_name
	if(reinforcing && amount_given <= 0)
		to_chat(user, span_warning("You must weld or remove \the plasteel from \the [src] before you can add anything else."))
	else
		if(mats_given >= amount_given)
			if(stack.use(amount_given))
				set_reinforcing(reinforcing + amount_given)
		else
			if(stack.use(mats_given))
				set_reinforcing(reinforcing + mats_given)
				amount_given = mats_given
	if(amount_given)
		to_chat(user, span_notice("You fit [amount_given] [singular_name]\s on \the [src]."))
	return OP_OK

/// The welder finished: the door is heat proof and the sheets are spent.
/obj/machinery/door/proc/plasteel_welded(datum/act/op/A)
	heat_proof = TRUE
	set_reinforcing(0)
	return OP_OK

/// A crowbar takes the fitted sheets back off.
/obj/machinery/door/proc/remove_plasteel(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/stack/material/plasteel/reinforcing_sheet = new /obj/item/stack/material/plasteel(get_turf(src), reinforcing)
	set_reinforcing(0)
	act_message(user, src, self = span_notice("You remove \the [reinforcing_sheet]."))
	playsound(src, A.held.usesound, 100, 1)
	return OP_OK

// ---- repair: a welder, as long as the damage ----

/// Damaged, with no sheets fitted: a welder repairs it.
/obj/machinery/door/proc/repairable(datum/act/A)
	return !reinforcing && get_integrity() < max_integrity // ALLOW(reads): a door's max_integrity is its type's constant

/// The repair takes as many deciseconds as the door is damaged.
/obj/machinery/door/proc/repair_time(datum/act/A)
	return max_integrity - get_integrity()

// ---- the emag ----

/// The emag sparks (a door that is still and working); the door gives way a moment later and stays open for good.
/obj/machinery/door/proc/door_emag(datum/act/op/A)
	do_animate("spark")
	after(src, 0.6 SECONDS, PROC_REF(trigger_emag), key = "emag")
	return OP_OK

/obj/machinery/door/proc/trigger_emag()
	PRIVATE_PROC(TRUE)
	SHOULD_NOT_OVERRIDE(TRUE)
	open()
	set_operating(-1)

/obj/machinery/door/on_update_integrity(old_value, new_value)
	. = ..()

/obj/machinery/door/atom_break(damage_flag)
	. = ..()
	if(.)
		on_broken()

/// What a door does when it breaks, after the base machinery break.
/obj/machinery/door/proc/on_broken()
	visible_message("[name] breaks!")

/// The look: a shut door shows "door1", an open one "door0" (density is tracked, so a swing redraws it). Subtypes draw their own.
/obj/machinery/door/draw(datum/look/look)
	..()
	look.state("door[density]")

/obj/machinery/door/proc/do_animate(animation)
	switch(animation)
		if("opening")
			if(panel_is_open(src))
				flick("o_doorc0", src)
			else
				flick("doorc0", src)
		if("closing")
			if(panel_is_open(src))
				flick("o_doorc1", src)
			else
				flick("doorc1", src)
		if("spark")
			if(density)
				flick("door_spark", src)
		if("deny")
			if(density && operable())
				flick("door_deny", src)
				play_sfx(src, SFX_MACHINES_BUZZ_TWO)
	return

/obj/machinery/door/proc/open(forced = 0)
	if(!can_open(forced))
		return
	set_operating(1)

	publish_navigation_change()

	do_animate("opening")
	icon_state = "door0"
	set_opacity(0)
	after(src, anim_length_before_density, PROC_REF(open_internalsetdensity), with = list(forced))

/obj/machinery/door/proc/open_internalsetdensity(forced = 0)
	PRIVATE_PROC(TRUE) //do not touch this or BYOND will devour you
	SHOULD_NOT_OVERRIDE(TRUE)
	set_density(FALSE)
	update_nearby_tiles()
	after(src, anim_length_before_finalize, PROC_REF(open_internalfinish), with = list(forced))

/obj/machinery/door/proc/open_internalfinish(forced = 0)
	PRIVATE_PROC(TRUE) //do not touch this or BYOND will devour you
	SHOULD_NOT_OVERRIDE(TRUE)
	layer = open_layer
	explosion_resistance = 0
	set_opacity(0)
	set_operating(0)

	if(autoclose)
		autoclose_in(next_close_wait())
	return TRUE

/// How long the door waits open before closing itself: a moment at high speed, a moment when the air on either side differs by 5 K or more (keeping
/// the heat in), else the stock wait.
/obj/machinery/door/proc/next_close_wait()
	if(!normalspeed)
		return 0.5 SECONDS
	var/lowest_temp = T20C
	var/highest_temp = T0C
	for(var/D in GLOB.cardinal)
		var/turf/target = get_step(loc, D)
		if(!target || target.density)
			continue
		var/datum/gas_mixture/airmix = target.return_air()
		if(!airmix)
			continue
		var/airmix_temp = airmix.return_temperature()
		lowest_temp = min(lowest_temp, airmix_temp)
		highest_temp = max(highest_temp, airmix_temp)
	return abs(highest_temp - lowest_temp) >= 5 ? 1.5 SECONDS : 15 SECONDS

/obj/machinery/door/proc/close(forced = 0, ignore_safties = FALSE, crush_damage = DOOR_CRUSH_DAMAGE)
	if(!can_close(forced))
		return
	clear_autoclose_blockers()
	set_operating(1)

	publish_navigation_change()

	autoclose_cancel()
	do_animate("closing")
	after(src, anim_length_before_density, PROC_REF(close_internalsetdensity), with = list(forced))

/obj/machinery/door/proc/close_internalsetdensity(forced = 0)
	PRIVATE_PROC(TRUE) //do not touch this or BYOND will devour you
	SHOULD_NOT_OVERRIDE(TRUE)
	set_density(TRUE)
	explosion_resistance = initial(explosion_resistance)
	layer = closed_layer
	update_nearby_tiles()
	after(src, anim_length_before_finalize, PROC_REF(close_internalfinish), with = list(forced))

/obj/machinery/door/proc/close_internalfinish(forced = 0)
	PROTECTED_PROC(TRUE) //do not touch this or BYOND will devour you
	if(visible && !glass)
		set_opacity(1)	//caaaaarn!
	set_operating(0)

	// /obj/fire was a ZAS hotspot type, deleted with the LINDA migration.
	// LINDA tracks hotspots via /obj/effect/hotspot (vendored under
	// code/atmospherics/environmental/LINDA_fire.dm). Switch to the
	// LINDA type so doors still extinguish fire underneath when they close.
	var/obj/effect/hotspot/hotspot = locate_within(loc, /obj/effect/hotspot)
	if(hotspot)
		spent(hotspot)

	return TRUE

/obj/machinery/door/proc/requiresID()
	return TRUE

/obj/machinery/door/allowed(mob/M)
	if(!requiresID())
		return ..(null) //don't care who they are or what they have, act as if they're NOTHING
	. = ..()

/obj/machinery/door/update_nearby_tiles(need_rebuild)
	if(!SSair)
		return FALSE

	for(var/turf/simulated/turf in locs)
		update_heat_protection(turf)
		SSair.mark_for_update(turf)

	return TRUE

/obj/machinery/door/proc/update_heat_protection(turf/simulated/source)
	if(istype(source))
		if(density && (opacity || heat_proof))
			source.thermal_conductivity = DOOR_HEAT_TRANSFER_COEFFICIENT
		else
			source.thermal_conductivity = initial(source.thermal_conductivity)

/obj/machinery/door/Moved(atom/old_loc, direction, forced = FALSE)
	. = ..()
	if(width > 1)
		if(dir in list(EAST, WEST))
			bound_width = width * world.icon_size
			bound_height = world.icon_size
		else
			bound_width = world.icon_size
			bound_height = width * world.icon_size

	if(update_adjacent_tiles)
		update_nearby_tiles()

/obj/machinery/door/morgue
	icon = 'icons/obj/doors/doormorgue.dmi'

/obj/machinery/door/proc/toggle()
	if(glass)
		icon = icon_tinted
		glass = 0
		if(!operating && density)
			set_opacity(1)
	else
		icon = initial(icon)
		glass = 1
		if(!operating)
			set_opacity(0)

/obj/machinery/button/windowtint/doortint
	name = "door tint control"
	desc = "A remote control switch for polarized glass doors."

/obj/machinery/button/windowtint/doortint/toggle_tint()
	use_power(5)
	set_active(!active)

	for(var/obj/machinery/door/D in range(src,range))
		if(D.icon_tinted && (D.id_tint == src.id || !D.id_tint))
			D.toggle()

/// c animation (a relation view: it reads null once the target is deleted).
/obj/machinery/door/proc/c_animation() as /atom/movable/overlay
	return c_animation
