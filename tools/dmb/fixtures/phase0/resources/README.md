# Raw resource payload controls

Fresh DreamMaker 516.1687 compile-only controls (no DreamDaemon), captured
2026-10-06. Input sources are unchanged copies of
`fixtures/translation/resource_kinds` and `fixtures/translation/selected_skin`.

`raw_payload_control/receipt.json` pins compiler SHA256 and command;
`payload-comparison.json` records exact current source/payload lengths and SHA256.
All nine resource_kinds files are byte-identical to named native RSC payloads.
`raw_skin_control` proves raw DMF and its PNG bytes separately. Each directory
retains native RSC bytes and compiler output. Full external input copies remain
at E:/dmb-native-v2-phase0/{resource,skin}-capture-control.

Production raw encoding is enabled for DMI, PNG, OGG, TTF, TXT, HTML, CSS, JS,
JSON, DMF, GIF, WAV, MID, MP3, WOFF2, WebP, MP4, DM and explicit DMS resources.
`additional_raw_control` and `browser_source_raw_control` retain fresh pinned
native receipts and exact current source assets for the latter eight formats.
These controls certify raw archive payload encoding; malformed-file validation
parity and unobserved formats remain unsupported without an explicit encoder.
`script_file_raw_control` separately certifies the explicit DMS file payload
as raw generic kind0. Included-DMS script import phases remain unsupported.

Interpolation resource discovery uses balanced lexical tokens, independently
of semantic expression lowering. `interpolation_valid_control` is a legal
native nested weighted-pick control retaining both resource aliases and their
source ranges; `interpolation_control` preserves the rejected first single-pick
attempt rather than treating a rejected source as grammar evidence.

## Resource-order integration

The generic frontend now retains a pre-normalization allocation ledger with
empty type/var/proc/verb namespace creation, formal vs implicit declarations,
ordered field overrides, procedure body spans and explicit parent events.
The native phase collector passes 31 source-only archive order controls. Four
new compile-only controls prove empty var/proc namespace blocks establish the
same ordering phases as resource-free declarations.

The captured driver resolves literals through the one frozen resource lookup
ledger and requires complete alias coverage before projecting the RSC. It
supports the certified single-DMF assets-before-interface prefix and ordered
map assignment suffix. The selected raw DMF resource is attached to the exact
frozen world skin field; no separate UI-property compiler is invented.

Included-DMS import phases, multiple-DMF import phases, arbitrary additional resources,
and unproven map placement forms remain explicit Unsupported. No dictionary
sorting or content-only dedup replaces observable archive alias ordering.
