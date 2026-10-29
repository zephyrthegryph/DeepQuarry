"""Extract pinned builtin declaration data at BUILD TIME, never at runtime.

The input is SpacemanDMM's Rust ``builtins_table!`` DSL, not DM source. The
native compiler remains the only DM parser and semantic owner. This generator
has no dreammaker dependency, executes no Rust/default expression and emits no
runtime slot, procedure ID, ABI or negative BYOND-inventory certificate.

The declaration DSL and its interpretation are adapted from SpacemanDMM
commit 0290db5c752fa292f9824521515b603a2afd11dc (GPL-3.0; see the vendored
LICENSE). Authorship: Tad Hardesty and SpacemanDMM contributors. Source hashes
and the limited authority scope are retained in every generated manifest.

Unsupported syntax aborts the entire extraction. Production generation also
requires exact pinned builtin and proc-macro bytes; it cannot silently bless a
new DSL, a changed macro interpretation or a partial catalog.
"""

import argparse
from dataclasses import dataclass
import hashlib
import json
from pathlib import Path
import re
import struct
import sys


REFERENCE_COMMIT = "0290db5c752fa292f9824521515b603a2afd11dc"
BUILTINS_SHA256 = "927c3979e2e36715c4fd5ee5db87d09a70da1d77805967cf1d58081c67a2a33a"
PROC_MACRO_SHA256 = "5d7f97effb8282b0ecb97778f690ff5bbf42bb15e735204823e2657dbf9087e9"
# These are the audited reference implementations for parent and var-flag rules.
# They are provenance for the rules below, not hashes of modified vendor files.
OBJECT_TREE_SHA256 = "14140324324826cf2d165215ebe547d740b3fa7f1b3e84cfd335654aba402f90"
AST_SHA256 = "09fa36aab0ce183a2e35da243ff919f6862e2af3e0c4b082d756a6345d303768"


class Unsupported(ValueError):
    """An input cannot yield an authoritative complete pinned declaration set."""


@dataclass(frozen=True)
class Token:
    text: str
    kind: str
    start: int
    end: int
    line: int


def rust_string(raw):
    """Decode only literal Rust strings; never evaluate an expression."""
    match = re.fullmatch(r'r(#+)?"(.*)"\1', raw, flags=re.DOTALL)
    if raw.startswith('r"') and raw.endswith('"'):
        return raw[2:-1]
    if match:
        hashes = len(match[1] or "")
        return raw[hashes + 2:-(hashes + 1)]
    if not raw.startswith('"') or not raw.endswith('"'):
        raise Unsupported("expected a literal Rust string")
    result = []
    at = 1
    while at < len(raw) - 1:
        char = raw[at]
        at += 1
        if char != "\\":
            result.append(char)
            continue
        if at >= len(raw) - 1:
            raise Unsupported("unterminated Rust string escape")
        escaped = raw[at]
        at += 1
        if escaped in {'n': '\n', 'r': '\r', 't': '\t', '0': '\0', '\\': '\\', '"': '"', "'": "'"}:
            result.append({'n': '\n', 'r': '\r', 't': '\t', '0': '\0', '\\': '\\', '"': '"', "'": "'"}[escaped])
        elif escaped == "x":
            digits = raw[at:at + 2]
            if not re.fullmatch(r"[0-7][0-9a-fA-F]", digits):
                raise Unsupported("unsupported Rust byte escape")
            result.append(chr(int(digits, 16)))
            at += 2
        elif escaped == "u":
            match = re.match(r"\{([0-9a-fA-F_]+)\}", raw[at:])
            if not match:
                raise Unsupported("unsupported Rust Unicode escape")
            digits = match[1].replace("_", "")
            value = int(digits, 16)
            if not 1 <= len(digits) <= 6 or value > 0x10FFFF or 0xD800 <= value <= 0xDFFF:
                raise Unsupported("invalid Rust Unicode scalar")
            result.append(chr(value))
            at += match.end()
        elif escaped in "\r\n":
            if escaped == "\r" and raw[at:at + 1] == "\n":
                at += 1
            while at < len(raw) - 1 and raw[at].isspace():
                at += 1
        else:
            raise Unsupported(f"unsupported Rust escape \\{escaped}")
    return "".join(result)


