use super::*;
use std::cell::RefCell;
#[derive(Default)]
struct Host {
    calls: RefCell<Vec<&'static str>>,
    local: Option<u32>,
    argument: Option<u32>,
    stored: Option<SymRef>,
    member: Option<SymRef>,
    field: bool,
    global: bool,
    global_slot: Option<SymRef>,
    failure: Option<&'static str>,
}
impl Host {
    fn called<T>(&self, name: &'static str, value: T) -> Result<T, &'static str> {
        self.calls.borrow_mut().push(name);
        if self.failure == Some(name) {
            Err(name)
        } else {
            Ok(value)
        }
    }
}
impl VariableContext for Host {
    type Error = &'static str;
    fn local(&self, _: &str) -> Option<u32> {
        self.calls.borrow_mut().push("local");
        self.local
    }
    fn argument(&self, _: &str) -> Option<u32> {
        self.calls.borrow_mut().push("argument");
        self.argument
    }
    fn procedure_static(&self, _: &str) -> Result<Option<SymRef>, Self::Error> {
        self.called("procedure_static", self.stored)
    }
    fn member_shared(&self, _: &str) -> Result<Option<SymRef>, Self::Error> {
        self.called("member_shared", self.member)
    }
    fn has_instance_field(&self, _: &str) -> Result<bool, Self::Error> {
        self.called("field", self.field)
    }
    fn has_global(&self, _: &str) -> Result<bool, Self::Error> {
        self.called("global", self.global)
    }
    fn global_storage(&self, _: &str) -> Result<Option<SymRef>, Self::Error> {
        self.called("global_storage", self.global_slot)
    }
    fn receiver_owner(&self) -> Option<SymbolId> {
        Some(SymbolId::of("/datum/owner"))
    }
}
#[test]
fn authoritative_precedence_and_probe_order_are_shared_without_speculative_fallbacks() {
    let slot = SymRef::VariableSlot(SymbolId::of("slot"));
    for (host, name, expected, calls) in [
        (
            Host {
                local: Some(3),
                argument: Some(0),
                stored: Some(slot),
                ..Default::default()
            },
            "src",
            SelectedMeaning::Local(3),
            vec!["local"],
        ),
        (
            Host {
                argument: Some(0),
                stored: Some(slot),
                ..Default::default()
            },
            "src",
            SelectedMeaning::Argument(0),
            vec!["local", "argument"],
        ),
        (
            Host {
                stored: Some(slot),
                ..Default::default()
            },
            "src",
            SelectedMeaning::SharedStorage(slot),
            vec!["local", "argument", "procedure_static"],
        ),
        (
            Host {
                member: Some(slot),
                ..Default::default()
            },
            "value",
            SelectedMeaning::SharedStorage(slot),
            vec!["local", "argument", "procedure_static", "member_shared"],
        ),
        (
            Host {
                member: Some(slot),
                ..Default::default()
            },
            "src",
            SelectedMeaning::Builtin(SelectedBuiltin::Src),
            vec!["local", "argument", "procedure_static"],
        ),
        (
            Host {
                field: true,
                global: true,
                ..Default::default()
            },
            "value",
            SelectedMeaning::InstanceField {
                owner: Some(SymbolId::of("/datum/owner")),
                name: SymbolId::of("value"),
            },
            vec![
                "local",
                "argument",
                "procedure_static",
                "member_shared",
                "field",
            ],
        ),
        (
            Host {
                global: true,
                global_slot: Some(slot),
                ..Default::default()
            },
            "value",
            SelectedMeaning::SharedStorage(slot),
            vec![
                "local",
                "argument",
                "procedure_static",
                "member_shared",
                "field",
                "global",
                "global_storage",
            ],
        ),
    ] {
        assert_eq!(resolve_variable(&host, name), Ok(expected));
        assert_eq!(*host.calls.borrow(), calls);
    }
    let failing = Host {
        failure: Some("procedure_static"),
        ..Default::default()
    };
    assert_eq!(
        resolve_variable(&failing, "value"),
        Err(VariableResolutionError::Host("procedure_static"))
    );
    assert_eq!(
        *failing.calls.borrow(),
        vec!["local", "argument", "procedure_static"]
    );
    let missing = Host {
        global: true,
        ..Default::default()
    };
    assert_eq!(
        resolve_variable(&missing, "value"),
        Err(VariableResolutionError::MissingGlobalStorage)
    );
    assert_eq!(
        resolve_variable(&Host::default(), "value"),
        Err(VariableResolutionError::Unresolved)
    );
}
