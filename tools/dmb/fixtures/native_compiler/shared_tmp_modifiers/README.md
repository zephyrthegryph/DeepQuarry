# Shared `tmp` declaration flags

`probe.native.bin` is the compile-only DreamMaker 516.1687 output for the
adjacent manifest and source. `capture.json` records the compiler, source and
output hashes. No runtime was started.

The class declaration retains the `tmp` bit: instance, static and constant
fields have flags 4, 5 and 7 respectively. The shared variable footer strips
that bit: ordinary shared slots have flag 1, constant slots flag 3. This also
holds for root globals and procedure-local static variables.

The native writer must apply this distinction at footer emission, preserving
the class declaration flags. The Rust fixture compares both wire domains with
this independent captured output.
