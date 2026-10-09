// ---- taking a wall apart, declared ----
//
// A plain wall is cut open with a welder (or a plasma cutter, an energy blade or a pickaxe). A reinforced wall goes 6 -> 0 through its layers, and
// some steps go back. The wall's `construction_stage` var is the state (null on plain walls, which a reinforced wall's stage 6 starts from), so the
// steps are ops that read that var: wall_construction() is listed in the wall's CAPABILITIES block (walls.dm).
//
// Welder work that isn't taking the wall apart (burning off wallrot, lighting thermite, repairing damage) sits above the cutting steps.

MSG_DEF_SELF(wall/clumsy, "You don't have the dexterity to do this.")
MSG_DEF_SELF(wall/inside, "You can't do this from in here.")

MSG_DEF(wall/cut_plain, "You remove the outer plating.", span_warning("The wall was torn open by %U%!"))
MSG_DEF_SELF(wall/cut_plain_begins, "You begin cutting through the outer plating.")
MSG_DEF_SELF(wall/cut_plain_blade_begins, "You begin slicing through the outer plating.")
MSG_DEF_SELF(wall/cut_grille, "You cut through the outer grille.")
MSG_DEF_SELF(wall/mend_grille, "You mend the outer grille.")
MSG_DEF_SELF(wall/unscrew_lines, "You unscrew the support lines.")
MSG_DEF_SELF(wall/unscrew_lines_begins, "You begin removing the support lines.")
MSG_DEF_SELF(wall/screw_lines, "You screw down the support lines.")
MSG_DEF_SELF(wall/screw_lines_begins, "You begin screwing down the support lines.")
MSG_DEF_SELF(wall/slice_cover, "You press firmly on the cover, dislodging it.")
MSG_DEF_SELF(wall/slice_cover_begins, "You begin slicing through the metal cover.")
MSG_DEF_SELF(wall/pry_cover, "You pry off the cover.")
MSG_DEF_SELF(wall/pry_cover_begins, "You struggle to pry off the cover.")
MSG_DEF_SELF(wall/loosen_bolts, "You remove the bolts anchoring the support rods.")
MSG_DEF_SELF(wall/loosen_bolts_begins, "You start loosening the anchoring bolts which secure the support rods to their frame.")
MSG_DEF_SELF(wall/slice_rods, "You slice through the support rods.")
MSG_DEF_SELF(wall/slice_rods_begins, "You begin slicing through the support rods.")
MSG_DEF_SELF(wall/pry_sheath, "You pry off the outer sheath.")
MSG_DEF_SELF(wall/pry_sheath_begins, "You struggle to pry off the outer sheath.")
MSG_DEF_SELF(wall/burn_rot, "You burn away the fungi with %I%.")
MSG_DEF_SELF(wall/repair_begins, "You start repairing the damage to %T%.")
MSG_DEF_SELF(wall/repaired, "You finish repairing the damage to %T%.")

/// A worker who can do wall work: dexterous and standing on a turf.
/proc/wall_worker()
	return needs(req(TYPE_PROC_REF(/turf/simulated/wall, worker_dexterous), because = MSG(wall/clumsy)), req(TYPE_PROC_REF(/turf/simulated/wall, worker_standing), because = MSG(wall/inside)))

