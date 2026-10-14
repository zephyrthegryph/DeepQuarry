use super::*;
use std::cell::RefCell;

#[derive(Default)]
struct Host {
    calls: RefCell<Vec<String>>,
    local: Option<Option<&'static str>>,
    stored: Option<Option<&'static str>>,
    field: bool,
    member_proc: bool,
    fail: Option<&'static str>,
}
impl Host {
    fn observe<T>(&self, call: &str, value: T) -> Result<T, &'static str> {
        self.calls.borrow_mut().push(call.to_owned());
        if self.fail == Some(call) {
            Err("host failure")
        } else {
            Ok(value)
        }
    }
}
impl ReceiverTypeContext for Host {
    type Error = &'static str;
    fn current_type_path(&self) -> Option<&str> {
        Some("/datum/current")
    }
    fn semantic_queries_available(&self) -> bool {
        true
    }
    fn local_type(&self, _: &str) -> Option<Option<&str>> {
        self.calls.borrow_mut().push("local".into());
        self.local
    }
    fn argument_type(&self, _: &str) -> Option<Option<&str>> {
        self.calls.borrow_mut().push("argument".into());
        None
    }
    fn procedure_static_type(&self, _: &str) -> Result<Option<Option<String>>, Self::Error> {
        self.observe("static", self.stored.map(|v| v.map(str::to_owned)))
    }
    fn has_member_field(&self, _: &str, _: &str) -> Result<bool, Self::Error> {
        self.observe("has_field", self.field)
    }
    fn field_type(&self, _: &str) -> Result<Option<String>, Self::Error> {
        self.observe("field_type", None)
    }
    fn global_type(&self, _: &str) -> Result<Option<String>, Self::Error> {
        self.observe("global_type", Some("/datum/global".into()))
    }
    fn member_type(&self, _: &str, _: &str) -> Result<Option<String>, Self::Error> {
        self.observe("member_type", Some("/datum/member".into()))
    }
    fn is_intrinsic(&self, _: &str) -> bool {
        self.calls.borrow_mut().push("intrinsic".into());
        false
    }
    fn has_member_proc(&self, _: &str, _: &str) -> Result<bool, Self::Error> {
        self.observe("has_proc", self.member_proc)
    }
    fn procedure_return_type(&self, query: ResolveQuery) -> Result<Option<String>, Self::Error> {
        let call = match query {
            ResolveQuery::Proc { .. } => "proc_return",
            ResolveQuery::GlobalProc(_) => "global_return",
            _ => panic!("unexpected query"),
        };
        self.observe(call, Some("/datum/result".into()))
    }
    fn normalize_type(&self, path: &str) -> Result<String, Self::Error> {
        self.observe(&format!("normalize:{path}"), path.to_owned())
    }
}
fn expression(source: &str) -> Expr {
    let parsed = dm_syntax::parse_expression(source);
    assert!(
        parsed.diagnostics.is_empty(),
        "{source}: {:?}",
        parsed.diagnostics
    );
    parsed.expr.unwrap()
}

#[test]
fn untyped_nearer_bindings_stop_lookup_and_static_answers_do_not_add_normalization() {
    for (host, result, calls) in [
        (
            Host {
                local: Some(None),
                ..Default::default()
            },
            None,
            vec!["local"],
        ),
        (
            Host {
                stored: Some(Some("/datum/stored")),
                ..Default::default()
            },
            Some("/datum/stored"),
            vec!["local", "argument", "static"],
        ),
        (
            Host {
                field: true,
                ..Default::default()
            },
            None,
            vec!["local", "argument", "static", "has_field", "field_type"],
        ),
    ] {
        assert_eq!(
            infer_receiver_type(&host, &expression("value"))
                .unwrap()
                .as_deref(),
            result
        );
        assert_eq!(*host.calls.borrow(), calls);
    }
}

#[test]
fn call_precedence_group_observations_and_error_short_circuit_remain_exact() {
    for (host, source, calls) in [
        (
            Host {
                member_proc: true,
                ..Default::default()
            },
            "work()",
            vec!["intrinsic", "has_proc", "proc_return"],
        ),
        (
            Host::default(),
            "work()",
            vec![
                "intrinsic",
                "has_proc",
                "global_return",
                "normalize:/datum/result",
            ],
        ),
        (
            Host::default(),
            "(src)",
            vec!["normalize:/datum/current", "normalize:/datum/current"],
        ),
        (Host::default(), "src:field", vec![]),
    ] {
        infer_receiver_type(&host, &expression(source)).unwrap();
        assert_eq!(*host.calls.borrow(), calls);
    }
    let host = Host {
        fail: Some("has_field"),
        ..Default::default()
    };
    assert_eq!(
        infer_receiver_type(&host, &expression("value")),
        Err("host failure")
    );
    assert_eq!(
        *host.calls.borrow(),
        vec!["local", "argument", "static", "has_field"]
    );
}
