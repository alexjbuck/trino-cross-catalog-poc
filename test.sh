#!/bin/bash
set -e

# Use local trino CLI connecting to localhost:8080
TRINO="trino --server http://localhost:8080"

echo "=== Cross-Catalog View POC Test ==="
echo ""

echo "1. Waiting for Trino to be ready..."
until $TRINO --execute "SELECT 1" > /dev/null 2>&1; do
    echo "   Waiting..."
    sleep 5
done
echo "   Trino is ready!"
echo ""

echo "2. Setting up Lakekeeper warehouse..."
# Create warehouse in Lakekeeper via REST API
curl -s -X POST http://localhost:8181/management/v1/warehouse \
  -H "Content-Type: application/json" \
  -d '{
    "warehouse-name": "demo",
    "project-id": "00000000-0000-0000-0000-000000000000",
    "storage-profile": {
      "type": "s3",
      "bucket": "warehouse",
      "region": "us-east-1",
      "path-style-access": true,
      "endpoint": "http://minio:9000",
      "flavor": "minio"
    },
    "storage-credential": {
      "type": "s3",
      "credential-type": "access-key",
      "aws-access-key-id": "minioadmin",
      "aws-secret-access-key": "minioadmin"
    }
  }' || echo "   (warehouse may already exist)"
echo ""

echo "3. Creating Iceberg schema and table..."
$TRINO --execute "CREATE SCHEMA IF NOT EXISTS iceberg.demo"
$TRINO --execute "
CREATE TABLE IF NOT EXISTS iceberg.demo.data (
    date DATE,
    data INTEGER
)"
echo ""

echo "4. Inserting test data into Iceberg table..."
$TRINO --execute "DELETE FROM iceberg.demo.data WHERE true" 2>/dev/null || true
$TRINO --execute "
INSERT INTO iceberg.demo.data VALUES
    (DATE '2024-01-01', 100),
    (DATE '2024-01-02', 200),
    (DATE '2024-01-03', 300),
    (DATE '2024-01-04', 400),
    (DATE '2024-01-05', 500),
    (DATE '2024-01-06', 600),
    (DATE '2024-01-07', 700)
"
echo ""

echo "5. Verifying Postgres requirements table..."
$TRINO --execute "SELECT * FROM postgres.public.requirements ORDER BY date, requirement"
echo ""

echo "6. Verifying Iceberg data table..."
$TRINO --execute "SELECT * FROM iceberg.demo.data ORDER BY date"
echo ""

echo "7. Testing cross-catalog join (the key test!)..."
echo "   Running: SELECT from iceberg.demo.data JOIN postgres.public.requirements"
$TRINO --execute "
SELECT d.date, d.data, r.requirement
FROM iceberg.demo.data d
JOIN postgres.public.requirements r ON d.date = r.date
ORDER BY d.date, r.requirement
"
echo ""

echo "8. Testing the access control query pattern..."
echo "   Simulating user with groups: ['admin', 'analyst', 'public']"
echo ""
echo "   This query returns rows where the user has ALL required groups:"
$TRINO --execute "
SELECT d.date, d.data
FROM iceberg.demo.data d
WHERE NOT EXISTS (
    SELECT 1
    FROM postgres.public.requirements r
    WHERE r.date = d.date
    AND r.requirement NOT IN ('admin', 'analyst', 'public')
)
ORDER BY d.date
"
echo ""

echo "9. Testing with different user groups..."
echo "   Simulating user with groups: ['analyst', 'public'] (no admin)"
$TRINO --execute "
SELECT d.date, d.data
FROM iceberg.demo.data d
WHERE NOT EXISTS (
    SELECT 1
    FROM postgres.public.requirements r
    WHERE r.date = d.date
    AND r.requirement NOT IN ('analyst', 'public')
)
ORDER BY d.date
"
echo ""

echo "10. Testing with minimal groups..."
echo "    Simulating user with groups: ['public'] only"
$TRINO --execute "
SELECT d.date, d.data
FROM iceberg.demo.data d
WHERE NOT EXISTS (
    SELECT 1
    FROM postgres.public.requirements r
    WHERE r.date = d.date
    AND r.requirement NOT IN ('public')
)
ORDER BY d.date
"
echo ""

echo "=== Summary of Expected Results ==="
echo ""
echo "Requirements by date:"
echo "  Jan 1: admin"
echo "  Jan 2: analyst"
echo "  Jan 3: public"
echo "  Jan 4: admin + analyst"
echo "  Jan 5: admin + analyst + public"
echo "  Jan 6: secret"
echo "  Jan 7: secret + admin"
echo ""
echo "Expected access:"
echo "  User [admin,analyst,public]: Jan 1,2,3,4,5 (data: 100,200,300,400,500)"
echo "  User [analyst,public]:       Jan 2,3       (data: 200,300)"
echo "  User [public]:               Jan 3         (data: 300)"
echo ""
echo "=== POC Complete ==="
