
// Clicking with an empty hand
/mob/living/unarmed_touch(mob/living/L, stance = I_HELP)
	..()
	if(istype(L) && stance != I_HELP)
		if(ai_brain) // A disarm, grab or harm touch is considered a hostile action to the mob's AI.
			ai_brain.react_to_attack(L)
	if(touch_reaction_flags & SPECIES_TRAIT_THORNS)
		if(src != L)
			L.injure(INJURY_PIERCE, 3, L.hand ? BP_L_HAND : BP_R_HAND, src)
			act_message(L, src, MSG_SELF(span_warning("%T% is covered in sharp bits and it hurt when you touched them!")), \
				MSG_OTHERS(span_warning("%U% is hurt by sharp body parts when touching %T%!")))

/// The mob sink: each packet kind goes to injure() through the mapping agreed
/// with the body rewrite (damage.md §2), with the packet's penetration as
/// armor_pen. injure() is the one mob mitigation pipeline: armour
/// (injury_armor(kind, zone)), shields, resistance factors, species.
/mob/living/damage_sink(datum/damage_packet/packet)
	var/injure_flags = (packet.flags & DAMAGE_PACKET_UNARMORED) ? NONE : INJURE_ARMORED
	if(packet.flags & DAMAGE_PACKET_PROJECTILE)
		injure_flags |= INJURE_PROJECTILE
	if(packet.flags & DAMAGE_PACKET_SILENT)
		injure_flags |= INJURE_SILENT
	if(packet.flags & DAMAGE_PACKET_IGNORE_RESISTANCE)
		injure_flags |= INJURE_IGNORE_RESISTANCE
	var/list/amounts = packet.amounts
	var/atom/injury_source = packet.source || packet.weapon || packet.attacker
	. = 0
	for(var/kind in 1 to DAMAGE_KIND_COUNT)
		var/amount = amounts[kind]
		if(amount > 0)
			. += injure(injury_kind_for_damage(kind), amount, packet.zone, injury_source, packet.penetration, null, injure_flags)

/// Kinds the packet can't carry (asphyxia, cellular...) land directly.
/mob/living/receive_internal_injury(datum/damage_packet/packet, injury_kind, alist/injury_kinds, amount)
	var/injure_flags = (packet.flags & DAMAGE_PACKET_UNARMORED) ? NONE : INJURE_ARMORED
	if(packet.flags & DAMAGE_PACKET_PROJECTILE)
		injure_flags |= INJURE_PROJECTILE
	return injure_split(injury_kind, injury_kinds, amount, packet.zone, packet.source || packet.weapon || packet.attacker, packet.penetration, injure_flags)

/mob/living/bullet_act(obj/item/projectile/P, def_zone)
	if(reflect_projectile(P)) // REFLECTS (systems.md section 12)
		return PROJECTILE_CONTINUE
	// Declared projectile reactions run before the stun and on_hit(): a blocking one stops them too.
	if(projectile_pre_reactions(P))
		return 0
	. = resolve_projectile_hit(P, def_zone)
	end_projectile_reactions()

/// The round's effects on a living target, after the declared reactions let it through.
/mob/living/proc/resolve_projectile_hit(obj/item/projectile/P, def_zone)
	// begin, re-adds stealth removed feature
	if(istype(get_active_hand(),/obj/item/assembly/signaler))
		var/obj/item/assembly/signaler/signaler = get_active_hand()
		if(signaler.deadman && prob(80))
			log_and_message_admins("has triggered a signaler deadman's switch")
			act_message(src, null, others = "<font color='red'>%U% triggers their deadman's switch!</font>")
			signaler.signal()
	// end

	if(ai_brain && P.firer)
		ai_brain.react_to_attack(P.firer)

	// Armour on the struck part scales the secondary effects; the harm itself
	// is armoured inside injure().
	var/absorb = armor_against(P.injury_kind, def_zone, P.armor_penetration)

	//Stun Beams
	if(P.taser_effect)
		stun_effect_act(0, P.agony, def_zone, P, electric = TRUE)
		P.inflict_injury(src, def_zone)
		// Call on_hit() so any modifier_type_to_apply and other effects set on the
		// projectile are applied even for taser-effect projectiles.  Pass absorb so
		// a fully-blocked hit still suppresses secondary effects correctly. Agony
		// was already applied by stun_effect_act above; on_hit skips it for
		// taser_effect projectiles so it is not applied twice.
		P.on_hit(src, absorb, def_zone)
		spent(P, src)
		return

	P.inflict_injury(src, def_zone)
	P.on_hit(src, absorb, def_zone)

	if(absorb == 100)
		return 2
	else if (absorb >= 0)
		return 1
	else
		return 0


