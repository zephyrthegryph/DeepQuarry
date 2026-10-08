// Damage reactions: runtime (doc/rewrite/reactions.md section 1b, macros in code/__defines/sys_damage_reactions.dm).
//
// A damage reaction is a before_op / after_op reaction on a damage key (damage(trigger)), declared in reactions() or
// contributed by a capability. The composed reaction table of the type (code/datums/reactions/reactions.dm) keeps
// them as rows, list(trigger, handler, phase) in declaration order (parents first), so receive_damage() reads one
// cached list per hit: a type with no damage reactions pays one table read and goes straight to its sink.

/// The damage key of `trigger` (a DAMAGE_* kind or entry): before_op(damage(DAMAGE_EMP), PROC_REF(x)).
/proc/damage(trigger)
	return "[DAMAGE_KEY_PREFIX][trigger]"

/// The damage rows of A's type (list(trigger, handler, phase), parents first), or null when it has none.
/proc/damage_rows_of(atom/A)
	var/datum/rx_table/T = GLOB.rx_tables?[A.type]
	if(isnull(T))
		T = rx_table_build(A)
	return T ? T.damage_rows : null

/// TRUE when A's type has after_op damage rows.
/proc/damage_rows_after(atom/A)
	var/datum/rx_table/T = rx_table_of(A)
	return T ? T.damage_after : FALSE

/// rx_table_add() hook: records a before_op / after_op reaction on a damage key as a damage row (one row per trigger,
/// handler and phase: a declaration repeated further down the tree, or by a capability and its holder, runs once).
/proc/rx_table_add_damage(datum/rx_table/T, datum/reaction/R)
	if(!istext(R.key) || copytext(R.key, 1, length(DAMAGE_KEY_PREFIX) + 1) != DAMAGE_KEY_PREFIX)
		return
	var/trigger = text2num(copytext(R.key, length(DAMAGE_KEY_PREFIX) + 1))
	var/phase = R.kind == RXN_AFTER_OP ? DAMAGE_REACTION_PHASE_AFTER : DAMAGE_REACTION_PHASE_BEFORE
	for(var/list/row as anything in T.damage_rows)
		if(row[1] == trigger && row[2] == R.handler && row[3] == phase)
			return
	// Flyweight or pooled framework bookkeeping: the framework is the accessor, not a holder of a relation
	LAZYADD(T.damage_rows, list(list(trigger, R.handler, phase)))
	if(phase == DAMAGE_REACTION_PHASE_AFTER)
		T.damage_after = TRUE

// ---- the hook on receive_damage() ----

/// Runs the rows of `phase` that match the packet. Returns DAMAGE_REACTION_BLOCK if one blocked.
/atom/proc/run_damage_reactions(list/rows, datum/damage_packet/packet, phase)
	var/entry = packet.entry
	var/list/amounts = packet.amounts
	var/pre_reacted = (phase == DAMAGE_REACTION_PHASE_BEFORE) && (packet.flags & DAMAGE_PACKET_PRE_REACTED)
	for(var/list/row as anything in rows)
		if(row[3] != phase)
			continue
		var/trigger = row[1]
		if(pre_reacted && trigger == entry)
			continue // ran already, ahead of the entry's own effects
		if(trigger != entry && (trigger > DAMAGE_KIND_COUNT || amounts[trigger] <= 0))
			continue
		var/answer = holder_call(src, row[2], packet)
		if(phase == DAMAGE_REACTION_PHASE_BEFORE && (isnum(answer) ? (answer & DAMAGE_REACTION_BLOCK) : !isnull(answer)))
			packet.flags |= DAMAGE_PACKET_BLOCKED
			return DAMAGE_REACTION_BLOCK
		if(QDELETED(src))
			packet.flags |= DAMAGE_PACKET_BLOCKED
			return DAMAGE_REACTION_BLOCK
	return 0

