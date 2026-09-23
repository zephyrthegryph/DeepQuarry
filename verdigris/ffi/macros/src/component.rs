//! `#[vg::component]`, `#[vg::query]` and `#[vg::events]`
//! (`doc/rewrite/rust_architecture.md` §5). The struct, its command enum,
//! the `Domain` impl, field validators and the `Schema` are always
//! `byondapi`-free (they build and run in `cargo test` on the host). The
//! FFI glue — the store, get/set/describe and bind procs — is generated
//! too, but only under `#[cfg(target_arch = "x86")]`, matching
//! `byondapi-sys`'s own gate: on a host build (`cargo test -p vg-core`,
//! x86_64) it is simply absent, so a component crate's host tests never
//! need `byondapi` as a dependency; on the real i686 build it is exactly
//! what `kind/pump.rs` used to write by hand (get_*/set_*/push_*/bind, the
//! `KindStore`, the `DomainRegistry` impl), so a component module is just
//! the struct, `#[vg::query]` and `#[vg::events]` — `rust_architecture.md`
//! §5's "a component crate writes the struct and nothing else."
//!
//! **Known gap** (tracked, not silently dropped): this keeps the generated
//! glue — and so the crate it expands into (today, `vg-gas`) — depending on
//! `byondapi`, which §3's target crate map reserves for `vg-ffi` alone.
//! Moving the glue to actually live in `vg-ffi` needs `vg-ffi` to depend on
//! the domain crates instead of the other way around (the crate map's
//! stated direction), which also touches gas's existing, unrelated
//! `vg-ffi` usage (`turf.rs`'s watch registration) — a bigger, cross-track
//! change coordinated with M2, not done here.

use proc_macro2::{Span, TokenStream};
use quote::{format_ident, quote};
use syn::parse::{Parse, ParseStream};
use syn::spanned::Spanned;
use syn::{Ident, LitInt, LitStr, Token};

// --- `#[component(...)]` on the struct ---------------------------------

struct ComponentArgs {
    domain: Ident,
    kind: LitInt,
    dm: LitStr,
}

impl Parse for ComponentArgs {
    fn parse(input: ParseStream) -> syn::Result<Self> {
        let mut domain = None;
        let mut kind = None;
        let mut dm = None;
        while !input.is_empty() {
            let key: Ident = input.parse()?;
            input.parse::<Token![=]>()?;
            match key.to_string().as_str() {
                "domain" => domain = Some(input.parse()?),
                "kind" => kind = Some(input.parse()?),
                "dm" => dm = Some(input.parse()?),
                "ports" => {
                    // Accepted and ignored here: which pipe ports a gas
                    // device exposes is the flow-law's business (M2), not
                    // the binding layer's. `[input, output]`.
                    let content;
                    syn::bracketed!(content in input);
                    let _: syn::punctuated::Punctuated<Ident, Token![,]> =
                        content.parse_terminated(Ident::parse, Token![,])?;
                }
                other => {
                    return Err(syn::Error::new(
                        key.span(),
                        format!("unknown #[component] argument `{other}`"),
                    ));
                }
            }
            if input.peek(Token![,]) {
                input.parse::<Token![,]>()?;
            }
        }
        Ok(Self {
            domain: domain.ok_or_else(|| input.error("#[component] needs `domain = ...`"))?,
            kind: kind.ok_or_else(|| input.error("#[component] needs `kind = <n>` (a small integer unique within the domain)"))?,
            dm: dm.ok_or_else(|| input.error("#[component] needs `dm = \"/path/to/type\"`"))?,
        })
    }
}

#[derive(Clone, Copy, PartialEq, Eq)]
enum Role {
    Config,
    State,
    Input,
}

struct FieldAttr {
    role: Role,
    unit: Option<LitStr>,
    range: Option<(syn::Expr, syn::Expr)>,
    default: Option<syn::Expr>,
    on_invalid: Option<Ident>,
    from: Vec<Ident>,
}

