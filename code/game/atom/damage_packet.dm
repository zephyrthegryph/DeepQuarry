// The damage packet and the entry-point adapters that build it.
// See doc/rewrite/damage.md §2 (packet), §3 (adapters) and §4 (mitigation).
//
// Every hit follows one path: an entry point fills a packet, calls
// receive_damage(packet) on the target, and releases the packet. Objects
// apply integrity mitigation and call take_damage(); living mobs map each
// kind to an injure() kind (mob mitigation stays inside injure()).
//
// Packets are pooled: acquire one with damage_packet(), never new() one, and
// release() it as soon as receive_damage() returns. Nothing may keep a
// reference to a packet past its release.

GLOBAL_LIST_EMPTY(damage_packet_pool)

/datum/damage_packet
	/// Amount per kind, indexed by DAMAGE_* (flat list of DAMAGE_KIND_COUNT numbers).
	var/list/amounts
	/// Armour penetration, 0..100.
	var/penetration = 0
	/// Where the hit lands (a BP_* zone), null for spread / whole atom.
	var/zone
	/// Direction the hit travels in, or 0.
	var/direction = 0
	/// The atom delivering the hit: a projectile, thrown atom, weapon, blob, explosion epicentre.
	var/atom/source
	/// The mob responsible, for logging, reactions and contracts.
	var/atom/attacker
	/// The item used, when there is one.
	var/atom/weapon
	/// DAMAGE_PACKET_* flags.
	var/flags = NONE
	/// Legacy armour category (MELEE, BULLET, LASER, ENERGY, BOMB, FIRE, ACID, BIO)
	/// until interned armour (D2) derives it from the kinds. Null = unarmoured.
	var/armor_flag
	/// Out: armour percentage the target resolved (mobs), so adapters can pass
	/// it to on_hit() and friends. Null until resolved; an adapter that has
	/// already resolved armour sets it before delivery.
	var/blocked
	/// TRUE while checked out of the pool.
	var/in_use = FALSE

/datum/damage_packet/New()
	amounts = new /list(DAMAGE_KIND_COUNT)
	for(var/i in 1 to DAMAGE_KIND_COUNT)
		amounts[i] = 0

/datum/damage_packet/Destroy(force)
	if(!force)
		// Pooled; nothing should qdel a packet.
		return QDEL_HINT_LETMELIVE
	source = null
	attacker = null
	weapon = null
	return ..()

/// Take a clean packet from the pool.
/proc/damage_packet(armor_flag, atom/source, atom/attacker, atom/weapon, zone, flags = NONE, penetration = 0, direction = 0)
	var/datum/damage_packet/packet
	var/list/pool = GLOB.damage_packet_pool
	if(length(pool))
		packet = pool[length(pool)]
		pool.len--
	else
		packet = new
	packet.in_use = TRUE
	packet.armor_flag = armor_flag
	packet.source = source
	packet.attacker = attacker
	packet.weapon = weapon
	packet.zone = zone
	packet.flags = flags
	packet.penetration = penetration
	packet.direction = direction
	return packet

/// Clear the packet and return it to the pool.
/datum/damage_packet/proc/release()
	if(!in_use)
		CRASH("Released a damage packet twice.")
	in_use = FALSE
	for(var/i in 1 to DAMAGE_KIND_COUNT)
		amounts[i] = 0
	penetration = 0
	zone = null
	direction = 0
	source = null
	attacker = null
	weapon = null
	flags = NONE
	armor_flag = null
	blocked = null
	GLOB.damage_packet_pool += src

/datum/damage_packet/proc/add(kind, amount)
	if(amount > 0 && kind >= 1 && kind <= DAMAGE_KIND_COUNT)
		amounts[kind] += amount

/datum/damage_packet/proc/total()
	. = 0
	for(var/i in 1 to DAMAGE_KIND_COUNT)
		. += amounts[i]

/datum/damage_packet/proc/scale(multiplier)
	for(var/i in 1 to DAMAGE_KIND_COUNT)
		amounts[i] *= multiplier

/// Adds `amount` of a legacy damtype (BRUTE, BURN, ...). Sharp and edge pick
/// the physical kind. Returns FALSE for damtypes with no packet kind (OXY,
/// CLONE), which stay internal to the body.
/datum/damage_packet/proc/add_damtype(damtype, amount, sharp = FALSE, edge = FALSE)
	switch(damtype)
		if(BRUTE)
			add(physical_damage_kind(sharp, edge), amount)
		if(BURN)
			add(DAMAGE_THERMAL, amount)
		if(ELECTROCUTE)
			add(DAMAGE_SHOCK, amount)
		if(BIOACID)
			add(DAMAGE_CORROSIVE, amount)
		if(SEARING)
			add(DAMAGE_THERMAL, amount / 3)
			add(physical_damage_kind(sharp, edge), amount * 2 / 3)
		if(HALLOSS)
			add(DAMAGE_PAIN, amount)
		if(TOX)
			add(DAMAGE_TOXIC, amount)
		if(IRRADIATE)
			add(DAMAGE_RADIATION, amount)
		if(ELECTROMAG)
			add(DAMAGE_IONIC, amount)
		else
			return FALSE
	if(edge)
		flags |= DAMAGE_PACKET_EDGE
	return TRUE

