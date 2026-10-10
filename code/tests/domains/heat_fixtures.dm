// Heat network fixtures (code/modules/unit_tests/dq_heat_net_tests.dm): a plate whose gas is linked to the room while it is on, a pod that links
// its occupant to its gas while they are inside, and a pump and an engine between two gases. Compiled under UNIT_TESTS only.

/obj/machinery/heat_fixture
	var/heat_on = FALSE
	var/datum/gas_mixture/gas
	var/datum/gas_mixture/cold
	var/conductance = 50

TRACKED(/obj/machinery/heat_fixture, heat_on)

/// Two cells of nitrogen it starts with (gas_store()).
/obj/machinery/heat_fixture/declared_capabilities(list/into)
	..()
	into += gas_store(nameof(gas), CELL_VOLUME, T20C, list(GAS_N2 = ONE_ATMOSPHERE))
	into += gas_store(nameof(cold), CELL_VOLUME, T20C, list(GAS_N2 = ONE_ATMOSPHERE))

/// Links its gas to the room's air while on.
/obj/machinery/heat_fixture/plate

CAPABILITIES(/obj/machinery/heat_fixture/plate)
	when(nameof(heat_on), heat_link(nameof(gas), HEAT_AIR, nameof(conductance)))

/// Links its occupant's heat body to its gas while the occupant is in the slot and the pod is on.
/obj/machinery/heat_fixture/pod

CAPABILITIES(/obj/machinery/heat_fixture/pod)
	when(nameof(heat_on), while_slotted("heat_pod", heat_link(HEAT_HOLDER, nameof(gas), nameof(conductance)), on = ON_CONTENTS))

/// Pumps heat out of `cold` into `gas` toward 200 K with 2 kW while on.
/obj/machinery/heat_fixture/chiller

CAPABILITIES(/obj/machinery/heat_fixture/chiller)
	when(nameof(heat_on), heat_pump(nameof(cold), nameof(gas), 2000, 200, mode = HEAT_PUMP_COOL))

/// A heat engine from `gas` (hot) to `cold`.
/obj/machinery/heat_fixture/engine

CAPABILITIES(/obj/machinery/heat_fixture/engine)
	when(nameof(heat_on), heat_engine(nameof(gas), nameof(cold), 0.5, 100))
