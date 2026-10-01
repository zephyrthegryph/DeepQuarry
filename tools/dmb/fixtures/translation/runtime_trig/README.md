# Runtime trigonometric opcodes

Native516.1687 emits sin182, cos183, tan184, arcsinC4, arccosC5, arctan145 and arctan2 146. Portable procedures use runtime arguments to prevent constant folding.

Static VM dispatch table10154278 distinguishes old sinC2 handler101422db and cosC3 handler10142463 from182 handler10142321 and183 handler101424a9. Old handlers convert degrees directly to double radians then call sin/cos. New handlers reduce the absolute angle modulo360 and reflect quadrants, selecting complementary sin/cos near cardinal axes. Sin180 and cos90 reach sin0 and exactzero, whereas direct old double sin(pi)/cos(pi/2) produce small nonzero residues. The installed constant at103aa7c8 is pi/180;103ab8c0=360,103aa830=180,103aa82c=90.

Lowering now selects the native516 handlers. The regression requires exact builtin opcodes and full normalized native procedure parity in debug and nondebug output. Native compilation and disassembly only; no DreamDaemon execution.
