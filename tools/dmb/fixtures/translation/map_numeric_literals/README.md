Paired native 516.1687 map numeric initializer controls: -26, 65535, 65536,
negative zero, and +26. Pixel overrides additionally reproduce the translated
lighting failure: compact PushInt zero-extends a WORD, so emitting -26 through
that opcode yields 65510 and the builtin pixel setter clamps it to 32767.
The integration test compares native map assignments in both debug modes and
rejects an explicitly corrupted old-style negative compact initializer.
