/mob/living/silicon/robot/syndicate
	lawupdate = FALSE
	scrambledcodes = TRUE
	emagged = TRUE
	modtype = "Syndicate"
	lawchannel = "State"
	braintype = "Drone"
	ui_theme = "syndicate"
	cell_type = /obj/item/cell/robot_syndi // 25k cell, because Antag.

/mob/living/silicon/robot/syndicate/setup_radio()
	..()
	own_set(radio, "keyslot", new /obj/item/encryptionkey/syndicate(radio))
	radio.recalculateChannels()

/mob/living/silicon/robot/syndicate/setup_brain()
	..()
	own_set(src, "mmi", new /obj/item/mmi/digital/robot(src)) // Explicitly a drone.
	updatename(modtype)
	play_sfx(src, SFX_MECHA_NOMINALSYNDI)

/mob/living/silicon/robot/syndicate/setup_laws()
	..()
	own_set(src, "laws", new /datum/ai_laws/syndicate_override())

/mob/living/silicon/robot/syndicate/setup_module()
	..()
	if(!restrict_modules_to)
		restrict_modules_to = GLOB.antag_module_types

/mob/living/silicon/robot/syndicate/protector/setup_module()
	..()
	own_set(src, "module", new /obj/item/robot_module/robot/syndicate/protector(src))
	modtype = "Protector"
	restrict_modules_to = list("Protector")

/mob/living/silicon/robot/syndicate/mechanist/setup_module()
	..()
	own_set(src, "module", new /obj/item/robot_module/robot/syndicate/mechanist(src))
	modtype = "Mechanist"
	restrict_modules_to = list("Mechanist")

/mob/living/silicon/robot/syndicate/combat_medic/setup_module()
	..()
	own_set(src, "module", new /obj/item/robot_module/robot/syndicate/combat_medic(src))
	modtype = "Combat Medic"
	restrict_modules_to = list("Combat Medic")

/mob/living/silicon/robot/syndicate/ninja/setup_module()
	..()
	own_set(src, "module", new /obj/item/robot_module/robot/syndicate/ninja(src))
	modtype = "Ninja"
	restrict_modules_to = list("Ninja")

/mob/living/silicon/robot/syndicate/speech_bubble_appearance()
	return "synthetic_evil"
