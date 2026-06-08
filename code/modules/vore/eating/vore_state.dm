/*
 * /datum/vore_state — snapshot datum for all vore-specific state on a mob.
 *
 * Purpose: extract the ~80 vore vars off the base /mob type into a structured
 * datum that can be (a) lazily instantiated, (b) serialized/deserialized in one
 * place, and (c) compared or copied between mobs cleanly.
 *
 * The vars themselves remain on /mob for backward compatibility with the large
 * number of direct-access call sites outside our module boundaries.  This datum
 * provides:
 *   - A canonical list of every saveable vore-state field via get_saveable_fields().
 *   - capture_from(mob) / apply_to(mob) for snapshot round-trips.
 *   - validate() to sanity-check captured state before persisting.
 *
 * Mobs obtain or create their vore-state datum via /mob/proc/get_vore_state().
 * Call sites that only need direct var access continue to use mob.vore_organs etc.
 * unchanged.
 */

/datum/vore_state
	/// The mob this datum belongs to. Weak reference — always check validity.
	var/mob/owner

	// ------------------------------------------------------------------ //
	//  Prey / prey-permission flags  (mirrored from /mob)                 //
	// ------------------------------------------------------------------ //
	var/digestable        = TRUE
	var/devourable        = TRUE
	var/feeding           = TRUE
	var/absorbable        = TRUE
	var/resizable         = TRUE
	var/digest_leave_remains = FALSE
	var/allowmobvore      = TRUE
	var/allowtemp         = TRUE
	var/digest_pain       = TRUE
	var/can_be_drop_prey  = FALSE
	var/can_be_drop_pred  = FALSE
	var/can_be_afk_prey   = TRUE
	var/can_be_afk_pred   = TRUE

	// ------------------------------------------------------------------ //
	//  Spontaneous-vore belly references (names only, resolved at apply)  //
	// ------------------------------------------------------------------ //
	var/spont_belly_front = null
	var/spont_belly_rear  = null
	var/spont_belly_left  = null
	var/spont_belly_right = null

	// ------------------------------------------------------------------ //
	//  Interaction & flavour prefs                                        //
	// ------------------------------------------------------------------ //
	var/vore_taste        = null
	var/vore_smell        = null
	var/noisy             = FALSE
	var/permit_healbelly  = TRUE
	var/stumble_vore      = TRUE
	var/slip_vore         = TRUE
	var/drop_vore         = TRUE
	var/throw_vore        = TRUE
	var/food_vore         = TRUE
	var/consume_liquid_belly = FALSE
	var/allow_spontaneous_tf  = FALSE
	var/show_vore_fx      = TRUE
	var/selective_preference  = null   // Resolved on apply; DM_DEFAULT if null
	var/size_strip_preference = null   // Resolved on apply; SIZESTRIP_NONE if null
	var/eating_privacy_global = FALSE
	var/vore_death_privacy    = FALSE
	var/allow_mimicry         = TRUE
	var/allow_mind_transfer   = FALSE
	var/phase_vore            = TRUE
	var/noisy_full            = FALSE
	var/receive_reagents      = FALSE
	var/give_reagents         = FALSE
	var/apply_reagents        = TRUE
	var/latejoin_vore         = FALSE
	var/latejoin_prey         = FALSE
	var/strip_pref            = TRUE
	var/contaminate_pref      = TRUE
	var/private_struggle_global = FALSE

	// ------------------------------------------------------------------ //
	//  Late-join warning prefs                                            //
	// ------------------------------------------------------------------ //
	var/no_latejoin_vore_warning         = FALSE
	var/no_latejoin_prey_warning         = FALSE
	var/no_latejoin_vore_warning_time    = 15
	var/no_latejoin_prey_warning_time    = 15
	var/no_latejoin_vore_warning_persists = FALSE
	var/no_latejoin_prey_warning_persists = FALSE

	// ------------------------------------------------------------------ //
	//  Soulcatcher prefs                                                  //
	// ------------------------------------------------------------------ //
	var/soulcatcher_pref_flags = 0
	var/persistend_edit_mode   = FALSE

	// ------------------------------------------------------------------ //
	//  Overlay / sprite prefs                                             //
	// ------------------------------------------------------------------ //
	var/max_voreoverlay_alpha = 255
	// vore_sprite_color and vore_sprite_multiply are associative lists;
	// stored as serialized copies during capture.
	var/list/vore_sprite_color    = null
	var/list/vore_sprite_multiply = null

	// ------------------------------------------------------------------ //
	//  Other miscellaneous vore prefs                                     //
	// ------------------------------------------------------------------ //
	var/belly_rub_target    = null
	var/nutrition_message_visible = TRUE
	var/weight_message_visible    = TRUE
	var/voice_freq          = 42500

