-- Fails the build if any table in the reconciliation report does not reconcile.
-- Each returned row is a table where rows were lost or created somewhere between bronze and gold.
-- coalesce treats a missing (NULL) result as a failure too, so a broken check can't pass silently.

select *
from {{ ref('reconciliation_report') }}
where not coalesce(check_passed, false)
