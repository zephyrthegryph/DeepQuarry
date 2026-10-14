# Observable procedure order

The pinned discovery receipt records BYOND 516.1687's `typesof(/type/proc)`
sequence for nonalphabetical declarations, an override, and a derived type.
Both runtimes must independently match that sequence without errors.

The initial native output had different enumeration despite an encounter-ordered
method footer. Its procedure table was allocated by symbolic hash order. The
native linker now receives the current declaration-issued procedure allocation
roster and appends only generated initializer/argument-helper domains.

This checks observable enumeration, not whole-program byte or runtime parity.
The original failed discovery receipt remains unchanged.