def tokens(source):
    """A strict Rust-DSL lexer; strings/comments cannot create declarations."""
    result = []
    at = 0
    line = 1
    while at < len(source):
        start, source_line = at, line
        tail = source[at:]
        if source[at].isspace():
            line += source[at] == "\n"
            at += 1
            continue
        if tail.startswith("//"):
            end = source.find("\n", at)
            end = len(source) if end < 0 else end
            if tail.startswith("///") and not tail.startswith("////"):
                result.append(Token(source[at + 3:end], "doc", start, end, source_line))
            at = end
            continue
        if tail.startswith("/*"):
            depth, at = 1, at + 2
            while at < len(source) and depth:
                if source.startswith("/*", at):
                    depth += 1
                    at += 2
                elif source.startswith("*/", at):
                    depth -= 1
                    at += 2
                else:
                    line += source[at] == "\n"
                    at += 1
            if depth:
                raise Unsupported(f"line {source_line}: unterminated Rust comment")
            if tail.startswith("/**") and not tail.startswith("/***"):
                result.append(Token(source[start + 3:at - 2], "doc", start, at, source_line))
            continue
        raw = re.match(r'r(#+)?"', tail)
        if raw:
            hashes = raw[1] or ""
            closing = '"' + hashes
            end = source.find(closing, at + raw.end())
            if end < 0:
                raise Unsupported(f"line {source_line}: unterminated raw Rust string")
            at = end + len(closing)
            line += source[start:at].count("\n")
            result.append(Token(source[start:at], "string", start, at, source_line))
            continue
        if source[at] == '"':
            at += 1
            while at < len(source):
                if source[at] == "\\":
                    at += 2
                elif source[at] == '"':
                    at += 1
                    break
                else:
                    at += 1
            else:
                raise Unsupported(f"line {source_line}: unterminated Rust string")
            raw = source[start:at]
            rust_string(raw)
            line += raw.count("\n")
            result.append(Token(raw, "string", start, at, source_line))
            continue
        ident = re.match(r"[A-Za-z_][A-Za-z_0-9]*", tail)
        if ident:
            at += ident.end()
            result.append(Token(ident[0], "ident", start, at, source_line))
            continue
        number = re.match(r"(?:[0-9]+(?:\.[0-9]+)?)(?:[eE][+-]?[0-9]+)?", tail)
        if number:
            at += number.end()
            result.append(Token(number[0], "number", start, at, source_line))
            continue
        if source[at].isascii() and not source[at].isalnum():
            at += 1
            result.append(Token(source[start:at], "punct", start, at, source_line))
            continue
        raise Unsupported(f"line {line}: unsupported Rust-DSL character {source[at]!r}")
    return result


def path(parts):
    return "/" + "/".join(parts) if parts else "/"


FLAGS = {
    "global": ("static", 1), "static": ("static", 1), "const": ("const", 4),
    "tmp": ("tmp", 8), "final": ("final", 16),
    "SpacemanDMM_final": ("final", 16),
    "SpacemanDMM_private": ("private", 32),
    "SpacemanDMM_protected": ("protected", 64),
}


