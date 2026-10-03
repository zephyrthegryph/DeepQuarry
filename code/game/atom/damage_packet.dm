// The damage packet and the entry-point adapters that build it.
// See doc/rewrite/damage.md §2 (packet), §3 (adapters) and §4 (mitigation).
//
// Every hit follows one path: an entry point fills a packet, calls
// receive_damage(packet) on the target, and releases the packet. Objects
// apply integrity mitigation and call take_damage(); living mobs hand each
// kind to injure() through the agreed mapping, and injure() runs the one
// mob mitigation pipeline (armour, shields, resistances, species).
//
// Packets are pooled (code/datums/lifecycle/pool.dm): acquire one with
// damage_packet(), never new() one, and release() it as soon as
// receive_damage() returns. Nothing may keep a reference to a packet past its
// release; release() resets every field below to its initial value (the amounts list is kept and zeroed).

/datum/damage_packet
	parent_type = /datum/pooled
	/// Amount per kind, indexed by DAMAGE_* (flat list of DAMAGE_KIND_COUNT
	/// numbers). Zeroed when the packet is taken.
	var/list/amounts
	/// Armour penetration in armour points (injure()'s armor_pen).
	var/penetration = 0
	/// Where the hit lands (a BP_* zone), null for spread / whole atom.
	var/zone
	/// Direction the hit travels in, or 0.
	var/direction = 0
	/// The atom delivering the hit: a projectile, thrown atom, weapon, blob.
	var/atom/source
	/// The mob responsible, for logging, reactions and contracts.
	var/atom/attacker
	/// The item used, when there is one.
	var/atom/weapon
	/// DAMAGE_PACKET_* flags.
	var/flags = NONE
	/// Object damage flag override (FIRE, ACID, ...) for hits whose destruction
	/// matters (fire burns an object down, acid melts it). Null derives it per
	/// kind from injury_armor_key(). Mobs ignore it: injure() looks armour up by kind.
	var/armor_flag
	/// The entry point that built the packet (DAMAGE_ENTRY_*), 0 for a direct delivery.
	/// Entry triggers of declared damage reactions match on it (code/datums/sys/damage_reactions.dm).
	var/entry = 0
	/// EMP / explosion severity for those entries, 0 otherwise.
	var/severity = 0

/datum/damage_packet/New()
	..()
	amounts = new /list(DAMAGE_KIND_COUNT)
	for(var/i in 1 to DAMAGE_KIND_COUNT)
		amounts[i] = 0

/// Take a clean packet from the pool.
/proc/damage_packet(atom/source, atom/attacker, atom/weapon, zone, flags = NONE, penetration = 0, direction = 0, armor_flag = null, entry = 0, severity = 0)
	var/datum/damage_packet/packet = take(/datum/damage_packet)
	packet.source = source // ALLOW(ownership): pooled transient packet, lives for one hit; the pool resets it on release
	packet.attacker = attacker // ALLOW(ownership): pooled transient packet, lives for one hit; the pool resets it on release
	packet.weapon = weapon // ALLOW(ownership): pooled transient packet, lives for one hit; the pool resets it on release
	packet.zone = zone
	packet.flags = flags
	packet.penetration = penetration
	packet.direction = direction
	packet.armor_flag = armor_flag
	packet.entry = entry
	packet.severity = severity
	return packet

/// Back to zero for the next taker (the amounts list is New()'s, kept and emptied by the pool, so it
/// is refilled here).
/datum/damage_packet/reset()
	..()
	for(var/i in 1 to DAMAGE_KIND_COUNT)
		amounts += 0

/datum/damage_packet/proc/add(kind, amount)
	POOL_ASSERT_LIVE(src)
	if(amount > 0 && kind >= 1 && kind <= DAMAGE_KIND_COUNT)
		amounts[kind] += amount

/// The sum of every kind's amount.
/datum/damage_packet/proc/total()
	POOL_ASSERT_LIVE(src)
	. = 0
	for(var/i in 1 to DAMAGE_KIND_COUNT)
		. += amounts[i]

