//! Original stored_refs metadata and raw policy projections, no typed model.
use crate::{
    lint::{Meta, Policy, RuleMeta, ScanKind},
    tree::CODE_DM,
};

const H_VAR: &str = "declare the var: owns_one/ref_one/links()/slot() in the type's CAPABILITIES block (or its relations() table), which clears it when \
the other end is deleted; or keep a weak ref (ref_token(x), read back with resolve_token()). doc/rewrite/proposals/reference_storage.md";
const H_LIST: &str = "a list of atoms/datums is a declared many (owns_many/ref_many/a many links() end) or holds handles (ref_token(x)); a cache or \
pool keys by a handle or a type, never by the object. doc/rewrite/proposals/reference_storage.md";

pub(crate) static META: Meta = Meta {
    name: crate::allow_registry_fields::stored_refs::SCOPE_META_0.name,
    group: crate::allow_registry_fields::stored_refs::SCOPE_META_0.group,
    label: "stored_refs",
    legacy: "",
    select: CODE_DM,
    scan: ScanKind::Tree,
    policy: Policy::Hard,
    rules: &[RuleMeta { name: "var", hint: H_VAR }, RuleMeta { name: "list", hint: H_LIST }],
    allow: crate::allow_registry_fields::stored_refs::ALLOW_SHARED_0,
    lists: crate::allow_registry_fields::stored_refs::SCOPE_META_0.lists,
};

pub fn metadata() -> &'static Meta {
    &META
}

#[cfg(feature = "native-policy")]
pub(crate) struct SourceFacts {
    pub relations: crate::relation_decl_policy::DeclarationIndex,
    pub schemas: crate::value_schema_policy::SchemaHints,
    pub init_only: Vec<(String, String)>,
    pub remaining: usize,
}
#[cfg(feature = "native-policy")]
impl SourceFacts {
    pub(crate) fn capture(
        raw: &crate::captured_raw_policy::CapturedRawPolicy,
        mut checkpoint: impl FnMut() -> Result<(), String>,
    ) -> Result<Self, String> {
        // Admit select + clone + sort scratch capacities before the FIRST Vec
        // allocation. This is coordination over borrowed owners, not a model.
        let roster_reserve = raw
            .tree
            .files
            .len()
            .checked_mul(std::mem::size_of::<&crate::tree::SourceFile>())
            .and_then(|n| n.checked_mul(8))
            .and_then(|n| n.checked_add(4096))
            .ok_or("stored source-roster admission overflow")?;
        if roster_reserve > 64 * 1024 * 1024 {
            return Err("stored source-roster exceeds admission before selection".into());
        }
        let files = raw.tree.select(&CODE_DM);
        let mut relations = crate::relation_decl_policy::declarations_with_registry_reserved(
            files.clone(),
            roster_reserve,
            &mut checkpoint,
        )?;
        let mut remaining = (64usize * 1024 * 1024)
            .checked_sub(relations.retained_admission)
            .ok_or("stored relation admission overflow")?;
        let header_reserve = files
            .iter()
            .map(|f| f.raw().text.len())
            .max()
            .unwrap_or(0)
            .checked_mul(2)
            .ok_or("stored header reserve overflow")?;
        remaining = remaining
            .checked_sub(header_reserve)
            .ok_or("stored header reserve admission exceeded")?;
        let mut schemas = crate::value_schema_policy::SchemaHints::default();
        let mut init_only = Vec::new();
        struct Legacy<'a,P>{remaining:&'a std::cell::RefCell<usize>,poll:&'a std::cell::RefCell<P>}
        impl<P:FnMut()->Result<(),String>>crate::key_policy_control::Control for Legacy<'_,P>{type Error=String;const CHECKED:bool=false;fn checkpoint(&mut self)->Result<(),String>{(self.poll.borrow_mut())()}fn reserve(&mut self,n:usize)->Result<(),String>{self.checkpoint()?;let old=*self.remaining.borrow();*self.remaining.borrow_mut()=old.checked_sub(n).ok_or("stored raw fact admission exhausted")?;Ok(())}fn overflow(&mut self)->String{"stored raw fact geometry overflow".into()}fn allocation_failed(&mut self)->String{"stored raw fact allocation refused".into()}}
        let charged=std::cell::RefCell::new(remaining);let poll=std::cell::RefCell::new(&mut checkpoint);let mut retained=Legacy{remaining:&charged,poll:&poll};let mut temporary=Legacy{remaining:&charged,poll:&poll};for f in files{read_extra_file_using(f,&mut schemas,&mut relations.registry,&mut init_only,&mut retained,&mut temporary)?;}drop(retained);drop(temporary);drop(poll);remaining=charged.into_inner();
        checkpoint()?;
        if let Some(e) = raw.tree.captured_violation() {
            return Err(e);
        }
        Ok(Self {
            relations,
            schemas,
            init_only,
            remaining: remaining + header_reserve,
        })
    }
}
#[cfg(feature = "native-policy")]
fn put_pair(
    rows: &mut Vec<(String, String)>,
    owner: &str,
    name: &str,
    remaining: &mut usize,
) -> Result<(), String> {
    let charge = owner
        .len()
        .checked_add(name.len())
        .and_then(|n| n.checked_mul(4))
        .and_then(|n| n.checked_add(256))
        .ok_or("stored policy pair accounting overflow")?;
    *remaining = remaining
        .checked_sub(charge)
        .ok_or("stored policy pair admission exceeded before retention")?;
    rows.push((owner.to_owned(), name.to_owned()));
    Ok(())
}

/// SAME old raw keep/init-only/schema policy; private source loan stays with host.
#[cfg(feature="native-policy")]
pub(crate) fn read_extra_file_using<C:crate::key_policy_control::Control,T:crate::key_policy_control::Control<Error=C::Error>>(f:&crate::tree::SourceFile,schemas:&mut crate::value_schema_policy::SchemaHints,registry:&mut Vec<String>,init_only:&mut Vec<(String,String)>,retained:&mut C,temporary:&mut T)->Result<(),C::Error>where C::Error:From<String>{
 use crate::key_policy_control as kc;kc::reserve(temporary,||f.raw().text.len().checked_mul(64)?.checked_add(8192))?;schemas.read_with_control(f,temporary)?;let keep=crate::pat!(r"(?m)^LIFECYCLE_KEEP_(?:UNLESS_FORCED|ALWAYS)\((/[\w/]+)\)");let head=crate::pat!(r"^CAPABILITIES(?:_PART)?\((/[\w/]+)[,)]");let param=crate::pat!(r"\bparam\(\s*nameof\((\w+)\).*\bkeep\s*=\s*FALSE");let successor=crate::pat!(r"\bsuccessor\s*=\s*nameof\((\w+)\)");let code=f.code();for cap in keep.captures_iter(&code.text){retained.checkpoint()?;kc::row(retained,registry)?;registry.push(kc::own(retained,cap.s(1))?);}let mut owner=None;for line in code.lines(){retained.checkpoint()?;if let Some(cap)=head.captures(line){owner=Some(kc::own(temporary,cap.s(1))?);continue}if !(line.starts_with('\t')||line.starts_with(' '))&&!line.trim().is_empty(){owner=None}if let Some(ty)=owner.as_deref(){if let Some(cap)=param.captures(line){kc::row(retained,init_only)?;init_only.push((kc::own(retained,ty)?,kc::own(retained,cap.s(1))?));}for cap in successor.captures_iter(line){retained.checkpoint()?;kc::row(retained,init_only)?;init_only.push((kc::own(retained,ty)?,kc::own(retained,cap.s(1))?));}}}retained.checkpoint()
}
