/**
 * The mob, usually meant to be a creature of some type
 *
 * Has a client attached that is a living person (most of the time), although I have to admit
 * sometimes it's hard to tell they're sentient
 *
 * Has a lot of the creature game world logic, such as health etc
 */
/mob
	density = TRUE
	layer = MOB_LAYER
	plane = MOB_PLANE
	animate_movement = 2
	blocks_emissive = EMISSIVE_BLOCK_GENERIC
	///when this be added to vis_contents of something it inherit something.plane, important for visualisation of mob in openspace.
	vis_flags = VIS_INHERIT_PLANE
	unacidable = FALSE

	/// It's like a client, but persists! Persistent clients will stick to a mob until the client in question is logged into a different mob.
	var/tmp/datum/persistent_client/persistent_client

	var/datum/mind/mind

	var/stat = CONSCIOUS //Whether a mob is alive or dead.
	COOLDOWN_DECLARE(next_move) // world.time when mob is next allowed to self-move.

	/**
	 * Whether and how a mob is incapacitated
	 *
	 * Normally being restrained, agressively grabbed, or in stasis counts as incapacitated
	 * unless there is a flag being used to check if it's ignored
	 *
	 * * bitflags: (see code/__DEFINES/status_effects.dm)
	 * * INCAPABLE_RESTRAINTS - if our mob is in a restraint (handcuffs)
	 * * INCAPABLE_STASIS - if our mob is in stasis (stasis bed, etc.)
	 * * INCAPABLE_GRAB - if our mob is being agressively grabbed
	 *
	**/
	VAR_FINAL/incapacitated = NONE

	var/tmp/atom/movable/screen/hands = null
	var/tmp/atom/movable/screen/pullin = null
	var/tmp/atom/movable/screen/purged = null
	var/tmp/atom/movable/screen/internals = null
	var/tmp/atom/movable/screen/healths = null
	var/tmp/atom/movable/screen/throw_icon = null
	var/tmp/atom/movable/screen/pain = null
	var/tmp/atom/movable/screen/gun/item/item_use_icon = null
	var/tmp/atom/movable/screen/gun/radio/radio_use_icon = null
	var/tmp/atom/movable/screen/gun/move/gun_move_icon = null
	var/tmp/atom/movable/screen/gun/mode/gun_setting_icon = null
	var/tmp/atom/movable/screen/ling/chems/ling_chem_display = null
	var/tmp/atom/movable/screen/borer/chems/borer_chem_display = null
	var/tmp/atom/movable/screen/wizard/energy/wiz_energy_display = null
	var/tmp/atom/movable/screen/wizard/instability/wiz_instability_display = null
	var/tmp/atom/movable/screen/autowhisper_display = null

	var/tmp/datum/plane_holder/plane_holder = null
	var/list/vis_enabled = null		// List of vision planes that should be graphically visible (list of their VIS_ indexes).
	var/list/planes_visible = null	// List of atom planes that are logically visible/interactable (list of actual plane numbers).

	//spells hud icons - this interacts with add_spell and remove_spell
	var/tmp/list/atom/movable/screen/movable/spell_master/spell_masters = null
	var/tmp/atom/movable/screen/movable/ability_master/ability_master = null

	/*A bunch of this stuff really needs to go under their own defines instead of being globally attached to mob.
	A variable should only be globally attached to turfs/objects/whatever, when it is in fact needed as such.
	The current method unnecessarily clusters up the variable list, especially for humans (although rearranging won't really clean it up a lot but the difference will be noticable for other mobs).
	I'll make some notes on where certain variable defines should probably go.
	Changing this around would probably require a good look-over the pre-existing code.
	*/
	var/tmp/atom/movable/screen/zone_sel/zone_sel = null

	var/use_me = 1 //Allows all mobs to use the me verb by default, will have to manually specify they cannot
	var/damageoverlaytemp = 0

	var/computer_id = null
	var/list/logging

	var/other_mobs = null
	var/memory = ""
	var/disabilities = 0	//Carbon
	var/transforming = null	//Carbon
	var/other = 0.0
	var/real_name = null
	var/nickname = null
	var/flavor_text = ""
	var/med_record = ""
	var/sec_record = ""
	var/gen_record = ""
	var/exploit_record = ""
	var/list/obj/item/exploit_addons		//Assorted things that show up at the end of the exploit_record list
	var/blinded = null
	var/bhunger = 0			//Carbon
	var/ajourn = 0
	var/phoron = null
	var/resting = 0			//Carbon
	var/lying = 0
	var/lying_prev = 0
	var/is_shifted = FALSE // Edit; pixel shifting
	var/canmove = 1
	//Allows mobs to move through dense areas without restriction. For instance, in space or out of holder objects.
	var/incorporeal_move = 0 //0 is off, 1 is normal, 2 is for ninjas.
	var/list/pinned                     // Lazylist of things pinning this creature to walls (see living_defense.dm). Usually empty.
	var/list/embedded                   // Lazylist of embedded items, since simple mobs don't have organs. Usually empty.
	// ALLOW(instance_list): d: per-mob languages, filled at runtime; mobs are few
	var/list/languages = list()         // For speaking/listening.
	// ALLOW(instance_list): d: per-mob language_keys, filled at runtime; mobs are few
	var/list/language_keys = list()		// List of language keys indexing languages
	var/species_language = null			// For species who want reset to use a specified default.
	var/only_species_language  = 0		// For species who can only speak their default and no other languages. Does not affect understanding.
	// ALLOW(instance_list): c: interned per subtype by shared_type_list() in Initialize(), so instances share one list
	var/list/speak_emote = list("says") // Verbs used when speaking. Defaults to 'say' if speak_emote is null.
	var/emote_type = 1		// Define emote default type, 1 for seen emotes, 2 for heard emotes
	var/facing_dir = null   // Used for the ancient art of moonwalking.

	var/name_archive //For admin things like possession

	EXPIRY_DECLARE(timeofdeath) //Living
	/// What onlookers see when this mob dies ("\The [src] <death_message>"). See /mob/proc/get_death_message().
	var/death_message = "seizes up and falls limp..."
	COOLDOWN_DECLARE(cpr_time) //Carbon

	var/bodytemperature = BODYTEMP_NORMAL
	var/charges = 0.0

	var/losebreath = 0.0//Carbon
	var/m_int = null//Living
	var/m_intent = I_RUN//Living
	var/lastKnownIP = null
	var/no_pull_when_living = FALSE //Test for if it can be pulled when alive
	/// Set around a holder-driven forced step (a chair/wheelchair moving its
	/// own buckled occupant directly, handle_buckled_mob_movement()) so
	/// /mob/living/Move() doesn't redirect that step back into the buckled
	/// object's own Move() -- BUCKLED()/BUCKLED_MOBS() (om.dm) are pure graph
	/// reads now, with no field left to transiently null for the same effect.
	var/tmp/skip_buckled_move_redirect = FALSE

	var/seer = 0 //for cult//Carbon, probably Human

	var/tmp/datum/hud/hud_used = null

	var/tmp/list/mapobjs                    // Lazylist of overview screen objects. Usually empty/null.

	var/in_throw_mode = 0

	var/inertia_dir = 0


	var/job = null//Living

	var/const/blindness = 1//Carbon
	var/const/deafness = 2//Carbon
	var/const/muteness = 4//Carbon

	var/can_pull_size = ITEMSIZE_NO_CONTAINER // Maximum w_class the mob can pull.
	var/can_pull_mobs = MOB_PULL_LARGER // Whether or not the mob can pull other mobs.

	var/datum/dna/dna = null//Carbon
	var/radiation = 0.0//Carbon

	/// Lazy list of active mutation defines (HULK, HUSK, XRAY, ...). Null when empty.
	/// Do not read/write this directly outside mutations.dm -- use has_mutation(),
	/// add_mutation(), remove_mutation() and mutation_count() instead.
	var/list/mutations //Carbon -- Doohl
	//see: setup.dm for list of mutations

	var/voice_name = "unidentifiable voice"

	var/list/ventcraw_item_admin_allow = null // If this is a list, it will be appended to the default list of items the mob is allowed to ventcrawl with

	var/faction = FACTION_NEUTRAL //Used for checking whether hostile simple animals will attack you, possibly more stuff later

	var/can_be_antagged = FALSE // To prevent pAIs/mice/etc from getting antag in autotraitor and future auto- modes. Uses inheritance instead of a bunch of typechecks.
	var/away_from_keyboard = FALSE	//are we at, or away, from our keyboard?
	var/manual_afk = FALSE			//did we set afk manually or was it automatic?