class Parser:
    def __init__(self, source):
        self.source = source
        self.tokens = tokens(source)
        self.at = 0
        self.declarations = []
        self.constants = {}
        for index in range(len(self.tokens) - 6):
            row = self.tokens[index:index + 7]
            if (row[0].text == "const" and row[1].text in ("DM_VERSION", "DM_BUILD")
                    and [token.text for token in row[2:5]] == [":", "i32", "="]
                    and row[5].kind == "number" and row[6].text == ";"):
                if row[1].text in self.constants:
                    self.fail("duplicate pinned version constant", row[1])
                self.constants[row[1].text] = int(row[5].text)

    def fail(self, reason, token=None):
        token = token or (self.tokens[self.at] if self.at < len(self.tokens) else self.tokens[-1])
        raise Unsupported(f"line {token.line}: {reason}")

    def peek(self, text):
        return self.at < len(self.tokens) and self.tokens[self.at].text == text

    def take(self, text=None):
        if self.at == len(self.tokens):
            self.fail("unexpected end of builtin table")
        token = self.tokens[self.at]
        if text is not None and token.text != text:
            self.fail(f"expected {text!r}, found {token.text!r}", token)
        self.at += 1
        return token

    def balanced(self, opening, closing):
        self.take(opening)
        start = self.at
        stack = [closing]
        pairs = {"(": ")", "[": "]", "{": "}"}
        while stack:
            token = self.take()
            if token.kind in ("string", "doc"):
                continue
            if token.text in pairs:
                stack.append(pairs[token.text])
            elif token.text in (")", "]", "}"):
                if token.text != stack.pop():
                    self.fail("mismatched Rust-DSL delimiters", token)
        return self.tokens[start:self.at - 1]

    def raw(self, values):
        return None if not values else self.source[values[0].start:values[-1].end]

    def attributes(self):
        result = []
        while self.at < len(self.tokens):
            if self.tokens[self.at].kind == "doc":
                result.append({"name": "doc", "value": self.take().text})
                continue
            if not self.peek("#"):
                break
            self.take("#")
            values = self.balanced("[", "]")
            if (len(values) == 4 and values[0].text == "dm_ref"
                    and values[1].text == "(" and values[2].kind == "string"
                    and values[3].text == ")"):
                result.append({"name": "dm_ref", "value": rust_string(values[2].text)})
            elif (len(values) == 3 and values[0].text == "doc" and values[1].text == "="
                  and values[2].kind == "string"):
                result.append({"name": "doc", "value": rust_string(values[2].text)})
            else:
                self.fail(f"unsupported builtin attribute {self.raw(values)!r}", values[0] if values else None)
        return result

    def default(self, values):
        if (len(values) < 4 or values[0].kind != "ident" or values[1].text != "!"
                or values[2].text != "(" or values[-1].text != ")"):
            self.fail(f"unsupported builtin default {self.raw(values)!r}", values[0])
        name, inner = values[0].text, values[3:-1]
        if name == "int":
            negative = bool(inner and inner[0].text == "-")
            if negative:
                inner = inner[1:]
            if len(inner) != 1:
                self.fail("int! default is not a pinned literal or version constant", values[0])
            value = inner[0]
            if value.kind == "number" and re.fullmatch(r"[0-9]+", value.text):
                number = int(value.text)
            elif value.text in self.constants:
                number = self.constants[value.text]
            else:
                self.fail(f"unknown int! constant {value.text!r}", value)
            number = -number if negative else number
            if not -(2 ** 31) <= number < 2 ** 31:
                self.fail("int! default is outside the pinned i32 range", value)
            bits = struct.unpack("<I", struct.pack("<f", number))[0]
            return {"syntax": self.raw(values), "constant": {"kind": "number", "f32_bits": bits}}
        if name == "string" and len(inner) == 1 and inner[0].kind == "string":
            return {"syntax": self.raw(values), "constant": {"kind": "text", "value": rust_string(inner[0].text)}}
        if name == "path":
            parts = []
            at = 0
            while at < len(inner):
                if inner[at].text != "/" or at + 1 >= len(inner) or inner[at + 1].kind != "ident":
                    self.fail("unsupported path! default", values[0])
                parts.append(inner[at + 1].text)
                at += 2
            return {"syntax": self.raw(values), "constant": {"kind": "type_path", "value": path(parts)}}
        self.fail(f"unsupported builtin default macro {name!r}", values[0])

    def parameters(self, values):
        groups = []
        start = 0
        depth = 0
        for at, token in enumerate(values):
            if token.kind == "punct":
                depth += token.text in ("(", "[", "{")
                depth -= token.text in (")", "]", "}")
                if token.text == "," and depth == 0:
                    groups.append(values[start:at])
                    start = at + 1
        if start < len(values):
            groups.append(values[start:])
        result = []
        for group in groups:
            if not group or group[0].kind != "ident":
                self.fail("builtin parameter must be a simple name", group[0] if group else None)
            default = group[2:] if len(group) > 1 and group[1].text == "=" else []
            if len(group) > 1 and not default:
                self.fail("unsupported builtin parameter declaration", group[1])
            if default:
                # ProcArgument::parse consumes these Rust expressions, but the
                # pinned proc macro intentionally does not pass them to the tree.
                simple = (len(default) == 1 and default[0].kind in ("ident", "number", "string"))
                member = (len(default) == 3 and default[0].kind == "ident"
                          and default[1].text == "." and default[2].kind == "ident")
                signed = (len(default) == 2 and default[0].text == "-" and default[1].kind == "number")
                if not (simple or member or signed):
                    self.fail("unsupported authored builtin parameter default", default[0])
            result.append({
                "name": group[0].text,
                "type_path": [], "flags": [], "input_annotation": None,
                "default": None, "source_default_syntax": self.raw(default),
            })
        return result

    def entry(self, parts, body, attributes, line):
        if not parts:
            self.fail("empty builtin declaration path")
        boundaries = [index for index, part in enumerate(parts) if part in ("var", "proc", "verb")]
        boundary = boundaries[0] if boundaries else None
        base = {"ordinal": len(self.declarations), "path_syntax": "/".join(parts),
                "source_line": line, "attributes": attributes}
        if body[0] == "callable":
            if boundary is not None:
                if parts[boundary] == "var" or len(parts) - boundary != 2:
                    self.fail("invalid builtin callable declaration path")
                owner, name = path(parts[:boundary]), parts[-1]
                kind = parts[boundary]
                form = "declare"
            else:
                owner, name, kind, form = path(parts[:-1]), parts[-1], "proc", "implicit"
            base.update(kind="callable", owner=owner, name=name, callable_kind=kind,
                        form=form, parameters=body[1], return_annotation=None,
                        source_parameter_defaults_discarded=True,
                        variadic="not_expressed_by_reference_dsl")
        elif body[0] == "field" or boundary is not None and parts[boundary] == "var":
            if boundary is not None:
                if parts[boundary] != "var":
                    self.fail("builtin proc path used as a field")
                owner, tail = path(parts[:boundary]), list(parts[boundary + 1:])
                flags, spelling, bits = set(), [], 0
                while tail and tail[0] in FLAGS:
                    flag = tail.pop(0)
                    spelling.append(flag)
                    flags.add(FLAGS[flag][0])
                    bits |= FLAGS[flag][1]
                if not tail:
                    self.fail("builtin field has no name")
                declared_type, name, form = tail[:-1], tail[-1], "declare"
            else:
                owner, name, form = path(parts[:-1]), parts[-1], "override"
                declared_type, flags, spelling, bits = None, None, None, None
            base.update(kind="field", owner=owner, name=name, form=form,
                        type_path=declared_type, flags=sorted(flags) if flags is not None else None,
                        flag_syntax=spelling, reference_flag_bits=bits, default=body[1])
        else:
            if boundary is not None:
                self.fail("incomplete builtin declaration path")
            base.update(kind="type", path=path(parts))
        self.declarations.append(base)

    def group(self, prefix=(), inherited=()):
        while not self.peek("}"):
            attrs = list(inherited) + self.attributes()
            start = self.tokens[self.at] if self.at < len(self.tokens) else None
            parts = list(prefix)
            if start is not None and start.kind == "ident":
                parts.append(self.take().text)
            while self.peek("/"):
                self.take("/")
                token = self.take()
                if token.kind != "ident":
                    self.fail("builtin path component is not an identifier", token)
                parts.append(token.text)
            if self.peek("{"):
                self.take("{")
                self.group(tuple(parts), tuple(attrs))
                self.take("}")
                continue
            if self.peek("="):
                self.take("=")
                values = []
                depth = 0
                while not (self.peek(";") and depth == 0):
                    token = self.take()
                    if token.kind == "punct":
                        depth += token.text in ("(", "[", "{")
                        depth -= token.text in (")", "]", "}")
                        if depth < 0:
                            self.fail("unbalanced builtin default", token)
                    values.append(token)
                self.take(";")
                if not values:
                    self.fail("empty builtin field default")
                body = ("field", self.default(values))
            elif self.peek("("):
                body = ("callable", self.parameters(self.balanced("(", ")")))
                self.take(";")
            else:
                self.take(";")
                body = ("none", None)
            self.entry(tuple(parts), body, attrs, start.line if start is not None else 0)

    def parse(self):
        locations = [index for index in range(len(self.tokens) - 2)
                     if self.tokens[index].text == "builtins_table"
                     and self.tokens[index + 1].text == "!"
                     and self.tokens[index + 2].text == "{"]
        if len(locations) != 1:
            raise Unsupported(f"expected one builtin table, found {len(locations)}")
        self.at = locations[0] + 3
        self.group()
        self.take("}")
        return self.declarations


