# Source-only cache cohort

Owner directory code/modules/body/organs: the per-snapshot species fallback dictionary is lazy; its real getters use LAZYSET and safe lookup. dq_organ_species_cache_home checks absent source, actual species read/cache and reference removal fallback.

No generation, compile, tests, baseline update or stamp has run. Root owns verification and commits.
