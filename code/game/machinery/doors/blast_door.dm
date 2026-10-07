// BLAST DOORS
//
// Refactored 27.12.2014 by Atlantis
//
// Blast doors are suposed to be reinforced versions of regular doors. Instead of being manually
// controlled they use buttons or other means of remote control. This is why they cannot be emagged
// as they lack any ID scanning system, they just handle remote control signals. Subtypes have
// different icons, which are defined by set of variables. Subtypes are on bottom of this file.

// UPDATE 06.04.2018
// The emag thing wasn't working as intended, manually overwrote it.

#define BLAST_DOOR_CRUSH_DAMAGE 40
#define SHUTTER_CRUSH_DAMAGE 5 // Shutter damage 5.

/obj/machinery/door/blast
	name = "Blast Door"
	desc = "That looks like it doesn't open easily."
	icon = 'icons/obj/doors/rapid_pdoor.dmi'
	icon_state = null
	min_force = 20 //minimum amount of force needed to damage the door with a melee weapon
	var/datum/material/implicit_material
	// Icon states for different shutter types: draw() shows the open or closed one.
	var/icon_state_open = null
	var/icon_state_opening = null
	var/icon_state_closed = null
	var/icon_state_closing = null
	var/open_sound = SFX_MACHINES_DOOR_BLASTDOOROPEN
	var/close_sound = SFX_MACHINES_DOOR_BLASTDOORCLOSE
	var/damage = BLAST_DOOR_CRUSH_DAMAGE
	var/multiplier = 1 // The multiplier for how powerful our YEET is.
	var/istransparent = 0

	closed_layer = ON_WINDOW_LAYER // Above airlocks when closed
	var/id = 1.0
	dir = 1
	explosion_resistance = 25

	//Most blast doors are infrequently toggled and sometimes used with regular doors anyways,
	//turning this off prevents awkward zone geometry in places like medbay lobby, for example.
	block_air_zones = 0

/obj/machinery/door/blast/Initialize(mapload)
	. = ..()
	implicit_material = get_material_by_name(MAT_PLASTEEL)
	set_rad_insulation(density ? closed_rad_insulation() : RAD_NO_INSULATION)

/obj/machinery/door/blast/get_material()
	return implicit_material

/// A shut blast door ignores whatever walks into it; an open one answers as any door.
/obj/machinery/door/blast/door_bumped(datum/act/A)
	if(!density)
		return ..()

/// The look: the shut or open state its type names (icon_state_closed / icon_state_open).
/obj/machinery/door/blast/draw(datum/look/look)
	..()
	look.state(density ? icon_state_closed : icon_state_open)

// Blast doors are triggered remotely, so nobody is allowed to physically influence it.
/obj/machinery/door/blast/allowed(mob/M)
	return FALSE

// ---- what a blast door is, declared ----
//
// A door that answers a button, not a hand or a card: the base door's touch ops are refused for want of access (a held thing is swallowed, a hand
// flashes the denial), and the plasteel fitting is not offered (it is plasteel already). What is the blast door's own: a crowbar or an axe forcing
// one that has lost its power or broke, a weapon's blow (a slow one: it takes a while to dent), plasteel to mend it, a claw forcing it, an
// emag that doubles how far it throws whoever it shuts on.

MSG_DEF_SELF(blast_door/motors_resist, "Its motors resist your effort.")
MSG_DEF_SELF(blast_door/need_wield, "You need to be wielding that to do that.")
MSG_DEF_SELF(blast_door/already_repaired, "It is already fully repaired.")
MSG_DEF_SELF(blast_door/more_sheets, "You don't have enough sheets to repair this!")
MSG_DEF(blast_door/repaired, "You have repaired %T%.", "%U% repairs %T%.")
MSG_DEF(blast_door/emagged, "You subvert %T%'s motors with %I%.", "")

