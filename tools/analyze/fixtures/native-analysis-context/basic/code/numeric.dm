#if 1 / 2 != 0.5
#error original division must retain fractional f32 values
#endif
#if 16777216 + 1 != 16777216
#error original arithmetic must round at f32 precision
#endif
#if ~0 != 16777215
#error original integer operations must retain the 24-bit mask
#endif
#if (2 || 3) != 2 || (2 && 3) != 3
#error original logical operators must return operands
#endif
#if null == 0
#error original null and numeric zero must remain different constants
#endif
/datum/context_numeric_semantics
