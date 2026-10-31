//! Shared checker-qualified view of ORIGINAL native variable metadata.
//! Does not change runtime declared_type/flags or copy a declaration/model.
use super::{BodyArchive, SourceNoteOrigin};
use crate::{DefinitionMode, MemberId, MemberKind, MemberMetadata};
use dm_ir::{PackedU128, SymbolId};
pub struct CheckerVariableProperties<'a> {
    pub formal: MemberId,
    pub owner: SymbolId,
    pub name: SymbolId,
    pub metadata: &'a MemberMetadata,
    pub qualifiers: u8,
    pub declared_type: Option<SymbolId>,
    pub list_element_type: Option<SymbolId>,
    /// Small ephemeral source-qualified hint; may name a type never interned.
    declared_hint: Option<String>,
}
impl CheckerVariableProperties<'_> {
    /// Already normalized through OWNED primary flags. Unknown nonempty type
    /// names remain typed; absence in the native tree does not erase a hint.
    pub fn declared_hint(&self) -> Option<&str> {
        self.declared_hint.as_deref()
    }
}
fn cleaned_type(
    tree: &crate::SemanticTree,
    path: SymbolId,
    flags: u8,
) -> Result<Option<String>, String> {
    let raw = tree
        .symbols()
        .text(path)
        .ok_or("checker variable native type spelling unavailable")?;
    if !raw.starts_with('/') {
        return Err("checker variable type is not a native absolute path".into());
    }
    let mut kept = Vec::new();
    for part in raw.split('/').filter(|part| !part.is_empty()) {
        let flag = match part {
            "final" | "SpacemanDMM_final" => dm_syntax::CHECKER_VAR_FINAL,
            "SpacemanDMM_private" => dm_syntax::CHECKER_VAR_PRIVATE,
            "SpacemanDMM_protected" => dm_syntax::CHECKER_VAR_PROTECTED,
            "var" => {
                return Err("checker variable redundant namespace projection is not issued".into())
            }
            _ => {
                kept.push(part);
                continue;
            }
        };
        if flags & flag == 0 {
            return Err("native type qualifier lacks original primary flag issuance".into());
        }
    }
    Ok((!kept.is_empty()).then(|| format!("/{}", kept.join("/"))))
}
impl BodyArchive {
    /// Flags are independent of normalized value typing (for example nested
    /// arrays); this borrows the same original formal/cursor-issued metadata.
    pub fn checker_variable_qualifiers(
        &self,
        formal: MemberId,
        profile: PackedU128,
    ) -> Result<u8, String> {
        self.tree()
            .validate_checker_builtin_profile(profile)
            .map_err(|e| format!("checker qualifier profile: {e:?}"))?;
        let node = self
            .tree()
            .member(formal)
            .ok_or("checker qualifier formal unavailable")?;
        if node.kind != MemberKind::Var
            || node.definition != DefinitionMode::Declare
            || node.metadata.inherited_opaque.is_some()
        {
            return Err("checker qualifier needs exact authored formal".into());
        }
        let ordinal = *self
            .declarations
            .for_target(crate::Target::Member(formal))
            .first()
            .ok_or("checker qualifier formal occurrence unavailable")?;
        self.mapping.declaration_checker_qualifiers(ordinal)
    }
    pub fn checker_variable_properties(
        &self,
        formal: MemberId,
        profile: PackedU128,
    ) -> Result<CheckerVariableProperties<'_>, String> {
        self.tree()
            .validate_checker_builtin_profile(profile)
            .map_err(|e| format!("checker variable profile unavailable: {e:?}"))?;
        let node = self
            .tree()
            .member(formal)
            .ok_or("checker formal variable member unavailable")?;
        if node.kind != MemberKind::Var
            || node.definition != DefinitionMode::Declare
            || node.metadata.inherited_opaque.is_some()
        {
            return Err("checker variable needs an exact authored formal declaration".into());
        }
        let ordinal = *self
            .declarations
            .for_target(crate::Target::Member(formal))
            .first()
            .ok_or("checker variable formal has no native source occurrence")?;
        self.checker_variable_properties_at(formal,ordinal)
    }
    fn require_original_variable_occurrence(&self,formal:MemberId,ordinal:crate::OccurrenceId,profile:PackedU128,proof:&crate::checker_builtins::ValidatedCheckerProfile<'_>)->Result<(),String>{
        proof.require(self.tree(),profile).map_err(|e|format!("checker variable profile unavailable: {e:?}"))?;
        if self.declarations.get(ordinal).is_none_or(|row|row.target!=crate::Target::Member(formal)){return Err("checker variable occurrence belongs to another original member".into())}Ok(())
    }
    /// Original current ordinal avoids constructing the legacy target grouping.
    pub fn checker_variable_qualifiers_original_at(&self,formal:MemberId,ordinal:crate::OccurrenceId,profile:PackedU128,proof:&crate::checker_builtins::ValidatedCheckerProfile<'_>)->Result<u8,String>{
        self.require_original_variable_occurrence(formal,ordinal,profile,proof)?;let node=self.tree().member(formal).ok_or("checker qualifier formal unavailable")?;if node.kind!=MemberKind::Var||node.definition!=DefinitionMode::Declare||node.metadata.inherited_opaque.is_some(){return Err("checker qualifier needs exact authored formal".into())}self.mapping.declaration_checker_qualifiers(ordinal)
    }
    pub fn checker_variable_properties_original_at(&self,formal:MemberId,ordinal:crate::OccurrenceId,profile:PackedU128,proof:&crate::checker_builtins::ValidatedCheckerProfile<'_>)->Result<CheckerVariableProperties<'_>,String>{self.require_original_variable_occurrence(formal,ordinal,profile,proof)?;self.checker_variable_properties_at(formal,ordinal)}
    fn checker_variable_properties_at(&self,formal:MemberId,ordinal:crate::OccurrenceId)->Result<CheckerVariableProperties<'_>,String>{
        let node=self.tree().member(formal).ok_or("checker formal variable member unavailable")?;if node.kind!=MemberKind::Var||node.definition!=DefinitionMode::Declare||node.metadata.inherited_opaque.is_some(){return Err("checker variable needs an exact authored formal declaration".into())}
        let flags = self.mapping.declaration_checker_qualifiers(ordinal)?;
        let data = node.metadata.as_ref();
        let declared_hint = if let Some(array) = &data.array {
            if array.dimensions.len() != 1 {
                return Err("nested array checker type projection is not issued".into());
            }
            let element = array
                .element_type
                .map(|path| cleaned_type(self.tree(), path, flags))
                .transpose()?
                .flatten();
            if element
                .as_ref()
                .is_some_and(|path| path == "/list" || path.starts_with("/list/"))
            {
                return Err("array-of-list checker type projection is not issued".into());
            }
            Some(element.map_or_else(|| "/list".to_owned(), |path| format!("/list{path}")))
        } else if data.declared_type == Some(SymbolId::of("/list")) {
            match data.list_element_type {
                Some(element) => Some(
                    cleaned_type(self.tree(), element, flags)?
                        .map_or_else(|| "/list".to_owned(), |path| format!("/list{path}")),
                ),
                None => Some("/list".to_owned()),
            }
        } else {
            data.declared_type
                .map(|path| cleaned_type(self.tree(), path, flags))
                .transpose()?
                .flatten()
        };
        let (declared_type, list_element_type) = match declared_hint.as_deref() {
            None => (None, None),
            Some(path) => {
                let projected = dm_syntax::project_declaration_type(path);
                (
                    Some(SymbolId::of(projected.runtime_path)),
                    projected
                        .list_element_path
                        .map(|tail| SymbolId::of(&format!("/{tail}"))),
                )
            }
        };
        Ok(CheckerVariableProperties {
            formal,
            owner: self
                .tree()
                .type_node(node.owner)
                .ok_or("checker variable owner unavailable")?
                .path,
            name: node.name,
            metadata: data,
            qualifiers: flags,
            declared_type,
            list_element_type,
            declared_hint,
        })
    }
    pub fn checker_variable_definition_point(
        &self,
        formal: MemberId,
        profile: PackedU128,
    ) -> Result<SourceNoteOrigin, String> {
        let _ = self.checker_variable_properties(formal, profile)?;
        self.member_policy_point(formal)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    fn tree(source: &str) -> crate::SemanticTree {
        let parsed = dm_syntax::parse(source);
        assert!(parsed.diagnostics.is_empty());
        let contribution = crate::from_ast(
            &parsed,
            dm_ir::SymbolTable::default(),
            dm_ir::FileId(0),
            0,
            0,
        )
        .unwrap();
        crate::build(contribution.symbols, &contribution.skeletons).unwrap()
    }
    #[test]
    fn proved_qualifiers_are_a_view_and_never_mutate_native_runtime_metadata() {
        let tree = tree("/datum/example\n    var/SpacemanDMM_private/datum/value\n");
        let owner = tree.lookup_type(SymbolId::of("/datum/example")).unwrap();
        let id = tree
            .resolve(owner, SymbolId::of("value"), crate::MemberKind::Var)
            .unwrap();
        let data = &tree.member(id).unwrap().metadata;
        let original = data.declared_type.unwrap();
        assert_eq!(
            tree.symbols().text(original),
            Some("/SpacemanDMM_private/datum")
        );
        assert_eq!(
            cleaned_type(&tree, original, dm_syntax::CHECKER_VAR_PRIVATE)
                .unwrap()
                .as_deref(),
            Some("/datum")
        );
        assert_eq!(data.declared_type, Some(original));
        assert!(
            cleaned_type(&tree, original, 0).is_err(),
            "matching text alone cannot authorize qualifier removal"
        );
    }
    #[test]
    fn qualifier_only_type_is_untyped_and_unknown_named_type_is_not_inferred_away() {
        let tree = tree("/datum/example\n    var/SpacemanDMM_private/value\n    var/SpacemanDMM_protected/missing_type/other\n");
        let owner = tree.lookup_type(SymbolId::of("/datum/example")).unwrap();
        let raw = |name| {
            tree.member(
                tree.resolve(owner, SymbolId::of(name), crate::MemberKind::Var)
                    .unwrap(),
            )
            .unwrap()
            .metadata
            .declared_type
            .unwrap()
        };
        assert_eq!(
            cleaned_type(&tree, raw("value"), dm_syntax::CHECKER_VAR_PRIVATE).unwrap(),
            None
        );
        assert_eq!(
            cleaned_type(&tree, raw("other"), dm_syntax::CHECKER_VAR_PROTECTED)
                .unwrap()
                .as_deref(),
            Some("/missing_type")
        );
        assert!(tree.lookup_type(SymbolId::of("/missing_type")).is_none());
    }
}
