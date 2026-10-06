
/obj/structure/blob
	name = "blob"
	icon = 'icons/mob/blob.dmi'
	desc = "A thick wall of writhing tendrils."
	light_range = 2
	density = FALSE // This is false because blob mob AI's walk_to() proc appears to never attempt to move onto dense objects even if allowed by CanPass().
	opacity = FALSE
	anchored = TRUE
	layer = MOB_LAYER + 0.1
	var/point_return = 0 //How many points the blob gets back when it removes a blob of that type. If less than 0, blob cannot be removed.
	max_integrity = 30
	var/health_regen = 2 //how much health this blob regens when pulsed
	EXPIRY_DECLARE(pulse_timestamp) //we got pulsed when?
	EXPIRY_DECLARE(heal_timestamp) //we got healed when?
	var/mob/observer/blob/overmind = null
	var/base_name = "blob" // The name that gets appended along with the blob_type's name.
	var/faction = FACTION_BLOB

REGISTRY_MEMBERSHIP(/obj/structure/blob, REGISTRY_BLOBS)

CAPABILITIES(/obj/structure/blob)
	param(nameof(overmind), pos = 1)

// ALLOW(init/INSTANCE_STATE): a blob takes its overmind's faction, faces a random way and consumes its tile before its parents' init
/obj/structure/blob/Initialize(mapload)
	if(overmind)
		faction = overmind.blob_type.faction
	set_dir(pick(GLOB.cardinal))
	consume_tile()
	. = ..()
	update_icon()

DESTROY_EFFECTS(/obj/structure/blob, new /datum/destroy_effects_data(sound = SFX_EFFECTS_SPLAT))

DECLARE_APPEARANCE_PROC(/obj/structure/blob, TYPE_PROC_REF(/atom, appearance_overlays), list())
/obj/structure/blob/appearance_overlays() //Updates color based on overmind color if we have an overmind.
	. = list()
	if(overmind)
		name = "[overmind.blob_type.name] [base_name]" // This is in update_icon() because inert blobs can turn into other blobs with magic if another blob core claims it with pulsing.
		color = overmind.blob_type.color
		set_light(3, 3, color)
	else
		name = "inert [base_name]"
		color = null
		set_light(0)

/obj/structure/blob/update_transform()
	var/matrix/M = matrix()
	M.Scale(icon_scale_x, icon_scale_y)
	animate(src, transform = M, time = 10)

// Blob tiles are not actually dense so we need Special Code(tm).
/obj/structure/blob/CanPass(atom/movable/mover, turf/target)
	if(istype(mover) && mover.checkpass(PASSBLOB))
		return TRUE
	else if(isliving(mover))
		var/mob/living/L = mover
		if(L.faction == faction)
			return TRUE
	else if(istype(mover, /obj/item/projectile))
		var/obj/item/projectile/P = mover
		if(istype(P.firer, /obj/structure/blob))
			return TRUE
		if(istype(P.firer) && P.firer.faction == faction)
			return TRUE
	return FALSE

/obj/structure/blob/examine(mob/user)
	. = ..()
	if(!overmind)
		. += "It seems inert." // Dead blob.
	else
		. += overmind.blob_type.desc

/obj/structure/blob/get_mechanics_info(list/additional_information)
	if(overmind)
		return overmind.blob_type.effect_desc
	return ..()

DAMAGE_REACTION(/obj/structure/blob, DAMAGE_EMP, PROC_REF(blob_on_emp))

/// A live blob's type reacts to a pulse.
/obj/structure/blob/proc/blob_on_emp(datum/damage_packet/packet)
	if(!overmind)
		return
	overmind.blob_type.on_emp(src, packet.severity)

/obj/structure/blob/proc/pulsed()
	if(!BEFORE(src, pulse_timestamp, CLOCK_WORLD))
		consume_tile()
		if(!BEFORE(src, heal_timestamp, CLOCK_WORLD))
			adjust_integrity(health_regen)
			EXPIRY_SET(src, heal_timestamp, 2 SECONDS, CLOCK_WORLD)
		update_icon()
		EXPIRY_SET(src, pulse_timestamp, 1 SECOND, CLOCK_WORLD)
		if(overmind)
			faction = overmind.blob_type.faction
			overmind.blob_type.on_pulse(src)
		return TRUE //we did it, we were pulsed!
	return FALSE //oh no we failed

