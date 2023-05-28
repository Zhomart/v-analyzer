module semantic

import analyzer.psi

// DumbAwareSemanticVisitor это максимально оптимизированный обходчик, который собирает
// информацию о семантических токенах в файле только на основе их синтаксического дерева.
// Этот аннотатор не должен вызывать resolve или использовать индексы.
pub struct DumbAwareSemanticVisitor {}

pub fn (v DumbAwareSemanticVisitor) accept(root psi.PsiElement) []SemanticToken {
	mut result := []SemanticToken{cap: 1000}

	for node in psi.new_tree_walker(root.node) {
		v.highlight_node(node, root, mut result)
	}

	return result
}

[inline]
fn (_ DumbAwareSemanticVisitor) highlight_node(node psi.AstNode, root psi.PsiElement, mut result []SemanticToken) {
	if node.type_name == .var_definition {
		result << element_to_semantic(node, .variable)
	} else if node.type_name == .enum_field_definition {
		if first_child := node.first_child() {
			result << element_to_semantic(first_child, .enum_member)
		}
	} else if node.type_name == .field_name {
		result << element_to_semantic(node, .property)
	} else if node.type_name == .struct_field_declaration {
		if first_child := node.first_child() {
			result << element_to_semantic(first_child, .property)
		}
	} else if node.type_name == .module_clause {
		if last_child := node.last_child() {
			result << element_to_semantic(last_child, .namespace)
		}
	} else if node.type_name == .value_attribute {
		first_child := node.first_child() or { return }
		result << element_to_semantic(first_child, .decorator)
	} else if node.type_name == .attribute {
		// '['
		first_child := node.first_child() or { return }
		// ']'
		last_child := node.last_child() or { return }
		result << element_to_semantic(first_child, .decorator)
		result << element_to_semantic(last_child, .decorator)
	} else if node.type_name == .key_value_attribute {
		value_child := node.child_by_field_name('value') or { return }
		if value_child.type_name == .identifier {
			result << element_to_semantic(node, .decorator)
		}
	} else if node.type_name == .qualified_type {
		first_child := node.first_child() or { return }
		result << element_to_semantic(first_child, .namespace)
	} else if node.type_name == .unknown {
		text := node.text(root.containing_file.source_text)
		if text == 'mut' || text == '__global' || text == 'nil' {
			result << element_to_semantic(node, .keyword)
		}

		if text == 'sql' {
			if parent := node.parent() {
				if parent.type_name == .sql_expression {
					result << element_to_semantic(node, .keyword)
				}
			}
		}
		if text == 'chan' {
			if parent := node.parent() {
				if parent.type_name == .channel_type {
					result << element_to_semantic(node, .keyword)
				}
			}
		}
		if text == 'thread' {
			if parent := node.parent() {
				if parent.type_name == .thread_type {
					result << element_to_semantic(node, .keyword)
				}
			}
		}
	} else if node.type_name == .enum_declaration {
		identifier := node.child_by_field_name('name') or { return }
		result << element_to_semantic(identifier, .enum_)
	} else if node.type_name == .parameter_declaration || node.type_name == .receiver {
		identifier := node.child_by_field_name('name') or { return }
		is_mut := if _ := node.child_by_field_name('mutability') {
			true
		} else {
			false
		}

		mut mods := []string{}
		if is_mut {
			mods << 'mutable'
		}
		result << element_to_semantic(identifier, .parameter, ...mods)
	} else if node.type_name == .var_definition {
		result << element_to_semantic(node, .variable)
	} else if node.type_name == .reference_expression {
		def := psi.node_to_var_definition(node, root.containing_file, none)
		if !isnil(def) {
			result << element_to_semantic(node, .variable)
		}

		first_char := node.first_char(root.containing_file.source_text)
		if first_char == `@` || first_char == `$` {
			result << element_to_semantic(node, .property) // not a best variant...
		}
	} else if node.type_name == .const_definition {
		name := node.child_by_field_name('name') or { return }
		result << element_to_semantic(name, .property) // not a best variant...
	} else if node.type_name == .nil_ {
		result << element_to_semantic(node, .keyword)
	}
}