// The hand provider of the mobs that act with their hands in the world: a human (any species) and a cyborg. The engine has no hand provider of its own on
// /mob/living (code/engine/parts/provider.dm), so a mob type declares its own; the implicit req_capable() of a physical binding already refuses a
// stunned, restrained or dead actor, and the reach gate refuses a target out of arm's reach.

CAPABILITIES(/mob/living/carbon/human)
	hands()
	owns_one(nameof(character_forms), /datum/forms)
	owns_one(nameof(vessel), /datum/reagents)
	owns_one(nameof(xenochimera), /datum/xenochimera)
	owns_many(nameof(genetic_side_effects), /datum/genetics/side_effect)
	owns_many(nameof(side_effects), /datum/medical_effect)
	owns_many(nameof(teleporters))

CAPABILITIES(/mob/living/silicon/robot)
	hands()
	provides(AFF_CONTROL, reach = BORG_INTERFACE_REACH, authority = AUTH_REMOTE_ACCESS)
	owns_one(nameof(camera), /obj/machinery/camera)
	owns_one(nameof(communicator), /obj/item/communicator/integrated)
	owns_one(nameof(decal_control), /datum/tgui_module/robot_ui_decals)
	owns_one(nameof(module), /obj/item/robot_module)
	owns_one(nameof(radio), /obj/item/radio/borg)
	owns_one(nameof(rbPDA), /obj/item/pda/ai)
	owns_one(nameof(robot_belly), /datum/robot_belly)
	owns_one(nameof(robot_modules_background), /atom/movable/screen)
	owns_one(nameof(bolt), /obj/item/implant/restrainingbolt)
	owns_many(nameof(components))