CAPABILITIES(/obj/machinery/door/blast)
	without(CAP_EMAG)
	without("reinforce")
	without("weld_plasteel")
	without("unreinforce")
	emag(then(PROC_REF(blast_emag)), say = MSG(blast_door/emagged))
	op("swallow", item(/obj/item), priority(OP_PRIORITY_NORMAL + 1), wait(0), then(PROC_REF(item_swallowed)))
	op("force_xeno", hand(), label("Force"), when(req(PROC_REF(claws_force))), priority(OP_PRIORITY_TAKE_OUT), wait(PROC_REF(claws_wait)),
		needs(req(PROC_REF(hand_ok), because = PROC_REF(hand_refusal))), then(PROC_REF(claws_forced)))
	op("force_generic", ai(), wait(PROC_REF(generic_wait)), then(PROC_REF(generic_forced)))
	op("pry", item(/obj/item), stance(I_HELP, I_DISARM, I_GRAB), when(req(PROC_REF(prying_item))), priority(OP_PRIORITY_PART), wait(0),
		needs(req(PROC_REF(wielded_if_axe), because = MSG(blast_door/need_wield)), req(PROC_REF(pry_free), because = MSG(blast_door/motors_resist))), then(PROC_REF(pry_forced)))
	op("pry_broken", item(/obj/item), stance(I_HURT), when(req(PROC_REF(prying_item))), when(PROC_REF(wrecked)), priority(OP_PRIORITY_CLAW), wait(0),
		needs(req(PROC_REF(wielded_if_axe), because = MSG(blast_door/need_wield)), req(PROC_REF(pry_free), because = MSG(blast_door/motors_resist))), then(PROC_REF(pry_forced)))
	op("mend", item(/obj/item/stack/material/plasteel), label("Repair"), priority(OP_PRIORITY_PART), wait(3 SECONDS),
		needs(req(PROC_REF(needs_mending), because = MSG(blast_door/already_repaired))),
		then(PROC_REF(mended)), says(MSG(blast_door/repaired)))

/// Emag: the motors are subverted and the door throws twice as hard.
/obj/machinery/door/blast/proc/blast_emag(datum/act/op/A)
	set_emagged(1)
	multiplier = 2 // Haha emag go yeet
	return OP_OK

/// A held thing does nothing to a blast door (it is not for hands or cards).
/obj/machinery/door/blast/proc/item_swallowed(datum/act/op/A)
	return OP_OK

/// A xeno's claws are on the hand.
/obj/machinery/door/blast/proc/claws_force(datum/act/op/A)
	var/mob/living/carbon/human/X = A.actor
	return !A.held && istype(X) && istype(X.species, /datum/species/xenos)

/// Claws force a shut door open slowly (15 seconds) and an open one shut quicker (5).
/obj/machinery/door/blast/proc/claws_wait(datum/act/A)
	return density ? 15 SECONDS : 5 SECONDS

/obj/machinery/door/blast/proc/claws_forced(datum/act/op/A)
	var/mob/user = A.actor
	play_sfx(src, SFX_MACHINES_DOOR_AIRLOCK_CREAKING)
	if(density)
		act_message(user, src, others = span_danger("%U% forces %T% open!"))
		force_open()
	else
		act_message(user, src, others = span_danger("%U% forces %T% closed!"))
		force_close()
	return OP_OK

/// A simple mob smashing at a blast door that has lost its power: a strong one forces it (5 seconds open, 2 shut), a weak one strains for nothing.
/// A door that works takes the smash as damage.
/obj/machinery/door/blast/smashed_by(datum/act/hit/generic/A)
	var/mob/living/user = A.attacker
	var/damage = A.damage
	if(!operable())
		if(damage >= STRUCTURE_MIN_DAMAGE_THRESHOLD)
			act_message(user, src, others = span_danger("%U% starts forcing %T% [density ? "open" : "closed"]!"))
			perform_op(user, src, "force_generic", origin = ORIGIN_SYSTEM)
		else
			act_message(user, src, others = span_notice("%U% strains fruitlessly to force %T% [density ? "open" : "closed"]."))
		return OP_OK
	return ..()

/obj/machinery/door/blast/proc/generic_wait(datum/act/A)
	return density ? 5 SECONDS : 2 SECONDS

/obj/machinery/door/blast/proc/generic_forced(datum/act/op/A)
	var/mob/user = A.actor
	if(density)
		act_message(user, src, others = span_danger("%U% forces %T% open!"))
		force_open()
	else
		act_message(user, src, others = span_danger("%U% forces %T% closed!"))
		force_close()
	return OP_OK

/// A thing in hand that pries (a crowbar, a fireaxe, a blade).
/obj/machinery/door/blast/proc/prying_item(datum/act/op/A)
	var/obj/item/held = A.held
	return istype(held) && held.pry == 1 // ALLOW(reads): an item's pry is fixed for its life

