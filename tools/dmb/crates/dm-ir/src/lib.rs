//! Compiler-owned intermediate representations. These structures contain symbolic
//! references, never DMB table offsets or Salsa handles. They can be cached or
//! inspected without depending on a particular BYOND output layout.

use std::collections::BTreeSet;
use std::fmt;

macro_rules! id {
    ($name:ident) => {
        #[derive(Clone, Copy, Debug, Default, PartialEq, Eq, PartialOrd, Ord, Hash)]
        pub struct $name(pub u32);
        impl $name {
            pub const fn index(self) -> usize {
                self.0 as usize
            }
        }
    };
}

id!(FileId);
id!(TypeId);
id!(VarId);
id!(ProcId);
id!(LocalId);
id!(BlockId);
id!(ValueId);

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, Hash)]
pub struct Span {
    pub file: FileId,
    pub start: u32,
    pub end: u32,
}

impl Span {
    pub fn new(file: FileId, start: u32, end: u32) -> Result<Self, &'static str> {
        if end < start {
            return Err("span end precedes start");
        }
        Ok(Self { file, start, end })
    }
}

/// A canonical absolute DM path. Root is `/`; components are nonempty and
/// separated by one slash. This is a semantic key, not a source spelling.
#[derive(Clone, Debug, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub struct TypePath(String);

impl TypePath {
    pub fn parse(path: &str) -> Result<Self, &'static str> {
        if !path.starts_with('/') {
            return Err("type path must be absolute");
        }
        if path == "/" {
            return Ok(Self(path.into()));
        }
        if path.ends_with('/') || path.split('/').skip(1).any(str::is_empty) {
            return Err("type path contains an empty component");
        }
        Ok(Self(path.into()))
    }

    pub fn as_str(&self) -> &str {
        &self.0
    }

    pub fn parent(&self) -> Option<Self> {
        if self.0 == "/" {
            return None;
        }
        let slash = self.0.rfind('/').expect("absolute path");
        Some(Self(if slash == 0 {
            "/".into()
        } else {
            self.0[..slash].into()
        }))
    }

    pub fn name(&self) -> &str {
        if self.0 == "/" {
            "/"
        } else {
            self.0.rsplit('/').next().unwrap()
        }
    }
}

impl fmt::Display for TypePath {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        self.0.fmt(f)
    }
}

