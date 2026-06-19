/*
 * ucode native extension exposing the tree-sitter C API ("ts_native" module).
 *
 * This is deliberately a thin, mechanical FFI layer: one function per
 * tree-sitter call, minimal validation. Ergonomics (argument-checking with
 * friendly messages, structured results, collection helpers) live in the
 * companion ts.uc module, which is the module consumers should actually
 * import. The checks kept here are the ones that prevent a null-pointer
 * dereference or undefined behavior in C; ucode's own value accessors
 * (ucv_string_get, ucv_int64_get, ...) already fail safe (return NULL/0)
 * for wrong-typed arguments, so we don't duplicate that here.
 */

#include <tree_sitter/api.h>

#include <ucode/module.h>
#include <ucode/lib.h>

const TSLanguage *tree_sitter_ucode(void);
const TSLanguage *tree_sitter_ucdocs(void);

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

static uc_value_t *
node_wrap(uc_value_t *tree_ref, TSNode node)
{
	uc_ts_node_t *n;

	if (ts_node_is_null(node))
		return NULL;

	n = xalloc(sizeof(*n));
	n->tree_ref = ucv_get(tree_ref);
	n->node = node;

	return uc_resource_new(node_type, n);
}

static void
node_free(void *ptr)
{
	uc_ts_node_t *n = ptr;

	ucv_put(n->tree_ref);
	free(n);
}

static void
tree_free(void *ptr)
{
	ts_tree_delete((TSTree *)ptr);
}

static void
parser_free(void *ptr)
{
	ts_parser_delete((TSParser *)ptr);
}

static uc_value_t *
uc_ts_language_ucode(uc_vm_t *vm, size_t nargs)
{
	return uc_resource_new(language_type, (void *)tree_sitter_ucode());
}

static uc_value_t *
uc_ts_language_ucdocs(uc_vm_t *vm, size_t nargs)
{
	return uc_resource_new(language_type, (void *)tree_sitter_ucdocs());
}

static uc_value_t *
uc_ts_new_parser(uc_vm_t *vm, size_t nargs)
{
	const TSLanguage *lang = ucv_resource_data(uc_fn_arg(0), "ts.language");
	TSParser *parser;

	if (!lang) {
		uc_vm_raise_exception(vm, EXCEPTION_TYPE, "expecting a language handle");
		return NULL;
	}

	parser = ts_parser_new();

	if (!ts_parser_set_language(parser, lang)) {
		ts_parser_delete(parser);
		uc_vm_raise_exception(vm, EXCEPTION_RUNTIME, "incompatible language version");
		return NULL;
	}

	return uc_resource_new(parser_type, parser);
}

static uc_value_t *
uc_ts_parse(uc_vm_t *vm, size_t nargs)
{
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
		uc_vm_raise_exception(vm, EXCEPTION_TYPE, "expecting a parser handle and a source string");
		return NULL;
	}

	tree = ts_parser_parse_string(parser, NULL,
		ucv_string_get(srcval), ucv_string_length(srcval));

	if (!tree) {
		uc_vm_raise_exception(vm, EXCEPTION_RUNTIME, "parse failed");
		return NULL;
	}

	return uc_resource_new(tree_type, tree);
}

static uc_value_t *
uc_ts_root_node(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *treeval = uc_fn_arg(0);
	TSTree *tree = ucv_resource_data(treeval, "ts.tree");

	if (!tree) {
		uc_vm_raise_exception(vm, EXCEPTION_TYPE, "expecting a tree handle");
		return NULL;
	}

	return node_wrap(treeval, ts_tree_root_node(tree));
}

static uc_ts_node_t *
node_arg(uc_vm_t *vm, size_t nargs, size_t n)
{
	uc_ts_node_t *node = ucv_resource_data(uc_fn_arg(n), "ts.node");

	if (!node)
		uc_vm_raise_exception(vm, EXCEPTION_TYPE, "expecting a node handle");

	return node;
}

static uc_value_t *
uc_ts_node_type(uc_vm_t *vm, size_t nargs)
{
	uc_ts_node_t *node = node_arg(vm, nargs, 0);

	return node ? ucv_string_new(ts_node_type(node->node)) : NULL;
}

static uc_value_t *
uc_ts_node_is_named(uc_vm_t *vm, size_t nargs)
{
	uc_ts_node_t *node = node_arg(vm, nargs, 0);

	return node ? ucv_boolean_new(ts_node_is_named(node->node)) : NULL;
}

