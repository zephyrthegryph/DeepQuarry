// Subtypes inherit latent_safe by path until one sets it to FALSE.
/datum/base/child
	var/datum/child_ref
	var/tmp/datum/child_tmp

/datum/base/child/proc/state_codecs()
	return list("child_codec_ref" = /datum/state_codec/owned,
		"leaked_ref" = /datum/state_codec/borrowed)

/datum/base/child
	var/datum/child_codec_ref
	var/list/datum/child_list

/datum/base/child/grandchild
	var/datum/grand_ref

/datum/base/unsafe
	latent_safe = FALSE
	var/datum/unsafe_ref

/datum/base/unsafe/deeper
	var/datum/deeper_ref

/datum/base/unsafe/again
	latent_safe = 1
	var/datum/again_ref

/datum/base/off
	latent_safe = 0
	var/datum/off_ref

/datum/not_latent
	var/datum/not_latent_ref

/datum/typo
	latent_safe = TRUEX
	var/datum/typo_ref

/datum/typo2
	latent_safe = 10
	var/datum/typo2_ref

/datum/commented_latent
	// latent_safe = TRUE
	var/datum/commented_latent_ref

/datum/only_latent
	latent_safe=TRUE // trailing comment

/datum/state_codec/owned

// Implicit roots: /obj and /mob chain through /atom/movable and /atom.
/atom
	var/atom/atom_ref
	var/tmp/atom/atom_tmp

/atom/movable
	var/atom/movable/movable_ref

/obj/safe_obj
	latent_safe = TRUE
	var/obj/obj_ref
	var/list/mob/obj_list

/obj/safe_obj/proc/state_codecs()
	return list("movable_ref" = /datum/state_codec/owned)

/mob/safe_mob
	latent_safe = TRUE
	var/mob/mob_ref

/turf/safe_turf
	latent_safe = TRUE
	var/turf/turf_ref
	var/obj/turf_obj

/turf
	var/turf/base_turf_ref

/area/safe_area
	latent_safe = TRUE
	var/area/area_ref

/area
	var/area/base_area_ref

/client/safe_client
	latent_safe = TRUE
	var/client/client_ref
	var/datum/client_datum

// A type with an unrelated root: no implicit parents.
/image/safe_image
	latent_safe = TRUE
	var/image/image_ref

// Codec declared far away on a different type does not apply.
/datum/unrelated/proc/state_codecs()
	return list("leaked_ref" = /datum/state_codec/owned)
// a codec with a bare string that is not a state_codec
/datum/base/proc/state_codecs()
	return list("plain" = 5)
