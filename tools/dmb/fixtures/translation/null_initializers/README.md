# Null initializer provenance

Six native paired procedures preserve a managed list call result before implicit list-loop/traditional-for initialization and ordinary local declarations with or without authored null.

Native implicit loop initialization uses PushVal Null, retaining the eval reference. Authored local null uses GetVar Null, which has a different eval lifetime. An implicit ordinary local declaration needs no initialization instruction. The integration test compares three complete bodies (implicit list/typed loops and authored local null) in both debug modes, and verifies exact null provenance in all six shapes. Traditional for lowering retains an additional getter/discard; an implicit ordinary local stores its already-null initial value. These distinct layouts are not normalized by the comparer.

BYOND516.1687 rejects `for(var/x=null in L)` and its typed equivalent as bad assignment; those forms are excluded from the legal paired matrix. Native artifacts were compiled fresh with zero errors/warnings; no runtime was executed. The focused six-shape provenance checks and three complete-body comparisons passed in both debug modes using actual refreshed exporter JSON.

