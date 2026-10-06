/datum/body_effect/underwater_stealth
	tick_interval = 2 SECONDS
	name = "underwater stealth"
	desc = "You are currently underwater, rendering it more difficult to see you and enabling you to move quicker, thanks to your aquatic nature."

	on_created_text = span_warning("You sink under the water.")
	on_expired_text = span_notice("You come out from the water.")

	stacks = MODIFIER_STACK_FORBID

	// A bit faster when actually submerged fully in water, as you're not waddling through it. // nerf this a lil
	// You are, however, underwater. Getting shocked will hurt.
	// You are swinging a sword under water...Good luck.
	// You're underwater. Good luck shooting a gun. (Makes shots as if you were 3.33 tiles further.)
	// You're underwater and a bit harder to hit.
	factors = alist(BF_SLOWDOWN = -1.0, BF_ACCURACY = -50, BF_EVASION = 30, BF_MELEE_DAMAGE = 0.75, BF_SIEMENS = 1.5)

/datum/body_effect/underwater_stealth/on_start(mob/living/L)
	L.set_alpha_source(ALPHA_SOURCE_UNDERWATER_STEALTH, 50/255)
	return

/datum/body_effect/underwater_stealth/on_end(mob/living/L, expired)
	L.clear_alpha_source(ALPHA_SOURCE_UNDERWATER_STEALTH)
	return

/datum/body_effect/underwater_stealth/on_tick(mob/living/L)
	if(L.stat == DEAD)
		L.end_body_effect(type, TRUE) //If you're dead you float to the top.
		return
	if(istype(L.loc, /turf/simulated/floor/water))
		var/turf/simulated/floor/water/water_floor = L.loc
		if(water_floor.depth < 1) //You're not in deep enough water anymore.
			L.end_body_effect(type, FALSE)
			return
		if(water_floor.depth > 1)
			L.set_alpha_source(ALPHA_SOURCE_UNDERWATER_STEALTH, 50/255)
		else
			L.set_alpha_source(ALPHA_SOURCE_UNDERWATER_STEALTH, 65/255)
	else
		L.end_body_effect(type, FALSE)

// Personal shield projections. Their numeric effects (siemens, stun
// resistance, evasion...) are ordinary body factors; the one thing that is
// not a simple multiplier is the charge-dependent damage resistance, which
// also drains the generator's cell for what it absorbs. That runs as stage 2
// of injure()'s mitigation while the shield is up.
/datum/body_effect/shield_projection
	tick_interval = 2 SECONDS
	name = "Shield Projection"
	desc = "You are currently protected by a shield, rendering nigh impossible to hit you through conventional means."

	on_created_text = span_notice("Your shield generator buzzes on.")
	on_expired_text = span_warning("Your shield generator buzzes off.")
	stacks = MODIFIER_STACK_FORBID //No stacking shields. If you put one one your belt and backpack it won't work.

	icon_override = 1
	mob_overlay_state = "deflect"
	// Stun weapons drain 100% charge per point of damage. They're good at blocking lasers and bullets but not good at blocking stun beams!
	factors = alist(BF_SIEMENS = 2)

	end_on_death = TRUE // the generator stops protecting you but keeps running

	/// Cell charge used per point of injury the shield absorbs when the generator doesn't say.
	var/damage_cost = 50
	/// Injury multipliers at FULL charge: INJURY_CATEGORY_* -> multiplier
	/// (SHIELD_RESIST_ALL for every injury). 0 = immune, 1 = full injury.
	var/alist/resist_full
	/// Injury multipliers at EMPTY charge; the shield slides between the two.
	/// Missing categories are 1 (no protection) when empty.
	var/alist/resist_empty

/// Key in resist_full / resist_empty that applies to every injury category.
#define SHIELD_RESIST_ALL 0

// Per-application state: the handle of the generator projecting the shield.

/datum/body_effect/shield_projection/on_start(mob/living/L)
	observe(L, /datum/notice/living_shield_injury, src, then(PROC_REF(on_holder_injure)))
	on_check(L)

/datum/body_effect/shield_projection/on_end(mob/living/L, expired)
	unobserve(L, /datum/notice/living_shield_injury, src)

/// The generator worn on the back, belt or suit storage (only humans wear them), or null.
/datum/body_effect/shield_projection/proc/find_generator(mob/living/L)
	if(!ishuman(L))
		return null
	var/mob/living/carbon/human/H = L
	for(var/slot in list(SLOT_ID_BACK, SLOT_ID_BELT, SLOT_ID_SUIT_STORAGE))
		var/obj/item/personal_shield_generator/G = H.get_equipped_item(slot)
		if(istype(G))
			return G
	return null

/// The generator projecting the shield on `L`, or null. The effect's per-mob state is the colour
/// it last drew (plain data), so a generator swap re-draws without holding a reference to it.
/datum/body_effect/shield_projection/proc/generator_of(mob/living/L) as /obj/item/personal_shield_generator
	return find_generator(L)

