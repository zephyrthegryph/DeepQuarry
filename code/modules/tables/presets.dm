//TABLE PRESETS
/obj/structure/table/standard
	plating_id = DEFAULT_TABLE_MATERIAL
	icon_state = "plain_preview"
	color = "#EEEEEE"

/obj/structure/table/steel
	plating_id = MAT_STEEL
	icon_state = "plain_preview"
	color = "#666666"

/obj/structure/table/marble
	plating_id = MAT_MARBLE
	icon_state = "stone_preview"
	color = "#CCCCCC"

/obj/structure/table/reinforced
	plating_id = DEFAULT_TABLE_MATERIAL
	reinforcement_id = MAT_STEEL
	icon_state = "reinf_preview"
	color = "#EEEEEE"

/obj/structure/table/steel_reinforced
	plating_id = MAT_STEEL
	reinforcement_id = MAT_STEEL
	icon_state = "reinf_preview"
	color = "#666666"

/obj/structure/table/wooden_reinforced
	plating_id = MAT_WOOD
	reinforcement_id = MAT_STEEL
	icon_state = "reinf_preview"
	color = "#824B28"

/obj/structure/table/woodentable
	plating_id = MAT_WOOD
	icon_state = "plain_preview"
	color = "#824B28"

/obj/structure/table/sifwoodentable
	plating_id = MAT_SIFWOOD
	icon_state = "plain_preview"
	color = "#0099cc"

/obj/structure/table/sifwooden_reinforced
	plating_id = MAT_SIFWOOD
	reinforcement_id = MAT_STEEL
	icon_state = "reinf_preview"
	color = "#824B28"

/obj/structure/table/hardwoodtable
	plating_id = MAT_HARDWOOD
	icon_state = "stone_preview"
	color = "#42291a"

/obj/structure/table/gamblingtable
	plating_id = MAT_WOOD
	carpeted = TRUE
	icon_state = "gamble_preview"

/obj/structure/table/glass
	plating_id = MAT_GLASS
	icon_state = "plain_preview"
	color = "#00E1FF"
	alpha = 77 // 0.3 * 255

/obj/structure/table/borosilicate
	plating_id = MAT_PGLASS
	icon_state = "plain_preview"
	color = "#4D3EAC"
	alpha = 77

/obj/structure/table/holotable
	plating_id = "holo" + DEFAULT_TABLE_MATERIAL
	icon_state = "holo_preview"
	color = "#EEEEEE"

/obj/structure/table/woodentable/holotable
	plating_id = "holowood"
	icon_state = "holo_preview"

/obj/structure/table/alien
	plating_id = MAT_ALIEN_ALIUM
	name = "alien table"
	desc = "Advanced flat surface technology at work!"
	icon_state = "alien_preview"
	can_reinforce = FALSE
	can_plate = FALSE

/obj/structure/table/alien
	can_flip_verb = FALSE
	can_dismantle = FALSE

//BENCH PRESETS
/obj/structure/table/bench/standard
	plating_id = DEFAULT_TABLE_MATERIAL
	icon_state = "plain_preview"
	color = "#EEEEEE"

/obj/structure/table/bench/steel
	plating_id = MAT_STEEL
	icon_state = "plain_preview"
	color = "#666666"

/obj/structure/table/bench/marble
	plating_id = MAT_MARBLE
	icon_state = "stone_preview"
	color = "#CCCCCC"

/*
/obj/structure/table/bench/reinforced
	icon_state = "reinf_preview"
	color = "#EEEEEE"

/obj/structure/table/bench/steel_reinforced
	icon_state = "reinf_preview"
	color = "#666666"

/obj/structure/table/bench/wooden_reinforced
	icon_state = "reinf_preview"
	color = "#824B28"

*/
/obj/structure/table/bench/wooden
	plating_id = MAT_WOOD
	icon_state = "plain_preview"
	color = "#824B28"

/obj/structure/table/bench/sifwooden
	plating_id = MAT_SIFWOOD
	icon_state = "plain_preview"
	color = "#0099cc"

/obj/structure/table/bench/sifwooden/padded
	icon_state = "padded_preview"
	carpeted = 1

/obj/structure/table/bench/padded
	plating_id = MAT_STEEL
	carpeted = TRUE
	icon_state = "padded_preview"

/obj/structure/table/bench/glass
	plating_id = MAT_GLASS
	icon_state = "plain_preview"
	color = "#00E1FF"
	alpha = 77 // 0.3 * 255

/*
/obj/structure/table/bench/holotable
	icon_state = "holo_preview"
	color = "#EEEEEE"

/obj/structure/table/bench/wooden/holotable
	icon_state = "holo_preview"

*/

/obj/structure/table/bench/glamour
	plating_id = MAT_GLAMOUR
	icon_state = "plain_preview"
	color = "#fffce6"

//new wood types
/obj/structure/table/birch
	plating_id = MAT_BIRCHWOOD
	icon_state = "plain_preview"
	color = "#f6dec0"

/obj/structure/table/pine
	plating_id = MAT_PINEWOOD
	icon_state = "plain_preview"
	color = "#cd9d6f"

/obj/structure/table/oak
	plating_id = MAT_OAKWOOD
	icon_state = "plain_preview"
	color = "#674928"

/obj/structure/table/acacia
	plating_id = MAT_ACACIAWOOD
	icon_state = "plain_preview"
	color = "#b75e12"

/obj/structure/table/redwood
	plating_id = MAT_REDWOOD
	icon_state = "stone_preview"
	color = "#a45a52"

/obj/structure/table/darkglass
	plating_id = MAT_DARKGLASS
	name = "darkglass table"
	desc = "Shiny!"
	icon = 'icons/obj/tables_vr.dmi'
	icon_state = "darkglass_table_preview"
// flipped = -1 // KSC = So one can climb tables and walk on them. (Having this on -1 means you can climb this table but unable to walk over an other table tile of the same type)
	can_reinforce = FALSE
	can_plate = FALSE

/obj/structure/table/darkglass
	can_flip_verb = FALSE
	can_dismantle = FALSE

/obj/structure/table/alien/blue
	icon = 'icons/turf/shuttle_alien_blue.dmi'

/obj/structure/table/fancyblack
	plating_id = MAT_FANCYBLACK
	name = "fancy table"
	desc = "Cloth!"
	icon = 'icons/obj/tablesfancy_vr.dmi'
	icon_state = "fancyblack"
// flipped = -1 // KSC = So one can climb tables and walk on them. (Having this on -1 means you can climb this table but unable to walk over an other table tile of the same type)
	can_reinforce = FALSE
	can_plate = FALSE

/obj/structure/table/fancyblack
	can_flip_verb = FALSE
	can_dismantle = FALSE

/obj/structure/table/gold
	plating_id = MAT_GOLD
	icon_state = "plain_preview"
	color = "#FFFF00"

