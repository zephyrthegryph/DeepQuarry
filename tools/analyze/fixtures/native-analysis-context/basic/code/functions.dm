/proc/context_exception_probe()
    return EXCEPTION("pinned old context")
/proc/context_assert_probe(value)
    ASSERT(value)
    return __FILE__
/proc/context_line_probe()
    return EXCEPTION(
		__LINE__
    )

#define CONTEXT_LINE_ID(value) (value)
/proc/context_line_tail_probe()
    return CONTEXT_LINE_ID(
		__LINE__
    ) + __LINE__
#undef CONTEXT_LINE_ID
