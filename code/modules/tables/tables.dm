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
	var/flipped = 0
	max_integrity = 10

	// For racks.
	var/can_reinforce = 1
	var/can_plate = 1

	/// Transient hand-off: shards produced by the most recent break_to_parts(), read
	/// by callers (e.g. tableslam) that previously consumed take_damage()'s return.
	var/list/last_break_shards
	var/tmp/datum/material/material_static
	var/tmp/datum/material/reinforced_static

	// Gambling tables. I'd prefer reinforced with carpet/felt/cloth/whatever, but AFAIK it's either harder or impossible to get /obj/item/stack/material of those.
	// Convert if/when you can easily get stacks of these.
	var/carpeted = 0
	var/carpeted_type = /obj/item/stack/tile/carpet

/obj/structure/table/examine_icon()
	return icon(icon=initial(icon), icon_state=initial(icon_state)) //Basically the map preview version

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
	update_connections(SSticker && SSticker.current_state == GAME_STATE_PLAYING)
	update_icon()
	update_desc()
	update_material()

	make_climbable(/datum/om/behaviour/climbable/table)

// neighbouring tables re-smooth without it.
/obj/structure/table/on_destroy(force)
	material_static = null
	reinforced_static = null
	update_connections(1) // Update tables around us to ignore us (material=null forces no connections)
	for(var/obj/structure/table/T in oview(src, 1))
		T.update_icon()
	..()

/// Old attackby (tables.dm): carpet or plate the table.
/obj/structure/table/proc/interaction_surface(mob/user, obj/item/W, datum/interaction/interaction)
	if(!carpeted && material() && istype(W, /obj/item/stack/tile/carpet))
		var/obj/item/stack/tile/carpet/C = W
		if(C.use(1))
			user.visible_message(span_infoplain(span_bold("\The [user]") + " adds \the [C] to \the [src]."),
								span_notice("You add \the [C] to \the [src]."))
			carpeted = 1
			carpeted_type = W.type
			update_icon()
			return 1
		else
			to_chat(user, span_warning("You don't have enough carpet!"))

	if(!material() && can_plate && istype(W, /obj/item/stack/material))
		common_material_add(W, user, "plat", PROC_REF(plating_done))
		return 1

	return FALSE

/obj/structure/table/screwdriver_act(mob/user, obj/item/tool)
	if(!reinforced())
		return ITEM_INTERACT_BLOCKING
	remove_reinforced(tool, user)
	return ITEM_INTERACT_SUCCESS

/obj/structure/table/crowbar_act(mob/user, obj/item/tool)
	if(!carpeted)
		return ITEM_INTERACT_BLOCKING
	user.visible_message(span_infoplain(span_bold("\The [user]") + " removes the carpet from \the [src]."), span_notice("You remove the carpet from \the [src]."))
	new carpeted_type(loc)
	carpeted = FALSE
	update_icon()
	return ITEM_INTERACT_SUCCESS

/obj/structure/table/wrench_act(mob/user, obj/item/tool)
	if(carpeted || reinforced())
		return ITEM_INTERACT_BLOCKING
	if(material())
		remove_material(tool, user)
		return ITEM_INTERACT_SUCCESS
	dismantle(tool, user)
	return ITEM_INTERACT_SUCCESS

/obj/structure/table/welder_act(mob/user, obj/item/tool)
	if(get_integrity() >= max_integrity)
		return ITEM_INTERACT_BLOCKING
	var/obj/item/weldingtool/welder = tool.get_welder()
	if(!welder.welding)
		return ITEM_INTERACT_BLOCKING
	use_tool(user, tool, src, delay = 2 SECONDS, quality = TOOL_WELDER, volume = 50, amount = 1, message_self = "You begin repairing damage to \the [src].", receiver = src, on_done = PROC_REF(welder_act_tool_done), done_args = list(user), claims = TRUE)
	return ITEM_INTERACT_SUCCESS

/obj/structure/table/proc/welder_act_tool_done(mob/user)
	user.visible_message(span_infoplain(span_bold("\The [user]") + " repairs some damage to \the [src]."), span_notice("You repair some damage to \the [src]."))
	repair_damage(max_integrity / 5)
	return ITEM_INTERACT_SUCCESS

DECLARE_INTERACTIONS(/obj/structure/table, \
	INTERACT_HAND(null, PROC_REF(interaction_hand)), \
	INTERACT_ITEM("Surface", PROC_REF(interaction_surface)), \
	INTERACT_INSERT_HOSTILE(/obj/item/grab, PROC_REF(interaction_slam), "Slam against table"), \
	INTERACT_ITEM("Place", PROC_REF(interaction_item)), \
	INTERACT_DRAG("Place", PROC_REF(interaction_drag)), \
)

/// Old attack_hand.
/obj/structure/table/proc/interaction_hand(mob/user, obj/item/held, datum/interaction/interaction)
	if(ishuman(user))
		var/mob/living/carbon/human/X = user
		if(istype(X.species, /datum/species/xenos))
			src.attack_alien(user)
			return TRUE
	return FALSE

