# Untyped field vs typed global namespace

Pinned BYOND 516.1687 hidden compile-only control, 60-second watchdog: 0 errors,
0 warnings. A source instance field `value_ref` is untyped; the same-name global
has declared type `/datum/global_kind`. `return new value_ref()` reads the nearer
instance field, not the typed global. Proc 0 begins GetVar
`[65500,65486,438]` (cache/src/field name), then NEW0/RET/END. Raw receipt/artifacts:
`D:/dmb-native-v2-phase0/untyped-field-shadow-control` outside the checkout.

A separate untyped `.value` member control was rejected by the reference compiler,
with and without the global. It is not evidence for accepting unknown dot members.
The resolver regression uses a supported dynamic-constructor read instead.