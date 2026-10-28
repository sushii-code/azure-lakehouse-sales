-- By default dbt glues the target schema in front of a custom schema
-- (gold + staging = gold_staging). This override uses the custom schema
-- exactly as written, so models land in workspace.staging and workspace.gold.
-- Models without a custom schema fall back to the target schema from profiles.yml.

{% macro generate_schema_name(custom_schema_name, node) -%}
    {%- if custom_schema_name is none -%}
        {{ target.schema }}
    {%- else -%}
        {{ custom_schema_name | trim }}
    {%- endif -%}
{%- endmacro %}
