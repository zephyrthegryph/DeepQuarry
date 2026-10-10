// Tables, benches and racks (phase 2, furniture). A table is declared: ONE CAPABILITIES list says what it is, a build ladder (a frame, its plating,
// its reinforcement, and the wrench that takes the frame down) with the carpet, the repair, the flip and the ways to put things on it as ops of its own.
// What stays imperative is the table's own: the connected-tile smoothing and look, the cover check for projectiles, the break into parts, and the
// conditions and effects the declarations name.
//
// The plating and the reinforcement are the build graph's: a table is "plated with M" when the graph has passed STAGE_TABLE_PLATED and the ledger says it
// took a sheet of M there (material(), reinforced()). A preset table (steel, wooden, reinforced, a bench or a rack) starts built with its layers, which
// set_layers() writes into the graph as if somebody had built it from a sheet of each material, so taking a layer off gives the sheet back either way.

DECLARE_SHARED_CACHE_EX(table_icon, GLOBAL_PROC_REF(build_table_icon), SC_NEVER, 2048, 0)

/obj/structure/table
	name = "table frame"
	icon = 'icons/obj/tables.dmi'
	icon_state = "frame"
	desc = "It's a table, for putting things on. Or standing on, if you really want to."
	density = TRUE
	anchored = TRUE
	layer = TABLE_LAYER
	throwpass = 1
	surgery_cleanliness = 50
	/// 0: standing; 1: flipped on its side; -1: a kind that is never flipped or stood on (a rack, a bench).
	var/flipped = 0
	max_integrity = 10

	// For racks.
	var/can_reinforce = 1
	var/can_plate = 1
	/// FALSE on the tables nobody can take apart: the alien, dark glass and fancy tables, the pod table, a holo rack.
	var/can_dismantle = TRUE

	/// A preset's layers: the id of the material it starts plated with, and the one it starts reinforced with (null: none).
	var/plating_id
	var/reinforcement_id

	/// Transient hand-off: shards produced by the most recent break_to_parts(), read
	/// by callers (e.g. tableslam) that previously consumed take_damage()'s return.
	var/list/last_break_shards

	// Gambling tables. I'd prefer reinforced with carpet/felt/cloth/whatever, but AFAIK it's either harder or impossible to get /obj/item/stack/material of those.
	// Convert if/when you can easily get stacks of these.
	var/carpeted = 0
	var/carpeted_type = /obj/item/stack/tile/carpet

TRACKED(/obj/structure/table, flipped)
TRACKED(/obj/structure/table, carpeted)

STAGE_DEF(table, frame)
STAGE_DEF(table, plated)
STAGE_DEF(table, reinforced)

MSG_DEF_SELF(stage/table/frame, "It is a bare frame.")
MSG_DEF_SELF(stage/table/plated, "It is plated.")
MSG_DEF_SELF(stage/table/reinforced, "It is plated and reinforced.")

MSG_DEF_SELF(table/needs_plating, "There's nothing to put that on! Try adding plating to the table first.")
MSG_DEF_SELF(table/put_back_first, "Put the table back in place before reinforcing it!")
MSG_DEF_SELF(table/already_reinforced, "The table is already reinforced!")
MSG_DEF_SELF(table/plate_first, "Plate the table before reinforcing it!")
MSG_DEF_SELF(table/not_reinforceable, "The table cannot be reinforced!")
MSG_DEF_SELF(table/plating_stuck, "You are unable to remove the plating from this table!")
MSG_DEF_SELF(table/reinforcement_stuck, "You are unable to remove the reinforcements from this table!")
MSG_DEF_SELF(table/carpet_on, "Take the carpet off first.")
MSG_DEF_SELF(table/no_dismantle, "You cannot dismantle that.")
MSG_DEF_SELF(table/hands_busy, "You need your hands and legs free for this.")
MSG_DEF_SELF(table/wont_budge, "It won't budge.")
MSG_DEF_SELF(table/in_the_way, "There's something in the way.")
MSG_DEF_SELF(table/better_grip, "You need a better grip to do that!")
MSG_DEF_SELF(table/not_in_hand, "You aren't holding that.")
MSG_DEF(table/flipped, "You flip %T%!", "%U% flips %T%!")
MSG_DEF(table/put_back, "You put %T% back on its legs.", "%U% puts %T% back on its legs.")
MSG_DEF(table/carpeted, "You add %I% to %T%.", "%U% adds %I% to %T%.")
MSG_DEF(table/uncarpeted, "You remove the carpet from %T%.", "%U% removes the carpet from %T%.")
MSG_DEF(table/repaired, "You repair some damage to %T%.", "%U% repairs some damage to %T%.")

