```ucode
{{ label }}: {{ typeStr }}
```
{%- if (doc?.description): %}

{{ doc.description }}
{%- endif %}
{%- if (length(params ?? []) > 0): %}

**Parameters:**
{%- for (let p in params): %}
- `{{ p.name }}`: `{{ p.typeStr }}`{%- if (p.description): %} — {{ p.description }}{%- endif %}
{%- endfor %}
{%- endif %}
{%- if (returns?.description): %}

**Returns:** {{ returns.description }}
{%- endif %}
{%- for (let ex in (doc?.examples ?? [])): %}

**Example:**
```ucode
{{ ex }}
```
{%- endfor %}
