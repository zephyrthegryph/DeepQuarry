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

/obj/effect/mine/Initialize(mapload)
	. = ..()
	register_dangerous_to_step()
	if(camo_net)
		alpha = 50

CAPABILITIES(/obj/effect/mine)
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
	after(src, 2 SECONDS, PROC_REF(explode))

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
	after(src, 2 SECONDS, PROC_REF(explode))

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
	Bumped(AM)

/obj/effect/mine/Bumped(mob/M as mob|obj)

	if(triggered)
		return

	if(istype(M, /obj/mecha))
		explode(M)

	if(istype(M, /obj/vehicle))
		explode(M)

	if(istype(M, /mob/living/))
		var/mob/living/mob = M
		if(!(dq_get_hovering(mob) || mob.flying || mob.is_incorporeal() || mob.mob_size <= MOB_TINY))
			explode(M)

/obj/effect/mine/proc/screwdriver_used(datum/act/op/A)
	var/mob/living/user = A.actor
	var/obj/item/tool = A.held
	panel_open = !panel_open
	act_message(user, null, MSG_SELF(span_notice("You very carefully screw the mine's panel [panel_open ? "open" : "closed"].")), \
		MSG_OTHERS(span_warning("%U% very carefully screws the mine's panel [panel_open ? "open" : "closed"].")))
	playsound(src, tool.usesound, 50, 1)
	alpha = camo_net ? (panel_open ? 255 : 50) : 255
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
	if(!panel_open || isAI(user))
		return
	wires_open(src, user)

/obj/effect/mine/camo
	camo_net = TRUE

/obj/effect/mine/dnascramble
	mineitemtype = /obj/item/mine/dnascramble

/obj/effect/mine/dnascramble/explode(mob/living/M)
	if(triggered) // Prevents circular mine explosions from two mines detonating eachother
		return
	triggered = TRUE
	fx_sparks(src, 3)
	if(istype(M))
		M.add_radiation(50)
		randmutb(M)
		domutcheck(M,null)
		M.UpdateAppearance()
	visible_message("\The [src.name] flashes violently before disintegrating!")
	SSmotiontracker.ping(src,100)
	consume(src)

/obj/effect/mine/stun
	mineitemtype = /obj/item/mine/stun

/obj/effect/mine/stun/explode(mob/living/M)
	if(triggered) // Prevents circular mine explosions from two mines detonating eachother
		return
	triggered = TRUE
	fx_sparks(src, 3)
	if(istype(M))
		M.status_at_least(STAT_STUNNED, 30)
	visible_message("\The [src.name] flashes violently before disintegrating!")
	SSmotiontracker.ping(src,100)
	consume(src)

/obj/effect/mine/n2o
	mineitemtype = /obj/item/mine/n2o

/obj/effect/mine/n2o/explode(mob/living/M)
	if(triggered) // Prevents circular mine explosions from two mines detonating eachother
		return
	triggered = TRUE
	for (var/turf/simulated/floor/target in range(1,src))
		if(!target.blocks_air)
			target.assume_gas(GAS_N2O, 30)
	visible_message("\The [src.name] detonates!")
	SSmotiontracker.ping(src,100)
	consume(src)

/obj/effect/mine/phoron
	mineitemtype = /obj/item/mine/phoron

/obj/effect/mine/phoron/explode(mob/living/M)
	if(triggered) // Prevents circular mine explosions from two mines detonating eachother
		return
	triggered = TRUE
	for (var/turf/simulated/floor/target in range(1,src))
		if(!target.blocks_air)
			target.assume_gas(GAS_PHORON, 30)
			target.hotspot_expose(1000, CELL_VOLUME)
	visible_message("\The [src.name] detonates!")
	SSmotiontracker.ping(src,100)
	consume(src)

/obj/effect/mine/kick
	mineitemtype = /obj/item/mine/kick

/obj/effect/mine/kick/explode(mob/living/M)
	if(triggered) // Prevents circular mine explosions from two mines detonating eachother
		return
	triggered = TRUE
	fx_sparks(src, 3)
	if(istype(M, /obj/mecha))
		var/obj/mecha/E = M
		M = E?.slot_item(MECHA_SLOT_PILOT)
	if(istype(M))
		destroyed(M.client, M)
	consume(src)

