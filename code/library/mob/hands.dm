// The providers of the mobs that act in the world: a human (any species) has hands; a cyborg has its chassis manipulators, its selected gripper
// (robot_simple_items.dm: preferred, and what it carries is the held item) and its interface for the remote controls (remote_interface(),
// library/mob/silicon.dm). The engine has no hand provider of its own on /mob/living (code/engine/parts/provider.dm), so a mob
// type declares its own; the implicit req_capable() of a physical binding already refuses a stunned, restrained or dead actor, and the reach gate
// refuses a target out of arm's reach.

CAPABILITIES(/mob/living/carbon/human)
	hands()
	body_clock(STAT_BODY_CLOCK_ACTIVE)
	limb_clock(STAT_LIMB_TROUBLE)
	organ_clock(STAT_ORGANS_ACTIVE)
	pain_clock(STAT_PAIN_FELT)
	surgery_ops()
	owns_one(nameof(character_forms), /datum/forms)
	owns_one(nameof(vessel), /datum/reagents)
	owns_one(nameof(xenochimera), /datum/xenochimera)
	owns_many(nameof(genetic_side_effects), /datum/genetics/side_effect)
	owns_many(nameof(side_effects), /datum/medical_effect)
	owns_many(nameof(teleporters))
	owns_one(nameof(crafting), starts = /datum/personal_crafting)
	param(nameof(species_at_make), pos = 1)

CAPABILITIES(/mob/living/silicon/robot)
	remote_interface(reach = BORG_INTERFACE_REACH)
	// Its chassis manipulators: what a cyborg with no gripper selected still does by touch (a closet, a bulb, its own modules). 16.8 gives a cyborg
	// no hands of its own; that waits until every module set has a gripper. A selected gripper is preferred over these (held_carrier()).
	hands()
	// an opened chassis gives up its cell (or the fried remains of its mount) to whatever hand takes it: a person's, another cyborg's gripper
	op("take_power_part", hand(), when(TYPE_PROC_REF(/mob/living/silicon/robot, power_part_exposed)), label("Remove the cell"),
		priority(OP_PRIORITY_TAKE_OUT), wait(0), then(TYPE_PROC_REF(/mob/living/silicon/robot, power_part_taken)))
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
	owns_one(nameof(robotact), starts = /datum/tgui_module/robot_ui)
	space(SPACE_PANEL, door = nameof(wiresexposed))
	wires(name = "Cyborg", count = 5, randomize = TRUE, tools = FALSE, status_lines = PROC_REF(wire_lights))
	on_wire(WIRE_BORG_LAWCHECK, cut = PROC_REF(lawcheck_wire_cut))
	on_wire(WIRE_AI_CONTROL, cut = PROC_REF(ai_wire_cut), pulse = PROC_REF(ai_wire_pulsed))
	on_wire(WIRE_BORG_CAMERA, cut = PROC_REF(camera_wire_cut), pulse = PROC_REF(camera_wire_pulsed))
	on_wire(WIRE_BORG_LOCKED, cut = PROC_REF(lockdown_wire_cut), pulse = PROC_REF(lockdown_wire_pulsed))
