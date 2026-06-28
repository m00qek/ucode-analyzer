```ucode
{{ signature }}
```
{% if (doc?.description): %}

{{ doc.description }}
{% endif %}
{% if (length(params ?? []) > 0): %}

**Parameters:**
{{ join('\n', map(params, (p) => '- `' + p.name + '`: `' + p.typeStr + '`' + (p.description ? ' — ' + p.description : ''))) }}
{% endif %}
{% if (returns?.description): %}

**Returns:** {{ returns.description }}
{% endif %}
{% for (let ex in (doc?.examples ?? [])): %}

**Example:**
```ucode
{{ ex }}
```
{% endfor %}
{% if (since): %}

*Since:* `{{ since }}`
{% endif %}
{% if (unavailable): %}

> ⚠ Not available in the installed version.
{% endif %}
