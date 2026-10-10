// The providers of the mobs that act in the world: a human (any species) has hands; a cyborg has its chassis manipulators, its selected gripper
// (robot_simple_items.dm: preferred, and what it carries is the held item) and its interface for the remote controls (remote_interface(),
// library/mob/silicon.dm). The engine has no hand provider of its own on /mob/living (code/engine/parts/provider.dm), so a mob
// type declares its own; the implicit req_capable() of a physical binding already refuses a stunned, restrained or dead actor, and the reach gate
// refuses a target out of arm's reach.

CAPABILITIES(/mob/living/carbon/human)
	emag(then(PROC_REF(on_emag)), repeatable = TRUE, powered = FALSE)
	op("vr_transform", menu(), when(PROC_REF(vr_transform_granted)), label("Transform Into Creature"), needs(req_self(), req_capable()), asks(/datum/prompt/choice, fields = list("title" = "Mob list", "question" = "Please select a creature:", "choices" = computed(PROC_REF(vr_creature_options)), "ask_flags" = ASK_CONSCIOUS, "timeout" = 0), step = "creature"), then(PROC_REF(vr_creature_chosen)))
	op("vr_logout", menu(), when(PROC_REF(vr_logout_granted)), label("Log Out Of Virtual Reality"), needs(req_self()), asks(/datum/prompt/yes_no, fields = list("title" = "Log out?", "question" = "Would you like to log out of virtual reality?", "timeout" = 0), step = "logout"), then(PROC_REF(fake_exit_vr_answered)))
	// Species and trait abilities (the verbs stay the player's entry; the work is the op).
	op("regenerate", ai(), needs(req(PROC_REF(regenerate_fed), because = MSG(human/regen_hungry)), req(PROC_REF(regenerate_idle), because = MSG(human/regen_active))), starts(PROC_REF(regenerate_started)), begins(MSG(human/regen_begins)), wait(PROC_REF(regenerate_time)), on_interrupt(PROC_REF(regenerate_human_failed)), then(PROC_REF(regenerate_human_done)))
	op("enter_cocoon", ai(), needs(req(PROC_REF(cocoon_has_space), because = MSG(human/cocoon_no_space)), req(PROC_REF(cocoon_fit), because = MSG(human/cocoon_state))), wait(2.5 SECONDS), then(PROC_REF(enter_cocoon_human_done)))
	op("check_pulse", menu(), label("Check pulse"), needs(req_capable()), starts(PROC_REF(check_pulse_started)), begins(PROC_REF(check_pulse_begins)), wait(6 SECONDS), on_interrupt(PROC_REF(check_pulse_human_failed)), then(PROC_REF(check_pulse_human_done)))
	// Pressure on a bleeding limb is held until the user lets go (the hand changes or they move): wait_until() with no end of its own.
	op("apply_pressure", ai(), reach(REACH_ADJACENT), takes("zone", "hand"), starts(PROC_REF(pressure_started)), wait_until(until = PROC_REF(pressure_hand_changed)), on_interrupt(PROC_REF(pressure_released)), then(PROC_REF(pressure_released)))
	// Licking wounds clean: a lap per wound, as long as the wound is bad (lick_wounds.dm); standing still is the only thing it keeps.
	op("lick_wounds", ai(), takes("patient", "limb"), wait(PROC_REF(lick_time), repeats = PROC_REF(lick_more), after_step = PROC_REF(lick_done)), on_interrupt(PROC_REF(lick_interrupted)))
	// Loosening a cinched tourniquet (tourniquet.dm): the actor stays next to the wearer for the two seconds it takes.
	op("loosen_tourniquet", ai(), reach(REACH_ADJACENT), takes("limb"), begins(PROC_REF(loosen_tourniquet_begins)), wait(TOURNIQUET_REMOVE_TIME), then(PROC_REF(loosen_tourniquet_done)))
	// Devouring from the water: the victim is picked, then kept for the five seconds it takes to drag them under; if they get away it fails.
	op("underwater_devour", ai(), asks(/datum/prompt/choice/victim/underwater, fields = list("choices" = computed(PROC_REF(underwater_devour_choices))), step = "victim", keeps_answer = TRUE),
		starts(PROC_REF(underwater_devour_started)), wait(5 SECONDS, keeps = STAY | TARGET_PRESENT | ALIVE), on_interrupt(PROC_REF(underwater_devour_escaped)), then(PROC_REF(underwater_devour_human_done)))
	op("lleill_ring_spawn", ai(), wait(10 SECONDS), on_interrupt(PROC_REF(lleill_ring_interrupted)), then(PROC_REF(lleill_ring_spawn_done)))
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
	// Stripping (stripping.dm): the inventory panel's handle_strip() starts these by key; the stripper has to stay next to them and keep what is in hand.
	op("strip_pockets", ai(), begins(MSG(strip/pockets)), wait(HUMAN_STRIP_DELAY), then(PROC_REF(strip_pockets_done)))
	op("strip_splints", ai(), begins(MSG(strip/splints)), wait(HUMAN_STRIP_DELAY), then(PROC_REF(strip_splints_done)))
	op("strip_sensors", ai(), begins(MSG(strip/sensors)), wait(HUMAN_STRIP_DELAY), then(PROC_REF(strip_sensors_done)))
	op("strip_internals", ai(), begins(MSG(strip/internals)), wait(HUMAN_STRIP_DELAY), then(PROC_REF(strip_internals_done)))
	op("strip_tie", ai(), begins(PROC_REF(strip_tie_text)), wait(HUMAN_STRIP_DELAY), then(PROC_REF(strip_tie_done)))
	// one op per slot the strip menu works on (strip_slot_ids() in stripping.dm names the same set; the key is "strip_" and the slot id)
	op("strip_hand_l", ai(), begins(PROC_REF(strip_slot_text)), wait(HUMAN_STRIP_DELAY), then(PROC_REF(strip_slot_done)))
	op("strip_hand_r", ai(), begins(PROC_REF(strip_slot_text)), wait(HUMAN_STRIP_DELAY), then(PROC_REF(strip_slot_done)))
	op("strip_back", ai(), begins(PROC_REF(strip_slot_text)), wait(HUMAN_STRIP_DELAY), then(PROC_REF(strip_slot_done)))
	op("strip_belt", ai(), begins(PROC_REF(strip_slot_text)), wait(HUMAN_STRIP_DELAY), then(PROC_REF(strip_slot_done)))
	op("strip_pocket_l", ai(), begins(PROC_REF(strip_slot_text)), wait(HUMAN_STRIP_DELAY), then(PROC_REF(strip_slot_done)))
	op("strip_pocket_r", ai(), begins(PROC_REF(strip_slot_text)), wait(HUMAN_STRIP_DELAY), then(PROC_REF(strip_slot_done)))
	op("strip_uniform", ai(), begins(PROC_REF(strip_slot_text)), wait(HUMAN_STRIP_DELAY), then(PROC_REF(strip_slot_done)))
	op("strip_suit", ai(), begins(PROC_REF(strip_slot_text)), wait(HUMAN_STRIP_DELAY), then(PROC_REF(strip_slot_done)))
	op("strip_suit_storage", ai(), begins(PROC_REF(strip_slot_text)), wait(HUMAN_STRIP_DELAY), then(PROC_REF(strip_slot_done)))
	op("strip_head", ai(), begins(PROC_REF(strip_slot_text)), wait(HUMAN_STRIP_DELAY), then(PROC_REF(strip_slot_done)))
	op("strip_mask", ai(), begins(PROC_REF(strip_slot_text)), wait(HUMAN_STRIP_DELAY), then(PROC_REF(strip_slot_done)))
	op("strip_eyes", ai(), begins(PROC_REF(strip_slot_text)), wait(HUMAN_STRIP_DELAY), then(PROC_REF(strip_slot_done)))
	op("strip_ear_l", ai(), begins(PROC_REF(strip_slot_text)), wait(HUMAN_STRIP_DELAY), then(PROC_REF(strip_slot_done)))
	op("strip_ear_r", ai(), begins(PROC_REF(strip_slot_text)), wait(HUMAN_STRIP_DELAY), then(PROC_REF(strip_slot_done)))
	op("strip_gloves", ai(), begins(PROC_REF(strip_slot_text)), wait(HUMAN_STRIP_DELAY), then(PROC_REF(strip_slot_done)))
	op("strip_shoes", ai(), begins(PROC_REF(strip_slot_text)), wait(HUMAN_STRIP_DELAY), then(PROC_REF(strip_slot_done)))
	op("strip_id", ai(), begins(PROC_REF(strip_slot_text)), wait(HUMAN_STRIP_DELAY), then(PROC_REF(strip_slot_done)))
	op("strip_handcuffed", ai(), begins(PROC_REF(strip_slot_text)), wait(HUMAN_STRIP_DELAY), then(PROC_REF(strip_slot_done)))
	op("strip_legcuffed", ai(), begins(PROC_REF(strip_slot_text)), wait(HUMAN_STRIP_DELAY), then(PROC_REF(strip_slot_done)))
	// Resisting a straight jacket or shibari (human_resist.dm), and a shank twisted from an aggressive grab (human_defense.dm).
	op("jacket_escape", ai(), begins(PROC_REF(jacket_escape_text)), wait(PROC_REF(jacket_breakout_time)), then(PROC_REF(jacket_escape_done)))
	op("jacket_rip", ai(), begins(PROC_REF(jacket_rip_text)), wait(20 SECONDS), then(PROC_REF(jacket_rip_done)))
	op("shank_twist", ai(), begins(PROC_REF(shank_twist_text)), wait(2 SECONDS), then(PROC_REF(shank_attack_human_done)))
	// CPR, abdominal thrusts and a joint lock from a neck grab (human_attackhand.dm): attack_hand_help_intent() / grab_joint() start them by key.
	op("cpr", ai(), begins(MSG(cpr/begin)), wait(3 SECONDS), then(PROC_REF(cpr_done)))
	op("heimlich", ai(), begins(MSG(heimlich/begin)), wait(2 SECONDS), then(PROC_REF(perform_heimlich_human_done)))
	op("joint_dislocate", ai(), begins(PROC_REF(joint_dislocate_text)), wait(10 SECONDS), then(PROC_REF(grab_joint_human_done)))

