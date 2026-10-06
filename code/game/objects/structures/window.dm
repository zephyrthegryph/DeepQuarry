/obj/structure/window
	announce_damage_bands = TRUE
	damage_wear = "cracks"
	name = "window"
	desc = "A window."
	icon = 'icons/obj/structures_vr.dmi' // New icons
	density = TRUE
	can_atmos_pass = ATMOS_PASS_PROC
	w_class = ITEMSIZE_NORMAL

	layer = WINDOW_LAYER
	pressure_resistance = 4*ONE_ATMOSPHERE
	anchored = TRUE
	flags = ON_BORDER
	max_integrity = 14
	var/maximal_heat = T0C + 100 		// Maximal heat before this window begins taking damage from fire
	var/damage_per_fire_tick = 2.0 		// Amount of damage per fire tick. Regular windows are not fireproof so they might as well break quickly.
	var/force_threshold = 0
	var/ini_dir = null
	var/state = 2
	var/reinf = 0
	var/basestate
	var/shardtype = /obj/item/material/shard
	var/glasstype = null // Set this in subtypes. Null is assumed strange or otherwise impossible to dismantle, such as for shuttle glass.
	var/silicate = 0 // number of units of silicate
	var/fulltile = FALSE // Set to true on full-tile variants.

/obj/structure/window/examine(mob/user)
	. = ..()

	if(silicate)
		if (silicate < 30)
			. += span_notice("It has a thin layer of silicate.")
		else if (silicate < 70)
			. += span_notice("It is covered in silicate.")
		else
			. += span_notice("There is a thick layer of silicate covering it.")

/obj/structure/window/examine_icon()
	return icon(icon=initial(icon),icon_state=initial(icon_state))

// Silicate coating soaks part of incoming damage, armor-style.
/obj/structure/window/run_atom_armor(damage_amount, damage_type, damage_flag, attack_dir, armour_penetration)
	. = ..()
	if(silicate && .)
		. = . * (1 - silicate / 200)

// Glass-on-glass sound rather than the default smash.
/obj/structure/window/play_attack_sound(damage_amount, damage_type, damage_flag)
	play_sfx(src, SFX_EFFECTS_GLASSHIT, volume = 100)

// Crack visuals / warnings as integrity drops past thresholds.
/obj/structure/window/on_update_integrity(old_value, new_value)
	. = ..()
	update_icon()

/obj/structure/window/atom_destruction(damage_flag)
	shatter()
	return ..()

/obj/structure/window/proc/apply_silicate(amount)
	if(get_integrity() < max_integrity) // Mend the damage
		repair_damage(amount * 3)
		if(get_integrity() >= max_integrity)
			visible_message("[src] looks fully repaired." )
	else // Reinforce
		silicate = min(silicate + amount, 100)
		updateSilicate()

/obj/structure/window/proc/updateSilicate()
	cut_overlays()
	update_icon()

	var/image/img = image(src)
	img.color = "#ffffff"
	img.alpha = silicate * 255 / 100
	add_overlay(img)

/obj/structure/window/proc/shatter(display_message = 1)
	play_sfx(src, SFX_SHATTER)
	if(display_message)
		visible_message("[src] shatters!")
	if(reinf)
		new /obj/item/stack/rods(loc)
	if(is_fulltile())
		new shardtype(loc) //todo pooling?
		if(reinf)
			new /obj/item/stack/rods(loc)
	replace_with(src, shardtype)
	return

/obj/structure/window/proc/can_glasspassers_pass()
	PROTECTED_PROC(TRUE)
	return TRUE

/obj/structure/window/can_pathfinding_enter(atom/movable/actor, dir, datum/pathfinding/search)
	return ..() || (!fulltile && (src.dir) != dir)

/obj/structure/window/can_pathfinding_exit(atom/movable/actor, dir, datum/pathfinding/search)
	return ..() || (!fulltile && (src.dir != dir))

/obj/structure/window/CanPass(atom/movable/mover, turf/target)
	if(istype(mover) && mover.checkpass(PASSGLASS))
		return can_glasspassers_pass()
	if(is_fulltile())
		return FALSE	//full tile window, you can't move into it!
	if(get_dir(mover, target) == GLOB.reverse_dir[dir]) // From elsewhere to here, can't move against our dir
		return !density
	else
		return TRUE