def hierarchy(declarations):
    """Pinned ObjectTreeBuilder parent rules, not runtime BYOND hierarchy."""
    types = {"/": {"path": "/", "parent": None, "parent_rule": "root"}}
    defaults = {}

    def ensure(owner):
        parts = owner.strip("/").split("/") if owner != "/" else []
        for length in range(1, len(parts) + 1):
            value = path(parts[:length])
            if value not in types:
                types[value] = {"path": value}

    for declaration in declarations:
        ensure(declaration["path"] if declaration["kind"] == "type" else declaration["owner"])
        if declaration["kind"] == "field" and declaration["name"] == "parent_type":
            defaults[declaration["owner"]] = declaration["default"]
    roots = {"/datum", "/list", "/alist", "/savefile", "/world", "/vector", "/pixloc", "/callee"}
    special = {"/atom": "/datum", "/turf": "/atom", "/area": "/atom",
               "/obj": "/atom/movable", "/mob": "/atom/movable"}
    for name, row in types.items():
        if name == "/":
            continue
        if name in roots:
            parent, rule = "/", "pinned_nonparentable_root"
        elif name in special:
            parent, rule = special[name], "pinned_builtin_family"
        elif name in defaults:
            default = defaults[name]
            if default is None and name == "/client":
                parent, rule = "/", "pinned_client_root"
            elif default is not None and default["constant"]["kind"] in ("type_path", "text"):
                parent, rule = default["constant"]["value"] or "/", "declared_parent_type_default"
            else:
                raise Unsupported(f"unsupported pinned parent_type default for {name}")
        elif name == "/client":
            parent, rule = "/", "pinned_client_root"
        else:
            parent = name.rsplit("/", 1)[0] or "/datum"
            rule = "lexical_parent" if parent != "/datum" or name.count("/") > 1 else "implicit_datum"
        if parent not in types:
            raise Unsupported(f"pinned parent {parent!r} of {name} has no type declaration")
        row.update(parent=parent, parent_rule=rule)
    for name in types:
        seen = set()
        cursor = name
        while cursor is not None:
            if cursor in seen:
                raise Unsupported(f"cyclic pinned builtin hierarchy at {cursor}")
            seen.add(cursor)
            cursor = types[cursor]["parent"]
    return list(types.values())