static uc_value_t *
uc_ts_node_text(uc_vm_t *vm, size_t nargs)
{
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

static uc_value_t *
uc_ts_node_start_byte(uc_vm_t *vm, size_t nargs)
{
	uc_ts_node_t *node = node_arg(vm, nargs, 0);

	return node ? ucv_int64_new(ts_node_start_byte(node->node)) : NULL;
}

static uc_value_t *
uc_ts_node_end_byte(uc_vm_t *vm, size_t nargs)
{
	uc_ts_node_t *node = node_arg(vm, nargs, 0);

	return node ? ucv_int64_new(ts_node_end_byte(node->node)) : NULL;
}

static uc_value_t *
uc_ts_node_child_count(uc_vm_t *vm, size_t nargs)
{
	uc_ts_node_t *node = node_arg(vm, nargs, 0);

	return node ? ucv_int64_new(ts_node_child_count(node->node)) : NULL;
}

static uc_value_t *
uc_ts_node_named_child_count(uc_vm_t *vm, size_t nargs)
{
	uc_ts_node_t *node = node_arg(vm, nargs, 0);

	return node ? ucv_int64_new(ts_node_named_child_count(node->node)) : NULL;
}

static uc_value_t *
uc_ts_node_child(uc_vm_t *vm, size_t nargs)
{
	uc_ts_node_t *node = node_arg(vm, nargs, 0);

	if (!node)
		return NULL;

	return node_wrap(node->tree_ref, ts_node_child(node->node, ucv_int64_get(uc_fn_arg(1))));
}

static uc_value_t *
uc_ts_node_named_child(uc_vm_t *vm, size_t nargs)
{
	uc_ts_node_t *node = node_arg(vm, nargs, 0);

	if (!node)
		return NULL;

	return node_wrap(node->tree_ref, ts_node_named_child(node->node, ucv_int64_get(uc_fn_arg(1))));
}

static uc_value_t *
uc_ts_node_child_by_field(uc_vm_t *vm, size_t nargs)
{
	uc_ts_node_t *node = node_arg(vm, nargs, 0);
	uc_value_t *fieldval = uc_fn_arg(1);

	if (!node)
		return NULL;

	return node_wrap(node->tree_ref,
		ts_node_child_by_field_name(node->node, ucv_string_get(fieldval), ucv_string_length(fieldval)));
}

static uc_value_t *
uc_ts_node_parent(uc_vm_t *vm, size_t nargs)
{
	uc_ts_node_t *node = node_arg(vm, nargs, 0);

	if (!node)
		return NULL;

	return node_wrap(node->tree_ref, ts_node_parent(node->node));
}

static const uc_function_list_t global_fns[] = {
	{ "ts_language_ucode",         uc_ts_language_ucode },
	{ "ts_language_ucdocs",        uc_ts_language_ucdocs },
	{ "ts_new_parser",             uc_ts_new_parser },
	{ "ts_parse",                  uc_ts_parse },
	{ "ts_root_node",              uc_ts_root_node },
	{ "ts_node_type",              uc_ts_node_type },
	{ "ts_node_is_named",          uc_ts_node_is_named },
	{ "ts_node_text",              uc_ts_node_text },
	{ "ts_node_start_byte",        uc_ts_node_start_byte },
	{ "ts_node_end_byte",          uc_ts_node_end_byte },
	{ "ts_node_child_count",       uc_ts_node_child_count },
	{ "ts_node_named_child_count", uc_ts_node_named_child_count },
	{ "ts_node_child",             uc_ts_node_child },
	{ "ts_node_named_child",       uc_ts_node_named_child },
	{ "ts_node_child_by_field",    uc_ts_node_child_by_field },
	{ "ts_node_parent",            uc_ts_node_parent },
};

void uc_module_init(uc_vm_t *vm, uc_value_t *scope)
{
	parser_type = _uc_type_declare(vm, "ts.parser", NULL, 0, parser_free);
	tree_type = _uc_type_declare(vm, "ts.tree", NULL, 0, tree_free);
	node_type = _uc_type_declare(vm, "ts.node", NULL, 0, node_free);
	language_type = _uc_type_declare(vm, "ts.language", NULL, 0, NULL);

	uc_function_list_register(scope, global_fns);
}
