// mob_misc: lazy owned state of /mob (storage contract, doc/rewrite/storage_contract.md). It does not exist until the first write;
// read a field with STATE_GET(M, mob_misc, field), write with STATE_SET(M, mob_misc, field, value), end it with mob_misc_clear(M).

/datum/mob_misc_state
	var/accumulated_rads = 0
	var/ajourn = 0
	var/bhunger = 0
	/// / Blood on the bare hands, in blood units (lazy state field bloody_hands, default 0).
	var/bloody_hands = 0
	/// A bed or nest raising its buckled mob (the old /atom/movable old_y): added to default_pixel_y as the offset a shake or float returns to.
	var/buckle_pixel_y = 0
	var/damageoverlaytemp = 0
	var/digitalcamo = 0
	/// base_vars wave 11: rare numeric state of a mob. Each reads 0 while unset and a write of 0 clears it. (losebreath, read by every breathing step, lives on the physiology.)
	var/disabilities = 0
	var/emote_sound_mode = EMOTE_SOUND_VOICE_FREQ
	var/facing_dir
	var/floatiness = 0
	var/forbid_seeing_deadchat = FALSE
	var/get_rig_stats = 0
	var/hive_lang_range = 0
	var/in_throw_mode = 0
	var/inertia_dir = 0
	/// base_vars wave 3
	var/is_floating = 0
	var/is_slipping = FALSE
	/// /mob
	var/last_emote_summary
	var/lastareachange = 0
	var/m_int
	var/muffled = FALSE
	var/name_archive
	var/image/narglow
	var/image/narsimage
	var/other_mobs
	var/registered_z
	var/image/riftimage
	var/seer = 0
	var/skip_buckled_move_redirect = FALSE
	/// /mob
	var/suiciding = 0
	var/updating_fullness = FALSE
	var/vantag_hud = 0
	var/voice_freq = 42500
	var/list/active_genes
	var/list/global_hud_claims
	var/list/logging
	var/list/misc_tabs
	var/list/progressbars
	var/list/skincmds
	var/list/ventcraw_item_admin_allow
	var/list/voice_sounds_list
	var/teleop

CAPABILITIES(/datum/mob_misc_state)
	ref_one(nameof(teleop), /mob, weak = TRUE)


/mob
	var/datum/mob_misc_state/mob_misc
