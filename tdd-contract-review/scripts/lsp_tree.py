#!/usr/bin/env python3
"""Standalone LSP-driven call-tree builder (Go, Ruby, TypeScript/TSX).

Given a seed symbol, walks outgoing calls via `definition` and emits a nested
markdown (or JSON) tree. Runs all LSP queries inside a single multilspy session
so the language-server cold-start is paid once per invocation, not per call site.

Call-site enumeration is AST-accurate:
  * Go         — `scripts/callsites.go` (built once into `.bin/callsites`).
  * Ruby       — `scripts/callsites.rb` (Prism-based).
  * TypeScript — `scripts/callsites_ts.py` (tree-sitter-typescript; handles
                 .ts and .tsx, including React / React Native function
                 components, hooks, and class components).

Usage:
  lsp_tree.py --lang LANG --project PATH --file FILE --symbol NAME \
              [--depth N] [--format markdown|json] [--run-dir DIR]

--lang: `go`, `ruby`, or `ts`. Other values error out — see
`contract-extraction.md` for the algorithmic walk that covers Python and other
languages.

--symbol grammar (Go):
  "(*Type).Method"   pointer-receiver method
  "(Type).Method"    value-receiver method
  "Name"             free function or type

--symbol grammar (Ruby, matches Solargraph convention):
  "A::B::Foo#bar"    instance method (nested namespace supported)
  "A::B::Foo.bar"    class / singleton method (def self.bar)
  "A::B::Foo"        class or module body

--symbol grammar (TypeScript, mirrors the Ruby form):
  "Foo#bar"          class instance method (non-static)
  "Foo.bar"          class static · namespace member · object-literal arrow
  "Foo"              class body · function · const-arrow at module scope
  "bar"              free function / const-arrow / hook at module scope

--run-dir behavior:
  * Every LSP response is written to DIR/lsp/<op>__<slug>__L<line>C<col>.json
    (same naming scheme as `lsp_query.py`), giving a flat audit trail of every
    LSP call the run made.
  * The final tree is written to DIR/tree__<file-slug>__<symbol-slug>.<md|json>
    (extension follows --format), and `WROTE: <path>` is printed on stdout
    instead of the tree body.

Own-node lines in the tree are reported as `start-end` (1-indexed) spanning
the declaration through the closing brace. Recursion / already-visited nodes
are labelled [seen] and not re-expanded. External / stdlib targets are
labelled [external]. --depth caps the walk (default 5).
"""
import os
import subprocess
import sys
from pathlib import Path

VENV_DIR = Path(__file__).resolve().parent / ".venv"
VENV_PY = VENV_DIR / "bin" / "python"


def ensure_venv():
    if sys.prefix == str(VENV_DIR):
        return
    if not VENV_PY.exists():
        print(f"[lsp_tree] bootstrapping venv at {VENV_DIR}", file=sys.stderr)
        subprocess.check_call([sys.executable, "-m", "venv", str(VENV_DIR)])
        subprocess.check_call(
            [str(VENV_PY), "-m", "pip", "install", "--quiet", "--upgrade", "pip"]
        )
        subprocess.check_call(
            [str(VENV_PY), "-m", "pip", "install", "--quiet",
             "multilspy", "tree-sitter", "tree-sitter-typescript"]
        )
    os.execv(str(VENV_PY), [str(VENV_PY), str(Path(__file__).resolve()), *sys.argv[1:]])


ensure_venv()

import argparse  # noqa: E402
import asyncio  # noqa: E402
import glob  # noqa: E402
import json  # noqa: E402
import re  # noqa: E402
import shutil  # noqa: E402

from multilspy import SyncLanguageServer  # noqa: E402
from multilspy.multilspy_config import MultilspyConfig  # noqa: E402
from multilspy.multilspy_logger import MultilspyLogger  # noqa: E402


SCRIPTS_DIR = Path(__file__).resolve().parent
CALLSITES_GO_SRC = SCRIPTS_DIR / "callsites.go"
CALLSITES_GO_BIN = SCRIPTS_DIR / ".bin" / "callsites"
CALLSITES_RB = SCRIPTS_DIR / "callsites.rb"
CALLSITES_TS = SCRIPTS_DIR / "callsites_ts.py"


def prepend_path(*dirs):
    existing = os.environ.get("PATH", "").split(os.pathsep)
    new = [d for d in dirs if d and Path(d).is_dir() and d not in existing]
    if new:
        os.environ["PATH"] = os.pathsep.join(new + existing)


