//! `#[vg::component]`, `#[vg::query]` and `#[vg::events]`
//! (`doc/rewrite/rust_bindings.md` §2). Everything these generate is
//! `byondapi`-free: the struct, its command enum, the `Domain` impl and
//! field validators. The FFI glue that turns them into `get_*`/`set_*`
//! binds is hand-written per component (it is what differs between a gas
//! device and, later, a power consumer), following the same shape each
//! time; see `verdigris/domains/gas/src/kind/pump.rs`.

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
    })
}
