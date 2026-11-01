//! Sealed diagnostic-only result of the ORIGINAL native declaration builder.
//! Never a runtime/compiler admission receipt, alternate model or parser.
use crate::{MemberKind, OccurrenceTable, SemanticTree, TreeError, TreeSnapshot};
use std::sync::{Arc, Weak};
pub struct DiagnosticDeclarations {
    snapshot: TreeSnapshot,
    receipt: DiagnosticDeclarationReceipt,
}
pub struct DiagnosticDeclarationReceipt {
    pub(crate) retained_records: Option<crate::frontend::DiagnosticRetainedRecords>,
    errors: Vec<TreeError>,
    pub(crate) settings_compilable: bool,
    owner: Weak<SemanticTree>,
}
impl DiagnosticDeclarationReceipt {
    pub(crate) fn reused_valid_tree(tree: &Arc<SemanticTree>) -> Self {
        let mut receipt = Self::new();
        receipt.owner = Arc::downgrade(tree);
        receipt
    }

    pub fn settings_compilable(&self)->bool{self.settings_compilable}
    pub fn profile(&self)->&'static str{if self.errors.iter().any(|error|matches!(error,TreeError::Duplicate{kind:MemberKind::Proc|MemberKind::Verb,..})){"native-diagnostic-procedure-versions-v3"}else if self.errors.iter().any(|error|matches!(error,TreeError::InheritedDuplicate{kind:MemberKind::Proc|MemberKind::Verb,..})){"native-diagnostic-source-declarations-v2"}else{"native-diagnostic-inherited-variable-v1"}}
    pub fn errors(&self) -> &[TreeError] {
        &self.errors
    }
    pub fn visit_error_storage(&self, mut visit: impl FnMut(usize, usize, usize)) {
        visit(
            self.errors.as_ptr() as usize,
            self.errors.len() * std::mem::size_of::<TreeError>(),
            self.errors.capacity() * std::mem::size_of::<TreeError>(),
        );
    }

    pub fn authenticates(&self, tree: &SemanticTree) -> bool {
        self.owner
            .upgrade()
            .is_some_and(|owner| std::ptr::eq(owner.as_ref(), tree))
    }

    pub(crate) fn new() -> Self {
        Self {
            errors: Vec::new(),
            settings_compilable: true,
            retained_records: None,
            owner: Weak::new(),
        }
    }
    pub(crate) fn accept_callable_duplicate(&mut self,error:TreeError)->Result<(),TreeError>{if matches!(&error,TreeError::Duplicate{kind:MemberKind::Proc|MemberKind::Verb,..}){self.errors.push(error);Ok(())}else{Err(error)}}
    pub(crate) fn accept(&mut self, error: TreeError) -> Result<(), TreeError> {
        if matches!(
            &error,
            TreeError::InheritedDuplicate {
                kind: MemberKind::Var | MemberKind::Proc | MemberKind::Verb,
                ..
            }
        ) {
            self.errors.push(error);
            Ok(())
        } else {
            Err(error)
        }
    }
}
impl DiagnosticDeclarations {
    pub(crate) fn into_parts(self) -> (TreeSnapshot, DiagnosticDeclarationReceipt) {
        (self.snapshot, self.receipt)
    }

    pub(crate) fn bind(snapshot: TreeSnapshot, mut receipt: DiagnosticDeclarationReceipt) -> Self {
        receipt.owner = Arc::downgrade(&snapshot.tree);
        Self { snapshot, receipt }
    }
    pub fn tree(&self) -> &SemanticTree {
        &self.snapshot.tree
    }
    pub fn occurrences(&self) -> &OccurrenceTable {
        &self.snapshot.occurrences
    }
    pub fn errors(&self) -> &[TreeError] {
        &self.receipt.errors
    }
    pub fn authenticates(&self, tree: &SemanticTree) -> bool {
        self.receipt
            .owner
            .upgrade()
            .is_some_and(|owner| std::ptr::eq(owner.as_ref(), tree))
    }
    pub fn visit_error_storage(&self, mut visit: impl FnMut(usize, usize, usize)) {
        let e = &self.receipt.errors;
        visit(
            e.as_ptr() as usize,
            e.len() * std::mem::size_of::<TreeError>(),
            e.capacity() * std::mem::size_of::<TreeError>(),
        );
    }
    pub const fn runtime_admissible(&self) -> bool {
        false
    }
    pub fn profile(&self) -> &'static str {self.receipt.profile()}
}
