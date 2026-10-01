# Native lazy pick parity

`probe.native.bin` is a fresh DreamMaker516.1687 compile of `probe.dme` with no reused output archive. `probe.json` is actual patched OpenDream output.

The integration test checks22 complete procedure bodies against native output in both debug modes. Cases cover ordinary calls, short-circuit and conditional values, safe fields, nested picks, call arguments, loops, formatted values, adjacent pick tables, and300 alternatives with numeric/string/resource/global-reference values. Resource alternatives alternate two distinct tiny assets. Singleargument list picking retains native PickD2; multiargument picking uses lazy PickSwitch79.

Native threshold construction is cumulative `i * floor(65535 / count)`. The test checks every threshold for each300-candidate procedure. Source operand counts are bounded by the available bytes; malformed maximum counts are separately rejected without attempting large allocation.

Focused22-case integration passes. Full-game lowering passes59,982 procedures with zero errors after the nested-span and external-entry relocation fixes. The combined package gate is pending.