//The last mob/living/carbon to push/drag/grab this mob (mostly used by slimes friend recognition)
	var/tmp/mob/living/carbon/LAssailant = null

//Wizard mode, but can be used in other modes thanks to the brand new "Give Spell" badmin button
	// Spells migrate between mobs on mind/ghost swaps (spellbook.dm, mind_transfer.dm): a relation list.
	var/list/datum/spell/spell_list = list() // ALLOW(instance_list): d: per-mob spell_list, filled at runtime; mobs are few

//Changlings, but can be used in other modes
//	var/obj/effect/proc_holder/changpower/list/power_list = list()

	mouse_drag_pointer = MOUSE_ACTIVE_POINTER

	var/update_icon = 1 //Set to 1 to trigger update_icons() at the next life() call

	var/status_flags = CANPUSH	//bitflags: CANPUSH, LEAPING, HIDING, PASSEMOTES, FAKEDEATH. Status immunities and godmode are effects (EFFECT_IMMUNE_*, EFFECT_GODMODE).

	var/tmp/area/lastarea = null
	EXPIRY_TMP_DECLARE(lastareachange)

	var/digitalcamo = 0 // Can they be tracked by the AI?



	var/obj/control_object //Used by admins to possess objects. All mobs should have this var

	//Whether or not mobs can understand other mobtypes. These stay in /mob so that ghosts can hear everything.
	var/universal_speak = 0 // Set to 1 to enable the mob to speak to everyone -- TLE
	var/universal_understand = 0 // Set to 1 to enable the mob to understand everyone, not necessarily speak

	var/stance_damage = 0 //Whether this mob's ability to stand has been affected

	//If set, indicates that the client "belonging" to this (clientless) mob is currently controlling some other mob
	//so don't treat them as being SSD even though their client var is null.
	var/tmp/mob/teleop = null

	// ALLOW(instance_list): c: interned per subtype by shared_type_list() in Initialize(), so instances share one list
	var/list/shouldnt_see = list(/mob/observer/eye)	//list of objects that this mob shouldn't see in the stat panel. this silliness is needed because of AI alt+click and cult blood runes. Interned per subtype in /mob/Initialize().

	var/list/active_genes
	var/mob_size = MOB_MEDIUM
	var/forbid_seeing_deadchat = FALSE // Used for lings to not see deadchat, and to have ghosting behave as if they were not really dead.

	var/seedarkness = 1	//Determines mob's ability to see shadows. 1 = Normal vision, 0 = darkvision

	var/get_rig_stats = 0 //Moved from computer.dm

	var/custom_speech_bubble = "default"

	var/low_priority = FALSE //Skip processing life() if there's just no players on this Z-level

	var/default_pixel_x = 0 //For offsetting mobs
	var/default_pixel_y = 0

	var/attack_icon //Icon to use when attacking w/o anything in-hand
	var/attack_icon_state //State for above

	var/registered_z


	///List of progress bars this mob is currently seeing for actions
	var/tmp/list/progressbars = null //for stacking do_after bars

	///For storing what do_after's someone has, key = string, value = amount of interactions of that type happening.
	var/tmp/list/do_afters

	///Allows a datum to intercept all click calls this mob is the source of
	var/tmp/datum/click_intercept

	var/tmp/datum/focus //What receives our keyboard inputs. src by default

	/// dict of custom stat tabs with data
	var/list/list/misc_tabs = list() // ALLOW(instance_list): d: per-mob misc_tabs, filled at runtime; mobs are few

	// Membership list maintained by /datum/action Grant()/Remove(): a relation list.
	var/tmp/list/datum/action/actions


	var/custom_footstep = FOOTSTEP_MOB_SHOE
	var/vent_crawl_time = 4.5 SECONDS // Time to animate entering a vent
	VAR_PRIVATE/is_motion_tracking = FALSE // Prevent multiple unsubs and resubs, also used to check if the vis layer is enabled, use has_motiontracking() to get externally.
	VAR_PRIVATE/wants_to_see_motion_echos = TRUE

	var/is_slipping = FALSE
	COOLDOWN_DECLARE(slip_protect)

