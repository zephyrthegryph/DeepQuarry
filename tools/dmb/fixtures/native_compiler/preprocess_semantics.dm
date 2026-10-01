#define VALUE 17
#define ALIAS VALUE
#define STRINGIFY(x) #x
#define EXPAND_STRINGIFY(x) STRINGIFY(x)
#define JOIN(x, y) x##y
#define MAKE_NAME(x) JOIN(preproc_, x)
#define CHOOSE(x) (x)
#define FORWARD(x) x
#define IS_DEFINED(x) defined(x)
#if CHOOSE(VALUE) == 17
#define BRANCH "conditional_yes"
#else
#define BRANCH "conditional_no"
#endif
#if IS_DEFINED(VALUE)
#define DEFINED_BRANCH "defined_yes"
#else
#define DEFINED_BRANCH "defined_no"
#endif
#if CHOOSE(ALIAS) == CHOOSE(VALUE)
#define NESTED_BRANCH "nested_yes"
#else
#define NESTED_BRANCH "nested_no"
#endif

/proc/preprocess_semantics()
    var/preproc_ALIAS = 7
    return list(STRINGIFY(VALUE), EXPAND_STRINGIFY(VALUE), MAKE_NAME(ALIAS), __FILE__, __LINE__, FORWARD(__FILE__), FORWARD(__LINE__), BRANCH, NESTED_BRANCH, DEFINED_BRANCH)