def setup_lang_toolchain(lang: str):
    """Mirror lsp_query.py: brewed Ruby first, so `ruby` on PATH has Prism."""
    if lang == "ruby":
        prepend_path("/opt/homebrew/opt/ruby/bin")
        for gem_bin in glob.glob("/opt/homebrew/lib/ruby/gems/*/bin"):
            prepend_path(gem_bin)


def ensure_callsites_bin():
    """Build the Go call-site helper on first use; rebuild if source is newer."""
    if CALLSITES_GO_BIN.exists() and CALLSITES_GO_BIN.stat().st_mtime >= CALLSITES_GO_SRC.stat().st_mtime:
        return
    CALLSITES_GO_BIN.parent.mkdir(exist_ok=True)
    print(f"[lsp_tree] building {CALLSITES_GO_BIN}", file=sys.stderr)
    subprocess.check_call(
        ["go", "build", "-o", str(CALLSITES_GO_BIN), "./callsites.go"],
        cwd=str(SCRIPTS_DIR),
    )


def _run_ruby_helper(args):
    ruby = shutil.which("ruby")
    if not ruby:
        raise RuntimeError("ruby not on PATH (needs Ruby with Prism — try brewed Ruby)")
    proc = subprocess.run(
        [ruby, str(CALLSITES_RB), *args],
        capture_output=True, text=True,
    )
    if proc.returncode != 0:
        raise RuntimeError(f"callsites.rb failed: {proc.stderr.strip()}")
    return json.loads(proc.stdout)


def _run_ts_helper(args):
    # Run in the same venv Python so tree-sitter + tree-sitter-typescript
    # (installed by ensure_venv) are guaranteed available.
    proc = subprocess.run(
        [str(VENV_PY), str(CALLSITES_TS), *args],
        capture_output=True, text=True,
    )
    if proc.returncode != 0:
        raise RuntimeError(f"callsites_ts.py failed: {proc.stderr.strip()}")
    return json.loads(proc.stdout)


def extract_node(abs_file: Path, in_symbol: str, lang: str) -> dict:
    """Return {start_line, end_line, calls=[(line, col, name), ...]}.

    start_line / end_line are 1-indexed. Call line/col are 0-indexed.
    """
    if lang == "go":
        proc = subprocess.run(
            [str(CALLSITES_GO_BIN), str(abs_file), in_symbol],
            capture_output=True, text=True,
        )
        if proc.returncode != 0:
            raise RuntimeError(f"callsites failed: {proc.stderr.strip()}")
        sites = json.loads(proc.stdout)
        # Go helper emits only calls; derive range via regex+brace match.
        source = abs_file.read_text()
        decl_off, _, body_end = find_symbol_body_go(source, in_symbol)
        return {
            "start_line": source.count("\n", 0, decl_off) + 1,
            "end_line": source.count("\n", 0, body_end - 1) + 1,
            "calls": [(s["line"], s["col"], s["name"]) for s in sites],
        }
    if lang == "ruby":
        data = _run_ruby_helper([str(abs_file), in_symbol])
        return {
            "start_line": data["start_line"],
            "end_line": data["end_line"],
            "calls": [(c["line"], c["col"], c["name"]) for c in data["calls"]],
        }
    if lang == "ts":
        data = _run_ts_helper([str(abs_file), in_symbol])
        return {
            "start_line": data["start_line"],
            "end_line": data["end_line"],
            "calls": [(c["line"], c["col"], c["name"]) for c in data["calls"]],
        }
    raise ValueError(f"unsupported lang: {lang}")


def build_symbol_regex(in_symbol: str):
    """Regex for finding the declaration line of in_symbol inside Go source.

    Only used to compute the own-node start/end line range — NOT for call-site
    detection (that's the AST helper).
    """
    if ")." in in_symbol:
        recv_raw, method = in_symbol.split(").", 1)
        recv = recv_raw.lstrip("(")
        if recv.startswith("*"):
            type_name = re.escape(recv[1:])
            return re.compile(
                rf"^func\s+\(\w+\s+\*{type_name}\)\s+{re.escape(method)}\b",
                re.MULTILINE,
            )
        return re.compile(
            rf"^func\s+\(\w+\s+{re.escape(recv)}\)\s+{re.escape(method)}\b",
            re.MULTILINE,
        )
    esc = re.escape(in_symbol)
    return re.compile(rf"^(?:func|type)\s+{esc}\b", re.MULTILINE)