CAPABILITIES(/mob)
	telekinetic_reach()
	godmode_immunities()
	every(1 DECISECONDS, then(PROC_REF(dizzy_shake_tick)), when = nameof(dizzy_shaking))
	every(1 DECISECONDS, then(PROC_REF(jittery_shake_tick)), when = nameof(jittery_shaking))
	owns_one(nameof(ability_master), /atom/movable/screen/movable/ability_master, starts = /atom/movable/screen/movable/ability_master)
	owns_one(nameof(belly_overlay_tgui), /datum/belly_overlay_tgui)
	owns_one(nameof(borer_chem_display), /atom/movable/screen/borer/chems)
	owns_one(nameof(dna), /datum/dna)
	owns_one(nameof(gun_move_icon), /atom/movable/screen/gun/move)
	owns_one(nameof(gun_setting_icon), /atom/movable/screen/gun/mode)
	owns_one(nameof(hands), /atom/movable/screen)
	owns_one(nameof(healths), /atom/movable/screen)
	owns_one(nameof(hud_used), /datum/hud)
	owns_one(nameof(internals), /atom/movable/screen)
	owns_one(nameof(item_use_icon), /atom/movable/screen/gun/item)
	owns_one(nameof(ling_chem_display), /atom/movable/screen/ling/chems)
	owns_one(nameof(lleill_display), /atom/movable/screen/lleill)
	owns_one(nameof(machine_shim), /datum/using_machine_shim)
	owns_one(nameof(pain), /atom/movable/screen)
	owns_one(nameof(plane_holder), /datum/plane_holder)
	owns_one(nameof(radio_use_icon), /atom/movable/screen/gun/radio)
	owns_one(nameof(remote_view), /datum/remote_view)
	owns_one(nameof(shadekin_display), /atom/movable/screen/shadekin)
	owns_one(nameof(vorePanel), /datum/vore_look)
	owns_one(nameof(wiz_energy_display), /atom/movable/screen/wizard/energy)
	owns_one(nameof(wiz_instability_display), /atom/movable/screen/wizard/instability)
	owns_one(nameof(xenochimera_danger_display), /atom/movable/screen/xenochimera/danger_level)
	owns_one(nameof(zone_sel), /atom/movable/screen/zone_sel)
	owns_many(nameof(spell_masters), /atom/movable/screen/movable/spell_master)
	owns_many(nameof(vore_organs))
	owns_many(nameof(alerts))
	owns_many(nameof(screens))
	// Selected, spontaneous and previewed bellies are borrowed views, separate from owned vore_organs.
	ref_one(nameof(vore_selected))
	ref_one(nameof(spont_belly_front))
	ref_one(nameof(spont_belly_rear))
	ref_one(nameof(spont_belly_left))
	ref_one(nameof(spont_belly_right))
	ref_one(nameof(previewing_belly))
	hover(PROC_REF(hover_input))
	op("flavor_more", topic("flavor_more"), then(PROC_REF(topic_flavor_more)))
	op("flavor_change", topic("flavor_change", arg("flavor_change", schema_text(32), optional = TRUE)), needs(req_self()), then(PROC_REF(topic_flavor_change)))
	// The links of living mobs, humans and cyborgs, guarded by their holder type: they move into those types' own blocks (code/library/mob/hands.dm,
	// code/modules/combat_ai/integration/mob_living.dm) when that work is free.
	op("default_lang_reset", topic("default_lang=reset"), needs(req(/mob/living, of = ON_HOLDER, silent = TRUE), req_self()), then(TYPE_PROC_REF(/mob/living, topic_default_lang_reset)))
	op("default_lang", topic("default_lang", arg("default_lang", schema_ref(/datum/language), optional = TRUE, among = TYPE_PROC_REF(/mob/living, topic_known_languages))), needs(req(/mob/living, of = ON_HOLDER, silent = TRUE), req_self()), then(TYPE_PROC_REF(/mob/living, topic_default_lang)))
	op("set_lang_key", topic("set_lang_key", arg("set_lang_key", schema_ref(/datum/language), optional = TRUE, among = TYPE_PROC_REF(/mob/living, topic_known_languages))), needs(req(/mob/living, of = ON_HOLDER, silent = TRUE), req_self()), asks(/datum/prompt/text/language_key, fields = list("question" = computed(TYPE_PROC_REF(/mob/living, language_key_question)), "default" = computed(TYPE_PROC_REF(/mob/living, language_key_default)), "language" = computed(TYPE_PROC_REF(/mob/living, language_key_language))), step = "key"), then(TYPE_PROC_REF(/mob/living, topic_set_lang_key)))
	op("vore_prefs", topic("vore_prefs"), needs(req(/mob/living, of = ON_HOLDER, silent = TRUE)), then(TYPE_PROC_REF(/mob/living, topic_vore_prefs)))
	op("ooc_notes", topic("ooc_notes"), needs(req(/mob/living, of = ON_HOLDER, silent = TRUE)), then(TYPE_PROC_REF(/mob/living, topic_ooc_notes)))
	op("print_ooc_notes_chat", topic("print_ooc_notes_chat"), needs(req(/mob/living, of = ON_HOLDER, silent = TRUE)), then(TYPE_PROC_REF(/mob/living, topic_print_ooc_notes_chat)))
	op("lookitem", topic("lookitem", arg("lookitem", schema_ref(/obj/item), optional = TRUE)), needs(req(/mob/living/carbon/human, of = ON_HOLDER, silent = TRUE)), then(TYPE_PROC_REF(/mob/living/carbon/human, topic_lookitem)))
	op("lookitem_desc_only", topic("lookitem_desc_only", arg("lookitem_desc_only", schema_ref(/obj/item), optional = TRUE, among = TYPE_PROC_REF(/mob/living/carbon/human, topic_worn_items))), needs(req(/mob/living/carbon/human, of = ON_HOLDER, silent = TRUE)), then(TYPE_PROC_REF(/mob/living/carbon/human, topic_lookitem_desc_only)))
	op("criminal", topic("criminal"), needs(req(/mob/living/carbon/human, of = ON_HOLDER, silent = TRUE)), then(TYPE_PROC_REF(/mob/living/carbon/human, topic_hud_criminal)))
	op("medical", topic("medical"), needs(req(/mob/living/carbon/human, of = ON_HOLDER, silent = TRUE)), then(TYPE_PROC_REF(/mob/living/carbon/human, topic_hud_medical)))
	op("secrecord", topic("secrecord"), needs(req(/mob/living/carbon/human, of = ON_HOLDER, silent = TRUE)), then(TYPE_PROC_REF(/mob/living/carbon/human, topic_hud_secrecord)))
	op("medrecord", topic("medrecord"), needs(req(/mob/living/carbon/human, of = ON_HOLDER, silent = TRUE)), then(TYPE_PROC_REF(/mob/living/carbon/human, topic_hud_medrecord)))
	op("emprecord", topic("emprecord"), needs(req(/mob/living/carbon/human, of = ON_HOLDER, silent = TRUE)), then(TYPE_PROC_REF(/mob/living/carbon/human, topic_hud_emprecord)))
	op("secrecordComment", topic("secrecordComment"), needs(req(/mob/living/carbon/human, of = ON_HOLDER, silent = TRUE)), then(TYPE_PROC_REF(/mob/living/carbon/human, topic_hud_seccomments)))
	op("medrecordComment", topic("medrecordComment"), needs(req(/mob/living/carbon/human, of = ON_HOLDER, silent = TRUE)), then(TYPE_PROC_REF(/mob/living/carbon/human, topic_hud_medcomments)))
	op("emprecordComment", topic("emprecordComment"), needs(req(/mob/living/carbon/human, of = ON_HOLDER, silent = TRUE)), then(TYPE_PROC_REF(/mob/living/carbon/human, topic_hud_empcomments)))
	op("secrecordadd", topic("secrecordadd"), needs(req(/mob/living/carbon/human, of = ON_HOLDER, silent = TRUE)), then(TYPE_PROC_REF(/mob/living/carbon/human, topic_hud_secadd)))
	op("medrecordadd", topic("medrecordadd"), needs(req(/mob/living/carbon/human, of = ON_HOLDER, silent = TRUE)), then(TYPE_PROC_REF(/mob/living/carbon/human, topic_hud_medadd)))
	op("emprecordadd", topic("emprecordadd"), needs(req(/mob/living/carbon/human, of = ON_HOLDER, silent = TRUE)), then(TYPE_PROC_REF(/mob/living/carbon/human, topic_hud_empadd)))
	op("showalerts", topic("showalerts"), needs(req(/mob/living/silicon, of = ON_HOLDER, silent = TRUE), req_self()), then(TYPE_PROC_REF(/mob/living/silicon, topic_showalerts)))
	op("vv_setspecies", topic_in(VV_TOPIC, VV_HK_SET_SPECIES), needs(req(/mob/living/carbon/human, of = ON_HOLDER, silent = TRUE), req_rights(R_SPAWN)), asks(/datum/prompt/choice, fields = list("title" = "Species", "question" = "Please choose a new species", "choices" = computed(TYPE_PROC_REF(/mob/living/carbon/human, vv_species_choices)), "rights" = R_SPAWN, "timeout" = 0), step = "species"), then(TYPE_PROC_REF(/mob/living/carbon/human, vv_topic_set_species)))
	op("vv_turn_skeleton", topic_in(VV_TOPIC, VK_HK_TURN_SKELETON), needs(req(/mob/living/carbon/human, of = ON_HOLDER, silent = TRUE), req_rights(R_FUN)), then(TYPE_PROC_REF(/mob/living/carbon/human, vv_topic_turn_skeleton)))
	op("vv_turn_monkey", topic_in(VV_TOPIC, VV_HK_TURN_MONKEY), needs(req(/mob/living/carbon/human, of = ON_HOLDER, silent = TRUE), req_rights(R_SPAWN)), then(TYPE_PROC_REF(/mob/living/carbon/human, vv_topic_turn_monkey)))
	op("vv_turn_alien", topic_in(VV_TOPIC, VV_HK_TURN_ALIEN), needs(req(/mob/living/carbon/human, of = ON_HOLDER, silent = TRUE), req_rights(R_SPAWN)), then(TYPE_PROC_REF(/mob/living/carbon/human, vv_topic_turn_alien)))
	op("vv_turn_ai", topic_in(VV_TOPIC, VK_HK_TURN_AI), needs(req(/mob/living/carbon/human, of = ON_HOLDER, silent = TRUE), req_rights(R_SPAWN)), then(TYPE_PROC_REF(/mob/living/carbon/human, vv_topic_turn_ai)))
	op("vv_turn_robot", topic_in(VV_TOPIC, VK_HK_TURN_ROBOT), needs(req(/mob/living/carbon/human, of = ON_HOLDER, silent = TRUE), req_rights(R_SPAWN)), then(TYPE_PROC_REF(/mob/living/carbon/human, vv_topic_turn_robot)))
	op("vv_regen_icons", topic_in(VV_TOPIC, VV_HK_REGEN_ICONS), then(PROC_REF(vv_topic_regen_icons)))
	op("vv_regen_icons_full", topic_in(VV_TOPIC, VV_HK_REGEN_ICONS_FULL), then(PROC_REF(vv_topic_regen_icons_full)))
	op("vv_player_panel", topic_in(VV_TOPIC, VV_HK_PLAYER_PANEL), then(PROC_REF(vv_topic_player_panel)))
	op("vv_toggle_godmode", topic_in(VV_TOPIC, VV_HK_GODMODE), needs(req_rights(R_ADMIN)), then(PROC_REF(vv_topic_godmode)))
	op("vv_addlanguage", topic_in(VV_TOPIC, VV_HK_ADDLANGUAGE), needs(req_rights(R_SPAWN)), asks(/datum/prompt/choice/vv_spawn, fields = list("title" = "Language", "question" = "Please choose a language to add.", "choices" = computed(PROC_REF(vv_language_choices))), step = "language"), then(PROC_REF(vv_language_added_apply)))
	op("vv_remlanguage", topic_in(VV_TOPIC, VV_HK_REMOVELANGUAGE), needs(req_rights(R_SPAWN)), asks(/datum/prompt/choice/vv_spawn, fields = list("title" = "Language", "question" = "Please choose a language to remove.", "choices" = computed(PROC_REF(vv_known_language_choices))), step = "language"), then(PROC_REF(vv_language_removed_apply)))
	op("vv_addverb", topic_in(VV_TOPIC, VV_HK_ADDVERB), needs(req_rights(R_DEBUG)), asks(/datum/prompt/choice/vv_debug, fields = list("title" = "Verbs", "question" = "Select a verb!", "choices" = computed(PROC_REF(vv_verb_choices))), step = "verb"), then(PROC_REF(vv_verb_added_apply)))
	op("vv_remverb", topic_in(VV_TOPIC, VV_HK_REMOVEVERB), needs(req_rights(R_DEBUG)), asks(/datum/prompt/choice/vv_debug, fields = list("title" = "Verbs", "question" = "Please choose a verb to remove.", "choices" = computed(PROC_REF(vv_current_verb_choices))), step = "verb"), then(PROC_REF(vv_verb_removed_apply)))
	op("vv_give_spell", topic_in(VV_TOPIC, VV_HK_GIVE_SPELL), then(PROC_REF(vv_topic_give_spell)))
	op("vv_remove_spell", topic_in(VV_TOPIC, VV_HK_REMOVE_SPELL), then(PROC_REF(vv_topic_remove_spell)))
	op("vv_give_modifier", topic_in(VV_TOPIC, VV_HK_GIVE_MODIFIER), then(PROC_REF(vv_topic_give_modifier)))
	op("vv_gib", topic_in(VV_TOPIC, VV_HK_GIB), then(PROC_REF(vv_topic_gib)))
	op("vv_buildmode", topic_in(VV_TOPIC, VV_HK_BUILDMODE), needs(req_rights(R_BUILDMODE)), then(PROC_REF(vv_topic_buildmode)))
	op("vv_dropall", topic_in(VV_TOPIC, VV_HK_DROP_ALL), then(PROC_REF(vv_topic_drop_all)))
	op("vv_direct_control", topic_in(VV_TOPIC, VV_HK_DIRECT_CONTROL), then(PROC_REF(vv_topic_direct_control)))
	op("vv_give_ai", topic_in(VV_TOPIC, VV_HK_GIVE_AI), needs(req(/mob/living, of = ON_HOLDER, silent = TRUE), req_rights(R_HOLDER)), asks(/datum/prompt/text/vv_ai_faction, fields = list("question" = computed(TYPE_PROC_REF(/mob/living, vv_ai_faction_question))), step = "faction"), asks(/datum/prompt/choice/vv_ai_stance, step = "stance"), asks(/datum/prompt/choice/vv_ai_wake, step = "wake"), then(TYPE_PROC_REF(/mob/living, vv_topic_give_ai)))