/// The ops that take a wall apart, and the welder work above them.
/proc/wall_construction()
	return list(
		op("burn_rot", lit_welder(fuel = 0), when(TYPE_PROC_REF(/turf/simulated/wall, has_rot)), wall_worker(), priority(OP_PRIORITY_DEFAULT + 3), label("Burn away the fungi"), wait(0), says(MSG(wall/burn_rot)), then(TYPE_PROC_REF(/turf/simulated/wall, burn_away_rot))),
		op("light_thermite", lit_welder(fuel = 0), when(TYPE_PROC_REF(/turf/simulated/wall, thermite_ready)), wall_worker(), hostile(), priority(OP_PRIORITY_DEFAULT + 2), label("Ignite the thermite"), wait(0), then(TYPE_PROC_REF(/turf/simulated/wall, light_thermite))),
		op("weld_repair", lit_welder(fuel = 0), when(TYPE_PROC_REF(/turf/simulated/wall, repairable)), wall_worker(), priority(OP_PRIORITY_DEFAULT + 1), label("Repair the wall"), wait(TYPE_PROC_REF(/turf/simulated/wall, repair_time)), begins(MSG(wall/repair_begins)), says(MSG(wall/repaired)), then(TYPE_PROC_REF(/turf/simulated/wall, finish_weld_repair))),

		// a plain wall: cut through the outer plating with a welder, or with what stands in for one
		op("cut_plain", lit_welder(fuel = 0), when(TYPE_PROC_REF(/turf/simulated/wall, is_plain)), wall_worker(), label("Cut through the outer plating"), wait(TYPE_PROC_REF(/turf/simulated/wall, plain_cut_time)), begins(MSG(wall/cut_plain_begins)), starts(TYPE_PROC_REF(/turf/simulated/wall, tool_started)), says(MSG(wall/cut_plain)), then(TYPE_PROC_REF(/turf/simulated/wall, plain_cut))),
		op("cut_plain_blade", item(/obj/item/melee/energy/blade), when(TYPE_PROC_REF(/turf/simulated/wall, is_plain)), when(TYPE_PROC_REF(/turf/simulated/wall, no_thermite)), wall_worker(), label("Cut through the outer plating"), wait(TYPE_PROC_REF(/turf/simulated/wall, plain_cut_time_blade)), begins(MSG(wall/cut_plain_blade_begins)), starts(TYPE_PROC_REF(/turf/simulated/wall, alt_started)), says(MSG(wall/cut_plain)), then(TYPE_PROC_REF(/turf/simulated/wall, plain_cut))),
		op("cut_plain_pickaxe", item(/obj/item/pickaxe), when(TYPE_PROC_REF(/turf/simulated/wall, is_plain)), when(TYPE_PROC_REF(/turf/simulated/wall, no_thermite)), wall_worker(), label("Cut through the outer plating"), wait(TYPE_PROC_REF(/turf/simulated/wall, plain_cut_time_pickaxe)), begins(TYPE_PROC_REF(/turf/simulated/wall, pickaxe_begins)), starts(TYPE_PROC_REF(/turf/simulated/wall, alt_started)), says(MSG(wall/cut_plain)), then(TYPE_PROC_REF(/turf/simulated/wall, plain_cut))),

		// a reinforced wall, outermost layer first
		op("cut_grille", tool(TOOL_WIRECUTTER), when(TYPE_PROC_REF(/turf/simulated/wall, at_stage_6)), wall_worker(), label("Cut the outer grille"), wait(0), says(MSG(wall/cut_grille)), then(TYPE_PROC_REF(/turf/simulated/wall, cut_grille))),
		op("mend_grille", tool(TOOL_WIRECUTTER), when(TYPE_PROC_REF(/turf/simulated/wall, at_stage_5)), wall_worker(), label("Mend the outer grille"), wait(0), says(MSG(wall/mend_grille)), then(TYPE_PROC_REF(/turf/simulated/wall, mend_grille))),
		op("unscrew_lines", tool(TOOL_SCREWDRIVER), when(TYPE_PROC_REF(/turf/simulated/wall, at_stage_5)), wall_worker(), label("Unscrew the support lines"), wait(4 SECONDS), begins(MSG(wall/unscrew_lines_begins)), starts(TYPE_PROC_REF(/turf/simulated/wall, tool_started)), says(MSG(wall/unscrew_lines)), then(TYPE_PROC_REF(/turf/simulated/wall, unscrew_lines))),
		op("screw_lines", tool(TOOL_SCREWDRIVER), when(TYPE_PROC_REF(/turf/simulated/wall, at_stage_4)), wall_worker(), label("Screw down the support lines"), wait(4 SECONDS), begins(MSG(wall/screw_lines_begins)), starts(TYPE_PROC_REF(/turf/simulated/wall, tool_started)), says(MSG(wall/screw_lines)), then(TYPE_PROC_REF(/turf/simulated/wall, screw_lines))),
		op("slice_cover", lit_welder(fuel = 0), when(TYPE_PROC_REF(/turf/simulated/wall, at_stage_4)), wall_worker(), label("Slice through the metal cover"), wait(6 SECONDS), begins(MSG(wall/slice_cover_begins)), starts(TYPE_PROC_REF(/turf/simulated/wall, tool_started)), says(MSG(wall/slice_cover)), then(TYPE_PROC_REF(/turf/simulated/wall, slice_cover))),
		op("slice_cover_cutter", item(/obj/item/pickaxe/plasmacutter), when(TYPE_PROC_REF(/turf/simulated/wall, at_stage_4)), when(TYPE_PROC_REF(/turf/simulated/wall, no_thermite)), wall_worker(), label("Slice through the metal cover"), wait(TYPE_PROC_REF(/turf/simulated/wall, cutter_time_cover)), begins(MSG(wall/slice_cover_begins)), starts(TYPE_PROC_REF(/turf/simulated/wall, alt_started)), says(MSG(wall/slice_cover)), then(TYPE_PROC_REF(/turf/simulated/wall, slice_cover))),
		op("pry_cover", tool(TOOL_CROWBAR), when(TYPE_PROC_REF(/turf/simulated/wall, at_stage_3)), wall_worker(), label("Pry off the cover"), wait(10 SECONDS), begins(MSG(wall/pry_cover_begins)), starts(TYPE_PROC_REF(/turf/simulated/wall, tool_started)), says(MSG(wall/pry_cover)), then(TYPE_PROC_REF(/turf/simulated/wall, pry_cover))),
		op("loosen_bolts", tool(TOOL_WRENCH), when(TYPE_PROC_REF(/turf/simulated/wall, at_stage_2)), wall_worker(), label("Loosen the anchoring bolts"), wait(4 SECONDS), begins(MSG(wall/loosen_bolts_begins)), starts(TYPE_PROC_REF(/turf/simulated/wall, tool_started)), says(MSG(wall/loosen_bolts)), then(TYPE_PROC_REF(/turf/simulated/wall, loosen_bolts))),
		op("slice_rods", lit_welder(fuel = 0), when(TYPE_PROC_REF(/turf/simulated/wall, at_stage_1)), wall_worker(), label("Slice through the support rods"), wait(7 SECONDS), begins(MSG(wall/slice_rods_begins)), starts(TYPE_PROC_REF(/turf/simulated/wall, tool_started)), says(MSG(wall/slice_rods)), then(TYPE_PROC_REF(/turf/simulated/wall, slice_rods))),
		op("slice_rods_cutter", item(/obj/item/pickaxe/plasmacutter), when(TYPE_PROC_REF(/turf/simulated/wall, at_stage_1)), when(TYPE_PROC_REF(/turf/simulated/wall, no_thermite)), wall_worker(), label("Slice through the support rods"), wait(TYPE_PROC_REF(/turf/simulated/wall, cutter_time_rods)), begins(MSG(wall/slice_rods_begins)), starts(TYPE_PROC_REF(/turf/simulated/wall, alt_started)), says(MSG(wall/slice_rods)), then(TYPE_PROC_REF(/turf/simulated/wall, slice_rods))),
		op("pry_sheath", tool(TOOL_CROWBAR), when(TYPE_PROC_REF(/turf/simulated/wall, at_stage_0)), wall_worker(), label("Pry off the outer sheath"), wait(10 SECONDS), begins(MSG(wall/pry_sheath_begins)), starts(TYPE_PROC_REF(/turf/simulated/wall, tool_started)), says(MSG(wall/pry_sheath)), then(TYPE_PROC_REF(/turf/simulated/wall, pry_sheath))))

