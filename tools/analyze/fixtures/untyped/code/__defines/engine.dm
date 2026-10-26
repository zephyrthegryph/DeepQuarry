// Markers expand to nothing (the analysis engine reads them from text).
#define CAPABILITIES(T) ##T/__capabilities()
#define TRUE 1
#define FALSE 0
#define SCHEMA(T, V, SCHEMA_EXPR, opts...)
#define PROC_REF(X) (nameof(.proc/##X))
#define TYPE_PROC_REF(TYPE, X) (nameof(##TYPE.proc/##X))
#define GLOBAL_PROC_REF(X) (/proc/##X)
