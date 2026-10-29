//! Shared unchanged base_vars policy metadata.
use crate::{
    lint::{Meta, Policy, RuleMeta, ScanKind},
    tree::Select,
};
pub(crate) const BASELINE: &str = "tools/ci/base_vars_baseline.txt";

pub(crate) static META: Meta = Meta {
    name: "base_vars",
    group: "",
    label: "base_vars",
    legacy: "tools/ci/base_vars_lint.py",
    // The vars are parsed from `glob.glob` files (non-hidden); the singleton scan is `os.walk`.
    select: Select { roots: &[("code", "dm")], hidden: true },
    scan: ScanKind::Tree,
    policy: Policy::Sites {
        baseline: BASELINE,
        header: &[
            "Base-type vars and `= list()` instance vars (unified plan sec 2.16). rule<TAB>file<TAB>text.",
            "tools/ci/base_vars_lint.py fails on a site not listed here. A site with",
            "`// ALLOW(base_vars): <reason>` doesn't count.",
            "Shrink-only: after a sweep, `python tools/ci/base_vars_lint.py --update`.",
        ],
        banned: &["records_data_only", "hot_home"],
    },
    rules: &[
        RuleMeta {
            name: "base_var",
            hint: "don't add a var to a base type: a per-type constant is a trait block, client state a hud_element(), live state its domain or TRACKED, rare per-instance state a sparse() slot, a cooldown a cooldowns() name (COOLDOWN_DECLARE on a base type is banned), a reference owns_one/links()/slot() (or `// ALLOW(base_vars): <reason>`)",
        },
        RuleMeta { name: "list_init", hint: "use `var/list/x` + LAZYADD/LAZYLEN, or `var/static/list/x` for a shared table" },
        RuleMeta {
            name: "hot_home",
            hint: "a `base_var_home_hot` entry needs an existing base-type var and a justification of at least 40 characters that names the hot reader (file.dm and the proc); drop an entry whose var is gone",
        },
        RuleMeta {
            name: "records_data_only",
            hint: "a /datum/record holds data fields only: move the proc to the domain that uses the record (accessors `set_x`/`get_x` are fine)",
        },
    ],
    allow: &["base_vars", "instance_list"],
    lists: &["list_init_exempt_prefixes", "list_init_exempt_files", "base_var_home_macros", "base_var_home_relations", "base_var_home_types", "record_accessor_prefixes", "hot_ceiling"],
};