/// Broken (a hostile hand with a prying tool still pries a broken door).
/obj/machinery/door/blast/proc/wrecked(datum/act/A)
	return broken_now()

/// A fireaxe must be held in both hands to pry; anything else does not care.
/obj/machinery/door/blast/proc/wielded_if_axe(datum/act/op/A)
	var/obj/item/material/twohanded/fireaxe/F = A.held
	return !istype(F) || F.wielded // ALLOW(reads): whether an axe is wielded is read when the pry is tried

/// The motors have given out (no power or broken) and the door is still.
/obj/machinery/door/blast/proc/pry_free(datum/act/A)
	return (power_lost() || broken_now()) && !operating

/obj/machinery/door/blast/proc/pry_forced(datum/act/op/A)
	add_fingerprint(A.actor)
	force_toggle(1, A.actor)
	return OP_OK

/// A weapon's blow dents a blast door slowly: a prying weapon takes off a third of its force, anything else a seventh.
/obj/machinery/door/blast/strike_with(datum/act/op/A)
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
			receive_weapon_hit(W, user, W.force * (W.pry == 1 ? 0.35 : 0.15), silent = FALSE)
	return OP_OK

/// Sheets of plasteel it would take to mend it fully (one per 150 points).
/obj/machinery/door/blast/proc/sheets_to_mend()
	return CEILING((max_integrity - get_integrity()) / 150, 1) // ALLOW(reads): a door's max_integrity is its type's constant

/obj/machinery/door/blast/proc/needs_mending(datum/act/A)
	return sheets_to_mend() > 0

/obj/machinery/door/blast/proc/mended(datum/act/op/A)
	var/obj/item/stack/P = A.held
	if(!P?.use(sheets_to_mend()))
		to_chat(A.actor, span_warning("You don't have enough sheets to repair this! You need at least [sheets_to_mend()] sheets."))
		return OP_REFUSED
	repair()
	return OP_OK

// ---- the mechanism ----

/// Proc: force_open()
/// Description: Opens the door. No checks are done inside this proc.
/obj/machinery/door/blast/proc/force_open()
	set_operating(TRUE)
	playsound(src, open_sound, 100, 1)
	flick(icon_state_opening, src)
	set_density(FALSE)
	update_nearby_tiles()
	set_opacity(0)
	set_rad_insulation(RAD_NO_INSULATION)
	after(src, 1.5 SECONDS, PROC_REF(complete_force_open), key = "swing_open", clock = CLOCK_WORLD)

/obj/machinery/door/blast/proc/complete_force_open()
	PRIVATE_PROC(TRUE)
	layer = open_layer
	set_operating(FALSE)

/// Proc: force_close()
/// Description: Closes the door. No checks are done inside this proc.
/obj/machinery/door/blast/proc/force_close()
	// Blast door turf checks. We do this before the door closes to prevent it from failing after the door is closed, because obv a closed door will block any adjacency checks.
	var/turf/T = get_turf(src)
	var/list/yeet_turfs = T.CardinalTurfs(TRUE)

	set_operating(TRUE)
	autoclose_cancel()
	playsound(src, close_sound, 100, 1)
	layer = closed_layer
	flick(icon_state_closing, src)
	set_density(TRUE)
	update_nearby_tiles()
	set_rad_insulation(closed_rad_insulation())
	if(istransparent)
		set_opacity(0)
	else
		set_opacity(1)
	after(src, 1.5 SECONDS, PROC_REF(complete_force_close), with = list(yeet_turfs), key = "swing_close", clock = CLOCK_WORLD)

/obj/machinery/door/blast/proc/complete_force_close(list/yeet_turfs)
	PRIVATE_PROC(TRUE)
	set_operating(FALSE)

	// Blast door crushing.
	for(var/turf/turf in locs)
		for(var/atom/movable/AM in turf)
			if(AM.airlock_crush(damage))
				if(LAZYLEN(yeet_turfs))
					AM.throw_at(get_edge_target_turf(src, get_dir(src, pick(yeet_turfs))), (rand(1,3) * multiplier), (rand(2,4) * multiplier)) // YEET.
				take_damage(damage*0.2, BRUTE, MELEE)

