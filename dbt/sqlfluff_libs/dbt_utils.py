"""Stand-in for the dbt_utils package, used ONLY by SQLFluff when it renders the SQL to lint it.

dbt itself never reads this file; real builds use the dbt_utils package from packages.yml.
The output only needs to be valid SQL of the same shape, so the linter can check the query.
"""


def generate_surrogate_key(field_list):
    return "md5(concat_ws('-', " + ", ".join(field_list) + "))"
