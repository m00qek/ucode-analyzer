```ucode
{{ label }}: module '{{ module.specifier }}'
```
{%- if (module.description): %}

{{ module.description }}
{%- endif %}
{%- if (length(module.members ?? []) > 0): %}

**Members:**
{{ join('\n', map(module.members, (m) => '- `' + m.name + '`' + (m.typeStr ? ': `' + m.typeStr + '`' : ''))) }}
{%- endif %}
