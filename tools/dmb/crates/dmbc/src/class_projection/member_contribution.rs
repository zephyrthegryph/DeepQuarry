//! Symbolic per-member projection, separated from current encounter placement.
//! This producer borrows the authoritative current tree; it grants no cache
//! admission and never retains dense member/source occurrence identities.
use super::*;

#[derive(Clone)]
pub(crate) enum MemberContribution {
    Field(Arc<FieldProjection>),
    Procedure {
        owner: SymbolId,
        name: SymbolId,
        verb: bool,
        key: Key,
        declared: bool,
    },
}

/// Request-local placement; kept separately from any reusable symbolic payload.
pub(super) struct CurrentPlacement<'a> {
    pub occurrence: &'a dm_tree::Occurrence,
}

pub(super) fn produce(
    tree: &dm_tree::SemanticTree,
    member_id: dm_tree::MemberId,
    default: Option<&DefaultValue>,
    defaults_admitted: bool,
    evaluator: &dyn CapturedFieldEvaluator,
) -> Result<MemberContribution, ProjectionError> {
    let member = tree
        .member(member_id)
        .ok_or(ProjectionError::MissingMember)?;
    let owner = tree
        .type_node(member.owner)
        .ok_or(ProjectionError::MissingMember)?
        .path;
    match member.kind {
        MemberKind::Var => {
            let metadata = &member.metadata;
            if metadata.array.is_some() && !defaults_admitted {
                return Err(ProjectionError::Unsupported(
                    "array defaults need initializer materialization".into(),
                ));
            }
            let role = if member.definition == DefinitionMode::Declare {
                FieldRole::Declaration
            } else {
                FieldRole::Assignment
            };
            let (flags, shared, declaring_owner, intrinsic) =
                if let Some(base) = &metadata.inherited_opaque {
                    if role == FieldRole::Declaration {
                        return Err(ProjectionError::OpaqueField {
                            owner,
                            name: member.name,
                        });
                    }
                    match dm_ir::Resolver::resolve(
                        tree,
                        dm_ir::ResolveQuery::VarStorage {
                            owner,
                            name: member.name,
                        },
                    ) {
                        dm_ir::ResolvedMeaning::InstanceField {
                            declaring_owner,
                            name,
                        } if name == member.name => (None, false, declaring_owner, true),
                        dm_ir::ResolvedMeaning::Slot {
                            owner: slot_owner,
                            name,
                            ..
                        } if name == member.name => (None, true, slot_owner, true),
                        _ => {
                            return Err(ProjectionError::OpaqueField {
                                owner: base.owner,
                                name: member.name,
                            })
                        }
                    }
                } else {
                    let (flags, shared) = wire_flags(metadata.flags, owner)?;
                    let mut declaration = member;
                    while declaration.definition != DefinitionMode::Declare {
                        declaration = tree
                            .member(declaration.previous.ok_or(ProjectionError::MissingMember)?)
                            .ok_or(ProjectionError::MissingMember)?;
                    }
                    let declaring_owner = tree
                        .type_node(declaration.owner)
                        .ok_or(ProjectionError::MissingMember)?
                        .path;
                    (Some(flags), shared, declaring_owner, false)
                };
            let expression = if role == FieldRole::Declaration {
                metadata.declared_initializer.as_ref()
            } else {
                metadata.initializer.as_ref()
            };
            let value = if let Some(value) = default {
                value.clone()
            } else {
                if defaults_admitted {
                    return Err(ProjectionError::Unsupported(
                        "classified source occurrence default is absent".into(),
                    ));
                }
                DefaultValue::Scalar(match expression {
                    Some(value) => evaluator
                        .evaluate(owner, value)
                        .map_err(ProjectionError::Evaluation)?,
                    None if role == FieldRole::Declaration => SemanticValue::Null,
                    None => {
                        return Err(ProjectionError::Unsupported(
                            "assignment has no authored value".into(),
                        ))
                    }
                })
            };
            // Mutable lists have occurrence identity and cannot be merged as
            // scalar records; the initializer linker must materialize them.
            if matches!(value, DefaultValue::Scalar(SemanticValue::List(_))) {
                return Err(ProjectionError::Unsupported(
                    "list defaults need occurrence-specific materialization".into(),
                ));
            }
            Ok(MemberContribution::Field(std::sync::Arc::new(
                FieldProjection {
                    owner,
                    declaring_owner,
                    name: member.name,
                    role,
                    wire_flags: flags,
                    intrinsic,
                    shared,
                    value,
                },
            )))
        }
        MemberKind::Proc | MemberKind::Verb => {
            let verb = member.kind == MemberKind::Verb;
            let depth = tree
                .override_chain(member_id)
                .iter()
                .filter(|id| {
                    tree.member(**id).is_some_and(|previous| {
                        previous.owner == member.owner
                            && previous.kind == member.kind
                            && previous.name == member.name
                    })
                })
                .count()
                .checked_sub(1)
                .ok_or(ProjectionError::MissingMember)?;
            let occurrence = u32::try_from(depth).map_err(|_| {
                ProjectionError::Unsupported("procedure occurrence overflow".into())
            })?;
            let key = if verb {
                Key::Verb {
                    owner,
                    name: member.name,
                    occurrence,
                }
            } else {
                Key::Proc {
                    owner,
                    name: member.name,
                    occurrence,
                }
            };
            Ok(MemberContribution::Procedure {
                owner,
                name: member.name,
                verb,
                key,
                declared: member.definition == DefinitionMode::Declare,
            })
        }
    }
}