// ---- who may work, and in which state ----

/// A worker who is dexterous.
/turf/simulated/wall/proc/worker_dexterous(datum/act/op/A)
	var/mob/actor = A.actor
	return actor.IsAdvancedToolUser()

/// A worker who stands on a turf, not inside something.
/turf/simulated/wall/proc/worker_standing(datum/act/op/A)
	var/mob/actor = A.actor
	return isturf(actor.loc)

/// No reinforcement layers are left to go through: a plain wall, or a reinforced one with no stage.
/turf/simulated/wall/proc/is_plain(datum/act/A)
	return !reinf_material || isnull(construction_stage)

/// `construction_stage` is null or a step number that may be 0 (null == 0 is true in DM), so each stage asks for a number.
/turf/simulated/wall/proc/at_stage(stage)
	return reinf_material && !isnull(construction_stage) && construction_stage == stage

/turf/simulated/wall/proc/at_stage_6(datum/act/A)
	return at_stage(6)

/turf/simulated/wall/proc/at_stage_5(datum/act/A)
	return at_stage(5)

/turf/simulated/wall/proc/at_stage_4(datum/act/A)
	return at_stage(4)

/turf/simulated/wall/proc/at_stage_3(datum/act/A)
	return at_stage(3)

/turf/simulated/wall/proc/at_stage_2(datum/act/A)
	return at_stage(2)

