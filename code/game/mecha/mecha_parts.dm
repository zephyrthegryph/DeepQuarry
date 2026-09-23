/////////////////////////
////// Mecha Parts //////
/////////////////////////

// Mecha circuitboards can be found in /code/game/objects/items/weapons/circuitboards/mecha.dm

/obj/item/mecha_parts
	name = "mecha part"
	icon = 'icons/mecha/mech_construct.dmi'
	icon_state = "blank"
	w_class = ITEMSIZE_HUGE


/obj/item/mecha_parts/chassis
	name="Mecha Chassis"
	icon_state = "backbone"
	/// "p<bitmask>" during the parts phase, "R<n>" on the reversible ladder. See construction_graph/mecha.
	var/construction_state = "p0"

/obj/item/mecha_parts/chassis/attack_hand()
	return

/////////// Ripley

/obj/item/mecha_parts/chassis/ripley
	name = "Ripley Chassis"
	construction_graph = /datum/construction_graph/mecha/ripley

/obj/item/mecha_parts/part/ripley_torso
	name="Ripley Torso"
	desc="A torso part of Ripley APLU. Contains power unit, processing core and life support systems."
	icon_state = "ripley_harness"

/obj/item/mecha_parts/part/ripley_left_arm
	name="Ripley Left Arm"
	desc="A Ripley APLU left arm. Data and power sockets are compatible with most exosuit tools."
	icon_state = "ripley_l_arm"

/obj/item/mecha_parts/part/ripley_right_arm
	name="Ripley Right Arm"
	desc="A Ripley APLU right arm. Data and power sockets are compatible with most exosuit tools."
	icon_state = "ripley_r_arm"

/obj/item/mecha_parts/part/ripley_left_leg
	name="Ripley Left Leg"
	desc="A Ripley APLU left leg. Contains somewhat complex servodrives and balance maintaining systems."
	icon_state = "ripley_l_leg"

/obj/item/mecha_parts/part/ripley_right_leg
	name="Ripley Right Leg"
	desc="A Ripley APLU right leg. Contains somewhat complex servodrives and balance maintaining systems."
	icon_state = "ripley_r_leg"

///////// Gygax

/obj/item/mecha_parts/chassis/gygax
	name = "Gygax Chassis"
	construction_graph = /datum/construction_graph/mecha/gygax

/obj/item/mecha_parts/part/gygax_torso
	name="Gygax Torso"
	desc="A torso part of Gygax. Contains power unit, processing core and life support systems. Has an additional equipment slot."
	icon_state = "gygax_harness"

/obj/item/mecha_parts/part/gygax_head
	name="Gygax Head"
	desc="A Gygax head. Houses advanced surveilance and targeting sensors."
	icon_state = "gygax_head"

/obj/item/mecha_parts/part/gygax_left_arm
	name="Gygax Left Arm"
	desc="A Gygax left arm. Data and power sockets are compatible with most exosuit tools and weapons."
	icon_state = "gygax_l_arm"

/obj/item/mecha_parts/part/gygax_right_arm
	name="Gygax Right Arm"
	desc="A Gygax right arm. Data and power sockets are compatible with most exosuit tools and weapons."
	icon_state = "gygax_r_arm"

/obj/item/mecha_parts/part/gygax_left_leg
	name="Gygax Left Leg"
	icon_state = "gygax_l_leg"

/obj/item/mecha_parts/part/gygax_right_leg
	name="Gygax Right Leg"
	icon_state = "gygax_r_leg"

/obj/item/mecha_parts/part/gygax_armour
	name="Gygax Armour Plates"
	icon_state = "gygax_armour"

////////// Serenity

/obj/item/mecha_parts/chassis/serenity
	name = "Serenity Chassis"
	construction_graph = /datum/construction_graph/mecha/serenity

//////////// Durand

/obj/item/mecha_parts/chassis/durand
	name = "Durand Chassis"
	construction_graph = /datum/construction_graph/mecha/durand

/obj/item/mecha_parts/part/durand_torso
	name="Durand Torso"
	icon_state = "durand_harness"

