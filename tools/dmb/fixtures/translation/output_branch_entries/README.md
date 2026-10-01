# Output branch entries

Twelve native/OpenDream paired procedures cover conditional entries into direct output receivers, early-return joins, world/argument/global/usr/src/local targets, direct interpolated output, conditional effectful values, backward authored goto, and field/index receivers.

Native artifacts were compiled in a fresh scratch directory with BYOND516.1687; JSON was exported from the current patched OpenDream compiler. No runtime was executed.

`tests/output_branch_entries.rs` compares complete bodies with semantic IDs and debug markers normalized, in both debug modes. All twelve pairs passed the focused fresh-library check. The test specifically retains receiver loads and native branch targets; it does not skip output operations or tolerate operand stack changes.