/// The generator must still be worn (and switched on); it also sets the shield's colour.
/datum/body_effect/shield_projection/on_check(mob/living/L)
	var/obj/item/personal_shield_generator/G = find_generator(L)
	if(!G || !G.slot_check())
		L.end_body_effect(type, !G)
		return
	if(L.body_effect_state(type) != G.effect_color)
		L.set_body_effect_state(type, G.effect_color)
		L.update_modifier_visuals()

/datum/body_effect/shield_projection/overlay_color(mob/living/L)
	var/obj/item/personal_shield_generator/G = generator_of(L)
	return G ? G.effect_color : effect_color

/// Injury multiplier for `category` at the cell's current charge on `L`, or null
/// when the shield doesn't touch that category.
/datum/body_effect/shield_projection/proc/resistance(mob/living/L, category)
	var/obj/item/cell/energy_source = generator_of(L)?.bcell
	var/efficiency = energy_source?.maxcharge ? energy_source.charge / energy_source.maxcharge : 0
	. = null
	for(var/key in list(SHIELD_RESIST_ALL, category))
		if(isnull(resist_full?[key]))
			continue
		var/empty = isnull(resist_empty?[key]) ? 1 : resist_empty[key]
		var/mult = empty + (resist_full[key] - empty) * efficiency
		. = isnull(.) ? mult : . * mult

/datum/body_effect/shield_projection/proc/on_holder_injure(datum/act/notice/A)
	SHOULD_NOT_SLEEP(TRUE)
	var/mob/living/source = A.target
	var/datum/notice/living_shield_injury/event = A
	var/kind = event.kind
	var/list/amount_ref = event.amount_ref
	var/mult = resistance(source, injury_category(kind))
	if(isnull(mult))
		return NONE
	var/obj/item/personal_shield_generator/G = generator_of(source)
	G?.bcell?.use((G ? G.damage_cost : damage_cost) * amount_ref[1])
	amount_ref[1] *= mult
	return NONE

//Shield variants.

//Simple. Goes from 100% resistance to 0% resistance depending on charge. This is mostly an example of a shield variant.
/datum/body_effect/shield_projection/bruteburn
	resist_full = alist(INJURY_CATEGORY_PHYSICAL = 0, INJURY_CATEGORY_THERMAL = 0)

/datum/body_effect/shield_projection/bruteburn/weak
	resist_full = alist(INJURY_CATEGORY_PHYSICAL = 0.5, INJURY_CATEGORY_THERMAL = 0.5)

//SECURITY VARIANTS
/datum/body_effect/shield_projection/security // Security backpack. 50% resistance at full charge. 10% resistance for the last shot taken.
	resist_full = alist(INJURY_CATEGORY_PHYSICAL = 0.5, INJURY_CATEGORY_THERMAL = 0.5, INJURY_CATEGORY_PAIN = 0.5)
	resist_empty = alist(INJURY_CATEGORY_PHYSICAL = 0.9, INJURY_CATEGORY_THERMAL = 0.9, INJURY_CATEGORY_PAIN = 0.9)
	factors = alist(BF_DISABLE_DURATION = 0.75, BF_SIEMENS = 2)

/datum/body_effect/shield_projection/security/weak // Security belt.
	resist_full = alist(INJURY_CATEGORY_PHYSICAL = 0.75, INJURY_CATEGORY_THERMAL = 0.75, INJURY_CATEGORY_PAIN = 0.75)
	resist_empty = alist(INJURY_CATEGORY_PHYSICAL = 0.95, INJURY_CATEGORY_THERMAL = 0.95, INJURY_CATEGORY_PAIN = 0.95)

/datum/body_effect/shield_projection/security/strong // Dunno. Upgraded variant of security backpack?
	resist_full = alist(INJURY_CATEGORY_PHYSICAL = 0.25, INJURY_CATEGORY_THERMAL = 0.25, INJURY_CATEGORY_PAIN = 0.25)
	// Not as weak as normal, but still weak.
	factors = alist(BF_DISABLE_DURATION = 0.5, BF_SIEMENS = 1.5)

//MINING VARIANTS
/datum/body_effect/shield_projection/mining //Base mining belt. 30% resistance that fades to 15% resistance
	// No mobs should be shooting you with halloss. If this happens, it means you're using it wrong!!!
	resist_full = alist(INJURY_CATEGORY_PHYSICAL = 0.7, INJURY_CATEGORY_THERMAL = 0.7, INJURY_CATEGORY_PAIN = 1.5)
	resist_empty = alist(INJURY_CATEGORY_PHYSICAL = 0.85, INJURY_CATEGORY_THERMAL = 0.85, INJURY_CATEGORY_PAIN = 1.5)
	// Miners often come into contact with things that can stun them.
	factors = alist(BF_DISABLE_DURATION = 0.75, BF_SIEMENS = 2)