CAPABILITIES(/obj/structure/table)
	smoothing()
	table_frame()
	climb(landing = PROC_REF(flipped_landing))
	extend("construction.dismantle", when(req_graph_at(list(STAGE_TABLE_FRAME))), needs(req(PROC_REF(dismantle_allowed))))
	extend("construction.build:table_reinforced", priority(above("place_dragged")))
	op("repair", tool(TOOL_WELDER), wait(2 SECONDS), label("Repair"), when(PROC_REF(is_damaged)),
		then(PROC_REF(repaired)), says(MSG(table/repaired)))
	op("carpet", stack(/obj/item/stack/tile/carpet, 1), wait(0), label("Carpet"), when(req(PROC_REF(can_carpet))),
		then(PROC_REF(carpet_laid)), says(MSG(table/carpeted)))
	op("uncarpet", tool(TOOL_CROWBAR), wait(0), label("Remove carpet"), when(nameof(carpeted)),
		then(PROC_REF(carpet_lifted)), says(MSG(table/uncarpeted)))
	op("flip", menu(), label("Flip table"), when(req(PROC_REF(is_flippable))),
		needs(req(PROC_REF(actor_can_flip)), req(PROC_REF(can_flip_away))),
		then(PROC_REF(flip_over)), says(MSG(table/flipped)))
	op("put_back", menu(), label("Put table back"), when(req(PROC_REF(is_flipped_up))),
		needs(req(PROC_REF(actor_can_flip)), req(PROC_REF(can_put_back))),
		then(PROC_REF(put_back)), says(MSG(table/put_back)))
	op("slice_blade", item(/obj/item/melee/energy/blade), then(PROC_REF(sliced_apart)))
	op("slice_arm_blade", item(/obj/item/melee/changeling/arm_blade), then(PROC_REF(sliced_apart)))
	op("claw", hand(), when(req(PROC_REF(actor_is_xeno))), then(PROC_REF(clawed_apart)))
	op("slam", item(/obj/item/grab), hostile(), label("Slam against table"), when(req(PROC_REF(slam_applies))), then(PROC_REF(slam_face)))
	op("put_on", item(/obj/item/grab), label("Put on table"), when(req(PROC_REF(person_grabbed))),
		needs(req(PROC_REF(person_can_go_on))), then(PROC_REF(put_person_on)))
	op("place", item(/obj/item), label("Place"), priority(OP_PRIORITY_NORMAL - 5), answers(INTENT_USE, INTENT_ATTACK),
		needs(req(PROC_REF(has_surface)), req(PROC_REF(held_is_carried))),
		then(PROC_REF(place_held)))
	op("place_dragged", item(/obj/item), gesture(GESTURE_DRAG), label("Place"),
		needs(req(PROC_REF(reinforce_refusal))), then(PROC_REF(place_dragged)))
	on_op("construction.build:table_plated", then(PROC_REF(layers_changed)))
	on_op("construction.build:table_reinforced", then(PROC_REF(layers_changed)))
	on_op("construction.undo:table_plated", then(PROC_REF(layers_changed)))
	on_op("construction.undo:table_reinforced", then(PROC_REF(layers_changed)))

