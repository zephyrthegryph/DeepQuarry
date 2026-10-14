# D4 destruction consequences audit

All11 baseline rows already reside in on_destroy hooks on current master; there are no remaining corresponding Destroy overrides to rename. Added nine real qdel tests covering machines, micro holders, tunnels, ventcrawlers, petrification statues, bellies, gargoyles, telecubes and both crystal shard products. The statue release moves to on_ending: core slot spilling occurs before on_destroy, so the old late hook misses mute/stasis cleanup. This corrects real qdel cleanup without changing containment declarations.

Known master-side scope blocker: gargoyle's keep=FALSE petrified input is dropped by atoms InitAtom before setup(petrify_human) runs. Its real constructor regression must expose that defect. The existing reviewed framework reorder is outside D4's permitted files and has not been applied here. Other hooks retain existing effects/drop behavior. decl update and focused validation pending. No push or merge.
