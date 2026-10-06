// File for modifier defines that don't fit anywhere else. Since this is a misc file, it's doomed to get filled with everything like all the others.


/*
	Berserk is a modifier that grants vastly increased melee capability for a short period of time, easily allowing the
holder to do more than twice the damage they would normally do, as it both increases outgoing melee damage, and
reduces their attack delay. The screen will also turn deep red and the holder will get larger in size.

The modifier also gives some defenses, in that it gives additional max health (this can bite them in the ass later since
its not permanent), makes them move slightly faster, cancels disabling effects when it triggers, and reduces the power of
future disables by a very large amount. It also suppresses pain until it expires, however berserking while under massive pain
is likely to cause them to pass out when exhaustion hits.

Due to the intense rage felt by the holder, the focus needed to use ranged weapons is lost, making accuracy with them
massively reduced. The holder also feels less of a need to evade attacks and will be easier to hit.

Berserk can be extended by having another instance try to affect the holder while in the middle of a berserk.

After the modifier expires, a second modifier representing exhaustion is placed, which inflicts massive maluses and prevents
further berserks until it expires. This generally means that someone getting caught while exhausted will be much easier to fight,
as they will be much slower, attack slower, do less melee damage, be easier to hit, and disabling effects will affect them harder.

Berserking causes the holder to feel hungrier. If they are starving, this modifier cannot be applied. Diona cannot
be berserked, or those who are suffering from exhaustion. Non-Drone Synthetics that receive the berserk modifier will
instead get a version that has no benefits, but will not cost nutrition or cause exhaustion. Drones cannot receive berserk, as
they are emotionless automatrons.

Berserk is a somewhat rare modifier to obtain freely (and for good reason), however here are ways to see it in action;
- Red Slimes will berserk if they go rabid.
- Red slime core reactions will berserk slimes that can see the user in addition to making them go rabid.
- Red slime core reactions will berserk prometheans that can see the user.
- Saviks will berserk when losing a fight.
- Changelings can evolve a 2 point ability to use a changeling-specific variant of Berserk, that replaces the text with a 'we' variant.
Recursive Enhancement allows the changeling to instead used an improved variant that features less exhaustion time and less nutrition drain.
- Xenoarch artifacts may have forced berserking as one of their effects. This is especially fun if an artifact that makes hostile mobs is nearby.
Will cause three brainloss in those affected due to the artifact meddling with their mind.
- A rare alien artifact might be found on the Surface, or obtained from Xenoarch, that causes berserking when it thinks
the wearer is in danger, however in addition to the usual drawbacks, each use causes three brainloss in the user, due to how
the artifact triggers the rage.

*/

/datum/body_effect/berserk
	end_on_death = TRUE
	name = "berserk"
	desc = "You are filled with an overwhelming rage."
	client_color = "#FF5555" // Make everything red!
	mob_overlay_state = "berserk"

	on_created_text = span_critical("You feel an intense and overwhelming rage overtake you as you go berserk!")
	on_expired_text = span_notice("The blaze of rage inside you has ran out.")
	stacks = MODIFIER_STACK_EXTEND

	// The good stuff.
	// Move a bit faster.
	// Attack at 2/3 the normal delay.
	// 50% more damage from melee.
	// More health as a buffer, however the holder might fall into crit after this expires if they're mortally wounded.
	// Disables only last 25% as long.
	// Look scarier.
	// Avoid falling over from shock (at least until it expires).
	// Aiming requires focus.
	// Ditto.
	// Too angry to dodge.
	factors = alist(BF_SLOWDOWN = -1, BF_ACCURACY = -75, BF_DISPERSION = 3, BF_EVASION = -45, BF_ATTACK_SPEED = 0.66, BF_MELEE_DAMAGE = 1.5, BF_DISABLE_DURATION = 0.25, BF_ENDURANCE_MULT = 1.5, BF_ICON_SCALE_X = 1.2, BF_ICON_SCALE_Y = 1.2, BF_PAIN_IMMUNITY = 1)

	// The less good stuff.

	var/nutrition_cost = 150
	var/exhaustion_duration = 2 MINUTES 	// How long the exhaustion effect lasts after it expires. Set to 0 to not apply one.
	// Per-application state: the shock stage suppressed while berserk.


// For changelings.
/datum/body_effect/berserk/changeling
	on_created_text = span_critical("We feel an intense and overwhelming rage overtake us as we go berserk!")
	on_expired_text = span_notice("The blaze of rage inside us has ran out.")

// For changelings who bought the Recursive Enhancement evolution.
/datum/body_effect/berserk/changeling/recursive
	exhaustion_duration = 1 MINUTE
	nutrition_cost = 75


