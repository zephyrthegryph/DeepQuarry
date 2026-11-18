//! Shared original codemod metadata; no parser, model, writer or completion authority.
#[derive(Clone,Copy)]pub struct Spec{pub name:&'static str,pub about:&'static str,pub callees:&'static[&'static str],pub reasons:&'static[(&'static str,&'static str)]}
pub const OM_AFTER:Spec=Spec{name:"om_after",about:"om_after(E, d, proc, args...), after_slot(E, slot, d, proc, args...) -> after(E, d, proc, [key = slot,] [with = list(args...)])",callees:&["om_after", "after_slot"],reasons:&[
            ("too_few_args", "fewer arguments than (E, delay, proc): malformed, fix the call"),
            ("named_arg", "a named argument among the call's arguments: the legacy varargs took them positionally, write the with = list(...) by hand"),
            ("arglist", "an arglist(...) spread as the handler's arguments: pass the list as with = L by hand"),
            ("value_used", "after_slot's result is used (it returned !!id, after() returns the id): convert by hand"),
            ("comment_in_moved_span", "a comment sits between the arguments being reordered: convert by hand"),
        ]};
pub const OWN_ADD:Spec=Spec{name:"own_add",about:"own_add(holder, var, value) -> rel_add(holder, var, value)",callees:&["own_add"],reasons:&[
            ("too_few_args", "fewer than (holder, var, value): malformed, fix the call"),
            ("dynamic_var", "the var is not written as nameof(x) or a literal, so its type cannot be read"),
            ("unresolved_receiver", "the static type of the holder is unknown (an untyped local, a chain, a call spanning lines): declare the var by hand"),
            ("unknown_var", "the holder's type has no such var"),
            ("untyped_var", "the var has no declared entity type (untyped, or a value type), or its type is declared in the vendored TGS API or the defines: nothing to declare it as"),
            ("scalar_var", "own_add on a var that is not a list"),
            ("extra_args", "a transfer argument (rel_add takes none): becomes move_into(holder, slot, item, actor =) in the transfers wave"),
        ]};
pub const OWN_SET:Spec=Spec{name:"own_set",about:"own_set(holder, var, value) -> rel_set(holder, var, value)",callees:&["own_set"],reasons:&[
            ("too_few_args", "fewer than (holder, var, value): malformed, fix the call"),
            ("dynamic_var", "the var is not written as nameof(x) or a literal, so its type cannot be read"),
            ("unresolved_receiver", "the static type of the holder is unknown (an untyped local, a chain, a call spanning lines): declare the var by hand"),
            ("unknown_var", "the holder's type has no such var"),
            ("untyped_var", "the var has no declared entity type (untyped, or a value type), or its type is declared in the vendored TGS API or the defines: nothing to declare it as"),
            ("list_var", "own_set on a list var: rel_set goes through the list state; convert by hand"),
            ("extra_args", "a transfer argument (rel_set takes none): becomes move_into(holder, slot, item, actor =) in the transfers wave"),
        ]};
pub const ALL:&[Spec]=&[OM_AFTER,OWN_ADD,OWN_SET];
pub fn find(name:&str)->Option<Spec>{ALL.iter().find(|spec|spec.name==name).copied()}
/// Exact metadata bytes for native utility delivery. No project/config/model
/// is read; output admission and checked publication stay with the caller.
pub fn write_list(out:&mut dyn std::io::Write)->std::io::Result<()>{
 for spec in ALL{writeln!(out,"{:<12} {}",spec.name,spec.about)?;}
 Ok(())
}


pub const HELP: &str = "analyze codemod: AST-aware rewriters (doc/rewrite/final_api.html, phase 2.5)

USAGE
  analyze codemod list
      The registered codemods, the legacy form each reads and what it becomes.
  analyze codemod NAME [--check] [--path PREFIX...] [--write-residue] [--sites] [--root DIR]
      Dry run on the tree: rewrites, residue by reason, the key-collision report. Exit 1 when there is
      residue not in the committed tools/analyze/codemods/NAME/residue.json (a new site that needs a human),
      when that file is missing, or when a key collision is unresolved. --write-residue writes
      residue.json (and keys.json when the codemod keys anything); it refuses with --path.
      --sites lists every residue site.
  analyze codemod NAME --apply [--path PREFIX...]
      Rewrite the files in place (no --path = the whole tree: phase 3 only, in a freeze window) and write
      data/codemod/NAME/revert.json.
  analyze codemod NAME --revert
      Undo the last --apply (each file must still be exactly what the codemod wrote).";
