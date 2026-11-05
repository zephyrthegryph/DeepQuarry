// human_misc: lazy owned state of /mob/living/carbon/human (storage contract, doc/rewrite/storage_contract.md). It does not exist until the first write;
// read a field with STATE_GET(M, human_misc, field), write with STATE_SET(M, human_misc, field, value), end it with human_misc_clear(M).

/datum/human_misc_state
	var/can_defib = 1
	var/changeling_locked
	var/chemical_darksight = 0
	var/damage_multiplier = 1
	var/environment_steady = FALSE
	var/gender_change_cooldown = 0
	var/health_doll_key
	var/heartbeat = 0
	var/markings_len = 0
	/// /mob/living/carbon/human
	var/nutrition_drained_at = 0
	var/nutrition_hidden = FALSE
	/// / The ckey this body originally belonged to (sparse slot original_player; null for a custom sleeve).
	var/original_player
	/// / Should affect how mob sprite is drawn, but currently doesn't (sparse slot pale, default 0).
	var/pale = 0
	var/resleeve_lock
	/// / A voice forced on the speaker (a symptom); unset for nearly everyone.
	var/special_voice = ""
	var/speech_sound_enabled = TRUE
	var/spit_name
	var/spit_projectile
	var/list/body_writing
	var/list/disability_motor_tics

/mob/living/carbon/human
	var/datum/human_misc_state/human_misc