/obj/structure/table/attack_alien(mob/user as mob)
	visible_message(span_danger("\The [user] tears apart \the [src]!"))
	src.break_to_parts()

/obj/structure/table/attack_generic(mob/user as mob, damage)
	if(damage >= 10)
		if(reinforced() && prob(70))
			visible_message(span_danger("\The [user] smashes against \the [src]!"))
			receive_generic_attack(user, damage / 2)
			user.do_attack_animation(src)
			..()
		else
			visible_message(span_danger("\The [user] tears apart \the [src]!"))
			src.break_to_parts()
			user.do_attack_animation(src)
			return 1
	visible_message(span_infoplain(span_bold("\The [user]") + " scratches at \the [src]!"))
	return ..()

/obj/structure/table/proc/reinforce_table(obj/item/stack/material/S, mob/user)
	if(reinforced())
		to_chat(user, span_warning("\The [src] is already reinforced!"))
		return

	if(!can_reinforce)
		to_chat(user, span_warning("\The [src] cannot be reinforced!"))
		return

	if(!material())
		to_chat(user, span_warning("Plate \the [src] before reinforcing it!"))
		return

	if(flipped)
		to_chat(user, span_warning("Put \the [src] back in place before reinforcing it!"))
		return

	common_material_add(S, user, "reinforc", PROC_REF(reinforcing_done))

/obj/structure/table/proc/plating_done(datum/material/M)
	if(material())
		return
	material_static = M
	update_connections(1)
	update_icon()
	update_desc()
	update_material()

/obj/structure/table/proc/reinforcing_done(datum/material/M)
	if(reinforced())
		return
	reinforced_static = M
	update_desc()
	update_icon()
	update_material()

/obj/structure/table/proc/update_desc()
	if(material())
		name = "[material().display_name] table"
	else
		name = "table frame"

	if(reinforced())
		name = "reinforced [name]"
		desc = "[initial(desc)] This one seems to be reinforced with [reinforced().display_name]."
	else
		desc = initial(desc)

// Returns the material to set the table to.
/// Plates or reinforces with `S` (a timed action); `done_proc` gets the material on completion.
/// Verb is actually verb without 'e' or 'ing', which is added. Works for 'plate'/'plating' and 'reinforce'/'reinforcing'.
/obj/structure/table/proc/common_material_add(obj/item/stack/material/S, mob/user, verb, done_proc)
	var/datum/material/M = S.get_material()
	if(!istype(M))
		to_chat(user, span_warning("You cannot [verb]e \the [src] with \the [S]."))
		return

	if(om_busy(src))
		return
	to_chat(user, span_notice("You begin [verb]ing \the [src] with [M.display_name]."))
	om_task_start(/datum/om/task/timed/table_material_add, user, src, receiver = src, S = S, "verb" = verb, done_proc = done_proc, M = M)

/datum/om/task/timed/table_material_add
	duration = 2 SECONDS
	claims = TRUE
	complete_proc = /obj/structure/table/proc/material_add_done
	var/obj/item/stack/material/S
	var/verb
	var/done_proc
	var/datum/material/M

/obj/structure/table/proc/material_add_done(datum/om/task/timed/table_material_add/task)
	var/obj/item/stack/material/S = task.S
	var/mob/user = task.actor
	var/verb = task.verb
	var/done_proc = task.done_proc
	var/datum/material/M = task.M
	if(!S.use(1))
		return
	user.visible_message(span_notice("\The [user] [verb]es \the [src] with [M.display_name]."), span_notice("You finish [verb]ing \the [src]."))
	call(src, done_proc)(M)

// Returns the material to set the table to.
/// Removes the `which` layer ("reinforced" or "material") with a timed tool job.
/obj/structure/table/proc/common_material_remove(mob/user, datum/material/M, delay, what, type_holding, obj/item/tool, which)
	if(!M.stack_type)
		to_chat(user, span_warning("You are unable to remove the [what] from this [src]!"))
		return M

	if(om_busy(src)) return M
	user.visible_message(span_infoplain(span_bold("\The [user]") + " begins removing the [type_holding] holding \the [src]'s [M.display_name] [what] in place."),
								span_notice("You begin removing the [type_holding] holding \the [src]'s [M.display_name] [what] in place."))
	use_tool(user, tool, src, delay = delay, volume = 50, receiver = src, job_type = /datum/om/task/timed/tool_job/table_layer_remove, job_params = list("material" = M, "what" = what, "which" = which))
	return TRUE

