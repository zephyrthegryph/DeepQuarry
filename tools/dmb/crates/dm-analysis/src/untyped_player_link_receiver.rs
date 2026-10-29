//! Stored-reference receiver policy over the EXISTING borrowed Walker.
//! Pinned old stored_refs::Walker.type_of (also used by player_link) differs
//! from untyped inference: no magic bare `global`, and root-proc fallback on
//! member calls requires an existing receiver and an ABSENT own method.
//! An existing method without a return annotation does not fall back. Field/return lookup and
//! primary-qualified hints still use the original owner/resolver providers.
use super::*;
impl<'a, R: Resolver + ?Sized> Walker<'a, R> {
    pub(crate) fn player_link_receiver_type(
        &self,
        expression: &Expr,
    ) -> Result<Option<String>, Unsupported> {
        let node = ungroup(expression);
        if let Some(ctor) =
            dm_syntax::native_special_forms::constructor(node).map_err(|e| Unsupported(e.into()))?
        {
            return Ok(match ctor {
                dm_syntax::native_special_forms::Constructor::Static { path, .. } => {
                    Some(path.into())
                }
                _ => None,
            });
        }
        Ok(match &node.kind {
            ExprKind::Ident(name) => {
                if name == "src" {
                    self.tree
                        .symbols()
                        .text(self.owner)
                        .filter(|owner| *owner != "/")
                        .map(str::to_owned)
                } else if name == "usr" {
                    Some("/mob".into())
                } else if let Some(ty) = self.locals.get(name) {
                    Some(ty.clone())
                } else {
                    let own = if self.owner != SymbolId::of("/") {
                        self.field_type(self.owner, name)?
                    } else {
                        None
                    };
                    match own {
                        Some(ty) => Some(ty),
                        None => self.field_type(SymbolId::of("/"), name)?,
                    }
                }
            }
            ExprKind::Member {
                object, selector, ..
            }
            | ExprKind::SafeMember {
                object, selector, ..
            } => match self.player_link_receiver_type(object)? {
                Some(owner) if !owner.is_empty() => {
                    self.field_type(SymbolId::of(&owner), selector)?
                }
                _ => None,
            },
            ExprKind::Index { object, .. } | ExprKind::SafeIndex { object, .. } => {
                self.player_link_receiver_type(object)?.and_then(|path| {
                    path.strip_prefix("/list")
                        .filter(|tail| tail.starts_with('/'))
                        .map(str::to_owned)
                })
            }
            ExprKind::Call { callee, .. } => match dm_syntax::call_target(callee) {
                dm_syntax::CallTarget::Named(name) => match self.return_type(self.owner, name)? {
                    some @ Some(_) => some,
                    None if self.owner != SymbolId::of("/") => {
                        self.return_type(SymbolId::of("/"), name)?
                    }
                    None => None,
                },
                dm_syntax::CallTarget::GlobalNamed(name) => {
                    self.return_type(SymbolId::of("/"), name)?
                }
                dm_syntax::CallTarget::Member { object, selector }
                | dm_syntax::CallTarget::SafeMember {
                    object, selector, ..
                } => {
                    if let Some(owner) = self.player_link_receiver_type(object)? {
                        // The original stored_refs Walker passes even an empty
                        // declared local type to Sem.ty(), which selects the
                        // ORIGINAL root for proc-return lookup. Field lookup
                        // deliberately differs and still rejects empty types.
                        let owner = if owner.is_empty() {
                            "/".to_owned()
                        } else {
                            owner
                        };
                        let q = Q::SourceDeclarationChain {
                            owner: SymbolId::of(&owner),
                            name: SymbolId::of(selector),
                            verb: false,
                        };
                        match self.resolver.resolve(q) {
                            M::Missing => {
                                // Pinned get_proc_declaration traverses the type's
                                // parents through the root. That fallback applies
                                // only after ty(owner) itself exists. A present
                                // unannotated method is handled by Members below.
                                if owner.is_empty() {
                                    None
                                } else {
                                    // SourceDeclarationChain has proven the own
                                    // method absent. Its old root fallback also
                                    // requires a checker/source receiver type;
                                    // runtime-only seed types do not qualify.
                                    let profile=self.tree.checker_builtin_profile().ok_or_else(||Unsupported("player-link source type roster lacks certified checker hierarchy".into()))?;
                                    if self
                                        .tree
                                        .checker_source_type_presence(profile, &owner)
                                        .map_err(|e| Unsupported(format!("{e:?}")))?
                                    {
                                        self.return_type(SymbolId::of("/"), selector)?
                                    } else {
                                        None
                                    }
                                }
                            }
                            M::Members(_) => self.return_type(SymbolId::of(&owner), selector)?,
                            _ => {
                                return Err(Unsupported(
                                    "player-link method declaration is incomplete".into(),
                                ))
                            }
                        }
                    } else {
                        None
                    }
                }
                _ => None,
            },
            ExprKind::Conditional {
                then_value,
                else_value,
                ..
            } => match self.player_link_receiver_type(then_value)? {
                Some(ty) if self.is_ref(&ty)? => Some(ty),
                _ => self.player_link_receiver_type(else_value)?,
            },
            _ => None,
        })
    }
}