/datum/damage_packet/proc/scale(multiplier)
	POOL_ASSERT_LIVE(src)
	for(var/i in 1 to DAMAGE_KIND_COUNT)
		amounts[i] *= multiplier

/// Adds `amount` of an INJURY_* kind. Returns FALSE for the kinds that stay
/// internal to the body (asphyxia, cellular, neural, digestion).
/datum/damage_packet/proc/add_injury(injury_kind, amount)
	var/kind = damage_kind_for_injury(injury_kind)
	if(!kind)
		return FALSE
	add(kind, amount)
	return TRUE

/// `amount` as `injury_kind`, or shared out over `injury_kinds` (INJURY_* ->
/// share) for a mixed hit, like injure_split(). Returns FALSE, adding nothing,
/// if any kind has no packet kind.
/datum/damage_packet/proc/add_split(injury_kind, alist/injury_kinds, amount)
	if(!length(injury_kinds))
		return add_injury(injury_kind, amount)
	for(var/split_kind in injury_kinds)
		if(!damage_kind_for_injury(split_kind))
			return FALSE
	for(var/split_kind in injury_kinds)
		add_injury(split_kind, amount * injury_kinds[split_kind])
	return TRUE

/// INJURY_* -> DAMAGE_*. 0 for the kinds that stay internal to the body
/// (cellular, neural, digestion).
/proc/damage_kind_for_injury(injury)
	var/static/list/kinds = list(
		DAMAGE_BLUNT,     // INJURY_BLUNT
		DAMAGE_SHARP,     // INJURY_CUT
		DAMAGE_PIERCE,    // INJURY_PIERCE
		DAMAGE_THERMAL,   // INJURY_BURN
		DAMAGE_COLD,      // INJURY_FROSTBITE
		DAMAGE_CORROSIVE, // INJURY_CORROSIVE
		DAMAGE_SHOCK,     // INJURY_ELECTRIC
		DAMAGE_TOXIC,     // INJURY_TOXIN
		DAMAGE_RADIATION, // INJURY_RADIATION
		0,                // INJURY_CELLULAR
		0,                // INJURY_NEURAL
		DAMAGE_PAIN,      // INJURY_PAIN
		0,                // INJURY_DIGESTION
	)
	if(injury < 1 || injury > length(kinds))
		return 0
	return kinds[injury]

/// DAMAGE_* -> INJURY_*, the mapping agreed with the body rewrite (damage.md §2).
/proc/injury_kind_for_damage(kind)
	var/static/list/injuries = list(
		INJURY_BLUNT,     // blunt
		INJURY_CUT,       // sharp
		INJURY_PIERCE,    // pierce
		INJURY_BURN,      // thermal
		INJURY_FROSTBITE, // cold
		INJURY_ELECTRIC,  // shock
		INJURY_CORROSIVE, // corrosive
		INJURY_TOXIN,     // toxic
		INJURY_RADIATION, // radiation
		INJURY_ELECTRIC,  // ionic: the body part's biology decides the effect
		INJURY_BLUNT,     // blast (the pressure effect is not modelled yet)
		INJURY_PAIN,      // pain
	)
	return injuries[kind]

/// DAMAGE_* -> the obj_integrity damage type (BRUTE / BURN), or null for the
/// kinds that can't harm objects. Ionic burns only types with an emp_integrity_factor.
/proc/damage_kind_obj_damage_type(kind)
	var/static/list/types = list(
		BRUTE, // blunt
		BRUTE, // sharp
		BRUTE, // pierce
		BURN,  // thermal
		null,  // cold
		null,  // shock
		BURN,  // corrosive
		null,  // toxic
		null,  // radiation
		BURN,  // ionic
		BRUTE, // blast
		null,  // pain
	)
	return types[kind]

/// DAMAGE_* -> the object armour key ("melee", "bomb", ...).
/proc/damage_kind_armor_key(kind)
	switch(kind)
		if(DAMAGE_BLAST)
			return injury_armor_key(ARMOR_BLAST)
		if(DAMAGE_IONIC)
			return ENERGY
		if(DAMAGE_COLD)
			return ARMOR_COLD
	return injury_armor_key(injury_kind_for_damage(kind))

