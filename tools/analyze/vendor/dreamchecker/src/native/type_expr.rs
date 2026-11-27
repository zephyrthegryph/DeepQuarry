//! "Type expressions" (`set SpacemanDMM_return_type = ...`): a return type computed from a call's arguments (SpacemanDMM
//! DreamChecker's `type_expr.rs`), compiled from the front end's typed expression.
use dm::{DMError, Location};
use dm_syntax::Expr;
use foldhash::HashMap;

use super::analysis::{Analysis, StaticType, Value};
use super::model::{Model, Param};
use super::view::{Follow, Reader, Shape, Term};

pub struct TypeExprContext<'m> {
    pub model: &'m Model,
    pub param_name_map: HashMap<String, Analysis>,
    pub param_idx_map: HashMap<usize, Analysis>,
}

impl TypeExprContext<'_> {
    fn get(&self, name: &str, idx: usize) -> Option<&Analysis> {
        self.param_name_map.get(name).or_else(|| self.param_idx_map.get(&idx))
    }
}

#[derive(Debug, Clone)]
pub enum TypeExpr {
    Static(StaticType),
    ParamTypepath { name: String, p_idx: usize, index_ct: usize },
    ParamStaticType { name: String, p_idx: usize, index_ct: usize },
    Condition { cond: Box<TypeExpr>, if_: Box<TypeExpr>, else_: Box<TypeExpr> },
}

impl From<StaticType> for TypeExpr {
    fn from(s: StaticType) -> TypeExpr {
        TypeExpr::Static(s)
    }
}

impl TypeExpr {
    pub fn compile(model: &Model, parameters: &[Param], reader: &mut Reader<'_, '_>, location: Location, e: &Expr) -> Result<TypeExpr, DMError> {
        Compiler { model, parameters, reader }.expression(location, e)
    }

    pub fn evaluate(&self, location: Location, ec: &TypeExprContext<'_>) -> Result<StaticType, DMError> {
        match self {
            TypeExpr::Static(st) => Ok(st.clone()),
            TypeExpr::Condition { cond, if_, else_ } => {
                if cond.evaluate(location, ec)?.is_truthy() {
                    if_.evaluate(location, ec)
                } else {
                    else_.evaluate(location, ec)
                }
            }
            TypeExpr::ParamTypepath { name, p_idx, .. } => match ec.get(name, *p_idx) {
                Some(Analysis { value: Some(Value::Prefab(path)), .. }) => super::walk::static_type(ec.model, location, path),
                _ => Ok(StaticType::None),
            },
            TypeExpr::ParamStaticType { name, p_idx, index_ct } => match ec.get(name, *p_idx) {
                Some(a) => Ok(a.static_ty.clone().strip_lists(*index_ct)),
                None => Ok(StaticType::None),
            },
        }
    }
}

struct Compiler<'c, 'r, 's, 'a> {
    model: &'c Model,
    parameters: &'c [Param],
    reader: &'r mut Reader<'s, 'a>,
}

impl Compiler<'_, '_, '_, '_> {
    fn loc(&mut self, offset: usize) -> Location {
        let at = self.reader.shift + offset;
        self.reader.site.locate(at)
    }

    fn expression(&mut self, location: Location, e: &Expr) -> Result<TypeExpr, DMError> {
        match self.reader.shape(e) {
            Shape::Base(b) => {
                let at = self.loc(b.term_at);
                let mut ty = self.term(at, &b.term)?;
                for (f, place) in &b.follows {
                    let at = self.loc(*place);
                    ty = self.follow(at, ty, f)?;
                }
                Ok(ty)
            }
            Shape::Binary { op: "||", lhs, rhs } => {
                let l = self.expression(location, lhs)?;
                let r = self.expression(location, rhs)?;
                Ok(TypeExpr::Condition { cond: Box::new(l.clone()), if_: Box::new(l), else_: Box::new(r) })
            }
            Shape::Binary { op: "&&", lhs, rhs } => {
                let l = self.expression(location, lhs)?;
                let r = self.expression(location, rhs)?;
                Ok(TypeExpr::Condition { cond: Box::new(l.clone()), if_: Box::new(r), else_: Box::new(l) })
            }
            Shape::Ternary { cond, if_, else_ } => Ok(TypeExpr::Condition {
                cond: Box::new(self.expression(location, cond)?),
                if_: Box::new(self.expression(location, if_)?),
                else_: Box::new(self.expression(location, else_)?),
            }),
            _ => Err(DMError::new(location, "type expr: bad expression node")),
        }
    }

    fn term(&mut self, location: Location, term: &Term<'_>) -> Result<TypeExpr, DMError> {
        match term {
            Term::Null => Ok(TypeExpr::from(StaticType::None)),
            Term::Ident(name) => {
                for (i, param) in self.parameters.iter().enumerate() {
                    if *name == param.name {
                        return Ok(TypeExpr::ParamTypepath { name: name.clone(), p_idx: i, index_ct: 0 });
                    }
                }
                Err(DMError::new(location, format!("type expr: no such parameter {name:?}")))
            }
            Term::Group(e) => self.expression(location, e),
            Term::Prefab { path, .. } => {
                let bits: Vec<String> = super::walk::type_path(path).into_iter().map(|(_, n)| n).collect();
                Ok(TypeExpr::from(super::walk::static_type(self.model, location, &bits)?))
            }
            _ => Err(DMError::new(location, "type expr: bad term node")),
        }
    }

    fn follow(&mut self, location: Location, lhs: TypeExpr, rhs: &Follow<'_>) -> Result<TypeExpr, DMError> {
        match rhs {
            Follow::Index(e) => match self.reader.shape(e) {
                Shape::Base(b) if b.follows.is_empty() && matches!(&b.term, Term::Ident(n) if n == "_") => match lhs {
                    TypeExpr::ParamTypepath { name, p_idx, index_ct } => Ok(TypeExpr::ParamTypepath { name, p_idx, index_ct: index_ct + 1 }),
                    _ => Err(DMError::new(location, "type expr: cannot index non-parameters")),
                },
                _ => Err(DMError::new(location, "type expr: cannot index by anything but `_`")),
            },
            Follow::Field(_, name) if *name == "type" => match lhs {
                TypeExpr::ParamTypepath { name, p_idx, index_ct } => Ok(TypeExpr::ParamStaticType { name, p_idx, index_ct }),
                _ => Err(DMError::new(location, "type expr: cannot take .type of non-parameters")),
            },
            // SpacemanDMM prints the follow's syntax tree here; its kind is what the reader can say.
            other => Err(DMError::new(location, format!("type expr: bad follow node {}", follow_debug(other)))),
        }
    }
}

fn follow_debug(f: &Follow<'_>) -> String {
    match f {
        Follow::Unary(op) => format!("Unary({op:?})"),
        Follow::Field(_, name) => format!("Field(Dot, {name:?})"),
        Follow::Call(_, name, _) => format!("Call(Dot, {name:?}, ..)"),
        Follow::Index(_) => "Index(..)".into(),
        Follow::StaticField(name) => format!("StaticField({name:?})"),
        Follow::ProcReference(name) => format!("ProcReference({name:?})"),
    }
}