/// The build ladder of a table: a bare frame, a sheet of any material for the plating (the wrench takes it off again), a second sheet dragged on for the
/// reinforcement (the screwdriver takes it off, slowly), and the wrench that takes a bare frame down into a sheet of steel. The ledger refunds the sheets
/// the layers took, the same material that went on.
/proc/table_frame()
	return construction(start(STAGE_TABLE_FRAME), \
		stage(STAGE_TABLE_PLATED, stack(/obj/item/stack/material, 1), wait(2 SECONDS), \
			when(TYPE_PROC_REF(/obj/structure/table, plating_open)), \
			undo = list(tool(TOOL_WRENCH), wait(2 SECONDS), \
				needs(req(TYPE_PROC_REF(/obj/structure/table, carpet_off)), \
					req(TYPE_PROC_REF(/obj/structure/table, plating_removable))))), \
		stage(STAGE_TABLE_REINFORCED, stack(/obj/item/stack/material, 1), gesture(GESTURE_DRAG), wait(2 SECONDS), \
			when(TYPE_PROC_REF(/obj/structure/table, reinforcement_open)), \
			needs(req(TYPE_PROC_REF(/obj/structure/table, standing_up))), \
			undo = list(tool(TOOL_SCREWDRIVER), wait(4 SECONDS), \
				needs(req(TYPE_PROC_REF(/obj/structure/table, reinforcement_removable))))), \
		dismantle(tool(TOOL_WRENCH), wait(2 SECONDS), becomes(/obj/item/stack/material/steel)))

// ---- the layers ----

/// The material the table is plated with (a shared definition, never cleared), or null for a bare frame.
/obj/structure/table/proc/material() as /datum/material
	return built_material(src, STAGE_TABLE_PLATED)

/// The material the table is reinforced with, or null.
/obj/structure/table/proc/reinforced() as /datum/material
	return built_material(src, STAGE_TABLE_REINFORCED)

/// The ledger entry of a sheet of `M` put on by hand: what taking the layer off gives back.
/proc/table_sheet_ledger(datum/material/M)
	if(!M)
		return list()
	return list("material" = M, "rows" = M.stack_type ? list(list("res" = RES_STACK, "n" = 1, "type" = M.stack_type, "material" = M)) : list())

/**
 * Builds the table as it stands with `plating` and `reinforcement` (materials; null for none) without anyone building it: a preset at map load, a
 * cultified table, a dimension theme. The graph is put at the frame and then walked up with a ledger of one sheet of each material, so the layers come
 * off and give the sheet back whoever put them on. Does not redraw (the caller does).
 */
/obj/structure/table/proc/set_layers(datum/material/plating, datum/material/reinforcement)
	graph_place(src, STAGE_TABLE_FRAME)
	if(plating)
		graph_advance(src, STAGE_TABLE_PLATED, null, table_sheet_ledger(plating))
		if(reinforcement)
			graph_advance(src, STAGE_TABLE_REINFORCED, null, table_sheet_ledger(reinforcement))

/// Redraws and renames the table and its neighbours, and sets its strength for what it is made of now.
/obj/structure/table/proc/refresh_layers()
	update_connections(TRUE)
	update_desc()
	update_material()

/// A layer went on or came off (the build ladder's hook).
/obj/structure/table/proc/layers_changed(datum/act/notice/A)
	refresh_layers()

/// The conditions of the ladder. Plating is open to a bare table that can be plated; reinforcing to a kind that can be (the stage itself says plated).
/obj/structure/table/proc/plating_open(datum/act/A)
	return can_plate

/obj/structure/table/proc/reinforcement_open(datum/act/A)
	return can_reinforce

/obj/structure/table/proc/standing_up(datum/act/A)
	return (flipped != 1) ? null : /datum/msg/table/put_back_first

/// Taking the plating or the reinforcement off needs a sheet to give back.
/obj/structure/table/proc/plating_removable(datum/act/A)
	var/datum/material/M = material()
	return (!!M?.stack_type) ? null : /datum/msg/table/plating_stuck

/obj/structure/table/proc/carpet_off(datum/act/A)
	return (!carpeted) ? null : /datum/msg/table/carpet_on

/obj/structure/table/proc/reinforcement_removable(datum/act/A)
	var/datum/material/M = reinforced()
	return (!!M?.stack_type) ? null : /datum/msg/table/reinforcement_stuck

/obj/structure/table/proc/dismantle_allowed(datum/act/A)
	return (can_dismantle) ? null : /datum/msg/table/no_dismantle

/// The table has a surface to put things on: a plated one, or a kind that never is.
/obj/structure/table/proc/has_surface(datum/act/A)
	return (!can_plate || !!material()) ? null : MSG(table/needs_plating)

