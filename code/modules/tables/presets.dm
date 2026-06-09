//TABLE PRESETS
/obj/structure/table/standard
	icon_state = "plain_preview"
	color = "#EEEEEE"

/obj/structure/table/standard/Initialize(mapload)
	material = get_material_by_name(DEFAULT_TABLE_MATERIAL)
	. = ..()

/obj/structure/table/steel
	icon_state = "plain_preview"
	color = "#666666"

/obj/structure/table/steel/Initialize(mapload)
	material = get_material_by_name(MAT_STEEL)
	. = ..()

/obj/structure/table/marble
	icon_state = "stone_preview"
	color = "#CCCCCC"

/obj/structure/table/marble/Initialize(mapload)
	material = get_material_by_name(MAT_MARBLE)
	. = ..()

/obj/structure/table/reinforced
	icon_state = "reinf_preview"
	color = "#EEEEEE"

/obj/structure/table/reinforced/Initialize(mapload)
	material = get_material_by_name(DEFAULT_TABLE_MATERIAL)
	reinforced = get_material_by_name(MAT_STEEL)
	. = ..()

/obj/structure/table/steel_reinforced
	icon_state = "reinf_preview"
	color = "#666666"

/obj/structure/table/steel_reinforced/Initialize(mapload)
	material = get_material_by_name(MAT_STEEL)
	reinforced = get_material_by_name(MAT_STEEL)
	. = ..()

/obj/structure/table/wooden_reinforced
	icon_state = "reinf_preview"
	color = "#824B28"

/obj/structure/table/wooden_reinforced/Initialize(mapload)
	material = get_material_by_name(MAT_WOOD)
	reinforced = get_material_by_name(MAT_STEEL)
	. = ..()

/obj/structure/table/woodentable
	icon_state = "plain_preview"
	color = "#824B28"

/obj/structure/table/woodentable/Initialize(mapload)
	material = get_material_by_name(MAT_WOOD)
	. = ..()

/obj/structure/table/sifwoodentable
	icon_state = "plain_preview"
	color = "#0099cc"

/obj/structure/table/sifwoodentable/Initialize(mapload)
	material = get_material_by_name(MAT_SIFWOOD)
	. = ..()

/obj/structure/table/sifwooden_reinforced
	icon_state = "reinf_preview"
	color = "#824B28"

/obj/structure/table/sifwooden_reinforced/Initialize(mapload)
	material = get_material_by_name(MAT_SIFWOOD)
	reinforced = get_material_by_name(MAT_STEEL)
	. = ..()

/obj/structure/table/hardwoodtable
	icon_state = "stone_preview"
	color = "#42291a"

/obj/structure/table/hardwoodtable/Initialize(mapload)
	material = get_material_by_name(MAT_HARDWOOD)
	. = ..()

/obj/structure/table/gamblingtable
	icon_state = "gamble_preview"

/obj/structure/table/gamblingtable/Initialize(mapload)
	material = get_material_by_name(MAT_WOOD)
	carpeted = 1
	. = ..()

/obj/structure/table/glass
	icon_state = "plain_preview"
	color = "#00E1FF"
	alpha = 77 // 0.3 * 255

/obj/structure/table/glass/Initialize(mapload)
	material = get_material_by_name(MAT_GLASS)
	. = ..()

/obj/structure/table/borosilicate
	icon_state = "plain_preview"
	color = "#4D3EAC"
	alpha = 77

/obj/structure/table/borosilicate/Initialize(mapload)
	material = get_material_by_name(MAT_PGLASS)
	. = ..()

/obj/structure/table/holotable
	icon_state = "holo_preview"
	color = "#EEEEEE"

/obj/structure/table/holotable/Initialize(mapload)
	material = get_material_by_name("holo[DEFAULT_TABLE_MATERIAL]")
	. = ..()

/obj/structure/table/woodentable/holotable
	icon_state = "holo_preview"

/obj/structure/table/woodentable/holotable/Initialize(mapload)
	material = get_material_by_name("holowood")
	. = ..()

/obj/structure/table/alien
	name = "alien table"
	desc = "Advanced flat surface technology at work!"
	icon_state = "alien_preview"
	can_reinforce = FALSE
	can_plate = FALSE

/obj/structure/table/alien/Initialize(mapload)
	material = get_material_by_name(MAT_ALIEN_ALIUM)
	verbs -= /obj/structure/table/verb/do_flip
	verbs -= /obj/structure/table/proc/do_put
	. = ..()

/obj/structure/table/alien/dismantle(obj/item/tool/wrench/W, mob/user)
	to_chat(user, span_warning("You cannot dismantle \the [src]."))
	return

//BENCH PRESETS
/obj/structure/table/bench/standard
	icon_state = "plain_preview"
	color = "#EEEEEE"

/obj/structure/table/bench/standard/Initialize(mapload)
	material = get_material_by_name(DEFAULT_TABLE_MATERIAL)
	. = ..()

/obj/structure/table/bench/steel
	icon_state = "plain_preview"
	color = "#666666"

/obj/structure/table/bench/steel/Initialize(mapload)
	material = get_material_by_name(MAT_STEEL)
	. = ..()


/obj/structure/table/bench/marble
	icon_state = "stone_preview"
	color = "#CCCCCC"

/obj/structure/table/bench/marble/Initialize(mapload)
	material = get_material_by_name(MAT_MARBLE)
	. = ..()
