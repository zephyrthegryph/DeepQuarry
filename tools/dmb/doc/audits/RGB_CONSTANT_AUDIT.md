# RGB constant conformance

`fixtures/translation/numeric_rgb_constants` contains DM/DME source, fresh
OpenDream JSON, and the paired native DreamMaker DMB (`.native.bin`). Both
compilers target BYOND 516.1687. Its 673 explicitly declared constants cover:

- 624 HSV/HSL combinations, including saturation/value clamping, fractional
  components, wrapped hues, and huge positive hue.
- 29 signed hue values from ordinary degrees through +/-3e38. Native floating
  point sector wrapping is preserved; a prior 1e20 mismatch was stale export
  output, not a defect in the current sector implementation.
- 20 RGB/named-channel/alpha cases, including fractional and huge channels,
  omitted versus explicit-null alpha, and reordered HSV/HSL arguments.

Two confirmed compiler corrections are encoded in the fixture:

1. `rgb(1,2,3)` is `#010203`, whereas `rgb(1,2,3,null)` and named `a=null`
   are `#01020300`. Alpha presence is tracked independently of its nullable
   numeric value.
2. Named `l=50,s=100,h=60` is HSL `#ffff00`, regardless of argument order.
   A later h/s argument must not reinterpret lightness as HSV value.

Native compilation reports zero errors/warnings. The patched OpenDream compiler
reports four existing nonnumeric-alpha warnings while producing the correct
constants. Full translated class metadata matches the native fixture without
semantic discrepancies. The regression compares all three authored classes
in both debug modes and requires their 624/29/20 declaration counts.

Native constant compilation rejects null RGB components, fewer than three
arguments, and unknown/inconsistent color spaces tested here (99, -1, 0.5).
Those rejection probes are not included as native-valid constants; this does
not establish their runtime behavior. No DreamDaemon execution was used.