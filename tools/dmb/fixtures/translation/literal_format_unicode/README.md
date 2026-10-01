# Literal format-range Unicode

Fresh BYOND516.1687 native compile, no runtime. Literal fullwidth charactersＡ/２/～ remain UTF-8; escaped ellipsis remainsFF12. Normal, raw andUnicode-escaped strings share literal identity. Ten authored procedure bodies and class defaults are compared in both debug modes. The exporter usesFF5E as a literal-character prefix before string interning; this prevents literalUnicode and native controls from sharing aStringID.

The source filename itself contains fullwidth characters; debug-mode emission must preserve its UTF-8 bytes. Standard MD5 calls with fully literal constant strings fold over their decoded UTF-8 bytes, including the class-default ASCII, Unicode, concatenated and Unicode-escaped controls. Runtime MD5 uses a parameter with a Unicode default to preserve its native runtime body.