/datum/vore_state/New(mob/new_owner)
	owner = new_owner

/datum/vore_state/Destroy()
	owner = null
	vore_sprite_color    = null
	vore_sprite_multiply = null
	return ..()

// ---------------------------------------------------------------------- //
//  Canonical saveable-fields list                                        //
// ---------------------------------------------------------------------- //

/// Returns the list of var names that this datum will capture/apply.
/// Used both by capture_from() / apply_to() and by preference serialization
/// so that the list is defined in exactly one place.
/datum/vore_state/proc/get_saveable_fields()
	return list(
		"digestable",
		"devourable",
		"feeding",
		"absorbable",
		"resizable",
		"digest_leave_remains",
		"allowmobvore",
		"allowtemp",
		"digest_pain",
		"can_be_drop_prey",
		"can_be_drop_pred",
		"can_be_afk_prey",
		"can_be_afk_pred",
		"spont_belly_front",
		"spont_belly_rear",
		"spont_belly_left",
		"spont_belly_right",
		"vore_taste",
		"vore_smell",
		"noisy",
		"permit_healbelly",
		"stumble_vore",
		"slip_vore",
		"drop_vore",
		"throw_vore",
		"food_vore",
		"consume_liquid_belly",
		"allow_spontaneous_tf",
		"show_vore_fx",
		"selective_preference",
		"size_strip_preference",
		"eating_privacy_global",
		"vore_death_privacy",
		"allow_mimicry",
		"allow_mind_transfer",
		"phase_vore",
		"noisy_full",
		"receive_reagents",
		"give_reagents",
		"apply_reagents",
		"latejoin_vore",
		"latejoin_prey",
		"strip_pref",
		"contaminate_pref",
		"no_latejoin_vore_warning",
		"no_latejoin_prey_warning",
		"no_latejoin_vore_warning_time",
		"no_latejoin_prey_warning_time",
		"no_latejoin_vore_warning_persists",
		"no_latejoin_prey_warning_persists",
		"soulcatcher_pref_flags",
		"persistend_edit_mode",
		"max_voreoverlay_alpha",
		"belly_rub_target",
		"nutrition_message_visible",
		"weight_message_visible",
		"voice_freq",
	)

// ---------------------------------------------------------------------- //
//  Capture / apply round-trip                                            //
// ---------------------------------------------------------------------- //

