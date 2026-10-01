# Initializer token identity

Fresh native compile-only fixtures establish equality partitions of kind-62 initializer tokens returned by `initial()`.

- `probe`: repeated list/new/sound/matrix expressions, inherited overrides, cross-class list expressions, root globals and proc-local statics.
- `folding`: folded arithmetic and constant aliases; named list keys; constructor omissions, positional defaults and named arguments remain distinct.

Optional compiler metadata version 1 records original declaration identities separately from final overrides. Keys describe supported construction shape with constant-folded operands. Unsupported construction identities are explicitly listed in `NativeUnidentifiedInitializerFields` / `NativeUnidentifiedInitializerIds`; they must not be described as proven sharing.

Constant strings use the compiler string codec. Resource constants must be resolved to native resource identity; type constants use paths rather than allocation IDs. Token numbers are allocation details; tests compare the complete pairwise equality partition, including global/static/default/override records.
`cleared` retains two distinct same-field construction markers followed by a final null override. `NativeInitializerAssignmentIdentities` is parallel to `DynamicInitializerAssignments`; final per-field identity alone cannot represent that history.
`families` adds alist entries, constant dimensions, newlist canonicalized to list-of-new, verb construction and particle generators. Fresh native proves empty newlist/list and newlist(T)/list(new T) share tokens. Dimension declarations remain null defaults, so identity metadata does not itself request a kind-62 marker.
`debug` proves final case-sensitive DEBUG macro presence disables token interning, independently of emitted debug lines. Metadata.NativeInitializerInterningMode explicitly selects unique/expression; late define and subsequent undef follow final macro state.

## Compiler DEBUG mode

Native initializer sharing depends on the final, case-sensitive preprocessor definition of DEBUG. This is independent of whether translated procedures include debug line markers.

Native compilation experiments established:

| Final macro state | Native hidden initializer identity |
|---|---|
| `#define DEBUG` | Every authored initializer remains distinct |
| `#define DEBUG 0` | Distinct, despite the value zero |
| DEBUG defined after all authored declarations | Distinct |
| DEBUG defined then undefined before declarations | Expression sharing |
| DEBUG undefined after all declarations | Expression sharing |
| Only lowercase `debug` defined | Expression sharing |

The identical 22-marker release and DEBUG programs had five release identity groups split in DEBUG and no merged groups. `debug.native.bin` and actual `debug.json` retain the DEBUG witness. The dedicated Rust regression checks all 22 marker names, requires 22 distinct native identities, and compares every pair of native/translated identities with both debug-line settings.

Metadata.NativeInitializerInterningMode exports `unique` for final DEBUG presence and `expression` otherwise. The native full-game DEBUG build must use unique allocation; canonical expression interning in that build incorrectly merges thousands of native initializer identities.
