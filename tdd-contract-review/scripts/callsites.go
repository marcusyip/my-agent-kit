// callsites.go — AST-based Go call-site extractor for lsp_tree.py.
//
// Given a source file and a symbol name, parses the file with go/parser and
// emits every call expression inside the symbol's body as JSON:
//
//   [{"line": 42, "col": 13, "name": "FindWallet"}, ...]
//
// Positions are 0-indexed (LSP convention). Identifier position points at
// the *callee* name — for `x.Foo(...)` the position is the `F`, for `Foo(...)`
// it's also the `F`. Function-literal calls (`func(){}()`) and calls whose
// callee isn't a simple identifier or selector (e.g. `f()()`) are skipped —
// lsp_tree treats those as unresolvable anyway.
//
// Symbol grammar (matches lsp_tree.py):
//   "(*Type).Method"   pointer-receiver method
//   "(Type).Method"    value-receiver method
//   "Name"             free function or method (first match)
//
// Usage:
//   go run callsites.go <file> <symbol>
//
// Exit 0 with JSON on stdout on success; exit 1 with error on stderr otherwise.
package main

import (
	"encoding/json"
	"fmt"
	"go/ast"
	"go/parser"
	"go/token"
	"os"
	"strings"
)

type callSite struct {
	Line int    `json:"line"`
	Col  int    `json:"col"`
	Name string `json:"name"`
}

func parseSymbol(sym string) (recv string, pointer bool, method string) {
	// "(*Type).Method" | "(Type).Method" | "Name"
	if i := strings.Index(sym, ")."); i > 0 && strings.HasPrefix(sym, "(") {
		r := sym[1:i]
		method = sym[i+2:]
		if strings.HasPrefix(r, "*") {
			return r[1:], true, method
		}
		return r, false, method
	}
	return "", false, sym
}

// matchFunc reports whether fn matches the requested symbol.
func matchFunc(fn *ast.FuncDecl, recv string, pointer bool, method string) bool {
	if fn.Name.Name != method {
		return false
	}
	// Free function / type method disambiguated by receiver presence.
	if recv == "" {
		return fn.Recv == nil
	}
	if fn.Recv == nil || len(fn.Recv.List) == 0 {
		return false
	}
	rt := fn.Recv.List[0].Type
	if star, ok := rt.(*ast.StarExpr); ok {
		if !pointer {
			return false
		}
		ident, ok := star.X.(*ast.Ident)
		return ok && ident.Name == recv
	}
	if pointer {
		return false
	}
	ident, ok := rt.(*ast.Ident)
	return ok && ident.Name == recv
}

// identPos returns the 0-indexed (line, col) of the callee identifier inside
// expr, or (-1, -1, "") if the callee shape isn't supported.
func identPos(fset *token.FileSet, expr ast.Expr) (int, int, string) {
	switch e := expr.(type) {
	case *ast.Ident:
		pos := fset.Position(e.NamePos)
		return pos.Line - 1, pos.Column - 1, e.Name
	case *ast.SelectorExpr:
		pos := fset.Position(e.Sel.NamePos)
		return pos.Line - 1, pos.Column - 1, e.Sel.Name
	case *ast.IndexExpr:
		// Generic call: Foo[T](...) — recurse on the base.
		return identPos(fset, e.X)
	case *ast.IndexListExpr:
		return identPos(fset, e.X)
	}
	return -1, -1, ""
}

func main() {
	if len(os.Args) != 3 {
		fmt.Fprintln(os.Stderr, "usage: callsites.go <file> <symbol>")
		os.Exit(2)
	}
	filePath := os.Args[1]
	symbol := os.Args[2]

	recv, pointer, method := parseSymbol(symbol)

	fset := token.NewFileSet()
	file, err := parser.ParseFile(fset, filePath, nil, parser.SkipObjectResolution)
	if err != nil {
		fmt.Fprintf(os.Stderr, "parse error: %v\n", err)
		os.Exit(1)
	}

	var target *ast.FuncDecl
	for _, decl := range file.Decls {
		fn, ok := decl.(*ast.FuncDecl)
		if !ok || fn.Body == nil {
			continue
		}
		if matchFunc(fn, recv, pointer, method) {
			target = fn
			break
		}
	}
	if target == nil {
		fmt.Fprintf(os.Stderr, "symbol not found: %s\n", symbol)
		os.Exit(1)
	}

	var sites []callSite
	seen := make(map[[2]int]struct{})
	ast.Inspect(target.Body, func(n ast.Node) bool {
		call, ok := n.(*ast.CallExpr)
		if !ok {
			return true
		}
		line, col, name := identPos(fset, call.Fun)
		if name == "" {
			return true
		}
		key := [2]int{line, col}
		if _, dup := seen[key]; dup {
			return true
		}
		seen[key] = struct{}{}
		sites = append(sites, callSite{Line: line, Col: col, Name: name})
		return true
	})

	if sites == nil {
		sites = []callSite{}
	}
	if err := json.NewEncoder(os.Stdout).Encode(sites); err != nil {
		fmt.Fprintf(os.Stderr, "json encode: %v\n", err)
		os.Exit(1)
	}
}
