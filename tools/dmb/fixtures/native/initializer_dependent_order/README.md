# Dependent instance initializer order

Preparation only: no compiler/runtime acceptance is recorded for this new fixture.

1. Run `run.py --reference-only --dm PINNED_DM --dm-sha256 SHA --output-root E:/dq-cache/dmb-initializer-order-reference`.
   It compiles both authored include orders with 30-second children, 120-second
   aggregate bound, and a 4 GB owned Job. No DD is launched.
2. Review the exact reference diagnostics. Runtime is admitted only from a pinned
   successful reference receipt for these unchanged source bytes and compiler.
3. Run the same `run.py` with `--reference-receipt PATH --reference-receipt-sha256 SHA`
   plus the existing native/template/DM/console-DD pins and fresh output root.
   The existing paired fixture core acquires the native pair and runs forward
   worlds, bounded to 300 seconds aggregate and 4 GB. No new compiler runner.

Forward assertions require `first=11`, `second=12`, and the exact effect trace
`first=11;second=12;`. A finish marker and absence of runtimes are mandatory.
Reverse include order is a compile-only control; its runtime behavior is not
predicted or certified. A successful compile is not an order-equivalence claim.

The fixture uses an absolute first declaration and an indented reopened type for
its second declaration, with a real read of the first field and observable calls.
This contrasts the independent constant-list client initialization observation.
No production ordering change is proposed until the actual paired result exists.