/obj/structure/window/Uncross(atom/movable/mover, turf/target)
	if(istype(mover) && mover.checkpass(PASSGLASS))
		return TRUE
	if(get_dir(mover, target) == dir) // From here to elsewhere, can't move in our dir
		return !density
	else
		return TRUE

/obj/structure/window/CanZASPass(turf/T, is_zone)
	if(is_fulltile() || get_dir(T, loc) == turn(dir, 180)) // Make sure we're handling the border correctly.
		return !anchored // If it's anchored, it'll block air.
	return TRUE // Don't stop airflow from the other sides.

/obj/structure/window/hitby(atom/movable/source, datum/thrownthing/throwingdatum)
	visible_message(span_danger("[src] was hit by [source]."))
	if(!reinf && get_integrity() - source.thrown_impact_force(throwingdatum) <= 7)
		set_anchored(FALSE)
		update_verbs()
		update_nearby_icons()
		step(src, get_dir(source, src))
	..()

/obj/structure/window/thrown_damage(atom/movable/source, datum/thrownthing/throwingdatum)
	return receive_thrown(source, throwingdatum, reinf ? 0.25 : 1)

/// Old attack_tk: knock on the window at range.
/obj/structure/window/proc/interaction_tk(mob/user, obj/item/held, datum/interaction/interaction)
	user.visible_message(span_notice("Something knocks on [src]."))
	play_sfx(src, SFX_EFFECTS_GLASSHIT, volume = 50)
	return TRUE

EXTEND_INTERACTIONS(/obj/structure/window, \
	INTERACT_HAND_AS(I_HURT, "Bang on", PROC_REF(interaction_bang)), \
	INTERACT_HAND("Knock", PROC_REF(interaction_hand)), \
	INTERACT_ITEM("Use", PROC_REF(interaction_item)), \
	INTERACT_TK("Knock", PROC_REF(interaction_tk)), \
)

/obj/structure/window/proc/interaction_bang(mob/user, obj/item/held, datum/interaction/interaction)
	if(user.has_mutation(HULK))
		return FALSE // a Hulk smashes through: interaction_hand()
	user.setClickCooldown(user.get_attack_speed())
	if(ishuman(user))
		var/mob/living/carbon/human/H = user
		var/shreddamage = H.species.can_shred(H, FALSE, 15)
		if(shreddamage)
			generic_hit(src, H, shreddamage + 5, "attacks")
			return TRUE

	play_sfx(src, SFX_EFFECTS_GLASSKNOCK)
	user.do_attack_animation(src)
	act_message(user, src, MSG_SELF(span_danger("You bang against %T%!")), \
		MSG_OTHERS(span_danger("%U% bangs against %T%!")), \
		MSG_BLIND("You hear a banging sound."))
	return TRUE

/obj/structure/window/proc/interaction_hand(mob/user, obj/item/held, datum/interaction/interaction)
	user.setClickCooldown(user.get_attack_speed())
	if(user.has_mutation(HULK))
		user.say(pick(";RAAAAAAAARGH!", ";HNNNNNNNNNGGGGGGH!", ";GWAAAAAAAARRRHHH!", "NNNNNNNNGGGGGGGGHH!", ";AAAAAAARRRGH!"))
		act_message(user, src, others = span_danger("%U% smashes through %T%!"))
		user.do_attack_animation(src)
		shatter()
	else
		play_sfx(src, SFX_EFFECTS_GLASSKNOCK)
		act_message(user, null, MSG_SELF("You knock on the [src.name]."), \
			MSG_OTHERS("[user.name] knocks on the [src.name]."), \
			MSG_BLIND("You hear a knocking sound."))
	return TRUE

/obj/structure/window/attack_generic(mob/user, damage)
	user.setClickCooldown(user.get_attack_speed())
	if(!damage)
		return
	if(damage >= STRUCTURE_MIN_DAMAGE_THRESHOLD)
		act_message(user, src, others = span_danger("%U% smashes into %T%!"))
		if(reinf)
			damage = damage / 2
		receive_generic_attack(user, damage)
	else
		act_message(user, src, others = span_infoplain(span_bold("%U%") + " bonks %T% harmlessly."))
	user.do_attack_animation(src)
	return 1

