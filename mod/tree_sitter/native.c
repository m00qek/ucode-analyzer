/*
 * ucode native extension exposing the tree-sitter C API, installed as
 * tree_sitter.native (/usr/lib/ucode/tree_sitter/native.so).
 *
 * This is deliberately a thin, mechanical FFI layer: one function per
 * tree-sitter call, minimal validation. Ergonomics (argument-checking with
 * friendly messages, structured results, collection helpers) live in the
 * companion src/ts.uc module, which is the module consumers should actually
 * import. The checks kept here are the ones that prevent a null-pointer
 * dereference or undefined behavior in C; ucode's own value accessors
 * (ucv_string_get, ucv_int64_get, ...) already fail safe (return NULL/0)
 * for wrong-typed arguments, so we don't duplicate that here.
 */

#include <tree_sitter/api.h>
#include <tree_sitter/tree-sitter-ucdocs.h>
#include <tree_sitter/tree-sitter-ucode-markup.h>
#include <tree_sitter/tree-sitter-ucode.h>

#include <string.h>

#include <ucode/lib.h>
#include <ucode/module.h>

/*
 * A ucode node value must keep the owning tree alive: TSNode is a value
 * type that stays valid only as long as the TSTree it was produced from
 * has not been freed. We hold a GC reference to the wrapping "ts.tree"
 * resource value for the lifetime of the node resource and release it
 * in the node's freefn.
 */
typedef struct {
  uc_value_t *tree_ref;
  TSNode node;
} uc_ts_node_t;

static uc_resource_type_t *parser_type;
static uc_resource_type_t *tree_type;
static uc_resource_type_t *node_type;
static uc_resource_type_t *language_type;
static uc_resource_type_t *query_type;

static uc_value_t *node_wrap(uc_value_t *tree_ref, TSNode node) {
  uc_ts_node_t *n;

  if (ts_node_is_null(node))
    return NULL;

  n = xalloc(sizeof(*n));
  n->tree_ref = ucv_get(tree_ref);
  n->node = node;

  return uc_resource_new(node_type, n);
}

static void node_free(void *ptr) {
  uc_ts_node_t *n = ptr;

  ucv_put(n->tree_ref);
  free(n);
}

static void tree_free(void *ptr) { ts_tree_delete((TSTree *)ptr); }

static void parser_free(void *ptr) { ts_parser_delete((TSParser *)ptr); }

static void query_free(void *ptr) { ts_query_delete((TSQuery *)ptr); }

static uc_value_t *uc_ts_language_ucode(uc_vm_t *vm, size_t nargs) {
  return uc_resource_new(language_type, (void *)tree_sitter_ucode());
}

static uc_value_t *uc_ts_language_ucdocs(uc_vm_t *vm, size_t nargs) {
  return uc_resource_new(language_type, (void *)tree_sitter_ucdocs());
}

static uc_value_t *uc_ts_language_ucode_markup(uc_vm_t *vm, size_t nargs) {
  return uc_resource_new(language_type, (void *)tree_sitter_ucode_markup());
}

static uc_value_t *uc_ts_new_parser(uc_vm_t *vm, size_t nargs) {
  const TSLanguage *lang = ucv_resource_data(uc_fn_arg(0), "ts.language");
  TSParser *parser;

  if (!lang) {
    uc_vm_raise_exception(vm, EXCEPTION_TYPE, "expecting a language handle");
    return NULL;
  }

  parser = ts_parser_new();

  if (!ts_parser_set_language(parser, lang)) {
    ts_parser_delete(parser);
    uc_vm_raise_exception(vm, EXCEPTION_RUNTIME,
                          "incompatible language version");
    return NULL;
  }

  return uc_resource_new(parser_type, parser);
}

static uc_value_t *uc_ts_parse(uc_vm_t *vm, size_t nargs) {
  TSParser *parser = ucv_resource_data(uc_fn_arg(0), "ts.parser");
  uc_value_t *srcval = uc_fn_arg(1);
  TSTree *tree;

  /*
   * srcval's type is checked explicitly (rather than relying on
   * ucv_string_get()'s safe-NULL behavior) because a NULL buffer with a
   * non-zero claimed length would cross into tree-sitter's own C code,
   * which we don't control and isn't documented as null-safe here.
   */
  if (!parser || ucv_type(srcval) != UC_STRING) {
    uc_vm_raise_exception(vm, EXCEPTION_TYPE,
                          "expecting a parser handle and a source string");
    return NULL;
  }

  tree = ts_parser_parse_string(parser, NULL, ucv_string_get(srcval),
                                ucv_string_length(srcval));

  if (!tree) {
    uc_vm_raise_exception(vm, EXCEPTION_RUNTIME, "parse failed");
    return NULL;
  }

  return uc_resource_new(tree_type, tree);
}