#[derive(Clone, Debug, PartialEq)]
pub enum Constant {
    Null,
    Boolean(bool),
    Number(f32),
    String(String),
    Path(TypePath),
    Resource(String),
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum NameRef {
    Local(LocalId),
    Field(VarId),
    Global(VarId),
    Proc(ProcId),
    Type(TypeId),
    Dynamic(String),
}

#[derive(Clone, Debug, PartialEq)]
pub struct HirExpr {
    pub kind: HirExprKind,
    pub span: Span,
}

#[derive(Clone, Debug, PartialEq)]
pub enum HirExprKind {
    Constant(Constant),
    Name(NameRef),
    Unary {
        op: UnaryOp,
        value: Box<HirExpr>,
    },
    Binary {
        op: BinaryOp,
        left: Box<HirExpr>,
        right: Box<HirExpr>,
    },
    Assign {
        target: Box<HirExpr>,
        value: Box<HirExpr>,
    },
    Member {
        receiver: Box<HirExpr>,
        name: String,
        safe: bool,
    },
    Index {
        receiver: Box<HirExpr>,
        index: Box<HirExpr>,
    },
    Call {
        callee: Box<HirExpr>,
        args: Vec<CallArg>,
    },
    ParentCall {
        args: Vec<CallArg>,
    },
    New {
        path: Option<TypePath>,
        args: Vec<CallArg>,
    },
    List(Vec<CallArg>),
    Conditional {
        condition: Box<HirExpr>,
        then_value: Box<HirExpr>,
        else_value: Box<HirExpr>,
    },
}

#[derive(Clone, Debug, PartialEq)]
pub struct CallArg {
    pub name: Option<String>,
    pub value: HirExpr,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum UnaryOp {
    Not,
    Negate,
    BitNot,
    PreIncrement,
    PostIncrement,
    PreDecrement,
    PostDecrement,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum BinaryOp {
    Add,
    Subtract,
    Multiply,
    Divide,
    Modulo,
    Power,
    Equal,
    NotEqual,
    Equivalent,
    NotEquivalent,
    Less,
    LessEqual,
    Greater,
    GreaterEqual,
    And,
    Or,
    BitAnd,
    BitOr,
    BitXor,
    ShiftLeft,
    ShiftRight,
    In,
}

#[derive(Clone, Debug, PartialEq)]
pub struct HirStmt {
    pub kind: HirStmtKind,
    pub span: Span,
}

#[derive(Clone, Debug, PartialEq)]
pub enum HirStmtKind {
    Expr(HirExpr),
    Local {
        id: LocalId,
        initial: Option<HirExpr>,
    },
    Return(Option<HirExpr>),
    If {
        condition: HirExpr,
        then_body: Vec<HirStmt>,
        else_body: Vec<HirStmt>,
    },
    While {
        condition: HirExpr,
        body: Vec<HirStmt>,
    },
    For {
        init: Vec<HirStmt>,
        condition: Option<HirExpr>,
        step: Vec<HirStmt>,
        body: Vec<HirStmt>,
    },
    Break,
    Continue,
    Throw(HirExpr),
    Try {
        body: Vec<HirStmt>,
        catch_local: Option<LocalId>,
        catch_body: Vec<HirStmt>,
    },
    Spawn {
        delay: HirExpr,
        body: Vec<HirStmt>,
    },
    Sleep(HirExpr),
}

#[derive(Clone, Debug, PartialEq)]
pub struct HirProc {
    pub id: ProcId,
    pub owner: TypeId,
    pub parameters: Vec<LocalId>,
    pub body: Vec<HirStmt>,
    pub span: Span,
}

/// MIR uses explicit basic blocks and a distinct destination for every value.
/// Native stack slots and BYOND table IDs are selected in the backend.
#[derive(Clone, Debug, PartialEq)]
pub struct MirProc {
    pub id: ProcId,
    pub entry: BlockId,
    pub blocks: Vec<BasicBlock>,
    pub local_count: u32,
    pub value_count: u32,
}

#[derive(Clone, Debug, PartialEq)]
pub struct BasicBlock {
    pub instructions: Vec<MirInstruction>,
    pub terminator: Terminator,
}

#[derive(Clone, Debug, PartialEq)]
pub struct MirInstruction {
    pub result: Option<ValueId>,
    pub operation: Operation,
    pub span: Span,
}

#[derive(Clone, Debug, PartialEq)]
pub enum Operation {
    Constant(Constant),
    ReadLocal(LocalId),
    WriteLocal {
        local: LocalId,
        value: ValueId,
    },
    ReadName(NameRef),
    WriteName {
        name: NameRef,
        value: ValueId,
    },
    Unary {
        op: UnaryOp,
        value: ValueId,
    },
    Binary {
        op: BinaryOp,
        left: ValueId,
        right: ValueId,
    },
    ReadMember {
        receiver: ValueId,
        name: String,
    },
    WriteMember {
        receiver: ValueId,
        name: String,
        value: ValueId,
    },
    ReadIndex {
        receiver: ValueId,
        index: ValueId,
    },
    WriteIndex {
        receiver: ValueId,
        index: ValueId,
        value: ValueId,
    },
    Call {
        callee: ValueId,
        args: Vec<ValueId>,
    },
    ParentCall {
        args: Vec<ValueId>,
    },
    New {
        path: Option<TypePath>,
        args: Vec<ValueId>,
    },
    Sleep {
        ticks: ValueId,
    },
}

#[derive(Clone, Debug, PartialEq)]
pub enum Terminator {
    Goto(BlockId),
    Branch {
        condition: ValueId,
        then_block: BlockId,
        else_block: BlockId,
    },
    Return(Option<ValueId>),
    Throw(ValueId),
    Suspend {
        delay: ValueId,
        resume: BlockId,
    },
    Unreachable,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum MirError {
    EmptyProcedure,
    InvalidEntry(BlockId),
    InvalidTarget { from: BlockId, to: BlockId },
    InvalidLocal { block: BlockId, local: LocalId },
    InvalidValue { block: BlockId, value: ValueId },
    DuplicateValue(ValueId),
}

impl MirProc {
    /// Structural verification only. Dominance and cache-lifetime checks belong
    /// to the lowering/codegen verifier, where control-flow semantics are known.
    pub fn verify(&self) -> Result<(), Vec<MirError>> {
        let mut errors = Vec::new();
        if self.blocks.is_empty() {
            errors.push(MirError::EmptyProcedure);
        }
        if self.entry.index() >= self.blocks.len() {
            errors.push(MirError::InvalidEntry(self.entry));
        }
        let mut results = BTreeSet::new();
        for (index, block) in self.blocks.iter().enumerate() {
            let from = BlockId(index as u32);
            let target = |to: BlockId, errors: &mut Vec<MirError>| {
                if to.index() >= self.blocks.len() {
                    errors.push(MirError::InvalidTarget { from, to });
                }
            };
            let value = |v: ValueId, errors: &mut Vec<MirError>| {
                if v.0 >= self.value_count {
                    errors.push(MirError::InvalidValue {
                        block: from,
                        value: v,
                    });
                }
            };
            for instruction in &block.instructions {
                if let Some(result) = instruction.result {
                    value(result, &mut errors);
                    if !results.insert(result) {
                        errors.push(MirError::DuplicateValue(result));
                    }
                }
                match &instruction.operation {
                    Operation::ReadLocal(local) | Operation::WriteLocal { local, .. }
                        if local.0 >= self.local_count =>
                    {
                        errors.push(MirError::InvalidLocal {
                            block: from,
                            local: *local,
                        })
                    }
                    _ => {}
                }
                for operand in instruction.operation.operands() {
                    value(operand, &mut errors);
                }
            }
            match &block.terminator {
                Terminator::Goto(to) => target(*to, &mut errors),
                Terminator::Branch {
                    condition,
                    then_block,
                    else_block,
                } => {
                    value(*condition, &mut errors);
                    target(*then_block, &mut errors);
                    target(*else_block, &mut errors);
                }
                Terminator::Return(Some(v)) | Terminator::Throw(v) => value(*v, &mut errors),
                Terminator::Suspend { delay, resume } => {
                    value(*delay, &mut errors);
                    target(*resume, &mut errors);
                }
                Terminator::Return(None) | Terminator::Unreachable => {}
            }
        }
        if errors.is_empty() {
            Ok(())
        } else {
            Err(errors)
        }
    }
}

impl Operation {
    pub fn operands(&self) -> Vec<ValueId> {
        match self {
            Self::WriteLocal { value, .. }
            | Self::WriteName { value, .. }
            | Self::Unary { value, .. }
            | Self::Sleep { ticks: value } => vec![*value],
            Self::Binary { left, right, .. } => vec![*left, *right],
            Self::ReadMember { receiver, .. } => vec![*receiver],
            Self::WriteMember {
                receiver, value, ..
            } => vec![*receiver, *value],
            Self::ReadIndex { receiver, index } => vec![*receiver, *index],
            Self::WriteIndex {
                receiver,
                index,
                value,
            } => vec![*receiver, *index, *value],
            Self::Call { callee, args } => std::iter::once(*callee)
                .chain(args.iter().copied())
                .collect(),
            Self::ParentCall { args } | Self::New { args, .. } => args.clone(),
            Self::Constant(_) | Self::ReadLocal(_) | Self::ReadName(_) => vec![],
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn absolute_paths_and_parents() {
        let path = TypePath::parse("/obj/item").unwrap();
        assert_eq!(path.parent().unwrap().as_str(), "/obj");
        assert_eq!(
            TypePath::parse("/obj").unwrap().parent().unwrap().as_str(),
            "/"
        );
        assert!(TypePath::parse("obj/item").is_err());
        assert!(TypePath::parse("/obj//item").is_err());
    }

    #[test]
    fn mir_rejects_bad_targets_and_duplicate_results() {
        let span = Span::default();
        let operation = Operation::Constant(Constant::Null);
        let proc = MirProc {
            id: ProcId(0),
            entry: BlockId(0),
            local_count: 0,
            value_count: 1,
            blocks: vec![BasicBlock {
                instructions: vec![
                    MirInstruction {
                        result: Some(ValueId(0)),
                        operation: operation.clone(),
                        span,
                    },
                    MirInstruction {
                        result: Some(ValueId(0)),
                        operation,
                        span,
                    },
                ],
                terminator: Terminator::Goto(BlockId(2)),
            }],
        };
        let errors = proc.verify().unwrap_err();
        assert!(errors.contains(&MirError::DuplicateValue(ValueId(0))));
        assert!(errors.contains(&MirError::InvalidTarget {
            from: BlockId(0),
            to: BlockId(2)
        }));
    }
}