impl Parse for FieldAttr {
    fn parse(input: ParseStream) -> syn::Result<Self> {
        let role_ident: Ident = input.parse()?;
        let role = match role_ident.to_string().as_str() {
            "config" => Role::Config,
            "state" => Role::State,
            "input" => Role::Input,
            other => {
                return Err(syn::Error::new(
                    role_ident.span(),
                    format!("unknown field role `{other}` (expected config, state or input)"),
                ));
            }
        };
        let mut attr = FieldAttr {
            role,
            unit: None,
            range: None,
            default: None,
            on_invalid: None,
            from: Vec::new(),
        };
        while input.peek(Token![,]) {
            input.parse::<Token![,]>()?;
            if input.is_empty() {
                break;
            }
            let key: Ident = input.parse()?;
            input.parse::<Token![=]>()?;
            match key.to_string().as_str() {
                "unit" => attr.unit = Some(input.parse()?),
                "range" => {
                    let r: syn::ExprRange = input.parse()?;
                    let start = r
                        .start
                        .clone()
                        .ok_or_else(|| syn::Error::new(r.span(), "range needs a start, e.g. `0.0..=10.0`"))?;
                    let end = r
                        .end
                        .clone()
                        .ok_or_else(|| syn::Error::new(r.span(), "range needs an end, e.g. `0.0..=10.0`"))?;
                    attr.range = Some((*start, *end));
                }
                "default" => attr.default = Some(input.parse()?),
                "on_invalid" => attr.on_invalid = Some(input.parse()?),
                "from" => {
                    let content;
                    syn::bracketed!(content in input);
                    let list: syn::punctuated::Punctuated<Ident, Token![,]> =
                        content.parse_terminated(Ident::parse, Token![,])?;
                    attr.from = list.into_iter().collect();
                }
                other => {
                    return Err(syn::Error::new(
                        key.span(),
                        format!("unknown field attribute `{other}`"),
                    ));
                }
            }
        }
        Ok(attr)
    }
}

struct ParsedField {
    ident: Ident,
    ty: syn::Type,
    attr: FieldAttr,
}

fn pascal_case(ident: &Ident) -> Ident {
    let mut out = String::new();
    for part in ident.to_string().split('_') {
        let mut chars = part.chars();
        if let Some(first) = chars.next() {
            out.extend(first.to_uppercase());
            out.extend(chars);
        }
    }
    format_ident!("{out}", span = ident.span())
}

/// `Pump` -> `pump`, `GasPump` -> `gas_pump`: the lowercase prefix every
/// generated get/set/push/bind/query proc shares with its DM-side caller.
/// Mirrors `tools/build/lib/verdigris_bindings.ts`'s `snake()` character for
/// character (underscore before an uppercase letter that follows a
/// lowercase letter or digit, then lowercase) — not just today's one-word
/// `Pump`, so a future multi-word component name still gets the same
/// global proc name on both sides of the FFI boundary. `pub(crate)`: also
/// used by `query.rs` to name `#[vg::component]`'s generated helpers from
/// its own, separate macro invocation on the same struct (this module's
/// naming-convention contract).
pub(crate) fn snake_case(ident: &Ident) -> String {
    let name = ident.to_string();
    let mut out = String::with_capacity(name.len() + 4);
    let chars: Vec<char> = name.chars().collect();
    for (i, &c) in chars.iter().enumerate() {
        if i > 0 && c.is_ascii_uppercase() {
            let prev = chars[i - 1];
            if prev.is_ascii_lowercase() || prev.is_ascii_digit() {
                out.push('_');
            }
        }
        out.extend(c.to_lowercase());
    }
    out
}