/obj/structure/window/proc/interaction_item(mob/user, obj/item/W, datum/interaction/interaction)
	// Slamming.
	if (istype(W, /obj/item/grab) && get_dist(src,user)<2)
		var/obj/item/grab/G = W
		if(isliving(G?.grab_target()))
			var/mob/living/M = G?.grab_target()
			var/state = G.state
			consumed(W, src)	//gotta delete it here because if window breaks, it won't get deleted
			switch (state)
				if(1)
					act_message(user, M, others = span_warning("%U% slams %T% against \the [src]!"))
					M.injure(INJURY_BLUNT, 7, null, src)
					hit(10)
				if(2)
					act_message(user, M, others = span_danger("%U% bashes %T% against \the [src]!"))
					if (prob(50))
						M.status_at_least(STAT_WEAKENED, 1)
					M.injure(INJURY_BLUNT, 10, null, src)
					hit(25)
				if(3)
					act_message(M, user, others = span_danger("<big>%T% crushes %U% against \the [src]!</big>"))
					M.status_at_least(STAT_WEAKENED, 5)
					M.injure(INJURY_BLUNT, 20, null, src)
					hit(50)
			return TRUE

	if(W.flags & NOBLUDGEON) return TRUE

	if(istype(W, /obj/item/stack/cable_coil) && reinf && state == 0 && !istype(src, /obj/structure/window/reinforced/polarized))
		var/obj/item/stack/cable_coil/C = W
		if (C.use(1))
			play_sfx(src, SFX_EFFECTS_SPARKS1, 0.75)
			act_message(user, src, MSG_SELF(span_notice("You begin to wire %T% for electrochromic tinting.")), \
				MSG_OTHERS(span_infoplain(span_bold("%U%") + " begins to wire %T% for electrochromic tinting.")), \
				MSG_BLIND("You hear sparks."))
			use_tool(user, C, src, delay = 2 SECONDS, receiver = src, on_done = PROC_REF(attackby_tool_done), done_args = list(state))
	else if(istype(W,/obj/item/frame) && anchored)
		return TRUE // its own op, frame.mount, hangs it on the window
	else
		user.setClickCooldown(user.get_attack_speed(W))
		if(W.obj_damage_type())
			user.do_attack_animation(src)
			hit(W.force)
			if(get_integrity() <= 7)
				set_anchored(FALSE)
				update_nearby_icons()
				step(src, get_dir(user, src))
		else
			play_sfx(src, SFX_EFFECTS_GLASSHIT)
	return TRUE

/obj/structure/window/proc/attackby_tool_done(state)
	if(!(state == 0))
		return
	play_sfx(src, SFX_ITEMS_DECONSTRUCT)
	var/obj/structure/window/reinforced/polarized/P = new(loc, dir)
	if(is_fulltile())
		P.fulltile = TRUE
		P.icon_state = "fwindow"
	P.max_integrity = max_integrity
	P.update_integrity(get_integrity())
	P.state = state
	P.set_anchored(anchored)
	replace_with(src, P)

// Tool steps and weld repair: window_construction.dm.

/obj/structure/window/proc/hit(damage, sound_effect = 1)
	if(damage < force_threshold || force_threshold < 0)
		return
	if(reinf) damage *= 0.5
	take_damage(damage, BRUTE, MELEE)
	return

/obj/structure/window/handle_rotation_verbs(angle, mob/user)
	if(is_fulltile())
		return FALSE
	update_nearby_tiles(need_rebuild=1) //Compel updates before
	. = ..()
	if(.)
		updateSilicate()
		update_nearby_tiles(need_rebuild=1)

CAPABILITIES(/obj/structure/window)
	smoothing()
	param(nameof(dir), pos = 1)
	param(nameof(constructed), pos = 2)

/// A window a player built (its constructor param).
/obj/structure/window/var/constructed = FALSE

// ALLOW(init/INSTANCE_STATE): a window insulates, starts loose when built, turns, and updates its tiles and the tables beside it
/obj/structure/window/Initialize(mapload)
	. = ..()
	update_rad_insulation()

	//player-constructed windows
	if (constructed)
		set_anchored(FALSE)
		state = 0

	// If we started anchored we'll need to disable rotation
	make_rotatable()
	update_verbs()

	ini_dir = dir

	update_nearby_tiles(need_rebuild=1)
	update_nearby_icons()

