# Blank lines after literal continuation

Captured with pinned BYOND 516.1687; compiler SHA was checked before and after
the bounded compile. No DreamDaemon was run. `capture.json` authenticates the
source, manifest and captured DMB (`probe.native.bin`).

The captured global values of `quoted`, `block` and `multiple` are all exactly
`leftright`. Blank physical lines and subsequent indentation after an escaped
newline are discarded. `raw_control` preserves the backslash, two newlines,
tab and following space. These are literal decoding fixtures, not runtime or
whole-program parity evidence.
