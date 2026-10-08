// Relays don't handle any actual communication. Global NTNet datum does that, relays only tell the datum if it should or shouldn't work.
/obj/machinery/ntnet_relay
	name = "NTNet Quantum Relay"
	desc = "A very complex router and transmitter capable of connecting electronic devices together. Looks fragile."
	use_power = USE_POWER_ACTIVE
	active_power_usage = 20000 //20kW, apropriate for machine that keeps massive cross-Zlevel wireless network operational.
	idle_power_usage = 100
	icon_state = "ntnet"
	anchored = TRUE
	density = TRUE
	circuit = /obj/item/circuitboard/ntnet_relay
	var/tmp/datum/ntnet/NTNet_static	// This is mostly for backwards reference and to allow varedit modifications from ingame.
	var/enabled = 1				// Set to 0 if the relay was turned off
	var/dos_failure = 0			// Set to 1 if the relay failed due to (D)DoS attack
	var/list/dos_sources	// DoS programs attacking us (a relation list)

	// Denial of Service attack variables
	var/dos_overload = 0		// Amount of DoS "packets" in this relay's buffer
	var/dos_capacity = 500		// Amount of DoS "packets" in buffer required to crash the relay
	var/dos_dissipate = 1		// Amount of DoS "packets" dissipated over time.

	var/datum/looping_sound/tcomms/soundloop
	var/noisy = TRUE

CAPABILITIES(/obj/machinery/ntnet_relay)
	started_work(step = PROC_REF(work_step), starts = PROC_REF(step_start_condition))
	owns_one(nameof(soundloop), /datum/looping_sound/tcomms)
	interface("NTNetRelay")
	without("ui_open")
	op("restart", ui_act("restart"), then(PROC_REF(ui_act_restart)))
	op("toggle", ui_act("toggle"), then(PROC_REF(ui_act_toggle)))
	op("purge", ui_act("purge"), then(PROC_REF(ui_act_purge)))

// TODO: Implement more logic here. For now it's only a placeholder.
/obj/machinery/ntnet_relay/operable(additional_flags = 0)
	if(!..())
		return 0
	if(dos_failure)
		return 0
	if(!enabled)
		return 0
	return 1

TRACKED(/obj/machinery/ntnet_relay, enabled)
TRACKED(/obj/machinery/ntnet_relay, dos_failure)

/obj/machinery/ntnet_relay/draw(datum/look/look)
	..()
	if(operable())
		look.state(initial(icon_state))
	else
		look.state("[initial(icon_state)]_off")
	look.effect(PROC_REF(look_effect_noise), operable())

/// The relay hums while it works: its sound loop follows the look, outside the draw.
/obj/machinery/ntnet_relay/proc/look_effect_noise(working)
	if(working)
		if(!noisy)
			soundloop.start()
			noisy = TRUE
	else
		soundloop.stop()
		noisy = FALSE

/obj/machinery/ntnet_relay/proc/work_step(datum/act/timer/A)
	if(operable())
		set_use_power(USE_POWER_ACTIVE)
	else
		set_use_power(USE_POWER_IDLE)

	if(dos_overload)
		dos_overload = max(0, dos_overload - dos_dissipate)

	// If DoS traffic exceeded capacity, crash.
	if((dos_overload > dos_capacity) && !dos_failure)
		set_dos_failure(1)
		GLOB.ntnet_global.add_log("Quantum relay switched from normal operation mode to overload recovery mode.")
	// If the DoS buffer reaches 0 again, restart.
	if((dos_overload == 0) && dos_failure)
		set_dos_failure(0)
		GLOB.ntnet_global.add_log("Quantum relay switched from overload recovery mode to normal operation mode.")

/obj/machinery/ntnet_relay/ui_data(datum/act/eval/A)
	var/list/data = list()
	data["enabled"] = enabled
	data["dos_capacity"] = dos_capacity
	data["dos_overload"] = dos_overload
	data["dos_crashed"] = dos_failure
	return data

/obj/machinery/ntnet_relay/proc/ui_act_restart(datum/act/op/A)
	dos_overload = 0
	set_dos_failure(0)
	GLOB.ntnet_global.add_log("Quantum relay manually restarted from overload recovery mode to normal operation mode.")
	. = TRUE

/obj/machinery/ntnet_relay/proc/ui_act_toggle(datum/act/op/A)
	set_enabled(!enabled)
	GLOB.ntnet_global.add_log("Quantum relay manually [enabled ? "enabled" : "disabled"].")
	. = TRUE

/obj/machinery/ntnet_relay/proc/ui_act_purge(datum/act/op/A)
	LAZYCLEARLIST(GLOB.ntnet_global.banned_nids)
	GLOB.ntnet_global.add_log("Manual override: Network blacklist cleared.")
	. = TRUE

/obj/machinery/ntnet_relay/Initialize(mapload)
	. = ..()
	assign_uid()
	default_apply_parts()
	if(GLOB.ntnet_global)
		rel_add(GLOB.ntnet_global, nameof(/datum/ntnet::relays), src)
		NTNet_static = GLOB.ntnet_global // a registered singleton: shared
		GLOB.ntnet_global.add_log("New quantum relay activated. Current amount of linked relays: [length(NTNet().relays)]")
	rel_set(src, nameof(soundloop), new /datum/looping_sound/tcomms(list(src), FALSE))
	if(prob(60)) // 60% chance to change the midloop
		if(prob(40))
			soundloop.mid_sounds = list('sound/machines/tcomms/tcomms_02.ogg' = 1)
			soundloop.mid_length = 40
		else if(prob(20))
			soundloop.mid_sounds = list('sound/machines/tcomms/tcomms_03.ogg' = 1)
			soundloop.mid_length = 10
		else
			soundloop.mid_sounds = list('sound/machines/tcomms/tcomms_04.ogg' = 1)
			soundloop.mid_length = 30
	soundloop.start() // Have to do this here bc it starts on

// NTNet (a registered singleton) lists us in its relays relation list; attacking DoS programs
// list themselves in our dos_sources relation list. Both leave on their own when either end dies.

// NTNet logs the lost relay and DoS programs report it.
/obj/machinery/ntnet_relay/on_destroy(force)
	if(NTNet())
		NTNet().add_log("Quantum relay connection severed. Current amount of linked relays: [length(NTNet().relays) - (src in NTNet().relays ? 1 : 0)]")
	for(var/datum/computer_file/program/ntnet_dos/D in dos_sources)
		D.error = "Connection to quantum relay severed"
	..()

/obj/machinery/ntnet_relay
	maintenance_flags = MACHINE_MAINT_STANDARD

/// Whether its work starts at initialization (started_work(starts =)).
/obj/machinery/ntnet_relay/step_start_condition()
	return TRUE // sets its power draw

/// A shared (registered) definition/flyweight: never cleared.
/obj/machinery/ntnet_relay/proc/NTNet() as /datum/ntnet
	return NTNet_static