/obj/structure/blob/proc/pulse_area(pulsing_overmind = overmind, claim_range = 10, pulse_range = 3, expand_range = 2)
	src.pulsed()
	var/expanded = FALSE
	if(prob(70) && expand())
		expanded = TRUE

	var/list/blobs_to_affect = list()
	for(var/obj/structure/blob/B in urange(claim_range, src, 1))
		blobs_to_affect += B

	shuffle_inplace(blobs_to_affect)

	for(var/obj/structure/blob/B as anything in blobs_to_affect)
		if(B.faction != faction)
			continue

		if(!B.overmind && !istype(B, /obj/structure/blob/core) && prob(30))
			rel_set(B, nameof(B.overmind), pulsing_overmind) //reclaim unclaimed, non-core blobs.
			B.update_icon()

		var/distance = get_dist(get_turf(src), get_turf(B))
		var/expand_probablity = max(50 / (max(distance, 1)), 1)
		if(overmind)
			expand_probablity *= overmind.blob_type.spread_modifier
			if(overmind.blob_type.slow_spread_with_size)
				expand_probablity /= (REGISTRY_COUNT(REGISTRY_BLOBS) / 10)

		if(distance <= expand_range)
			var/can_expand = TRUE
			if(blobs_to_affect.len >= 120 && BEFORE(src, B.heal_timestamp, CLOCK_WORLD))
				can_expand = FALSE
			if(!expanded && can_expand && !BEFORE(src, B.pulse_timestamp, CLOCK_WORLD) && prob(expand_probablity))
				var/obj/structure/blob/newB = B.expand(null, null, !expanded) //expansion falls off with range but is faster near the blob causing the expansion
				if(newB)
					if(expanded)
						spent(newB)
					expanded = TRUE

		if(distance <= pulse_range)
			B.pulsed()

/// The second half of expand(): the new blob slides into `T`.
/obj/structure/blob/proc/slide_into(turf/T, obj/structure/blob/origin, expand_reaction)
	set_density(initial(density))
	forceMove(T)
	update_icon()
	if(overmind && expand_reaction)
		overmind.blob_type.on_expand(origin, src, T, overmind)

/obj/structure/blob/proc/expand(turf/T = null, controller = null, expand_reaction = 1)
	if(!T)
		var/list/dirs = GLOB.cardinal.Copy()
		for(var/i = 1 to 4)
			var/dirn = pick(dirs)
			dirs.Remove(dirn)
			T = get_step(src, dirn)
			var/obj/structure/blob/B = locate_on(T, /obj/structure/blob)
			if(!B || B.faction != faction)	// Allow opposing blobs to fight.
				break
			else
				T = null
	if(!T)
		return FALSE

	var/make_blob = TRUE //can we make a blob?

	if(istype(T, /turf/space) && !(locate_on(T, /obj/structure/lattice)) && prob(80))
		make_blob = FALSE
		play_sfx(src, SFX_EFFECTS_SPLAT) //Let's give some feedback that we DID try to spawn in space, since players are used to it

	consume_tile() //hit the tile we're in, making sure there are no border objects blocking us

	if(!T.CanPass(src, T)) //is the target turf impassable
		make_blob = FALSE
		T.blob_act(src) //hit the turf if it is

	for(var/atom/A in turf_contents_of_type(T, /atom))
		if(!A.CanPass(src, T)) //is anything in the turf impassable
			make_blob = FALSE
		A.blob_act(src) //also hit everything in the turf

	if(make_blob) //well, can we?
		var/obj/structure/blob/B = new /obj/structure/blob/normal(src.loc)
		B.faction = faction
		if(controller)
			rel_set(B, nameof(B.overmind), controller)
		else
			rel_set(B, nameof(B.overmind), overmind)
		B.set_density(TRUE)
		if(T.Enter(B,src)) //NOW we can attempt to move into the tile
			// A decisecond later, so the slide animation works.
			after(B, 0.1 SECONDS, TYPE_PROC_REF(/obj/structure/blob, slide_into), with = list(T, src, expand_reaction))
			return B

		else
			blob_attack_animation(T, controller)
			T.blob_act(src) //if we can't move in hit the turf again
			spent(B) //we should never get to this point, since we checked before moving in. destroy the blob so we don't have two blobs on one tile
			return null
	else
		blob_attack_animation(T, controller) //if we can't, animate that we attacked
	return null

/obj/structure/blob/proc/consume_tile()
	for(var/atom/A in contents_of(loc))
		A.blob_act(src)
	if(loc && loc.density)
		loc.blob_act(src) //don't ask how a wall got on top of the core, just eat it

/obj/structure/blob/proc/blob_glow_animation()
	flick("[icon_state]_glow", src)

/obj/structure/blob/proc/blob_attack_animation(atom/A = null, controller) //visually attacks an atom
	var/obj/effect/temporary_effect/blob_attack/O = new /obj/effect/temporary_effect/blob_attack(src.loc)
	O.set_dir(dir)
	if(controller)
		var/mob/observer/blob/BO = controller
		O.color = BO.blob_type.color
		O.alpha = 200
	else if(overmind)
		O.color = overmind.blob_type.color
	if(A)
		O.do_attack_animation(A) //visually attack the whatever
	return O //just in case you want to do something to the animation.

