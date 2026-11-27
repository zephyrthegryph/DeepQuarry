//! The values the body walk infers (SpacemanDMM DreamChecker's `StaticType`, `Assumption`, `Analysis`), over the native model.
use dm::Location;
use foldhash::{HashSet, HashSetExt};

use super::model::{Model, TypeId};

#[derive(Debug, PartialEq, Clone)]
pub enum StaticType {
    None,
    Type(TypeId),
    List { list: TypeId, keys: Box<StaticType> },
    Proc,
}

impl StaticType {
    pub fn is_truthy(&self) -> bool {
        !matches!(*self, StaticType::None)
    }
    pub fn basic_type(&self) -> Option<TypeId> {
        match *self {
            StaticType::None | StaticType::Proc => None,
            StaticType::Type(t) => Some(t),
            StaticType::List { list, .. } => Some(list),
        }
    }
    pub fn strip_list(self) -> StaticType {
        if let StaticType::List { keys, .. } = self {
            *keys
        } else {
            StaticType::None
        }
    }
    pub fn strip_lists(mut self, n: usize) -> StaticType {
        for _ in 0..n {
            self = self.strip_list();
        }
        self
    }
    pub fn plain_list(m: &Model) -> StaticType {
        StaticType::List { list: m.expect("/list"), keys: Box::new(StaticType::None) }
    }
    pub fn list_of_type(m: &Model, of: &str) -> StaticType {
        StaticType::List { list: m.expect("/list"), keys: Box::new(StaticType::Type(m.expect(of))) }
    }
    pub fn is_list(&self, m: &Model) -> bool {
        match *self {
            StaticType::Type(t) => m.ty(t).path == "/list",
            StaticType::List { .. } => true,
            _ => false,
        }
    }
    /// SpacemanDMM's `{:?}` of its `StaticType` (a return type annotation's fix hint prints it): a type is `path(index)`.
    pub fn debug(&self, m: &Model) -> String {
        match self {
            StaticType::None => "None".into(),
            StaticType::Type(t) => format!("Type({}({}))", m.ty(*t).path, t.index()),
            StaticType::List { list, keys } => format!("List {{ list: {}({}), keys: {} }}", m.ty(*list).path, list.index(), keys.debug(m)),
            StaticType::Proc => "Proc".into(),
        }
    }
}

/// A constant an expression is known to have (SpacemanDMM's `Constant`, the forms a body's terms give).
#[derive(Debug, Clone, PartialEq)]
pub enum Value {
    Null,
    Float(f32),
    Str(String),
    Resource(String),
    /// A type path, by its pieces.
    Prefab(Vec<String>),
}

impl Value {
    /// SpacemanDMM's `Display` of the constant.
    pub fn display(&self) -> String {
        match self {
            Value::Null => "null".into(),
            Value::Float(n) => dm::lexer::FormatFloat(*n).to_string(),
            Value::Str(s) => dm::lexer::Quote(s).to_string(),
            Value::Resource(s) => format!("'{s}'"),
            Value::Prefab(path) => path.iter().map(|p| format!("/{p}")).collect(),
        }
    }
    /// SpacemanDMM's `{:?}` of the constant.
    pub fn debug(&self) -> String {
        match self {
            Value::Null => "Null(None)".into(),
            Value::Float(n) => format!("Float({n:?})"),
            Value::Str(s) => format!("String({s:?})"),
            Value::Resource(s) => format!("Resource({s:?})"),
            Value::Prefab(path) => format!("Prefab(Pop {{ path: {path:?}, vars: {{}} }})"),
        }
    }
    pub fn prefab_of(m: &Model, t: TypeId) -> Value {
        Value::Prefab(m.ty(t).path.split('/').skip(1).map(str::to_owned).collect())
    }
}

#[derive(Clone, Debug, Eq, PartialEq, Hash)]
pub enum Assumption {
    Truthy(bool),
    IsNull(bool),
    IsText(bool),
    IsNum(bool),
    IsType(bool, TypeId),
    IsPath(bool, TypeId),
}

#[derive(Clone, Debug, Default)]
pub struct AssumptionSet {
    pub set: HashSet<Assumption>,
}

#[macro_export]
#[doc(hidden)]
macro_rules! native_assumptions {
    ($($v:expr),* $(,)*) => {
        $crate::native::analysis::AssumptionSet { set: vec![$($v),*].into_iter().collect() }
    }
}
pub use native_assumptions as assumption_set;

impl AssumptionSet {
    pub fn from_value(m: &Model, value: &Value) -> AssumptionSet {
        match value {
            Value::Null => assumption_set![Assumption::IsNull(true), Assumption::Truthy(false)],
            Value::Str(val) => assumption_set![Assumption::IsText(true), Assumption::Truthy(!val.is_empty())],
            Value::Resource(_) => assumption_set![Assumption::Truthy(true)],
            Value::Float(val) => assumption_set![Assumption::IsNum(true), Assumption::Truthy(*val != 0.0)],
            Value::Prefab(path) => match m.type_by_path(path) {
                Some(ty) => assumption_set![Assumption::Truthy(false), Assumption::IsPath(true, ty)],
                None => AssumptionSet::default(),
            },
        }
    }
    pub fn from_valid_instance(ty: TypeId) -> AssumptionSet {
        assumption_set![Assumption::Truthy(true), Assumption::IsNull(false), Assumption::IsType(true, ty)]
    }
}

#[derive(Debug, Clone)]
pub struct Analysis {
    pub static_ty: StaticType,
    pub aset: AssumptionSet,
    pub value: Option<Value>,
    pub fix_hint: Option<(Location, String)>,
    pub is_impure: Option<bool>,
}

impl Analysis {
    pub fn empty() -> Analysis {
        Analysis { static_ty: StaticType::None, aset: AssumptionSet::default(), value: None, fix_hint: None, is_impure: None }
    }
    pub fn null() -> Analysis {
        Analysis { static_ty: StaticType::None, aset: assumption_set![Assumption::IsNull(true)], value: Some(Value::Null), fix_hint: None, is_impure: None }
    }
    pub fn from_static_type(ty: TypeId) -> Analysis {
        Analysis::from(StaticType::Type(ty))
    }
    pub fn from_static_type_impure(ty: TypeId) -> Analysis {
        let mut a = Analysis::from(StaticType::Type(ty));
        a.is_impure = Some(true);
        a
    }
    pub fn from_value(m: &Model, value: Value) -> Analysis {
        Analysis { static_ty: StaticType::None, aset: AssumptionSet::from_value(m, &value), value: Some(value), fix_hint: None, is_impure: None }
    }
    pub fn with_fix_hint<S: Into<String>>(mut self, location: Location, desc: S) -> Self {
        if location != Location::default() {
            self.fix_hint = Some((location, desc.into()));
        }
        self
    }
}

impl From<AssumptionSet> for Analysis {
    fn from(aset: AssumptionSet) -> Analysis {
        Analysis { static_ty: StaticType::None, aset, value: None, fix_hint: None, is_impure: None }
    }
}

/// Optimistic: assumes the static type is true and non-null.
impl From<StaticType> for Analysis {
    fn from(static_ty: StaticType) -> Analysis {
        let mut aset = AssumptionSet::default();
        if let Some(ty) = static_ty.basic_type() {
            aset.set.insert(Assumption::IsType(true, ty));
        }
        Analysis { aset, static_ty, fix_hint: None, value: None, is_impure: None }
    }
}

pub fn new_set() -> HashSet<Assumption> {
    HashSet::new()
}