def extract_declarations(source):
    """Draft extraction for focused tests; not a completeness certificate."""
    return Parser(source).parse()


def sha256(value):
    return hashlib.sha256(value).hexdigest()


def build_manifest(source_bytes, macro_bytes):
    if sha256(source_bytes) != BUILTINS_SHA256:
        raise Unsupported("builtin source bytes do not match the pinned reference; no manifest emitted")
    if sha256(macro_bytes) != PROC_MACRO_SHA256:
        raise Unsupported("builtin proc-macro bytes do not match the pinned interpretation; no manifest emitted")
    declarations = extract_declarations(source_bytes.decode("utf-8"))
    types = hierarchy(declarations)
    counts = {kind: sum(row["kind"] == kind for row in declarations)
              for kind in ("type", "field", "callable")}
    return {
        "format": "dq-native-builtin-semantic-declarations-v1",
        "reference": {
            "project": "SpacemanDMM", "commit": REFERENCE_COMMIT, "license": "GPL-3.0",
            "attribution": "Tad Hardesty and SpacemanDMM contributors",
            "builtin_source": "crates/dreammaker/src/builtins.rs", "builtin_sha256": BUILTINS_SHA256,
            "macro_source": "crates/builtins-proc-macro/src/lib.rs", "macro_sha256": PROC_MACRO_SHA256,
            "parent_rules_source": "crates/dreammaker/src/objtree.rs", "parent_rules_sha256": OBJECT_TREE_SHA256,
            "var_flags_source": "crates/dreammaker/src/ast.rs", "var_flags_sha256": AST_SHA256,
        },
        "coverage": {
            "pinned_dsl_declarations_complete": True,
            "runtime_engine_inventory_complete": False,
            "runtime_slots_or_abi": False,
            "default_defines_preprocessor_macros": False,
            "compiler_metadata_import_complete": False,
            "parameter_defaults": "authored syntax preserved; effective defaults discarded by pinned macro",
            "return_annotations": "empty in pinned add_builtin_proc; comments are not type declarations",
        },
        "counts": {**counts, "hierarchy_types": len(types)},
        "types": types,
        "declarations": declarations,
    }