/obj/structure/blob/proc/change_to(type, controller)
	if(!ispath(type))
		throw EXCEPTION("change_to(): invalid type for blob")
		return
	var/obj/structure/blob/B = new type(src.loc, controller)
	if(controller)
		rel_set(B, nameof(B.overmind), controller)
	B.update_icon()
	B.set_dir(dir)
	replace_with(src, B)
	return B

/obj/structure/blob/attack_generic(mob/user, damage, attack_verb)
	act_message(user, src, others = span_danger("%U% [attack_verb] %T%!"))
	play_sfx(src, SFX_EFFECTS_ATTACKBLOB, 2)
	user.do_attack_animation(src)
	if(overmind)
		damage *= overmind.blob_type.brute_multiplier
	else
		damage *= 2

	if(overmind)
		damage = overmind.blob_type.on_received_damage(src, damage, BRUTE, user)

	adjust_integrity(-damage)

DECLARE_INTERACTIONS(/obj/structure/blob, \
	INTERACT_HAND_UNGATED(null, PROC_REF(interaction_hand)), \
	INTERACT_ITEM(null, PROC_REF(interaction_item)), \
)

/// Old attack_hand.
/obj/structure/blob/proc/interaction_hand(mob/living/M, obj/item/held, datum/interaction/interaction)
	if(ishuman(M))
		var/mob/living/carbon/human/H = M
		H.setClickCooldown(H.get_attack_speed())
		var/datum/unarmed_attack/attack = H.get_unarmed_attack(src, BP_TORSO)
		if(!attack)
			return TRUE

		if(attack.unarmed_override(H, src, BP_TORSO))
			return TRUE

		H.do_attack_animation(src)
		act_message(H, src, others = span_danger("%U% strikes %T%!"))

		var/real_damage = rand(3,6)
		var/hit_kind = attack.injury_kind
		real_damage += attack.get_unarmed_damage(H)
		if(H.get_equipped_item(SLOT_ID_GLOVES))
			if(istype(H.get_equipped_item(SLOT_ID_GLOVES), /obj/item/clothing/gloves))
				var/obj/item/clothing/gloves/G = H.get_equipped_item(SLOT_ID_GLOVES)
				real_damage += G.punch_force
				hit_kind = G.punch_injury_kind || hit_kind
		if(H.has_mutation(HULK))
			real_damage *= 2 // Hulks do twice the damage

		real_damage = max(1, real_damage)

		var/damage_mult_burn = 1
		var/damage_mult_brute = 1

		switch(hit_kind)
			if(INJURY_CORROSIVE)
				damage_mult_burn *= 0.6
				damage_mult_brute = 0
			if(INJURY_BURN, INJURY_ELECTRIC)
				damage_mult_brute = 0
			if(INJURY_BLUNT, INJURY_CUT, INJURY_PIERCE, INJURY_CELLULAR)
				damage_mult_burn = 0
			if(INJURY_PAIN)
				damage_mult_brute = 0.25
				damage_mult_burn = 0
			else // Toxins, asphyxia, or something new. Half damage split to the organism.
				damage_mult_burn = 0.25
				damage_mult_brute = 0.25

		var/burn_amt = real_damage * damage_mult_burn
		var/brute_amt = real_damage * damage_mult_brute

		if(overmind)
			if(brute_amt)
				brute_amt = overmind.blob_type.on_received_damage(src, brute_amt, BRUTE, M)
			if(burn_amt)
				burn_amt = overmind.blob_type.on_received_damage(src, burn_amt, BURN, M)

		real_damage = burn_amt + brute_amt

		adjust_integrity(-real_damage)

	else
		generic_hit(src, M, rand(1,10), "bashed")
	return TRUE

/// Old attackby.
/obj/structure/blob/proc/interaction_item(mob/user, obj/item/W, datum/interaction/interaction)
	user.setClickCooldown(DEFAULT_ATTACK_COOLDOWN)
	play_sfx(src, SFX_EFFECTS_ATTACKBLOB)
	act_message(src, user, others = span_danger("%U% has been attacked with %I%[user ? " by %T%." : "."]"), item = W)
	var/damage = W.force
	switch(W.obj_damage_type())
		if(BURN)
			if(overmind)
				damage *= overmind.blob_type.burn_multiplier
			else
				damage *= 2

			if(damage > 0)
				play_sfx(src, SFX_ITEMS_WELDER)
			else
				play_sfx(src, SFX_WEAPONS_TAP)
		if(BRUTE)
			if(overmind)
				damage *= overmind.blob_type.brute_multiplier
			else
				damage *= 2

			if(damage > 0)
				play_sfx(src, SFX_EFFECTS_ATTACKBLOB)
			else
				play_sfx(src, SFX_WEAPONS_TAP)
	if(overmind)
		damage = overmind.blob_type.on_received_damage(src, damage, W.obj_damage_type(), user)
	adjust_integrity(-damage)
	return INTERACTION_HANDLED_PASS

