// Executions — a finisher on an opponent you've already broken down. When a target is
// staggered wide open, knocked down, or held in your grab, a Harm-intent swing becomes a
// cinematic execution instead of a normal hit: a big, committed blow with flavour that
// varies by weapon. It's the payoff for the read-and-react loop — parry to break poise,
// or wound a leg to drop them, then finish.

GLOBAL_LIST_INIT(dq_executions_sharp, list(
	"drives the blade clean through",
	"opens the throat of",
	"runs the edge across the neck of",
	"impales and twists into",
	"carves a deep gash across",
))
GLOBAL_LIST_INIT(dq_executions_blunt, list(
	"caves in the skull of",
	"brings the weapon down on the head of",
	"crushes the ribs of",
	"smashes the legs out from under",
	"hammers down onto",
))
GLOBAL_LIST_INIT(dq_executions_unarmed, list(
	"snaps the neck of",
	"stomps down hard on",
	"drives a knee into the throat of",
	"wrenches the head of",
	"pummels the downed",
))

/// TRUE when `victim` is broken down enough for `src` to execute it: staggered open, on the
/// ground, or held in our grab — and we're adjacent and alive to do it. Executions only land
/// on simple mobs (fauna); players are never executable.
/mob/living/proc/can_execute(mob/living/victim)
	if(!istype(victim) || victim == src || victim.stat >= DEAD)
		return FALSE
	if(!istype(victim, /mob/living/simple_mob) || victim.client)
		return FALSE // fauna only — never a player (incl. a player piloting a simple mob)
	if(incapacitated() || !Adjacent(victim))
		return FALSE
	if(victim.is_stagger_broken() || victim.lying || victim.weakened)
		return TRUE
	// Or we have a grip on them.
	for(var/obj/item/grab/G in victim.grabbed_by)
		if(G.assailant == src)
			return TRUE
	return FALSE

/// Perform an execution on `victim` with `weapon` (null = unarmed). A heavy, flavoured blow:
/// kills most fauna outright, badly hurts a tougher target. Single-tick, committed.
/mob/living/proc/perform_execution(mob/living/victim, obj/item/weapon)
	if(is_swinging || !can_execute(victim))
		return FALSE
	is_swinging = TRUE
	face_atom(victim)
	adjust_stamina(-round(STAMINA_COST_SWING * 1.5))

	var/sharp = istype(weapon) && weapon.sharp
	// Method-specific cinematic flair (lunge + hit-stop, victim reaction, shake, blood/none) before
	// the blow lands. Started while the victim's still standing so its reaction reads on a survivor;
	// on a lethal hit the attacker lunge, shake, blood and sound still carry the method's identity.
	dq_execution_flourish(victim, weapon, sharp)
	var/list/flavors = weapon ? (sharp ? GLOB.dq_executions_sharp : GLOB.dq_executions_blunt) : GLOB.dq_executions_unarmed
	var/phrase = pick(flavors)

	// A finisher against fauna: 75% of max HP ends most outright. (Players can't be executed —
	// can_execute gates to non-client simple mobs only.)
	var/dmg = max(round(victim.getMaxHealth() * 0.75), istype(weapon) ? round(weapon.force * 3) : 25)
	if(has_perk(/datum/perk/body/str_juggernaut)) // Juggernaut: brutal finishers bite through tanky fauna.
		dmg = round(dmg * 1.3)
	var/dtype = (istype(weapon) && weapon.damtype) ? weapon.damtype : BRUTE
	dqai_pdbg(src, "EXECUTE", "[weapon ? "[weapon]" : "unarmed"] finisher on [victim] for [dmg] [dtype] (victim hp [round(victim.health)]/[victim.getMaxHealth()])", victim)
	victim.apply_damage(damage = dmg, damagetype = dtype, def_zone = null, sharp = sharp, edge = sharp, used_weapon = weapon)

	victim.visible_message(span_danger("\The [src] [phrase] \the [victim]!"), span_danger("\The [src] [phrase] you!"))
	if(sharp)
		playsound(victim, pick('sound/effects/wounds/pierce1.ogg', 'sound/effects/wounds/pierce2.ogg', 'sound/effects/wounds/splatter.ogg'), 60, 1, -1)
	else
		playsound(victim, pick('sound/effects/bonebreak1.ogg', 'sound/effects/bonebreak2.ogg', 'sound/effects/meatslap.ogg'), 60, 1, -1)

	// Recovery — an execution is a heavy commitment (Juggernaut shortens it to chain finishers).
	var/exec_recovery = weapon ? max(4, weapon.get_melee_recovery() * 2) : 8
	if(has_perk(/datum/perk/body/str_juggernaut))
		exec_recovery = round(exec_recovery * DQ_PERK_EXECUTION_SPEED_MULT)
	setClickCooldown(exec_recovery)
	combo_until = 0
	is_swinging = FALSE
	return TRUE

