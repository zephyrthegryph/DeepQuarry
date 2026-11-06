/obj/effect/mine
	name = "land mine"	//The name and description are deliberately NOT modified, so you can't game the mines you find.
	desc = "A small explosive land mine."
	density = FALSE
	anchored = TRUE
	icon = 'icons/obj/weapons.dmi'
	icon_state = "landmine"
	var/triggered = FALSE
	var/smoke_strength = 3
	var/mineitemtype = /obj/item/mine
	var/panel_open = FALSE
	var/camo_net = FALSE	// Will the mine 'cloak' on deployment?

	// The trap item will be triggered in some manner when detonating. Default only checks for grenades.
	var/obj/item/trap = null

/// A mine under a camouflage net is faint (derives(), at init).
/obj/effect/mine/proc/camo_alpha()
	return camo_net ? 50 : alpha

CAPABILITIES(/obj/effect/mine)
	on_notice(/datum/notice/bumped, then(PROC_REF(bumped_by)))
	setup(PROC_REF(register_dangerous_to_step))
	owns_one(nameof(trap), starts = nameof(trap))
	space(SPACE_PANEL, door = nameof(panel_open))
	wires(name = "Explosive Wires", count = 7, randomize = TRUE, tools = FALSE, status_lines = PROC_REF(wire_lights))
	on_wire(WIRE_EXPLODE, cut = PROC_REF(explode_wire_cut), pulse = PROC_REF(explode_wire_pulsed))
	on_wire(WIRE_EXPLODE_DELAY, cut = PROC_REF(explode_wire_cut), pulse = PROC_REF(delay_wire_pulsed))
	on_wire(WIRE_DISARM, cut = PROC_REF(disarm_wire_cut), pulse = PROC_REF(ping_wire_pulsed))
	on_wire(WIRE_BADDISARM, cut = PROC_REF(bad_disarm_wire_cut), pulse = PROC_REF(ping_wire_pulsed))
	op("use_screwdriver", tool(TOOL_SCREWDRIVER), wait(0), then(PROC_REF(screwdriver_used)))
	op("use_multitool", tool(TOOL_MULTITOOL), wait(0), then(PROC_REF(multitool_used)))
	op("use_wirecutter", tool(TOOL_WIRECUTTER), wait(0), then(PROC_REF(wirecutter_used)))
	extend(/datum/act/hit/projectile, instead(then(PROC_REF(mine_shot))))
	on_notice(/datum/notice/hit/explosion, then(PROC_REF(mine_blast)))
	derives(nameof(alpha), PROC_REF(camo_alpha))

/obj/effect/mine/proc/wire_lights()
	return list("\[Warning: detonation may occur even with proper equipment.]")

/obj/effect/mine/proc/wire_beep(text)
	visible_message("[icon2html(src, viewers(src))] [text]", "[icon2html(src, viewers(src))] [text]")

/// Either explode wire, cut or mended, sets it off.
/obj/effect/mine/proc/explode_wire_cut(datum/act/A)
	wire_beep("*BEEE-*")
	explode()

/obj/effect/mine/proc/explode_wire_pulsed(datum/act/A)
	wire_beep("*beep*")

/// The delay wire pulsed sets it off in two seconds.
/obj/effect/mine/proc/delay_wire_pulsed(datum/act/A)
	wire_beep("*BEEPBEEPBEEP*")
	if(!after_pending(src, "mine_explode")) // the earliest countdown stands: a re-pulse must not push the blast back
		after(src, 2 SECONDS, PROC_REF(explode), key = "mine_explode")

/// The disarm wire, cut: the mine comes up as its item (with its trap), the signalers on it fall off.
/obj/effect/mine/proc/disarm_wire_cut(datum/act/A)
	wire_beep("*click!*")
	var/obj/effect/mine/MI = new mineitemtype(get_turf(src))
	if(trap)
		var/obj/item/trap_item = trap
		trap_item.forceMove(MI)
		own_move(trap_item, MI, nameof(MI.trap)) // from the disarmed casing to the dropped mine
		wires_detach_all(src) // kick all the signallers off
	expire(0)

/// The bad disarm wire, cut: it goes off in two seconds.
/obj/effect/mine/proc/bad_disarm_wire_cut(datum/act/A)
	wire_beep("*BEEPBEEPBEEP*")
	if(!after_pending(src, "mine_explode")) // the earliest countdown stands: a re-pulse must not push the blast back
		after(src, 2 SECONDS, PROC_REF(explode), key = "mine_explode")

