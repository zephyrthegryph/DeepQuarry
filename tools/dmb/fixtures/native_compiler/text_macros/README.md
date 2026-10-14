# Text macro and escape oracle

`probe.dm` holds every text macro and escape form DreamMaker 516.1687 accepts in
seven positions (after/before/around a substitution, alone, mid-word); each
string ends `|Q<n>`. `probe.native.bin` is its DreamMaker output. The test
`simple::tests::text_macros_oracle` requires the native template bytes of every
string to equal DreamMaker's, and that forms DreamMaker rejects (`\r`, `\redb`,
`\he` with no preceding substitution, ...) are rejected. A DreamDaemon run of the
same strings printed identical text under both compilers (268 cases).
