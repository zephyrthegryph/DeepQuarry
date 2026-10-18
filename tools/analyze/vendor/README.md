# Vendored SpacemanDMM crates

`dreammaker`, `interval-tree` and `builtins-proc-macro` from SpacemanDMM (https://github.com/SpaceManiac/SpacemanDMM, by Tad Hardesty and contributors;
`interval-tree` originally by coco), tag `suite-1.11`, commit 0290db5c752fa292f9824521515b603a2afd11dc. GPL-3.0: the license is
`LICENSE-SpacemanDMM` and a copy in each crate (`LICENSE`). Changed here, for `src/sem/model_store.rs` (the parsed model kept between runs):

- `serde` derives on the AST, object tree, constants, docs, `FileId` and `Location` (bitflags types serialize their bits);
  `indexmap` and `ordered-float` with their `serde` features;
- `ObjectTree::splice_file`: put a file's re-parsed proc bodies and locations into a stored tree;
- `ObjectTree::drop_body_ranges`: forget the body ranges (their end lies in whatever file the parse read next).

Everything else is upstream. To move to a new suite, copy the three crates over and re-apply the list above.