static bool edit_field(uc_value_t *edit, const char *name, uint32_t *out) {
  uc_value_t *v = ucv_object_get(edit, name, NULL);

  if (ucv_type(v) != UC_INTEGER)
    return false;

  *out = (uint32_t)ucv_int64_get(v);

  return true;
}

/*
 * Intentionally the *only* way to reuse a previous tree: this always calls
 * ts_tree_edit() on `tree` immediately before parsing, on the same call.
 * ts_tree_edit() and the old-tree variant of ts_parser_parse_string() are
 * not exposed separately, so there is no sequence of calls through this
 * binding that parses with an old tree that wasn't just edited -- the
 * failure mode documented in the prototype's PROBLEMS_IN_TREESITTER.MD #4
 * (an unedited/mismatched old tree silently producing wrong node byte
 * ranges) isn't reachable through this API.
 *
 * `tree` must be the TSTree produced by the immediately preceding parse of
 * the exact text that `edit` describes a change to; this binding has no way
 * to verify that. Any TSNode values obtained from `tree` before this call
 * become stale once ts_tree_edit() runs and must not be used afterwards --
 * fetch fresh nodes from the returned tree instead.
 */
static uc_value_t *uc_ts_reparse(uc_vm_t *vm, size_t nargs) {
  TSParser *parser = ucv_resource_data(uc_fn_arg(0), "ts.parser");
  TSTree *tree = ucv_resource_data(uc_fn_arg(1), "ts.tree");
  uc_value_t *editval = uc_fn_arg(2);
  uc_value_t *srcval = uc_fn_arg(3);
  TSInputEdit edit = {0};
  TSTree *newtree;

  if (!parser || !tree || ucv_type(editval) != UC_OBJECT ||
      ucv_type(srcval) != UC_STRING) {
    uc_vm_raise_exception(
        vm, EXCEPTION_TYPE,
        "expecting a parser, a tree, an edit object, and a source string");
    return NULL;
  }

  if (!edit_field(editval, "startByte", &edit.start_byte) ||
      !edit_field(editval, "oldEndByte", &edit.old_end_byte) ||
      !edit_field(editval, "newEndByte", &edit.new_end_byte) ||
      !edit_field(editval, "startRow", &edit.start_point.row) ||
      !edit_field(editval, "startColumn", &edit.start_point.column) ||
      !edit_field(editval, "oldEndRow", &edit.old_end_point.row) ||
      !edit_field(editval, "oldEndColumn", &edit.old_end_point.column) ||
      !edit_field(editval, "newEndRow", &edit.new_end_point.row) ||
      !edit_field(editval, "newEndColumn", &edit.new_end_point.column)) {
    uc_vm_raise_exception(vm, EXCEPTION_TYPE, "incomplete edit object");
    return NULL;
  }

  ts_tree_edit(tree, &edit);

  newtree = ts_parser_parse_string(parser, tree, ucv_string_get(srcval),
                                   ucv_string_length(srcval));

  if (!newtree) {
    uc_vm_raise_exception(vm, EXCEPTION_RUNTIME, "parse failed");
    return NULL;
  }

  return uc_resource_new(tree_type, newtree);
}

static uc_value_t *uc_ts_root_node(uc_vm_t *vm, size_t nargs) {
  uc_value_t *treeval = uc_fn_arg(0);
  TSTree *tree = ucv_resource_data(treeval, "ts.tree");

  if (!tree) {
    uc_vm_raise_exception(vm, EXCEPTION_TYPE, "expecting a tree handle");
    return NULL;
  }

  return node_wrap(treeval, ts_tree_root_node(tree));
}

static uc_ts_node_t *node_arg(uc_vm_t *vm, size_t nargs, size_t n) {
  uc_ts_node_t *node = ucv_resource_data(uc_fn_arg(n), "ts.node");

  if (!node)
    uc_vm_raise_exception(vm, EXCEPTION_TYPE, "expecting a node handle");

  return node;
}

static uc_value_t *uc_ts_node_type(uc_vm_t *vm, size_t nargs) {
  uc_ts_node_t *node = node_arg(vm, nargs, 0);

  return node ? ucv_string_new(ts_node_type(node->node)) : NULL;
}

