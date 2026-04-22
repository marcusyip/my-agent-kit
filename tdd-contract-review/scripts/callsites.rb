#!/usr/bin/env ruby
# callsites.rb — AST-based Ruby call-site extractor for lsp_tree.py.
#
# Parses the file with Prism (stdlib on modern Ruby, or `gem install prism`),
# locates the requested class/module scope and method, and emits every CallNode
# inside the body as JSON:
#
#   {
#     "start_line": 8,       # 1-indexed decl line
#     "end_line":   40,      # 1-indexed last line of the scope/body
#     "calls": [
#       {"line": 12, "col": 6, "name": "authenticate_user!"},  # 0-indexed
#       ...
#     ]
#   }
#
# Symbol grammar (matches Solargraph's convention):
#   "A::B::Foo#bar"  instance method (nested namespace)
#   "A::B::Foo.bar"  class/singleton method (def self.bar)
#   "A::B::Foo"      class or module body
#
# Positions: start/end are 1-indexed (display-oriented). Call line/col are
# 0-indexed (LSP-oriented).
#
# Usage:
#   ruby callsites.rb <file> <symbol>        # extract mode (default)
#   ruby callsites.rb <file> @<line>         # resolve mode: returns the symbol
#                                            # enclosing the given 0-indexed line
#                                            # as {"symbol": "Foo#bar"}.
#
# Exit 0 with JSON on stdout on success; exit 1 with error on stderr otherwise.

require "json"
require "set"

begin
  require "prism"
rescue LoadError
  warn "callsites.rb: prism not available " \
       "(needs Ruby with Prism built-in or `gem install prism`)"
  exit 1
end

if ARGV.size != 2
  warn "usage: callsites.rb <file> <symbol>"
  exit 2
end

file_path, symbol = ARGV

SpecKind = [:instance, :class, :body]

def parse_spec(sym)
  if sym.include?("#")
    cls, meth = sym.split("#", 2)
    return :instance, cls.split("::"), meth
  end
  if sym =~ /\A([A-Z][\w:]*)\.(\w+)\z/
    return :class, Regexp.last_match(1).split("::"), Regexp.last_match(2)
  end
  return :body, sym.split("::"), nil
end

def const_path_names(node)
  case node
  when Prism::ConstantReadNode
    [node.name.to_s]
  when Prism::ConstantPathNode
    parent = node.respond_to?(:parent) ? node.parent : nil
    (parent ? const_path_names(parent) : []) + [node.name.to_s]
  else
    []
  end
end

def find_namespace(node, target, prefix = [])
  return nil unless node
  if node.is_a?(Prism::ClassNode) || node.is_a?(Prism::ModuleNode)
    own = const_path_names(node.constant_path)
    full = prefix + own
    return node if full == target
    return find_namespace(node.body, target, full)
  end
  if node.respond_to?(:child_nodes)
    node.child_nodes.each do |c|
      next if c.nil?
      hit = find_namespace(c, target, prefix)
      return hit if hit
    end
  end
  nil
end

def find_method(scope_node, kind, name)
  body = scope_node.body
  return nil unless body
  stmts = body.is_a?(Prism::StatementsNode) ? body.body : [body]
  stmts.each do |s|
    next unless s.is_a?(Prism::DefNode)
    next unless s.name.to_s == name
    case kind
    when :instance
      return s if s.receiver.nil?
    when :class
      return s if s.receiver.is_a?(Prism::SelfNode)
    end
  end
  nil
end

def collect_calls(node, acc)
  return unless node
  if node.is_a?(Prism::CallNode) && node.message_loc
    acc << {
      line: node.message_loc.start_line - 1,
      col: node.message_loc.start_column,
      name: node.name.to_s,
    }
  end
  if node.respond_to?(:child_nodes)
    node.child_nodes.each { |c| collect_calls(c, acc) if c }
  end
end

def dedup(calls)
  seen = Set.new
  calls.each_with_object([]) do |c, out|
    key = [c[:line], c[:col]]
    next if seen.include?(key)
    seen << key
    out << c
  end
end

parsed = Prism.parse_file(file_path)
if parsed.failure?
  warn "parse error: #{parsed.errors.map(&:message).join('; ')}"
  exit 1
end
program = parsed.value

# Resolve mode: second arg is "@LINE" (0-indexed).
if symbol.start_with?("@")
  target_line_1 = symbol[1..].to_i + 1  # convert 0-indexed → Prism's 1-indexed
  resolved = nil
  walk = lambda do |node, stack|
    return if resolved
    case node
    when Prism::ClassNode, Prism::ModuleNode
      own = const_path_names(node.constant_path)
      new_stack = stack + own
      if node.location.start_line == target_line_1 && resolved.nil?
        resolved = new_stack.join("::")
        return
      end
      walk.call(node.body, new_stack) if node.body
    when Prism::DefNode
      if node.location.start_line == target_line_1 && resolved.nil?
        sep = node.receiver.is_a?(Prism::SelfNode) ? "." : "#"
        resolved = "#{stack.join('::')}#{sep}#{node.name}"
        return
      end
    else
      if node.respond_to?(:child_nodes)
        node.child_nodes.each { |c| walk.call(c, stack) if c }
      end
    end
  end
  walk.call(program, [])
  STDOUT.write(JSON.dump({ symbol: resolved || "" }))
  STDOUT.write("\n")
  exit 0
end

kind, class_parts, method_name = parse_spec(symbol)
scope = find_namespace(program, class_parts)
if scope.nil?
  warn "namespace not found: #{class_parts.join('::')}"
  exit 1
end

target_node = case kind
              when :body
                scope
              else
                m = find_method(scope, kind, method_name)
                if m.nil?
                  warn "method not found in #{class_parts.join('::')}: #{method_name}"
                  exit 1
                end
                m
              end

# Prism locations: start_line 1-indexed, end_line 1-indexed inclusive of the
# last character (`end` keyword or closing brace). `location` is the node's full span.
loc = target_node.location
start_line = loc.start_line
end_line = loc.end_line

# For :body, scan calls inside the body (not the class/module decl header).
# For :instance/:class, scan the method body.
body_to_scan = case kind
               when :body then target_node.body
               else target_node.body
               end

acc = []
collect_calls(body_to_scan, acc) if body_to_scan
out = dedup(acc)

STDOUT.write(JSON.dump({
  start_line: start_line,
  end_line: end_line,
  calls: out,
}))
STDOUT.write("\n")