// neighbouring windows and tables re-smooth without it.
/obj/structure/window/on_destroy(force)
	set_density(FALSE)
	update_nearby_tiles()
	var/turf/location = loc
	..()
	for(var/obj/structure/window/W in orange(location, 1))
		W.update_icon()

/obj/structure/window/Move()
	var/ini_dir = dir
	var/turf/location = loc
	update_nearby_tiles(need_rebuild=1)
	. = ..()
	set_dir(ini_dir)
	update_nearby_tiles(need_rebuild=1)

//checks if this window is full-tile one
/obj/structure/window/proc/is_fulltile()
	return fulltile

/obj/structure/window/is_between_turfs(turf/origin, turf/target)
	if(is_fulltile())
		return TRUE
	return ..()

//This proc is used to update the icons of nearby windows. It should not be confused with update_nearby_tiles(), which is an atmos proc!
/obj/structure/window/proc/update_nearby_icons()
	update_icon()
	for(var/obj/structure/window/W in orange(src, 1))
		W.update_icon()

//Updates the availabiliy of the rotation verbs
/obj/structure/window/proc/update_verbs()
	if(anchored || is_fulltile())
		revoke(src, granted_verb(/atom/movable/proc/rotate_counterclockwise), src)
		revoke(src, granted_verb(/atom/movable/proc/rotate_clockwise), src)
		revoke(src, granted_verb(/atom/movable/proc/turn_around), src)
	else if(!is_fulltile())
		grant(src, granted_verb(/atom/movable/proc/rotate_counterclockwise), src)
		grant(src, granted_verb(/atom/movable/proc/rotate_clockwise), src)
		grant(src, granted_verb(/atom/movable/proc/turn_around), src)

//merges adjacent full-tile windows into one (blatant ripoff from game/smoothwall.dm)
DECLARE_APPEARANCE_PROC(/obj/structure/window, TYPE_PROC_REF(/atom, appearance_overlays), list("get_integrity"))
/obj/structure/window/appearance_overlays()
	. = list()
	//A little cludge here, since I don't know how it will work with slim windows. Most likely VERY wrong.
	//this way it will only update full-tile ones
	if(!is_fulltile())
		// Rotate the sprite somewhat so non-fulltiled windows can be seen as needing repair.
		var/full_tilt_degrees = 15
		var/tilt_to_apply = abs((get_integrity() / max_integrity) - 1)
		if(tilt_to_apply && prob(50))
			tilt_to_apply = -tilt_to_apply
		adjust_rotation(LERP(0, full_tilt_degrees, tilt_to_apply))

		icon_state = "[basestate]"
		return .
	else
		flags &= ~ON_BORDER // Removes ON_BORDER
	var/list/dirs = list()
	if(anchored)
		for(var/obj/structure/window/W in orange(src,1))
			if(W.anchored && W.density && W.glasstype == src.glasstype && W.is_fulltile()) //Only counts anchored, not-destroyed fill-tile windows.
				dirs += get_dir(src, W)

	icon_state = ""
	. += window_overlay_images(dirs_to_corner_states(dirs))

/// The overlay images for a full-tile window in this state (doc/rewrite/init_and_turfs.md sec 3.5):
/// built once per (icon, basestate, corner connections, damage step, layer) and shared by every
/// window in that state. Read-only: callers pass it to add_overlay(), which copies.
/obj/structure/window/proc/window_overlay_images(list/connections)
	var/ratio = CEILING((get_integrity() / max_integrity) * 4, 1) * 25
	var/step = ratio > 75 ? 100 : ratio
	return CACHED_KEY(window_overlay_sets, "[icon]|[basestate]|[connections.Join(",")]|[step]|[layer]", icon, basestate, connections, step, layer)

DECLARE_SHARED_CACHE(window_overlay_sets, GLOBAL_PROC_REF(build_window_overlay_sets), SC_NEVER)