/obj/effect/mine/frag
	mineitemtype = /obj/item/mine/frag
	var/fragment_types = list(/obj/item/projectile/bullet/pellet/fragment)
	var/num_fragments = 20  //total number of fragments produced by the grenade
	//The radius of the circle used to launch projectiles. Lower values mean less projectiles are used but if set too low gaps may appear in the spread pattern
	var/spread_range = 7

/obj/effect/mine/frag/explode(mob/living/M)
	if(triggered) // Prevents circular mine explosions from two mines detonating eachother
		return
	triggered = TRUE
	fx_sparks(src, 3)
	var/turf/O = get_turf(src)
	if(!O)
		return
	src.fragmentate(O, num_fragments, spread_range, fragment_types) //only 20 weak fragments because you're stepping directly on it
	visible_message("\The [src.name] detonates!")
	SSmotiontracker.ping(src,100)
	consume(src)

/obj/effect/mine/training	//Name and Desc commented out so it's possible to trick people with the training mines
//	name = "training mine"
//	desc = "A mine with its payload removed, for EOD training and demonstrations."
	mineitemtype = /obj/item/mine/training

/obj/effect/mine/training/explode(mob/living/M)
	if(triggered) // Prevents circular mine explosions from two mines detonating eachother
		return
	triggered = TRUE
	visible_message("\The [src.name]'s light flashes rapidly as it 'explodes'.")
	new src.mineitemtype(get_turf(src))
	wires_detach_all(src) //Kick all the signallers off!
	consume(src)

/obj/effect/mine/emp
	mineitemtype = /obj/item/mine/emp

/obj/effect/mine/emp/explode(mob/living/M)
	if(triggered) // Prevents circular mine explosions from two mines detonating eachother
		return
	triggered = TRUE
	fx_sparks(src, 3)
	visible_message("\The [src.name] flashes violently before disintegrating!")
	SSmotiontracker.ping(src,100)
	empulse(loc, 2, 4, 7, 10, 1) // As strong as an EMP grenade
	consume(src)

/obj/effect/mine/emp/camo
	camo_net = TRUE

/obj/effect/mine/incendiary
	mineitemtype = /obj/item/mine/incendiary

/obj/effect/mine/incendiary/explode(mob/living/M)
	if(triggered) // Prevents circular mine explosions from two mines detonating eachother
		return
	triggered = TRUE
	fx_sparks(src, 3)
	if(istype(M))
		M.adjust_fire_stacks(5)
		M.fire_act()
	visible_message("\The [src.name] bursts into flames!")
	SSmotiontracker.ping(src,100)
	consume(src)

/obj/effect/mine/stripping
	mineitemtype = /obj/item/mine/stripping

/obj/effect/mine/stripping/explode(mob/living/M)
	if(triggered) // Prevents circular mine explosions from two mines detonating eachother
		return
	triggered = TRUE
	fx_sparks(src, 3)
	if(istype(M))
		for(var/obj/item/content_item in contents_of(M))
			M.drop_from_inventory(content_item)
	visible_message("\The [src.name] explodes, stripping [M]!")
	SSmotiontracker.ping(src,100)
	consume(src)

/obj/effect/mine/gadget
	mineitemtype = /obj/item/mine/gadget

/obj/effect/mine/gadget/explode(mob/living/M)
	if(triggered) // Prevents circular mine explosions from two mines detonating eachother
		return
	triggered = TRUE
	fx_sparks(src, 3)

	if(trap)
		trigger_trap(M)
		visible_message("\The [src.name] flashes as it is triggered!")

	else
		explosion(loc, 0, 0, 2, 2)
		visible_message("\The [src.name] detonates!")
	SSmotiontracker.ping(src,100)

	consume(src)

/////////////////////////////////////////////
// The held item version of the above mines
/////////////////////////////////////////////
/obj/item/mine
	name = "mine"
	desc = "A small explosive mine with 'HE' and a grenade symbol on the side."
	icon = 'icons/obj/weapons.dmi'
	icon_state = "landmine"
	var/countdown = 10
	var/minetype = /obj/effect/mine		//This MUST be an /obj/effect/mine type, or it'll runtime.

	var/obj/item/trap = null

	var/list/allowed_gadgets = null