//Handles the effects of "stun" weapons
/mob/living/proc/stun_effect_act(stun_amount, agony_amount, def_zone, used_weapon=null, electric = FALSE)
	flash_pain()
	PUBLISH_LEGACY(src, /datum/notice/stun_effect, stun_amount, agony_amount, def_zone, used_weapon, electric)

	if (stun_amount)
		status_at_least(STAT_STUNNED, stun_amount)
		status_at_least(STAT_WEAKENED, stun_amount)
		apply_effect(STUTTER, stun_amount)
		apply_effect(EYE_BLUR, stun_amount)

	if (agony_amount)
		injure(INJURY_PAIN, agony_amount, def_zone, used_weapon)
		apply_effect(STUTTER, agony_amount/10)
		apply_effect(EYE_BLUR, agony_amount/10)

/mob/living/proc/electrocute_act(shock_damage, obj/source, siemens_coeff = 1.0, def_zone = null, stun = 1)
	  return 0 //only carbon liveforms have this proc

/mob/living/emp_act(severity, recursive)
	. = ..()
	if (. & EMP_PROTECT_SELF || is_incorporeal()) // Can't emp shadekin in phase
		return

	var/emp_shift = factor(BF_EMP_SHIFT)
	if(emp_shift)
		severity = CLAMP(severity + emp_shift, 1, 5)

	if(severity == 5)	// Effectively nullified.
		return

	// The family's own EMP effects (human species sensitivity, synthetic simple mobs) run in
	// its override after this; declared DAMAGE_EMP reactions fire here, once.
	if(react_to_entry(DAMAGE_ENTRY_EMP, severity))
		return . | EMP_PROTECT_SELF

/// Explosion entry for mobs: each family's ladder (human, silicon, simple mob ...) chains here
/// first and stops if this returns TRUE (a component ignored the blast, or a declared
/// DAMAGE_EXPLOSION reaction blocked it).
/mob/living/ex_act(severity)
	if(..())
		return TRUE
	return react_to_entry(DAMAGE_ENTRY_EXPLOSION, severity)

/mob/living/blob_act(obj/structure/blob/B)
	if(stat == DEAD || faction == B.faction)
		return

	var/damage = rand(30, 40)
	var/armor_pen = 0
	var/kind = INJURY_BLUNT
	var/alist/kinds = null
	var/attack_message = "The blob attacks you!"
	var/attack_verb = "attacks"
	var/def_zone = pick(BP_HEAD, BP_TORSO, BP_GROIN, BP_L_ARM, BP_R_ARM, BP_L_LEG, BP_R_LEG)

	if(B && B.overmind)
		var/datum/blob_type/blob = B.overmind.blob_type

		damage = rand(blob.damage_lower, blob.damage_upper)
		armor_pen = blob.armor_pen
		kind = blob.injury_kind
		kinds = blob.injury_kinds

		attack_message = "[blob.attack_message][HAS_SYNTHETIC_BIOLOGY(src) ? "[blob.attack_message_synth]":"[blob.attack_message_living]"]"
		attack_verb = blob.attack_verb
		B.overmind.blob_type.on_attack(B, src, def_zone)

	act_message(src, B, MSG_SELF(span_danger("[attack_message]!")), MSG_OTHERS(span_danger("%T% [attack_verb] %U%!")))
	play_sfx(src, SFX_EFFECTS_ATTACKBLOB)

	if(ai_brain)
		ai_brain.react_to_attack(B)

	receive_split(damage_packet(B, B?.overmind, null, def_zone, NONE, armor_pen, 0, null, DAMAGE_ENTRY_BLOB), kind, kinds, damage)