/// Builder for window_overlay_sets.
/proc/build_window_overlay_sets(icon, basestate, list/connections, ratio, layer)
	var/list/images = list()
	for(var/i = 1 to 4)
		images += image(icon, "[basestate][connections[i]]", dir = 1<<(i-1))
	// Damage overlays.
	if(ratio <= 75)
		images += image(icon, "damage[ratio]", layer = layer + 0.1)
	return images

/obj/structure/window/basic
	desc = "It looks thin and flimsy. A few knocks with... almost anything, really should shatter it."
	icon_state = "window"
	basestate = "window"
	glasstype = /obj/item/stack/material/glass
	maximal_heat = T0C + 100
	damage_per_fire_tick = 2.0
	max_integrity = 12.0
	force_threshold = 3

/obj/structure/window/basic/full
	icon_state = "window-full"
	max_integrity = 24
	fulltile = TRUE
	flags = NONE

/obj/structure/window/phoronbasic
	name = "phoron window"
	desc = "A borosilicate alloy window. It seems to be quite strong."
	basestate = "phoronwindow"
	icon_state = "phoronwindow"
	shardtype = /obj/item/material/shard/phoron
	glasstype = /obj/item/stack/material/glass/phoronglass
	maximal_heat = T0C + 2000
	damage_per_fire_tick = 1.0
	max_integrity = 40.0
	force_threshold = 5

/obj/structure/window/phoronbasic/full
	icon_state = "phoronwindow-full"
	max_integrity = 80
	fulltile = TRUE
	flags = NONE

/obj/structure/window/phoronreinforced
	name = "reinforced borosilicate window"
	desc = "A borosilicate alloy window, with rods supporting it. It seems to be very strong."
	basestate = "phoronrwindow"
	icon_state = "phoronrwindow"
	shardtype = /obj/item/material/shard/phoron
	glasstype = /obj/item/stack/material/glass/phoronrglass
	reinf = 1
	maximal_heat = T0C + 4000
	damage_per_fire_tick = 1.0 // This should last for 80 fire ticks if the window is not damaged at all. The idea is that borosilicate windows have something like ablative layer that protects them for a while.
	max_integrity = 80.0
	force_threshold = 10

/obj/structure/window/phoronreinforced/full
	icon_state = "phoronrwindow-full"
	max_integrity = 160
	fulltile = TRUE
	flags = NONE

/obj/structure/window/reinforced
	name = "reinforced window"
	desc = "It looks rather strong. Might take a few good hits to shatter it."
	icon_state = "rwindow"
	basestate = "rwindow"
	max_integrity = 40.0
	reinf = 1
	maximal_heat = T0C + 750
	damage_per_fire_tick = 2.0
	glasstype = /obj/item/stack/material/glass/reinforced
	force_threshold = 6

/obj/structure/window/reinforced/full
	icon_state = "rwindow-full"
	max_integrity = 80
	fulltile = TRUE
	flags = NONE

/obj/structure/window/reinforced/tinted
	name = "tinted window"
	desc = "It looks rather strong and opaque. Might take a few good hits to shatter it."
	icon_state = "twindow"
	basestate = "twindow"
	opacity = 1

/obj/structure/window/reinforced/tinted/frosted
	name = "frosted window"
	desc = "It looks rather strong and frosted over. Looks like it might take a few less hits then a normal reinforced window."
	icon_state = "fwindow"
	basestate = "fwindow"
	max_integrity = 30
	force_threshold = 5

/obj/structure/window/shuttle
	name = "shuttle window"
	desc = "It looks rather strong. Might take a few good hits to shatter it."
	icon = 'icons/obj/podwindows.dmi'
	icon_state = "window"
	basestate = "window"
	max_integrity = 40
	reinf = 1
	basestate = "w"
	dir = 5
	force_threshold = 7

/obj/structure/window/reinforced/polarized
	name = "electrochromic window"
	desc = "Adjusts its tint with voltage. Might take a few good hits to shatter it."
	var/id

/obj/structure/window/reinforced/polarized/full
	icon_state = "rwindow-full"
	max_integrity = 80
	fulltile = TRUE
	flags = NONE

/obj/structure/window/reinforced/polarized/can_glasspassers_pass()
	// If the windows are currently tinted, they're blocking light from passing.
	// So, they should block stuff like lasers at that time.
	return opacity

