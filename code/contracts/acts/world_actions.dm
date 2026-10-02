// World actions (doc/rewrite/final_api.html, section 8 "World actions"): the declaration of each action. `analyze gen actions` reads these
// lines and writes the act type (/datum/act/<name>), act_<name>() (what ACT_TRY calls) and the past-tense notice (/datum/notice/<past>) into
// code/engine/_generated/actions.dm; nothing else is declared by hand.
//
// A name with a slash (hit/projectile) is a subtype that inherits its parent's fields; its proc and ACT_TRY token use an underscore. A field
// named `origin` is declared `origin_turf` (every act has an ORIGIN_* `origin`). Not declared here:
//   - irradiate, injure and body_status carry the body domain's fields (section 14), declared by the body domain.
//   - the op action's act type is the op context (context.dm); only its notice, /datum/notice/op_done, is generated.
//   - the legacy /datum/notice/hit of master (an item used on the holder with no answer) is /datum/notice/legacy_hit.

ACTION(move, turf/origin, turf/destination, direction)
ACTION(z_change, turf/origin, turf/destination)
ACTION(cross, atom/movable/crosser)
ACTION(uncross, atom/movable/crosser)
ACTION(bump, atom/bumped)
ACTION(stumbled_into, atom/movable/stumbled)
ACTION(fall, turf/landing, mob/living/landed_on)
ACTION(thrown_hit, atom/movable/thrown)
ACTION(hit, datum/damage_packet/packet)
ACTION(hit/projectile)
ACTION(hit/melee)
ACTION(hit/explosion)
ACTION(hit/emp)
ACTION(hit/blob)
ACTION(hit/fire)
ACTION(hit/shock)
ACTION(irradiate)
ACTION(injure)
ACTION(body_status, notice = /datum/notice/body_status_changed)
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