def build_rust_hierarchy(source_bytes, macro_bytes):
    """Generate test/oracle-only native EngineSeed input from exact pinned bytes.

    Only hierarchy crosses this boundary. No declarations, signatures, runtime
    slots, member-presence inventory or ABI data are emitted by this projection.
    """
    manifest = build_manifest(source_bytes, macro_bytes)
    parents = [(row["path"], row["parent"]) for row in manifest["types"]]
    if len(parents) != 28 or len({name for name, _ in parents}) != 28:
        raise Unsupported("pinned hierarchy owner count changed; no Rust seed emitted")
    if parents[0] != ("/", None):
        raise Unsupported("pinned hierarchy root changed; no Rust seed emitted")
    names = {name for name, _ in parents}
    for name, parent in parents:
        if not re.fullmatch(r"/(?:[A-Za-z_][A-Za-z_0-9]*(?:/[A-Za-z_][A-Za-z_0-9]*)*)?", name):
            raise Unsupported("unsupported Rust hierarchy path spelling")
        if (name != "/" and parent not in names) or (name == "/" and parent is not None):
            raise Unsupported("pinned hierarchy has an unproved parent")
    facts = {
        "format": "dq-reference-checker-hierarchy-v1",
        "reference_commit": REFERENCE_COMMIT,
        "builtin_sha256": BUILTINS_SHA256,
        "macro_sha256": PROC_MACRO_SHA256,
        "parent_rules_sha256": OBJECT_TREE_SHA256,
        "parents": parents,
    }
    canonical = json.dumps(facts, sort_keys=True, separators=(",", ":")).encode("ascii")
    facts_hash = sha256(canonical)
    seed_identity = sha256(b"dq-reference-hierarchy-seed-v1\0" + canonical)[:32]
    schema_identity = sha256(b"dq-reference-hierarchy-schema-v1\0" + canonical)[:32]
    rows = "\n".join(
        f"    ({json.dumps(name)}, " + (f"Some({json.dumps(parent)})" if parent is not None else "None") + "),"
        for name, parent in parents
    )
    return f'''// @generated by tools/dmb/scripts/native_builtin_manifest.py --rust-hierarchy-output
// Test/oracle input ONLY. Do not use as the production engine default.
// Pinned hierarchy adapted from SpacemanDMM (GPL-3.0),
// Tad Hardesty and SpacemanDMM contributors. No runtime JSON parsing.
// Only these 28 path/parent facts are certified within the pinned SDK scope.
// Empty member inventory is INCOMPLETE: no runtime slot, ABI or absence claims.

use dm_ir::{{SymbolId, SymbolTable}};
use dm_tree::{{frontend::EngineSeed, EngineHierarchy}};
use std::sync::Arc;

pub const REFERENCE_COMMIT: &str = "{REFERENCE_COMMIT}";
pub const BUILTIN_SOURCE_SHA256: &str = "{BUILTINS_SHA256}";
pub const PROC_MACRO_SHA256: &str = "{PROC_MACRO_SHA256}";
pub const PARENT_RULES_SHA256: &str = "{OBJECT_TREE_SHA256}";
pub const HIERARCHY_FACTS_SHA256: &str = "{facts_hash}";
pub const HIERARCHY_ONLY: bool = true;
pub const MEMBER_INVENTORY_COMPLETE: bool = false;

pub const PARENTS: &[(&str, Option<&str>)] = &[
{rows}
];

pub fn seed() -> EngineSeed {{
    let mut symbols = SymbolTable::default();
    for (path, _) in PARENTS {{
        symbols.intern(path).expect("pinned hierarchy symbol collision");
    }}
    let parents = PARENTS.iter().map(|(path, parent)| (
        SymbolId::of(path), parent.map(SymbolId::of),
    )).collect();
    EngineSeed {{
        identity: 0x{seed_identity}u128,
        symbols,
        hierarchy: EngineHierarchy {{ schema: 0x{schema_identity}u128, parents }},
        intrinsics: Arc::from([]),
        fields: Arc::from([]),
    }}
}}
'''