def find_symbol_body_go(source: str, in_symbol: str):
    """Return (decl_offset, body_start, body_end) for Go in_symbol, or raise."""
    pat = build_symbol_regex(in_symbol)
    m = pat.search(source)
    if not m:
        raise LookupError(f"symbol not found: {in_symbol}")
    brace_start = source.index("{", m.start())
    depth = 0
    i = brace_start
    while i < len(source):
        c = source[i]
        if c == "{":
            depth += 1
        elif c == "}":
            depth -= 1
            if depth == 0:
                return m.start(), brace_start, i + 1
        i += 1
    raise RuntimeError(f"unterminated symbol body: {in_symbol}")


def reconstruct_symbol_go(source: str, target_line: int, fallback: str):
    """Given a Go file source + 0-indexed line, return an in_symbol string."""
    lines = source.split("\n")
    if target_line < 0 or target_line >= len(lines):
        return fallback
    decl = lines[target_line]
    m = re.match(r"\s*func\s+\(\w+\s+(\*?\w+)\)\s+(\w+)", decl)
    if m:
        return f"({m.group(1)}).{m.group(2)}"
    m = re.match(r"\s*func\s+(\w+)", decl)
    if m:
        return m.group(1)
    m = re.match(r"\s*type\s+(\w+)", decl)
    if m:
        return m.group(1)
    return fallback


def is_go_interface_method(source: str, target_line: int) -> bool:
    """True if source:target_line sits on a method signature inside an
    `interface { ... }` block. Go-only — interface method lines have no
    `func` keyword, just `Name(args) returnType`.
    """
    lines = source.split("\n")
    if target_line < 0 or target_line >= len(lines):
        return False
    decl = lines[target_line].lstrip()
    if decl.startswith(("func ", "type ", "//", "/*")):
        return False
    if not re.match(r"[A-Za-z_]\w*\s*\(", decl):
        return False
    depth = 0
    for i in range(target_line - 1, -1, -1):
        ln = lines[i]
        depth += ln.count("}") - ln.count("{")
        if depth < 0:
            return "interface" in ln
    return False


def reconstruct_symbol_ruby(abs_file: Path, target_line: int, fallback: str):
    """Shell out to callsites.rb @LINE resolve mode; returns Solargraph symbol."""
    try:
        data = _run_ruby_helper([str(abs_file), f"@{target_line}"])
    except Exception:
        return fallback
    sym = data.get("symbol") or ""
    return sym or fallback


def reconstruct_symbol_ts(abs_file: Path, target_line: int, fallback: str):
    """Shell out to callsites_ts.py @LINE resolve mode; returns Grammar-A symbol."""
    try:
        data = _run_ts_helper([str(abs_file), f"@{target_line}"])
    except Exception:
        return fallback
    sym = data.get("symbol") or ""
    return sym or fallback


def reconstruct_symbol(abs_file: Path, source: str, target_line: int,
                       fallback: str, lang: str):
    if lang == "go":
        return reconstruct_symbol_go(source, target_line, fallback)
    if lang == "ruby":
        return reconstruct_symbol_ruby(abs_file, target_line, fallback)
    if lang == "ts":
        return reconstruct_symbol_ts(abs_file, target_line, fallback)
    return fallback


def resolve_target_path(defn: dict):
    abs_path = defn.get("absolutePath")
    if not abs_path:
        uri = defn.get("uri", "")
        if uri.startswith("file://"):
            abs_path = uri[len("file://"):]
    return abs_path


def preopen_typescript_project(server, project: Path, opened: dict):
    """Open every .ts / .tsx file under project/src (or project root) so
    typescript-language-server registers them in its project graph. Without
    this, the first `definition` call on a cross-file use-site returns the
    local import binding instead of chasing through to the source file."""
    src_root = project / "src" if (project / "src").is_dir() else project
    for path in src_root.rglob("*"):
        if path.suffix.lower() not in (".ts", ".tsx"):
            continue
        # Skip declaration files — they rarely hold real definitions we walk to.
        if path.name.endswith(".d.ts"):
            continue
        try:
            rel = path.resolve().relative_to(project).as_posix()
        except ValueError:
            continue
        if rel in opened:
            continue
        try:
            file_ctx = server.open_file(rel)
            file_ctx.__enter__()
            opened[rel] = file_ctx
        except Exception as exc:
            print(f"[lsp_tree] preopen warning ({rel}): {exc}", file=sys.stderr)


