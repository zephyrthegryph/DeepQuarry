# Native class names and display text

Twenty-eight authored classes compile under DreamMaker 516.1687 without warnings. Tests compare dedicated name/text bytes in both debug modes and ordinary datum name/text defaults separately.

Appearance names inherit authored ancestor values, while ordinary datum `var/name` and `var/text` remain variables and do not replace dedicated class header defaults. Null ordinary name values remain null. Root appearance classes also derive their text from authored names.

Native derived text is one raw byte from the effective name after proper/improper control prefixes (`FF15`/`FF16`), not a Unicode character. Therefore `éclair` produces byte `C3`; explicit text is preserved and an explicit null text remains absent. Leading spaces and empty names are preserved.

Native compilation and fixture snapshots completed. Translated paired regression remains pending the coordinated build.

Image and mutable appearance descendants retain absent implicit names/text; their authored names do not synthesize display text. Explicit text and explicit empty names remain inherited, and null image names reset to absent rather than a type leaf.
