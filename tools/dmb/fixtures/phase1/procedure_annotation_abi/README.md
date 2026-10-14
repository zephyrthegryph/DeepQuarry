# Procedure annotation ABI controls

Pinned compiler: BYOND 516.1687. Raw receipts are outside this checkout under
`D:/dmb-native-v2-phase0/{typed-formal-controls,return-annotation-controls}`.
No DreamDaemon run was performed.

* `typed-formals`: 0 errors, 0 warnings. Datum typed unsized parameters use
  argument restriction 0 and lexical list construction (tag 40), not element
  construction. Explicit typed iteration uses its separate authored loop type.
* `typed-formal-shape`: 0 errors, 0 warnings. `values[1] = new` constructs a list
  for both typed and untyped unsized list parameters. `values.len` is a list
  member. Obj and mob element families retain argument restriction bits 2 and 1;
  all observed source bytes are kind 1/parameter 125 with fourth word 0.
* `return-positive`: 0 errors, 0 warnings. `as num`, `/datum/item`, `anything`,
  and `num|null` retain flags 4, source kind 0/parameter 255, absent category and
  description. Returning numeric 1 produces exactly PushInt 1, Ret, End for
  every annotated and unannotated case, without value coercion.
* `return-rejected`: 3 expected errors. Return annotation does not supply an
  implicit `return new` construction type; arbitrary atomic name `mystery` is
  rejected. Additional external grammar controls reject parenthesized unions,
  unknown absolute paths, and unrecognized atomic names such as `void`.

The backend admits observed atomic/path union syntax, requires each path's
positive captured type value, and keeps source annotation identity. It does
not infer return-value checks or implicit new contexts. Sized/mixed formal
arrays and declaration modifiers remain explicit unsupported boundaries.