/obj/structure/table/proc/common_material_remove_tool_done(mob/user, datum/material/M, what, which)
	user.visible_message(span_infoplain(span_bold("\The [user]") + " removes the [M.display_name] [what] from \the [src]."),
								span_notice("You remove the [M.display_name] [what] from \the [src]."))
	new M.stack_type(src.loc)
	if(which == "reinforced")
		reinforced_static = null
		update_desc()
		update_icon()
		update_material()
		return
	material_static = null
	update_connections(TRUE)
	update_icon()
	for(var/obj/structure/table/table in oview(src, 1))
		table.update_icon()
	update_desc()
	update_material()

/obj/structure/table/proc/remove_reinforced(obj/item/S, mob/user)
	common_material_remove(user, reinforced(), 40, "reinforcements", "screws", S, "reinforced")

/obj/structure/table/proc/remove_material(obj/item/W, mob/user)
	common_material_remove(user, material(), 20, "plating", "bolts", W, "material")

/obj/structure/table/proc/dismantle(obj/item/W, mob/user)
	if(om_busy(src)) return
	user.visible_message(span_infoplain(span_bold("\The [user]") + " begins dismantling \the [src]."),
							span_notice("You begin dismantling \the [src]."))
	use_tool(user, W, src, delay = 2 SECONDS, volume = 50, receiver = src, on_done = PROC_REF(dismantle_tool_done), done_args = list(user), claims = TRUE)
	return TRUE

/obj/structure/table/proc/dismantle_tool_done(mob/user)
	user.visible_message(span_infoplain(span_bold("\The [user]") + " dismantles \the [src]."),
							span_notice("You dismantle \the [src]."))
	replace_with(src, /obj/item/stack/material/steel)
	return

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
	qdel(src)
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

/obj/structure/table/update_icon()
	if(flipped != 1)
		icon_state = "blank"
		cut_overlays()

		// Base frame shape. Mostly done for glass/diamond tables, where this is visible.
		for(var/i = 1 to 4)
			var/image/I = get_table_image(icon, connections?[i] || 0, 1<<(i-1))
			add_overlay(I)

		// Standard table image
		if(material())
			for(var/i = 1 to 4)
				var/connect = connections?[i] || 0
				var/image/I = get_table_image(icon, "[material().table_icon_base]_[connect]", 1<<(i-1), material().icon_colour, 255 * material().opacity)
				add_overlay(I)

		// Reinforcements
		if(reinforced())
			for(var/i = 1 to 4)
				var/connect = connections?[i] || 0
				var/image/I = get_table_image(icon, "[reinforced().icon_reinf]_[connect]", 1<<(i-1), reinforced().icon_colour, 255 * reinforced().opacity)
				add_overlay(I)

		if(carpeted)
			for(var/i = 1 to 4)
				var/connect = connections?[i] || 0
				var/image/I = get_table_image(icon, "carpet_[connect]", 1<<(i-1))
				add_overlay(I)
	else
		cut_overlays()
		var/type = 0
		var/tabledirs = 0
		for(var/direction in list(turn(dir,90), turn(dir,-90)) )
			var/obj/structure/table/T = locate(/obj/structure/table ,get_step(src,direction))
			if (T && T.flipped == 1 && T.dir == src.dir && material() && T.material() && T.material().name == material().name)
				type++
				tabledirs |= direction

		type = "[type]"
		if (type=="1")
			if (tabledirs & turn(dir,90))
				type += "-"
			if (tabledirs & turn(dir,-90))
				type += "+"

		icon_state = "flip[type]"
		if(material())
			var/image/I = image(icon, "[material().table_icon_base]_flip[type]")
			I.color = material().icon_colour
			I.alpha = 255 * material().opacity
			add_overlay(I)
			name = "[material().display_name] table"
		else
			name = "table frame"

		if(reinforced())
			var/image/I = image(icon, "[reinforced().icon_reinf]_flip[type]")
			I.color = reinforced().icon_colour
			I.alpha = 255 * reinforced().opacity
			add_overlay(I)

		if(carpeted)
			add_overlay("carpet_flip[type]")

/obj/structure/table/proc/get_all_connected_tables(list/connections)
	if(!connections)
		connections = list(src)
	else
		connections |= src
	if(istype(src, /obj/structure/table/rack))
		return connections

	for(var/direction in GLOB.cardinal)
		var/turf/T = get_step(src, direction)
		if(T)
			var/obj/structure/table/nextT = locate_on(T, /obj/structure/table)
			if(!nextT || !istype(nextT))
				continue
			if(istype(nextT, /obj/structure/table/rack) || (istype(nextT, /obj/structure/table/bench) && !istype(src, /obj/structure/table/bench)) ||  (!istype(nextT, /obj/structure/table/bench) && istype(src, /obj/structure/table/bench)))
				continue
			if(!(nextT in connections))
				connections |= nextT.get_all_connected_tables(connections)

	return connections

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

/// A shared definition/flyweight (implicitly shared), never cleared.
/obj/structure/table/proc/material() as /datum/material
	return material_static

/// A shared definition/flyweight (implicitly shared), never cleared.
/obj/structure/table/proc/reinforced() as /datum/material
	return reinforced_static
