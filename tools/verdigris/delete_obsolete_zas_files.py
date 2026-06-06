"""Delete CHOMP atmos source files that are pure ZAS machinery — they reference
deleted /datum/pipe_network, omni_port, etc. and have LINDA equivalents already
vendored under modular_dq/code/atmospherics/machinery/.

Removes the #include line from vorestation.dme, then deletes the source file.

Idempotent: skips files already absent from the DME or filesystem.
"""
from __future__ import annotations

import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
DME = REPO / "vorestation.dme"

OBSOLETE = [
    # Pipe construction (ZAS pipe_dispenser, RPD)
    "code/game/machinery/pipe/pipe_recipes.dm",
    "code/game/machinery/pipe/pipe_dispenser.dm",
    "code/game/machinery/pipe/pipelayer.dm",
    "code/game/machinery/pipe/construction.dm",
    "code/game/objects/items/weapons/RPD_vr.dm",
    "code/game/objects/items/devices/pipe_painter.dm",
    # Portable & alteration atmos machinery
    "code/game/machinery/atmoalter/portable_atmospherics.dm",
    "code/game/machinery/atmoalter/canister.dm",
    "code/game/machinery/atmoalter/meter.dm",
    "code/game/machinery/atmoalter/pump.dm",
    "code/game/machinery/atmoalter/pump_vr.dm",
    "code/game/machinery/atmoalter/scrubber.dm",
    "code/game/machinery/atmoalter/clamp.dm",
    "code/game/machinery/atmoalter/area_atmos_computer.dm",
    # Atmos consoles
    "code/game/machinery/atmo_control.dm",
    "code/game/machinery/air_alarm.dm",
    "code/game/machinery/airconditioner_vr.dm",
    "code/game/machinery/fire_alarm.dm",
    "code/game/machinery/atm_ret_field.dm",
    "code/game/machinery/spaceheater.dm",
    # Ventcrawl (depends on ZAS pipe network)
    "code/modules/ventcrawl/ventcrawl.dm",
    "code/modules/ventcrawl/ventcrawl_atmospherics.dm",
    "code/modules/ventcrawl/ventcrawl_multiz.dm",
    # TGUI for ZAS atmos
    "code/modules/tgui/modules/shutoff_monitor.dm",
    "code/modules/tgui/modules/supermatter_monitor.dm",
    # ZAS engines (overmap)
    "code/modules/overmap/ships/engines/gas_thruster.dm",
    "code/modules/overmap/ships/engines/gas_thruster_vr.dm",
    # Power machinery with deep ZAS deps
    "code/modules/power/generator.dm",
    "code/modules/power/singularity/collector.dm",
    "code/modules/power/fusion/core/core_field.dm",
    "code/modules/power/turbine.dm",
    "code/modules/power/supermatter/setup_supermatter.dm",
    # Circuit boards for ZAS atmos machinery
    "code/game/objects/items/weapons/circuitboards/machinery/unary_atmos.dm",
    "code/game/objects/items/weapons/circuitboards/circuitboards_vr.dm",
    # Refinery/distillery (use XGM gas table reactions)
    "code/modules/refinery/core/industrial_reagent_reactor.dm",
    "code/modules/reagents/machinery/distillery.dm",
    # Admin atmos diagnostic verbs
    "code/modules/admin/verbs/atmosdebug.dm",
    "code/modules/admin/verbs/diagnostics.dm",
    # Bomb tester
    "code/game/machinery/bomb_tester_vr.dm",
    # Gas thrower
    "code/modules/projectiles/guns/magnetic/gasthrower.dm",
    # shelters_vr and shelters_ch were initially in this list (they pre-fill shelter
    # air via XGM); restored because they ALSO define /datum/map_template/shelter
    # subtypes that overmap ships subtype heavily. Will need per-site hand-fix of
    # the atmos-fill code instead of file-level deletion.
    # ZAS supply
    "code/datums/supplypacks/atmospherics.dm",
    # Map common (atmos-specific common turfs)
    "code/modules/events/supply_demand_vr.dm",  # Uses GLOB.gas_data heavily
]


def main() -> int:
    text = DME.read_text(encoding="utf-8")
    removed_includes = 0
    deleted_files = 0
    missing = 0

    for rel in OBSOLETE:
        # Normalize separators to backslashes for DME include lines.
        dme_rel = rel.replace("/", "\\")
        include_line = f'#include "{dme_rel}"\n'
        if include_line in text:
            text = text.replace(include_line, "", 1)
            removed_includes += 1

        path = REPO / rel
        if path.exists():
            path.unlink()
            deleted_files += 1
        else:
            missing += 1

    DME.write_text(text, encoding="utf-8", newline="")
    print(
        f"removed {removed_includes} includes, deleted {deleted_files} files, "
        f"{missing} not present (idempotent ok)",
        file=sys.stderr,
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
