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
JSON and DMF. These controls certify raw archive payload encoding, not native
source validation of malformed files, every multimedia format, DMF header
projection or client script transformation. Unverified extensions remain
Unsupported unless supplied a source-bound explicit encoder.

## Remaining resource-order contract

The production adapter can derive capture order automatically when every archive
alias has a distinct runtime content ID. Equal-content aliases require an exact,
validated complete alias permutation: native import order affects the first kind
and resource-to-text filename lookup. It must come from grammar phase facts,
not dictionary sorting or source literal scanning.

The thirty `fixtures/translation/resource_archive_order` controls establish root
global promotion, explicit namespace creation, procedure grouping, deferred
actual-parent passes, and included-script/interface phases. The current authored
map model supplies ordered assignment facts but the generic source declaration
model does not yet expose every namespace/group creation fact needed by that
collector. This remains a Phase 1 integration requirement; the bounded output
adapter rejects ambiguous automatic ordering rather than claiming parity.

Included skin icons precede their DMF archive entry; DMF payload certification
above does not implement client header or script projection. Those output domains
must remain explicitly unsupported until their separate composer contracts land.
