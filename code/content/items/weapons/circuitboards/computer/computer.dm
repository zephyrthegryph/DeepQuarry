#ifndef T_BOARD
#error T_BOARD macro is not defined but we need it!
#endif

/obj/item/circuitboard/med_data
	name = T_BOARD("medical records console")
	build_path = /obj/machinery/computer/med_data

/obj/item/circuitboard/med_data/pcu
	name = T_BOARD("medical records PCU")
	build_path = /obj/machinery/computer/med_data/laptop

/obj/item/circuitboard/card
	name = T_BOARD("ID card modification console")
	build_path = /obj/machinery/computer/card

/obj/item/circuitboard/card/centcom
	name = T_BOARD("CentCom ID card modification console")
	build_path = /obj/machinery/computer/card/centcom
	hidden = TRUE // Mapper only centcom machine

/obj/item/circuitboard/skills/pcu
	name = T_BOARD("department management console")
	build_path = /obj/machinery/computer/skills // this needs to be fixed someday, a pcu subtype needs to be made, but it affects all maps...

/obj/item/circuitboard/arcade/battle
	name = T_BOARD("battle arcade machine")
	build_path = /obj/machinery/computer/arcade/battle

/obj/item/circuitboard/arcade/orion_trail
	name = T_BOARD("orion trail arcade machine")
	build_path = /obj/machinery/computer/arcade/orion_trail

/obj/item/circuitboard/arcade/clawmachine
	name = T_BOARD("grab-a-gift arcade machine")
	build_path = /obj/machinery/computer/arcade/clawmachine

/obj/item/circuitboard/engine
	name = T_BOARD("engine control console")
	build_path = /obj/machinery/computer/ship/engines
	hidden = TRUE // todo - Make properly constructable in round

/obj/item/circuitboard/nav
	name = T_BOARD("navigation console")
	build_path = /obj/machinery/computer/ship/navigation
	hidden = TRUE // todo - Make properly constructable in round

/obj/item/circuitboard/nav/tele
	name = T_BOARD("navigation telescreen")
	build_path = /obj/machinery/computer/ship/navigation/telescreen
	hidden = TRUE // todo - Make properly constructable in round