def slugify_path(p: str) -> str:
    """Matches lsp_query.py.slugify_path for cross-tool artifact compatibility."""
    return re.sub(r"[^A-Za-z0-9]+", "-", p).strip("-")


def artifact_filename(op: str, file_rel: str, line=None, col=None) -> str:
    slug = slugify_path(file_rel)
    if line is not None:
        return f"{op}__{slug}__L{line}C{col}.json"
    return f"{op}__{slug}.json"


class TreeWalker:
    def __init__(self, server, project: Path, max_depth: int,
                 opened_files: dict, lang: str, scope: str = "all",
                 run_dir: Path = None):
        self.server = server
        self.project = project
        self.max_depth = max_depth
        self.opened_files = opened_files
        self.lang = lang
        self.scope = scope
        self.run_dir = run_dir
        self.visited: set = set()
        if run_dir is not None:
            (run_dir / "lsp").mkdir(parents=True, exist_ok=True)

    def ensure_open(self, file_rel: str):
        if file_rel in self.opened_files:
            return
        file_ctx = self.server.open_file(file_rel)
        file_ctx.__enter__()
        self.opened_files[file_rel] = file_ctx

    def persist(self, op: str, file_rel: str, payload, line=None, col=None):
        if self.run_dir is None:
            return
        out = self.run_dir / "lsp" / artifact_filename(op, file_rel, line, col)
        with open(out, "w") as f:
            json.dump(payload, f, indent=2, default=str)
            f.write("\n")

    def request_document_symbols(self, file_rel: str):
        result = self.server.request_document_symbols(file_rel)
        self.persist("document_symbols", file_rel, result)
        return result

    def request_definition(self, file_rel: str, line: int, col: int):
        result = self.server.request_definition(file_rel, line, col)
        self.persist("definition", file_rel, result, line, col)
        return result

    def request_implementation(self, file_rel: str, line: int, col: int):
        """textDocument/implementation. multilspy doesn't wrap this in a
        public API, so we call the underlying async send.implementation
        directly and normalize the response to a list of Location dicts
        matching request_definition's shape (has `uri`, `range`,
        `absolutePath`).
        """
        sync = self.server
        uri = (self.project / file_rel).resolve().as_uri()
        params = {
            "textDocument": {"uri": uri},
            "position": {"line": line, "character": col},
        }
        coro = sync.language_server.server.send.implementation(params)
        raw = asyncio.run_coroutine_threadsafe(coro, sync.loop).result(
            timeout=sync.timeout
        )
        if raw is None:
            locs = []
        elif isinstance(raw, list):
            locs = raw
        else:
            locs = [raw]
        normalized = []
        for item in locs:
            if not isinstance(item, dict):
                continue
            if "uri" in item and "range" in item:
                out = dict(item)
            elif "targetUri" in item and "targetSelectionRange" in item:
                # LocationLink → Location shape
                out = {
                    "uri": item["targetUri"],
                    "range": item["targetSelectionRange"],
                }
            else:
                continue
            abs_path = out["uri"][len("file://"):] if out["uri"].startswith("file://") else out["uri"]
            out["absolutePath"] = abs_path
            normalized.append(out)
        self.persist("implementation", file_rel, normalized, line, col)
        return normalized

    def walk(self, file_rel: str, symbol: str, call_name: str, depth: int):
        node = {
            "call_name": call_name,
            "symbol": symbol,
            "file": file_rel,
            "start_line": None,
            "end_line": None,
            "children": [],
            "tag": None,
        }
        if depth >= self.max_depth:
            node["tag"] = "depth-cap"
            return node

        abs_path = self.project / file_rel
        if not abs_path.exists():
            node["tag"] = "unreadable (missing)"
            return node

        try:
            info = extract_node(abs_path, symbol, self.lang)
        except LookupError:
            node["tag"] = "symbol-not-found"
            return node
        except Exception as exc:
            msg = str(exc)
            if "not found" in msg.lower():
                node["tag"] = "symbol-not-found"
            else:
                node["tag"] = f"extract-error ({exc})"
            return node

        node["start_line"] = info["start_line"]
        node["end_line"] = info["end_line"]

        self.ensure_open(file_rel)
        # document_symbols on each visited file: satisfies the skill's per-file
        # coverage expectation and produces an artifact the gate counts.
        try:
            self.request_document_symbols(file_rel)
        except Exception as exc:
            print(f"[lsp_tree] document_symbols warning ({file_rel}): {exc}",
                  file=sys.stderr)

        for line, col, name in info["calls"]:
            try:
                defs = self.request_definition(file_rel, line, col)
            except Exception as exc:
                node["children"].append({
                    "call_name": name,
                    "tag": f"lsp-error ({exc})",
                    "children": [],
                })
                continue

            if not defs:
                node["children"].append({
                    "call_name": name,
                    "tag": "unresolved",
                    "children": [],
                })
                continue

            defn = defs[0]
            target_abs_str = resolve_target_path(defn)
            if not target_abs_str:
                node["children"].append({
                    "call_name": name,
                    "tag": "no-path",
                    "children": [],
                })
                continue

            target_abs = Path(target_abs_str)
            target_line = defn["range"]["start"]["line"]

            try:
                target_rel = target_abs.resolve().relative_to(self.project).as_posix()
            except ValueError:
                if self.scope == "local":
                    continue
                node["children"].append({
                    "call_name": name,
                    "file": str(target_abs),
                    "tag": "external",
                    "children": [],
                })
                continue

            key = (target_rel, target_line)
            if key in self.visited:
                node["children"].append({
                    "call_name": name,
                    "file": target_rel,
                    "start_line": target_line + 1,
                    "tag": "seen",
                    "children": [],
                })
                continue
            self.visited.add(key)

            try:
                target_source = target_abs.read_text()
            except OSError:
                node["children"].append({
                    "call_name": name,
                    "file": target_rel,
                    "tag": "unreadable",
                    "children": [],
                })
                continue

            # Go interface hop: when `definition` lands on an interface
            # method signature, fan out to concrete implementations via
            # textDocument/implementation. The LSP query must use the
            # ORIGINAL call site (file_rel, line, col) — gopls resolves
            # impls from the variable's static type at the use site.
            if self.lang == "go" and is_go_interface_method(target_source, target_line):
                try:
                    impls = self.request_implementation(file_rel, line, col)
                    iface_tag = "interface" if impls else "interface (no impls)"
                except Exception as exc:
                    impls = []
                    iface_tag = f"interface (lsp-error: {exc})"
                iface_node = {
                    "call_name": name,
                    "file": target_rel,
                    "start_line": target_line + 1,
                    "end_line": None,
                    "children": [],
                    "tag": iface_tag,
                }
                for impl in impls:
                    impl_abs_str = resolve_target_path(impl)
                    if not impl_abs_str:
                        iface_node["children"].append({
                            "call_name": name, "tag": "no-path", "children": [],
                        })
                        continue
                    impl_abs = Path(impl_abs_str)
                    impl_line = impl["range"]["start"]["line"]
                    try:
                        impl_rel = impl_abs.resolve().relative_to(self.project).as_posix()
                    except ValueError:
                        if self.scope == "local":
                            continue
                        iface_node["children"].append({
                            "call_name": name,
                            "file": str(impl_abs),
                            "tag": "external",
                            "children": [],
                        })
                        continue
                    ikey = (impl_rel, impl_line)
                    if ikey in self.visited:
                        iface_node["children"].append({
                            "call_name": name,
                            "file": impl_rel,
                            "start_line": impl_line + 1,
                            "tag": "seen",
                            "children": [],
                        })
                        continue
                    self.visited.add(ikey)
                    try:
                        impl_source = impl_abs.read_text()
                    except OSError:
                        iface_node["children"].append({
                            "call_name": name, "file": impl_rel,
                            "tag": "unreadable", "children": [],
                        })
                        continue
                    impl_symbol = reconstruct_symbol(
                        impl_abs, impl_source, impl_line, name, self.lang,
                    )
                    iface_node["children"].append(
                        self.walk(impl_rel, impl_symbol, name, depth + 1)
                    )
                node["children"].append(iface_node)
                continue

            target_symbol = reconstruct_symbol(
                target_abs, target_source, target_line, name, self.lang,
            )
            child = self.walk(target_rel, target_symbol, name, depth + 1)
            node["children"].append(child)

        return node


