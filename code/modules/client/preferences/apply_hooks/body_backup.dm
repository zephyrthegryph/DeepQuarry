// Post-spawn orchestration for the vore_misc tab:
//   - recalculate vis (stomach sprite pref applies via apply_to_human; this is the redraw)
//   - VANTAG hud flag refresh (vantag_preference already wrote via its apply_to_human; this
//     bitsets the hud flag that says "VANTAG changed, redraw")
//   - body/mind backup ~5s after spawn for resleeve persistence
//
// Lives in a hook because the body/mind backup spawns a delayed callback that reads multiple
// prefs and species state — not expressible as a per-pref apply.

/datum/preference_apply_hook/body_backup
	// LATE + 10 so body_backup runs strictly *after* nif (which is APPLY_HOOK_PRIORITY_LATE).
	// body_backup reads target.nif inside its deferred block; if it ran first the NIF
	// wouldn't be spawned yet and the m_backup would persist a null reference.
	priority = APPLY_HOOK_PRIORITY_LATE + 10
	skip_on_preview = TRUE

/datum/preference_apply_hook/body_backup/apply(mob/living/carbon/human/target, datum/preferences/preferences)
	if(!ishuman(target))
		return
	target.recalculate_vis()

	if(istype(target, /mob/living/carbon/human/dummy))
		return

	BITSET(target.hud_updateflag, VANTAG_HUD)
	var/want_body_save = preferences.read_preference(/datum/preference/toggle/human/resleeve_scan)
	var/want_mind_save = preferences.read_preference(/datum/preference/toggle/human/mind_scan)
	var/resleeve_lock_pref = preferences.read_preference(/datum/preference/toggle/human/resleeve_lock)

	// addtimer instead of spawn(5 SECONDS) — addtimer participates in the
	// SS scheduler (cancellable, profilable, survives MC stalls correctly).
	addtimer(CALLBACK(GLOBAL_PROC, GLOBAL_PROC_REF(_dq_body_backup_after_spawn), target, preferences, want_body_save, want_mind_save, resleeve_lock_pref), 5 SECONDS)

/proc/_dq_body_backup_after_spawn(mob/living/carbon/human/target, datum/preferences/preferences, want_body_save, want_mind_save, resleeve_lock_pref)
	if(QDELETED(target) || QDELETED(preferences))
		return
	// Janky fix to prevent resleeving VR avatars but beats refactoring transcore
	if(!target.virtual_reality_mob && !(/mob/living/carbon/human/proc/perform_exit_vr in target.verbs))
		if(want_body_save && !(target.species.flags & NO_SLEEVE))
			var/datum/transhuman/body_record/BR = new()
			BR.init_from_mob(target, TRUE, resleeve_lock_pref)
		if(want_mind_save)
			var/datum/transcore_db/our_db = SStranscore.db_by_key(null)
			if(our_db)
				our_db.m_backup(target.mind, target.nif, one_time = TRUE)
	if(resleeve_lock_pref)
		target.resleeve_lock = target.ckey
	target.original_player = target.ckey
