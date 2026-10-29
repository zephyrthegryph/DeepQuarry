# CR literal boundary probes (not a blessed oracle)

These tiny executable DM worlds isolate the existing native `without_cr`
transformation. Files deliberately contain literal CR bytes; never normalize
line endings. Their output reports JSON text, length and byte values, then exits.
No behavior is asserted until DreamMaker/DreamDaemon evidence is captured.

Cases:

- `cr_interpolation`: backslash + CR + `[a]`. Pinned checker observes a real
  interpolation, but native currently cooks this to an escaped literal bracket.
- `cr_escaped_bracket`: backslash + CR + backslash + `[a]`. The converse boundary
  risk: the first backslash-CR is a continuation; the later bracket is escaped.
- `lf_interpolation`: LF continuation control.
- `cr_inside_interpolation`: CR appears only inside the expression boundary.
- `plain_cr` / `raw_cr`: establish actual runtime CR treatment independently of
  pinned checker lexical segment presence.

Root must compile each exact byte-identical input with installed DreamMaker
516.1687 and the private native binary, then run each resulting DMB with the same
installed DreamDaemon. The pinned DreamChecker already accepts the first case
with zero diagnostics; that proves its parsing, not DreamMaker runtime output.

No source fix is applied here. Ordinary CR removal and escape-boundary decisions
must be separated only after these independent runtime observations. A safe
candidate would parse original CR escape/interpolation boundaries once, skip CR
only during runtime literal-byte emission if DreamMaker proves that behavior,
and retain source spans without normalization/remapping. It must also handle an
escaped CR-only continuation and nested interpolation strings. Parsing the
already-cooked string then re-parsing for the checker is not acceptable.

## Independent runtime observations (2026-10-28)

Root ran the first five cases through the private native compiler and installed
DreamMaker 516.1687, then the same DreamDaemon. JSON text, lengths and every byte
matched for `cr_interpolation`, `cr_escaped_bracket`, `lf_interpolation`,
`cr_inside_interpolation` and `plain_cr`. In particular backslash-CR-`[a]`
yields literal `[a]` under BOTH compilers. The pinned checker interprets that
same source as interpolation: it diverges from runtime here. Do not change
runtime parsing to imitate that checker behavior.

The sixth case, `raw_cr`, exposed native source admission rather than runtime
bytes: native rejected raw single-line CR as unterminated; DreamMaker accepted
it and produced `ab`. Root prepared a narrow CR allowance in the existing raw
literal lexer; LF is still rejected. Its focused regressions and new-binary
runtime confirmation are pending. Existing runtime CR stripping is unchanged.

Evidence: `data/unified-analysis/cr-runtime-probes.log` and root's captured
outputs under `E:/dq-cache/probe-cache/unified-cr-20261028`. Initial invocation
used a default store on C before discovery; all reruns explicitly bind compiler
cache and output-store paths under E. This is six tiny compiler probes, not a
whole-project semantic equivalence claim.