/// The strength of the table follows what it is made of.
/obj/structure/table/proc/update_material()
	var/old_max = max_integrity
	if(!material())
		max_integrity = 10
	else
		max_integrity = material().integrity / 2

		if(reinforced())
			max_integrity += reinforced().integrity / 2

	// Preserve absolute damage accrued so far when the max changes (mirrors the old
	// `health += maxhealth - old_maxhealth` behaviour).
	update_integrity(get_integrity() + (max_integrity - old_max))

/obj/structure/table/proc/update_desc()
	if(material())
		name = "[plating_display()] table"
	else
		name = "table frame"

	if(reinforced())
		name = "reinforced [name]"
		desc = "[initial(desc)] This one seems to be reinforced with [reinforced().display_name]."
	else
		desc = initial(desc)

// ---- the carpet and the repair ----

/obj/structure/table/proc/can_carpet(datum/act/A)
	return (!carpeted && !!material()) ? null : /datum/msg/req_failed

/obj/structure/table/proc/carpet_laid(datum/act/op/A)
	var/obj/item/stack/tile/carpet/C = A.held
	carpeted_type = C.type
	set_carpeted(TRUE)
	return OP_OK

/obj/structure/table/proc/carpet_lifted(datum/act/op/A)
	new carpeted_type(loc)
	set_carpeted(FALSE)
	return OP_OK

/obj/structure/table/proc/is_damaged(datum/act/A)
	return get_integrity() < max_integrity // ALLOW(reads): a table's strength is read when a repair is tried; the click asks again before anything runs

/obj/structure/table/proc/repaired(datum/act/op/A)
	repair_damage(max_integrity / 5)
	return OP_OK

// ---- the strength of the table ----

/obj/structure/table/examine_icon()
	return icon(icon=initial(icon), icon_state=initial(icon_state)) //Basically the map preview version

/obj/structure/table/take_damage(damage_amount, damage_type = BRUTE, damage_flag, sound_effect = TRUE, attack_dir, armour_penetration = 0)
	// If the table is made of a brittle material, and is *not* reinforced with a non-brittle material, damage is multiplied by TABLE_BRITTLE_MATERIAL_MULTIPLIER
	if(material() && material().is_brittle())
		if(reinforced())
			if(reinforced().is_brittle())
				damage_amount *= TABLE_BRITTLE_MATERIAL_MULTIPLIER
		else
			damage_amount *= TABLE_BRITTLE_MATERIAL_MULTIPLIER
	return ..()

// Reaching 0 integrity breaks the table into shards/sheets.
/obj/structure/table/atom_destruction(damage_flag)
	visible_message(span_warning("\The [src] breaks down!"))
	break_to_parts()
	return ..()

/obj/structure/table/Initialize(mapload)
	. = ..()

	// A preset starts built with its layers.
	if(plating_id)
		set_layers(get_material_by_name(plating_id), reinforcement_id ? get_material_by_name(reinforcement_id) : null)

	// One table per turf.
	for(var/obj/structure/table/T in contents_of(loc))
		if(T != src)
			// There's another table here that's not us, break to metal.
			// break_to_parts calls qdel(src)
			break_to_parts(full_return = 1)
			return

	// reset color/alpha, since they're set for nice map previews
	color = "#ffffff"
	alpha = 255
	update_connections()
	update_desc()
	update_material()


/obj/structure/table/attack_alien(mob/user as mob)
	act_message(user, src, others = span_danger("%U% tears apart %T%!"))
	src.break_to_parts()

/// A claw (a xenomorph's hand) tears the table apart.
/obj/structure/table/proc/actor_is_xeno(datum/act/op/A)
	var/mob/living/carbon/human/X = A.actor
	return (istype(X) && istype(X.species, /datum/species/xenos)) ? null : /datum/msg/req_failed

/obj/structure/table/proc/clawed_apart(datum/act/op/A)
	attack_alien(A.actor)
	return OP_OK

/obj/structure/table/attack_generic(mob/user as mob, damage)
	if(damage >= 10)
		if(reinforced() && prob(70))
			act_message(user, src, others = span_danger("%U% smashes against %T%!"))
			receive_generic_attack(user, damage / 2)
			user.do_attack_animation(src)
			..()
		else
			act_message(user, src, others = span_danger("%U% tears apart %T%!"))
			src.break_to_parts()
			user.do_attack_animation(src)
			return 1
	act_message(user, src, others = span_infoplain(span_bold("%U%") + " scratches at %T%!"))
	return ..()

