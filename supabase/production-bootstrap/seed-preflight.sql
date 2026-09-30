-- READ ONLY source-side guards for the optional, INCOMPLETE reference candidate.
-- Returning zero does not make the reference candidate production-ready.
SELECT count(*) FROM fitmatch_catalog.product_classification_history
WHERE reviewed_by IS NOT NULL;