/obj/effect/mine/proc/ping_wire_pulsed(datum/act/A)
	wire_beep("*ping*")

/// The look (the draw sweep: from its layers).
/obj/effect/mine/draw(datum/look/look)
	..()
	look.state("landmine_armed")

/// Phase 2: leaves the dangerous-to-step index.
/obj/effect/mine/lifecycle_dematerialize()
	. = ..()
	unregister_dangerous_to_step()

/obj/effect/mine/Moved(atom/oldloc)
	. = ..()
	if(.)
		var/turf/old_turf = get_turf(oldloc)
		var/turf/new_turf = get_turf(src)
		if(old_turf != new_turf)
			old_turf.unregister_dangerous_object(src)
			new_turf.register_dangerous_object(src)

/obj/effect/mine/proc/explode(mob/living/M)
	if(triggered) // Prevents circular mine explosions from two mines detonating eachother
		return
	triggered = TRUE
	fx_sparks(src, 3)

	if(trap)
		trigger_trap(M)
		visible_message("\The [src.name] flashes as it is triggered!")

	else
		explosion(loc, 0, 2, 3, 4) //land mines are dangerous, folks.
		visible_message("\The [src.name] detonates!")

	consume(src)

/obj/effect/mine/proc/trigger_trap(mob/living/victim)
	if(istype(trap, /obj/item/grenade))
		var/obj/item/grenade/G = trap
		rel_take(src, nameof(trap))
		G.forceMove(get_turf(src))
		if(victim && victim.ckey)
			msg_admin_attack("[key_name_admin(victim)] stepped on \a [src.name], triggering [trap]")
		G.activate()

	if(istype(trap, /obj/item/transfer_valve))
		var/obj/item/transfer_valve/TV = trap
		rel_take(src, nameof(trap))
		TV.forceMove(get_turf(src))
		TV.toggle_valve()

/// A round may set the mine off; either way it takes no damage.
/obj/effect/mine/proc/mine_shot(datum/act/hit/projectile/A)
	if(prob(50))
		explode()
	return OP_OK

/// A blast sets the mine off (always if heavy).
/obj/effect/mine/proc/mine_blast(datum/act/A)
	var/datum/notice/hit/explosion/N = A
	var/datum/damage_packet/packet = N.packet
	if(packet.severity <= 2 || prob(50))
		explode()

/obj/effect/mine/Crossed(atom/movable/AM as mob|obj)
	if(AM.is_incorporeal())
		return
	touched_by(AM)

/// The bump notice (was Bumped()).
/obj/effect/mine/proc/bumped_by(datum/act/bump_act)
	var/datum/notice/bumped/N = bump_act
	touched_by(N.bumper)

/// Something walked into or over the mine: a vehicle, a mech or a living thing heavy enough on the ground sets it off.
/obj/effect/mine/proc/touched_by(mob/M)

	if(triggered)
		return

	if(istype(M, /obj/mecha))
		explode(M)

	if(istype(M, /obj/vehicle))
		explode(M)

	if(istype(M, /mob/living/))
		var/mob/living/mob = M
		if(!(dq_get_hovering(mob) || stat_value(mob, STAT_FLYING) || mob.is_incorporeal() || mob.mob_size <= MOB_TINY))
			explode(M)

/obj/effect/mine/proc/screwdriver_used(datum/act/op/A)
	var/mob/living/user = A.actor
	var/obj/item/tool = A.held
	set_panel_open(!panel_open)
	act_message(user, null, MSG_SELF(span_notice("You very carefully screw the mine's panel [panel_open ? "open" : "closed"].")), \
		MSG_OTHERS(span_warning("%U% very carefully screws the mine's panel [panel_open ? "open" : "closed"].")))
	playsound(src, sounds_of(tool).use, 50, 1)
	set_alpha(camo_net ? (panel_open ? 255 : 50) : 255)
	return OP_OK

/obj/effect/mine/proc/wirecutter_used(datum/act/op/A)
	var/mob/living/user = A.actor
	if(!panel_open)
		return OP_OK
	interact(user)
	return OP_OK

/obj/effect/mine/proc/multitool_used(datum/act/op/A)
	var/mob/living/user = A.actor
	if(!panel_open)
		return OP_OK
	interact(user)
	return OP_OK

/obj/effect/mine/interact(mob/living/user as mob)
	if(!panel_open)
		return
	user.open_exposed_wiring(src)

/obj/effect/mine/camo
	camo_net = TRUE
