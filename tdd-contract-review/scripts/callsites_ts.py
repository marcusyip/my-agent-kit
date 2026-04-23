#!/usr/bin/env python3
# callsites_ts.py — AST-based TypeScript/TSX call-site extractor for lsp_tree.py.
#
# Parses the file with tree-sitter-typescript (TSX grammar for .tsx/.jsx, TS
# grammar for .ts/.js), locates the requested symbol, and emits every
# call_expression inside its body as JSON — same contract as callsites.rb:
#
#   {
#     "start_line": 1-indexed, "end_line": 1-indexed,
#     "calls": [{"line": 0-indexed, "col": 0-indexed, "name": str}, ...]
#   }
#
# Symbol grammar (mirrors callsites.rb / Solargraph's convention):
#   "Foo#bar"   instance method (non-static)
#   "Foo.bar"   static method · namespace member · object-literal arrow pair
#   "Foo"       class body · function · const-arrow at module scope · namespace
#   "bar"       free function / const-arrow / hook at module scope
#
# Positions: start/end are 1-indexed (display-oriented). Call line/col are
# 0-indexed (LSP-oriented).
#
# Usage:
#   callsites_ts.py <file> <symbol>    extract mode (default)
#   callsites_ts.py <file> @<line>     resolve mode (0-indexed line) — returns
#                                      {"symbol": "Foo#bar"} for the declaration
#                                      starting on that line.
#
# Exit 0 with JSON on stdout on success; exit 1 with error on stderr otherwise.

import json
import sys
from pathlib import Path

try:
    import tree_sitter
    import tree_sitter_typescript as tsts
except ImportError as e:
    print(
        f"callsites_ts.py: {e} — needs tree-sitter + tree-sitter-typescript "
        "(pip install tree-sitter tree-sitter-typescript)",
        file=sys.stderr,
    )
    sys.exit(1)


# ---- parsing ----------------------------------------------------------------

def pick_language(file_path: str):
    suffix = Path(file_path).suffix.lower()
    if suffix in (".tsx", ".jsx"):
        return tree_sitter.Language(tsts.language_tsx())
    return tree_sitter.Language(tsts.language_typescript())


def parse_file(file_path: str):
    source = Path(file_path).read_bytes()
    lang = pick_language(file_path)
    parser = tree_sitter.Parser(lang)
    tree = parser.parse(source)
    return tree.root_node, source


def node_text(node, source: bytes) -> str:
    return source[node.start_byte:node.end_byte].decode("utf-8", errors="replace")


# ---- symbol lookup ----------------------------------------------------------

def iter_top_level(root):
    """Yield top-level declarations, unwrapping export_statement wrappers."""
    for c in root.children:
        if c.type == "export_statement":
            for cc in c.children:
                if cc.type not in ("export", "{", "}", ",", "from", "string",
                                     "default"):
                    yield cc
        else:
            yield c


def decl_name(node, source: bytes) -> str:
    """Return the declared name of a top-level declaration, or ""."""
    # class_declaration / internal_module / enum_declaration → type_identifier
    # function_declaration → identifier
    name_types = ("type_identifier", "identifier", "property_identifier")
    for c in node.children:
        if c.type in name_types:
            return node_text(c, source)
    return ""


def class_methods(cls_node):
    for c in cls_node.children:
        if c.type != "class_body":
            continue
        for m in c.children:
            if m.type == "method_definition":
                yield m


def method_name(method_node, source: bytes) -> str:
    for c in method_node.children:
        if c.type in ("property_identifier", "computed_property_name"):
            return node_text(c, source)
    return ""


def method_is_static(method_node) -> bool:
    return any(c.type == "static" for c in method_node.children)


def find_instance_method(root, source: bytes, class_name: str, meth_name: str):
    for n in iter_top_level(root):
        if n.type != "class_declaration" or decl_name(n, source) != class_name:
            continue
        for m in class_methods(n):
            if method_name(m, source) == meth_name and not method_is_static(m):
                return m
    return None


def find_static_method(root, source: bytes, class_name: str, meth_name: str):
    for n in iter_top_level(root):
        if n.type != "class_declaration" or decl_name(n, source) != class_name:
            continue
        for m in class_methods(n):
            if method_name(m, source) == meth_name and method_is_static(m):
                return m
    return None


