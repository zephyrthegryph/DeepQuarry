# Native fixture provenance

These outputs were compiled offline with BYOND 516.1687 on Windows. No DreamDaemon was started.

`callee_parameters` checks `/callee` parameter restriction flags (0), source flags, and the argument read.
`builtin_callee` checks Callee (0xfff1), Caller (0xfff0), direct and safe caller selectors, nested safe-chain receiver preservation, typed callee parameters, and a parameter that shadows the builtin name. Native rejects a local declaration named callee as a builtin conflict; the fixture contains only valid source.
