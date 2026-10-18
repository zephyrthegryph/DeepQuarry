# Vendored SpacemanDMM crates

`dreammaker`, `interval-tree` and `builtins-proc-macro` from SpacemanDMM `suite-1.11` (commit 0290db5), GPL-3.0
(`LICENSE-SpacemanDMM`). Changed here, for `src/sem/model_store.rs` (the parsed model kept between runs):

- `serde` derives on the AST, object tree, constants, docs, `FileId` and `Location` (bitflags types serialize their bits);
  `indexmap` and `ordered-float` with their `serde` features;
- `ObjectTree::splice_file`: put a file's re-parsed proc bodies and locations into a stored tree;
- `ObjectTree::drop_body_ranges`: forget the body ranges (their end lies in whatever file the parse read next).

Everything else is upstream. To move to a new suite, copy the three crates over and re-apply the list above.
