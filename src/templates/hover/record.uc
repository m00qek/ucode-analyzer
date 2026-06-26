```ucode
{{ label }}: {{ typeStr }}
```
{%- if (doc?.description): %}

{{ doc.description }}
{%- endif %}
{%- if (length(fields ?? []) > 0): %}

**Members:**
{%- for (let f in fields): %}
- `{{ f.name }}`{%- if (f.typeStr): %}: `{{ f.typeStr }}`{%- endif %}{%- if (f.description): %} — {{ f.description }}{%- endif %}
{%- endfor %}
{%- endif %}
{%- for (let ex in (doc?.examples ?? [])): %}

**Example:**
```ucode
{{ ex }}
```
{%- endfor %}