/// Sharp + edge cuts, sharp alone pierces, anything else is blunt.
/proc/physical_damage_kind(sharp, edge)
	if(sharp && edge)
		return DAMAGE_SHARP
	if(sharp)
		return DAMAGE_PIERCE
	return DAMAGE_BLUNT

/// INJURY_* -> DAMAGE_* for sources that declare an explicit injury kind.
/// 0 for the kinds that stay internal to the body (asphyxia, cellular, neural, digestion).
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
		0,                // INJURY_ASPHYXIA
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

/// Shared EMP ladder: ionic amount per severity (EMP_HEAVY .. EMP_HARMLESS).
/proc/emp_ionic_damage(severity)
	var/static/list/ladder = list(20, 15, 10, 5)
	var/band = round(severity)
	if(band < 1 || band > length(ladder))
		return 0
	return ladder[band]

/// Blast per explosion severity, as a fraction of the target's max integrity.
/proc/explosion_blast_fraction(severity)
	var/static/list/ladder = list(1, 0.5, 0.25)
	var/band = round(severity)
	if(band < 1 || band > length(ladder))
		return 0
	return ladder[band]


// --- The sink -------------------------------------------------------------------

/// Apply a damage packet. Returns the amount actually applied after mitigation.
/// The default sink is object integrity; /mob/living overrides it with injure().
/atom/proc/receive_damage(datum/damage_packet/packet)
	if(!uses_integrity || QDELETED(src))
		return 0
	var/list/amounts = packet.amounts
	// §4 step 1 (shields): no object holds a shield yet.
	// §4 step 3 (innate armour) is the per-item armour list, and step 4
	// (material response) does not exist yet; both run in run_atom_armor().
	var/brute = amounts[DAMAGE_BLUNT] + amounts[DAMAGE_SHARP] + amounts[DAMAGE_PIERCE] + amounts[DAMAGE_BLAST]
	var/burn = amounts[DAMAGE_THERMAL] + amounts[DAMAGE_CORROSIVE] + amounts[DAMAGE_IONIC] * emp_integrity_factor
	// Cold, shock, toxic, radiation and pain have no effect on integrity.
	var/sound = !(packet.flags & DAMAGE_PACKET_SILENT)
	. = 0
	if(brute > 0)
		. += take_damage(brute, BRUTE, packet.armor_flag, sound, packet.direction, packet.penetration)
	if(burn > 0 && !QDELETED(src))
		. += take_damage(burn, BURN, packet.armor_flag, sound, packet.direction, packet.penetration)

/atom
	/// How much of an incoming ionic (EMP) amount becomes burn integrity damage.
	/// Zero for almost everything: EMPs disrupt objects, they don't break them.
	var/emp_integrity_factor = 0


// --- Adapter helpers --------------------------------------------------------------
// Each builds the packet for one kind of entry point, delivers it and
// releases it. They return the amount applied.

/// One kind of damage, for adapters with nothing more to say.
/atom/proc/deal_damage(kind, amount, armor_flag = MELEE, atom/source, atom/attacker, atom/weapon, flags = NONE, penetration = 0, zone = null, direction = 0)
	if(amount <= 0)
		return 0
	var/datum/damage_packet/packet = damage_packet(armor_flag, source, attacker, weapon, zone, flags, penetration, direction)
	packet.add(kind, amount)
	. = receive_damage(packet)
	packet.release()

/// Fill `packet` from this projectile: kinds from its injury kind or damage
/// type (sharp/edge honoured), penetration and armour category.
/obj/item/projectile/proc/fill_damage_packet(datum/damage_packet/packet, proj_sharp = sharp, proj_edge = edge)
	packet.flags |= DAMAGE_PACKET_PROJECTILE
	if(nodamage || !damage)
		return
	if(injury_kind)
		packet.add(damage_kind_for_injury(injury_kind), damage)
		if(proj_edge)
			packet.flags |= DAMAGE_PACKET_EDGE
	else
		packet.add_damtype(damage_type, damage, proj_sharp, proj_edge)

/// Build the packet for a projectile hit.
/obj/item/projectile/proc/damage_packet_for(atom/target, def_zone, proj_sharp = sharp, proj_edge = edge)
	var/datum/damage_packet/packet = damage_packet(check_armour, src, firer, null, def_zone, NONE, armor_penetration, dir)
	fill_damage_packet(packet, proj_sharp, proj_edge)
	return packet

/// Projectile hit. `multiplier` is for types whose shape changes how much of a round they catch.
/atom/proc/receive_projectile(obj/item/projectile/P, def_zone, multiplier = 1)
	var/datum/damage_packet/packet = P.damage_packet_for(src, def_zone)
	if(multiplier != 1)
		packet.scale(multiplier)
	. = packet.total() > 0 ? receive_damage(packet) : 0
	packet.release()

