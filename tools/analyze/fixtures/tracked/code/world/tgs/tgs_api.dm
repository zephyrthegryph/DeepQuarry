// Exempt path: the vendored tgstation-server DMAPI is kept verbatim.
TRACKED(/datum/tgs, tgs_declared)

/datum/tgs/proc/tgs_writes(obj/machinery/pump/P)
	tgs_declared = 1
	P.open = 1