/obj/item/mecha_parts/part/durand_head
	name="Durand Head"
	icon_state = "durand_head"

/obj/item/mecha_parts/part/durand_left_arm
	name="Durand Left Arm"
	icon_state = "durand_l_arm"

/obj/item/mecha_parts/part/durand_right_arm
	name="Durand Right Arm"
	icon_state = "durand_r_arm"

/obj/item/mecha_parts/part/durand_left_leg
	name="Durand Left Leg"
	icon_state = "durand_l_leg"

/obj/item/mecha_parts/part/durand_right_leg
	name="Durand Right Leg"
	icon_state = "durand_r_leg"

/obj/item/mecha_parts/part/durand_armour
	name="Durand Armour Plates"
	icon_state = "durand_armour"

////////// Firefighter

/obj/item/mecha_parts/chassis/firefighter
	name = "Firefighter Chassis"
	construction_graph = /datum/construction_graph/mecha/firefighter
/*
/obj/item/mecha_parts/part/firefighter_torso
	name="Ripley-on-Fire Torso"
	icon_state = "ripley_harness"

/obj/item/mecha_parts/part/firefighter_left_arm
	name="Ripley-on-Fire Left Arm"
	icon_state = "ripley_l_arm"

/obj/item/mecha_parts/part/firefighter_right_arm
	name="Ripley-on-Fire Right Arm"
	icon_state = "ripley_r_arm"

/obj/item/mecha_parts/part/firefighter_left_leg
	name="Ripley-on-Fire Left Leg"
	icon_state = "ripley_l_leg"

/obj/item/mecha_parts/part/firefighter_right_leg
	name="Ripley-on-Fire Right Leg"
	icon_state = "ripley_r_leg"
*/

////////// Phazon

/obj/item/mecha_parts/chassis/phazon
	name = "Phazon Chassis"
	construction_graph = /datum/construction_graph/mecha/phazon

/obj/item/mecha_parts/part/phazon_torso
	name="Phazon Torso"
	icon_state = "phazon_harness"
	//construction_time = 300
	//construction_cost = list(MAT_STEEL=35000,MAT_GLASS=10000,MAT_PHORON=20000)

/obj/item/mecha_parts/part/phazon_head
	name="Phazon Head"
	icon_state = "phazon_head"
	//construction_time = 200
	//construction_cost = list(MAT_STEEL=15000,MAT_GLASS=5000,MAT_PHORON=10000)

/obj/item/mecha_parts/part/phazon_left_arm
	name="Phazon Left Arm"
	icon_state = "phazon_l_arm"
	//construction_time = 200
	//construction_cost = list(MAT_STEEL=20000,MAT_PHORON=10000)

/obj/item/mecha_parts/part/phazon_right_arm
	name="Phazon Right Arm"
	icon_state = "phazon_r_arm"
	//construction_time = 200
	//construction_cost = list(MAT_STEEL=20000,MAT_PHORON=10000)

/obj/item/mecha_parts/part/phazon_left_leg
	name="Phazon Left Leg"
	icon_state = "phazon_l_leg"
	//construction_time = 200
	//construction_cost = list(MAT_STEEL=20000,MAT_PHORON=10000)

/obj/item/mecha_parts/part/phazon_right_leg
	name="Phazon Right Leg"
	icon_state = "phazon_r_leg"
	//construction_time = 200
	//construction_cost = list(MAT_STEEL=20000,MAT_PHORON=10000)

///////// Odysseus


/obj/item/mecha_parts/chassis/odysseus
	name = "Odysseus Chassis"
	construction_graph = /datum/construction_graph/mecha/odysseus

/obj/item/mecha_parts/part/odysseus_head
	name="Odysseus Head"
	icon_state = "odysseus_head"

/obj/item/mecha_parts/part/odysseus_torso
	name="Odysseus Torso"
	desc="A torso part of Odysseus. Contains power unit, processing core and life support systems."
	icon_state = "odysseus_torso"

/obj/item/mecha_parts/part/odysseus_left_arm
	name="Odysseus Left Arm"
	desc="An Odysseus left arm. Data and power sockets are compatible with most exosuit tools."
	icon_state = "odysseus_l_arm"

