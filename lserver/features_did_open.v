module lserver

import lsp
import analyzer
import analyzer.psi
import analyzer.parser

pub fn (mut ls LanguageServer) did_open(params lsp.DidOpenTextDocumentParams, mut wr ResponseWriter) {
	src := params.text_document.text
	uri := params.text_document.uri.normalize()

	res := parser.parse_code(src)
	psi_file := psi.new_psi_file(psi.AstNode(res.tree.root_node()), res.rope)

	ls.opened_files[uri] = analyzer.OpenedFile{
		uri: uri
		version: 0
		text: src
		psi_file: psi_file
	}

	println('opened file: ${uri}')
}