// Returns a list of /obj/item/material/shard objects that were created as a result of this table's breakage.
// Used for !fun! things such as embedding shards in the faces of tableslammed people.

// The repeated
//	S = [x].place_shard(loc)
//	if(S) shards += S
// is to avoid filling the list with nulls, as place_shard won't place shards of certain materials (holo-wood, holo-steel)

/obj/structure/table/proc/break_to_parts(full_return = 0)
	var/list/shards = list()
	var/obj/item/material/shard/S = null
	if(reinforced())
		if(reinforced().stack_type && (full_return || prob(20)))
			reinforced().place_sheet(loc, 1)
		else
			S = reinforced().place_shard(loc)
			if(S) shards += S
	if(material())
		if(material().stack_type && (full_return || prob(20)))
			material().place_sheet(loc, 1)
		else
			S = material().place_shard(loc)
			if(S) shards += S
	if(carpeted && (full_return || prob(50))) // Higher chance to get the carpet back intact, since there's no non-intact option
		new carpeted_type(src.loc)
	if(full_return || prob(20))
		new /obj/item/stack/material/steel(src.loc)
	else
		var/datum/material/M = get_material_by_name(MAT_STEEL)
		S = M.place_shard(loc)
		if(S) shards += S
	last_break_shards = shards
	destroyed(src, null, BRUTE)
	return shards

/obj/structure/table/can_visually_connect_to(obj/structure/S)
	if(istype(S,/obj/structure/table/bench) && !istype(src,/obj/structure/table/bench))
		return FALSE
	if(istype(src,/obj/structure/table/bench) && !istype(S,/obj/structure/table/bench))
		return FALSE
	if(istype(S,/obj/structure/table/rack) && !istype(src,/obj/structure/table/rack))
		return FALSE
	if(istype(src,/obj/structure/table/rack) && !istype(S,/obj/structure/table/rack))
		return FALSE
	if(istype(S,/obj/structure/table))
		return TRUE
	..()

/proc/get_table_image(icon/ticon,ticonstate,tdir,tcolor,talpha)
	// Keyed by the icon file's path: a ref would be recycled. A runtime /icon has no stable
	// identity, so it is built uncached.
	if(!isfile(ticon))
		return build_table_icon(ticon, ticonstate, tdir, tcolor, talpha)
	return CACHED_KEY(table_icon, "[ticon]-[ticonstate]-[tdir]-[tcolor]-[talpha]", ticon, ticonstate, tdir, tcolor, talpha)

/proc/build_table_icon(icon/ticon, ticonstate, tdir, tcolor, talpha)
	var/image/I = image(icon = ticon, icon_state = ticonstate, dir = tdir)
	if(tcolor)
		I.color = tcolor
	if(talpha)
		I.alpha = talpha
	return I

/// Whether the table draws the frame, plating, reinforcement and carpet layers (a rack and a survival pod table draw their own sprite).
/obj/structure/table/proc/draws_layers()
	return TRUE

/// The frame, plating, reinforcement and carpet of a standing table by its connections; a flipped one by the flipped tables beside it (watched: one
/// appearing, leaving, turning or changing material redraws this table). The plating and reinforcement are shared definitions that never change, so
/// they are read in the layer procs below, not watched: a layer going on or off is the table's own state.
/obj/structure/table/draw(datum/look/look)
	..()
	if(!draws_layers())
		return
	if(flipped != 1)
		look.state("blank")
		for(var/image/layer_image as anything in standing_layers())
			look.overlay(layer_image)
	else
		var/type = 0
		var/tabledirs = 0
		var/plated_with = plating_name()
		for(var/direction in list(turn(dir,90), turn(dir,-90)))
			var/obj/structure/table/T = look.neighbour(src, direction, /obj/structure/table)
			if(T && T.flipped == 1 && T.dir == dir && plated_with && T.plating_name() == plated_with)
				type++
				tabledirs |= direction

		type = "[type]"
		if(type == "1")
			if(tabledirs & turn(dir,90))
				type += "-"
			if(tabledirs & turn(dir,-90))
				type += "+"

		look.state("flip[type]")
		look.identity(name = plated_with ? "[plating_display()] table" : "table frame")
		for(var/layer_image in flipped_layers(type))
			look.overlay(layer_image)