/turf/simulated/wall/proc/at_stage_1(datum/act/A)
	return at_stage(1)

/turf/simulated/wall/proc/at_stage_0(datum/act/A)
	return at_stage(0)

// ---- a tool touching the wall ----

/// A tool touching the wall: it radiates, and a hot tool heats it.
/turf/simulated/wall/proc/touched_by_tool(obj/item/tool)
	radiate()
	var/heat = is_hot(tool)
	if(heat)
		burn(heat)

/// A step begins: the actor's click cooldown, and the tool touches the wall.
/turf/simulated/wall/proc/step_began(datum/act/op/A)
	var/mob/actor = A.actor
	var/obj/item/held = A.held
	actor.setClickCooldown(actor.get_attack_speed(held))
	if(held)
		touched_by_tool(held)

/// The first wait of a step starts.
/turf/simulated/wall/proc/tool_started(datum/act/op/A)
	step_began(A)

/// The first wait of a step that something other than the welder does starts: its own sound too.
/turf/simulated/wall/proc/alt_started(datum/act/op/A)
	step_began(A)
	var/obj/item/held = A.held
	var/sound = held?.usesound
	if(istype(held, /obj/item/melee/energy/blade))
		play_sfx(src, SFX_SPARKS)
		return
	if(istype(held, /obj/item/pickaxe) && !istype(held, /obj/item/pickaxe/plasmacutter))
		var/obj/item/pickaxe/pick = held
		sound = pick.drill_sound
	if(sound)
		playsound(src, sound, 100, TRUE)

/// A step that has no wait: begun and done in one go.
/turf/simulated/wall/proc/step_done(datum/act/op/A)
	step_began(A)

/// A layer has gone: whoever is looking at the wall sees the new state.
/turf/simulated/wall/proc/layer_done(datum/act/op/A)
	var/mob/actor = A.actor
	actor.update_examine_panel(src)

// ---- a plain wall ----

/// 60 deciseconds less the material's cut_delay.
/turf/simulated/wall/proc/plain_cut_base()
	return max(0, 60 - material.cut_delay)

/// The welder's wait (the op scales it by the tool).
/turf/simulated/wall/proc/plain_cut_time(datum/act/op/A)
	return plain_cut_base()

/// An energy blade cuts in half the time (and its own toolspeed).
/turf/simulated/wall/proc/plain_cut_time_blade(datum/act/op/A)
	var/obj/item/held = A.held
	return max(0, plain_cut_base() * 0.5 * held.toolspeed)

/// A pickaxe is as slow as the welder less its dig speed (and its own toolspeed).
/turf/simulated/wall/proc/plain_cut_time_pickaxe(datum/act/op/A)
	var/obj/item/pickaxe/pick = A.held
	return max(0, (plain_cut_base() - pick.digspeed) * pick.toolspeed)