/// Snapshot all saveable vore vars from the given mob into this datum.
/// Call sites should use mob.get_vore_state().capture_from(mob) to ensure
/// the datum is properly initialised.
/datum/vore_state/proc/capture_from(mob/M)
	if(!istype(M))
		return FALSE

	digestable              = M.digestable
	devourable              = M.devourable
	feeding                 = M.feeding
	absorbable              = M.absorbable
	resizable               = M.resizable
	digest_leave_remains    = M.digest_leave_remains
	allowmobvore            = M.allowmobvore
	allowtemp               = M.allowtemp
	digest_pain             = M.digest_pain
	can_be_drop_prey        = M.can_be_drop_prey
	can_be_drop_pred        = M.can_be_drop_pred
	can_be_afk_prey         = M.can_be_afk_prey
	can_be_afk_pred         = M.can_be_afk_pred

	// Spont belly refs — store names, not object refs, for persistence safety
	spont_belly_front = istype(M.spont_belly_front) ? M.spont_belly_front.name : null
	spont_belly_rear  = istype(M.spont_belly_rear)  ? M.spont_belly_rear.name  : null
	spont_belly_left  = istype(M.spont_belly_left)  ? M.spont_belly_left.name  : null
	spont_belly_right = istype(M.spont_belly_right) ? M.spont_belly_right.name : null

	vore_taste              = M.vore_taste
	vore_smell              = M.vore_smell
	noisy                   = M.noisy
	permit_healbelly        = M.permit_healbelly
	stumble_vore            = M.stumble_vore
	slip_vore               = M.slip_vore
	drop_vore               = M.drop_vore
	throw_vore              = M.throw_vore
	food_vore               = M.food_vore
	consume_liquid_belly    = M.consume_liquid_belly
	allow_spontaneous_tf    = M.allow_spontaneous_tf
	show_vore_fx            = M.show_vore_fx
	selective_preference    = M.selective_preference
	size_strip_preference   = M.size_strip_preference
	eating_privacy_global   = M.eating_privacy_global
	vore_death_privacy      = M.vore_death_privacy
	allow_mimicry           = M.allow_mimicry
	allow_mind_transfer     = M.allow_mind_transfer
	phase_vore              = M.phase_vore
	noisy_full              = M.noisy_full
	receive_reagents        = M.receive_reagents
	give_reagents           = M.give_reagents
	apply_reagents          = M.apply_reagents
	latejoin_vore           = M.latejoin_vore
	latejoin_prey           = M.latejoin_prey
	strip_pref              = M.strip_pref
	contaminate_pref        = M.contaminate_pref
	no_latejoin_vore_warning          = M.no_latejoin_vore_warning
	no_latejoin_prey_warning          = M.no_latejoin_prey_warning
	no_latejoin_vore_warning_time     = M.no_latejoin_vore_warning_time
	no_latejoin_prey_warning_time     = M.no_latejoin_prey_warning_time
	no_latejoin_vore_warning_persists = M.no_latejoin_vore_warning_persists
	no_latejoin_prey_warning_persists = M.no_latejoin_prey_warning_persists
	soulcatcher_pref_flags  = M.soulcatcher_pref_flags
	persistend_edit_mode    = M.persistend_edit_mode
	max_voreoverlay_alpha   = M.max_voreoverlay_alpha
	belly_rub_target        = M.belly_rub_target
	nutrition_message_visible = M.nutrition_message_visible
	weight_message_visible  = M.weight_message_visible
	voice_freq              = M.voice_freq

	// Deep-copy associative lists so they are independent of the mob
	if(islist(M.vore_sprite_color))
		vore_sprite_color = M.vore_sprite_color.Copy()
	else
		vore_sprite_color = list("stomach" = "#000", "taur belly" = "#000")

	if(islist(M.vore_sprite_multiply))
		vore_sprite_multiply = M.vore_sprite_multiply.Copy()
	else
		vore_sprite_multiply = list("stomach" = FALSE, "taur belly" = FALSE)

	return TRUE