/// The name of what the table is plated with (its display name), or null for a bare frame.
/obj/structure/table/proc/plating_name()
	return material()?.name

/// What the plating is called on the table (a flipped one is named after it).
/obj/structure/table/proc/plating_display()
	return material()?.display_name

/// The tint of the plating, or null for a bare frame.
/obj/structure/table/proc/plating_colour()
	return material()?.icon_colour

/// The layers of a standing table, bottom first: the frame shape by connection, then plating, reinforcement and carpet.
/obj/structure/table/proc/standing_layers()
	var/list/layers = list()
	var/datum/material/plating = material()
	var/datum/material/reinforcement = reinforced()
	for(var/i = 1 to 4)
		layers += get_table_image(icon, connections?[i] || 0, 1<<(i-1))
	if(plating)
		for(var/i = 1 to 4)
			layers += get_table_image(icon, "[plating.table_icon_base]_[connections?[i] || 0]", 1<<(i-1), plating.icon_colour, 255 * plating.opacity)
	if(reinforcement)
		for(var/i = 1 to 4)
			layers += get_table_image(icon, "[reinforcement.icon_reinf]_[connections?[i] || 0]", 1<<(i-1), reinforcement.icon_colour, 255 * reinforcement.opacity)
	if(carpeted)
		for(var/i = 1 to 4)
			layers += get_table_image(icon, "carpet_[connections?[i] || 0]", 1<<(i-1))
	return layers

/// The layers of a flipped table of the given kind ("0", "1-", "1+", "2"): plating, reinforcement, carpet.
/obj/structure/table/proc/flipped_layers(kind)
	var/list/layers = list()
	var/datum/material/plating = material()
	var/datum/material/reinforcement = reinforced()
	if(plating)
		layers += look_overlay_image(icon, "[plating.table_icon_base]_flip[kind]", color = plating.icon_colour, alpha = 255 * plating.opacity)
	if(reinforcement)
		layers += look_overlay_image(icon, "[reinforcement.icon_reinf]_flip[kind]", color = reinforcement.icon_colour, alpha = 255 * reinforcement.opacity)
	if(carpeted)
		layers += "carpet_flip[kind]"
	return layers

/obj/structure/table/proc/get_all_connected_tables(list/found)
	if(!found)
		found = list()
	found |= src
	if(istype(src, /obj/structure/table/rack))
		return found

	for(var/direction in GLOB.cardinal)
		var/turf/T = get_step(src, direction)
		if(T)
			var/obj/structure/table/nextT = locate_on(T, /obj/structure/table)
			if(!nextT || !istype(nextT))
				continue
			if(istype(nextT, /obj/structure/table/rack) || (istype(nextT, /obj/structure/table/bench) && !istype(src, /obj/structure/table/bench)) ||  (!istype(nextT, /obj/structure/table/bench) && istype(src, /obj/structure/table/bench)))
				continue
			if(!(nextT in found))
				nextT.get_all_connected_tables(found)

	return found

#define CORNER_NONE 0
#define CORNER_COUNTERCLOCKWISE 1
#define CORNER_DIAGONAL 2
#define CORNER_CLOCKWISE 4

/*
	turn() is weird:
		turn(icon, angle) turns icon by angle degrees clockwise
		turn(matrix, angle) turns matrix by angle degrees clockwise
		turn(dir, angle) turns dir by angle degrees counter-clockwise
*/

/proc/dirs_to_corner_states(list/dirs)
	if(!istype(dirs))
		return

	var/list/ret = list(NORTHWEST, SOUTHEAST, NORTHEAST, SOUTHWEST)

	for(var/i = 1 to ret.len)
		var/dir = ret[i]
		. = CORNER_NONE
		if(dir in dirs)
			. |= CORNER_DIAGONAL
		if(turn(dir,45) in dirs)
			. |= CORNER_COUNTERCLOCKWISE
		if(turn(dir,-45) in dirs)
			. |= CORNER_CLOCKWISE
		ret[i] = "[.]"

	return ret

#undef CORNER_NONE
#undef CORNER_COUNTERCLOCKWISE
#undef CORNER_DIAGONAL
#undef CORNER_CLOCKWISE