// ---------------------------------------------------------------------------
// Visual flair. All of this is purely cosmetic and non-blocking; it degrades gracefully if the
// victim dies/gibs mid-animation (the attacker lunge, camera shake, blood and sound survive).
// Three distinct reads keyed off the same sharp/blunt/unarmed split as the flavour text:
//   sharp  — THE CUT:   fast deep thrust, red rim, a real blood spray, a light snap of the camera.
//   blunt  — THE CRUSH: a heavy drop with a long hit-stop, white rim, a vertical squash, hard shake.
//   unarmed — THE SNAP: a double-jab flurry, a wrenching twist of the body, a medium shake.
// ---------------------------------------------------------------------------

/// A weighty attacker lunge toward `target` with a hit-stop hold, then a recoil — heavier and
/// slower to recover than do_attack_animation. `double` adds a second jab (the bare-handed flurry).
/// Restores our own pixel offset so it composes with vore/size icon shifts.
/mob/living/proc/dq_execution_lunge(atom/target, magnitude = 8, hold = 1, double = FALSE)
	var/d = get_dir(src, target)
	var/dx = 0
	var/dy = 0
	if(d & NORTH)
		dy = magnitude
	else if(d & SOUTH)
		dy = -magnitude
	if(d & EAST)
		dx = magnitude
	else if(d & WEST)
		dx = -magnitude
	var/ox = pixel_x
	var/oy = pixel_y
	animate(src, pixel_x = ox + dx, pixel_y = oy + dy, time = 1, easing = QUAD_EASING | EASE_OUT)
	if(double)
		animate(pixel_x = ox + round(dx * 0.4), pixel_y = oy + round(dy * 0.4), time = 1)
		animate(pixel_x = ox + dx, pixel_y = oy + dy, time = 1)
	animate(pixel_x = ox + dx, pixel_y = oy + dy, time = hold) // hit-stop hold
	animate(pixel_x = ox, pixel_y = oy, time = 3, easing = QUAD_EASING | EASE_IN)

/// Play the method-specific execution flourish. `src` is the executioner, `victim` the target.
/mob/living/proc/dq_execution_flourish(mob/living/victim, obj/item/weapon, sharp)
	if(QDELETED(victim))
		return
	var/turf/T = get_turf(victim)
	var/old_color = victim.color
	var/matrix/base = victim.transform
	if(sharp)
		dq_execution_lunge(victim, 11, 1)
		shake_camera(src, 3, 0.4)
		victim.add_filter("dq_exec_rim", 60, list("type" = "outline", "size" = 2, "color" = "#e02020a0"))
		animate(victim, color = "#ff6666", time = 1)
		animate(color = old_color, time = 3)
		if(T)
			blood_splatter(T, null, TRUE) // generic spray; null source avoids per-hit blood-source logging
	else if(weapon)
		dq_execution_lunge(victim, 8, 3) // heavy drop + a long hit-stop
		shake_camera(src, 6, 1.1)
		victim.add_filter("dq_exec_rim", 60, list("type" = "outline", "size" = 3, "color" = "#ffffffb0"))
		var/matrix/squash = matrix(base)
		squash.Scale(1.25, 0.7) // a vertical crush
		animate(victim, color = "#ffffff", transform = squash, time = 1)
		animate(color = old_color, transform = base, time = 4)
	else
		dq_execution_lunge(victim, 6, 2, double = TRUE) // a bare-handed flurry
		shake_camera(src, 4, 0.7)
		victim.add_filter("dq_exec_rim", 60, list("type" = "outline", "size" = 2, "color" = "#cccccc90"))
		var/matrix/twist = matrix(base)
		twist.Turn(20) // a wrenching snap
		animate(victim, color = "#ffcccc", transform = twist, time = 1)
		animate(color = old_color, transform = base, time = 3)
	addtimer(CALLBACK(victim, TYPE_PROC_REF(/datum, remove_filter), "dq_exec_rim"), 0.4 SECONDS)
