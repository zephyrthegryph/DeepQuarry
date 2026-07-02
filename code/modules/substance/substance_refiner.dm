// The substance refiner (design doc §11).
//
// A material operation on a substance: refine TOWARD a target property at a cost
// to the others. Purify for power and you lose stability; tune the resonance to
// aim a counter and you muddy the rest. There is no flat upgrade here — every
// refine is a trade, so a refined counter is genuinely a counter (excellent at the
// one thing, worse elsewhere) rather than a strictly-better substance.
//
// Operates on a substance material stack (a substance is always material): it
// consumes the loaded stack and casts a fresh stack of the refined alloy. No TGUI —
// a single-slot bench driven by a choice menu, so the trade is an explicit decision.

// The refinement operations — each pushes one axis at the others' expense (see
// apply_refine below). Shared by the standalone bench and the particle-accelerator
// refine path (particle_smasher), so both offer the same trades.
GLOBAL_LIST_INIT(substance_refine_ops, list(
	"Concentrate — Energy up, Volatility up, Purity down",
	"Stabilize — Volatility down, Energy down",
	"Bond — Affinity up, Energy down",
	"Purify — Purity up, Energy down",
	"Tune resonance + (Purity down)",
	"Tune resonance − (Purity down)",
))

/obj/machinery/substance_refiner
	name = "substance refiner"
	desc = "A precision bench for pushing one property of a substance at the expense of the rest. Load a substance stack and choose a refinement."
	icon = 'icons/obj/chemical.dmi'
	icon_state = "mixer0"
	density = TRUE
	anchored = TRUE
	use_power = USE_POWER_IDLE
	idle_power_usage = 20
	active_power_usage = 150
	var/obj/item/stack/material/substance/loaded

/obj/machinery/substance_refiner/Destroy()
	QDEL_NULL(loaded)
	return ..()

/obj/machinery/substance_refiner/attackby(obj/item/I, mob/user)
	if(istype(I, /obj/item/stack/material/substance))
		var/obj/item/stack/material/substance/stack = I
		if(loaded)
			to_chat(user, span_warning("\The [src] already holds a stack."))
			return
		if(!substance_stack_substance(stack))
			to_chat(user, span_warning("\The [stack] is not a workable substance."))
			return
		if(!user.unEquip(stack, src))
			return
		loaded = stack
		to_chat(user, span_notice("You load \the [stack] into \the [src]."))
		return
	return ..()

/obj/machinery/substance_refiner/attack_hand(mob/user)
	if(..())
		return
	if(stat & (BROKEN|NOPOWER))
		return
	if(!substance_stack_substance(loaded))
		to_chat(user, span_warning("Load a substance stack first."))
		return

	var/list/ops = GLOB.substance_refine_ops + list("Eject stack")
	var/choice = input(user, "Refine \the [loaded]?", "Substance Refiner") as null|anything in ops
	if(!choice || !substance_stack_substance(loaded) || !Adjacent(user))
		return

	if(choice == "Eject stack")
		eject(user)
		return

	// Refine into a fresh alloy: clone the substance, trade its axes, recast a stack.
	// The bench's own idle rating is its engineering ceiling; the room is the atmos axis.
	var/datum/substance/refined = substance_stack_substance(loaded).Clone()
	apply_refine(refined, choice, substance_env_context(src, SUBSTANCE_ATTR_MAX))
	var/amount = loaded.amount
	var/turf/T = get_turf(src)
	QDEL_NULL(loaded)
	substance_spawn_stack(T, refined, amount)
	qdel(refined)
	use_power(active_power_usage)
	to_chat(user, span_notice("\The [src] recasts the stock as a refined alloy."))

/obj/machinery/substance_refiner/proc/eject(mob/user)
	if(!loaded)
		return
	loaded.forceMove(get_turf(src))
	if(user && Adjacent(user))
		user.put_in_hands(loaded)
	loaded = null

// Apply a refinement's trade to a substance, clamping to the axis bounds.
//
// An optional environment context (atmospherics + engineering, same one the resolver
// uses) modulates the trade after the base push:
//   * atmos (ctx.volatility_mod) — a hot / high-pressure room refines less cleanly, so
//     any leftover heat lands as extra volatility; a cold room settles it.
//   * engineering (ctx.energy_ceiling) — the machine's rating caps how much energy a
//     refine may hold. Push energy past the ceiling and the overdrive spills into
//     volatility instead, so a better-rated machine safely pushes energy-up trades
//     further. 0 == unrated (no cap).
/proc/apply_refine(datum/substance/S, choice, datum/substance_context/ctx = null)
	switch(choice)
		if("Concentrate — Energy up, Volatility up, Purity down")
			S.energy = clamp(S.energy + 15, 0, SUBSTANCE_ATTR_MAX)
			S.volatility = clamp(S.volatility + 10, 0, SUBSTANCE_ATTR_MAX)
			S.purity = clamp(S.purity - 10, 0, SUBSTANCE_ATTR_MAX)
		if("Stabilize — Volatility down, Energy down")
			S.volatility = clamp(S.volatility - 15, 0, SUBSTANCE_ATTR_MAX)
			S.energy = clamp(S.energy - 8, 0, SUBSTANCE_ATTR_MAX)
		if("Bond — Affinity up, Energy down")
			S.affinity = clamp(S.affinity + 15, 0, SUBSTANCE_ATTR_MAX)
			S.energy = clamp(S.energy - 6, 0, SUBSTANCE_ATTR_MAX)
		if("Purify — Purity up, Energy down")
			S.purity = clamp(S.purity + 15, 0, SUBSTANCE_ATTR_MAX)
			S.energy = clamp(S.energy - 10, 0, SUBSTANCE_ATTR_MAX)
		if("Tune resonance + (Purity down)")
			S.resonance = (S.resonance + 30) % SUBSTANCE_RES_MAX
			S.purity = clamp(S.purity - 8, 0, SUBSTANCE_ATTR_MAX)
		if("Tune resonance − (Purity down)")
			S.resonance = (S.resonance - 30 + SUBSTANCE_RES_MAX) % SUBSTANCE_RES_MAX
			S.purity = clamp(S.purity - 8, 0, SUBSTANCE_ATTR_MAX)

	if(!ctx)
		return
	// Engineering: energy above the machine's ceiling overdrives into volatility.
	if(ctx.energy_ceiling && S.energy > ctx.energy_ceiling)
		var/overdrive = S.energy - ctx.energy_ceiling
		S.energy = ctx.energy_ceiling
		S.volatility = clamp(S.volatility + round(overdrive / 2), 0, SUBSTANCE_ATTR_MAX)
	// Atmospherics: the ambient reading nudges how cleanly the refine settles.
	if(ctx.volatility_mod)
		S.volatility = clamp(S.volatility + round(ctx.volatility_mod / 3), 0, SUBSTANCE_ATTR_MAX)