/// Packet sink for the adapters with nothing blob-specific to say (fire,
/// explosions, shocks): each kind is scaled by the blob type's brute or burn
/// multiplier and offered to its on_received_damage() before it lands on integrity.
/obj/structure/blob/damage_sink(datum/damage_packet/packet)
	if(QDELETED(src))
		return 0
	var/list/amounts = packet.amounts
	. = 0
	for(var/kind in 1 to DAMAGE_KIND_COUNT)
		var/amount = amounts[kind]
		if(amount <= 0)
			continue
		var/damage_type = damage_kind_obj_damage_type(kind)
		if(!damage_type || (kind == DAMAGE_IONIC && !emp_integrity_factor))
			continue
		if(overmind)
			amount *= damage_type == BURN ? overmind.blob_type.burn_multiplier : overmind.blob_type.brute_multiplier
			amount = overmind.blob_type.on_received_damage(src, amount, damage_type, packet.attacker)
		. += adjust_integrity(-amount)
		if(QDELETED(src))
			return

/obj/structure/blob/bullet_act(obj/item/projectile/P)
	if(!P)
		return

	if(istype(P.firer) && P.firer.faction == faction)
		return

	return ..()

/// Projectile adapter: only a round's structural damage hurts a blob, so tasers don't.
/obj/structure/blob/projectile_damage(obj/item/projectile/P, def_zone)
	var/damage = P.get_structure_damage()
	if(!damage)
		return 0

	switch(P.obj_damage_type())
		if(BRUTE)
			if(overmind)
				damage *= overmind.blob_type.brute_multiplier
		if(BURN)
			if(overmind)
				damage *= overmind.blob_type.burn_multiplier

	if(overmind)
		damage = overmind.blob_type.on_received_damage(src, damage, P.obj_damage_type(), P.firer)

	return adjust_integrity(-damage)

/obj/structure/blob/water_act(amount)
	if(overmind)
		overmind.blob_type.on_water(src, amount)

/obj/structure/blob/blob_act(obj/structure/blob/B)
	if(B)

		if(!B.overmind)
			return

		if(B.faction != faction)
			var/damage = rand(B.overmind.blob_type.damage_lower, B.overmind.blob_type.damage_upper)
			var/inc_damage_type = injury_kind_obj_damage_type(B.overmind.blob_type.injury_kind)

			if(overmind)
				damage = overmind.blob_type.on_received_damage(src, damage, inc_damage_type, B)

			else
				faction = B.faction
				rel_set(src, nameof(overmind), B.overmind)
				update_icon()
				return

			adjust_integrity(-1 * damage)

	return

/// Heals (positive) or hurts (negative) the blob's integrity. Blob damage is
/// already scaled by the blob type, so it skips armour. Returns the damage dealt.
/obj/structure/blob/proc/adjust_integrity(amount)
	if(amount > 0)
		repair_damage(amount)
		return 0
	if(amount < 0)
		return take_damage(-amount, BRUTE, null, FALSE)
	return 0

/obj/structure/blob/on_update_integrity(old_value, new_value)
	. = ..()
	update_icon()

/// Integrity depletion: the blob type gets its death hook, and no debris is left.
/obj/structure/blob/handle_deconstruct(disassembled = TRUE)
	if(disassembled)
		return
	play_sfx(src, SFX_EFFECTS_SPLAT)
	if(overmind)
		overmind.blob_type.on_death(src)

/obj/effect/temporary_effect/blob_attack
	name = "blob"
	desc = "The blob lashing out at something."
	icon_state = "blob_attack"
	plane = MOB_PLANE
	layer = ABOVE_MOB_LAYER
	time_to_die = 6
	alpha = 140
	mouse_opacity = 0

DAMAGE_REACTION(/obj/structure/grille, DAMAGE_BLOB, TYPE_PROC_REF(/atom, damage_reaction_qdel))

/turf/simulated/wall/blob_act(obj/structure/blob/B)
	deal_damage(DAMAGE_BLUNT, 100, MELEE, B, B?.overmind)

// Every blob names its overmind (a one-sided view); only resource blobs pair with its
// resource_blobs list (resource.dm).
/obj/structure/blob/relations()
	. = ..()
	. += rel_one(nameof(overmind))
/mob/observer/blob/relations()
	. = ..()
	. += rel_many(nameof(resource_blobs), back = nameof(/obj/structure/blob/resource::overmind))