/// The one EMP ladder (damage.md §7): the ionic amount of each severity,
/// EMP_HEAVY .. EMP_HARMLESS. Pulses read it forwards (emp_ionic_damage) and
/// ionic hits such as ion rounds read it backwards (emp_severity_for_ionic).
GLOBAL_LIST_INIT(emp_ladder, list(100, 70, 40, 10))

/// Ionic amount an EMP of `severity` delivers.
/proc/emp_ionic_damage(severity)
	var/list/ladder = GLOB.emp_ladder
	var/band = round(severity)
	if(band < 1 || band > length(ladder))
		return 0
	return ladder[band]

/// The severity an ionic hit of `amount` pulses its target with. Within 9 of
/// a rung it is that rung; in the 15 below that it is a coin flip between the
/// rung and the next one down; anything weaker is harmless.
/proc/emp_severity_for_ionic(amount)
	var/list/ladder = GLOB.emp_ladder
	amount = round(amount)
	for(var/severity in 1 to length(ladder) - 1)
		var/rung = ladder[severity] - 9
		if(amount >= rung)
			return severity
		if(amount >= rung - 15)
			return prob(50) ? severity : severity + 1
	return EMP_HARMLESS

/// Blast per explosion severity, as a fraction of the target's max integrity.
/proc/explosion_blast_fraction(severity)
	var/static/list/ladder = list(1, 0.5, 0.25)
	var/band = round(severity)
	if(band < 1 || band > length(ladder))
		return 0
	return ladder[band]

// --- The sinks ------------------------------------------------------------------

/// Apply a damage packet. Returns the amount actually applied after mitigation.
/// The type's damage reactions run first (before_op(damage(...)) in its composed reactions table,
/// doc/rewrite/reactions.md section 1b): one that blocks stops the hit. Then the sink applies it, then the
/// after_op(damage(...)) rows. Not overridable: a type changes where damage lands by overriding damage_sink().
/atom/proc/receive_damage(datum/damage_packet/packet)
	SHOULD_NOT_OVERRIDE(TRUE)
	// The engine's hit action (the hit bridge): hooks of /datum/act/hit and its entry subtypes run first. A holder nothing hooks pays one act_wanted() check.
	var/hit = hit_try(src, packet)
	if(isnull(hit))
		return 0
	var/list/rows = damage_rows_of(src)
	if(!rows)
		. = damage_sink(packet)
		act_done(hit)
		return
	if(run_damage_reactions(rows, packet, DAMAGE_REACTION_PHASE_BEFORE))
		act_cancel(hit)
		return 0
	. = damage_sink(packet)
	if(damage_rows_after(src) && !QDELETED(src))
		run_damage_reactions(rows, packet, DAMAGE_REACTION_PHASE_AFTER)
	act_done(hit)

/// The hit action type an entry of a packet is, the most specific one (a hook of /datum/act/hit applies to every subtype of it): projectile, melee
/// (a weapon or a generic attack), explosion, emp, blob, fire (an entry-less packet flagged FIRE), shock; thrown and direct deliveries are the generic hit.
/proc/hit_act_type(datum/damage_packet/packet)
	switch(packet.entry)
		if(DAMAGE_ENTRY_PROJECTILE)
			return /datum/act/hit/projectile
		if(DAMAGE_ENTRY_EMP)
			return /datum/act/hit/emp
		if(DAMAGE_ENTRY_EXPLOSION)
			return /datum/act/hit/explosion
		if(DAMAGE_ENTRY_BLOB)
			return /datum/act/hit/blob
		if(DAMAGE_ENTRY_WEAPON, DAMAGE_ENTRY_GENERIC)
			return /datum/act/hit/melee
		if(DAMAGE_ENTRY_SHOCK)
			return /datum/act/hit/shock
	if(packet.armor_flag == FIRE)
		return /datum/act/hit/fire
	return /datum/act/hit