/// For an entry that lands nothing through a packet (a zero-damage round, a pulse on a type
/// that takes no ionic damage, a mob family's own explosion ladder): delivers an empty packet so
/// the type's reactions to `entry` fire. Returns TRUE if a reaction blocked the hit.
/atom/proc/react_to_entry(entry, severity = 0, atom/source = null, atom/attacker = null)
	var/datum/damage_packet/packet = damage_packet(source, attacker, null, null, DAMAGE_PACKET_SILENT, 0, 0, null, entry, severity)
	// The engine's hit action first (a silent entry is a hit too: an EMP or a blast that lands no integrity loss still reaches the hooks).
	var/hit = (entry == DAMAGE_ENTRY_PROJECTILE) ? ACT_PASS : hit_try(src, packet) // a round reaches the hit action through its own damage packet
	if(isnull(hit))
		packet.release()
		return TRUE
	if(!damage_rows_of(src))
		act_done(hit)
		packet.release()
		return FALSE
	if(entry == DAMAGE_ENTRY_PROJECTILE && GLOB.projectile_pre_reacted == ref(src))
		packet.flags |= DAMAGE_PACKET_PRE_REACTED
	. = react_to_packet(packet)
	act_done(hit)
	packet.release()

/// The target (as a ref) whose DAMAGE_PROJECTILE BEFORE reactions bullet_act() has already run
/// for the round being resolved, so the packet adapters don't run them again.
GLOBAL_VAR_INIT(projectile_pre_reacted, null)

/// Runs the DAMAGE_PROJECTILE BEFORE reactions ahead of the round's own effects (on_hit(): stun,
/// embed, reagents ...), so a blocking reaction (a shield, an immunity) stops those too, as the old
/// bullet_act() cancel did. Returns TRUE if one blocked. Otherwise marks the target so the damage
/// packet the round delivers next doesn't run them a second time (end_projectile_reactions()).
/atom/proc/projectile_pre_reactions(obj/item/projectile/P)
	var/list/rows = damage_rows_of(src)
	if(!rows)
		return FALSE
	var/datum/damage_packet/packet = damage_packet(P, P.firer, null, null, DAMAGE_PACKET_SILENT | DAMAGE_PACKET_PROJECTILE, 0, 0, null, DAMAGE_ENTRY_PROJECTILE)
	. = !!run_damage_reactions(rows, packet, DAMAGE_REACTION_PHASE_BEFORE)
	packet.release()
	if(!.)
		GLOB.projectile_pre_reacted = ref(src)

/atom/proc/end_projectile_reactions()
	if(GLOB.projectile_pre_reacted == ref(src))
		GLOB.projectile_pre_reacted = null

/// Runs the reactions (both phases) to a packet that carries nothing, without the sink.
/// Returns TRUE if a reaction blocked the hit.
/atom/proc/react_to_packet(datum/damage_packet/packet)
	var/list/rows = damage_rows_of(src)
	if(!rows)
		return FALSE
	if(run_damage_reactions(rows, packet, DAMAGE_REACTION_PHASE_BEFORE))
		return TRUE
	if(damage_rows_after(src) && !QDELETED(src))
		run_damage_reactions(rows, packet, DAMAGE_REACTION_PHASE_AFTER)
	return FALSE

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

// ---- shared reaction procs ----

/// A hit through the trigger lands nothing (the entry's own effects before the packet, such as
/// a projectile's on_hit(), still ran). `. += before_op(damage(DAMAGE_PROJECTILE), TYPE_PROC_REF(/atom, damage_reaction_block))`
/atom/proc/damage_reaction_block(datum/damage_packet/packet)
	return DAMAGE_REACTION_BLOCK

/// The hit destroys the holder outright (an explosion on something with no integrity).
/atom/proc/damage_reaction_qdel(datum/damage_packet/packet)
	destroyed(src)
	return DAMAGE_REACTION_BLOCK

/// Damage keeps its key interpretation and cached rows outside the engine.
/datum/rx_table/add_domain_reaction(datum/reaction/R)
	rx_table_add_damage(src, R)