/obj/structure/window/reinforced/polarized/proc/window_id_entered(datum/act/request/A)
	if(!A.answer)
		return
	var/mob/user = A.request.answerer
	var/t = sanitizeSafe(A.answer.value, MAX_NAME_LEN)
	if(t)
		src.id = t
		to_chat(user, span_notice("The new ID of \the [src] is '[id]'."))

/// Overrides window's interaction_item(): a multitool programs the tint ID while unanchored.
/obj/structure/window/reinforced/polarized/interaction_item(mob/user, obj/item/W, datum/interaction/interaction)
	var/obj/item/multitool/MT = W.get_multitool()
	if(MT && !anchored) // Only allow programming if unanchored!
		// First check if they have a windowtint button buffered
		if(istype(MT.connectable(), /obj/machinery/button/windowtint))
			var/obj/machinery/button/windowtint/buffered_button = MT.connectable()
			src.id = buffered_button.id
			to_chat(user, span_notice("\The [src] is linked to \the [buffered_button] with ID '[id]'."))
			return TRUE
		// Otherwise fall back to asking them... and remind them what the current ID is.
		if(id)
			to_chat(user, "The window's current ID is [id].")
		open_request(src, /datum/prompt/text, PROC_REF(window_id_entered), answerer = user, title = name, question = "Enter the new ID for the window.", default = id, encode = FALSE, ask_flags = ASK_NEAR_SUBJECT | ASK_CAPABLE, timeout = 0)
		return TRUE
	return ..()

/obj/structure/window/reinforced/polarized/proc/toggle()
	if(opacity)
		animate(src, color="#FFFFFF", time=5)
		set_opacity(0)
	else
		animate(src, color="#222222", time=5)
		set_opacity(1)
	var/turf/T = get_turf(src)
	T.recalculate_directional_opacity()

/obj/machinery/button/windowtint
	maintenance_flags = MACHINE_MAINT_PANEL
	name = "window tint control"
	icon = 'icons/obj/stationobjs.dmi'
	icon_state = "light0"
	desc = "A remote control switch for polarized windows."
	circuit = /obj/item/circuitboard/electrochromic
	flags = WALL_ITEM
	var/range = 7

/obj/machinery/button/windowtint/declare_interactions(list/into)
	into += list(
		/datum/interaction/machine_hand/windowtint_toggle,
	)
	..()

/datum/interaction/machine_hand/windowtint_toggle
	id = "windowtint_toggle"
	name = "Toggle"
	effect = /obj/machinery/button/windowtint/proc/interaction_toggle

/obj/machinery/button/windowtint/proc/interaction_toggle(mob/user, obj/item/held, datum/interaction/interaction)
	toggle_tint()
	return TRUE

/obj/machinery/button/windowtint/proc/toggle_tint()
	use_power(5)

	set_active(!active)

	for(var/obj/structure/window/reinforced/polarized/W in range(src,range))
		if (W.id == src.id || !W.id)
			W.toggle()

/obj/machinery/button/windowtint/power_change()
	. = ..()
	if(active && !powered(power_channel))
		toggle_tint()

/// The look (the draw sweep: from its template).
/obj/machinery/button/windowtint/draw(datum/look/look)
	..()
	look.state("light[active]")

/obj/machinery/button/windowtint/multitool_act(mob/user, obj/item/tool)
	var/obj/item/multitool/multitool = tool
	if(!id)
		open_request(src, /datum/prompt/text, PROC_REF(button_id_entered), valid = PROC_REF(button_id_valid), answerer = user, subject = tool, ask_flags = ASK_HELD | ASK_CAPABLE, title = name, question = "Enter an ID for \the [src].", max_len = MAX_NAME_LEN, name_text = TRUE, encode = FALSE, timeout = 0)
		return ITEM_INTERACT_SUCCESS
	store_in_multitool(user, multitool)
	return ITEM_INTERACT_SUCCESS

/// Setting a tint button's ID with a multitool (the subject, held throughout); the button stays next to them and unset.
/obj/machinery/button/windowtint/proc/button_id_valid(datum/request/R)
	var/mob/M = R.answerer
	return !id && istype(M) && Adjacent(M)