static uc_value_t *uc_ts_node_is_named(uc_vm_t *vm, size_t nargs) {
  uc_ts_node_t *node = node_arg(vm, nargs, 0);

  return node ? ucv_boolean_new(ts_node_is_named(node->node)) : NULL;
}

static uc_value_t *uc_ts_node_is_missing(uc_vm_t *vm, size_t nargs) {
  uc_ts_node_t *node = node_arg(vm, nargs, 0);

  return node ? ucv_boolean_new(ts_node_is_missing(node->node)) : NULL;
}

static uc_value_t *uc_ts_node_has_error(uc_vm_t *vm, size_t nargs) {
  uc_ts_node_t *node = node_arg(vm, nargs, 0);

  return node ? ucv_boolean_new(ts_node_has_error(node->node)) : NULL;
}

static uc_value_t *uc_ts_node_text(uc_vm_t *vm, size_t nargs) {
  uc_ts_node_t *node = node_arg(vm, nargs, 0);
  uc_value_t *srcval = uc_fn_arg(1);
  uint32_t start, end;

  if (!node)
    return NULL;

  /* explicit check: see comment in uc_ts_parse() */
  if (ucv_type(srcval) != UC_STRING) {
    uc_vm_raise_exception(vm, EXCEPTION_TYPE, "expecting a source string");
    return NULL;
  }

  start = ts_node_start_byte(node->node);
  end = ts_node_end_byte(node->node);

  if (end > ucv_string_length(srcval))
    end = ucv_string_length(srcval);

  if (start > end)
    start = end;

  return ucv_string_new_length(ucv_string_get(srcval) + start, end - start);
}

static uc_value_t *uc_ts_node_start_byte(uc_vm_t *vm, size_t nargs) {
  uc_ts_node_t *node = node_arg(vm, nargs, 0);

  return node ? ucv_int64_new(ts_node_start_byte(node->node)) : NULL;
}

static uc_value_t *uc_ts_node_end_byte(uc_vm_t *vm, size_t nargs) {
  uc_ts_node_t *node = node_arg(vm, nargs, 0);

  return node ? ucv_int64_new(ts_node_end_byte(node->node)) : NULL;
}

static uc_value_t *uc_ts_node_child_count(uc_vm_t *vm, size_t nargs) {
  uc_ts_node_t *node = node_arg(vm, nargs, 0);

  return node ? ucv_int64_new(ts_node_child_count(node->node)) : NULL;
}

static uc_value_t *uc_ts_node_named_child_count(uc_vm_t *vm, size_t nargs) {
  uc_ts_node_t *node = node_arg(vm, nargs, 0);

  return node ? ucv_int64_new(ts_node_named_child_count(node->node)) : NULL;
}

static uc_value_t *uc_ts_node_child(uc_vm_t *vm, size_t nargs) {
  uc_ts_node_t *node = node_arg(vm, nargs, 0);

  if (!node)
    return NULL;

  return node_wrap(node->tree_ref,
                   ts_node_child(node->node, ucv_int64_get(uc_fn_arg(1))));
}

static uc_value_t *uc_ts_node_named_child(uc_vm_t *vm, size_t nargs) {
  uc_ts_node_t *node = node_arg(vm, nargs, 0);

  if (!node)
    return NULL;

  return node_wrap(
      node->tree_ref,
      ts_node_named_child(node->node, ucv_int64_get(uc_fn_arg(1))));
}

static uc_value_t *uc_ts_node_child_by_field(uc_vm_t *vm, size_t nargs) {
  uc_ts_node_t *node = node_arg(vm, nargs, 0);
  uc_value_t *fieldval = uc_fn_arg(1);

  if (!node)
    return NULL;

  return node_wrap(node->tree_ref, ts_node_child_by_field_name(
                                       node->node, ucv_string_get(fieldval),
                                       ucv_string_length(fieldval)));
}

static uc_value_t *uc_ts_node_parent(uc_vm_t *vm, size_t nargs) {
  uc_ts_node_t *node = node_arg(vm, nargs, 0);

  if (!node)
    return NULL;

  return node_wrap(node->tree_ref, ts_node_parent(node->node));
}

/*
 * The children of a node as an array, in one cursor pass: ts_node_child(i)
 * walks from the first child on every call, so index loops are quadratic.
 * `named` keeps only named children; a non-zero `field` keeps only children
 * under that field id.
 */
