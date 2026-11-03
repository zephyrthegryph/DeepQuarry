//! Stored-reference receiver policy over the EXISTING borrowed Walker.
//! Pinned old stored_refs::Walker.type_of (also used by player_link) differs
//! from untyped inference: no magic bare `global`, and root-proc fallback on
//! member calls requires an existing receiver and an ABSENT own method.
//! An existing method without a return annotation does not fall back. Field/return lookup and
//! primary-qualified hints still use the original owner/resolver providers.
use super::*;
impl<'a, R: Resolver + ?Sized> Walker<'a, R> {
    pub(crate) fn player_link_receiver_type(&self,expression:&Expr)->Result<Option<String>,Unsupported>{
        self.player_link_receiver_type_using(expression,&mut||Ok::<(),Unsupported>(()))
    }
    /// Same old receiver lookup; only operation control is lent by the caller.
    pub(crate) fn player_link_receiver_type_using<E:From<Unsupported>+From<String>>(&self,expression:&Expr,checkpoint:&mut impl FnMut()->Result<(),E>)->Result<Option<String>,E>{
        checkpoint()?;
        let node = ungroup_using(expression,checkpoint)?;
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
                    checkpoint()?;
                    let own = if self.owner != SymbolId::of("/") {
                        self.field_type_using(self.owner,name,checkpoint)?
                    } else {
                        None
                    };
                    match own {
                        Some(ty) => Some(ty),
                        None => {checkpoint()?;self.field_type_using(SymbolId::of("/"),name,checkpoint)?},
                    }
                }
            }
            ExprKind::Member {
                object, selector, ..
            }
            | ExprKind::SafeMember {
                object, selector, ..
            } => match self.player_link_receiver_type_using(object,checkpoint)? {
                Some(owner) if !owner.is_empty() => {
                    checkpoint()?;
                    self.field_type_using(SymbolId::of(&owner),selector,checkpoint)?
                }
                _ => None,
            },
            ExprKind::Index { object, .. } | ExprKind::SafeIndex { object, .. } => {
                self.player_link_receiver_type_using(object,checkpoint)?.and_then(|path| {
                    path.strip_prefix("/list")
                        .filter(|tail| tail.starts_with('/'))
                        .map(str::to_owned)
                })
            }
            ExprKind::Call { callee, .. } => match dm_syntax::call_target(callee) {
                dm_syntax::CallTarget::Named(name) => {checkpoint()?;match self.return_type_using(self.owner,name,checkpoint)? {
                    some @ Some(_) => some,
                    None if self.owner != SymbolId::of("/") => {
                        checkpoint()?;
                        self.return_type_using(SymbolId::of("/"),name,checkpoint)?
                    }
                    None => None,
                }},
                dm_syntax::CallTarget::GlobalNamed(name) => {
                    checkpoint()?;
                    self.return_type_using(SymbolId::of("/"),name,checkpoint)?
                }
                dm_syntax::CallTarget::Member { object, selector }
                | dm_syntax::CallTarget::SafeMember {
                    object, selector, ..
                } => {
                    if let Some(owner) = self.player_link_receiver_type_using(object,checkpoint)? {
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
                        checkpoint()?;
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
                                    checkpoint()?;
                                    let profile=self.tree.checker_builtin_profile().ok_or_else(||Unsupported("player-link source type roster lacks certified checker hierarchy".into()))?;
                                    if self
                                        .tree
                                        .checker_source_type_presence(profile, &owner)
                                        .map_err(|e| Unsupported(format!("{e:?}")))?
                                    {
                                        checkpoint()?;
                                        self.return_type(SymbolId::of("/"), selector)?
                                    } else {
                                        None
                                    }
                                }
                            }
                            M::Members(_) => {checkpoint()?;self.return_type_using(SymbolId::of(&owner),selector,checkpoint)?},
                            _ => {
                                return Err(Unsupported(
                                    "player-link method declaration is incomplete".into(),
                                ).into())
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
            } => match self.player_link_receiver_type_using(then_value,checkpoint)? {
                Some(ty) if {checkpoint()?;self.is_ref_using(&ty,checkpoint)?} => Some(ty),
                _ => self.player_link_receiver_type_using(else_value,checkpoint)?,
            },
            _ => None,
        })
    }
}
