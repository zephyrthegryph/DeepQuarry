// Stamina / tiredness — a combat-exertion pool, separate from halloss (pain) and the
// `tiredness` vore var. Swinging, blocking, and running drain it; it regenerates when you
// disengage (faster resting/sleeping). Emptying it collapses you (a knockdown) until you
// recover. All drains funnel through adjust_stamina(), so the collapse rule lives in one place.
//
// This is a player/human mechanic: the vars sit on /mob/living, but only the human Life loop,
// human movement, and the player melee path touch them. NPCs use a separate attack path and so
// never tire.

/mob/living
	/// Current stamina. Drained by exertion, regenerated when idle. 0 collapses the mob.
	var/stamina = MAX_STAMINA
	/// Stamina ceiling. Flat per-mob; a species/trait override is a future hook.
	var/max_stamina = MAX_STAMINA
	/// world.time of the last drain — regen stays paused until STAMINA_REGEN_DELAY past it.
	var/stamina_use_time = 0
	/// TRUE between a collapse and recovering past STAMINA_RECOVER_THRESHOLD (blocks re-collapse).
	var/stamina_collapsed = FALSE
	/// The HUD bar (clientless/NPC mobs leave it null and skip all display work).
	var/atom/movable/screen/stamina/stamina_meter

/// Add (or, with a negative amount, spend) stamina. The single choke-point for the pool:
/// clamps to range, gates regen by stamping the use time on a drain, triggers the collapse at
/// zero, lifts the collapse lock on recovery, and refreshes the meter.
/mob/living/proc/adjust_stamina(amount)
	if(!amount)
		return
	if(amount < 0)
		stamina_use_time = world.time
		amount *= perk_mult(DQ_PERK_FX_STAMINA_DRAIN) // Conditioned: exertion drains you less.
	stamina = clamp(stamina + amount, 0, max_stamina)
	if(stamina <= 0 && !stamina_collapsed)
		stamina_collapse()
	else if(stamina >= STAMINA_RECOVER_THRESHOLD)
		stamina_collapsed = FALSE
	update_stamina_meter()

/// Stamina hit zero: knock the mob down, lock out its next swing, and leave it with a sliver of
/// stamina so it comes round able to crawl away rather than instantly re-collapsing.
/mob/living/proc/stamina_collapse()
	stamina = STAMINA_COLLAPSE_FLOOR
	stamina_collapsed = TRUE
	Weaken(STAMINA_COLLAPSE_WEAKEN)
	Stun(2)
	melee_locked_until = max(melee_locked_until, world.time + DQ_BLOCK_WHIFF_LOCK)
	playsound(src, 'sound/effects/bodyfall1.ogg', 50, 1, -1)
	visible_message(span_danger("\The [src] collapses, exhausted!"), span_danger("You collapse, too exhausted to keep going!"))

/// Per-Life-tick regen. No-op until the idle delay since the last drain has elapsed; rate rises
/// with rest. Call from the human Life status pass.
/mob/living/proc/handle_stamina_regen()
	if(stamina >= max_stamina)
		return
	if(world.time < stamina_use_time + STAMINA_REGEN_DELAY)
		return
	var/regen = STAMINA_REGEN_AWAKE
	if(sleeping)
		regen = STAMINA_REGEN_SLEEPING
	else if(resting)
		regen = STAMINA_REGEN_RESTING
	regen *= perk_mult(DQ_PERK_FX_STAMINA_REGEN) // Second Breath: recover faster once clear of the fight.
	stamina = min(stamina + regen, max_stamina)
	update_stamina_meter()

/// Redraw the HUD bar to the current ratio. Cheap and guarded — does nothing without a meter.
/mob/living/proc/update_stamina_meter()
	if(stamina_meter)
		stamina_meter.update(max_stamina ? stamina / max_stamina : 0)

// ---------------------------------------------------------------------------
// HUD bar — a runtime-drawn two-tone meter (no .dmi art dependency). The source HUD style is
// stashed at creation so the bar can be rebuilt each update.
// ---------------------------------------------------------------------------

/atom/movable/screen/stamina
	name = "stamina"
	icon_state = ""
	/// The HUD style dmi, kept as a 32x32 canvas source for DrawBox.
	var/icon/style

/atom/movable/screen/stamina/proc/update(ratio)
	if(!style)
		return
	ratio = clamp(ratio, 0, 1)
	var/icon/bar = new(style, "black")
	bar.MapColors(0,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,0, -1,-1,-1,-1) // blank the canvas to transparent
	bar.DrawBox(rgb(35, 35, 35), 2, 13, 31, 19)                    // track
	var/fill_w = clamp(round(29 * ratio), ratio > 0 ? 1 : 0, 29)
	if(fill_w)
		var/fill = ratio > 0.5 ? rgb(76, 175, 80) : (ratio > 0.25 ? rgb(255, 179, 0) : rgb(229, 57, 53))
		bar.DrawBox(fill, 2, 13, 1 + fill_w, 19)
	icon = bar