fn is_bool_type(ty: &syn::Type) -> bool {
    quote!(#ty).to_string() == "bool"
}

/// A `#ty` value as a `ByondValue` (the two field types in use today: `f32`
/// converts directly, `bool` as 1.0/0.0 — `ByondValue` has no bool `From`).
fn value_to_byond(ty: &syn::Type, expr: TokenStream) -> TokenStream {
    if is_bool_type(ty) {
        quote! { ::byondapi::value::ByondValue::from(if #expr { 1.0f32 } else { 0.0f32 }) }
    } else {
        quote! { ::byondapi::value::ByondValue::from(#expr) }
    }
}

/// The reverse of [`value_to_byond`], as a fallible expression (`?` inside).
fn byond_to_value(ty: &syn::Type, expr: TokenStream) -> TokenStream {
    if is_bool_type(ty) {
        quote! { (#expr.get_number()? != 0.0) }
    } else {
        quote! { ((#expr.get_number()?) as #ty) }
    }
}

/// Expands `#[component(...)] struct Foo { ... }`.
pub fn expand(attr: proc_macro::TokenStream, item: proc_macro::TokenStream) -> proc_macro::TokenStream {
    let args = syn::parse_macro_input!(attr as ComponentArgs);
    let input = syn::parse_macro_input!(item as syn::ItemStruct);
    match expand_inner(&args, input) {
        Ok(ts) => ts.into(),
        Err(e) => e.to_compile_error().into(),
    }
}

fn expand_inner(args: &ComponentArgs, mut input: syn::ItemStruct) -> syn::Result<TokenStream> {
    let syn::Fields::Named(fields) = &mut input.fields else {
        return Err(syn::Error::new(input.span(), "#[component] needs a struct with named fields"));
    };

    let mut parsed = Vec::new();
    for field in &mut fields.named {
        let Some(ident) = field.ident.clone() else {
            continue;
        };
        let mut vg_attr = None;
        let mut kept = Vec::new();
        for a in field.attrs.drain(..) {
            if a.path().is_ident("vg") {
                if vg_attr.is_some() {
                    return Err(syn::Error::new(a.span(), "a field may have only one #[vg(...)]"));
                }
                let tokens = match &a.meta {
                    syn::Meta::List(list) => list.tokens.clone(),
                    _ => return Err(syn::Error::new(a.span(), "expected #[vg(role, ...)]")),
                };
                vg_attr = Some(syn::parse2::<FieldAttr>(tokens)?);
            } else {
                kept.push(a);
            }
        }
        field.attrs = kept;
        let Some(attr) = vg_attr else {
            return Err(syn::Error::new(
                ident.span(),
                format!("field `{ident}` needs a #[vg(config|state|input, ...)] attribute"),
            ));
        };
        if attr.role == Role::Config && attr.default.is_none() {
            return Err(syn::Error::new(ident.span(), "a config field needs `default = ...`"));
        }
        parsed.push(ParsedField {
            ident,
            ty: field.ty.clone(),
            attr,
        });
    }

    input.attrs.push(syn::parse_quote! {
        #[derive(::std::clone::Clone, ::std::fmt::Debug, ::std::cmp::PartialEq)]
    });

    let struct_ident = input.ident.clone();
    let vis = input.vis.clone();
    let kind_ident = format_ident!("{struct_ident}Kind");
    let command_ident = format_ident!("{struct_ident}Command");
    let domain_str = args.domain.to_string();
    let kind_lit = &args.kind;
    let dm_str = &args.dm;

    // Default field values (input/state fields fall back to `Default`).
    let default_fields = parsed.iter().map(|f| {
        let ident = &f.ident;
        match &f.attr.default {
            Some(expr) => quote! { #ident: (#expr) as _ },
            None => quote! { #ident: ::std::default::Default::default() },
        }
    });

    // Command enum: one variant per config/input field (state fields are
    // never written by a command DM can reach).
    let command_fields: Vec<&ParsedField> = parsed
        .iter()
        .filter(|f| matches!(f.attr.role, Role::Config | Role::Input))
        .collect();
    let command_variants = command_fields.iter().map(|f| {
        let variant = pascal_case(&f.ident);
        let ty = &f.ty;
        quote! { #variant(#ty) }
    });
    let apply_arms = command_fields.iter().map(|f| {
        let variant = pascal_case(&f.ident);
        let ident = &f.ident;
        quote! { #command_ident::#variant(v) => value.#ident = ::std::clone::Clone::clone(v) }
    });

    // Validators: one per config field (bounded ones clamp/reject; the rest
    // pass through, kept for uniform call sites in the FFI glue).
    let validators = parsed.iter().filter(|f| f.attr.role == Role::Config).map(|f| {
        let ident = &f.ident;
        let ty = &f.ty;
        let fn_ident = format_ident!("validate_{ident}");
        match &f.attr.range {
            Some((min, max)) => {
                let on_invalid = f
                    .attr
                    .on_invalid
                    .clone()
                    .unwrap_or_else(|| format_ident!("clamp", span = Span::call_site()));
                let call = match on_invalid.to_string().as_str() {
                    "clamp" => quote! { ::vg_core::component::clamp(v, (#min) as #ty, (#max) as #ty) },
                    "reject" => quote! { ::vg_core::component::reject_range(v, (#min) as #ty, (#max) as #ty) },
                    other => {
                        return syn::Error::new(
                            on_invalid.span(),
                            format!("on_invalid must be `clamp` or `reject`, got `{other}`"),
                        )
                        .to_compile_error();
                    }
                };
                quote! {
                    pub fn #fn_ident(v: #ty) -> ::std::result::Result<#ty, ::vg_core::component::FieldError> {
                        #call
                    }
                }
            }
            None => quote! {
                pub fn #fn_ident(v: #ty) -> ::std::result::Result<#ty, ::vg_core::component::FieldError> {
                    ::vg_core::component::identity(v)
                }
            },
        }
    });

    let field_names: Vec<&Ident> = parsed.iter().map(|f| &f.ident).collect();
    let field_roles: Vec<TokenStream> = parsed
        .iter()
        .map(|f| match f.attr.role {
            Role::Config => quote! { ::vg_core::component::FieldRole::Config },
            Role::State => quote! { ::vg_core::component::FieldRole::State },
            Role::Input => quote! { ::vg_core::component::FieldRole::Input },
        })
        .collect();
    let field_units: Vec<TokenStream> = parsed
        .iter()
        .map(|f| match &f.attr.unit {
            Some(u) => quote! { ::std::option::Option::Some(#u) },
            None => quote! { ::std::option::Option::None },
        })
        .collect();
    let field_name_strs: Vec<String> = field_names.iter().map(|i| i.to_string()).collect();
    let field_count = field_names.len();

    let glue = component_glue(&struct_ident, &kind_ident, &command_ident, dm_str, &parsed);

    Ok(quote! {
        #input

        #[doc = "Domain marker for `Domain`/`MainPort` (generated by #[vg::component])."]
        #[derive(::std::clone::Clone, ::std::marker::Copy, ::std::fmt::Debug, ::std::default::Default, ::std::cmp::PartialEq, ::std::cmp::Eq)]
        #vis struct #kind_ident;

        impl ::std::default::Default for #struct_ident {
            fn default() -> Self {
                Self { #(#default_fields),* }
            }
        }

        impl ::vg_core::owner::Domain for #kind_ident {
            type Value = #struct_ident;
            type Command = #command_ident;
            const NAME: &'static str = ::std::stringify!(#struct_ident);

            fn apply(value: &mut #struct_ident, cmd: &#command_ident) -> ::vg_core::owner::Applied {
                match cmd {
                    #(#apply_arms),*
                }
                ::vg_core::owner::Applied::default()
            }
        }

        #[derive(::std::clone::Clone, ::std::fmt::Debug, ::std::cmp::PartialEq)]
        #vis enum #command_ident {
            #(#command_variants),*
        }

        impl #struct_ident {
            /// Numeric component-kind id within its domain (a generated DM
            /// define, e.g. `VG_GAS_PUMP`).
            pub const KIND: u16 = #kind_lit;
            /// The domain this component belongs to (`rust_bindings.md` §1).
            pub const DOMAIN: &'static str = #domain_str;
            /// The DM type this component binds to.
            pub const DM_TYPE: &'static str = #dm_str;
            /// Field names in declaration order (for `vg_describe()`, §3).
            pub const FIELD_NAMES: [&'static str; #field_count] = [#(#field_name_strs),*];

            #(#validators)*

            /// This component's schema, for the generator and `vg_describe()`.
            #[must_use]
            pub fn schema() -> ::vg_core::component::Schema {
                ::vg_core::component::Schema {
                    domain: Self::DOMAIN,
                    kind: Self::KIND,
                    dm_type: Self::DM_TYPE,
                    fields: ::std::vec![
                        #(
                            ::vg_core::component::FieldSchema {
                                name: #field_name_strs,
                                role: #field_roles,
                                unit: #field_units,
                            }
                        ),*
                    ],
                }
            }
        }

        #glue
    })
}

/// The FFI glue (`rust_architecture.md` §5): the store, `DomainRegistry`
/// impl and every get/set/push/bind proc. See the module docs for the
/// `#[cfg(target_arch = "x86")]` gate and the known crate-boundary gap.
#[allow(clippy::too_many_lines)]
fn component_glue(
    struct_ident: &Ident,
    kind_ident: &Ident,
    command_ident: &Ident,
    dm: &LitStr,
    parsed: &[ParsedField],
) -> TokenStream {
    let lower = snake_case(struct_ident);
    let dm_path = dm.value();
    let shared_ident = format_ident!("__{struct_ident}Shared");
    let store_static = format_ident!("__{}_STORE", lower.to_uppercase());
    let registered_static = format_ident!("__{}_REGISTERED", lower.to_uppercase());
    let with_fn = format_ident!("__{lower}_with");
    let cell_of_fn = format_ident!("__{lower}_cell_of");
    let bind_fn = format_ident!("{lower}_bind");
    let bind_path = LitStr::new(&format!("/proc/{lower}_bind"), struct_ident.span());

    let config: Vec<&ParsedField> = parsed.iter().filter(|f| f.attr.role == Role::Config).collect();
    let state: Vec<&ParsedField> = parsed.iter().filter(|f| f.attr.role == Role::State).collect();
    let input: Vec<&ParsedField> = parsed.iter().filter(|f| f.attr.role == Role::Input).collect();

    // --- describe(): every field, value plus its declared unit -----------
    let describe_lines = parsed.iter().map(|f| {
        let name = f.ident.to_string();
        let ident = &f.ident;
        let suffix = f.attr.unit.as_ref().map(|u| format!(" {}", u.value())).unwrap_or_default();
        quote! { (#name.into(), ::std::format!("{}{}", v.#ident, #suffix)) }
    });

    // --- get_*/set_* (config), get_* (state), get_*/push_* (input) -------
    let mut procs = TokenStream::new();
    for f in &config {
        let field = &f.ident;
        let ty = &f.ty;
        let field_str = field.to_string();
        let get_fn = format_ident!("{lower}_get_{field}");
        let set_fn = format_ident!("{lower}_set_{field}");
        let get_path = LitStr::new(&format!("{dm_path}/proc/get_{field_str}"), field.span());
        let set_path = LitStr::new(&format!("{dm_path}/proc/set_{field_str}"), field.span());
        let validate = format_ident!("validate_{field}");
        let variant = pascal_case(field);
        let read_to_byond = value_to_byond(ty, quote! { v.#field });
        let stored_to_byond = value_to_byond(ty, quote! { v });
        let from_byond = byond_to_value(ty, quote! { value });
        procs.extend(quote! {
            #[cfg(target_arch = "x86")]
            #[::auxmacros::bind(#get_path)]
            fn #get_fn(entity: ::byondapi::value::ByondValue) -> ::eyre::Result<::byondapi::value::ByondValue> {
                let cell = #cell_of_fn(&entity)?;
                let v = #with_fn(|w| w.read(cell).ok_or_else(|| ::eyre::eyre!("{} row {cell} out of range", #dm)))?;
                ::std::result::Result::Ok(#read_to_byond)
            }

            #[cfg(target_arch = "x86")]
            #[::auxmacros::bind(#set_path)]
            fn #set_fn(entity: ::byondapi::value::ByondValue, value: ::byondapi::value::ByondValue) -> ::eyre::Result<::byondapi::value::ByondValue> {
                let cell = #cell_of_fn(&entity)?;
                let raw = #from_byond;
                let v = #struct_ident::#validate(raw).map_err(|e| ::eyre::eyre!("field `{}`: {}", #field_str, e))?;
                #with_fn(|w| w.submit(cell, #command_ident::#variant(v)).map_err(|e| ::eyre::eyre!("{e}")))?;
                ::std::result::Result::Ok(#stored_to_byond)
            }
        });
    }
    for f in &state {
        let field = &f.ident;
        let ty = &f.ty;
        let field_str = field.to_string();
        let get_fn = format_ident!("{lower}_get_{field}");
        let get_path = LitStr::new(&format!("{dm_path}/proc/get_{field_str}"), field.span());
        let read_to_byond = value_to_byond(ty, quote! { v.#field });
        procs.extend(quote! {
            #[cfg(target_arch = "x86")]
            #[::auxmacros::bind(#get_path)]
            fn #get_fn(entity: ::byondapi::value::ByondValue) -> ::eyre::Result<::byondapi::value::ByondValue> {
                let cell = #cell_of_fn(&entity)?;
                let v = #with_fn(|w| w.read(cell).ok_or_else(|| ::eyre::eyre!("{} row {cell} out of range", #dm)))?;
                ::std::result::Result::Ok(#read_to_byond)
            }
        });
    }
    for f in &input {
        let field = &f.ident;
        let ty = &f.ty;
        let field_str = field.to_string();
        let get_fn = format_ident!("{lower}_get_{field}");
        let push_fn = format_ident!("{lower}_push_{field}");
        let get_path = LitStr::new(&format!("{dm_path}/proc/get_{field_str}"), field.span());
        let push_path = LitStr::new(&format!("{dm_path}/proc/push_{field_str}"), field.span());
        let variant = pascal_case(field);
        let read_to_byond = value_to_byond(ty, quote! { v.#field });
        let pushed_to_byond = value_to_byond(ty, quote! { v });
        let from_byond = byond_to_value(ty, quote! { value });
        procs.extend(quote! {
            /// Rust's currently stored value, for the reconciler (§7):
            /// compare against the type's pure input proc.
            #[cfg(target_arch = "x86")]
            #[::auxmacros::bind(#get_path)]
            fn #get_fn(entity: ::byondapi::value::ByondValue) -> ::eyre::Result<::byondapi::value::ByondValue> {
                let cell = #cell_of_fn(&entity)?;
                let v = #with_fn(|w| w.read(cell).ok_or_else(|| ::eyre::eyre!("{} row {cell} out of range", #dm)))?;
                ::std::result::Result::Ok(#read_to_byond)
            }

            /// Pushed by generated wiring on a source change (§7). Never
            /// validated (an input has no declared range): identity.
            #[cfg(target_arch = "x86")]
            #[::auxmacros::bind(#push_path)]
            fn #push_fn(entity: ::byondapi::value::ByondValue, value: ::byondapi::value::ByondValue) -> ::eyre::Result<::byondapi::value::ByondValue> {
                let cell = #cell_of_fn(&entity)?;
                let v = #from_byond;
                #with_fn(|w| w.submit(cell, #command_ident::#variant(v)).map_err(|e| ::eyre::eyre!("{e}")))?;
                ::std::result::Result::Ok(#pushed_to_byond)
            }
        });
    }

    // --- bind(): entity, init_<config>..., <input>... ---------------------
    let bind_params = config
        .iter()
        .map(|f| {
            let p = format_ident!("init_{}", f.ident);
            quote! { #p: ::byondapi::value::ByondValue }
        })
        .chain(input.iter().map(|f| {
            let p = &f.ident;
            quote! { #p: ::byondapi::value::ByondValue }
        }));
    let config_assigns = config.iter().map(|f| {
        let field = &f.ident;
        let ty = &f.ty;
        let p = format_ident!("init_{}", f.ident);
        let validate = format_ident!("validate_{field}");
        let field_str = field.to_string();
        let from_byond = byond_to_value(ty, quote! { #p });
        quote! {
            #field: #struct_ident::#validate(#from_byond).map_err(|e| ::eyre::eyre!("field `{}`: {}", #field_str, e))?
        }
    });
    let input_assigns = input.iter().map(|f| {
        let field = &f.ident;
        let ty = &f.ty;
        let from_byond = byond_to_value(ty, quote! { #field });
        quote! { #field: #from_byond }
    });

    quote! {
        #[doc(hidden)]
        struct #shared_ident(::std::rc::Rc<::std::cell::RefCell<::vg_core::store::KindStore<#kind_ident>>>);

        #[cfg(target_arch = "x86")]
        impl ::vg_ffi::registry::DomainRegistry for #shared_ident {
            fn detach(&mut self, comp: ::vg_core::entity::ComponentRef) {
                if comp.kind != #struct_ident::KIND {
                    return;
                }
                self.0.borrow_mut().detach(comp.cell);
            }
            fn describe(&self, comp: ::vg_core::entity::ComponentRef) -> ::std::vec::Vec<(::std::string::String, ::std::string::String)> {
                if comp.kind != #struct_ident::KIND {
                    return ::std::vec::Vec::new();
                }
                let ::std::option::Option::Some(v) = self.0.borrow().read(comp.cell) else {
                    return ::std::vec::Vec::new();
                };
                ::std::vec![ #(#describe_lines),* ]
            }
            fn tick(&mut self) {
                self.0.borrow_mut().tick();
            }
            fn reset(&mut self) {
                *self.0.borrow_mut() = ::vg_core::store::KindStore::new();
            }
            fn drain_events(&mut self, out: &mut ::std::vec::Vec<(u16, f32, u8)>) {
                let mut raw = ::std::vec::Vec::new();
                self.0.borrow_mut().drain_events(&mut raw);
                out.extend(raw.into_iter().map(|(entity, id)| (#struct_ident::KIND, entity, id)));
            }
        }

        #[cfg(target_arch = "x86")]
        ::std::thread_local! {
            #[doc(hidden)]
            static #store_static: ::std::rc::Rc<::std::cell::RefCell<::vg_core::store::KindStore<#kind_ident>>> =
                ::std::rc::Rc::new(::std::cell::RefCell::new(::vg_core::store::KindStore::new()));
            #[doc(hidden)]
            static #registered_static: ::std::cell::Cell<bool> = const { ::std::cell::Cell::new(false) };
        }

        #[cfg(target_arch = "x86")]
        fn #with_fn<T>(f: impl FnOnce(&mut ::vg_core::store::KindStore<#kind_ident>) -> ::eyre::Result<T>) -> ::eyre::Result<T> {
            #registered_static.with(|done| {
                if !done.get() {
                    #store_static.with(|s| {
                        ::vg_ffi::registry::register_domain(DOMAIN as u32, ::std::boxed::Box::new(#shared_ident(::std::rc::Rc::clone(s))));
                    });
                    done.set(true);
                }
            });
            #store_static.with(|s| f(&mut s.borrow_mut()))
        }

        #[cfg(target_arch = "x86")]
        fn #cell_of_fn(entity: &::byondapi::value::ByondValue) -> ::eyre::Result<u32> {
            let comp = ::vg_ffi::entity::resolve(entity.get_number()?, DOMAIN, #struct_ident::KIND)?;
            ::std::result::Result::Ok(comp.cell)
        }

        #procs

        /// Creates the entity (if `entity` is 0) or reuses it, attaches a
        /// component seeded from the `init_*` values and the current
        /// inputs, and returns the entity handle (§4, §5). DM's base
        /// `on_materialize()` calls this once per component the type
        /// declares.
        #[cfg(target_arch = "x86")]
        #[::auxmacros::bind(#bind_path)]
        fn #bind_fn(entity: ::byondapi::value::ByondValue, #(#bind_params),*) -> ::eyre::Result<::byondapi::value::ByondValue> {
            let value = #struct_ident {
                #(#config_assigns,)*
                #(#input_assigns,)*
                ..::std::default::Default::default()
            };
            let id = ::vg_ffi::entity::bind_or_reuse(entity.get_number()?)?;
            let entity_v = ::vg_ffi::entity::entity_value(id);
            let cell = #with_fn(|w| w.bind(entity_v, value).map_err(|e| ::eyre::eyre!("{} bind: {}", #dm, e)))?;
            ::vg_ffi::entity::attach(id, DOMAIN, ::vg_core::entity::ComponentRef::new(#struct_ident::KIND, cell)).map_err(|e| ::eyre::eyre!("{e}"))?;
            ::std::result::Result::Ok(::byondapi::value::ByondValue::from(entity_v))
        }
    }
}