def format_range(node) -> str:
    start = node.get("start_line")
    end = node.get("end_line")
    if start is None:
        return ""
    if end is None or end == start:
        return f":{start}"
    return f":{start}-{end}"


def render_markdown(node, indent=0):
    parts = [node.get("call_name") or node.get("symbol") or "?"]
    sym = node.get("symbol")
    if sym and sym != node.get("call_name"):
        parts.append(f"→ {sym}")
    if node.get("file"):
        parts.append(f"@ {node['file']}{format_range(node)}")
    if node.get("tag"):
        parts.append(f"[{node['tag']}]")
    line = "  " * indent + "- " + " ".join(parts)
    rendered = [line]
    for child in node.get("children", []):
        rendered.append(render_markdown(child, indent + 1))
    return "\n".join(rendered)


def main():
    parser = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument("--lang", required=True)
    parser.add_argument("--project", required=True)
    parser.add_argument("--file", required=True, help="path relative to --project")
    parser.add_argument("--symbol", required=True, help='(*Type).Method | (Type).Method | Name')
    parser.add_argument("--depth", type=int, default=5)
    parser.add_argument("--format", choices=["markdown", "json"], default="markdown")
    parser.add_argument("--scope", choices=["all", "local"], default="all",
                        help="local: drop calls that resolve outside the project "
                             "(stdlib / gems). LSP queries still run so the on-disk "
                             "artifact audit trail is unaffected.")
    parser.add_argument("--run-dir", default=None,
                        help="persist every LSP response under DIR/lsp/")
    args = parser.parse_args()

    if args.lang not in ("go", "ruby", "ts"):
        sys.exit(
            f"--lang {args.lang}: only `go`, `ruby`, and `ts` are supported "
            "today (AST-based call-site detection). For other languages, use "
            "the manual walk with lsp_query.py as described in "
            "contract-extraction.md."
        )

    project = Path(args.project).resolve()
    if not project.is_dir():
        sys.exit(f"--project not a directory: {project}")

    run_dir = Path(args.run_dir).resolve() if args.run_dir else None

    setup_lang_toolchain(args.lang)
    if args.lang == "go":
        ensure_callsites_bin()

    # multilspy expects the Language enum values ("typescript", not "ts").
    ml_lang = {"ts": "typescript"}.get(args.lang, args.lang)
    config = MultilspyConfig.from_dict({"code_language": ml_lang})
    logger = MultilspyLogger()
    server = SyncLanguageServer.create(config, logger, str(project))

    ctx = server.start_server()
    try:
        ctx.__enter__()
    except Exception as exc:
        sys.exit(f"[lsp_tree] failed to start language server: {exc}")

    opened: dict = {}
    try:
        walker = TreeWalker(server, project, args.depth, opened, args.lang,
                            args.scope, run_dir)
        # typescript-language-server only resolves cross-file `definition`
        # after the target file has been opened by the client. Pre-open every
        # .ts / .tsx under the project so the first use-site query chases
        # through imports instead of stopping at the import binding. Ruby /
        # Go servers index the whole project on startup and don't need this.
        if args.lang == "ts":
            preopen_typescript_project(server, project, opened)

        seed_abs = project / args.file
        try:
            seed_info = extract_node(seed_abs, args.symbol, args.lang)
            seed_line = seed_info["start_line"] - 1  # 0-indexed for visited key
            walker.visited.add((args.file, seed_line))
        except Exception:
            pass

        root = walker.walk(args.file, args.symbol, args.symbol, 0)
    finally:
        for file_rel, file_ctx in opened.items():
            try:
                file_ctx.__exit__(None, None, None)
            except Exception as exc:
                print(f"[lsp_tree] file close warning (ignored): {exc}", file=sys.stderr)
        try:
            ctx.__exit__(None, None, None)
        except Exception as exc:
            # gopls may exit cleanly before multilspy signals its children;
            # psutil.NoSuchProcess is benign — the walk already completed.
            print(f"[lsp_tree] server cleanup warning (ignored): {exc}", file=sys.stderr)

    if args.format == "json":
        body = json.dumps(root, indent=2, default=str) + "\n"
    else:
        body = render_markdown(root) + "\n"

    if run_dir is not None:
        ext = "json" if args.format == "json" else "md"
        file_slug = slugify_path(args.file)
        symbol_slug = slugify_path(args.symbol)
        out_path = run_dir / f"tree__{file_slug}__{symbol_slug}.{ext}"
        with open(out_path, "w") as f:
            f.write(body)
        sys.stdout.write(f"WROTE: {out_path}\n")
    else:
        sys.stdout.write(body)


if __name__ == "__main__":
    main()