/// Fill `packet` from a melee weapon: kinds from force, sharp, edge and damage type.
/obj/item/proc/fill_weapon_packet(datum/damage_packet/packet, amount = force, damtype_used = damtype)
	packet.add_damtype(damtype_used, amount, sharp, edge)

/// Weapon hit on this atom. `amount` and `damtype_used` let a type react to
/// the tool (a welder burns a barricade; a blast door shrugs off most of a blow).
/atom/proc/receive_weapon_hit(obj/item/W, mob/user, amount = W.force, damtype_used = W.damtype, silent = TRUE)
	if(amount <= 0)
		return 0
	var/datum/damage_packet/packet = damage_packet(MELEE, W, user, W, null, silent ? DAMAGE_PACKET_SILENT : NONE, W.armor_penetration, user ? get_dir(user, src) : 0)
	W.fill_weapon_packet(packet, amount, damtype_used)
	. = receive_damage(packet)
	packet.release()

/// Force of a thrown atom on impact: the one formula (damage.md §3).
/// Items hit with their throwforce, mobs with their size, other objects with their weight class.
/atom/movable/proc/thrown_impact_force(datum/thrownthing/throwingdatum)
	var/speed_factor = (throwingdatum?.speed || THROWFORCE_SPEED_DIVISOR) / THROWFORCE_SPEED_DIVISOR
	return w_class_impact_force() * speed_factor

/atom/movable/proc/w_class_impact_force()
	return 0

/obj/w_class_impact_force()
	return w_class

/obj/item/w_class_impact_force()
	return throwforce

/mob/w_class_impact_force()
	return mob_size

/// Thrown-atom impact on this atom.
/atom/proc/receive_thrown(atom/movable/AM, datum/thrownthing/throwingdatum, multiplier = 1)
	var/amount = AM.thrown_impact_force(throwingdatum) * multiplier
	if(amount <= 0)
		return 0
	var/datum/damage_packet/packet = damage_packet(MELEE, AM, throwingdatum?.get_thrower(), isitem(AM) ? AM : null, null, DAMAGE_PACKET_THROWN, 0, get_dir(AM, src))
	if(isitem(AM))
		var/obj/item/I = AM
		packet.penetration = I.armor_penetration
		packet.add_damtype(I.damtype, amount, I.sharp, I.edge)
	else
		packet.add(DAMAGE_BLUNT, amount)
	. = receive_damage(packet)
	packet.release()

/// Generic (usually animal) attack: kinds from the attacker's profile.
/atom/proc/receive_generic_attack(mob/user, amount)
	if(amount <= 0)
		return 0
	// Objects play their own hit sounds for animal attacks; mobs still flash pain.
	var/datum/damage_packet/packet = damage_packet(MELEE, user, user, null, null, ismob(src) ? NONE : DAMAGE_PACKET_SILENT, 0, user ? get_dir(user, src) : 0)
	var/mob/living/simple_mob/S = user
	if(istype(S))
		packet.penetration = S.attack_armor_pen
		packet.add(physical_damage_kind(S.attack_sharp, S.attack_edge), amount)
		if(S.attack_edge)
			packet.flags |= DAMAGE_PACKET_EDGE
	else
		packet.add(DAMAGE_BLUNT, amount)
	. = receive_damage(packet)
	packet.release()

/// Explosion: blast from the propagated severity.
/atom/proc/receive_explosion(severity)
	if(!uses_integrity)
		return 0
	return deal_damage(DAMAGE_BLAST, max_integrity * explosion_blast_fraction(severity), BOMB, flags = DAMAGE_PACKET_SILENT)

/// EMP: ionic from the severity, through the shared ladder.
/atom/proc/receive_emp(severity)
	return deal_damage(DAMAGE_IONIC, emp_ionic_damage(severity), ENERGY, flags = DAMAGE_PACKET_SILENT)

/// Electric shock (electrocute_act): `amount` is after insulation (siemens) scaling, so it is unarmoured.
/atom/proc/receive_shock(amount, atom/source, zone = null, flags = NONE)
	if(amount <= 0)
		return 0
	var/datum/damage_packet/packet = damage_packet(null, source, null, null, zone, flags)
	packet.blocked = 0
	packet.add(DAMAGE_SHOCK, amount)
	. = receive_damage(packet)
	packet.release()

/// Blob attack: kinds from the blob type's profile.
/atom/proc/receive_blob(obj/structure/blob/B)
	var/datum/blob_type/blob = B?.overmind?.blob_type
	var/datum/damage_packet/packet
	if(blob)
		packet = damage_packet(blob.armor_check, B, B.overmind, null, null, NONE, blob.armor_pen)
		packet.add_damtype(blob.damage_type, rand(blob.damage_lower, blob.damage_upper))
	else
		packet = damage_packet(MELEE, B)
		packet.add(DAMAGE_BLUNT, rand(30, 40))
	. = receive_damage(packet)
	packet.release()
