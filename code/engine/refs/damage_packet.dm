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