/// The pickaxe's own drilling verb.
/turf/simulated/wall/proc/pickaxe_begins(datum/act/op/A)
	var/obj/item/pickaxe/pick = A.held
	return msg_text("You begin [istype(pick) ? pick.drill_verb : "digging"] through the outer plating.")

/// The wall comes open.
/turf/simulated/wall/proc/plain_cut(datum/act/op/A)
	dismantle_wall()
	return OP_OK

// ---- a reinforced wall ----

/// A plasma cutter slices the metal cover in the time the step takes.
/turf/simulated/wall/proc/cutter_time_cover(datum/act/op/A)
	var/obj/item/held = A.held
	return 6 SECONDS * held.toolspeed

/// A plasma cutter slices the support rods in the time the step takes.
/turf/simulated/wall/proc/cutter_time_rods(datum/act/op/A)
	var/obj/item/held = A.held
	return 7 SECONDS * held.toolspeed

/turf/simulated/wall/proc/cut_grille(datum/act/op/A)
	step_done(A)
	set_construction_stage(5)
	layer_done(A)
	return OP_OK

/turf/simulated/wall/proc/mend_grille(datum/act/op/A)
	step_done(A)
	set_construction_stage(6)
	layer_done(A)
	return OP_OK

/turf/simulated/wall/proc/unscrew_lines(datum/act/op/A)
	set_construction_stage(4)
	layer_done(A)
	return OP_OK

/turf/simulated/wall/proc/screw_lines(datum/act/op/A)
	set_construction_stage(5)
	layer_done(A)
	return OP_OK

/turf/simulated/wall/proc/slice_cover(datum/act/op/A)
	set_construction_stage(3)
	layer_done(A)
	return OP_OK

/turf/simulated/wall/proc/pry_cover(datum/act/op/A)
	set_construction_stage(2)
	layer_done(A)
	return OP_OK

/turf/simulated/wall/proc/loosen_bolts(datum/act/op/A)
	set_construction_stage(1)
	layer_done(A)
	return OP_OK

/turf/simulated/wall/proc/slice_rods(datum/act/op/A)
	set_construction_stage(0)
	layer_done(A)
	return OP_OK

/turf/simulated/wall/proc/pry_sheath(datum/act/op/A)
	dismantle_wall()
	return OP_OK

// ---- welder work that isn't taking the wall apart ----

/// No thermite on the wall: the cutter and the blade set thermite off instead (wall_item).
/turf/simulated/wall/proc/no_thermite(datum/act/A)
	return !thermite

/// Wallrot grows on the wall.
/turf/simulated/wall/proc/has_rot(datum/act/A)
	return (locate_within(src, /obj/effect/overlay/wallrot)) ? TRUE : FALSE

/// Thermite is on the wall and no wallrot covers it.
/turf/simulated/wall/proc/thermite_ready(datum/act/A)
	return thermite && !(locate_within(src, /obj/effect/overlay/wallrot))

/// Damaged, with no thermite and no wallrot.
/turf/simulated/wall/proc/repairable(datum/act/A)
	if(thermite || (locate_within(src, /obj/effect/overlay/wallrot)))
		return FALSE
	return get_integrity() < max_integrity

/// At least half a second; longer the more damage there is.
/turf/simulated/wall/proc/repair_time(datum/act/op/A)
	return max(5, (max_integrity - get_integrity()) / 5)

/turf/simulated/wall/proc/burn_away_rot(datum/act/op/A)
	touched_by_tool(A.held)
	for(var/obj/effect/overlay/wallrot/rot in turf_contents_of_type(src, /obj/effect/overlay/wallrot))
		dissolved(rot, A.actor)
	return OP_OK

/turf/simulated/wall/proc/light_thermite(datum/act/op/A)
	touched_by_tool(A.held)
	thermitemelt(A.actor)
	return OP_OK

/turf/simulated/wall/proc/finish_weld_repair(datum/act/op/A)
	touched_by_tool(A.held)
	repair_damage(max_integrity)
	var/mob/actor = A.actor
	actor.update_examine_panel(src)
	return OP_OK
