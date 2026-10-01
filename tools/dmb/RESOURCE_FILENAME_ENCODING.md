# Resource filename encoding evidence

DreamMaker **516.1687** accepts UTF-8 DM source without a BOM and resource files
with Latin, Greek, and CJK names. The native RSC stores the following names as
their exact UTF-8 bytes:

| Filename | Native RSC bytes, hexadecimal |
|---|---|
| `café.txt` | `63 61 66 c3 a9 2e 74 78 74` |
| `δείγμα.txt` | `ce b4 ce b5 ce af ce b3 ce bc ce b1 2e 74 78 74` |
| `资源.txt` | `e8 b5 84 e6 ba 90 2e 74 78 74` |

Both native DreamMaker and the patched OpenDream compiler accepted these probes
with zero errors and warnings. Full Rust translation reproduces the name bytes,
asset payloads, resource kinds, and payload-derived IDs exactly. Native archive
timestamps are excluded from this semantic comparison.

The DMB resource table contains `(resource ID, kind)` records, not filename
strings. Those records match the translated output. The resource names live in
the RSC's named entries.

Portable evidence is in `fixtures/translation/unicode_resources/`; the integration
test `tests/resource_unicode.rs` checks all three filenames, archive contents,
DMB reference identities, and lossless native RSC read/write. The native fixtures
were compiled without running DreamDaemon.

This establishes UTF-8 filenames for these legal static resources on the tested
compiler version. Older compiler versions, legacy source encodings, and arbitrary
imported archives remain outside this evidence. The reader therefore continues
to preserve RSC names as raw bytes rather than requiring valid UTF-8.
