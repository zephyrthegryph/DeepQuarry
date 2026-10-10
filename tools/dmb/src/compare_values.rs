use super::*;

#[path = "compare_global_variables.rs"]
mod globals;

#[derive(Clone, Debug, Eq, PartialEq)]
pub(super) enum NormalValue {
    Null,
    Number(u32),
    String(Option<Vec<u8>>),
    Type(u8, Option<Vec<u8>>),
    InstanceType(u8, Option<Vec<u8>>, InstanceInitializer),
    Proc(Option<Vec<u8>>),
    Resource(Option<(u8, u32)>),
    /// Compiler allocation identity for a runtime initializer, not a table ID.
    HiddenInitializer,
    Raw(Value),
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub(super) enum InstanceInitializer {
    Absent,
    Constants(String),
    // Preserve the allocation and wire body when constant semantics are unknown.
    Opaque(u32, Option<Vec<u32>>),
}

pub(super) fn value(dmb: &Dmb, value: Value) -> NormalValue {
    match value.kind() {
        ValueKind::Null => NormalValue::Null,
        ValueKind::Number => NormalValue::Number(value.number_bits().unwrap_or(0)),
        ValueKind::String => NormalValue::String(bytes(dmb, value.id())),
        ValueKind::MobPath => NormalValue::Type(
            value.tag(),
            dmb.mobs
                .get(value.id() as usize)
                .and_then(|mob| path(dmb, mob.class)),
        ),
        ValueKind::ClientPath if value.id() == 0 => {
            NormalValue::Type(value.tag(), Some(b"/client".to_vec()))
        }
        ValueKind::ClientPath => NormalValue::Raw(value),
        // Native list/file/savefile type constants carry a zero singleton payload,
        // independent of whichever class happens to occupy table slot zero.
        ValueKind::ListPath if value.id() == 0 => {
            NormalValue::Type(value.tag(), Some(b"/list".to_vec()))
        }
        ValueKind::FilePath if value.id() == 0 => {
            NormalValue::Type(value.tag(), Some(b"/file".to_vec()))
        }
        ValueKind::SavefilePath if value.id() == 0 => {
            NormalValue::Type(value.tag(), Some(b"/savefile".to_vec()))
        }
        ValueKind::MovablePath
        | ValueKind::AtomPath
        | ValueKind::AreaPath
        | ValueKind::DatumPath
        | ValueKind::SavefilePath
        | ValueKind::FilePath
        | ValueKind::ListPath
        | ValueKind::ImagePath
        | ValueKind::BuiltinPath => NormalValue::Type(value.tag(), path(dmb, value.id())),
        ValueKind::InstanceTypePath => {
            let Some(instance) = dmb.instances.get(value.id() as usize) else {
                return NormalValue::Raw(value);
            };
            let class = if instance.kind == 8 {
                dmb.mobs.get(instance.class as usize).map(|mob| mob.class)
            } else {
                Some(instance.class)
            };
            let initializer = if instance.initializer == 0xffff {
                InstanceInitializer::Absent
            } else if let Some(assignments) = constant_map_assignments(dmb, instance.initializer) {
                InstanceInitializer::Constants(format!("{assignments:?}"))
            } else {
                InstanceInitializer::Opaque(
                    instance.initializer,
                    dmb.proc_code_words(instance.initializer as usize)
                        .map(<[u32]>::to_vec),
                )
            };
            NormalValue::InstanceType(
                instance.kind,
                class.and_then(|id| path(dmb, id)),
                initializer,
            )
        }
        ValueKind::ProcPath => NormalValue::Proc(proc_path(dmb, value.id())),
        ValueKind::Resource => NormalValue::Resource(
            dmb.resources
                .get(value.id() as usize)
                .map(|r| (r.kind, r.id)),
        ),
        ValueKind::HiddenInitializer => NormalValue::HiddenInitializer,
        _ => NormalValue::Raw(value),
    }
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub(super) enum NormalVariable {
    Field(Option<Vec<u8>>),
    Global(Option<Vec<u8>>),
    InvalidGlobal(&'static str, u32, Option<u32>),
    DynamicProc(Option<Vec<u8>>),
    DynamicVerb(Option<Vec<u8>>),
    StaticProc(Option<Vec<u8>>),
    StaticVerb(Option<Vec<u8>>),
    Named(&'static str),
    Indexed(&'static str, u32),
    Nested(
        &'static str,
        Box<NormalVariable>,
        Option<Box<NormalVariable>>,
    ),
}

pub(super) fn variable(dmb: &Dmb, input: &Variable) -> NormalVariable {
    use Variable::*;
    match input {
        Field(id) => NormalVariable::Field(bytes(dmb, *id)),
        Global(id) => globals::normalize(dmb, *id),
        DynamicProc(id) => NormalVariable::DynamicProc(bytes(dmb, *id)),
        DynamicVerb(id) => NormalVariable::DynamicVerb(bytes(dmb, *id)),
        StaticProc(id) => {
            // The native VM converts ProcID to its descriptor's display StringID
            // before entering the same receiver/name dispatcher as DynamicProc.
            // Invalid/missing names retain a distinct form instead of matching None.
            dmb.procs
                .get(*id as usize)
                .and_then(|proc| optional_proc_string(dmb, proc.strings[1]))
                .map_or_else(
                    || NormalVariable::StaticProc(proc_path(dmb, *id)),
                    |display| NormalVariable::DynamicProc(Some(display)),
                )
        }
        StaticVerb(id) => {
            // Like StaticProc, the VM reads descriptor+4 before name dispatch,
            // but verb modes 1/9 remain distinct from proc modes 2/10.
            dmb.procs
                .get(*id as usize)
                .and_then(|proc| optional_proc_string(dmb, proc.strings[1]))
                .map_or_else(
                    || NormalVariable::StaticVerb(proc_path(dmb, *id)),
                    |display| NormalVariable::DynamicVerb(Some(display)),
                )
        }
        Arg(id) => NormalVariable::Indexed("arg", *id),
        Local(id) => NormalVariable::Indexed("local", *id),
        SetCache(left, right) => NormalVariable::Nested(
            "set-cache",
            Box::new(variable(dmb, left)),
            Some(Box::new(variable(dmb, right))),
        ),
        Initial(inner) => NormalVariable::Nested("initial", Box::new(variable(dmb, inner)), None),
        IsSaved(inner) => NormalVariable::Nested("is-saved", Box::new(variable(dmb, inner)), None),
        Usr => NormalVariable::Named("usr"),
        Src => NormalVariable::Named("src"),
        Args => NormalVariable::Named("args"),
        Dot => NormalVariable::Named("dot"),
        Cache => NormalVariable::Named("cache"),
        CacheKey => NormalVariable::Named("cache-key"),
        CacheIndex => NormalVariable::Named("cache-index"),
        World => NormalVariable::Named("world"),
        Caller => NormalVariable::Named("caller"),
        Callee => NormalVariable::Named("callee"),
        Null => NormalVariable::Named("null"),
    }
}
