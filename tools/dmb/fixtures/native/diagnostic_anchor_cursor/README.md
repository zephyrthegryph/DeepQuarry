# Diagnostic cursor discovery

Authenticated compile-only BYOND516.1687 captures use the pinned executable SHA `8cac7e8bd48219f8a7fb622535a1ce1a914d0a9a3e909bc9ceb84b3074709dc0`. Each receipt records executable SHA/file version before and after, version banner, exact copied source/manifest hashes, diagnostics and output hashes. Each child has a10-second watchdog and each capture has a60-second admission deadline. No native compiler or runtime was executed.

Receipts are preserved in `E:/dq-cache/dmb-native-v2/diagnostic-anchor-discovery/20261010-cursor-a`, `20261010-cursor-mixed-a` and `20261010-type-masks-a`. Sources in the mixed capture apply the explicitly recorded byte replacement ` as anything` → ` as text|anything`; the no-newline case removes only final CR/LF bytes. The recorded copied source is the compiler input.

Pure `anything` emits no warning in all six contexts. Multiple explicit type tokens containing `anything` and no choices warn once for each `anything` token: `anything|null`, `null|anything`, text/object combinations each warn once, while `anything|anything` warns twice. Thus a combined numeric mask alone cannot encode this diagnostic predicate.

For mixed filters, blank lines/comments advance the reported location to the next significant declaration token (line6); a following statement reports its token line3. Same-line semicolon and nested comma report line2. At included-file EOF, both with and without a final newline, BYOND reports the include caller `probe.dme:2`. A current expression offset or a fabricated line increment does not represent these coordinates. Exact production parity needs an issued lexer-lookahead anchor and the current include-return cursor; absent such authority it must disclose the coordinate limitation.