def find_namespace_member(root, source: bytes, ns_name: str, meth_name: str):
    """Foo.bar where Foo is a namespace/module containing function/const bar."""
    for n in iter_top_level(root):
        if n.type != "internal_module" or decl_name(n, source) != ns_name:
            continue
        # body is a statement_block or module-level statements
        for c in n.children:
            if c.type != "statement_block":
                continue
            for inner in c.children:
                target = _match_func_or_const(inner, source, meth_name)
                if target is not None:
                    return target
    return None


def find_object_pair(root, source: bytes, obj_name: str, key_name: str):
    """const Foo = { bar: () => {} }  →  return the arrow_function node."""
    for n in iter_top_level(root):
        vd = _variable_declarator(n, source, obj_name)
        if vd is None:
            continue
        obj = _value_child(vd, "object")
        if obj is None:
            continue
        for pair in obj.children:
            if pair.type != "pair":
                continue
            key = pair.child_by_field_name("key")
            if key is None or node_text(key, source) != key_name:
                continue
            value = pair.child_by_field_name("value")
            if value is None:
                continue
            if value.type in ("arrow_function", "function_expression",
                                "function"):
                return value
    return None


def _variable_declarator(node, source: bytes, name: str):
    """Given a top-level node, return the variable_declarator for `name`."""
    if node.type == "export_statement":
        for c in node.children:
            r = _variable_declarator(c, source, name)
            if r is not None:
                return r
        return None
    if node.type not in ("lexical_declaration", "variable_declaration"):
        return None
    for vd in node.children:
        if vd.type != "variable_declarator":
            continue
        if decl_name(vd, source) == name:
            return vd
    return None


def _value_child(vd_node, value_type: str):
    for c in vd_node.children:
        if c.type == value_type:
            return c
    return None


def _match_func_or_const(node, source: bytes, name: str):
    """Return a body-bearing node if this top-level item declares `name`."""
    if node.type == "function_declaration" and decl_name(node, source) == name:
        return node
    vd = _variable_declarator(node, source, name)
    if vd is None:
        return None
    for c in vd.children:
        if c.type in ("arrow_function", "function_expression", "function"):
            return c
    return vd  # fallback: treat the declarator as the body span


def find_top_level(root, source: bytes, name: str):
    """Match a bare name against module-scope declarations, in priority order:
    function_declaration, class_declaration, internal_module, enum_declaration,
    then const = arrow_function."""
    for n in iter_top_level(root):
        if n.type == "function_declaration" and decl_name(n, source) == name:
            return n
    for n in iter_top_level(root):
        if n.type == "class_declaration" and decl_name(n, source) == name:
            return n
    for n in iter_top_level(root):
        if n.type in ("internal_module", "enum_declaration") and \
                decl_name(n, source) == name:
            return n
    for n in iter_top_level(root):
        target = _match_func_or_const(n, source, name)
        if target is not None:
            return target
    return None


def resolve_symbol(root, source: bytes, symbol: str):
    """Dispatch on symbol grammar; return the node whose body we'll scan."""
    if "#" in symbol:
        cls, meth = symbol.split("#", 1)
        return find_instance_method(root, source, cls, meth)
    if "." in symbol:
        prefix, last = symbol.rsplit(".", 1)
        for finder in (find_static_method, find_namespace_member,
                        find_object_pair):
            target = finder(root, source, prefix, last)
            if target is not None:
                return target
        return None
    return find_top_level(root, source, symbol)


# ---- body + call-site collection --------------------------------------------

def body_of(node):
    """Return the node to scan for calls: method/function body, class body,
    object value, or the node itself if nothing more specific."""
    for c in node.children:
        if c.type in ("statement_block", "class_body"):
            return c
    return node


def span_of(node):
    """Return (start_line_1idx, end_line_1idx) covering the full declaration."""
    return node.start_point[0] + 1, node.end_point[0] + 1


def extract_callee(fn_node):
    """Return (line, col, name) for the callee identifier, or None."""
    if fn_node is None:
        return None
    if fn_node.type in ("identifier", "type_identifier"):
        line = fn_node.start_point[0]
        col = fn_node.start_point[1]
        return line, col, fn_node.text.decode("utf-8", errors="replace")
    if fn_node.type == "member_expression":
        prop = fn_node.child_by_field_name("property")
        if prop is None:
            for c in fn_node.children:
                if c.type == "property_identifier":
                    prop = c
        if prop is not None:
            line = prop.start_point[0]
            col = prop.start_point[1]
            return line, col, prop.text.decode("utf-8", errors="replace")
    # parenthesized_expression, call_expression (IIFE), super, new_expression:
    # skip — tree-sitter treats them as non-resolvable identifiers anyway.
    return None


