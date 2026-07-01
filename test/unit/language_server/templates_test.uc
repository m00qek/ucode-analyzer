import { describe, it, assert, mock, beforeEach } from 'utest';
import * as templates from 'language_server.templates';

let SELF_SRC = '/app/src';

describe('templates.resolveTemplate', () => {
	beforeEach(() => templates.resetCache());

	it('returns the built-in path when only selfSrcDir is configured', () => {
		let path = templates.resolveTemplate('hover/function', { selfSrcDir: SELF_SRC });
		assert.match(SELF_SRC + '/language_server/templates/hover/function.uc', path);
	});

	it('returns null when neither configDir nor selfSrcDir is set', () => {
		assert.match(null, templates.resolveTemplate('hover/function', {}));
	});

	it('returns null for a template name that does not exist in selfSrcDir', () => {
		let path = templates.resolveTemplate('hover/no_such_template', { selfSrcDir: SELF_SRC });
		assert.match(null, path);
	});

	it('prefers configDir over selfSrcDir when the user file exists', () => {
		mock.global.patch('fs', { data: {
			'/custom/templates/hover/function.uc': '{{ label }}',
		}});
		let config = { configDir: '/custom', selfSrcDir: SELF_SRC };
		let path = templates.resolveTemplate('hover/function', config);
		mock.global.unpatch('fs');

		assert.match('/custom/templates/hover/function.uc', path);
	});

	it('falls back to selfSrcDir when the configDir file does not exist', () => {
		let config = { configDir: '/nonexistent_user_dir', selfSrcDir: SELF_SRC };
		let path = templates.resolveTemplate('hover/function', config);
		assert.match(SELF_SRC + '/language_server/templates/hover/function.uc', path);
	});

	it('caches: second call returns same result without re-checking disk', () => {
		let config = { selfSrcDir: SELF_SRC };
		let first = templates.resolveTemplate('hover/function', config);

		// Block disk access — cache must serve the answer without hitting fs.
		mock.global.patch('fs', { strict: true, data: {} });
		let second = templates.resolveTemplate('hover/function', config);
		mock.global.unpatch('fs');

		assert.match(first, second);
	});
});

describe('templates.renderTemplate — built-in defaults', () => {
	let _config = { selfSrcDir: SELF_SRC };

	beforeEach(() => templates.resetCache());

	it('default template: renders code fence with label and typeStr', () => {
		let ctx = { label: 'x', typeStr: 'int', doc: null };
		let md = templates.renderTemplate('hover/default', ctx, _config);
		assert.match(true, md !== null);
		assert.match(true, index(md, 'x') >= 0);
		assert.match(true, index(md, 'int') >= 0);
	});

	it('default template: includes description when doc is present', () => {
		let ctx = { label: 'x', typeStr: 'int', doc: { description: 'A count value.', examples: [] } };
		let md = templates.renderTemplate('hover/default', ctx, _config);
		assert.match(true, index(md, 'A count value.') >= 0);
	});

	it('default template: includes @example blocks', () => {
		let ctx = { label: 'x', typeStr: 'int', doc: { description: null, examples: ['let x = 1;'] } };
		let md = templates.renderTemplate('hover/default', ctx, _config);
		assert.match(true, index(md, 'let x = 1;') >= 0);
		assert.match(true, index(md, '**Example:**') >= 0);
	});

	it('function template: renders declaration-form signature in code fence', () => {
		let ctx = {
			label: 'parse',
			signature: 'function parse(src: string): tree',
			typeStr: '(src: string) => tree',
			doc: { description: 'Parse text.', examples: [] },
			params: [{ name: 'src', typeStr: 'string', description: 'Source text.' }],
			returns: { typeStr: 'tree', description: null },
		};
		let md = templates.renderTemplate('hover/function', ctx, _config);
		assert.match(true, index(md, 'function parse(src: string): tree') >= 0);
	});

	it('function template: renders parameter list with each param on its own line', () => {
		let ctx = {
			label: 'match',
			signature: 'function match(expected: T, actual: T, msg: string): *',
			typeStr: '(expected: T, actual: T, msg: string) => *',
			doc: { description: 'Asserts equality.', examples: [] },
			params: [
				{ name: 'expected', typeStr: 'T', description: 'The expected value.' },
				{ name: 'actual',   typeStr: 'T', description: 'The actual value.' },
				{ name: 'msg',      typeStr: 'string', description: null },
			],
			returns: { typeStr: '?', description: null },
		};
		let md = templates.renderTemplate('hover/function', ctx, _config);
		assert.match(true, index(md, '**Parameters:**') >= 0);
		// Each param must be on its own line — check newline between items.
		assert.match(true, index(md, '\n- `expected`') >= 0);
		assert.match(true, index(md, '\n- `actual`') >= 0);
		assert.match(true, index(md, '\n- `msg`') >= 0);
		// Descriptions appear inline after em-dash.
		assert.match(true, index(md, '— The expected value.') >= 0);
	});

	it('function template: strips leading dash from descriptions', () => {
		let ctx = {
			label: 'f',
			signature: 'function f(x: int): *',
			typeStr: '(x: int) => *',
			doc: { description: null, examples: [] },
			params: [{ name: 'x', typeStr: 'int', description: 'The value.' }],
			returns: null,
		};
		let md = templates.renderTemplate('hover/function', ctx, _config);
		// Should not have "— - The value." — description already clean.
		assert.match(true, index(md, '— The value.') >= 0);
		assert.match(false, index(md, '— - ') >= 0);
	});

	it('function template: includes returns description when present', () => {
		let ctx = {
			label: 'f',
			signature: 'function f(): int',
			typeStr: '() => int',
			doc: { description: null, examples: [] },
			params: [],
			returns: { typeStr: 'int', description: 'The result.' },
		};
		let md = templates.renderTemplate('hover/function', ctx, _config);
		assert.match(true, index(md, '**Returns:**') >= 0);
		assert.match(true, index(md, 'The result.') >= 0);
	});

	it('record template: lists fields each on its own line', () => {
		let ctx = {
			label: 'assert',
			typeStr: '{ match, throws }',
			doc: { description: 'Assertions.', examples: [] },
			fields: [
				{ name: 'match',  typeStr: 'function', description: 'Assert equality.' },
				{ name: 'throws', typeStr: 'function', description: null },
			],
		};
		let md = templates.renderTemplate('hover/record', ctx, _config);
		assert.match(true, index(md, 'assert') >= 0);
		assert.match(true, index(md, '**Members:**') >= 0);
		assert.match(true, index(md, '\n- `match`') >= 0);
		assert.match(true, index(md, '— Assert equality.') >= 0);
		assert.match(true, index(md, '\n- `throws`') >= 0);
	});

	it('module template: renders specifier and description', () => {
		let ctx = {
			label: 'ts',
			typeStr: "module 'tree_sitter'",
			module: { specifier: 'tree_sitter', description: 'Tree-sitter bindings.' },
		};
		let md = templates.renderTemplate('hover/module', ctx, _config);
		assert.match(true, index(md, 'ts') >= 0);
		assert.match(true, index(md, 'tree_sitter') >= 0);
		assert.match(true, index(md, 'Tree-sitter bindings.') >= 0);
	});

	it('returns null for a nonexistent template name', () => {
		assert.match(null, templates.renderTemplate('hover/no_such', {}, _config));
	});
});
