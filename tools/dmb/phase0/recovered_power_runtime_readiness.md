# Recovered power comparison readiness

The recovered20261010 source cannot currently produce a matching runtime library:
its DM bindings declare `034eab3a3bbb7263`, while Rust ffi ABI declares
`bc10d05a700cfdd7`. Building or taking a cache library does not repair this
captured-source disagreement. Regeneration would change the authenticated roster
and requires a new capture. No library was copied or built.

The focused capture runner's optional `--require-snapshot-runtime-abi` detects
this prerequisite before launching children. It does not certify library source
content. Ordinary calls remain unchanged.

Once a coherent capture and its existing content-key library issuer are available,
the desired test selection is `dq_power_cut_splits_and_repair_merges`,
`dq_power_apc_cycle`, and `dq_power_idle_apc_and_smes_sleep`. Use trusted mode,
6144MiB Job,900seconds overall and existing300second child bounds. Runtime must
select that capture's source-proven library through the ordinary observed/staged
library route and retain ABI verification. Review checkout library substitution,
`DQ_PREBUILT_VERDIGRIS` bypass and ABI-check bypass cannot establish this proof.

Bounded cache inventory found11release manifests. The `bc10d05a700cfdd7` candidate
has key `18e98765d134e3e4280002770277c259`, commit
`f70e7ebeebc0b181296bba08f349d77213c8084f`. It is not admitted for this snapshot.
The current review VerdigrisTarget source does not expose a content-key issuer;
the manifest's ABI and commit labels alone do not prove matching recovered bytes.
