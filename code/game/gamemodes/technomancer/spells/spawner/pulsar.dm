/datum/technomancer/spell/pulsar
	name = "Pulsar"
	desc = "Emits electronic pulses to destroy, disable, or otherwise harm devices and machines.  Be sure to not hit yourself with this."
	cost = 100
	obj_path = /obj/item/spell/spawner/pulsar
	category = OFFENSIVE_SPELLS

/obj/item/spell/spawner/pulsar
	name = "pulsar"
	desc = "Be sure to not hit yourself!"
	icon_state = "radiance"
	cast_methods = CAST_RANGED | CAST_THROW
	aspect = ASPECT_EMP
	spawner_type = /obj/effect/temporary_effect/pulse/pulsar

/obj/item/spell/spawner/pulsar
	light_range = 3
	light_power = 2
	light_color = "#2ECCFA"
	light_on = TRUE

/obj/item/spell/spawner/pulsar/on_ranged_cast(atom/hit_atom, mob/user)
	if(within_range(hit_atom) && pay_energy(4000))
		adjust_instability(8)
		..()

/obj/item/spell/spawner/pulsar/on_throw_cast(atom/hit_atom, mob/user)
	empulse(hit_atom, 1, 1, 1, 1, log=1)

// Does something every so often. Deletes itself when pulses_remaining hits zero.
/obj/effect/temporary_effect/pulse
	var/pulses_remaining = 3
	var/pulse_delay = 2 SECONDS

/// Pulses on the declared every(). A subtype that runs its own loop (the snake) sets it FALSE.
/obj/effect/temporary_effect/pulse/var/pulsing = TRUE
TRACKED(/obj/effect/temporary_effect/pulse, pulsing)

CAPABILITIES(/obj/effect/temporary_effect/pulse)
	after_init(0, then(PROC_REF(first_pulse)))
	every(PROC_REF(pulse_interval), then(PROC_REF(pulse_step)), when = nameof(pulsing))

/// The every() interval: the effect's pulse_delay.
/obj/effect/temporary_effect/pulse/proc/pulse_interval(datum/act/A)
	return pulse_delay

/// The first pulse, as the effect appears.
/obj/effect/temporary_effect/pulse/proc/first_pulse(datum/act/timer/A)
	pulse_loop()

/// The first pulse, at once; the declared repeat runs the rest every pulse_delay.
/obj/effect/temporary_effect/pulse/proc/pulse_loop()
	return pulse_step()

/// every(): one pulse, or the end of the effect once pulses_remaining is spent.
/obj/effect/temporary_effect/pulse/proc/pulse_step(datum/act/timer/A)
	if(pulses_remaining > 0)
		pulses_remaining--
		on_pulse()
		return
	consume(src)

// Override for specific effects.
/obj/effect/temporary_effect/pulse/proc/on_pulse()

/obj/effect/temporary_effect/pulse/pulsar
	name = "pulsar"
	desc = "Not a real pulsar, but still emits loads of EMP."
	icon_state = "shield2"
	time_to_die = null
	light_range = 4
	light_power = 5
	light_color = "#2ECCFA"
	pulses_remaining = 3

/obj/effect/temporary_effect/pulse/pulsar/on_pulse()
	empulse(src, 1, 1, 2, 2, log = 1)