/datum/body_effect/berserk/on_start(mob/living/L)
	if(ishuman(L)) // Most other mobs don't really use nutrition and can't get it back.
		L.adjust_nutrition(-nutrition_cost)
	act_message(L, null, others = span_critical("%U% descends into an all consuming rage!"))

	// End all stuns.
	L.status_set(STAT_PARALYZED, 0)
	L.status_set(STAT_STUNNED, 0)
	L.status_set(STAT_WEAKENED, 0)
	L.mend(TREAT_ANALGESIC, 200) // Rage drowns out the pain.
	L.lying = 0
	L.update_canmove()

	// Temporarily end pain.
	if(ishuman(L))
		var/mob/living/carbon/human/H = L
		L.set_body_effect_state(type, H.shock_stage)
		H.set_shock(0, "berserk")

/datum/body_effect/berserk/on_end(mob/living/L, expired)
	var/last_shock_stage = L.body_effect_state(type) || 0
	if(exhaustion_duration > 0 && L.stat != DEAD)
		L.apply_body_effect(/datum/body_effect/berserk_exhaustion, exhaustion_duration)

		if(prob(last_shock_stage))
			to_chat(L, span_warning("You pass out from the pain you were suppressing."))
			L.status_at_least(STAT_PARALYZED, 5)
			L.status_at_least(STAT_SLEEPING, 5)

		if(ishuman(L))
			var/mob/living/carbon/human/H = L
			H.set_shock(last_shock_stage, "berserk end")

/datum/body_effect/berserk/can_apply(mob/living/L, suppress_failure = FALSE)
	if(L.stat)
		if(!suppress_failure)
			to_chat(L, span_warning("You can't be unconscious or dead to berserk."))
		return FALSE // It would be weird to see a dead body get angry all of a sudden.

	if(!L.is_sentient())
		return FALSE // Drones don't feel anything.

	if(L.has_body_effect(/datum/body_effect/berserk_exhaustion))
		if(!suppress_failure)
			to_chat(L, span_warning("You recently berserked, and cannot do so again while exhausted."))
		return FALSE // On cooldown.

	if(HAS_SYNTHETIC_BIOLOGY(L))
		L.apply_body_effect(/datum/body_effect/berserk_synthetic, 30 SECONDS)
		return FALSE // Borgs can get angry but their metal shell can't be pushed harder by just being mad. Same for Posibrains.

	if(ishuman(L))
		var/mob/living/carbon/human/H = L
		if(H.species?.mood_immune)
			to_chat(L, span_warning("You feel strange for a moment, but it passes."))
			return FALSE // Happy trees aren't affected by blood rages.

	if(L.nutrition < nutrition_cost)
		if(!suppress_failure)
			to_chat(L, span_warning("You are too hungry to berserk."))
		return FALSE // Too hungry to enrage.

	return ..()


// Applied when berserk expires. Acts as a downside as well as the cooldown for berserk.
/datum/body_effect/berserk_exhaustion
	name = "exhaustion"
	desc = "You recently exerted yourself extremely hard, and need a rest."

	on_created_text = span_warning("You feel extremely exhausted.")
	on_expired_text = span_notice("You feel less exhausted now.")
	stacks = MODIFIER_STACK_EXTEND

	factors = alist(BF_SLOWDOWN = 2, BF_EVASION = -30, BF_ATTACK_SPEED = 1.5, BF_MELEE_DAMAGE = 0.6, BF_DISABLE_DURATION = 1.5)

/datum/body_effect/berserk_exhaustion/on_start(mob/living/L)
	act_message(L, null, others = span_warning("%U% looks exhausted."))


// Synth version with no benefits due to a loss of focus inside a metal shell, which can't be pushed harder just be being mad.
// Fortunately there is no exhaustion or nutrition cost.
/datum/body_effect/berserk_synthetic
	name = "recklessness"
	desc = "You are filled with an overwhelming rage, however your metal shell prevents taking advantage of this."
	client_color = "#FF0000" // Make everything red!
	mob_overlay_state = "berserk"

	on_created_text = span_danger("You feel an intense and overwhelming rage overtake you as you go berserk! \
	Unfortunately, your lifeless body cannot benefit from this. You feel reckless...")
	on_expired_text = span_notice("The blaze of rage inside your mind has ran out.")
	stacks = MODIFIER_STACK_EXTEND

	// Just being mad isn't gonna overclock your body when you're a beepboop.
	// Aiming requires focus.
	// Ditto.
	// Too angry to dodge.
	factors = alist(BF_ACCURACY = -75, BF_DISPERSION = 3, BF_EVASION = -45)

// Speedy, but not hasted.
/datum/body_effect/sprinting
	name = "sprinting"
	desc = "You are filled with energy!"

	on_created_text = span_warning("You feel a surge of energy!")
	on_expired_text = span_notice("The energy high dies out.")
	stacks = MODIFIER_STACK_EXTEND

	factors = alist(BF_SLOWDOWN = -1, BF_DISABLE_DURATION = 0.8)