/// Proc: force_toggle()
/// Description: Opens or closes the door, depending on current state. No checks are done inside this proc.
/obj/machinery/door/blast/proc/force_toggle(forced = 0, mob/user as mob)
	if (forced)
		play_sfx(src, SFX_MACHINES_DOOR_AIRLOCK_CREAKING)

	if(src.density)
		src.force_open()
	else
		src.force_close()

/// Proc: open()
/// Description: Opens the door. Does necessary checks. Closes itself fifteen seconds later if it autocloses.
/obj/machinery/door/blast/open(forced = 0)
	if(forced)
		force_open()
		return 1
	else
		if (src.operating || (broken_now() || power_lost()))
			return 1
		force_open()

	if(autoclose && src.operating && !(broken_now() || power_lost()))
		after(src, 15 SECONDS, PROC_REF(close), key = "autoclose", clock = CLOCK_WORLD)
	return 1

/// Proc: close()
/// Description: Closes the door. Does necessary checks.
/obj/machinery/door/blast/close()

	if (src.operating || (broken_now() || power_lost()))
		return

	force_close()
	return 1

/// Proc: repair()
/// Description: Fully repairs the blast door.
/obj/machinery/door/blast/proc/repair()
	repair_damage(max_integrity)
	atom_fix()

// SUBTYPE: Regular
// Your classical blast door, found almost everywhere.
/obj/machinery/door/blast/regular
	icon_state_open = "pdoor0"
	icon_state_opening = "pdoorc0"
	icon_state_closed = "pdoor1"
	icon_state_closing = "pdoorc1"
	icon_state = "pdoor1"
	max_integrity = 600
	heat_proof = 1 //just so repairing them doesn't try to fireproof something that never takes fire damage


/obj/machinery/door/blast/regular/open
	icon_state = "pdoor0"
	density = FALSE
	opacity = 0

/obj/machinery/door/blast/regular/bookcase //code block
	name = "bookcase"
	desc = "On closer inspection, the array of books is decorative and built into the frame."
	icon_state = "bookcase1"
	icon_state_open = "bookcase0"
	icon_state_opening = "bookcasec0"
	icon_state_closed = "bookcase1"
	icon_state_closing = "bookcasec1"

// SUBTYPE: Shuttle
// Slightly weaker, intergrated shutters - open state is hidden from view. Found on fancy_shuttles
/obj/machinery/door/blast/shuttle
	name = "shuttle blast doors"
	icon_state_open = "spdoor0"
	icon_state_opening = "spdoorc0"
	icon_state_closed = "spdoor1"
	icon_state_closing = "spdoorc1"
	icon_state = "spdoor1"
	max_integrity = 400

/obj/machinery/door/blast/shuttle/open
	icon_state = "spdoor0"
	density = FALSE
	opacity = 0

// SUBTYPE: Shutters
// Nicer looking, and also weaker, shutters. Found in kitchen and similar areas.
/obj/machinery/door/blast/shutters
	icon_state_open = "shutter0"
	icon_state_opening = "shutterc0"
	icon_state_closed = "shutter1"
	icon_state_closing = "shutterc1"
	icon_state = "shutter1"
	damage = SHUTTER_CRUSH_DAMAGE

// SUBTYPE: Transparent
// Not technically a blast door but operates like one. Allows air and light.
/obj/machinery/door/blast/gate
	name = "thick gate"
	icon_state_open = "tshutter0"
	icon_state_opening = "tshutterc0"
	icon_state_closed = "tshutter1"
	icon_state_closing = "tshutterc1"
	icon_state = "tshutter1"
	damage = SHUTTER_CRUSH_DAMAGE
	max_integrity = 400
	block_air_zones = 0
	opacity = 0
	istransparent = 1

/obj/machinery/door/blast/gate/open
	icon_state = "tshutter0"
	density = FALSE

/obj/machinery/door/blast/gate/thin
	name = "thin gate"
	icon_state_open = "shutter2_0"
	icon_state_opening = "shutter2_c0"
	icon_state_closed = "shutter2_1"
	icon_state_closing = "shutter2_c1"
	icon_state = "shutter2_1"
	max_integrity = 200
	opacity = 0

/obj/machinery/door/blast/gate/thin/open
	icon_state = "shutter2_1"
	density = FALSE

/obj/machinery/door/blast/gate/bars
	name = "prison bars"
	icon_state_open = "bars_0"
	icon_state_opening = "bars_c0"
	icon_state_closed = "bars_1"
	icon_state_closing = "bars_c1"
	icon_state = "bars_1"
	max_integrity = 600
	opacity = 0