/obj/item/mecha_parts/part/odysseus_right_arm
	name="Odysseus Right Arm"
	desc="An Odysseus right arm. Data and power sockets are compatible with most exosuit tools."
	icon_state = "odysseus_r_arm"

/obj/item/mecha_parts/part/odysseus_left_leg
	name="Odysseus Left Leg"
	desc="An Odysseus left leg. Contains somewhat complex servodrives and balance maintaining systems."
	icon_state = "odysseus_l_leg"

/obj/item/mecha_parts/part/odysseus_right_leg
	name="Odysseus Right Leg"
	desc="A Odysseus right leg. Contains somewhat complex servodrives and balance maintaining systems."
	icon_state = "odysseus_r_leg"

/*/obj/item/mecha_parts/part/odysseus_armour
	name="Odysseus Carapace"
	icon_state = "odysseus_armour"
	construction_time = 200
	construction_cost = list(MAT_STEEL=15000)*/

////////// Janus

/obj/item/mecha_parts/chassis/janus
	name = "Janus Chassis"
	construction_graph = /datum/construction_graph/mecha/janus

/obj/item/mecha_parts/part/janus_torso
	name="Imperion Torso"
	icon_state = "janus_harness"
/obj/item/mecha_parts/part/janus_head
	name="Imperion Head"
	icon_state = "janus_head"

/obj/item/mecha_parts/part/janus_left_arm
	name="Prototype Gygax Left Arm"
	icon_state = "janus_l_arm"

/obj/item/mecha_parts/part/janus_right_arm
	name="Prototype Gygax Right Arm"
	icon_state = "janus_r_arm"

/obj/item/mecha_parts/part/janus_left_leg
	name="Prototype Durand Left Leg"
	icon_state = "janus_l_leg"

/obj/item/mecha_parts/part/janus_right_leg
	name="Prototype Durand Right Leg"
	icon_state = "janus_r_leg"


///Fighters///


/obj/item/mecha_parts/fighter
	icon = 'icons/mecha/fighters_construct64x64.dmi'

/obj/item/mecha_parts/fighter/chassis
	name="Fighter Chassis"
	icon_state = "backbone"
	/// "p<bitmask>" during the parts phase, "R<n>" on the reversible ladder. See construction_graph/mecha.
	var/construction_state = "p0"

/obj/item/mecha_parts/fighter/chassis/attack_hand(mob/user, list/params)
	return


//! Pinnace

/obj/item/mecha_parts/fighter/chassis/pinnace
	name = "\improper Pinnace Chassis"
	icon_state = "pinnace_chassis"
	construction_graph = /datum/construction_graph/mecha/fighter/pinnace

/obj/item/mecha_parts/fighter/part/pinnace_core
	name="\improper Pinnace Core"
	icon_state = "pinnace_core"

/obj/item/mecha_parts/fighter/part/pinnace_cockpit
	name="\improper Pinnace Cockpit"
	icon_state = "pinnace_cockpit"

/obj/item/mecha_parts/fighter/part/pinnace_left_wing
	name="\improper Pinnace Left Wing"
	icon_state = "pinnace_l_wing"

/obj/item/mecha_parts/fighter/part/pinnace_right_wing
	name="\improper Pinnace Right Wing"
	icon_state = "pinnace_r_wing"

/obj/item/mecha_parts/fighter/part/pinnace_main_engine
	name="\improper Pinnace Main Engine"
	icon_state = "pinnace_m_engine"

/obj/item/mecha_parts/fighter/part/pinnace_left_engine
	name="\improper Pinnace Left Engine"
	icon_state = "pinnace_l_engine"

/obj/item/mecha_parts/fighter/part/pinnace_right_engine
	name="\improper Pinnace Right Engine"
	icon_state = "pinnace_r_engine"

//! Baron

/obj/item/mecha_parts/fighter/chassis/baron
	name = "\improper Baron Chassis"
	icon_state = "baron_chassis"
	construction_graph = /datum/construction_graph/mecha/fighter/baron