CAPABILITIES(/mob/living/silicon/robot)
	emag(then(PROC_REF(on_emag)), repeatable = TRUE, powered = FALSE)
	on_change(nameof(sprite_datum), ANY, then(PROC_REF(sprite_changed)))
	every(0.8 SECONDS, then(PROC_REF(transform_animation_sounds)), when = nameof(transform_sounds_left))
	remote_interface(reach = BORG_INTERFACE_REACH)
	// Its chassis manipulators: what a cyborg with no gripper selected still does by touch (a closet, a bulb, its own modules). 16.8 gives a cyborg
	// no hands of its own; that waits until every module set has a gripper. A selected gripper is preferred over these (held_carrier()).
	hands()
	robot_interactions() // robot.dm: its item, tool and touch ops
	// an opened chassis gives up its cell (or the fried remains of its mount) to whatever hand takes it: a person's, another cyborg's gripper
	op("take_power_part", hand(), when(req_empty_hand()), when(TYPE_PROC_REF(/mob/living/silicon/robot, power_part_exposed)), label("Remove the cell"),
		priority(OP_PRIORITY_TAKE_OUT), wait(0), then(TYPE_PROC_REF(/mob/living/silicon/robot, power_part_taken)))
	// a cyborg clicking itself drops its hat; breaking its restraining bolt is the resist verb's work and ignores a stun, so it is not a physical binding
	op("drop_hat", hand(), label("Drop hat"), priority(OP_PRIORITY_PART), when(PROC_REF(hat_droppable)), starts(PROC_REF(hat_drop_started)), wait(3 SECONDS), then(PROC_REF(hat_dropped)))
	op("break_bolt", menu(), when(PROC_REF(bolt_breakable)), begins(PROC_REF(bolt_break_text)), wait(1.5 MINUTES), then(PROC_REF(bolt_broken)))
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
