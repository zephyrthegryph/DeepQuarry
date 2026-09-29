// Declared damage reactions: runtime (doc/rewrite/systems.md section 12, macros in
// code/__defines/sys_damage_reactions.dm).
//
// The declarations live in the type's lifecycle declaration table (built once per type, shared
// by every instance). receive_damage() reads the table once per hit: a type with no reactions
// pays one cached list read and goes straight to its sink.

/datum/lifecycle_decls
	/// DAMAGE_REACTION rows: list(trigger, proc_ref, phase), in declaration order (parents first).
	var/list/damage_reactions
	/// TRUE when a row has DAMAGE_REACTION_PHASE_AFTER.
	var/damage_reactions_after = FALSE
	/// REFLECTS: list(kinds, chance).
	var/list/reflects
	/// EMP_DISABLE: list(duration, field).
	var/list/emp_disable

/datum/lifecycle_decls/proc/add_damage_reaction(trigger, proc_ref, phase)
	for(var/list/row as anything in damage_reactions)
		if(row[1] == trigger && row[2] == proc_ref && row[3] == phase)
			return // declared again further down the tree: one row
	LAZYADD(damage_reactions, list(list(trigger, proc_ref, phase)))
	if(phase == DAMAGE_REACTION_PHASE_AFTER)
		damage_reactions_after = TRUE

/datum/lifecycle_decls/proc/set_reflects(list/kinds, chance)
	reflects = list(kinds, chance)

/datum/lifecycle_decls/proc/set_emp_disable(duration, field)
	emp_disable = list(duration, field)
	add_damage_reaction(DAMAGE_ENTRY_EMP, TYPE_PROC_REF(/atom, emp_disable_react), DAMAGE_REACTION_PHASE_BEFORE)
	add_expiry_hook(field, CLOCK_WORLD, TYPE_PROC_REF(/atom, emp_disable_lapsed), TRUE)

/// Validation and work bits for the reaction declarations (called from finish()).
/datum/lifecycle_decls/proc/finish_damage_reactions(datum/D)
	if(emp_disable && !(emp_disable[2] in D.vars))
		stack_trace("EMP_DISABLE([owner_type], \"[emp_disable[2]]\"): no such var; dropped")
		emp_disable = null
		for(var/list/row as anything in damage_reactions?.Copy())
			if(row[2] == TYPE_PROC_REF(/atom, emp_disable_react))
				damage_reactions -= list(row)
		if(!length(damage_reactions))
			damage_reactions = null
	if(reflects && !islist(reflects[1]))
		stack_trace("REFLECTS([owner_type]): kinds must be a list; dropped")
		reflects = null
	if(damage_reactions || reflects)
		work |= DECL_WORK_REACT

// ---- the hook on receive_damage() ----

/// Runs the rows of `phase` that match the packet. Returns DAMAGE_REACTION_BLOCK if one blocked.
/atom/proc/run_damage_reactions(datum/lifecycle_decls/decls, datum/damage_packet/packet, phase)
	var/entry = packet.entry
	var/list/amounts = packet.amounts
	var/pre_reacted = (phase == DAMAGE_REACTION_PHASE_BEFORE) && (packet.flags & DAMAGE_PACKET_PRE_REACTED)
	for(var/list/row as anything in decls.damage_reactions)
		if(row[3] != phase)
			continue
		var/trigger = row[1]
		if(pre_reacted && trigger == entry)
			continue // ran already, ahead of the entry's own effects
		if(trigger != entry && (trigger > DAMAGE_KIND_COUNT || amounts[trigger] <= 0))
			continue
		if(call(src, row[2])(packet) & DAMAGE_REACTION_BLOCK)
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
	var/datum/lifecycle_decls/decls = lifecycle_decls_of(src)
	if(!decls?.damage_reactions)
		return FALSE
	var/datum/damage_packet/packet = damage_packet(source, attacker, null, null, DAMAGE_PACKET_SILENT, 0, 0, null, entry, severity)
	if(entry == DAMAGE_ENTRY_PROJECTILE && GLOB.projectile_pre_reacted == ref(src))
		packet.flags |= DAMAGE_PACKET_PRE_REACTED
	. = react_to_packet(packet)
	packet.release()

/// The target (as a ref) whose DAMAGE_PROJECTILE BEFORE reactions bullet_act() has already run
/// for the round being resolved, so the packet adapters don't run them again.
GLOBAL_VAR_INIT(projectile_pre_reacted, null)

