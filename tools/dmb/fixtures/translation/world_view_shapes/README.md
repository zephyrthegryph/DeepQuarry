# Native world.view encoding

Compile-only paired probes and byondcore516.1687 disassembly establish:

- Numeric radius is checked in[-1,35] before truncating toward zero. The side is2*radius+1, packed into both bytes; radius-1 writesFFFF.
- Parser10299d80 uses decimal strtol, clamps negative axes tozero, requires lowercase x immediately after the first integer, permits leading ASCII whitespace and ignores trailing second-axis characters.
- Validator100c4fde..100c5007 limits each parsed axis to255 and product to5041.
- Setter100c6903 stores parsed axes and radius=max(axes)/2. Writer1024cf50 packs width/height if width is nonzero; otherwise writes that radius. Thus0x10 writes0005, -1x15 writes0007, and10x0 writes0A00.

Native invalid inputs include numeric-1.5/35.5, axes256, product71*72, uppercase X and fractional first component. Portable valid cases retain native binaries and actual OpenDream exports. No runtime execution was used.

Loader1024c6d1..1024c723 interprets the serialized word using a **signed** comparison with255. Words0..255 and negative signed words (includingFFFF=-1) are radius forms; positive words256..32767 are packed dimensions. Radius dimensions are2*r+1 with signed16-bit wrapping. This includes the native compiler's surprising accepted widths>=128: their negative serialized words enter the compact-radius loader branch. The public raw field and legacy raw-byte view_size accessor retain wire compatibility; WorldViewEncoding/view_encoding/native_view_size expose the verified interpretation without guessing away this behavior.
