/obj/mecha/medical
	max_hull_equip = 1
	max_weapon_equip = 0
	max_utility_equip = 2
	max_universal_equip = 1
	max_special_equip = 1

	stomp_sound = 'sound/mecha/mechmove01.ogg'

	cargo_capacity = 1

TYPE_TABLE(/obj/mecha/medical, mecha_starting_components, list( \
		/obj/item/mecha_parts/component/hull, \
		/obj/item/mecha_parts/component/actuator, \
		/obj/item/mecha_parts/component/armor/lightweight, \
		/obj/item/mecha_parts/component/gas, \
		/obj/item/mecha_parts/component/electrical \
		))


// ALLOW(init/INSTANCE_STATE): an exosuit made on a player level carries a tracking beacon
/obj/mecha/medical/Initialize(mapload)
	. = ..()
	var/turf/T = get_turf(src)
	if(isPlayerLevel(T.z))
		new /obj/item/mecha_parts/mecha_tracking(src)