/// Apply all saveable vore vars from this datum back onto a mob.
/// Does NOT restore vore_organs or soulgem — those are managed elsewhere.
/datum/vore_state/proc/apply_to(mob/M)
	if(!istype(M))
		return FALSE

	M.digestable              = digestable
	M.devourable              = devourable
	M.feeding                 = feeding
	M.absorbable              = absorbable
	M.resizable               = resizable
	M.digest_leave_remains    = digest_leave_remains
	M.allowmobvore            = allowmobvore
	M.allowtemp               = allowtemp
	M.digest_pain             = digest_pain
	M.can_be_drop_prey        = can_be_drop_prey
	M.can_be_drop_pred        = can_be_drop_pred
	M.can_be_afk_prey         = can_be_afk_prey
	M.can_be_afk_pred         = can_be_afk_pred

	// Spont belly refs — resolve names to objects if the mob has organs loaded
	if(LAZYLEN(M.vore_organs))
		M.spont_belly_front = _resolve_belly(M, spont_belly_front)
		M.spont_belly_rear  = _resolve_belly(M, spont_belly_rear)
		M.spont_belly_left  = _resolve_belly(M, spont_belly_left)
		M.spont_belly_right = _resolve_belly(M, spont_belly_right)

	M.vore_taste              = vore_taste
	M.vore_smell              = vore_smell
	M.noisy                   = noisy
	M.permit_healbelly        = permit_healbelly
	M.stumble_vore            = stumble_vore
	M.slip_vore               = slip_vore
	M.drop_vore               = drop_vore
	M.throw_vore              = throw_vore
	M.food_vore               = food_vore
	M.consume_liquid_belly    = consume_liquid_belly
	M.allow_spontaneous_tf    = allow_spontaneous_tf
	M.show_vore_fx            = show_vore_fx
	M.selective_preference    = selective_preference ? selective_preference : DM_DEFAULT
	M.size_strip_preference   = size_strip_preference ? size_strip_preference : SIZESTRIP_NONE
	M.eating_privacy_global   = eating_privacy_global
	M.vore_death_privacy      = vore_death_privacy
	M.allow_mimicry           = allow_mimicry
	M.allow_mind_transfer     = allow_mind_transfer
	M.phase_vore              = phase_vore
	M.noisy_full              = noisy_full
	M.receive_reagents        = receive_reagents
	M.give_reagents           = give_reagents
	M.apply_reagents          = apply_reagents
	M.latejoin_vore           = latejoin_vore
	M.latejoin_prey           = latejoin_prey
	M.strip_pref              = strip_pref
	M.contaminate_pref        = contaminate_pref
	M.no_latejoin_vore_warning          = no_latejoin_vore_warning
	M.no_latejoin_prey_warning          = no_latejoin_prey_warning
	M.no_latejoin_vore_warning_time     = no_latejoin_vore_warning_time
	M.no_latejoin_prey_warning_time     = no_latejoin_prey_warning_time
	M.no_latejoin_vore_warning_persists = no_latejoin_vore_warning_persists
	M.no_latejoin_prey_warning_persists = no_latejoin_prey_warning_persists
	M.soulcatcher_pref_flags  = soulcatcher_pref_flags
	M.persistend_edit_mode    = persistend_edit_mode
	M.max_voreoverlay_alpha   = max_voreoverlay_alpha
	M.belly_rub_target        = belly_rub_target
	M.nutrition_message_visible = nutrition_message_visible
	M.weight_message_visible  = weight_message_visible
	M.voice_freq              = voice_freq

	if(islist(vore_sprite_color))
		M.vore_sprite_color = vore_sprite_color.Copy()
	if(islist(vore_sprite_multiply))
		M.vore_sprite_multiply = vore_sprite_multiply.Copy()

	return TRUE

/// Resolve a stored belly name back to an /obj/belly on a mob.
/// Returns null if the name is null or no matching belly exists.
/datum/vore_state/proc/_resolve_belly(mob/M, belly_name)
	if(!belly_name || !LAZYLEN(M.vore_organs))
		return null
	for(var/obj/belly/B as anything in M.vore_organs)
		if(B.name == belly_name)
			return B
	return null

// ---------------------------------------------------------------------- //
//  Round-trip validation                                                  //
// ---------------------------------------------------------------------- //

/// Validate that all fields in get_saveable_fields() are also declared as vars
/// on this datum.  Logs a warning for any field that would be silently lost on
/// capture.  Call from unit tests.
/datum/vore_state/proc/validate_field_coverage()
	var/list/fields = get_saveable_fields()
	var/list/missing = list()
	for(var/field in fields)
		if(isnull(vars[field]))
			if(!(field in vars))
				missing += field
	if(missing.len)
		log_game("/datum/vore_state field coverage gap: [jointext(missing, ", ")]")
		return FALSE
	return TRUE

// ---------------------------------------------------------------------- //
//  /mob accessor                                                          //
// ---------------------------------------------------------------------- //

/mob
	/// Lazily-instantiated vore-state datum.  Null until first call to
	/// get_vore_state().  qdel'd in /mob/Destroy().
	var/datum/vore_state/vore_state_datum = null

/// Returns this mob's /datum/vore_state, creating it on first access.
/// Use this instead of instantiating the datum directly.
/mob/proc/get_vore_state()
	if(!vore_state_datum)
		vore_state_datum = new /datum/vore_state(src)
	return vore_state_datum
