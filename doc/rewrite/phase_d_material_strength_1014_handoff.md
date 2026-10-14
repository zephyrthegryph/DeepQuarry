# Phase D material strength provider move

Branch: `codex/phase-d-material-strength-1014`, based on `origin/master` at `2470d3f930`.
Pure move commit: `9c696e2987`.

`code/datums/properties/families/material_strength.dm` moves to `code/library/providers/material_strength.dm`, the shared-provider layer in final_api section 22. The existing DME include path is replaced in place, preserving ordering. Source blob identity was checked, and git records an R100 move. No source content, requirements, refusal text, declarations or behavior changed.

The file defines the three material strength properties and pure material-fold providers: hardness, yield strength and fracture toughness. It contains no old declaration forms or lifecycle overrides and has no relevant declaration/init/base-variable baseline entry. Latest source edit is `11aae8c699`, September 23; no October 13 or 14 master source overlap was found. No acceptance files, equipment-slot tables or reserved analyzer files are included.

Verification is pending. Preparation ran no generation, compile, tests or lane-ready gate, and did not push. Suggested focused selectors are `dq_requirement_protocol_pin`, `dq_conversion_pin` and `dq_armor_material_response`; the latter checks real material response factors from the material strength numbers. This test is adjacent consumer coverage, not a claim of dedicated provider-fold coverage. The lane owner must gate before pushing. No pin re-bless is expected for this path-only change.
