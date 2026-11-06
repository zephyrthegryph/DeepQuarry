//! Sealed diagnostic-only result of the ORIGINAL native declaration builder.
//! Never a runtime/compiler admission receipt, alternate model or parser.
use crate::{MemberKind, OccurrenceTable, SemanticTree, TreeError, TreeSnapshot};
use std::sync::{Arc, Weak};
pub struct DiagnosticDeclarations {
    snapshot: TreeSnapshot,
    receipt: DiagnosticDeclarationReceipt,
}
/// Bounded Original checker-only source outcomes. No source coordinate survives
/// a warm reissue: reports borrow the current primary cursor again.
pub(crate) type OriginalSealedParents = [Option<(dm_ir::SymbolId, dm_ir::SymbolId)>; 4];
pub struct DiagnosticDeclarationReceipt {
    pub(crate) original_sealed_parents: OriginalSealedParents,
    pub(crate) retained_records: Option<Arc<crate::frontend::DiagnosticRetainedRecords>>,
    errors: Vec<TreeError>,
    // Shared original error owner only; flattened so warm reissues never form a chain.
    reused_errors: Option<Arc<DiagnosticDeclarationReceipt>>,
    pub(crate) original_variables:Option<crate::checker_builtins::OriginalVariableDeclarations>,
    pub(crate) settings_compilable: bool,
    owner: Weak<SemanticTree>,
}
impl DiagnosticDeclarationReceipt {
    pub(crate) fn reused_valid_tree(tree: &Arc<SemanticTree>) -> Self {
        let mut receipt = Self::new();
        receipt.owner = Arc::downgrade(tree);
        receipt
    }

    pub(crate) fn reused_diagnostic_tree(tree:&Arc<SemanticTree>, previous:&Arc<Self>)->Option<Self>{
        if !previous.authenticates(tree)||previous.retained_records.is_some(){return None}
        let base=previous.reused_errors.as_ref().unwrap_or(previous);
        if !base.authenticates(tree)||base.retained_records.is_some(){return None}
        let mut receipt=Self::reused_valid_tree(tree);
        receipt.settings_compilable=previous.settings_compilable;
        receipt.original_sealed_parents=previous.original_sealed_parents;
        if !base.errors.is_empty(){receipt.reused_errors=Some(Arc::clone(base));}
        Some(receipt)
    }

    pub(crate) fn has_original_variable_declarations(&self)->bool{self.original_variables.is_some()}
    pub fn original_sealed_parents(&self) -> impl Iterator<Item = (dm_ir::SymbolId, dm_ir::SymbolId)> + '_ {
        self.original_sealed_parents.iter().flatten().copied()
    }
    pub(crate) fn masks_original_sealed_parent(&self, owner: dm_ir::SymbolId, requested: dm_ir::SymbolId) -> bool {
        self.original_sealed_parents().any(|row| row == (owner, requested))
    }
    pub fn is_clean(&self) -> bool {
        self.original_sealed_parents().next().is_none() && self.errors().is_empty()
    }
    pub fn settings_compilable(&self)->bool{self.settings_compilable}
    pub fn profile(&self)->&'static str{if self.original_sealed_parents().next().is_some() || self.errors().iter().any(|error|matches!(error,TreeError::OriginalMissingParent{..})){"native-diagnostic-original-parent-outcome-v4"}else if self.errors().iter().any(|error|matches!(error,TreeError::Duplicate{kind:MemberKind::Proc|MemberKind::Verb,..})){"native-diagnostic-procedure-versions-v3"}else if self.errors().iter().any(|error|matches!(error,TreeError::InheritedDuplicate{kind:MemberKind::Proc|MemberKind::Verb,..})){"native-diagnostic-source-declarations-v2"}else{"native-diagnostic-inherited-variable-v1"}}
    pub fn errors(&self) -> &[TreeError] {
        self.reused_errors.as_ref().map_or(self.errors.as_slice(),|base|base.errors.as_slice())
    }
    pub fn visit_error_storage(&self, mut visit: impl FnMut(usize, usize, usize)) {
        if let Some(base)=&self.reused_errors{
            let bytes=std::mem::size_of::<Self>()+2*std::mem::size_of::<usize>();
            visit(Arc::as_ptr(base)as usize,bytes,bytes);
            base.visit_error_storage(visit);return
        }
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
            original_sealed_parents: [None; 4],
            reused_errors:None,
            original_variables:None,
            settings_compilable: true,
            retained_records: None,
            owner: Weak::new(),
        }
    }
    pub(crate) fn accept_original_missing_parent(&mut self,owner:dm_ir::SymbolId,parent:dm_ir::SymbolId)->Result<(),TreeError>{
        // Only the actual Original catalog/context can opt into this reader
        // recovery. Special engine roots have different pinned rules.
        if self.original_variables.is_none()||self.reused_errors.is_some()||["/datum","/atom","/atom/movable","/turf","/area","/obj","/mob","/world","/client","/list","/alist","/savefile","/vector","/pixloc","/callee"].iter().any(|path|dm_ir::SymbolId::of(path)==owner){return Err(TreeError::MissingParent(parent))}
        if self.errors.iter().any(|error|matches!(error,TreeError::OriginalMissingParent{owner:previous,..}if *previous==owner)){return Err(TreeError::ConflictingParent(owner))}
        self.errors.push(TreeError::OriginalMissingParent{owner,parent});Ok(())
    }
    pub(crate) fn accept_callable_duplicate(&mut self,error:TreeError)->Result<(),TreeError>{if self.reused_errors.is_none()&&matches!(&error,TreeError::Duplicate{kind:MemberKind::Proc|MemberKind::Verb,..}){self.errors.push(error);Ok(())}else{Err(error)}}
    pub(crate) fn accept(&mut self, error: TreeError) -> Result<(), TreeError> {
        if self.reused_errors.is_none() && matches!(
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
