# Native TRUE/FALSE source-name controls

Pinned compiler: BYOND 516.1687. Raw receipts under
`D:/dmb-native-v2-phase0/return-annotation-controls`; no DreamDaemon run.

* `bools-positive`: 0 errors, 0 warnings; root TRUE+FALSE folds to PushInt 1,
  child FALSE is accepted.
* `bools-define`: 0 errors, 0 warnings; explicit TRUE=5 and FALSE=9 definitions
  fold to PushInt 14.
* `bools-undef`: 0 errors, 0 warnings; despite undef directives, TRUE+FALSE
  still folds to PushInt 1. These observations do not establish whether the
  underlying fallback is compiler intrinsic constants or special macros.
* `bools-shadow`: one expected error `No such node: const/1` for authored
  var/const/TRUE, demonstrating default substitution before declaration parsing.
* `bools`: one expected error `returnglobal.1: undefined var` for global.TRUE.
  Other unqualified root/child references in that source had no errors.

User macro replacement is observed. Undef is not certified to produce an
undefined-name error; no runtime-variable or engine-slot identity is inferred.