/// Starts the hit action for a packet. ACT_PASS (a truthy no-op) when nothing hooks or listens for it (nothing allocated); null when a hook refused the
/// hit or took it over (the caller lands nothing); else the act, which the caller ends with act_done() or act_cancel().
/proc/hit_try(atom/holder, datum/damage_packet/packet)
	var/act_type = hit_act_type(packet)
	if(!act_wanted(holder, act_type))
		return ACT_PASS
	var/hit
	switch(act_type)
		if(/datum/act/hit/projectile)
			// ALLOW(handlers): the act is returned to receive_damage(), which ends it with act_done() or act_cancel()
			hit = ACT_TRY(holder, hit_projectile, packet)
		if(/datum/act/hit/emp)
			hit = ACT_TRY(holder, hit_emp, packet)
		if(/datum/act/hit/explosion)
			hit = ACT_TRY(holder, hit_explosion, packet)
		if(/datum/act/hit/blob)
			hit = ACT_TRY(holder, hit_blob, packet)
		if(/datum/act/hit/melee)
			hit = ACT_TRY(holder, hit_melee, packet)
		if(/datum/act/hit/shock)
			hit = ACT_TRY(holder, hit_shock, packet)
		if(/datum/act/hit/fire)
			hit = ACT_TRY(holder, hit_fire, packet)
		else
			hit = ACT_TRY(holder, hit, packet)
	if(isnull(hit))
		packet.flags |= DAMAGE_PACKET_BLOCKED
		log_world("HIT: [holder.type] [act_type] refused or taken over by a hook (outcome [GLOB.act_last_outcome])")
		return null
	return hit

/// Where a packet lands. The default sink is object integrity; /mob/living overrides it with injure().
/atom/proc/damage_sink(datum/damage_packet/packet)
	if(!uses_integrity || QDELETED(src))
		return 0
	var/list/amounts = packet.amounts
	// §4 step 1 (shields): holders with a shield block before the hit lands
	// (/mob/living/proc/check_shields()); no object holds one. Steps 3 (innate
	// armour, get_armor()) and 4 (material response, impact_factor()) run in
	// run_atom_armor(), which reads the kind being delivered.
	var/sound = !(packet.flags & DAMAGE_PACKET_SILENT)
	. = 0
	for(var/kind in 1 to DAMAGE_KIND_COUNT)
		var/amount = amounts[kind]
		if(amount <= 0)
			continue
		var/damage_type = damage_kind_obj_damage_type(kind)
		if(!damage_type)
			continue
		if(kind == DAMAGE_IONIC)
			amount *= emp_integrity_factor
			if(amount <= 0)
				continue
		GLOB.incoming_damage_kind = kind
		. += take_damage(amount, damage_type, packet.armor_flag || damage_kind_armor_key(kind), sound, packet.direction, packet.penetration)
		GLOB.incoming_damage_kind = 0
		sound = FALSE
		// A destroyed wall becomes a floor in place (same turf, no integrity).
		if(QDELETED(src) || !uses_integrity)
			return
	// What the shell let through reaches the holder's contents (containment
	// paths, C2). A holder destroyed above has already spilled them.
	if(contents_count(src))
		propagate_damage(packet)

/atom
	/// How much of an incoming ionic (EMP) amount becomes burn integrity damage.
	/// Zero for almost everything: EMPs disrupt objects, they don't break them.
	var/emp_integrity_factor = 0

/// For hits whose kinds have no packet kind (asphyxia, cellular...): they
/// stay internal to the body, so only a living target takes them, directly.
/atom/proc/receive_internal_injury(datum/damage_packet/packet, injury_kind, alist/injury_kinds, amount)
	return 0

// --- Adapter helpers --------------------------------------------------------------
// Each builds the packet for one kind of entry point, delivers it and
// releases it. They return the amount applied.

/// One kind of damage, for adapters with nothing more to say.
/atom/proc/deal_damage(kind, amount, armor_flag = null, atom/source, atom/attacker, atom/weapon, flags = NONE, penetration = 0, zone = null, direction = 0)
	if(amount <= 0)
		return 0
	var/datum/damage_packet/packet = damage_packet(source, attacker, weapon, zone, flags, penetration, direction, armor_flag)
	packet.add(kind, amount)
	. = receive_damage(packet)
	packet.release()