// Speedy, but not berserked.
/datum/body_effect/melee_surge
	name = "melee surge"
	desc = "You are filled with energy!"

	on_created_text = span_warning("You feel a surge of energy!")
	on_expired_text = span_notice("The energy high dies out.")
	stacks = MODIFIER_STACK_ALLOWED

	factors = alist(BF_ATTACK_SPEED = 0.8, BF_MELEE_DAMAGE = 1.1, BF_DISABLE_DURATION = 0.8)

// Non-cult version of deep wounds.
// Surprisingly, more dangerous.
/datum/body_effect/grievous_wounds
	name = "grievous wounds"
	desc = "Your wounds are not easily mended."

	on_created_text = span_critical("Your wounds pain you greatly.")
	on_expired_text = span_notice("The pain lulls.")

	stacks = MODIFIER_STACK_EXTEND

	// 50% less healing.
	// 22% longer disables.
	// 20% more bleeding.
	// A combination of fear and immense pain or damage reults in a twitching firing arm. Flee.
	factors = alist(BF_BLEEDING = 1.20, BF_DISPERSION = 2, BF_DISABLE_DURATION = 1.22, BF_HEALING_RECEIVED = 0.50)


// Applied when near something very cold.
// Reduces mobility, attack speed.
/datum/body_effect/chilled
	name = "chilled"
	desc = "You feel yourself freezing up. Its hard to move."
	mob_overlay_state = "chilled"

	on_created_text = span_danger("You feel like you're going to freeze! It's hard to move.")
	on_expired_text = span_warning("You feel somewhat warmer and more mobile now.")
	stacks = MODIFIER_STACK_EXTEND

	factors = alist(BF_SLOWDOWN = 2, BF_EVASION = -40, BF_ATTACK_SPEED = 1.4, BF_DISABLE_DURATION = 1.2)


// Similar to being on fire, except poison tends to be more long term.
// Antitoxins will remove stacks over time.
// Synthetics can't receive this.
// Pulse modifier.
/datum/body_effect/false_pulse
	name = "false pulse"
	desc = "Your blood flows, despite all other factors."

	on_created_text = span_notice("You feel alive.")
	on_expired_text = span_notice("You feel.. different.")
	stacks = MODIFIER_STACK_EXTEND

	factors = alist(BF_PULSE_SET = PULSE_NORM)

/datum/body_effect/slow_pulse
	name = "slow pulse"
	desc = "Your blood flows slower."

	on_created_text = span_notice("You feel sluggish.")
	on_expired_text = span_notice("You feel energized.")
	stacks = MODIFIER_STACK_EXTEND

	factors = alist(BF_BLEEDING = 0.8, BF_PULSE_SHIFT = -1)


// Temperature Normalizer.
/datum/body_effect/homeothermic
	tick_interval = 2 SECONDS
	name = "temperature resistance"
	desc = "Your body normalizes to room temperature."

	on_created_text = span_notice("You feel comfortable.")
	on_expired_text = span_notice("You feel.. still probably comfortable.")
	stacks = MODIFIER_STACK_EXTEND

/datum/body_effect/homeothermic/on_tick(mob/living/L)
	..()
	L.set_bodytemperature(round((L.body_temperature() + T20C) / 2))

/datum/body_effect/exothermic
	tick_interval = 2 SECONDS
	name = "heat resistance"
	desc = "Your body lowers to room temperature."

	on_created_text = span_notice("You feel comfortable.")
	on_expired_text = span_notice("You feel.. still probably comfortable.")
	stacks = MODIFIER_STACK_EXTEND

/datum/body_effect/exothermic/on_tick(mob/living/L)
	..()
	if(L.body_temperature() > T20C)
		L.set_bodytemperature(round((L.body_temperature() + T20C) / 2))

/datum/body_effect/endothermic
	tick_interval = 2 SECONDS
	name = "cold resistance"
	desc = "Your body rises to room temperature."

	on_created_text = span_notice("You feel comfortable.")
	on_expired_text = span_notice("You feel.. still probably comfortable.")
	stacks = MODIFIER_STACK_EXTEND

/datum/body_effect/endothermic/on_tick(mob/living/L)
	..()
	if(L.body_temperature() < T20C)
		L.set_bodytemperature(round((L.body_temperature() + T20C) / 2))

// Nullifies EMP.
/datum/body_effect/faraday
	name = "EMP shielding"
	desc = "You are covered in some form of faraday shielding. EMPs have no effect."
	mob_overlay_state = "electricity"

	on_created_text = span_notice("You feel a surge of energy, that fades to a calm tide.")
	on_expired_text = span_warning("You feel a longing for the flow of energy.")
	stacks = MODIFIER_STACK_EXTEND

	factors = alist(BF_EMP_SHIFT = 5)

