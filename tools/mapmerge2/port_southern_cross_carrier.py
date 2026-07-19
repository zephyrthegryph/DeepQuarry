#!/usr/bin/env python3
"""Apply mechanical current-engine field migrations to the archived carrier."""

from pathlib import Path


MAP = Path("maps/southern_cross/southern_cross-7.dmm")


def main():
    source = MAP.read_text(encoding="utf-8")
    source = source.replace("\thealth = ", "\tmax_integrity = ")
    source = source.replace("/obj/machinery/mecha_part_fabricator_tg_tg", "/obj/machinery/mecha_part_fabricator_tg")
    replacements = {
        "/obj/machinery/r_n_d/protolathe": "/obj/machinery/rnd/production/protolathe",
        "/obj/machinery/r_n_d/circuit_imprinter": "/obj/machinery/rnd/production/circuit_imprinter",
        "/obj/machinery/r_n_d/destructive_analyzer": "/obj/machinery/rnd/destructive_analyzer",
        "/obj/machinery/computer/rdconsole/robotics": "/obj/machinery/computer/rdconsole_tg",
        "/obj/machinery/computer/rdconsole/core": "/obj/machinery/computer/rdconsole_tg",
        "/obj/machinery/mecha_part_fabricator/pros": "/obj/machinery/mecha_part_fabricator_tg/prosthetics",
    }
    for old, new in replacements.items():
        source = source.replace(old, new)
    source = source.replace("/obj/machinery/mecha_part_fabricator,", "/obj/machinery/mecha_part_fabricator_tg,")
    source = source.replace("/obj/machinery/mecha_part_fabricator{", "/obj/machinery/mecha_part_fabricator_tg{")
    MAP.write_text(source, encoding="utf-8", newline="\n")


if __name__ == "__main__":
    main()