/// Deliver `amount` of an item's (or blob's) declared kinds in `packet`, then release it.
/// A packet from an entry that lands nothing still runs the type's declared reactions.
/atom/proc/receive_split(datum/damage_packet/packet, injury_kind, alist/injury_kinds, amount)
	if(amount > 0 && packet.add_split(injury_kind, injury_kinds, amount))
		. = receive_damage(packet)
	else
		var/blocked = packet.entry && react_to_packet(packet)
		if(amount > 0 && !blocked)
			. = receive_internal_injury(packet, injury_kind, injury_kinds, amount)
	packet.release()

/// Projectile hit. `multiplier` is for types whose shape changes how much of
/// a round they catch. Ion rounds (emp_on_hit) pulse instead of harming.
/atom/proc/receive_projectile(obj/item/projectile/P, def_zone, multiplier = 1)
	if(P.nodamage || !P.damage || P.emp_on_hit)
		react_to_entry(DAMAGE_ENTRY_PROJECTILE, 0, P, P.firer)
		return 0
	var/datum/damage_packet/packet = damage_packet(P, P.firer, null, def_zone, DAMAGE_PACKET_PROJECTILE, P.armor_penetration, P.dir, null, DAMAGE_ENTRY_PROJECTILE)
	if(GLOB.projectile_pre_reacted == ref(src))
		packet.flags |= DAMAGE_PACKET_PRE_REACTED
	if(P.edge)
		packet.flags |= DAMAGE_PACKET_EDGE
	return receive_split(packet, P.injury_kind, P.injury_kinds, P.damage * multiplier)

/// Weapon hit. `amount` and `injury_kind` let a type react to the tool (a
/// welder burns a barricade; a blast door shrugs off most of a blow).
/atom/proc/receive_weapon_hit(obj/item/W, mob/user, amount = W.force, injury_kind = null, zone = null, silent = TRUE, armored = TRUE)
	var/flags = silent ? DAMAGE_PACKET_SILENT : NONE
	if(!armored)
		flags |= DAMAGE_PACKET_UNARMORED
	var/datum/damage_packet/packet = damage_packet(W, user, W, zone, flags, W.armor_penetration, user ? get_dir(user, src) : 0, null, DAMAGE_ENTRY_WEAPON)
	if(W.edge)
		packet.flags |= DAMAGE_PACKET_EDGE
	if(injury_kind)
		return receive_split(packet, injury_kind, null, amount)
	return receive_split(packet, W.injury_kind, W.injury_kinds, amount)

/// Force of a thrown atom on impact: the one formula (damage.md §3).
/// Items hit with their throwforce, mobs with their size, other objects with their weight class.
/atom/movable/proc/thrown_impact_force(datum/thrownthing/throwingdatum)
	var/speed_factor = (throwingdatum?.speed || THROWFORCE_SPEED_DIVISOR) / THROWFORCE_SPEED_DIVISOR
	return impact_mass() * speed_factor

/atom/movable/proc/impact_mass()
	return 0

/obj/impact_mass()
	return w_class

/obj/item/impact_mass()
	return throwforce

/mob/impact_mass()
	return mob_size

/// Thrown-atom impact.
/atom/proc/receive_thrown(atom/movable/AM, datum/thrownthing/throwingdatum, multiplier = 1, zone = null)
	var/amount = AM.thrown_impact_force(throwingdatum) * multiplier
	if(amount <= 0)
		react_to_entry(DAMAGE_ENTRY_THROWN, 0, AM, throwingdatum?.get_thrower())
		return 0
	var/datum/damage_packet/packet = damage_packet(AM, throwingdatum?.get_thrower(), null, zone, DAMAGE_PACKET_THROWN, 0, get_dir(AM, src), null, DAMAGE_ENTRY_THROWN)
	if(!isitem(AM))
		packet.add(DAMAGE_BLUNT, amount)
		. = receive_damage(packet)
		packet.release()
		return
	var/obj/item/I = AM
	packet.weapon = I // ALLOW(ownership): pooled transient packet, lives for one hit; the pool resets it on release
	packet.penetration = I.armor_penetration
	if(I.edge)
		packet.flags |= DAMAGE_PACKET_EDGE
	return receive_split(packet, I.injury_kind, I.injury_kinds, amount)

