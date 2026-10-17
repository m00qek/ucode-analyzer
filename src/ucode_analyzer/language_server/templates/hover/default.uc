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
{%- if (length(doc?.see ?? []) > 0): %}

**See:** {{ join(', ', doc.see) }}
{%- endif %}
{%- if (since): %}

*Since:* `{{ since }}`
{%- endif %}
{%- if (unavailable): %}

> ⚠ Not available in the installed version.
{%- endif %}
