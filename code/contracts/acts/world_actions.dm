// World actions (doc/rewrite/final_api.html, section 8 "World actions"): the declaration of each action. `analyze gen actions` reads these
// lines and writes the act type (/datum/act/<name>), act_<name>() (what ACT_TRY calls) and the past-tense notice (/datum/notice/<past>) into
// code/engine/_generated/actions.dm; nothing else is declared by hand.
//
// A name with a slash (hit/projectile) is a subtype that inherits its parent's fields; its proc and ACT_TRY token use an underscore. A field
// named `origin` is declared `origin_turf` (every act has an ORIGIN_* `origin`). Not declared here:
//   - irradiate, injure and body_status carry the body domain's fields (section 14), declared by the body domain.
//   - the op action's act type is the op context (context.dm); only its notice, /datum/notice/op_done, is generated.
//   - an item used on the holder with no answer is the attackby action's notice, /datum/notice/attacked_by.

ACTION(move, turf/origin, turf/destination, direction)
ACTION(z_change, turf/origin, turf/destination)
ACTION(cross, atom/movable/crosser)
ACTION(uncross, atom/movable/crosser)
// bump is published on the BUMPED atom (the door, the pod, the wall): `bumper` walked into it heading `direction`. One emitter,
// /atom/movable/proc/bump_into() (atoms_movable.dm), which the movement path's Bump() and a mech's push both call.
ACTION(bump, atom/movable/bumper, atom/bumped, direction)
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
// A simple mob's, a xeno's or a bot's generic attack (the old attack_generic()), started by generic_hit() before anything lands: `packet` names the
// attacker and DAMAGE_ENTRY_GENERIC and carries no amounts; `damage` is what the default attack would deal. A takeover (instead) is the target's
// own answer; otherwise the default attack lands.
ACTION(hit/generic, mob/attacker, damage, attack_verb)
ACTION(irradiate, effect, blocked, check_protection, rad_protection)
ACTION(injure, kind, amount, zone, atom/cause, flags)
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
// Gates the legacy before/ events were: an emit site asks the action first and goes on only when nothing refused or took it over. A caller that has a
// result to give back (a flag word, a name) reads ACT_REPLY of the hook that took it over. See doc/rewrite/codemod_rules.md.
ACTION(attackby, obj/item/item, mob/user, params, notice = /datum/notice/attacked_by)
ACTION(attack_hand, mob/user, notice = /datum/notice/hand_attacked)
ACTION(attack_self, mob/user, notice = /datum/notice/self_attacked)
ACTION(tool_act, tool_quality, secondary, mob/user, obj/item/tool, notice = /datum/notice/tool_acted)
ACTION(pre_attack, atom/target_, mob/user, params, notice = /datum/notice/pre_attacked)
ACTION(pre_move, direction, atom/destination, notice = /datum/notice/pre_moved)
ACTION(check_insert, atom/movable/thing, slot_id, notice = /datum/notice/insert_checked)
ACTION(check_remove, atom/movable/thing, slot_id, notice = /datum/notice/remove_checked)
ACTION(emp, severity, protection, notice = /datum/notice/emp_felt)
ACTION(explode, severity, notice = /datum/notice/exploded)
ACTION(shoot, obj/item/projectile/projectile, def_zone, notice = /datum/notice/shot)
ACTION(play_cinematic, datum/cinematic/cinematic, notice = /datum/notice/cinematic_played)
ACTION(draw_hud, notice = /datum/notice/hud_drawn)
ACTION(draw_health_icon, notice = /datum/notice/health_icon_drawn)
ACTION(relay_movement, direction, notice = /datum/notice/movement_relayed)
ACTION(live_radiation, notice = /datum/notice/radiation_lived)
ACTION(geiger_scan, mob/user, obj/item/geiger/counter, notice = /datum/notice/geiger_scanned)
ACTION(flush_disposal, items, datum/gas_mixture/gas, notice = /datum/notice/disposal_flushed)
ACTION(send_disposal, obj/structure/disposalholder/packet, notice = /datum/notice/disposal_sent)
ACTION(name_voice, notice = /datum/notice/voice_named)
ACTION(name_alt, notice = /datum/notice/alt_named)
ACTION(name_visible, notice = /datum/notice/visibly_named)
ACTION(op, datum/op_plan/op, provider, notice = /datum/notice/op_done)

// Mob Life (code/library/mob/statuses.dm, code/modules/mob/living/life/living_systems.dm). Nothing refuses these; their notices keep the names
// the OM events' twins had, which remote view observes.
ACTION(living_status_stun, amount, FIXED, notice = /datum/notice/living_status_stun)
ACTION(living_status_weaken, amount, FIXED, notice = /datum/notice/living_status_weaken)
ACTION(living_status_paralyze, amount, FIXED, notice = /datum/notice/living_status_paralyze)
ACTION(living_status_sleep, amount, FIXED, notice = /datum/notice/living_status_sleep)
ACTION(living_status_blind, amount, FIXED, notice = /datum/notice/living_status_blind)
ACTION(mob_handle_vision, FIXED, notice = /datum/notice/mob_handle_vision)
ACTION(mob_handle_hud_darksight, FIXED, notice = /datum/notice/mob_handle_hud_darksight)
/// A shuttle's schedule (departure, arrival, ETA) changed: status displays redraw.
ACTION(shuttle_schedule_change, FIXED, notice = /datum/notice/shuttle_schedule_changed)
// modes() (code/engine/actions/modes.dm): the holder's mode capability changed. FIXED: nothing refuses a mode change; the var already holds the new one.
ACTION(mode_change, old_mode, new_mode, mode_var, FIXED)
// standing() (code/engine/stats/standings.dm): a standing row of the holder was placed, replaced or went; its cached standings are dropped. `subject_key` is the row's key.
ACTION(standing_change, subject_key, FIXED)
// A belly of the holder changed what it shows of the holder's body: prey or items entered or left it, its liquid or a prey's health moved its size, or its sprite settings were edited. The holder recomputes its tracked fullness.
ACTION(belly_change, FIXED, notice = /datum/notice/belly_changed)