/// The kind of wound a generic (usually animal) attack from `user` leaves:
/// simple mobs declare their melee kind; anything else is a blunt blow.
/proc/generic_attack_kind(mob/user)
	var/mob/living/simple_mob/S = user
	if(istype(S))
		return S.attack_injury_kind
	return INJURY_BLUNT

/// Generic (usually animal) attack: kinds from the attacker's profile.
/// Armour applies only where the target says so (humans armour against animals).
/atom/proc/receive_generic_attack(mob/user, amount, zone = null, armored = FALSE)
	// Objects play their own hit sounds for animal attacks; mobs still flash pain.
	var/flags = ismob(src) ? NONE : DAMAGE_PACKET_SILENT
	if(!armored)
		flags |= DAMAGE_PACKET_UNARMORED
	var/mob/living/simple_mob/S = user
	var/datum/damage_packet/packet = damage_packet(user, user, null, zone, flags, istype(S) ? S.attack_armor_pen : 0, user ? get_dir(user, src) : 0, null, DAMAGE_ENTRY_GENERIC)
	return receive_split(packet, generic_attack_kind(user), null, amount)

/// Explosion: blast from the propagated severity. Explosions deliver it in
/// type batches (SSexplosions.deliver_blast_batches); objects are destroyed by
/// integrity, never by a severity ladder.
/atom/proc/receive_explosion(severity)
	if(resistance_flags & BOMB_PROOF)
		return 0
	if(!uses_integrity)
		react_to_entry(DAMAGE_ENTRY_EXPLOSION, severity)
		return 0
	var/datum/damage_packet/packet = damage_packet(null, null, null, null, DAMAGE_PACKET_SILENT, 0, 0, null, DAMAGE_ENTRY_EXPLOSION, severity)
	packet.add(DAMAGE_BLAST, max_integrity * explosion_blast_fraction(severity))
	. = receive_damage(packet)
	packet.release()

/// Severity the explosion delivers to this atom's contents, in bulk, in the
/// same batch epoch; 0 shields them. A destroyed container spills whatever it
/// held, so contents are queued before the container's own packet lands.
/atom/movable/proc/explosion_contents_severity(severity)
	return 0

/// An ionic hit (ion rounds): pulse the target at the ladder's severity.
/atom/proc/receive_ionic(amount)
	emp_act(emp_severity_for_ionic(amount))

/// EMP: ionic from the severity, through the shared ladder.
/atom/proc/receive_emp(severity)
	var/datum/damage_packet/packet = damage_packet(null, null, null, null, DAMAGE_PACKET_SILENT | DAMAGE_PACKET_UNARMORED, 0, 0, null, DAMAGE_ENTRY_EMP, severity)
	packet.add(DAMAGE_IONIC, emp_ionic_damage(severity))
	. = receive_damage(packet)
	packet.release()

/// Electric shock (electrocute_act): `amount` is after insulation (siemens)
/// scaling, so armour does not apply again.
/atom/proc/receive_shock(amount, atom/source, zone = null)
	var/datum/damage_packet/packet = damage_packet(source, null, null, zone, DAMAGE_PACKET_UNARMORED, 0, 0, null, DAMAGE_ENTRY_SHOCK)
	packet.add(DAMAGE_SHOCK, amount)
	. = receive_damage(packet)
	packet.release()

/// Blob attack: kinds from the blob type's profile.
/atom/proc/receive_blob(obj/structure/blob/B, zone = null)
	var/datum/blob_type/blob = B?.overmind?.blob_type
	if(!blob)
		var/datum/damage_packet/plain = damage_packet(B, null, null, zone, NONE, 0, 0, null, DAMAGE_ENTRY_BLOB)
		plain.add(DAMAGE_BLUNT, rand(30, 40))
		. = receive_damage(plain)
		plain.release()
		return
	var/datum/damage_packet/packet = damage_packet(B, B.overmind, null, zone, NONE, blob.armor_pen, 0, null, DAMAGE_ENTRY_BLOB)
	return receive_split(packet, blob.injury_kind, blob.injury_kinds, rand(blob.damage_lower, blob.damage_upper))
