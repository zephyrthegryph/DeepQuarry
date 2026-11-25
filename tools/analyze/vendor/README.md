# Vendored SpacemanDMM crates

`dreammaker`, `dreamchecker`, `interval-tree` and `builtins-proc-macro` from SpacemanDMM (https://github.com/SpaceManiac/SpacemanDMM, by Tad Hardesty and contributors;
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
- `ObjectTree::drop_body_ranges`: forget the body ranges (their end lies in whatever file the parse read next);
- `Context::fork` / `take_errors`: a worker context with the same files and config, and draining its diagnostics (`dreamchecker`'s
  parallel pass);
- `parser::hold_parse_summary` / `take_parse_summary` / `diagnostics_before_finish`: keep the "parsed N/M proc bodies" line and mark
  where `ObjectTree::finish`'s diagnostics start, so `analyze dreamchecker` prints the parse in the standalone's order.

`dreamchecker` is the library only (no `main.rs`, no `build.rs`: the standalone binary stays the oracle). Changed here, for
`src/dreamchecker.rs` (`analyze dreamchecker`):

- proc bodies are read through `LazyCode` (`*proc.get().code`);
- `run_parallel` / `AnalyzeObjectTree::check_procs_parallel`: the proc-body pass on several threads, each with a forked context;
  every body's diagnostics are registered, and its tables (`used_kwargs`, `call_tree`, sleeping/impure violators, `waitfor`)
  merged, in the serial order;
- `check_proc_call_tree`: each search queues a proc once (upstream queued it again per caller, cloning the call stack, and skipped it
  when popped: 243 of 366 s on DeepQuarry), the searches run on several threads, and the directive procs are taken in source order
  (upstream's hash order is seeded per process). The other passes are unchanged and serial.

Everything else is upstream. To move to a new suite, copy the four crates over and re-apply the list above.
