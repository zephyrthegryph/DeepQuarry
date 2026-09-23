//! `#[vg::events(Type)] pub enum FooEvent { ... }` (`rust_bindings.md` §3,
//! §8): assigns each variant a stable numeric id and a `snake_case` name,
//! for the generated DM dispatcher (`on_foo_bar()`) and the outbox event
//! stream (`EventKind` in `vg_core::outbox` stays the small, cross-domain
//! set; a component's own event carries this id as its `extra` field).

use proc_macro2::TokenStream;
use quote::quote;
use syn::Ident;

fn snake_case(ident: &Ident) -> String {
    let mut out = String::new();
    for (i, ch) in ident.to_string().chars().enumerate() {
        if ch.is_uppercase() {
            if i != 0 {
                out.push('_');
            }
            out.extend(ch.to_lowercase());
        } else {
            out.push(ch);
        }
    }
    out
}

pub fn expand(attr: proc_macro::TokenStream, item: proc_macro::TokenStream) -> proc_macro::TokenStream {
    // The owner type is required in the attribute position (`#[vg::events(Pump)]`)
    // for readability at the call site; it is documentation only; parsed and
    // then intentionally unused, since an inherent impl cannot carry a type
    // alias back to it.
    let _owner = syn::parse_macro_input!(attr as Ident);
    let input = syn::parse_macro_input!(item as syn::ItemEnum);
    let enum_ident = &input.ident;
    let vis = &input.vis;

    let mut variants = Vec::new();
    for v in &input.variants {
        if !matches!(v.fields, syn::Fields::Unit) {
            return syn::Error::new_spanned(v, "#[vg::events] variants carry no data")
                .to_compile_error()
                .into();
        }
        variants.push(v.ident.clone());
    }
    let n = variants.len();
    let names: Vec<String> = variants.iter().map(snake_case).collect();
    let ids: Vec<u8> = (0..variants.len()).map(|i| i as u8).collect();

    let out: TokenStream = quote! {
        #[derive(::std::clone::Clone, ::std::marker::Copy, ::std::fmt::Debug, ::std::cmp::PartialEq, ::std::cmp::Eq)]
        #vis enum #enum_ident {
            #(#variants),*
        }

        impl #enum_ident {
            /// `snake_case` names, in declaration order (the generated DM
            /// handler is `on_<component>_<name>`).
            pub const NAMES: [&'static str; #n] = [#(#names),*];

            /// A stable numeric id, generated in declaration order. Crosses
            /// to DM as an `Event`'s `extra` field.
            #[must_use]
            pub const fn id(self) -> u8 {
                match self {
                    #(Self::#variants => #ids),*
                }
            }

            #[must_use]
            pub fn name(self) -> &'static str {
                Self::NAMES[self.id() as usize]
            }

            #[must_use]
            pub fn from_id(id: u8) -> ::std::option::Option<Self> {
                match id {
                    #(#ids => ::std::option::Option::Some(Self::#variants),)*
                    _ => ::std::option::Option::None,
                }
            }
        }
    };
    out.into()
}
