# Query preparation contract

Compiler-only real owned-daemon contract. It prepares valid declarations/defaults/statics around an invalid unknown-call body, discovers current semantic pages and returned symbols, queries the SAME resolved host, rejects stale pins, and verifies ordinary compile rejects source without publishing DMB/RSC. One-shot preparation explicitly reports `retained=false`.

The existing launcher bounds children to 30 seconds, aggregate lifetime to 120 seconds, and the owned Job to 4 GiB. This proves neither runtime behavior nor six-worktree acceptance. Supply exact `--native`, `--native-sha256`, `--template`, and `--template-sha256` pins.

## Actual validation

Counted compiler `4bf626fc4f`, SHA-256 `0ecf4e539c61514ab19c575edf15d6d22245c1f81a8f580715ea2846d15d6bd9`: PASS, receipt `E:/dq-cache/dmb-query-preparation-contract/f51387da961f4c2bafa48b6736f3234d/receipt.json`, receipt SHA-256 `e6f394e292a8798ddec45bde2935377b9083194b45adfd627266c8f22921f1ad`. Both daemon and Job descendants were reaped. Two pure policy checks passed.

The ordinary source-rejected compile may stage resources and diagnostic directories; those are preserved and do not count as executable publication. The gate checks exact installed DMB/RSC/pair receipt destinations and the immutable PairStore `pairs` roster. Earlier receipts `3af09f56a69146c9bd24d6f9a88b4454` and `cd3ebe7dc447450d9563ad0e2d96abc6` failed overly broad fixture assertions about these staging files; they remain preserved.

```powershell
python tools/dmb/fixtures/native/query_preparation_contract/run.py --native E:/dq-cache/dmb-native-v2/frozen-build/20261011-4bf626fc4f-counted-dmbc.exe --native-sha256 0ecf4e539c61514ab19c575edf15d6d22245c1f81a8f580715ea2846d15d6bd9 --template E:/projects/dq-wt/dmb-review/tools/dmb/fixtures/native_template.bin --template-sha256 9221528efb715be5b8df23020989e0c2a53ea32bff9894747166dbe04d785540
```