static uc_value_t *children_array(uc_vm_t *vm, uc_ts_node_t *node, bool named,
                                  TSFieldId field) {
  uc_value_t *result = ucv_array_new(vm);
  TSTreeCursor cursor = ts_tree_cursor_new(node->node);
  TSNode child;

  if (ts_tree_cursor_goto_first_child(&cursor)) {
    do {
      child = ts_tree_cursor_current_node(&cursor);

      if (named && !ts_node_is_named(child))
        continue;

      if (field && ts_tree_cursor_current_field_id(&cursor) != field)
        continue;

      ucv_array_push(result, node_wrap(node->tree_ref, child));
    } while (ts_tree_cursor_goto_next_sibling(&cursor));
  }

  ts_tree_cursor_delete(&cursor);

  return result;
}

static uc_value_t *uc_ts_node_children(uc_vm_t *vm, size_t nargs) {
  uc_ts_node_t *node = node_arg(vm, nargs, 0);

  return node ? children_array(vm, node, false, 0) : NULL;
}

static uc_value_t *uc_ts_node_named_children(uc_vm_t *vm, size_t nargs) {
  uc_ts_node_t *node = node_arg(vm, nargs, 0);

  return node ? children_array(vm, node, true, 0) : NULL;
}

/* The named children under a field, for fields that hold several (`params`). */
static uc_value_t *uc_ts_node_children_by_field(uc_vm_t *vm, size_t nargs) {
  uc_ts_node_t *node = node_arg(vm, nargs, 0);
  uc_value_t *fieldval = uc_fn_arg(1);
  TSFieldId field;

  if (!node)
    return NULL;

  if (ucv_type(fieldval) != UC_STRING) {
    uc_vm_raise_exception(vm, EXCEPTION_TYPE, "expecting a field name string");
    return NULL;
  }

  field = ts_language_field_id_for_name(ts_node_language(node->node),
                                        ucv_string_get(fieldval),
                                        ucv_string_length(fieldval));

  /* An unknown field name has id 0, which would match every child. */
  return field ? children_array(vm, node, true, field) : ucv_array_new(vm);
}

/*
 * The smallest (named) descendant with start <= offset < end, or `node`
 * itself when no child contains offset: the range [offset, offset + 1] is
 * spanned exactly by the nodes that contain that byte.
 */
static uc_value_t *descendant_at(uc_vm_t *vm, size_t nargs, bool named) {
  uc_ts_node_t *node = node_arg(vm, nargs, 0);
  uc_value_t *offsetval = uc_fn_arg(1);
  uint32_t offset;

  if (!node)
    return NULL;

  if (ucv_type(offsetval) != UC_INTEGER || ucv_int64_get(offsetval) < 0) {
    uc_vm_raise_exception(vm, EXCEPTION_TYPE, "expecting a byte offset");
    return NULL;
  }

  offset = (uint32_t)ucv_int64_get(offsetval);

  return node_wrap(node->tree_ref,
                   named ? ts_node_named_descendant_for_byte_range(
                               node->node, offset, offset + 1)
                         : ts_node_descendant_for_byte_range(node->node, offset,
                                                             offset + 1));
}

/*
 * The start bytes of every descendant of `node` (itself included) whose type
 * is one of `types`, in document order (a preorder walk, so non-decreasing).
 * Offsets rather than nodes: a caller can test "does this subtree hold any of
 * these?" with a binary search instead of visiting it.
 */
static uc_value_t *uc_ts_node_descendant_offsets(uc_vm_t *vm, size_t nargs) {
  uc_ts_node_t *node = node_arg(vm, nargs, 0);
  uc_value_t *typesval = uc_fn_arg(1);
  uc_value_t *result, *item;
  TSTreeCursor cursor;
  TSNode current;
  const char *type, *want;
  size_t i, ntypes;
  bool descend = true;

  if (!node)
    return NULL;

  if (ucv_type(typesval) != UC_ARRAY) {
    uc_vm_raise_exception(vm, EXCEPTION_TYPE, "expecting an array of types");
    return NULL;
  }

  ntypes = ucv_array_length(typesval);
  result = ucv_array_new(vm);
  cursor = ts_tree_cursor_new(node->node);

  for (;;) {
    if (descend) {
      current = ts_tree_cursor_current_node(&cursor);
      type = ts_node_type(current);

      for (i = 0; i < ntypes; i++) {
        item = ucv_array_get(typesval, i);
        want = ucv_string_get(item);

        if (want && !strcmp(type, want)) {
          ucv_array_push(result, ucv_int64_new(ts_node_start_byte(current)));
          break;
        }
      }

      if (ts_tree_cursor_goto_first_child(&cursor))
        continue;
    }

    /* The cursor's root is `node`: it has no siblings or parent to visit. */
    if (ts_tree_cursor_goto_next_sibling(&cursor)) {
      descend = true;
      continue;
    }

    if (!ts_tree_cursor_goto_parent(&cursor))
      break;

    descend = false;
  }

  ts_tree_cursor_delete(&cursor);

  return result;
}

