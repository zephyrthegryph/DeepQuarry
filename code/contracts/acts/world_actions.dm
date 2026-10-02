// World actions (doc/rewrite/final_api.html, section 8 "World actions"): the act types and the past-tense notices that
// ACTION() generates, hand-declared for E0 so the contracts, the driver and the proofs can name them. Vars only: the
// typed act_x() procs, ACT_TRY and the notice delivery are E4's. E4's generator reads the ACTION() lines below and emits
// the same types into code/engine/_generated/, at which point this file's type blocks are deleted and the ACTION() lines
// stay as the declaration (section 22: "ACTION lines in code/contracts/acts").
//
// Not declared here, because the name is taken on master or the fields belong to another section:
//   - /datum/notice/hit and its subtypes: master's /datum/notice/hit (code/datums/reactions) is a live notice with its own
//     fields. E4 retires it in the same change that declares hit/<entry>.
//   - irradiate, injure and body_status carry the body domain's fields (section 14), declared by the body domain.
//   - the op action itself, /datum/act/op (context.dm), whose notice is /datum/notice/op_done.

ACTION(move, turf/origin, turf/destination, direction)
ACTION(z_change, turf/origin, turf/destination)
ACTION(cross, atom/movable/crosser)
ACTION(uncross, atom/movable/crosser)
ACTION(bump, atom/bumped)
ACTION(stumbled_into, atom/movable/stumbled)
ACTION(fall, turf/landing, mob/living/landed_on)
ACTION(thrown_hit, atom/movable/thrown)
ACTION(hit, datum/damage_packet/packet)
ACTION(irradiate)
ACTION(injure)
ACTION(body_status)
ACTION(insert, atom/movable/item, slot_id)
ACTION(remove, atom/movable/item, slot_id)
ACTION(equip, obj/item/item, slot_id)
ACTION(unequip, obj/item/item, slot_id)
ACTION(buckle, mob/living/buckled)
ACTION(unbuckle, mob/living/unbuckled)
ACTION(climb, atom/climbed)
ACTION(speak, message, language)
ACTION(emote, emote_key)
ACTION(slash, mob/living/slasher, FIXED)
ACTION(op, datum/op_def/op, provider, notice = /datum/notice/op_done)

/datum/act/move
	parent_type = /datum/act/action
	/// The design names this `origin`, which is the ORIGIN_* field of every action: renamed.
	var/turf/origin_turf
	var/turf/destination
	var/direction

/datum/act/z_change
	parent_type = /datum/act/action
	/// As in move: `origin_turf`, not `origin`.
	var/turf/origin_turf
	var/turf/destination

/datum/act/cross
	parent_type = /datum/act/action
	var/atom/movable/crosser

/datum/act/uncross
	parent_type = /datum/act/action
	var/atom/movable/crosser

/datum/act/bump
	parent_type = /datum/act/action
	var/atom/bumped

/datum/act/stumbled_into
	parent_type = /datum/act/action
	var/atom/movable/stumbled

/datum/act/fall
	parent_type = /datum/act/action
	var/turf/landing
	var/mob/living/landed_on

/datum/act/thrown_hit
	parent_type = /datum/act/action
	var/atom/movable/thrown

/datum/act/hit
	parent_type = /datum/act/action
	var/datum/damage_packet/packet

/datum/act/hit/projectile
	// no typed fields of its own: it inherits its parent's

/datum/act/hit/melee
	// no typed fields of its own: it inherits its parent's

/datum/act/hit/explosion
	// no typed fields of its own: it inherits its parent's

/datum/act/hit/emp
	// no typed fields of its own: it inherits its parent's

/datum/act/hit/blob
	// no typed fields of its own: it inherits its parent's

/datum/act/hit/fire
	// no typed fields of its own: it inherits its parent's

/datum/act/hit/shock
	// no typed fields of its own: it inherits its parent's

/datum/act/irradiate
	parent_type = /datum/act/action

/datum/act/injure
	parent_type = /datum/act/action

/datum/act/body_status
	parent_type = /datum/act/action

/datum/act/insert
	parent_type = /datum/act/action
	var/atom/movable/item
	var/slot_id

/datum/act/remove
	parent_type = /datum/act/action
	var/atom/movable/item
	var/slot_id

/datum/act/equip
	parent_type = /datum/act/action
	var/obj/item/item
	var/slot_id

/datum/act/unequip
	parent_type = /datum/act/action
	var/obj/item/item
	var/slot_id

/datum/act/buckle
	parent_type = /datum/act/action
	var/mob/living/buckled

/datum/act/unbuckle
	parent_type = /datum/act/action
	var/mob/living/unbuckled

/datum/act/climb
	parent_type = /datum/act/action
	var/atom/climbed

/datum/act/speak
	parent_type = /datum/act/action
	var/message
	var/language

/datum/act/emote
	parent_type = /datum/act/action
	var/emote_key

/datum/act/slash
	parent_type = /datum/act/action
	var/mob/living/slasher

/datum/notice/moved
	// master's /datum/notice/moved already carries `direction`; only the turfs are added here
	var/turf/origin_turf
	var/turf/destination

/datum/notice/z_changed
	var/turf/origin_turf
	var/turf/destination

/datum/notice/crossed
	var/atom/movable/crosser

/datum/notice/uncrossed
	var/atom/movable/crosser

/datum/notice/bumped
	var/atom/bumped

/datum/notice/stumbled_into
	var/atom/movable/stumbled

/datum/notice/fell
	var/turf/landing
	var/mob/living/landed_on

/datum/notice/thrown_hit
	var/atom/movable/thrown

/datum/notice/irradiated
	// fields: the body domain's (section 14)

/datum/notice/injured
	// fields: the body domain's (section 14)

/datum/notice/body_status_changed
	// fields: the body domain's (section 14)

/datum/notice/inserted
	var/atom/movable/item
	var/slot_id

/datum/notice/removed
	var/atom/movable/item
	var/slot_id

/datum/notice/equipped
	var/obj/item/item
	var/slot_id

/datum/notice/unequipped
	var/obj/item/item
	var/slot_id

/datum/notice/buckled
	var/mob/living/buckled

/datum/notice/unbuckled
	var/mob/living/unbuckled

/datum/notice/climbed
	var/atom/climbed

/datum/notice/spoke
	var/message
	var/language

/datum/notice/emoted
	var/emote_key

/datum/notice/slashed
	var/mob/living/slasher

/// The notice every op publishes when it commits with a successful roll (on_op listens for it); carries the op key chain.
/datum/notice/op_done
	var/key
	var/outcome