// Nullifies explosions.
/datum/body_effect/blastshield
	name = "Blast Shielding"
	desc = "You are protected from explosions somehow."
	mob_overlay_state = "electricity"

	on_created_text = span_notice("You feel a surge of energy, that fades to a stalwart hum.")
	on_expired_text = span_warning("You feel a longing for the flow of energy.")
	stacks = MODIFIER_STACK_EXTEND

	factors = alist(BF_EXPLOSION_SHIFT = 3)

// Kills on expiration.
/datum/body_effect/doomed
	name = "Doomed"
	desc = "You are doomed."

	on_created_text = span_notice("You feel an overwhelming sense of dread.")
	on_expired_text = span_warning("You feel the life drain from your body.")
	stacks = MODIFIER_STACK_EXTEND

/// Only running out kills: curing or removing the doom (curea) lifts it.
/datum/body_effect/doomed/on_end(mob/living/L, expired)
	if(expired && L.stat != DEAD)
		act_message(L, null, others = span_alien("%U% collapses, the life draining from their body."))
		L.death()

/datum/body_effect/outline_test
	stacks = MODIFIER_STACK_FORBID
	tick_interval = 2 SECONDS
	name = "Outline Test"
	desc = "This only exists to prove filter effects work and gives an example of how to animate() the resulting filter object."

	filter_parameters = list(type = "outline", size = 1, color = "#FFFFFF", flags = OUTLINE_SHARP)

/datum/body_effect/outline_test/on_tick(mob/living/L)
	animate(L.body_effect_filter(type), size = 3, time = 0.25 SECONDS)
	animate(size = 1, 0.25 SECONDS)


// Acts as a psuedo-godmode, yet probably is more reliable than the actual var for it nowdays.
// Can't protect from instantly killing things like singulos.
/datum/body_effect/invulnerable
	name = "invulnerable"
	desc = "You are almost immune to harm, for a little while at least."
	stacks = MODIFIER_STACK_EXTEND

	factors = alist(BF_INCOMING_ALL = 0, BF_DISABLE_DURATION = 0, BF_PAIN_IMMUNITY = 1, BF_ARMOR(INJURY_BLUNT) = 2000, BF_ARMOR(INJURY_CUT) = 2000, BF_ARMOR(INJURY_PIERCE) = 2000, BF_ARMOR(INJURY_BURN) = 2000, BF_ARMOR(INJURY_CORROSIVE) = 2000, BF_ARMOR(INJURY_ELECTRIC) = 2000, BF_ARMOR(INJURY_TOXIN) = 2000, BF_ARMOR(INJURY_RADIATION) = 2000, BF_ARMOR(INJURY_PAIN) = 2000, BF_ARMOR(ARMOR_BLAST) = 2000, BF_HEAT_EXPOSURE = 0, BF_COLD_EXPOSURE = 0, BF_SIEMENS = 0.0)

// Reduces resistance to "elements".
// Note that most things that do give resistance gives 100% protection,
// and due to multiplicitive stacking, this modifier won't do anything to change that.
/datum/body_effect/elemental_vulnerability
	name = "elemental vulnerability"
	desc = "You're more vulnerable to extreme temperatures and electricity."
	stacks = MODIFIER_STACK_EXTEND

	factors = alist(BF_HEAT_EXPOSURE = 1.5, BF_COLD_EXPOSURE = 1.5, BF_SIEMENS = 1.5)

/datum/body_effect/entangled
	name = "entangled"
	desc = "Its hard to move."

	on_created_text = span_danger("You're caught in something! It's hard to move.")
	on_expired_text = span_warning("Your movement is freed.")
	stacks = MODIFIER_STACK_EXTEND

	factors = alist(BF_SLOWDOWN = 2)

/datum/body_effect/trait/thickdigits
	name = "Thick Digits"
	desc = "Your hands cannot properly wield weapons."

/datum/body_effect/trait/empresist
	name = "Emp Resist"
	desc = "You are resistant to EMPs."

/datum/body_effect/trait/empresistb
	name = "Major Emp Resist"
	desc = "You are resistant to EMPs."

/datum/body_effect/trait/empweakness
	name = "Emp Weakness"
	desc = "You are weak to EMPs."

/datum/body_effect/trait/majorempweakness
	name = "Major Emp Weakness"
	desc = "You are weak to EMPs."

/datum/body_effect/rednet //Not used here currently, but used downstream. Todo: Port it.
	stacks = MODIFIER_STACK_FORBID
	mob_overlay_state = "red_electricity_constant"
	factors = alist(BF_SLOWDOWN = 1)