MSG_DEF(mine/priming, span_infoplain("You start priming %T%. Hold still!"), "%U% starts priming %T%.")

/// The start of priming: the admin log line, the fingerprint and what is said (a start hook that answers its message).
/obj/item/mine/proc/priming_begins(datum/act/op/A)
	var/mob/user = A.actor
	add_fingerprint(user)
	msg_admin_attack("[key_name_admin(user)] primed \a [src]")
	return /datum/msg/mine/priming

/obj/item/mine/proc/primed(datum/act/op/A)
	play_sfx(src, SFX_WEAPONS_ARMBOMB)
	prime(A.actor)

/obj/item/mine/proc/priming_failed(datum/act/op/A)
	var/mob/user = A.actor
	act_message(user, null, others = "%U% triggers \the [src.name]!", blind = "You accidentally trigger \the [src.name]!")
	prime(user, TRUE)

/// Old attackby.
/obj/item/mine/proc/interaction_item(datum/act/op/A)
	var/mob/living/user = A.actor
	var/obj/item/W = A.held
	if(LAZYLEN(allowed_gadgets) && !trap)
		var/allowed = FALSE

		for(var/path in allowed_gadgets)
			if(istype(W, path))
				allowed = TRUE
				break

		if(allowed)
			move_into(src, nameof(src.trap), W, user)

	return OP_DECLINE

/obj/item/mine/proc/prime(mob/user as mob, explode_now = FALSE)
	visible_message("\The [src.name] beeps as the priming sequence completes.")
	var/obj/effect/mine/R = new minetype(get_turf(src))
	src.transfer_fingerprints_to(R)
	R.add_fingerprint(user)
	if(trap)
		rel_move(src, nameof(src.trap), R, nameof(R.trap)) // CONTAINED on the mine: the transfer moves it in
	if(explode_now)
		R.explode(user)
	consume(src)

/obj/item/mine/dnascramble
	name = "radiation mine"
	desc = "A small explosive mine with a radiation symbol on the side."
	minetype = /obj/effect/mine/dnascramble

/obj/item/mine/phoron
	name = "incendiary mine"
	desc = "A small explosive mine with a fire symbol on the side."
	minetype = /obj/effect/mine/phoron

/obj/item/mine/kick
	name = "kick mine"
	desc = "Concentrated war crimes. Handle with care."
	minetype = /obj/effect/mine/kick

/obj/item/mine/n2o
	name = "nitrous oxide mine"
	desc = "A small explosive mine with three Z's on the side."
	minetype = /obj/effect/mine/n2o

/obj/item/mine/stun
	name = "stun mine"
	desc = "A small explosive mine with a lightning bolt symbol on the side."
	minetype = /obj/effect/mine/stun

/obj/item/mine/frag
	name = "fragmentation mine"
	desc = "A small explosive mine with 'FRAG' and a grenade symbol on the side."
	minetype = /obj/effect/mine/frag

/obj/item/mine/training
	name = "training mine"
	desc = "A mine with its payload removed, for EOD training and demonstrations."
	minetype = /obj/effect/mine/training

/obj/item/mine/emp
	name = "emp mine"
	desc = "A small explosive mine with a lightning bolt symbol on the side."
	minetype = /obj/effect/mine/emp

/obj/item/mine/incendiary
	name = "incendiary mine"
	desc = "A small explosive mine with a fire symbol on the side."
	minetype = /obj/effect/mine/incendiary

/obj/item/mine/stripping
	name = "strip mine"
	desc = "A small bluespace mine with a symbol of clothing with a slash through it.."
	minetype = /obj/effect/mine/stripping

/obj/item/mine/gadget
	name = "gadget mine"
	desc = "A small pressure-triggered device. If no component is added, the internal release bolts will detonate in unison when triggered."

	allowed_gadgets = list(/obj/item/grenade, /obj/item/transfer_valve)