/*
/obj/structure/table/bench/reinforced
	icon_state = "reinf_preview"
	color = "#EEEEEE"

/obj/structure/table/bench/reinforced/Initialize(mapload)
	material = get_material_by_name(DEFAULT_TABLE_MATERIAL)
	reinforced = get_material_by_name(MAT_STEEL)
	. = ..()

/obj/structure/table/bench/steel_reinforced
	icon_state = "reinf_preview"
	color = "#666666"

/obj/structure/table/bench/steel_reinforced/Initialize(mapload)
	material = get_material_by_name(MAT_STEEL)
	reinforced = get_material_by_name(MAT_STEEL)
	. = ..()

/obj/structure/table/bench/wooden_reinforced
	icon_state = "reinf_preview"
	color = "#824B28"

/obj/structure/table/bench/wooden_reinforced/Initialize(mapload)
	material = get_material_by_name(MAT_WOOD)
	reinforced = get_material_by_name(MAT_STEEL)
	. = ..()
*/
/obj/structure/table/bench/wooden
	icon_state = "plain_preview"
	color = "#824B28"

/obj/structure/table/bench/wooden/Initialize(mapload)
	material = get_material_by_name(MAT_WOOD)
	. = ..()

/obj/structure/table/bench/sifwooden
	icon_state = "plain_preview"
	color = "#0099cc"

/obj/structure/table/bench/sifwooden/Initialize(mapload)
	material = get_material_by_name(MAT_SIFWOOD)
	. = ..()

/obj/structure/table/bench/sifwooden/padded
	icon_state = "padded_preview"
	carpeted = 1

/obj/structure/table/bench/padded
	icon_state = "padded_preview"

/obj/structure/table/bench/padded/Initialize(mapload)
	material = get_material_by_name(MAT_STEEL)
	carpeted = 1
	. = ..()

/obj/structure/table/bench/glass
	icon_state = "plain_preview"
	color = "#00E1FF"
	alpha = 77 // 0.3 * 255

/obj/structure/table/bench/glass/Initialize(mapload)
	material = get_material_by_name(MAT_GLASS)
	. = ..()

/*
/obj/structure/table/bench/holotable
	icon_state = "holo_preview"
	color = "#EEEEEE"

/obj/structure/table/bench/holotable/Initialize(mapload)
	material = get_material_by_name("holo[DEFAULT_TABLE_MATERIAL]")
	. = ..()

/obj/structure/table/bench/wooden/holotable
	icon_state = "holo_preview"

/obj/structure/table/bench/wooden/holotable/Initialize(mapload)
	material = get_material_by_name("holowood")
	. = ..()
*/

/obj/structure/table/bench/glamour
	icon_state = "plain_preview"
	color = "#fffce6"

/obj/structure/table/bench/glamour/Initialize(mapload)
	material = get_material_by_name(MAT_GLAMOUR)
	. = ..()

//new wood types
/obj/structure/table/birch
	icon_state = "plain_preview"
	color = "#f6dec0"

/obj/structure/table/birch/Initialize(mapload)
	material = get_material_by_name(MAT_BIRCHWOOD)
	. = ..()

/obj/structure/table/pine
	icon_state = "plain_preview"
	color = "#cd9d6f"

/obj/structure/table/pine/Initialize(mapload)
	material = get_material_by_name(MAT_PINEWOOD)
	. = ..()

/obj/structure/table/oak
	icon_state = "plain_preview"
	color = "#674928"

/obj/structure/table/oak/Initialize(mapload)
	material = get_material_by_name(MAT_OAKWOOD)
	. = ..()

/obj/structure/table/acacia
	icon_state = "plain_preview"
	color = "#b75e12"

/obj/structure/table/acacia/Initialize(mapload)
	material = get_material_by_name(MAT_ACACIAWOOD)
	. = ..()

/obj/structure/table/redwood
	icon_state = "stone_preview"
	color = "#a45a52"

/obj/structure/table/redwood/Initialize(mapload)
	material = get_material_by_name(MAT_REDWOOD)
	. = ..()


// === merged from presets_vr.dm during hard-fork de-suffix (verified no override-order change) ===
/obj/structure/table/darkglass
	name = "darkglass table"
	desc = "Shiny!"
	icon = 'icons/obj/tables_vr.dmi'
	icon_state = "darkglass_table_preview"
// flipped = -1 // KSC = So one can climb tables and walk on them. (Having this on -1 means you can climb this table but unable to walk over an other table tile of the same type)
	can_reinforce = FALSE
	can_plate = FALSE

/obj/structure/table/darkglass/Initialize(mapload)
	material = get_material_by_name(MAT_DARKGLASS)
	verbs -= /obj/structure/table/verb/do_flip
	verbs -= /obj/structure/table/proc/do_put

	. = ..()

/obj/structure/table/darkglass/dismantle(obj/item/tool/wrench/W, mob/user)
	to_chat(user, span_warning("You cannot dismantle \the [src]."))
	return
/obj/structure/table/alien/blue
	icon = 'icons/turf/shuttle_alien_blue.dmi'


/obj/structure/table/fancyblack
	name = "fancy table"
	desc = "Cloth!"
	icon = 'icons/obj/tablesfancy_vr.dmi'
	icon_state = "fancyblack"
// flipped = -1 // KSC = So one can climb tables and walk on them. (Having this on -1 means you can climb this table but unable to walk over an other table tile of the same type)
	can_reinforce = FALSE
	can_plate = FALSE

/obj/structure/table/fancyblack/Initialize(mapload)
	material = get_material_by_name(MAT_FANCYBLACK)
	verbs -= /obj/structure/table/verb/do_flip
	verbs -= /obj/structure/table/proc/do_put

	. = ..()

/obj/structure/table/fancyblack/dismantle(obj/item/tool/wrench/W, mob/user)
	to_chat(user, span_warning("You cannot dismantle \the [src]."))
	return

/obj/structure/table/gold
	icon_state = "plain_preview"
	color = "#FFFF00"

/obj/structure/table/gold/Initialize(mapload)
	material = get_material_by_name(MAT_GOLD)
	. = ..()
