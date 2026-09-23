/obj/machinery/atmospherics/pipe/Initialize(mapload) //This is needed or else 20+ lines of copypasta to dance around inheritence.
	. = ..()
	description_info += "<br>Most pipes and atmospheric devices can be connected or disconnected with a wrench.  The pipe's pressure must not be too high, \
	or if it is a device, it must be turned off first."

//HE pipes

//Supply/Scrubber pipes

//Universal adapters

//Three way manifolds

//Insulated pipes

//Four way manifolds

//Endcaps

//T-shaped valves

//Normal valves

//TEG ports

//Passive gates

//Normal pumps (high power one inherits from this)

//Vents

//Freezers

//Heaters

//Gas injectors

//Scrubbers

//Omni filters

//Omni mixers

//Canisters
/obj/machinery/portable_atmospherics/canister
	description_antag = "Canisters can be damaged, spilling their contents into the air, or you can just leave the release valve open."

//Portable pumps

//Portable scrubbers

//Meters

//Pipe dispensers
