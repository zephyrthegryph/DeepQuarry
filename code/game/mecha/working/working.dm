/obj/mecha/working
	internal_damage_threshold = 60
	max_hull_equip = 1
	max_weapon_equip = 0
	max_utility_equip = 3
	max_universal_equip = 1
	max_special_equip = 1

CAPABILITIES(/obj/mecha/working)
	initial_contents(/obj/item/mecha_parts/mecha_tracking, when = PROC_REF(on_player_level)) // an exosuit made on a player level carries a tracking beacon

/obj/mecha/working/range_action(atom/target as obj|mob|turf)
	return
