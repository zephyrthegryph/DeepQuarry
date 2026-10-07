# Native modified-instance controls

Pinned compiler: BYOND 516.1687. `receipt.json` binds the compiler and every
captured input, binary and diagnostic log by SHA256. Each compile ran alone,
hidden, with a 60-second timeout; no DreamDaemon was run.

## Positive observations

`positive_final` compiles with two unused-local warnings. Global `a`, global
`b`, the outer class default, and both procedure locals share descriptor 0
for `/obj/base{amount=1}`. Global `c` and `d` share descriptor 1 despite
opposite assignment order. Descriptor 0 is instance kind 9, class 0,
initializer procedure 70; descriptor 1 is kind 9, class 0, initializer 69.
Procedure 69 writes amount=1 then other=2; procedure 70 writes amount=1.
Defaults and local PushVal instructions use modified-instance tag 41.

`datum_reordered` compiles without diagnostics. Reversing two distinct fields
again shares descriptor 0 (kind 32, class 0, initializer 68). Repeating the
same field, amount=1 then amount=2, produces descriptor 1 / initializer 67
and retains both writes. Both defaults use tag 41. Instance kind, rather
than that tag, distinguishes datum from obj.

`static_field-corrected` and `const_field-corrected` both compile without
diagnostics. Their initializer 67 writes Src.amount through SetVar with
the same encoding as an ordinary modified field. This establishes legality
and encoding, not the runtime effect of modifying a shared or const field.

## Negative observations

`outer_field-corrected` rejects `only_outer: undefined var`, even though
the surrounding lexical class declares that field. `outer_constant-corrected`
similarly rejects `ONLY_OUTER: undefined var`.

`receiver_constant` and `lexical_constant` both reject `C: bad constant`.
Having receiver C=7 and surrounding C=9 does not make bare C a valid modified
initializer constant. These controls do not establish an alternate scoped
constant lookup rule.

Initial exploratory controls are retained externally in the evidence directory;
they redeclared builtin x/y or used return syntax that did not admit modifiers.
Only the corrected, individually captured controls above support these facts.