/mob
	var/vantag_hud = 0			// Do I have the HUD enabled?

	var/disconnect_time = null		//Time of client loss, set by Logout(), for timekeeping

	var/tmp/atom/movable/screen/shadekin/shadekin_display = null
	// the lleill glamour display (an /atom/movable/screen/lleill, see owns_one above; the var keeps the looser shadekin screen type, the glamour screen is not a shadekin one
	var/tmp/atom/movable/screen/shadekin/lleill_display = null
	var/tmp/atom/movable/screen/xenochimera/danger_level/xenochimera_danger_display = null

	var/size_multiplier = 1 //multiplier for the mob's icon size
	var/accumulated_rads = 0 	// For radiation stuff.
	var/faction_bump_vore = FALSE	// Don't bump nom mobs of the same faction

/mob/relations()
	. = ..()
	. += rel_one(nameof(control_object)) // the object an admin possesses
	// HUD screens the mob points at but its /datum/hud owns (hotkeybuttons/adding/other/extra_screens):
	// owning them here too made the hud's rel_add and the mob's rel_set a double ownership.
	. += rel_one(nameof(autowhisper_display))
	. += rel_one(nameof(pullin))
	. += rel_one(nameof(throw_icon))
	. += rel_many(nameof(spell_list))
	. += rel_many(nameof(actions))
	. += rel_many(nameof(exploit_addons), back = nameof(/obj/item::exploit_for))
/obj/item/relations()
	. = ..()
	. += rel_one(nameof(exploit_for), back = nameof(/mob::exploit_addons))

// Tracked inputs of the Life presentation reactions (HUD, sight, canmove; living_systems.dm): their setters publish.
TRACKED(/mob, blinded)
TRACKED(/mob, seedarkness)
TRACKED(/mob, transforming)
TRACKED(/mob, resting)
TRACKED(/mob, status_flags)
