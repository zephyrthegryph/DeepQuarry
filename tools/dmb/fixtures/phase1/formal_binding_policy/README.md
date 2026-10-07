# Formal binding/source policy controls

Pinned compiler BYOND 516.1687; compile-only receipts outside the checkout at
`D:/dmb-native-v2-phase0/argument-source-controls`. No DreamDaemon was run.

`positive` and `readonly-positive`: 0 errors, 0 warnings.

* Dynamic `mob/M as mob in oview(src)` uses argument source 0x40 and an
  anonymous source helper (reference[0]=71): GetVar Src, PushNull, OView, Ret,
  End. The ordinary argument restriction is mob bit 1.
* `/callee` formal uses flags 0 and ordinary source 1/parameter 125. The
  lexical `/callee` type is retained rather than substituted by `/datum`.
* Const scalar/list formals likewise use restriction 0 and source 1/125.
  Const is a binding constraint, not a procedure flag or payload freeze.
* A const list's indexed payload and a distinct src.value field remain writable.

`readonly-rejected`: six expected `cannot change constant value` errors for
assignment, compound assignment, increment, decrement, foreach rebinding and
range rebinding. An additional external shadow control rejects a new local
with the same spelling as a formal; that is not used to claim shadow acceptance.

Backend guards use the exact resolved argument slot. Ordinary local slots and
field/index destinations are distinct domains. Parameter defaults initialize
bindings normally; subsequent source writes are rejected. Other declaration
modifiers and invalid numeric radii remain unsupported explicitly.
