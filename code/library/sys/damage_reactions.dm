// Hits that land nothing and reflection. What a type does when it is hit is a hook on the hit action in its CAPABILITIES block
// (extend(/datum/act/hit/emp, instead(...)), on_notice(/datum/notice/hit/emp, ...)); see code/game/atom/damage_packet.dm.

/// For an entry that lands nothing through a packet (a zero-damage round, a pulse on a type
/// that takes no ionic damage, a mob family's own explosion ladder): delivers an empty packet so
/// the type's hit hooks for `entry` fire. Returns TRUE if a hook cancelled the hit.
/atom/proc/react_to_entry(entry, severity = 0, atom/source = null, atom/attacker = null)
	var/datum/damage_packet/packet = damage_packet(source, attacker, null, null, DAMAGE_PACKET_SILENT, 0, 0, null, entry, severity)
	// The engine's hit action first (a silent entry is a hit too: an EMP or a blast that lands no integrity loss still reaches the hooks).
	var/hit = (entry == DAMAGE_ENTRY_PROJECTILE && projectile_hit_open(src)) ? ACT_PASS : hit_try(src, packet) // bullet_act() already started the round's hit action
	if(isnull(hit))
		packet.release()
		return TRUE
	act_done(hit)
	packet.release()
	return FALSE

/// One round's open hit: the hit action and packet bullet_act() started on `target_ref`, until projectile_hit_end(). The record holds the
/// only reference to the open hit action until then, so they are relations, not handles.
/datum/projectile_hit
	/// The target atom (as a ref) the hit action was started for.
	var/target_ref
	var/datum/act/hit_act
	var/datum/damage_packet/hit_packet

CAPABILITIES(/datum/projectile_hit)
	ref_one(nameof(hit_act))
	ref_one(nameof(hit_packet))

/// The open hits, oldest first. A round whose on_hit() fires another round nests: each target has its own record, so the inner hit ends
/// without disturbing the outer one.
GLOBAL_LIST_EMPTY(projectile_hits)

/// The open hit started on `target` for the round being resolved, if any. The damage packet the round delivers next reuses its action
/// (receive_damage() and react_to_entry() neither start the hit action a second time nor run the hooks again).
/proc/projectile_hit_open(atom/target)
	var/token = ref(target)
	for(var/i in length(GLOB.projectile_hits) to 1 step -1)
		var/datum/projectile_hit/open = GLOB.projectile_hits[i]
		if(open.target_ref == token)
			return open
	return null

/// Starts the round's hit action ahead of the round's own effects (on_hit(): stun, embed, reagents ...), so a veto (a hook
/// that takes the hit over) stops those too, a zero-damage round included. Returns TRUE if a hook vetoed. Otherwise records
/// the open hit so the damage packet the round delivers next reuses the action (projectile_hit_end() ends it). Safe to call
/// again for the same target while the action is open: it does nothing and returns FALSE.
/atom/proc/projectile_hit_begin(obj/item/projectile/P)
	if(projectile_hit_open(src))
		return FALSE
	var/datum/damage_packet/packet = damage_packet(P, P.firer, null, null, DAMAGE_PACKET_SILENT | DAMAGE_PACKET_PROJECTILE, 0, 0, null, DAMAGE_ENTRY_PROJECTILE)
	var/hit = hit_try(src, packet)
	if(isnull(hit))
		packet.release()
		return TRUE
	var/datum/projectile_hit/open = new
	open.target_ref = ref(src)
	if(isdatum(hit)) // ACT_PASS is not an action: act_done() ignores it
		rel_set(open, nameof(open.hit_act), hit)
	rel_set(open, nameof(open.hit_packet), packet)
	rel_add(GLOB, nameof(GLOB.projectile_hits), open)
	return FALSE

/// Ends the hit action projectile_hit_begin() started on this atom, if any.
/atom/proc/projectile_hit_end()
	var/datum/projectile_hit/open = projectile_hit_open(src)
	if(!open)
		return
	rel_remove(GLOB, nameof(GLOB.projectile_hits), open)
	var/datum/act/hit = open.hit_act
	var/datum/damage_packet/packet = open.hit_packet
	rel_clear(open, nameof(open.hit_act))
	rel_clear(open, nameof(open.hit_packet))
	qdel(open)
	act_done(hit)
	packet?.release()

// ---- reflects(kinds, chance): projectiles bounce back ----

/// The holder bounces matching projectiles back towards where they were fired from (bullet_act asks
/// reflect_projectile()), instead of being hit.
/datum/capability/reflects
	/// Projectile type paths, or the obj damage types BRUTE / BURN.
	var/list/kinds
	/// Percent: a number, or a PROC_REF of a holder proc answering it (a legacy REFLECTS() may name a var).
	var/chance = 100

/// Projectiles matching `kinds` (projectile type paths, or BRUTE / BURN) bounce with `chance` percent (a number, or
/// a PROC_REF of a holder proc answering it).
/proc/reflects(list/kinds, chance = 100)
	if(!islist(kinds))
		CRASH("reflects(): kinds must be a list of projectile types or BRUTE / BURN")
	var/datum/capability/reflects/C = new
	C.kinds = kinds.Copy()
	C.chance = chance
	return C

/// The holder's reflect chance now.
/datum/capability/reflects/proc/chance_for(atom/holder)
	if(isnum(chance))
		return chance
	if(hascall(holder, chance))
		return holder_call(holder, chance)
	return lifecycle_decl_value(holder, chance) // legacy REFLECTS(..., "var_name")

/// Bounces `P` back towards where it came from if this atom reflects it (reflects()). Returns TRUE
/// when it did (the caller returns PROJECTILE_CONTINUE: the round keeps flying).
/atom/proc/reflect_projectile(obj/item/projectile/P)
	var/datum/capability/reflects/C = cap_of(src, /datum/capability/reflects)
	if(!C || !P?.starting)
		return FALSE
	var/matched = FALSE
	var/damage_type = P.obj_damage_type()
	for(var/kind in C.kinds)
		if(ispath(kind) ? istype(P, kind) : (kind == damage_type))
			matched = TRUE
			break
	if(!matched || !prob(C.chance_for(src)))
		return FALSE
	act_message(src, P, null, MSG_OTHERS(span_danger("%U% reflects %T%!")))
	var/new_x = P.starting.x + pick(0, 0, -1, 1, -2, 2, -2, 2, -2, 2, -3, 3, -3, 3)
	var/new_y = P.starting.y + pick(0, 0, -1, 1, -2, 2, -2, 2, -2, 2, -3, 3, -3, 3)
	P.redirect(new_x, new_y, get_turf(src), src)
	P.reflected = TRUE
	return TRUE
