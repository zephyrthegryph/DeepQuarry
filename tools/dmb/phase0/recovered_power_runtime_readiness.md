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

## Coherent new capture procedure (root execution only)

1. Preserve the recovered root and its receipt bytes. Create one new private
   E:/dq-cache root/source from current-review working bytes, including the
   authored heat marker types and existing generated code/icons. Record the
   exact tracked/untracked capture recipe, positive roster and exclusions with
   regular/nonreparse independent copies. The historical subset lacks authored
   types; do not repair it by transplanting selected files or reuse its identity.
   See the observed blocker and fresh-current route below.
2. Pin Bun and the current ordinary generator source. Run
   `bun tools/dmb/phase0/generate_captured_runtime_bindings.ts NEW_ROOT/source`
   under the existing owned Job/300second child watchdog. This calls
   `generateVerdigrisBindings(root,false)` followed by its check mode. No ABI
   literal is manually changed. Preserve stdout and changed-path inventory.
3. Reissue NEW `source-snapshot.json` and `input-closure.json` through the existing
   source-capture roster schema, hashing the actual complete staged input roster
   after generation. Retain an explicit transformation receipt for every changed
   generated file. Run the existing `verify_source` and
   `authenticate_source_snapshot` on those NEW owners. Source roster authentication
   still does not prove exhaustive implicit compiler read closure.
4. Only after the new DM/Rust ABI preflight passes, build that staged Rust source
   using the ordinary bindings check and its actual rust-toolchain/Cargo.lock.
   Root's bounded owned launcher must use Cargo `build --locked -j1 --release
   --target i686-pc-windows-msvc --package verdigris --lib`, cwd NEW_ROOT/source/verdigris,
   CARGO_TARGET_DIR=NEW_E_TARGET, no foreign DLL/prebuilt/ABI-check bypass,300seconds
   and4GB. Missing captured Rust inputs or stale bindings fail; do not silently
   substitute current checkout sources. Preserve actual build input/output pins.
5. Run the new `build_captured_verdigris.py --prepared-root NEW_ROOT --output
   NEW_BUILD_EVIDENCE --target-directory NEW_E_TARGET --cargo ABSOLUTE_CARGO_EXE
   --cargo-sha256 PIN` under root supervision. It issues the source-qualified
   `runtime-build-receipt.json` through the ordinary300second/4GB owned Job.
   The focused adapter admits that actual receipt via
   `--runtime-build-receipt FILE --runtime-build-receipt-sha256 SHA`, checking
   complete before/after roster, compiled source pin, current generated ABI,
   Cargo invocation/identity and DLL hash. The ordinary runtime library stager
   selects this exact DLL for both paired worlds, retaining post-run checks.
   It cannot silently use the review checkout library for this explicit route.
   Recompiling BYOND/native through
   `recapture_focused_pair.py --require-snapshot-runtime-abi` uses the new roster,
   ordered UNIT_TESTS/CITESTING/DM_VERSION/DM_BUILD defines and original toolpins.

This procedure does not make the incompatible original pair acceptable and does
not promote `inputClosureAuthenticated` or `acceptedRuntimeBaseline` to true.

## Observed generation blocker and fresh-current route (2026-10-11)

The independently copied recovered roster at
`E:/dq-cache/dmb-native-v2/coherent-runtime-source-20261011-f4c8528f4929`
was authenticated before ordinary bindings generation. The owned generator exited
1 and was reaped: its captured Rust HeatBody component names
`/atom/movable/vg_heat_body`, but the roster omits authored
`code/modules/heat/heat_entities.dm`, and its captured `_bindings_types.dm`
contains no such header. Current review has the authored marker file. The
canonical producer excludes its own generated outputs from authored type/proc
validation; relaxing that guard or adding a dummy type would conceal this gap.
Rendering failed before any output writes; all three copied bindings/ABI outputs
still match ancestry. The preserved preparation/retry receipts record both the
initial launcher failure and the actual generator failure separately.

Use a NEW current-review working-byte capture instead of patching that historical
subset. Capture the current tracked working files and untracked game inputs,
including existing generated code and icons, with regular/nonreparse independent
copies. Record the recipe, exact exclusions and byte roster, then derive
`comparison.dme` from the captured current `deepquarry.dme` by the ordinary strict
(no WIP include filtering) byte-copy transform. Run ordinary bindings generation
only there, reissue/verify the new positive roster, and perform the captured ABI
preflight. Git HEAD is descriptive metadata, not captured-byte authority. A
300-second aggregate and 4-GiB input cap must fail explicitly rather than omit
oversized inputs. This does not authenticate implicit/compiler configuration or
negative-read closure and does not make the old pair an accepted baseline.

After the new capture passes, steps4-5 above apply to its own Verdigris sources;
no foreign DLL substitution and no Cargo while another owned Cargo gate runs.
