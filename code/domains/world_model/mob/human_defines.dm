/mob/living/carbon/human
	// Every human has a body plan with limbs and organs; species setup refills these.
	organs = list()
	organs_by_name = list()

	// Hair, eye, skin and synth colours, styles, skin tone, digitigrade and lips: the looks profile record
	// (/datum/record/appearance, profile_records.dm).



	var/datum/robolimb/synthetic		//If they are a synthetic (aka synthetic torso). Also holds the datum for the type of robolimb.

	var/list/all_underwear	// Lazy.
	var/list/all_underwear_metadata = list() // ALLOW(instance_list): d: per-mob all_underwear_metadata, filled at runtime; mobs are few
	var/list/hide_underwear = list() // ALLOW(instance_list): d: per-mob hide_underwear, filled at runtime; mobs are few

	// Age, background, records, flavour text and kit choices: the bio profile record on /mob
	// (/datum/record/identity, code/modules/mob/profile_records.dm).





	var/hand_blood_color



	var/identifying_gender // In case the human identifies as another gender than it's biological



	// vr_holder (the "real" mob a VR avatar's client belongs to) and vr_link (the avatar a real mob entered or left) are one sparse link
	// pair (LK_VR_HOLDER / LK_VR_LINK, code/library/mob/hands.dm).



	// Horray Furries!
	var/datum/sprite_accessory/ears/ear_style = null

	/// secondary ears sprite accessory reference
	var/datum/sprite_accessory/ears/ear_secondary_style
	/// secondary ears color channels; can be null, or a list of #aabbcc hexcolors
	var/list/ear_secondary_colors

	var/datum/sprite_accessory/tail/tail_style = null

	var/wagging = 0 //UGH.

	var/datum/sprite_accessory/wing/wing_style = null


	var/flapping = 0

	// Custom Species Name

	var/block_hud

	var/phobias		//For holding a list of phobias

	var/redgate_restricted = FALSE
	var/hide_headset = FALSE
	var/hide_glasses = FALSE


/mob/living/carbon/human
	var/vantag_pref = VANTAG_NONE //What's my status?
	var/wings_hidden = FALSE
	var/tail_hidden = FALSE

	// body_writing (what is written on each body part, by BP_ key) is a sparse slot (code/datums/sparse_vars/mob_state.dm).



/mob/living/carbon/human/ai_controlled
	low_priority = TRUE

// Tracked inputs of the Life presentation reactions (HUD, sight, canmove; living_systems.dm): their setters publish.
/// Limbs and organs attach and detach through the body (body/parts/attach.dm invalidates it): MOB_KEY_HEALTH.
PUBLISHED_BY(/mob/living/carbon/human, organs, MOB_KEY_HEALTH)

/// The phobias step reads them.

