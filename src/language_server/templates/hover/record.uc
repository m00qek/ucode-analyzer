```ucode
{{ label }}: {{ typeStr }}
```
{% if (doc?.description): %}

{{ doc.description }}
{% endif %}
{% if (length(fields ?? []) > 0): %}

**Members:**
{{ join('\n', map(fields, (f) => '- `' + f.name + '`' + (f.typeStr ? ': `' + f.typeStr + '`' : '') + (f.description ? ' — ' + f.description : ''))) }}
{% endif %}
{% for (let ex in (doc?.examples ?? [])): %}

**Example:**
```ucode
{{ ex }}
```
{% endfor %}
{% if (length(doc?.see ?? []) > 0): %}

**See:** {{ join(', ', doc.see) }}
{% endif %}