/obj/machinery/door/blast/gate/bars/open
	icon_state = "bars_1"
	density = FALSE

// SUBTYPE: Multi-tile
// Pod doors ported from Paradise

// Whoever wrote the old code for multi-tile spesspod doors needs to burn in hell. - Unknown
// Wise words. - Bxil
/obj/machinery/door/blast/multi_tile
	name = "large blast door"

/obj/machinery/door/blast/multi_tile/Initialize(mapload)
	. = ..()
	apply_opacity_to_my_turfs(opacity)

/obj/machinery/door/blast/multi_tile/set_opacity()
	. = ..()
	apply_opacity_to_my_turfs(opacity)

/obj/machinery/door/blast/multi_tile/proc/apply_opacity_to_my_turfs(new_opacity)
	for(var/turf/T in locs)
		T.set_opacity(new_opacity)
	update_nearby_tiles()

/obj/machinery/door/blast/multi_tile
	icon_state_open = "open"
	icon_state_opening = "opening"
	icon_state_closed = "closed"
	icon_state_closing = "closing"
	icon_state = "closed"

/obj/machinery/door/blast/multi_tile/four_tile_ver_sec
	icon = 'icons/obj/doors/1x4blast_vert_sec.dmi'
	bound_height = 128
	width = 4
	dir = NORTH
	autoclose = TRUE

/obj/machinery/door/blast/multi_tile/four_tile_ver
	icon = 'icons/obj/doors/1x4blast_vert.dmi'
	bound_height = 128
	width = 4
	dir = NORTH

/obj/machinery/door/blast/multi_tile/three_tile_ver
	icon = 'icons/obj/doors/1x3blast_vert.dmi'
	bound_height = 96
	width = 3
	dir = NORTH

/obj/machinery/door/blast/multi_tile/two_tile_ver
	icon = 'icons/obj/doors/1x2blast_vert.dmi'
	bound_height = 64
	width = 2
	dir = NORTH

/obj/machinery/door/blast/multi_tile/four_tile_hor_sec
	icon = 'icons/obj/doors/1x4blast_hor_sec.dmi'
	bound_width = 128
	width = 4
	dir = EAST
	autoclose = TRUE

/obj/machinery/door/blast/multi_tile/four_tile_hor
	icon = 'icons/obj/doors/1x4blast_hor.dmi'
	bound_width = 128
	width = 4
	dir = EAST

/obj/machinery/door/blast/multi_tile/three_tile_hor
	icon = 'icons/obj/doors/1x3blast_hor.dmi'
	bound_width = 96
	width = 3
	dir = EAST

/obj/machinery/door/blast/multi_tile/two_tile_hor
	icon = 'icons/obj/doors/1x2blast_hor.dmi'
	bound_width = 64
	width = 2
	dir = EAST

#undef BLAST_DOOR_CRUSH_DAMAGE
#undef SHUTTER_CRUSH_DAMAGE

// SUBTYPE: Reactor Shroud.
// radiation proof door for use as shielding for the R-UST.
/obj/machinery/door/blast/radproof
	name = "Reactor Shroud"
	desc = "Two massive interlocking hulks of radiation resistant metal. It looks like it could stop a tank."
	icon_state_open = "pdoor0"
	icon_state_opening = "pdoorc0"
	icon_state_closed = "pdoor1"
	icon_state_closing = "pdoorc1"
	icon_state = "pdoor1"
	max_integrity = 600
	rad_insulation = RAD_FULL_INSULATION
	id = "EngineShroud"

/obj/machinery/door/blast/radproof/open
	icon_state = "pdoor0"
	density = 0
	opacity = 0
	rad_insulation = RAD_NO_INSULATION

/obj/machinery/door/blast/radproof/closed_rad_insulation()
	return RAD_FULL_INSULATION

/obj/machinery/button/remote/blast_door/radproof
	name = "Reactor Shroud Control"
	desc = "It the reactor shroud remotely."
	id = "EngineShroud"

/// Shielding while shut: its plasteel slab, or RAD_EXTREME_INSULATION without one.
/obj/machinery/door/blast/proc/closed_rad_insulation()
	return material_rad_insulation(implicit_material?.name, RAD_BLAST_DOOR_THICKNESS_MM, RAD_EXTREME_INSULATION)