// This tells AI mobs to not be dumb and step on mines willingly.
/obj/item/mine/is_safe_to_step(mob/living/L)
	if(!(dq_get_hovering(L) || L.flying || L.is_incorporeal() || L.mob_size <= MOB_TINY))
		return FALSE
	return ..()

CAPABILITIES(/obj/item/mine)
	op("use_screwdriver", tool(TOOL_SCREWDRIVER), wait(10 SECONDS), needs(req(PROC_REF(has_trap), silent = TRUE)), begins(MSG(mine/removing_trap)), then(PROC_REF(screwdriver_act_done)))
	op("self", in_hand(), label("Use"), begins(PROC_REF(priming_begins)), wait(10 SECONDS), on_interrupt(PROC_REF(priming_failed)), then(PROC_REF(primed)))
	op("item", item(/obj/item), label("Use"), then(PROC_REF(interaction_item)))

MSG_DEF_SELF(mine/removing_trap, span_notice("You begin removing the trap from %T%."))

/obj/item/mine/proc/has_trap(datum/act/op/A)
	return !!trap

/obj/item/mine/proc/screwdriver_act_done(datum/act/op/A)
	var/mob/user = A.actor
	if(!(trap))
		return
	to_chat(user, span_notice("You finish disconnecting the mine's trigger."))
	trap.forceMove(get_turf(src))
	rel_take(src, nameof(trap))

//Lasertag mines

/obj/effect/mine/lasertag
	mineitemtype = /obj/item/mine/lasertag
	var/beam_types = list(/obj/item/projectile/bullet/foam_dart_riot) // you fool, you baffoon, you used these, you absolute ignoramous, why did you not read this!
	var/spread_range = 3

/obj/effect/mine/lasertag/explode(mob/living/M)
	if(triggered) // Prevents circular mine explosions from two mines detonating eachother
		return
	triggered = 1
	fx_sparks(src, 3)
	var/turf/O = get_turf(src)
	if(!O)
		return
	src.launch_many_projectiles(O, spread_range, beam_types)
	visible_message("\The [src.name] detonates!")
	consume(src)

/obj/effect/mine/lasertag/red
	mineitemtype = /obj/item/mine/lasertag/red
	beam_types = list(/obj/item/projectile/beam/lasertag/red)

/obj/effect/mine/lasertag/blue
	mineitemtype = /obj/item/mine/lasertag/blue
	beam_types = list(/obj/item/projectile/beam/lasertag/blue)

/obj/effect/mine/lasertag/omni
	mineitemtype = /obj/item/mine/lasertag/omni
	beam_types = list(/obj/item/projectile/beam/lasertag/omni)

/obj/effect/mine/lasertag/all
	mineitemtype = /obj/item/mine/lasertag/all
	beam_types = list(/obj/item/projectile/beam/lasertag/red,/obj/item/projectile/beam/lasertag/blue,/obj/item/projectile/beam/lasertag/omni)

/obj/item/mine/lasertag
	name = "lasertag mine"
	desc = "A small mine with 'BOOM' written on top, and an optical hazard warning on the side."
	minetype = /obj/effect/mine/lasertag

/obj/item/mine/lasertag/red
	name = "red lasertag mine"
	desc = "A small red mine with 'BOOM' written on top, and an optical hazard warning on the side."
	minetype = /obj/effect/mine/lasertag/red

/obj/item/mine/lasertag/blue
	name = "blue lasertag mine"
	desc = "A small blue mine with 'BOOM' written on top, and an optical hazard warning on the side."
	minetype = /obj/effect/mine/lasertag/blue

/obj/item/mine/lasertag/omni
	name = "purple lasertag mine"
	desc = "A small purple mine with 'BOOM' written on top, and an optical hazard warning on the side."
	minetype = /obj/effect/mine/lasertag/omni

/obj/item/mine/lasertag/all
	name = "chaos lasertag mine"
	desc = "A small grey mine with 'BOOM' written on top, and an optical hazard warning on the side."
	minetype = /obj/effect/mine/lasertag/all

/obj/item/mine/ownership()
	. = ..()
	. += owns(nameof(trap), policy = OWN_CONTAINED)
