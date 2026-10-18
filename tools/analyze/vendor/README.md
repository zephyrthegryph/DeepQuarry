# Vendored SpacemanDMM crates

`dreammaker`, `interval-tree` and `builtins-proc-macro` from SpacemanDMM (https://github.com/SpaceManiac/SpacemanDMM, by Tad Hardesty and contributors;
`interval-tree` originally by coco), tag `suite-1.11`, commit 0290db5c752fa292f9824521515b603a2afd11dc. GPL-3.0: the license is
`LICENSE-SpacemanDMM` and a copy in each crate (`LICENSE`). Changed here, for `src/sem/model_store.rs` (the parsed model kept between runs):

- `serde` derives on the AST, object tree, constants, docs, `FileId` and `Location` (bitflags types serialize their bits);
  `indexmap` and `ordered-float` with their `serde` features;
- `ObjectTree::file_patch` / `splice_patch` / `splice_file`: what one file contributes to a tree, put in place of what it contributed;
- `ProcValue::code` is a `LazyCode` (derefs to `Option<Block>`): a stored tree keeps each body encoded and decodes it on first use
  (`set_code_codec`, `has_body`);
- `Preprocessor::push_file_as`: a file pushed under its registered path with the `__FILE__` an include from the `.dme` gives;
- `ObjectTree::parts` / `from_parts`: the type graph in slices (stored and decoded on several cores);
- `Token` and `Punctuation` serde derives, `StoredDefine`, `StoredDefineHistory` and `DefineHistory::to_stored` / `from_stored`: the macro
  history kept beside the model, so one file can be parsed alone (`branch_at_file`);
- `ObjectTree::drop_body_ranges`: forget the body ranges (their end lies in whatever file the parse read next).

Everything else is upstream. To move to a new suite, copy the three crates over and re-apply the list above.