/mob/living/proc/resolve_item_attack(obj/item/I, mob/living/user, target_zone, stance = I_HURT)
	return target_zone

//Called when the mob is hit with an item in combat, in `stance` (the swing's interaction stance). Returns the blocked result
/mob/living/proc/hit_with_weapon(obj/item/I, mob/living/user, effective_force, hit_zone, stance = I_HURT)
	act_message(src, user, others = span_danger("%U% has been [LAZYLEN(I.attack_verb) ? pick(I.attack_verb) : "attacked"] with [I.name] by %T%!"))

	if(ai_brain)
		ai_brain.react_to_attack(user)

	var/blocked = armor_against(I.injury_kind, hit_zone, I.armor_penetration)

	standard_weapon_hit_effects(I, user, effective_force, blocked, hit_zone, stance)

	if(injury_category(I.injury_kind) == INJURY_CATEGORY_PHYSICAL && prob(33)) // Added blood for whacking non-humans too
		var/turf/simulated/location = get_turf(src)
		if(istype(location)) location.add_blood_floor(src)

	return blocked

//returns 0 if the effects failed to apply for some reason, 1 otherwise.
/mob/living/proc/standard_weapon_hit_effects(obj/item/I, mob/living/user, effective_force, blocked, hit_zone, stance = I_HURT)
	if(!effective_force || blocked >= 100)
		return 0
	// Apply weapon damage: armour (and its chance to turn an edge) is applied in injure().
	receive_weapon_hit(I, user, effective_force, zone = hit_zone, silent = FALSE)

	return 1

//this proc handles being hit by a thrown atom
/mob/living/hitby(atom/movable/source, datum/thrownthing/throwingdatum)//Standardization and logging -Sieve
	if(is_incorporeal())
		return

	var/speed = throwingdatum?.speed || THROWFORCE_SPEED_DIVISOR
	var/mob/living/thrower = throwingdatum?.get_thrower()

	if(guard(src, GUARD_THROWN_HIT, thrower, source, speed))
		return

	if(isitem(source))
		var/obj/item/O = source
		/*var/miss_chance = 15
		if (O.throw_source)
			var/distance = get_dist(O.throw_source, loc)
			miss_chance = max(15*(distance-2), 0)

		if (prob(miss_chance))
			act_message(src, null, others = span_notice("%I% misses %U% narrowly!"), item = O)
			return*/
		// removing baymiss
		act_message(src, null, others = span_filter_warning("[span_red("%U% has been hit by [O].")]"))
		receive_thrown(O, throwingdatum)

		if(ismob(thrower))
			var/client/assailant = thrower.client
			if(assailant)
				add_attack_logs(thrower, src, "Hit by thrown [O.name]")
			if(ai_brain)
				ai_brain.react_to_attack(thrower)

		// Begin BS12 momentum-transfer code.
		var/mass = O.w_class/THROWNOBJ_KNOCKBACK_DIVISOR
		var/momentum = speed*mass

		if(movable_throw_source(O) && momentum >= THROWNOBJ_KNOCKBACK_SPEED)
			var/dir = get_dir(movable_throw_source(O), src)

			act_message(src, null, MSG_SELF(span_filter_warning("[span_red("You stagger under the impact!")]")), \
				MSG_OTHERS(span_filter_warning("[span_red("%U% staggers under the impact!")]")))
			src.throw_at(get_edge_target_turf(src,dir),1,momentum)

			if(!O || !src) return

			if(O.sharp) //Projectile is suitable for pinning.

				//Handles embedding for non-humans and simple_animals.
				embed(O)

				var/turf/T = near_wall(dir,2)

				if(T)
					forceMove(T)
					act_message(src, null, MSG_SELF(span_warning("You are pinned to the wall by [O]!")), \
						MSG_OTHERS(span_warning("%U% is pinned to the wall by [O]!")))
					set_anchored(TRUE)
					rel_add(src, nameof(pinned), O)

