-- Create the cross-catalog view in iceberg
-- This view filters data based on requirements stored in postgres
-- User must have ALL requirements for a given date to see that date's data
--
-- Logic: exclude any row where there exists a requirement that the user doesn't have
CREATE OR REPLACE VIEW iceberg.demo.filtered_data AS
SELECT d.date, d.data
FROM iceberg.demo.data d
WHERE NOT EXISTS (
    SELECT 1
    FROM postgres.public.requirements r
    WHERE r.date = d.date
    AND NOT contains(current_groups(), r.requirement)
);
