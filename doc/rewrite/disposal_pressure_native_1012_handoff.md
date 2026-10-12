# Disposal pressure native dependency handoff

Branch: `codex/disposal-pressure-native-1012`. Exact lane-ready stamp: `37fea69058`, merged master `13b1f32687`.

Disposal pressure now reads a shared tracked native pressure producer through a validated lookup argument. Native mutations publish their actual host getter values at completed atomic boundaries. Transfers, native identity retirement/reuse and reservoir replacement preserve coherent admission and immediate gauge reads. Relation hooks prepare producers before committed relation publication and release their evaluation leases on failure.

The disposal's broad `CHANGE_MACHINE_SETTINGS` publication drops from one to zero. Other settings bridges are handled by the separate machine-channel branch; this is not a claim of global channel zero. No baseline, ceiling or ALLOW was added. No pin rows were re-blessed.

Verification:

- Initial focused gate on `ab9943fe7b`: 34 passed, one fixture failure. The four gas behavior tests and transformed lookup-provider test passed, as did both mandatory pins. The exception fixture initially used a text ref to a collected poisoned context.
- Final fresh lane-ready gate on `37fea69058`: 30 passed, zero failures. It reran the repaired exception test, both mandatory pins and the lane's standard smoke/appearance checks. Normal pool recycling now retains the inspected context without allowing it to escape its callback; scoped pool settings and deferred driver cleanup are restored.
- Final production compile: zero errors; DreamChecker: zero diagnostics; ratchets passed.
- Targeted analyzer lookup-argument tests: three passed. Native numeric tests: four initially passed; the corrected turf host-getter/worker-view test passed in its failure-only repair run. No full workspace or DM suite ran.

An intermediate gate was canceled after the handler lint correctly rejected a context escape in an attempted fixture repair. Only that gate's identified processes were terminated, and it produced no stamp. The corrected fixture subsequently passed the handler lint and the fresh final gate.

Master-side state warnings were observed for the construction floor, canister prompts and the two starting NIFsoft caches. Their fixes are on the separately pushed test-hygiene branch; they are not suppressed here. All new pressure cases were clean.

The turf contract is getter parity, not an artificial frame delay: accepted local commands already affect the actual native host getter before worker commitment. Numeric readers match that getter, then refresh at the worker boundary.