/datum/body_effect/shield_projection/mining/strong // Mining belt, but upgraded. Even weaker to halloss!
	resist_full = alist(INJURY_CATEGORY_PHYSICAL = 0.55, INJURY_CATEGORY_THERMAL = 0.55, INJURY_CATEGORY_PAIN = 2)
	resist_empty = alist(INJURY_CATEGORY_PHYSICAL = 0.75, INJURY_CATEGORY_THERMAL = 0.75, INJURY_CATEGORY_PAIN = 2)
	factors = alist(BF_DISABLE_DURATION = 0.5, BF_SIEMENS = 2)

//MISC VARIANTS

/datum/body_effect/shield_projection/biohazard //The odd-ball damage types. Provides near-complete immunity while it's up.
	resist_full = alist(INJURY_CATEGORY_TOXIC = 0, INJURY_CATEGORY_GENETIC = 0)
	resist_empty = alist(INJURY_CATEGORY_TOXIC = 0.25, INJURY_CATEGORY_GENETIC = 0.25)

/datum/body_effect/shield_projection/admin // Adminbus.
	on_created_text = span_notice("Your shield generator activates and you feel the power of the tesla buzzing around you.")
	on_expired_text = span_warning("Your shield generator deactivates, leaving you feeling weak and vulnerable.")
	factors = alist(BF_DISABLE_DURATION = 0, BF_SIEMENS = 0)
	resist_full = alist(SHIELD_RESIST_ALL = 0)
	resist_empty = alist(SHIELD_RESIST_ALL = 0)

/datum/body_effect/shield_projection/broken //For broken variants. Good if possible randomization is included for packs spawned on PoIs.
	resist_full = alist(INJURY_CATEGORY_PHYSICAL = 2, INJURY_CATEGORY_THERMAL = 2)
	resist_empty = alist(INJURY_CATEGORY_PHYSICAL = 2, INJURY_CATEGORY_THERMAL = 2)

/datum/body_effect/shield_projection/inverted //Becomes stronger the weaker the cell is. Means the last shot taken will be the weakest. Example just to show it can be done.
	resist_full = alist(INJURY_CATEGORY_PHYSICAL = 1, INJURY_CATEGORY_THERMAL = 1)
	resist_empty = alist(INJURY_CATEGORY_PHYSICAL = 0, INJURY_CATEGORY_THERMAL = 0)

/datum/body_effect/shield_projection/parry //Intended for 'parry' shields, which only last for a single second before running out of charge
	resist_full = alist(INJURY_CATEGORY_PHYSICAL = 0, INJURY_CATEGORY_THERMAL = 0, INJURY_CATEGORY_PAIN = 0)
	resist_empty = alist(INJURY_CATEGORY_PHYSICAL = 0, INJURY_CATEGORY_THERMAL = 0, INJURY_CATEGORY_PAIN = 0)

/datum/body_effect/shield_projection/melee_focus
	//You are expected to be taking a LOT more hits while this is up.
	damage_cost = 5
	// 50% resistance at a full charge, 35% when about to empty. 500% damage
	// taken from halloss: anti PVP, this is meant to be a PvE weapon.
	resist_full = alist(INJURY_CATEGORY_PHYSICAL = 0.5, INJURY_CATEGORY_THERMAL = 0.5, INJURY_CATEGORY_PAIN = 5)
	resist_empty = alist(INJURY_CATEGORY_PHYSICAL = 0.65, INJURY_CATEGORY_THERMAL = 0.65, INJURY_CATEGORY_PAIN = 5)
	// Stuns are half as long; much harder to shoot; somewhat faster; can't
	// shoot; attacks faster and harder; bleeds slightly slower.
	factors = alist(BF_BLEEDING = 0.75, BF_SLOWDOWN = -0.5, BF_ACCURACY = -1000, BF_EVASION = 35, BF_ATTACK_SPEED = 0.8, BF_MELEE_DAMAGE = 1.25, BF_DISABLE_DURATION = 0.5, BF_SIEMENS = 2)

/// Exploration boss loot: a generator belt that pulls ore towards you.
/datum/body_effect/shield_projection/magnet
	name = "Magnet Pull"
	mob_overlay_state = null
	factors = null

/datum/body_effect/shield_projection/magnet/on_tick(mob/living/L)
	for(var/obj/item/ore/O in orange(4, L))
		step_towards(O, get_turf(L))

/datum/body_effect/shield_projection/magnet/defense
	resist_full = alist(INJURY_CATEGORY_PHYSICAL = 0.3, INJURY_CATEGORY_THERMAL = 0.3)
	resist_empty = alist(INJURY_CATEGORY_PHYSICAL = 0.8, INJURY_CATEGORY_THERMAL = 0.8)

#undef SHIELD_RESIST_ALL
