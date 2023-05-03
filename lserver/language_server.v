module lserver

import json
import jsonrpc
import lsp
import time
import utils
import analyzer

pub type ResponseWriter = jsonrpc.ResponseWriter

pub enum ServerStatus {
	off
	initialized
	shutdown
}

struct LanguageServer {
mut:
	status       ServerStatus = .off
	root_uri     lsp.DocumentUri
	capabilities lsp.ServerCapabilities
	client_pid   int
	writer       &ResponseWriter = &ResponseWriter(unsafe { nil })

	analyzer_instance analyzer.Analyzer
}

pub fn new(analyzer_instance analyzer.Analyzer) &LanguageServer {
	return &LanguageServer{
		analyzer_instance: analyzer_instance
	}
}

fn (mut wr ResponseWriter) wrap_error(err IError) IError {
	if err is none {
		wr.write(jsonrpc.null)
		return err
	}
	wr.log_message(err.msg(), .error)
	return none
}

pub fn (mut ls LanguageServer) handle_jsonrpc(request &jsonrpc.Request, mut rw jsonrpc.ResponseWriter) ! {
	// initialize writer upon receiving the first request
	if isnil(ls.writer) {
		ls.writer = rw.server.writer(own_buffer: true)
	}

	mut w := unsafe { &ResponseWriter(rw) }

	// The server will log a send request/notification
	// log based on the the received payload since the spec
	// doesn't indicate a way to log on the client side and
	// notify it to the server.
	//
	// Notification has no ID attached so the server can detect
	// if its a notification or a request payload by checking
	// if the ID is empty.
	if request.method == 'shutdown' {
		// NB: LSP specification is unclear whether or not
		// a shutdown request is allowed before server init
		// but we'll just put it here since we want to formally
		// shutdown the server after a certain timeout period.
		ls.shutdown(mut rw)
	} else if ls.status == .initialized {
		match request.method {
			// not only requests but also notifications
			'initialized' {} // does nothing currently
			'exit' {
				// ignore for the reasons stated in the above comment
				// ls.exit()
			}
			'textDocument/didOpen' {
				params := json.decode(lsp.DidOpenTextDocumentParams, request.params) or {
					return err
				}
				// ls.did_open(params, mut rw)
			}
			'textDocument/didSave' {
				params := json.decode(lsp.DidSaveTextDocumentParams, request.params) or {
					return err
				}
				// ls.did_save(params, mut rw)
			}
			'textDocument/didChange' {
				params := json.decode(lsp.DidChangeTextDocumentParams, request.params) or {
					return err
				}
				// ls.did_change(params, mut rw)
			}
			'textDocument/didClose' {
				params := json.decode(lsp.DidCloseTextDocumentParams, request.params) or {
					return err
				}
				// ls.did_close(params, mut rw)
			}
			'textDocument/willSave' {
				params := json.decode(lsp.WillSaveTextDocumentParams, request.params) or {
					return err
				}
				// ls.will_save(params, mut rw)
			}
			'textDocument/formatting' {
				params := json.decode(lsp.DocumentFormattingParams, request.params) or {
					return w.wrap_error(err)
				}
				// w.write(ls.formatting(params, mut rw) or { return w.wrap_error(err) })
			}
			'textDocument/documentSymbol' {
				params := json.decode(lsp.DocumentSymbolParams, request.params) or {
					return w.wrap_error(err)
				}
				// w.write(ls.document_symbol(params, mut rw) or { return w.wrap_error(err) })
			}
			'workspace/symbol' {
				// params := json.decode(lsp.WorkspaceSymbolParams, request.params) or {
				// 	return w.wrap_error(err)
				// }
				// ls.workspace_symbol(lsp.WorkspaceSymbolParams{}, mut rw)
			}
			'textDocument/signatureHelp' {
				params := json.decode(lsp.SignatureHelpParams, request.params) or {
					return w.wrap_error(err)
				}
				// w.write(ls.signature_help(params, mut rw) or { return w.wrap_error(err) })
			}
			'textDocument/completion' {
				params := json.decode(lsp.CompletionParams, request.params) or {
					return w.wrap_error(err)
				}
				// w.write(ls.completion(params, mut rw) or { return w.wrap_error(err) })
			}
			'textDocument/hover' {
				params := json.decode(lsp.HoverParams, request.params) or {
					return w.wrap_error(err)
				}
				hover_data := ls.hover(params, mut rw) or {
					w.write_empty()
					return
				}
				w.write(hover_data)
			}
			'textDocument/foldingRange' {
				params := json.decode(lsp.FoldingRangeParams, request.params) or {
					return w.wrap_error(err)
				}
				// w.write(ls.folding_range(params, mut rw) or { return w.wrap_error(err) })
			}
			'textDocument/definition' {
				params := json.decode(lsp.TextDocumentPositionParams, request.params) or {
					return w.wrap_error(err)
				}
				w.write(ls.definition(params, mut rw) or { return w.wrap_error(err) })
			}
			'textDocument/implementation' {
				params := json.decode(lsp.TextDocumentPositionParams, request.params) or {
					return w.wrap_error(err)
				}
				// w.write(ls.implementation(params, mut rw) or { return w.wrap_error(err) })
			}
			'workspace/didChangeWatchedFiles' {
				params := json.decode(lsp.DidChangeWatchedFilesParams, request.params) or {
					return err
				}
				// ls.did_change_watched_files(params, mut rw)
			}
			'textDocument/codeLens' {
				// params := json.decode(lsp.CodeLensParams, request.params) or {
				// 	return w.wrap_error(err)
				// }
				// w.write(ls.code_lens(lsp.CodeLensParams{}, mut rw) or { return w.wrap_error(err) })
			}
			'textDocument/documentLink' {
				// params := json.decode(lsp.DocumentLinkParams, request.params) or {
				// 	return w.wrap_error(err)
				// }
				// w.write(ls.document_link(lsp.DocumentLinkParams{}, mut rw) or {
				// 	return w.wrap_error(err)
				// })
			}
			else {
				return jsonrpc.response_error(error: jsonrpc.method_not_found, data: request.method).err()
			}
		}
	} else {
		match request.method {
			'exit' {
				ls.exit(mut rw)
			}
			'initialize' {
				params := json.decode(lsp.InitializeParams, request.params) or { return err }
				w.write(ls.initialize(params, mut rw))
			}
			else {
				if ls.status == .shutdown {
					return jsonrpc.invalid_request
				} else {
					return jsonrpc.server_not_initialized
				}
			}
		}
	}
}

pub fn monitor_changes(mut ls LanguageServer, mut wr ResponseWriter) {
	for {
		select {
			// This is for debouncing analysis
			350 * time.millisecond {
				if ls.client_pid != 0 && !utils.is_proc_exists(ls.client_pid) {
					ls.shutdown(mut wr)
				}

				// ls.analyze_file(ls.files[ls.current_file_uri], ls.last_affected_node,
				// 	ls.last_modified_line)
				// ls.last_modified_line = 0
				// ls.last_affected_node = .unknown
				// ls.is_typing = false
			}
		}
	}
}