static uc_value_t *uc_ts_node_descendant_at(uc_vm_t *vm, size_t nargs) {
  return descendant_at(vm, nargs, false);
}

static uc_value_t *uc_ts_node_named_descendant_at(uc_vm_t *vm, size_t nargs) {
  return descendant_at(vm, nargs, true);
}

static const char *query_error_name(TSQueryError type) {
  switch (type) {
  case TSQueryErrorSyntax:
    return "syntax error";
  case TSQueryErrorNodeType:
    return "invalid node type";
  case TSQueryErrorField:
    return "invalid field name";
  case TSQueryErrorCapture:
    return "invalid capture name";
  case TSQueryErrorStructure:
    return "invalid pattern structure";
  case TSQueryErrorLanguage:
    return "invalid language";
  default:
    return "unknown error";
  }
}

static uc_value_t *uc_ts_query_new(uc_vm_t *vm, size_t nargs) {
  const TSLanguage *lang = ucv_resource_data(uc_fn_arg(0), "ts.language");
  uc_value_t *srcval = uc_fn_arg(1);
  uint32_t error_offset;
  TSQueryError error_type;
  TSQuery *query;

  /* explicit check: see comment in uc_ts_parse() */
  if (!lang || ucv_type(srcval) != UC_STRING) {
    uc_vm_raise_exception(
        vm, EXCEPTION_TYPE,
        "expecting a language handle and a query source string");
    return NULL;
  }

  query = ts_query_new(lang, ucv_string_get(srcval), ucv_string_length(srcval),
                       &error_offset, &error_type);

  if (!query) {
    uc_vm_raise_exception(vm, EXCEPTION_RUNTIME, "query %s at byte %u",
                          query_error_name(error_type), error_offset);
    return NULL;
  }

  return uc_resource_new(query_type, query);
}

static uc_value_t *uc_ts_query_pattern_count(uc_vm_t *vm, size_t nargs) {
  TSQuery *query = ucv_resource_data(uc_fn_arg(0), "ts.query");

  if (!query) {
    uc_vm_raise_exception(vm, EXCEPTION_TYPE, "expecting a query handle");
    return NULL;
  }

  return ucv_int64_new(ts_query_pattern_count(query));
}

/*
 * Returns the raw predicate steps for a pattern as a flat array of
 * { type: "capture"|"string"|"done", value: <name or literal text> }.
 * Grouping steps into individual predicates (splitting on "done") and
 * evaluating standard predicates (#eq?, #match?, ...) is policy, not
 * mechanism, and belongs in ts.uc.
 */
static uc_value_t *uc_ts_query_predicate_steps(uc_vm_t *vm, size_t nargs) {
  TSQuery *query = ucv_resource_data(uc_fn_arg(0), "ts.query");
  uc_value_t *patternval = uc_fn_arg(1);
  const TSQueryPredicateStep *steps;
  uint32_t count, i, len;
  const char *text;
  uc_value_t *result, *step;

  if (!query) {
    uc_vm_raise_exception(vm, EXCEPTION_TYPE, "expecting a query handle");
    return NULL;
  }

  steps =
      ts_query_predicates_for_pattern(query, ucv_int64_get(patternval), &count);
  result = ucv_array_new(vm);

  for (i = 0; i < count; i++) {
    step = ucv_object_new(vm);

    switch (steps[i].type) {
    case TSQueryPredicateStepTypeCapture:
      text = ts_query_capture_name_for_id(query, steps[i].value_id, &len);
      ucv_object_add(step, "type", ucv_string_new("capture"));
      ucv_object_add(step, "value", ucv_string_new_length(text, len));
      break;

    case TSQueryPredicateStepTypeString:
      text = ts_query_string_value_for_id(query, steps[i].value_id, &len);
      ucv_object_add(step, "type", ucv_string_new("string"));
      ucv_object_add(step, "value", ucv_string_new_length(text, len));
      break;

    default:
      ucv_object_add(step, "type", ucv_string_new("done"));
      break;
    }

    ucv_array_push(result, step);
  }

  return result;
}