/obj/item/mecha_parts/fighter/part/baron_core
	name="\improper Baron Core"
	icon_state = "baron_core"

/obj/item/mecha_parts/fighter/part/baron_cockpit
	name="\improper Baron Cockpit"
	icon_state = "baron_cockpit"

/obj/item/mecha_parts/fighter/part/baron_left_wing
	name="\improper Baron Left Wing"
	icon_state = "baron_l_wing"

/obj/item/mecha_parts/fighter/part/baron_right_wing
	name="\improper Baron Right Wing"
	icon_state = "baron_r_wing"

/obj/item/mecha_parts/fighter/part/baron_main_engine
	name="\improper Baron Main Engine"
	icon_state = "baron_m_engine"

/obj/item/mecha_parts/fighter/part/baron_left_engine
	name="\improper Baron Left Engine"
	icon_state = "baron_l_engine"

/obj/item/mecha_parts/fighter/part/baron_right_engine
	name="\improper Baron Right Engine"
	icon_state = "baron_r_engine"


/obj/item/mecha_parts/chassis/scarab
	name = "Scarab Chassis"
	icon = 'icons/mecha/mech_construct_ch.dmi'
	icon_state = "scarab_chassis"
	construction_graph = /datum/construction_graph/mecha/scarab

/obj/item/mecha_parts/part/scarab_torso
	name="Scarab Torso"
	desc="A torso part of Scarab. Contains power unit, processing core and life support systems."
	icon = 'icons/mecha/mech_construct_ch.dmi'
	icon_state = "scarab_torso"

/obj/item/mecha_parts/part/scarab_head
	name="Scarab Head"
	desc="A Scarab head. Houses advanced surveilance and target marking equipment."
	icon = 'icons/mecha/mech_construct_ch.dmi'
	icon_state = "scarab_head"

/obj/item/mecha_parts/part/scarab_left_arm
	name="Scarab Left Arm"
	desc="A Scarab left arm. Data and power sockets are compatible with most exosuit tools and weapons."
	icon = 'icons/mecha/mech_construct_ch.dmi'
	icon_state = "scarab_l_arm"

/obj/item/mecha_parts/part/scarab_right_arm
	name="Scarab Right Arm"
	desc="A Scarab right arm. Data and power sockets are compatible with most exosuit tools and weapons."
	icon = 'icons/mecha/mech_construct_ch.dmi'
	icon_state = "scarab_r_arm"

/obj/item/mecha_parts/part/scarab_left_legs
	name="Scarab Left Legs"
	desc="A powerful, yet lightweight, pair of legs."
	icon = 'icons/mecha/mech_construct_ch.dmi'
	icon_state = "scarab_l_legs"

/obj/item/mecha_parts/part/scarab_right_legs
	name="Scarab Right Legs"
	desc="A powerful, yet lightweight, pair of legs."
	icon = 'icons/mecha/mech_construct_ch.dmi'
	icon_state = "scarab_r_legs"


/obj/item/mecha_parts/chassis/hades
	name = "Hades Chassis"
	construction_graph = /datum/construction_graph/mecha/hades

/obj/item/mecha_parts/part/hades_torso
	name="Hades Torso"
	icon_state = "janus_harness"

/obj/item/mecha_parts/part/hades_head
	name="Hades Head"
	icon_state = "janus_head"

/obj/item/mecha_parts/part/hades_left_arm
	name="Hades Left Arm"
	icon_state = "janus_l_arm"

/obj/item/mecha_parts/part/hades_right_arm
	name="Hades Right Arm"
	icon_state = "janus_r_arm"

/obj/item/mecha_parts/part/hades_left_leg
	name="Hades Left Leg"
	icon_state = "janus_l_leg"

/obj/item/mecha_parts/part/hades_right_leg
	name="Prototype Durand Right Leg"
	icon_state = "janus_r_leg"

/obj/item/circuitboard/mecha/hades/targeting
	name = "stange targeting circuit"

/obj/item/circuitboard/mecha/hades/peripherals
	name = "stange peripheral circuit"

/obj/item/circuitboard/mecha/hades/main
	name = "stange control circuit"