def checker_catalog_rows(manifest):
    """Fixed DSL facts, not runtime ABI/slot inventory or a second DM model."""
    rows = []
    flags = {"static": 1, "const": 2, "tmp": 4}
    forms = {"declare": 1, "override": 2, "implicit": 3}
    for row in manifest["declarations"]:
        kind = row["kind"]
        out = {"ordinal": row["ordinal"], "owner": row.get("owner", row.get("path")),
               "name": row.get("name", ""), "form": 0 if kind == "type" else forms[row["form"]],
               "kind": 0 if kind == "type" else 1 if kind == "field" else 3 if row["callable_kind"] == "verb" else 2,
               "type_path": None, "flags": None, "reference_flags": None,
               "default_syntax": None, "default": None, "parameters": []}
        if kind == "field":
            if row["flags"] is not None and any(flag not in flags for flag in row["flags"]):
                raise Unsupported("checker import has an unsupported native variable flag")
            out.update(type_path=None if row["type_path"] is None else "/".join(row["type_path"]),
                       flags=None if row["flags"] is None else sum(flags[flag] for flag in row["flags"]),
                       reference_flags=row["reference_flag_bits"],
                       default_syntax=None if row["default"] is None else row["default"]["syntax"],
                       default=None if row["default"] is None else row["default"]["constant"])
        elif kind == "callable":
            if row["return_annotation"] is not None or not row["source_parameter_defaults_discarded"]:
                raise Unsupported("checker import has unproved effective callable metadata")
            for param in row["parameters"]:
                if param["type_path"] or param["flags"] or param["default"] is not None or param["input_annotation"] is not None:
                    raise Unsupported("checker import has unsupported effective parameter metadata")
            out["parameters"] = [(p["name"], p["source_default_syntax"]) for p in row["parameters"]]
        rows.append(out)
    return rows


def checker_catalog_bytes(manifest, rows):
    out = bytearray(b"dq-pinned-checker-builtin-catalog-v1\0")
    def frame(value):
        data = value.encode("utf-8")
        out.extend(struct.pack("<Q", len(data)))
        out.extend(data)
    def optional(value, emit):
        out.append(value is not None)
        if value is not None:
            emit(value)
    ref = manifest["reference"]
    for key in ("commit", "builtin_sha256", "macro_sha256", "parent_rules_sha256", "var_flags_sha256"):
        frame(ref[key])
    out.extend(struct.pack("<Q", len(manifest["types"])))
    for row in manifest["types"]:
        frame(row["path"])
        optional(row["parent"], frame)
    out.extend(struct.pack("<Q", len(rows)))
    for row in rows:
        out.extend(struct.pack("<I", row["ordinal"]))
        frame(row["owner"]); frame(row["name"])
        out.extend((row["form"], row["kind"]))
        optional(row["type_path"], frame)
        optional(row["flags"], lambda value: out.extend(struct.pack("<I", value)))
        optional(row["reference_flags"], lambda value: out.extend(struct.pack("<I", value)))
        optional(row["default_syntax"], frame)
        default = row["default"]
        if default is None:
            out.append(0)
        elif default["kind"] == "number":
            out.append(1); out.extend(struct.pack("<I", default["f32_bits"]))
        elif default["kind"] in ("text", "type_path"):
            out.append(2 if default["kind"] == "text" else 3); frame(default["value"])
        else:
            raise Unsupported("checker import default cannot be represented exactly")
        out.extend(struct.pack("<Q", len(row["parameters"])))
        for name, source_default in row["parameters"]:
            frame(name); optional(source_default, frame)
    return bytes(out)