/mob/living/proc/on_throw_vore_special(pred = TRUE, mob/living/target)
	return

/mob/living/proc/embed(obj/O, def_zone=null)
	O.forceMove(src)
	LAZYADD(src.embedded, O)
	grant(src, granted_verb(/mob/proc/yank_out_object), src)
	throw_alert("embeddedobject", /atom/movable/screen/alert/embeddedobject)

//This is called when the mob is thrown into a dense turf
/mob/living/proc/turf_collision(turf/T, speed)
	if(OM_EMIT(src, /datum/om/event/before/living_turf_collision, T, speed) & COMPONENT_LIVING_BLOCK_TURF_COLLISION)
		return
	injure(INJURY_BLUNT, speed * 5, null, T) // A default of 25, spread across the body.
	playsound(src, get_sfx(SFX_PUNCH), 50) //ouch sound

/mob/living/proc/near_wall(direction,distance=1)
	var/turf/T = get_step(get_turf(src),direction)
	var/turf/last_turf = src.loc
	var/i = 1

	while(i>0 && i<=distance)
		if(T.density) //Turf is a wall!
			return last_turf
		i++
		last_turf = T
		T = get_step(T,direction)

	return 0

// End BS12 momentum-transfer code.

/mob/living/attack_generic(mob/user, damage, attack_message)
	if(istype(user,/mob/living))
		var/mob/living/L = user
		if(touch_reaction_flags & SPECIES_TRAIT_THORNS)
			if((src != L))
				L.injure(INJURY_PIERCE, 3, L.hand ? BP_L_HAND : BP_R_HAND, src)
				act_message(L, src, MSG_SELF(span_warning("%T% is covered in sharp bits and it hurt when you touched them!")), \
					MSG_OTHERS(span_warning("%U% is hurt by sharp body parts when touching %T%!")))

	if(!damage)
		react_to_entry(DAMAGE_ENTRY_GENERIC, 0, user, user)
		return

	receive_generic_attack(user, damage)
	add_attack_logs(user,src,"Generic attack (probably animal)", admin_notify = FALSE) //Usually due to simple_mob attacks
	if(ai_brain)
		ai_brain.react_to_attack(user)
	act_message(user, src, others = span_danger("%U% has [attack_message] %T%!"))
	user.do_attack_animation(src)
	return 1

/// What kind of wound a generic (usually animal) attack from `user` leaves:
/// simple mobs declare their melee kind; anything else is a blunt blow.
/mob/living/proc/generic_attack_injury_kind(mob/user)
	return generic_attack_kind(user)

/mob/living/proc/get_cold_protection()
	return 0

/mob/living/proc/get_heat_protection()
	return 0

/mob/living/proc/get_shock_protection()
	return 0

/mob/living/proc/get_water_protection()
	return 1 // Water won't hurt most things.

/mob/living/proc/get_poison_protection()
	return 0

//Finds the effective temperature that the mob is burning at.
/mob/living/proc/fire_burn_temperature()
	if (fire_stacks <= 0)
		return 0

	//Scale quadratically so that single digit numbers of fire stacks don't burn ridiculously hot.
	//lower limit of 700 K, same as matches and roughly the temperature of a cool flame.
	return max(2.25*round(FIRESUIT_MAX_HEAT_PROTECTION_TEMPERATURE*(fire_stacks/FIRE_MAX_FIRESUIT_STACKS)**2), 700)

// Called when struck by lightning.
/mob/living/proc/lightning_act()
	// The actual damage/electrocution is handled by the tesla_zap() that accompanies this.
	status_at_least(STAT_PARALYZED, 5)
	status_at_least(STAT_SLEEPING, 5)
	status_adjust(STAT_STUTTERING, 20)
	status_adjust(STAT_JITTERY, 150)
	emp_act(EMP_HEAVY)
	to_chat(src, span_critical("You've been struck by lightning!"))

