# Procedure-static constant settings

Compile-only BYOND 516.1687 control, hidden console compiler with 60-second
watchdog. No DreamDaemon or profiler was launched. Reference result: 0 errors,
0 warnings. Raw receipt/artifacts are outside the checkout at
`D:/dmb-native-v2-phase0/static-abi-setting-control`.

The procedure declares a static const named `label`, shadowing a global const
with a different value. Both `set name = label` and `set desc = label` use the
procedure-local value. Reference procedure 0 has strings `[440,439,439,65535]`,
flags 4, source kind 0, source parameter 255, no extended flags. String 439 is
`local label`, string 440 is `/proc/probe`. Code reads static variable 68, then
RET/END. This validates lexical ABI scalar lookup; it does not certify arbitrary
runtime values as settings or infer unnamed engine procedure metadata.

No generated DMB/RSC/log files belong in this source fixture.