def build_rust_checker_catalog(source_bytes, macro_bytes):
    manifest = build_manifest(source_bytes, macro_bytes)
    if manifest["counts"] != {"type": 20, "field": 444, "callable": 378, "hierarchy_types": 28}:
        raise Unsupported("pinned checker declaration counts changed")
    rows = checker_catalog_rows(manifest)
    digest = sha256(checker_catalog_bytes(manifest, rows))
    def string(value):
        # All pinned values are representable in Rust's JSON-compatible subset.
        if any(ord(ch) < 32 for ch in value):
            raise Unsupported("checker Rust catalog needs an unsupported string escape")
        return json.dumps(value, ensure_ascii=False)
    def option(value, emit=string):
        return "None" if value is None else "Some(" + emit(value) + ")"
    lines = ["// @generated by native_builtin_manifest.py --rust-checker-catalog-output",
             "// Pinned SpacemanDMM GPL-3.0, Tad Hardesty and contributors.",
             "// Checker semantic facts only; NEVER runtime ABI/slot completeness.",
             "use super::{RawBuiltin, RawDefault, RawParameter};",
             f'pub(super) const FACTS_SHA256: &str = "{digest}";',
             "pub(super) const PARENTS: &[(&str, Option<&str>)] = &["]
    for row in manifest["types"]:
        lines.append(f'    ({string(row["path"])}, {option(row["parent"])}),')
    lines += ["];", "pub(super) const ROWS: &[RawBuiltin] = &["]
    for row in rows:
        default = row["default"]
        raw_default = "None" if default is None else (
            f'Some(RawDefault::Number({default["f32_bits"]}))' if default["kind"] == "number" else
            f'Some(RawDefault::{"Text" if default["kind"] == "text" else "Type"}({string(default["value"])}))')
        params = ', '.join('RawParameter { name: '+string(name)+', source_default: '+option(value)+' }' for name,value in row["parameters"])
        lines.append('    RawBuiltin { ordinal: '+str(row["ordinal"])+', owner: '+string(row["owner"])+', name: '+string(row["name"])+', form: '+str(row["form"])+', kind: '+str(row["kind"])+', type_path: '+option(row["type_path"])+', flags: '+option(row["flags"],str)+', reference_flags: '+option(row["reference_flags"],str)+', default_syntax: '+option(row["default_syntax"])+', default: '+raw_default+', parameters: &['+params+'] },')
    return '\n'.join(lines+["];", ""])

def main(argv=None):
    tools = Path(__file__).resolve().parents[2]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, default=tools / "analyze/vendor/dreammaker/src/builtins.rs")
    parser.add_argument("--macro-source", type=Path, default=tools / "analyze/vendor/builtins-proc-macro/src/lib.rs")
    parser.add_argument("--output", type=Path, help="otherwise write JSON to stdout")
    parser.add_argument("--check", type=Path, help="compare an existing manifest without writing it")
    parser.add_argument("--rust-hierarchy-output", type=Path,
                        help="write hierarchy-only Rust EngineSeed helper for test/oracle inputs")
    parser.add_argument("--rust-checker-catalog-output", type=Path, help="emit exact checker-qualified native semantic catalog (not runtime inventory)")
    args = parser.parse_args(argv)
    if sum(value is not None for value in (args.output, args.check, args.rust_hierarchy_output, args.rust_checker_catalog_output)) > 1:
        parser.error("choose one manifest or Rust output")
    try:
        source_bytes, macro_bytes = args.source.read_bytes(), args.macro_source.read_bytes()
        if args.rust_checker_catalog_output is not None:
            args.rust_checker_catalog_output.write_text(build_rust_checker_catalog(source_bytes, macro_bytes), encoding="utf-8", newline="\n")
            return 0
        if args.rust_hierarchy_output is not None:
            text = build_rust_hierarchy(source_bytes, macro_bytes)
            args.rust_hierarchy_output.write_text(text, encoding="utf-8", newline="\n")
            return 0
        manifest = build_manifest(source_bytes, macro_bytes)
        text = json.dumps(manifest, indent=2, ensure_ascii=False) + "\n"
        if args.check is not None:
            if args.check.read_text(encoding="utf-8") != text:
                print("native builtin manifest differs", file=sys.stderr)
                return 1
        elif args.output is not None:
            args.output.write_text(text, encoding="utf-8", newline="\n")
        else:
            print(text, end="")
        return 0
    except (OSError, UnicodeError, Unsupported) as error:
        print(f"native builtin manifest rejected: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
