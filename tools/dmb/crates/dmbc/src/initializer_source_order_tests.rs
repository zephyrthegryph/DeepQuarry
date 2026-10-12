//! Current issued source ordering; this is not a BYOND runtime equivalence gate.
use dm_ir::{InitializerTarget, SymbolId};
use std::path::Path;
struct Source<'a> {
    first: &'a str,
    second: &'a str,
    reverse: bool,
}
impl dm_preprocess::SourceProvider for Source<'_> {
    fn read(&self, path: &Path) -> Result<String, String> {
        match path.file_name().and_then(|name| name.to_str()) {
            Some("project.dme") => Ok(if self.reverse {
                "#include \"second.dm\"\n#include \"first.dm\"\n"
            } else {
                "#include \"first.dm\"\n#include \"second.dm\"\n"
            }
            .into()),
            Some("first.dm") => Ok(self.first.into()),
            Some("second.dm") => Ok(self.second.into()),
            _ => Err(format!("unexpected source read: {}", path.display())),
        }
    }
}
#[test]
fn initializer_ledger_preserves_current_include_order_for_dependent_instance_writes() {
    for reverse in [false, true] {
        let frontend = dm_tree::frontend::build(
            Path::new("project.dme"),
            &Source {
                first: "/datum/order/var/first = 7\n",
                second: "/datum/order/var/second = first + 1\n",
                reverse,
            },
            &Default::default(),
            1,
        )
        .unwrap();
        let plan =
            dm_tree::initializers::plan(&frontend.snapshot, &frontend.emission_order).unwrap();
        let names: Vec<_> = plan
            .writes
            .iter()
            .filter_map(|write| match write.target {
                InitializerTarget::Instance { name, .. } => Some(name),
                _ => None,
            })
            .collect();
        let mut expected = vec![SymbolId::of("first"), SymbolId::of("second")];
        if reverse {
            expected.reverse();
        }
        assert_eq!(
            names, expected,
            "current source projection must not sort dependent writes by member identity"
        );
        assert_eq!(plan.writes.len(), plan.origins.len());
        assert!(
            plan.origins
                .windows(2)
                .all(|pair| pair[0].emission_ordinal < pair[1].emission_ordinal)
        );
    }
}
