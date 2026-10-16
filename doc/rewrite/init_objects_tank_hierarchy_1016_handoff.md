# Tank hierarchy source review

Five init fingerprints: base tank blueprint effects/proxy/gauge (3), phoron one-tank bomb (1), oxygen one-tank bomb (1). A global anchored search finds only these three overrides plus the pressurized-scale override in remaining-nine.review.patch. Both bomb_fill params are retained; gas contents are declared before setup. Ancestor-first setup therefore preserves actual ready gas/proxy before child fill and before pressurized scaling. The existing onetankbomb operation is unchanged, including host RNG, wiring, gas heating and assembly attachment; this is not a new detonation/fuse policy.

Apply after remaining-nine.review.patch so the pressurized leaf is migrated too. Two planned leaves test real gas/proxy identity/ownership/destruction, pressurized scale, full type default, explicit-zero positional fill, real gas amounts/heating and actual assembly attachment. No builds/generation/tests have run. Root must wire dq_init_objects_tank_hierarchy_tests.dm.