// Called when touching a lava tile.
// Does roughly 70 damage (30 instantly, up to ~40 over time) to unprotected mobs, and 10 to fully protected mobs.
/mob/living/lava_act()
	adjust_fire_stacks(4)
	inflict_heat_damage(20) // Another 20, however this is instantly applied to unprotected mobs.
	injure(INJURY_BURN, 10) // Lava cannot be 100% resisted with fire protection.

/mob/living/proc/reagent_permeability()
	return 1


// Returns a number to determine if something is harder or easier to hit than normal.
/mob/living/proc/get_evasion()
	return evasion + factor(BF_EVASION) // The 'base' evasion (generally zero) plus body factors.

/mob/living/proc/get_accuracy_penalty()
	// Certain statuses make it harder to score a hit.
	var/accuracy_penalty = 0
	if(has_status(STAT_BLINDED))
		accuracy_penalty += 75
	if(has_status(STAT_BLURRY))
		accuracy_penalty += 30
	if(has_status(STAT_CONFUSED))
		accuracy_penalty += 45

	return accuracy_penalty

// Applies direct "cold" damage while checking protection against the cold.
/mob/living/proc/inflict_cold_damage(amount)
	amount *= 1 - get_cold_protection(50) // Within spacesuit protection.
	if(amount > 0)
		injure(INJURY_FROSTBITE, amount)

// Ditto, but for "heat".
/mob/living/proc/inflict_heat_damage(amount)
	amount *= 1 - get_heat_protection(10000) // Within firesuit protection.
	if(amount > 0)
		injure(INJURY_BURN, amount)

// and one for electricity because why not
/mob/living/proc/inflict_shock_damage(amount)
	electrocute_act(amount, null, 1 - get_shock_protection(), pick(BP_HEAD, BP_TORSO, BP_GROIN))

// also one for water (most things resist it entirely, except for slimes)
/mob/living/proc/inflict_water_damage(amount)
	amount *= 1 - get_water_protection()
	if(amount > 0)
		injure(INJURY_TOXIN, amount)

// one for abstracted away ""poison"" (mostly because simplemobs shouldn't handle reagents)
/mob/living/proc/inflict_poison_damage(amount)
	amount *= 1 - get_poison_protection()
	if(amount > 0)
		injure(INJURY_TOXIN, amount)

/// Seconds of Life per unit of the old poisoned modifier's damage_per_tick (one Life cycle).
#define LINGERING_POISON_CYCLE (2 SECONDS)

/// A lingering, self-resolving poisoning (the old /datum/body_effect/poisoned): `per_cycle` toxin a
/// Life cycle for about `duration`, dealt as one lingering_poison affliction dose. Poison
/// protection scales it; the affliction's biology keeps it off synthetics.
/mob/living/proc/lingering_poison(per_cycle, duration, atom/source, paralytic = FALSE)
	var/amount = per_cycle * max(duration, 0) / LINGERING_POISON_CYCLE
	amount *= 1 - get_poison_protection()
	if(amount <= 0)
		return 0
	return injure(INJURY_TOXIN, amount, null, source, 0, paralytic ? /datum/affliction/venom/lingering_poison/paralytic : /datum/affliction/venom/lingering_poison)

#undef LINGERING_POISON_CYCLE

/// P2-S9: can `user` inject this mob at `target_zone` by `method` (INJECT_METHOD_*)?
/// Every injector calls this one proc; overrides honour armour and hide.
/mob/living/proc/can_inject(mob/user, error_msg, target_zone, ignore_thickness = FALSE, method = INJECT_METHOD_NEEDLE)
	return 1

/mob/living/proc/get_organ_target()
	var/mob/shooter = src
	var/t = shooter.zone_sel.selecting
	if ((t in list( O_EYES, O_MOUTH )))
		t = BP_HEAD
	var/obj/item/organ/external/def_zone = ran_zone(t)
	return def_zone

/mob/living/proc/restore_all_organs()
	return

/mob/living/proc/is_mouth_covered(head_only = FALSE, mask_only = FALSE)
	return FALSE

/mob/living/extrapolator_act(mob/living/user, obj/item/extrapolator/extrapolator, dry_run)
	. = ..()
	EXTRAPOLATOR_ACT_ADD_DISEASES(., get_contagions())