/// Runs the DAMAGE_PROJECTILE BEFORE reactions ahead of the round's own effects (on_hit(): stun,
/// embed, reagents ...), so a blocking reaction (a shield, an immunity) stops those too, as the old
/// bullet_act() cancel did. Returns TRUE if one blocked. Otherwise marks the target so the damage
/// packet the round delivers next doesn't run them a second time (end_projectile_reactions()).
/atom/proc/projectile_pre_reactions(obj/item/projectile/P)
	var/datum/lifecycle_decls/decls = lifecycle_decls_of(src)
	if(!decls?.damage_reactions)
		return FALSE
	var/datum/damage_packet/packet = damage_packet(P, P.firer, null, null, DAMAGE_PACKET_SILENT | DAMAGE_PACKET_PROJECTILE, 0, 0, null, DAMAGE_ENTRY_PROJECTILE)
	. = !!run_damage_reactions(decls, packet, DAMAGE_REACTION_PHASE_BEFORE)
	packet.release()
	if(!.)
		GLOB.projectile_pre_reacted = ref(src)

/atom/proc/end_projectile_reactions()
	if(GLOB.projectile_pre_reacted == ref(src))
		GLOB.projectile_pre_reacted = null

/// Runs the reactions (both phases) to a packet that carries nothing, without the sink.
/// Returns TRUE if a reaction blocked the hit.
/atom/proc/react_to_packet(datum/damage_packet/packet)
	var/datum/lifecycle_decls/decls = lifecycle_decls_of(src)
	if(!decls?.damage_reactions)
		return FALSE
	if(run_damage_reactions(decls, packet, DAMAGE_REACTION_PHASE_BEFORE))
		return TRUE
	if(decls.damage_reactions_after && !QDELETED(src))
		run_damage_reactions(decls, packet, DAMAGE_REACTION_PHASE_AFTER)
	return FALSE

// ---- REFLECTS ----

/// Bounces `P` back towards where it came from if this atom's type REFLECTS it. Returns TRUE
/// when it did (the caller returns PROJECTILE_CONTINUE: the round keeps flying).
/atom/proc/reflect_projectile(obj/item/projectile/P)
	var/datum/lifecycle_decls/decls = lifecycle_decls_of(src)
	var/list/reflects = decls?.reflects
	if(!reflects || !P?.starting)
		return FALSE
	var/matched = FALSE
	var/damage_type = P.obj_damage_type()
	for(var/kind in reflects[1])
		if(ispath(kind) ? istype(P, kind) : (kind == damage_type))
			matched = TRUE
			break
	if(!matched || !prob(lifecycle_decl_value(src, reflects[2])))
		return FALSE
	act_message(src, P, null, MSG_OTHERS(span_danger("%U% reflects %T%!")))
	var/new_x = P.starting.x + pick(0, 0, -1, 1, -2, 2, -2, 2, -2, 2, -3, 3, -3, 3)
	var/new_y = P.starting.y + pick(0, 0, -1, 1, -2, 2, -2, 2, -2, 2, -3, 3, -3, 3)
	P.redirect(new_x, new_y, get_turf(src), src)
	P.reflected = TRUE
	return TRUE

// ---- EMP_DISABLE ----

/// The EMP_DISABLE reaction: disable for duration / severity unless already disabled.
/atom/proc/emp_disable_react(datum/damage_packet/packet)
	var/list/spec = lifecycle_decls_of(src)?.emp_disable
	if(!spec)
		return
	var/field = spec[2]
	if(vars[field] > EXPIRY_NOW(src, CLOCK_WORLD))
		return // already down: an EMP doesn't extend the outage
	vars[field] = expiry_written(src, field, EXPIRY_AT(src, CLOCK_WORLD, spec[1] / max(packet.severity, 1))) // ALLOW(api): EMP_DISABLE writes its declared expiry field
	var/obj/machinery/M = src
	if(istype(M))
		M.stat_add(EMPED)
	emp_disable_changed(TRUE)

/// The EMP_DISABLE lapse hook (EXPIRY_ON_LAPSE on the declared field). Idempotent.
/atom/proc/emp_disable_lapsed()
	var/list/spec = lifecycle_decls_of(src)?.emp_disable
	if(!spec)
		return
	var/field = spec[2]
	if(!vars[field])
		return
	vars[field] = 0 // ALLOW(api): EMP_DISABLE clears its declared expiry field on lapse
	var/obj/machinery/M = src
	if(istype(M))
		M.stat_remove(EMPED)
	emp_disable_changed(FALSE)

/// What else an EMP_DISABLE type does when it goes down (TRUE) or comes back (FALSE).
/atom/proc/emp_disable_changed(disabled)
	return

// ---- shared reaction procs ----

/// A hit through the trigger lands nothing (the entry's own effects before the packet, such as
/// a projectile's on_hit(), still ran). `DAMAGE_REACTION(/obj/effect/decal/x, DAMAGE_PROJECTILE, TYPE_PROC_REF(/atom, damage_reaction_block))`
/atom/proc/damage_reaction_block(datum/damage_packet/packet)
	return DAMAGE_REACTION_BLOCK

/// The hit destroys the holder outright (an explosion on something with no integrity).
/atom/proc/damage_reaction_qdel(datum/damage_packet/packet)
	qdel(src)
	return DAMAGE_REACTION_BLOCK
