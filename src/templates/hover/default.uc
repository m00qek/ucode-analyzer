```ucode
{{ label }}: {{ typeStr }}
```
{%- if (doc?.description): %}

{{ doc.description }}
{%- endif %}
{%- for (let ex in (doc?.examples ?? [])): %}

**Example:**
```ucode
{{ ex }}
```
{%- endfor %}