def collect_calls(body_node):
    calls = []
    seen = set()
    stack = [body_node]
    while stack:
        n = stack.pop()
        if n.type == "call_expression":
            fn = n.child_by_field_name("function")
            if fn is None and n.children:
                fn = n.children[0]
            info = extract_callee(fn)
            if info is not None:
                line, col, name = info
                key = (line, col)
                if key not in seen:
                    seen.add(key)
                    calls.append({"line": line, "col": col, "name": name})
        stack.extend(reversed(n.children))
    calls.sort(key=lambda c: (c["line"], c["col"]))
    return calls


# ---- resolve mode -----------------------------------------------------------

def resolve_line_to_symbol(root, source: bytes, target_line: int) -> str:
    """Given a 0-indexed line, walk the AST and return the enclosing symbol
    as a Grammar-A string (Foo#bar / Foo.bar / Foo / bar)."""
    best = None  # (start_line, symbol_string)

    def visit(node, class_stack, module_stack):
        nonlocal best
        if node.type == "class_declaration":
            name = decl_name(node, source)
            if node.start_point[0] == target_line:
                best = (node.start_point[0], _join_stack(module_stack, name))
                return
            for c in node.children:
                if c.type == "class_body":
                    for m in c.children:
                        visit(m, class_stack + [name], module_stack)
            return
        if node.type == "method_definition":
            m_name = method_name(node, source)
            if node.start_point[0] == target_line and class_stack:
                sep = "." if method_is_static(node) else "#"
                best = (node.start_point[0],
                        f"{_join_stack(module_stack, class_stack[-1])}{sep}{m_name}")
            return
        if node.type == "internal_module":
            name = decl_name(node, source)
            if node.start_point[0] == target_line:
                best = (node.start_point[0], _join_stack(module_stack, name))
                return
            for c in node.children:
                if c.type == "statement_block":
                    for inner in c.children:
                        visit(inner, class_stack, module_stack + [name])
            return
        if node.type == "function_declaration":
            name = decl_name(node, source)
            if node.start_point[0] == target_line:
                best = (node.start_point[0], _join_stack(module_stack, name))
            return
        if node.type in ("lexical_declaration", "variable_declaration"):
            for vd in node.children:
                if vd.type != "variable_declarator":
                    continue
                if vd.start_point[0] == target_line:
                    best = (vd.start_point[0],
                            _join_stack(module_stack, decl_name(vd, source)))
                    return
            return
        if node.type == "export_statement":
            for c in node.children:
                visit(c, class_stack, module_stack)
            return

    for n in iter_top_level(root):
        visit(n, [], [])
        if best is not None:
            break
    return best[1] if best else ""


def _join_stack(module_stack, name: str) -> str:
    if not module_stack:
        return name
    return ".".join(module_stack + [name])


# ---- CLI --------------------------------------------------------------------

def main():
    if len(sys.argv) != 3:
        print("usage: callsites_ts.py <file> <symbol|@LINE>", file=sys.stderr)
        sys.exit(2)
    file_path, symbol = sys.argv[1], sys.argv[2]
    if not Path(file_path).is_file():
        print(f"callsites_ts.py: file not found: {file_path}", file=sys.stderr)
        sys.exit(1)

    root, source = parse_file(file_path)

    if symbol.startswith("@"):
        line_0 = int(symbol[1:])
        resolved = resolve_line_to_symbol(root, source, line_0)
        sys.stdout.write(json.dumps({"symbol": resolved}) + "\n")
        return

    target = resolve_symbol(root, source, symbol)
    if target is None:
        print(f"symbol not found: {symbol}", file=sys.stderr)
        sys.exit(1)

    start, end = span_of(target)
    body = body_of(target)
    calls = collect_calls(body)

    sys.stdout.write(json.dumps({
        "start_line": start,
        "end_line": end,
        "calls": calls,
    }) + "\n")


if __name__ == "__main__":
    main()
