//! Port of `tools/ci/state_schema_lint.py`'s CI check (roadmap L1, doc/rewrite/state.md section 2).
//!
//! A saved var (not `tmp`/`static`/`global`/`const`) on a latent-safe type, or one of its
//! ancestors, whose declared type is an object must be `tmp`, have a codec in `state_codecs()`,
//! hold a registry singleton, or have an ownership kind. The `--vars` / `--report` modes of the
//! script are not lints and are not ported.

use crate::dm::schema::{chain, OwnershipKinds, Schema};
use crate::lint::{Cx, Lint, Meta, Registry, Sink};
use crate::parity::{ParseKind, Parity};
use crate::tree::CODE_DM;

use crate::state_schema_policy::{self as policy,META};

struct StateSchema;

impl Lint for StateSchema {
    fn meta(&self) -> &Meta {
        &META
    }

    fn scan_tree(&self, cx: &Cx, out: &mut Sink) {
        let files = cx.all_files();
        let schema = Schema::get(cx.tree, &files);
        let kinds = OwnershipKinds::get(cx.tree, &files);

        struct Borrowed<'a>{schema:&'a Schema,kinds:&'a OwnershipKinds}
        impl<C:crate::key_policy_control::Control> policy::SchemaView<C> for Borrowed<'_>{
            fn visit_safe_types(&self,c:&mut C,emit:&mut dyn FnMut(&str,&mut C)->Result<(),C::Error>)->Result<usize,C::Error>{let types=self.schema.safe_types();for t in &types{emit(t,c)?;}Ok(types.len())}
            fn visit_chain(&self,subject:&str,c:&mut C,emit:&mut dyn FnMut(&str,&mut C)->Result<(),C::Error>)->Result<(),C::Error>{for path in chain(subject){emit(&path,c)?;}Ok(())}
            fn variables(&self,owner:&str,c:&mut C,visit:&mut dyn FnMut(policy::Variable<'_>,&mut C)->Result<(),C::Error>)->Result<(),C::Error>{if let Some(vars)=self.schema.decls.get(owner){for v in vars{visit(policy::Variable{name:&v.name,vtype:&v.vtype,path:&v.path,line:v.line,is_list:v.is_list,saved:v.saved(),holds_ref:v.holds_ref(),registry:v.registry(&self.schema.registry)},c)?;}}Ok(())}
            fn has_codec(&self,name:&str,subject:&str,_:&mut C)->Result<bool,C::Error>{Ok(self.schema.has_codec(name,subject))}
            fn has_kind(&self,owner:&str,name:&str,_:&mut C)->Result<bool,C::Error>{Ok(self.kinds.kind(owner,name).is_some())}
        }
        // Preserve the original one sink and exact site/note ordering. Judgment
        // accumulates notes only after the complete original lexical walk.
        let output=std::cell::RefCell::new(out);
        policy::judge(&Borrowed{schema:&schema,kinds:&kinds},|path,line,message|output.borrow_mut().site_in_msg("schema",path,line,message),|message|output.borrow_mut().note(message));
    }

    fn parity(&self) -> Option<Parity> {
        Some(Parity {
            old: &["tools/ci/state_schema_lint.py"],
            old_raw: &[],
            blank: &[],
            parse: ParseKind::FileLine,
            update: None,
            seed: None,
            files: &[],
            selftest: None,
        })
    }
}

pub fn register(reg: &mut Registry) {
    reg.add(StateSchema);
}
