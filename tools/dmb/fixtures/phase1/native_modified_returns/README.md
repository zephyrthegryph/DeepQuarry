# Modified return grammar

Pinned BYOND 516.1687, one hidden compile per control, timeout 60 seconds,
no DreamDaemon. All copied sources, native outputs and logs are SHA-bound.

* bare: root `return /obj/base{amount=1}` rejects `amount: undefined var`
  at line5, one error and no warnings. Base type really declares amount.
* outer_visible: a class proc whose lexical class also declares amount
  rejects bare return modifiers with `amount: bad variable` at line7.
* grouped: `return (/obj/base{amount=1})` compiles with no diagnostics.
  Procedure0 /proc/p has words `[0x60,41,0,0x12,0]`: modified descriptor0,
  return, end. Descriptor0 is kind9, class0, initializer68.

The parser must not treat unparenthesized return braces as modified values.
Parentheses already protect valid expression braces from block splitting.
These controls certify compilation grammar and encoding only.
