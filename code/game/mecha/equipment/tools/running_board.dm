// concept borrowed from vgstation-coders/vgstation13#26316 on GitHub
/obj/item/mecha_parts/mecha_equipment/runningboard
	name = "hacked powered exosuit running board"
	desc = "A running board with a power-lifter attachment, to quickly catapult exosuit pilots into the cockpit. Fits any exosuit."
	icon_state = "mecha_runningboard"
	equip_type = EQUIP_HULL

/obj/item/mecha_parts/mecha_equipment/runningboard/limited
	name = "powered exosuit running board"
	desc = "A running board with a power-lifter attachment, to quickly catapult exosuit pilots into the cockpit. Only fits to working exosuits."

MSG_DEF_SELF(mecha/working_only, "It only fits working exosuits.")

/obj/item/mecha_parts/mecha_equipment/runningboard/limited/attach_refusal(obj/mecha/M)
	if(!istype(M, /obj/mecha/working)) // is this a ripley?
		return /datum/msg/mecha/working_only
	return ..()
