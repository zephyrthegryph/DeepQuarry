//! Shared original Analyze command help; static DATA only.
pub const HELP: &str = "analyze: DeepQuarry's lint/analysis engine

USAGE
  analyze check [--lint NAME...] [--changed-only] [--no-cache] [--rehash] [--raw] [--ci] [--root DIR]
      Run lints (default: all). Exit 1 if any fails. --raw ignores baselines (every site is new);
      --changed-only judges only files changed against origin/master and the working tree.
  analyze check --native-dmbc ABSOLUTE_EXE --no-selftest --lint sem/reads untracked_inputs setter_publishes
      Run the three native read policies together. Optional: --root DIR, --raw, --ci.
  analyze baseline --update|--seed|--migrate [--lint NAME...]
      Rewrite ratchet baselines: --update only ever drops fixed sites; --seed records every site;
      --migrate rewrites line-text rows as identity rows (@owner::...) without adding or dropping one.
  analyze parity [NAME... | --all] [--bless] [--fixtures-only]
      Run the legacy Python lint and the engine port on this tree (and on tools/analyze/fixtures/)
      and diff the findings. --bless writes expected.txt from a clean fixture comparison.
  analyze timing [--lint NAME...] [--no-cache]
      A full check with a per-lint timing table.
  analyze selftest [--lint NAME...]     Run each lint's fixture tests.
  analyze list                          The registered lints.
  analyze frontend-diff                 Compare the text scanner with the dreammaker parser.
  analyze native-query --dmbc ABSOLUTE_EXE REQUEST.json [--jsonl]\n      Delegate a pinned source request to the existing native daemon client.\n  analyze gen [--check] [NAME...]       Write (or check) the generated DM under code/engine/_generated/.
  analyze codemod list | NAME [--check|--apply|--revert] [--path PREFIX...] [--write-residue]
      AST-aware rewriters (phase 2.5); `analyze codemod help`.
  analyze base-vars-dead [--tsv] [--few]
      Base-type vars nothing reads (dead or write-only), by name over code/ and maps/.
  analyze sem reads /type proc | oracle [--all]
                                        Semantic queries: a handler's reads; the reads spike oracle.

A lint is selected by its name or its group (`sys` selects every sys/* lint).";
