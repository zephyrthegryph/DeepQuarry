# Argument-source frame contract discovery

Uses the existing pinned retirement runtime launcher, ordinary native acquire,
trusted hidden DreamDaemon, and the pinned inspector's raw helper formal tables.
No lowering rule is changed or assumed. Supply explicit current executable pins:

```powershell
python tools/dmb/fixtures/native/argument_source_contract/run.py --native NATIVE.exe --native-sha256 NATIVE_SHA --template tools/dmb/fixtures/native_template.bin --template-sha256 9221528efb715be5b8df23020989e0c2a53ea32bff9894747166dbe04d785540 --dm "D:/Program Files (x86)/BYOND516/bin/dm.exe" --dm-sha256 8cac7e8bd48219f8a7fb622535a1ce1a914d0a9a3e909bc9ceb84b3074709dc0 --dd "D:/Program Files (x86)/BYOND516/bin/dd.exe" --dd-sha256 DD_SHA --inspector E:/dq-cache/dmb-native-v2/frozen-build/20261010-062957-inspector-a0bb00f6.exe --inspector-sha256 5a73ad00b2b2bec2bc2941816a5c31e95481dcbf7ddebc0f1fad6cf9f7f03035 --output-root E:/dq-cache/dmb-argument-source-contract
```

Overall watchdog 300 seconds; tiny runtime and metadata children at most 30
seconds; native compile at most the remaining 300 seconds; owned Job 4 GB plus
existing owned private-memory monitoring. `owned-job.json` preserves final kernel
cleanup/commit accounting independently of the runtime receipt.

The source expressions reference an earlier parameter, `args.len`, and `args[1]`.
Direct calls may not evaluate allowed-values expressions; observed helper-call
count explicitly exposes that limitation. No fake invocation of hidden helpers or
client prompt is used. If helper calls remain zero, runtime output proves only
ordinary call behavior; the authentic helper formal rows remain a separate
structural discrepancy to investigate with an actual client invocation contract.

`helper_metadata_equal` compares formal name/type/source/reserved rows, independently
of runtime `matches`. Raw IDs/rows and each inspector child are preserved. A
metadata mismatch is reported, not automatically treated as a proven runtime bug.
No cross-backend shared input closure certificate is asserted.

Additional prefix controls: `first_source` has a helper on parameter zero;
`third_source` has a typed/defaulted first parameter and dynamic allowed-values
sources on the second and third. Raw helper rows establish prefix length and
whether predecessor type flags/value-source selectors are copied or reset.
No expected prefix or flags are manufactured by the capture driver.
