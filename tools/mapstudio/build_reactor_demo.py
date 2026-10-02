"""Build a compact, standalone R-UST test room from individual map atoms."""

from collections import defaultdict

from engine import Coordinate, DMM, ROOT, dmm_module, route_atom


OUTPUT = ROOT / "maps/mapstudio_reactor_demo.dmm"
SIZE = Coordinate(27, 21, 1)
SPACE = "/area/space"
ACCESS = "/area/expoutpost/reactoraccess"
CONTROL = "/area/expoutpost/reactorcr"
REACTOR = "/area/expoutpost/reactorroom"
FUEL = "/area/expoutpost/engstorage"
COOLANT = "/area/expoutpost/atmospherics"
WALL = "/turf/simulated/wall/r_lead"
DARK = "/turf/simulated/floor/tiled/dark"
RAISED = "/turf/simulated/floor/tiled/milspec/raised"
REINFORCED = "/turf/simulated/floor/reinforced"
AIRLESS = "/turf/simulated/floor/reinforced/airless"
DELTA = {(0, 1): 1, (0, -1): 2, (1, 0): 4, (-1, 0): 8}
OPPOSITE = {1: 2, 2: 1, 4: 8, 8: 4}


def build():
    result = DMM(2, SIZE)

    def put(x, y, *atoms):
        result.set_tile(Coordinate(x, y, 1), dmm_module.fix_atom_ordering(atoms))

    def add(x, y, atom):
        point = Coordinate(x, y, 1)
        put(x, y, *(result.get_tile(point) + (atom,)))

    def set_turf(x, y, turf, area):
        put(x, y, turf, area)

    def replace(x, y, prefix, replacement):
        current = result.get_tile(Coordinate(x, y, 1))
        put(x, y, *(part for part in current if not part.startswith(prefix)), replacement)

    def atom(x, y, value):
        assert 2 <= x <= 26 and 2 <= y <= 20
        add(x, y, value)

    def door(x, y, name, blast=False, area=ACCESS):
        set_turf(x, y, REINFORCED, area)
        kind = "/obj/machinery/door/blast/radproof" if blast else "/obj/machinery/door/airlock/engineering"
        atom(x, y, f'{kind}{{name = "{name}"}}')

    def route(paths, layer, base):
        directions = defaultdict(set)
        for points in paths:
            for start, end in zip(points, points[1:]):
                dx, dy = end[0] - start[0], end[1] - start[1]
                assert (dx, dy) in DELTA, f"Noncardinal pipe or cable route: {start} to {end}"
                direction = DELTA[(dx, dy)]
                directions[start].add(direction)
                directions[end].add(OPPOSITE[direction])
        for (x, y), ports in directions.items():
            if layer == "power" and len(ports) > 2:
                pairs = []
                remaining = set(ports)
                for opposite in ({1, 2}, {4, 8}):
                    if opposite <= remaining:
                        pairs.append(opposite)
                        remaining -= opposite
                pairs.extend({direction} for direction in sorted(remaining))
                for pair in pairs:
                    atom(x, y, route_atom(base, layer, pair))
            else:
                atom(x, y, route_atom(base, layer, ports))

    def line(*points):
        result = []
        for a, b in zip(points, points[1:]):
            if a[0] == b[0]:
                step = 1 if b[1] > a[1] else -1
                section = [(a[0], y) for y in range(a[1], b[1] + step, step)]
            else:
                assert a[1] == b[1]
                step = 1 if b[0] > a[0] else -1
                section = [(x, a[1]) for x in range(a[0], b[0] + step, step)]
            result.extend(section if not result else section[1:])
        return result

    # One enclosed footprint. Every tile inside the exterior walls has an
    # intentional floor or lead wall; there are no exposed space pockets.
    for y in range(1, 22):
        for x in range(1, 28):
            if x in (1, 27) or y in (1, 21):
                put(x, y, "/turf/space", SPACE)
                continue
            area = (CONTROL if y >= 16 else REACTOR) if 8 <= x <= 20 else FUEL if x <= 7 else COOLANT
            turf = WALL if x in (2, 26) or y in (2, 20) else DARK
            set_turf(x, y, turf, area)

    # Lead partitions define a 13 x 11 reactor chamber and four compact
    # support rooms. Door openings are cut only after every partition exists.
    for y in range(4, 20):
        for x in (7, 21):
            set_turf(x, y, WALL, FUEL if x == 7 else COOLANT)
    for x in range(7, 22):
        set_turf(x, 15, WALL, REACTOR)
    for x in range(2, 8):
        set_turf(x, 15, WALL, FUEL)
    for x in range(21, 27):
        set_turf(x, 15, WALL, COOLANT)
    for x in range(8, 21):
        set_turf(x, 4, WALL, REACTOR)

    door(14, 20, "R-UST Control", area=CONTROL)
    door(14, 15, "Reactor Shield", blast=True, area=REACTOR)
    door(7, 17, "Fuel Preparation", area=FUEL)
    door(21, 17, "Cooling Service", area=COOLANT)
    door(5, 15, "Fuel Store", area=FUEL)
    door(23, 15, "TEG Service", area=COOLANT)
    door(7, 11, "Fuel Injector Access", blast=True, area=REACTOR)
    door(21, 11, "Coolant Access", blast=True, area=REACTOR)

    # The centre is shaped around the fusion field, with clear approach lanes
    # and an orange hazard ring instead of an empty rectangular floor.
    for y in range(5, 15):
        for x in range(8, 21):
            if x in (8, 20) or y == 14:
                continue
            turf = AIRLESS if 12 <= x <= 16 and 7 <= y <= 11 else REINFORCED if 10 <= x <= 18 else DARK
            set_turf(x, y, turf, REACTOR)
    for x, y in ((11, 7), (17, 7), (11, 11), (17, 11)):
        atom(x, y, "/obj/effect/floor_decal/industrial/warning")
    for x in range(12, 17):
        for y in (6, 12):
            atom(x, y, "/obj/effect/floor_decal/industrial/outline/yellow")
    for y in range(7, 12):
        for x in (11, 17):
            atom(x, y, "/obj/effect/floor_decal/industrial/outline/yellow")

    core_tag, fuel_tag, gyro_tag = "Solstice Core", "Solstice Injectors", "Solstice Gyrotron"
    atom(14, 9, f'/obj/machinery/power/fusion_core/mapped{{id_tag = "{core_tag}"}}')
    for x, y, direction in ((10, 9, 4), (18, 9, 8), (14, 5, 1)):
        atom(x, y, f'/obj/machinery/fusion_fuel_injector/mapped{{dir = {direction};id_tag = "{fuel_tag}"}}')
    atom(14, 13, f'/obj/machinery/power/emitter/gyrotron/anchored{{dir = 2;id_tag = "{gyro_tag}"}}')
    atom(12, 9, "/obj/machinery/power/hydromagnetic_trap")
    atom(16, 9, "/obj/machinery/power/hydromagnetic_trap")
    atom(11, 10, '/obj/machinery/atmospherics/unary/outlet_injector{dir = 4;id = "solstice_cooling_in";name = "Core Coolant Injector"}')
    atom(19, 10, '/obj/machinery/atmospherics/unary/vent_pump/engine{dir = 8;id_tag = "solstice_cooling_out";name = "Core Coolant Return"}')
    atom(14, 11, '/obj/machinery/air_sensor{id_tag = "solstice_sensor"}')
    for x, y in ((9, 6), (19, 6), (9, 13), (19, 13)):
        atom(x, y, "/obj/machinery/light/small")
    atom(9, 12, "/obj/structure/sign/signnew/radiation")
    atom(19, 12, "/obj/structure/sign/signnew/radiation")
    atom(9, 13, "/obj/machinery/power/apc")

    # Controls use the same tags as the machinery. The viewing positions are
    # shielded by the chamber's north wall and gated blast door.
    for x in range(10, 19):
        set_turf(x, 17, RAISED, CONTROL)
    for x, machine in ((10, "fusion_core_control"), (12, "fusion_fuel_control"),
                       (14, "gyrotron_control")):
        tag = {"fusion_core_control": core_tag, "fusion_fuel_control": fuel_tag,
               "gyrotron_control": gyro_tag}[machine]
        atom(x, 17, f'/obj/machinery/computer/{machine}{{dir = 1;id_tag = "{tag}"}}')
    atom(17, 17, '/obj/machinery/computer/general_air_control/supermatter_core{dir = 1;input_tag = "solstice_cooling_in";output_tag = "solstice_cooling_out";sensors = list("solstice_sensor"="Core Temperature")}')
    atom(19, 17, "/obj/machinery/computer/security/engineering")
    atom(10, 18, "/obj/item/book/manual/rust_engine")
    atom(18, 18, "/obj/structure/bed/chair/office/light")
    atom(9, 19, "/obj/machinery/power/apc")
    atom(10, 19, "/obj/machinery/alarm")
    atom(18, 19, "/obj/machinery/firealarm")
    for x in (10, 14, 18):
        atom(x, 19, "/obj/machinery/light")

    # West support: fuel compressor, separated rod storage, service tools,
    # and a small SMES closet immediately beside the control room.
    atom(4, 8, "/obj/machinery/fusion_fuel_compressor")
    for x, y, fuel in ((4, 11, "deuterium"), (5, 11, "deuterium"),
                       (4, 12, "tritium")):
        atom(x, y, f"/obj/item/fuel_assembly/{fuel}")
    atom(4, 6, "/obj/structure/closet/radiation")
    atom(5, 6, "/obj/structure/closet/toolcloset")
    atom(5, 9, "/obj/structure/table/rack/shelf/steel")
    atom(3, 13, "/obj/structure/sign/warning/radioactive")
    atom(3, 17, "/obj/machinery/power/smes/buildable/precharged")
    atom(5, 17, "/obj/machinery/power/smes/buildable/charging")
    atom(6, 18, "/obj/machinery/power/apc")
    atom(3, 18, "/obj/machinery/alarm")
    atom(5, 18, "/obj/structure/closet/walllocker/emerglocker")
    for x, y in ((4, 10), (5, 19), (5, 13)):
        atom(x, y, "/obj/machinery/light/small")

    # East support: the TEG is a matched east-west generator with its west
    # circulator facing north and east circulator facing south, as required by
    # generator.reconnect(). All vessels/connectors face an indoor aisle.
    atom(23, 9, '/obj/machinery/power/generator{anchored = 1;dir = 4}')
    atom(22, 9, '/obj/machinery/atmospherics/binary/circulator{anchored = 1;dir = 1}')
    atom(24, 9, '/obj/machinery/atmospherics/binary/circulator{anchored = 1;dir = 2}')
    atom(24, 6, "/obj/machinery/atmospherics/unary/freezer")
    atom(22, 6, "/obj/machinery/atmospherics/portables_connector")
    atom(23, 6, "/obj/machinery/portable_atmospherics/canister/carbon_dioxide")
    atom(25, 12, "/obj/machinery/portable_atmospherics/canister/carbon_dioxide")
    atom(24, 12, "/obj/machinery/atmospherics/pipe/tank/air/full")
    atom(25, 5, "/obj/machinery/pipedispenser")
    atom(25, 13, "/obj/structure/sign/department/atmos")
    atom(22, 18, "/obj/machinery/power/apc")
    atom(24, 18, "/obj/machinery/atmospherics/omni/atmos_filter")
    atom(25, 17, "/obj/machinery/alarm")
    atom(24, 19, "/obj/structure/closet/radiation")
    for x, y in ((23, 13), (23, 7), (23, 19)):
        atom(x, y, "/obj/machinery/light/small")

    # The cables include the core and generator tiles and feed each APC.
    green = "/obj/structure/cable/green"
    route((line((3, 17), (23, 17)), line((14, 17), (14, 9)),
           line((14, 9), (23, 9)), line((23, 17), (23, 9)),
           line((6, 17), (6, 18)), line((9, 17), (9, 19)),
           line((14, 12), (9, 12), (9, 13)), line((22, 17), (22, 18))), "power", green)

    # Two independent house-atmos loops and an indoor coolant loop. Each
    # route closes on itself, so there are no pipes aimed into open space.
    for lane in ("supply", "scrubbers"):
        route((line((9, 6), (19, 6), (19, 12), (9, 12), (9, 6)),), "atmos",
              f"/obj/machinery/atmospherics/pipe/simple/hidden/{lane}")
    route((line((11, 5), (25, 5), (25, 13), (11, 13), (11, 5)),), "atmos",
          "/obj/machinery/atmospherics/pipe/simple/visible/green")
    # Each circulator has a mapped pipe on both its inlet and outlet side.
    # The side branches meet the main coolant loop through real manifolds.
    green_pipe = "/obj/machinery/atmospherics/pipe/simple/visible/green"
    for y, side in ((8, 1), (10, 2)):
        atom(22, y, route_atom(green_pipe, "atmos", {side, 4}))
        atom(23, y, route_atom(green_pipe, "atmos", {4, 8}))
        atom(24, y, f'/obj/machinery/atmospherics/pipe/manifold/visible/green{{dir = {OPPOSITE[side]}}}')
        replace(25, y, green_pipe,
                '/obj/machinery/atmospherics/pipe/manifold/visible/green{dir = 4}')
    atom(9, 6, '/obj/machinery/atmospherics/unary/vent_pump/on{dir = 4}')
    atom(19, 6, '/obj/machinery/atmospherics/unary/vent_scrubber/on{dir = 8}')

    result.to_file(OUTPUT)
    return OUTPUT


if __name__ == "__main__":
    print(build())