/obj/machinery/button/windowtint/proc/button_id_entered(datum/act/request/A)
	if(!A.answer)
		return
	var/mob/user = A.request.answerer
	var/new_id = sanitizeSafe(A.answer.value, MAX_NAME_LEN)
	if(new_id)
		id = new_id
		to_chat(user, span_notice("The new ID of \the [src] is '[id]'. To reset this, rebuild the control."))
		store_in_multitool(user, user.get_active_hand())

/obj/machinery/button/windowtint/proc/store_in_multitool(mob/user, obj/item/multitool/multitool)
	if(id && istype(multitool))
		to_chat(user, span_notice("You store \the [src] ID ('[id]') in \the [multitool]'s buffer!"))
		rel_set(multitool, nameof(multitool.connectable), src)

MSG_DEF(windowtint/wires_cut, "You have cut the wires inside %T%.", "%U% has cut the wires inside %T%!")

CAPABILITIES(/obj/machinery/button/windowtint)
	op("use_wirecutter", tool(TOOL_WIRECUTTER), label("Cut the wires"), wait(0), says(MSG(windowtint/wires_cut)), then(PROC_REF(wires_cut)))

/// The cutters through an open panel: the wires come out and the button comes off the wall.
/obj/machinery/button/windowtint/proc/wires_cut(datum/act/op/A)
	var/obj/item/tool = A.held
	if(!panel_open)
		return OP_DECLINE // a shut panel: the cutters go on to the legacy tool handling, as before
	playsound(src, tool.usesound, 50, TRUE)
	new /obj/item/stack/cable_coil(get_turf(src), 5)
	dismantle()
	return OP_OK

/* moved this block to code\game\objects\items\weapons\rcd.dm
/obj/structure/window/rcd_values(mob/living/user, obj/item/rcd/the_rcd, passed_mode)
	switch(passed_mode)
		if(RCD_DECONSTRUCT)
			return rcd_value_entry(RCD_DECONSTRUCT, 5 SECONDS, RCD_SHEETS_PER_MATTER_UNIT * 5)

/obj/structure/window/rcd_act(mob/living/user, obj/item/rcd/the_rcd, passed_mode)
	switch(passed_mode)
		if(RCD_DECONSTRUCT)
			to_chat(user, span_notice("You deconstruct \the [src]."))
			spent(src, user)
			return TRUE
	return FALSE
*/

// === merged from window_vr.dm during hard-fork de-suffix (verified no override-order change) ===
/obj/structure/window/titanium
	name = "ti-glass window"
	desc = "A titanium alloy window, combining the strength of titanium with the transparency of glass. It seems to be very strong."
	basestate = "window"
	icon_state = "window"
	color = "#A7A3A6"
	shardtype = /obj/item/material/shard/titaniumglass
	glasstype = /obj/item/stack/material/glass/titanium
	reinf = 0
	maximal_heat = T0C + 5000
	damage_per_fire_tick = 1.0
	max_integrity = 100.0
	force_threshold = 10

/obj/structure/window/titanium/full
	icon_state = "window-full"
	max_integrity = 200
	fulltile = TRUE

/obj/structure/window/plastitanium
	name = "plastanium glass window"
	desc = "A plastitanium alloy window, combining the strength of plastitanium with the transparency of glass. It seems to be very strong."
	basestate = "window"
	icon_state = "window"
	color = "#676366"
	shardtype = /obj/item/material/shard/plastitaniumglass
	glasstype = /obj/item/stack/material/glass/plastitanium
	reinf = 0
	maximal_heat = T0C + 7000
	damage_per_fire_tick = 1.0
	max_integrity = 120.0
	force_threshold = 10

/obj/structure/window/plastitanium/full
	icon_state = "window-full"
	max_integrity = 250
	fulltile = TRUE

/obj/structure/window/reinforced/tinted/full
	icon_state = "window-full"
	fulltile = TRUE

/// Window shielding derives from its glass (the glasstype stack's material).
/obj/structure/window/proc/update_rad_insulation()
	var/obj/item/stack/material/stack_type = glasstype
	var/material_id = stack_type ? initial(stack_type.default_type) : MAT_GLASS
	set_rad_insulation(material_rad_insulation(material_id, is_fulltile() ? RAD_FULLTILE_WINDOW_THICKNESS_MM : RAD_WINDOW_THICKNESS_MM, RAD_VERY_LIGHT_INSULATION))