CAPABILITIES(/mob/living/carbon/human)
	op("hand_games", menu(desc = "Choose from a variety of hand games to play with someone next to you or across a small table."), label("Play Hand Games"), needs(req_self(), req(PROC_REF(hand_games_ready))), asks(/datum/prompt/choice, fields = list("title" = "Hand games", "question" = "Choose a game partner:", "choices" = computed(PROC_REF(hand_games_partner_choices)), "ask_flags" = ASK_CONSCIOUS, "timeout" = 0), step = "partner"), asks(/datum/prompt/choice, fields = list("title" = "Hand games", "question" = "Choose a game to play?", "choices" = list("Rock, Paper, Scissors", "Arm Wrestling", "Slap Hands", "Thumb Wars", "Cancel"), "buttons" = TRUE, "ask_flags" = ASK_CONSCIOUS, "timeout" = 0), step = "game"), then(PROC_REF(hand_games_op)))
	op("toggle_underwear", menu(desc = "Shows/hides selected parts of your underwear."), label("Toggle Underwear"), needs(req_self(), req_conscious()), asks(/datum/prompt/choice, fields = list("title" = "Show/hide underwear", "question" = "Choose underwear:", "choices" = computed(PROC_REF(toggle_underwear_choices)), "ask_flags" = ASK_CONSCIOUS, "timeout" = 0), step = "category"), then(PROC_REF(toggle_underwear_op)))
	op("pull_punches", menu(desc = "Try not to hurt them."), label("Pull Punches"), needs(req_self(), req_conscious()), then(PROC_REF(pull_punches_op)))
	op("flip_lying", menu(desc = "Switch your horizontal direction while prone."), label("Flip Resting Direction"), needs(req_self(), req(PROC_REF(flip_lying_ready))), then(PROC_REF(flip_lying_op)))
	op("hide_headset", menu(desc = "Toggle headset worn icon visibility."), label("Show/Hide Headset"), needs(req_self()), then(PROC_REF(hide_headset_op)))
	op("hide_glasses", menu(desc = "Toggle glasses worn icon visibility."), label("Show/Hide Glasses"), needs(req_self()), then(PROC_REF(hide_glasses_op)))
	op("create_area", menu(desc = "Create an area in a enclosed space, making it able to be powered by an APC."), label("Create Area"), needs(req_self(), req(PROC_REF(create_area_ready))), then(PROC_REF(create_area_op)))
	op("check_attacks", menu(), label("Check Attacks"), needs(req_self()), then(PROC_REF(check_attacks_op)))
	extend(/datum/act/hit/explosion, instead(then(PROC_REF(human_blast))))
	configure(living_rules(vore_icon_bellies = list("stomach", "taur belly"), vore_capacity_ex = list("stomach" = 3, "taur belly" = 3), vore_capacity = 3, has_huds = TRUE, vore_shred_time = 10 SECONDS))
	configure(buckle_rules(max_mobs = 1, movable = TRUE, lying = FALSE))
	setup(PROC_REF(finish_human_init))
	links(LINK_END(/mob/living/carbon/human, LK_WEARING_RIG), LINK_END(/obj/item/rig, LK_RIG_WEARER), sparse = TRUE) // the rig a human wears and the human in it (wearing_rig() / wearer())
	links(LINK_END(/mob/living/carbon/human, LK_DEFAULT_ATTACK), LINK_END(/datum/unarmed_attack, LK_DEFAULT_ATTACK_OF), sparse = TRUE, b_many = TRUE) // the unarmed attack it uses by default (default_attack())
	links(LINK_END(/mob/living/carbon/human, LK_VR_HOLDER), LINK_END(/mob/living/carbon/human, LK_VR_LINK), sparse = TRUE) // a VR avatar and the body its client came from (vr_holder() / vr_link())
	// The character's chosen look (code/modules/mob/living/carbon/human/profile_records.dm).
	profile(nameof(looks), /datum/record/appearance)
	// The chosen sprite accessories and the prosthetic model: shared definitions the look reads through (written with rel_set(), so a change
	// redraws the human).
	ref_one(nameof(tail_style), /datum/sprite_accessory/tail)
	ref_one(nameof(wing_style), /datum/sprite_accessory/wing)
	ref_one(nameof(ear_style), /datum/sprite_accessory/ears)
	ref_one(nameof(ear_secondary_style), /datum/sprite_accessory/ears)
	ref_one(nameof(synthetic), /datum/robolimb)
	wrapped_species_form()
	configure(mob_kind(can_be_antagged = TRUE, inventory_panel = /datum/inventory_panel/human, voice_name = "unknown"))
	configure(mob_movement(bump = HUMAN, push = ~HEAVY, swap = ~HEAVY))
	cooldowns(push_lying_cooldown, disarm_cooldown, breath_sound_cooldown, chew_cooldown, xylophone)
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
	op("loosen_tourniquet_pick", menu(), label("Loosen Tourniquet"), when(req_actor_kind(/mob/living)), needs(req_capable(), req_adjacent(), req(PROC_REF(loosen_tourniquet_pick_ready))), asks(/datum/prompt/choice, fields = list("question" = "Loosen which tourniquet?", "title" = "Tourniquet", "choices" = computed(PROC_REF(loosen_tourniquet_choices)), "timeout" = 0), step = "limb"), then(PROC_REF(loosen_tourniquet_picked)))
	op("loosen_tourniquet", ai(), reach(REACH_ADJACENT), takes("limb"), begins(PROC_REF(loosen_tourniquet_begins)), wait(TOURNIQUET_REMOVE_TIME), then(PROC_REF(loosen_tourniquet_done)))
	// Devouring from the water: the victim is picked, then kept for the five seconds it takes to drag them under; if they get away it fails.
	op("underwater_devour", ai(), asks(/datum/prompt/choice/victim/underwater, fields = list("choices" = computed(PROC_REF(underwater_devour_choices))), step = "victim", keeps_answer = TRUE),
		starts(PROC_REF(underwater_devour_started)), wait(5 SECONDS, keeps = STAY | TARGET_PRESENT | ALIVE), on_interrupt(PROC_REF(underwater_devour_escaped)), then(PROC_REF(underwater_devour_human_done)))
	op("lleill_ring_spawn", ai(), wait(10 SECONDS), on_interrupt(PROC_REF(lleill_ring_interrupted)), then(PROC_REF(lleill_ring_spawn_done)))
	// The lleill powers (lleill_abilities.dm): what the prompts chose comes with the call, and the ten seconds are the glamour working.
	op("lleill_transmute", ai(), needs(req_capable()), takes("item", "product", "cost"), wait(10 SECONDS), on_interrupt(PROC_REF(lleill_transmute_human_failed)), then(PROC_REF(lleill_transmute_human_done)))
	op("lleill_alchemy", ai(), needs(req_capable()), takes("item", "product", "cost"), wait(10 SECONDS), on_interrupt(PROC_REF(lleill_alchemy_stopped)), then(PROC_REF(lleill_alchemy_done)))
	op("lleill_contact", ai(), needs(req_capable()), takes("partner", "from"), wait(10 SECONDS), on_interrupt(PROC_REF(lleill_contact_broken)), then(PROC_REF(lleill_contact_done)))
	op("lleill_beast_form", ai(), needs(req_capable()), takes("beast", "options", "cost"), wait(10 SECONDS), on_interrupt(PROC_REF(lleill_beast_form_human_failed)), then(PROC_REF(lleill_beast_form_human_done)))
	// The shapeshifter reforms (species_shapeshift.dm): the answers about flavour text and OOC notes come with the call, and the body stays still for four seconds.
	op("shapeshifter_regenerate", ai(), needs(req_capable()), takes("flavour", "oocnotes"), wait(4 SECONDS), then(PROC_REF(shapeshifter_regenerate_human_done)))
	op("shapeshifter_reassemble", ai(), needs(req_capable()), takes("flavour", "oocnotes"), wait(4 SECONDS), then(PROC_REF(shapeshifter_reassemble_human_done)))
	op("shapeshifter_copy_body", ai(), needs(req_capable()), takes("victim", "flavour", "from"), wait(4 SECONDS), then(PROC_REF(copy_body_done)))
	// A bite for blood (station_special_abilities.dm), and a drain through a grab: one lap of five seconds per stage until a stage says it is done.
	op("bloodsuck", ai(), needs(req_capable()), takes("victim", "noise", "bleed", "from"), wait(30 SECONDS), then(PROC_REF(bloodsuck_human_done)))
	op("grab_drain", ai(), needs(req_capable()), takes("victim", "grab", "stage", "stage_proc", "needed_grab", "what"), wait(5 SECONDS, repeats = PROC_REF(grab_drain_more), after_step = PROC_REF(grab_drain_lap)), on_interrupt(PROC_REF(grab_drain_interrupted)))
	// Modular limbs (human_modular_limbs.dm): the limb is the one the verb checked.
	op("attach_limb", ai(), needs(req_capable()), takes("limb"), wait(2 SECONDS), then(PROC_REF(attach_limb_verb_human_done)))
	op("detach_limb", ai(), needs(req_capable()), takes("limb"), wait(2 SECONDS), then(PROC_REF(detach_limb_verb_human_done)))
	// The hand games (human_powers.dm): the partner agreed, and the winner of a rolled game comes with the call.
	op("game_thumbwars", ai(), needs(req_capable()), takes("partner", "from"), wait(5 SECONDS), on_interrupt(PROC_REF(game_thumbwars_human_failed)), then(PROC_REF(game_thumbwars_human_done)))
	op("game_armwrestle", ai(), needs(req_capable()), takes("partner", "from", "competition"), wait(5 SECONDS), on_interrupt(PROC_REF(game_armwrestle_human_failed)), then(PROC_REF(game_armwrestle_human_done)))
	op("game_slaphands", ai(), needs(req_capable()), takes("partner", "from", "competition"), wait(1 SECOND), on_interrupt(PROC_REF(game_slaphands_human_failed)), then(PROC_REF(game_slaphands_human_done)))
	// Popping a dislocated joint back (human.dm): performed by the one relocating (the actor) on the one whose joint it is (the holder), next to them.
	op("relocate_joint", ai(), needs(req_capable()), takes("limb"), wait(3 SECONDS), then(PROC_REF(relocate_human_done)))
	body_clock(STAT_BODY_CLOCK_ACTIVE)
	limb_clock(STAT_LIMB_TROUBLE)
	organ_clock(STAT_ORGANS_ACTIVE)
	pain_clock(STAT_PAIN_FELT)
	surgery_ops()
	owns_one(nameof(character_forms), /datum/forms)
	owns_one(nameof(vessel), /datum/reagents)
	owns_one(nameof(xenochimera), /datum/xenochimera)
	links(LINK_END(/mob/living/carbon/human, LK_GENETIC_EFFECTS), LINK_END(/datum/genetics/side_effect, LK_GENETIC_HOST), sparse = TRUE, a_many = TRUE, b_on_other_deleted = OTHER_DELETE_ME) // a human's genetic side effects, gone with it (genetic_side_effects())
	links(LINK_END(/mob/living/carbon/human, LK_SIDE_EFFECTS), LINK_END(/datum/medical_effect, LK_SIDE_EFFECT_OF), sparse = TRUE, a_many = TRUE, b_on_other_deleted = OTHER_DELETE_ME) // a human's medication side effects, gone with it (side_effects())
	links(LINK_END(/mob/living/carbon/human, LK_GLAMOUR_RINGS), LINK_END(/obj/structure/glamour_ring, LK_GLAMOUR_OWNER), sparse = TRUE, a_many = TRUE, b_on_other_deleted = OTHER_DELETE_ME) // the rings a lleill placed, gone with it (glamour_rings())
	owns_one(nameof(crafting), starts = /datum/personal_crafting)
	owns_one(nameof(dna), /datum/dna, starts = /datum/dna, starts_args = NO_LOC, early = TRUE) // set_species() writes it in phase 0
	param(nameof(species_at_make), pos = 1, apply = PROC_REF(set_species), early = TRUE) // the species builds the body every init line of the human reads: phase 0, after the DNA
	rolls(nameof(real_name), PROC_REF(roll_species_name))
	rolls(nameof(name), PROC_REF(roll_species_name), from = list(nameof(real_name)))
	derives(nameof(hide_underwear), PROC_REF(underwear_all_shown))
	hose_sockets(list(/datum/hose_connector/inflation)) // drop to disable all human mob inflation mechanics
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