static uc_value_t *uc_ts_query_matches(uc_vm_t *vm, size_t nargs) {
  TSQuery *query = ucv_resource_data(uc_fn_arg(0), "ts.query");
  uc_value_t *nodeval = uc_fn_arg(1);
  uc_ts_node_t *node = ucv_resource_data(nodeval, "ts.node");
  TSQueryCursor *cursor;
  TSQueryMatch match;
  uc_value_t *result, *matchval, *captures, *capture;
  uint32_t i, len;
  const char *name;

  if (!query || !node) {
    uc_vm_raise_exception(vm, EXCEPTION_TYPE,
                          "expecting a query handle and a node handle");
    return NULL;
  }

  cursor = ts_query_cursor_new();
  ts_query_cursor_exec(cursor, query, node->node);

  result = ucv_array_new(vm);

  while (ts_query_cursor_next_match(cursor, &match)) {
    matchval = ucv_object_new(vm);
    captures = ucv_array_new(vm);

    for (i = 0; i < match.capture_count; i++) {
      name = ts_query_capture_name_for_id(query, match.captures[i].index, &len);
      capture = ucv_object_new(vm);
      ucv_object_add(capture, "name", ucv_string_new_length(name, len));
      ucv_object_add(capture, "node",
                     node_wrap(node->tree_ref, match.captures[i].node));
      ucv_array_push(captures, capture);
    }

    ucv_object_add(matchval, "pattern", ucv_int64_new(match.pattern_index));
    ucv_object_add(matchval, "captures", captures);
    ucv_array_push(result, matchval);
  }

  ts_query_cursor_delete(cursor);

  return result;
}

static const uc_function_list_t global_fns[] = {
    {"ts_language_ucode", uc_ts_language_ucode},
    {"ts_language_ucdocs", uc_ts_language_ucdocs},
    {"ts_language_ucode_markup", uc_ts_language_ucode_markup},
    {"ts_new_parser", uc_ts_new_parser},
    {"ts_parse", uc_ts_parse},
    {"ts_reparse", uc_ts_reparse},
    {"ts_root_node", uc_ts_root_node},
    {"ts_node_type", uc_ts_node_type},
    {"ts_node_is_named", uc_ts_node_is_named},
    {"ts_node_is_missing", uc_ts_node_is_missing},
    {"ts_node_has_error", uc_ts_node_has_error},
    {"ts_node_text", uc_ts_node_text},
    {"ts_node_start_byte", uc_ts_node_start_byte},
    {"ts_node_end_byte", uc_ts_node_end_byte},
    {"ts_node_child_count", uc_ts_node_child_count},
    {"ts_node_named_child_count", uc_ts_node_named_child_count},
    {"ts_node_child", uc_ts_node_child},
    {"ts_node_named_child", uc_ts_node_named_child},
    {"ts_node_child_by_field", uc_ts_node_child_by_field},
    {"ts_node_parent", uc_ts_node_parent},
    {"ts_node_children", uc_ts_node_children},
    {"ts_node_named_children", uc_ts_node_named_children},
    {"ts_node_children_by_field", uc_ts_node_children_by_field},
    {"ts_node_descendant_at", uc_ts_node_descendant_at},
    {"ts_node_descendant_offsets", uc_ts_node_descendant_offsets},
    {"ts_node_named_descendant_at", uc_ts_node_named_descendant_at},
    {"ts_query_new", uc_ts_query_new},
    {"ts_query_pattern_count", uc_ts_query_pattern_count},
    {"ts_query_predicate_steps", uc_ts_query_predicate_steps},
    {"ts_query_matches", uc_ts_query_matches},
};

void uc_module_init(uc_vm_t *vm, uc_value_t *scope) {
  parser_type = _uc_type_declare(vm, "ts.parser", NULL, 0, parser_free);
  tree_type = _uc_type_declare(vm, "ts.tree", NULL, 0, tree_free);
  node_type = _uc_type_declare(vm, "ts.node", NULL, 0, node_free);
  language_type = _uc_type_declare(vm, "ts.language", NULL, 0, NULL);
  query_type = _uc_type_declare(vm, "ts.query", NULL, 0, query_free);

  uc_function_list_register(scope, global_fns);
}
