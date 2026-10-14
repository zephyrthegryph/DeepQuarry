# Missing resource domains

Fresh BYOND 516.1687 compile-only controls establish different handling:

- A missing resource literal in DM source is a source error: missing_literal_control
  exits1, reports `cannot find file` at probe.dm:1, 1 error and 0 warnings.
- A missing resource literal in a map atom is a source error:
  missing_map_literal_control reports `map.dmm:1:error: cannot find file`,
  followed by a parser-cascade `expected )`. The captured driver reports the
  primary error at the exact map origin; it does not manufacture the cascade.
- A missing icon named only by DMF is allowed: missing_skin_icon_control exits0,
  0 errors/warnings, retaining the raw DMF without importing the missing PNG.

Capture must retain exact negative lookup observations. DM lowering cannot turn
Missing into a fabricated null or Unsupported; DMF import planning may omit a
missing icon. No DreamDaemon was launched for either control.
