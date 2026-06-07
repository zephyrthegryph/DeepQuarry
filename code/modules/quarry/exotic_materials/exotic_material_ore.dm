// Ore-datum subclass + dropped item for dynamic exotic materials.
//
// One /datum/ore/exotic_material instance is registered per rolled
// material (see exotic_material_subsystem.dm) so the existing wall
// pipeline can mark walls with the material's name. When a wall is
// mined, /turf/simulated/mineral/proc/DropMineral calls
// `new mineral.ore (src)` — the spawned /obj/item/exotic_material_sample
// reads the wall's `mineral.material_id` to figure out which material it
// belongs to.

/datum/ore/exotic_material
	/// Back-link to the round-rolled material this ore represents.
	/// Set on the per-material instance created by _register_exotic_ore.
	/// The template instance auto-created by global_lists.dm has this
	/// left at 0 and gets registered under a null name — harmless.
	var/material_id = 0
	reagent = REAGENT_ID_SILICATE


/obj/item/exotic_material_sample
	name = "exotic material sample"
	desc = "A heavy chunk of unfamiliar rock. The colors don't match anything in the geology manual."
	icon = 'icons/obj/mining.dmi'
	icon_state = "ore_diamond"
	w_class = ITEMSIZE_SMALL
	randpixel = 8
	/// Round-id of the /datum/material/dynamic this sample is a piece of.
	/// Resolved through SSquarry.get_exotic_material(id) by the analyzer.
	/// 0 means the sample wasn't spawned via the quarry pipeline (e.g.
	/// admin-spawned outside a round) and the analyzer will refuse it.
	var/material_id = 0

/obj/item/exotic_material_sample/Initialize(mapload)
	. = ..()
	// We're spawned by DropMineral into the wall turf. Read the wall's
	// mineral datum to learn our material id, then carry it forward —
	// the wall's `mineral` clears shortly after as the turf becomes
	// floor.
	var/turf/T = get_turf(src)
	if(istype(T, /turf/simulated/mineral))
		var/turf/simulated/mineral/W = T
		if(istype(W.mineral, /datum/ore/exotic_material))
			var/datum/ore/exotic_material/OD = W.mineral
			material_id = OD.material_id
	_refresh_appearance()

/obj/item/exotic_material_sample/proc/_refresh_appearance()
	var/datum/material/dynamic/M = SSquarry?.get_exotic_material(material_id)
	if(!M)
		return
	name = "[M.pretty_name] sample"
	color = M.color
	desc = "A heavy chunk of [M.pretty_name]. The internal grain catches the light strangely. A science analyzer should be able to read its properties."

/obj/item/exotic_material_sample/examine(mob/user)
	. = ..()
	var/datum/material/dynamic/M = SSquarry?.get_exotic_material(material_id)
	if(!M)
		. += span_warning("It's almost certainly worth something, but you can't tell what.")
		return
	. += span_notice("It's a sample of <b>[M.pretty_name]</b>.")
	. += span_notice("Take it to an exotic material analyzer to learn its properties.")
