# Procedure ABI boundary controls

Compile-only controls captured with DreamMaker 516.1687, executable SHA256
`8cac7e8bd48219f8a7fb622535a1ce1a914d0a9a3e909bc9ceb84b3074709dc0`.
Each invocation was hidden and bounded to 60 seconds. No DreamDaemon ran.
The compiler output is retained under `D:/dmb-native-v2-phase0/abi-coverage-probes`; generated DMB/RSC
files remain outside the repository.

| Case | Observed result |
|---|---|
| fresh | Arbitrary new global and explicit class `/proc/` declarations succeed. Both procedure records have flags 4, source kind 0, source parameter 255, absent description/category. |
| inherited | Bare class `New()` and `Del()` succeed; New record has flags 4 and source (0,255). This does not certify every invisible intrinsic's layout. |
| implicit_fresh | Arbitrary bare class method name is rejected as undefined proc. It cannot use the fresh formal rule. |
| probe | Explicit class `/proc/New()` is rejected as duplicate built-in; global `/proc/sin()` is rejected as reserved word. |
| atom / mob / client / world | Each exact owner's bare New and Del compile. Both records flags4, no extended flags, source(0,255), absent description/category and display name New/Del. |

The boundary prototype treats the pinned native-bootstrap name catalog as a
conservative exclusion list, not as a source of physical ABI metadata. Known
names without captured layouts stay unsupported. Explicit source formal names
outside that catalog use the established default ABI rule; source predecessors
retain their exact prepared layouts. Catalog completeness and the production
adapter must be reviewed before exporting the prototype. The finite catalog is
an explicit compatibility assumption, rather than a mathematical absence proof;
its exact bytes, interpretation schema and policy version enter policy_identity.
Cross-proc/verb exclusion is deliberately conservative. New/Del positive receipts
cover only datum, atom, mob, client and world ancestry domains under this exact
template/schema. They produce known layouts and never a Fresh absence answer.
