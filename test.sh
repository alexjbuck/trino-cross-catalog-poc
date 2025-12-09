#!/bin/bash
set -e

# Use local trino CLI connecting to localhost:8080
TRINO="trino --server http://localhost:8080"

echo "=== Cross-Catalog View POC Test ==="
echo ""

echo "1. Waiting for Trino to be ready..."
until $TRINO --execute "SELECT 1" >/dev/null 2>&1; do
  echo "   Waiting..."
  sleep 5
done
echo "   Trino is ready!"
echo ""

echo "2. Bootstrapping Lakekeeper..."
curl -s -X POST http://localhost:8181/management/v1/bootstrap \
  -H "Content-Type: application/json" \
  -d '{"accept-terms-of-use": true}' || echo "   (may already be bootstrapped)"
echo ""

echo "3. Setting up Lakekeeper warehouse..."
# Create warehouse in Lakekeeper via REST API
curl -s -X POST http://localhost:8181/management/v1/warehouse \
  -H "Content-Type: application/json" \
  -d '{
    "warehouse-name": "demo",
    "storage-profile": {
      "type": "s3",
      "bucket": "warehouse",
      "region": "us-east-1",
      "path-style-access": true,
      "endpoint": "http://minio:9000",
      "flavor": "minio",
      "sts-enabled": false
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

echo "7. Testing cross-catalog join (inline query)..."
echo "   Running: SELECT from iceberg.demo.data JOIN postgres.public.requirements"
$TRINO --execute "
SELECT d.date, d.data, array_agg(r.requirement ORDER BY r.requirement) AS requirements
FROM iceberg.demo.data d
JOIN postgres.public.requirements r ON d.date = r.date
GROUP BY d.date, d.data
ORDER BY d.date
"
echo ""

echo "8. Creating STORED VIEW in Iceberg catalog (THE KEY TEST!)..."
echo "   This view references both iceberg.demo.data AND postgres.public.requirements"
$TRINO --execute "
CREATE OR REPLACE VIEW iceberg.demo.filtered_data AS
SELECT d.date, d.data
FROM iceberg.demo.data d
WHERE NOT EXISTS (
    SELECT 1
    FROM postgres.public.requirements r
    WHERE r.date = d.date
    AND NOT contains(current_groups(), r.requirement)
)
"
echo "   View created successfully!"
echo ""

echo "=== Testing STORED VIEW with different users (via file group provider) ==="
echo ""
echo "Group configuration (group.txt):"
echo "  admin:admin,superuser,poweruser"
echo "  analyst:analyst,alice,bob,poweruser"
echo "  public:admin,analyst,alice,bob,guest,public,poweruser"
echo ""

echo "9. User 'admin' - groups: [admin, public]"
echo "   Checking current_groups():"
trino --server http://localhost:8080 --user admin --execute "SELECT current_groups()"
echo "   Querying stored view:"
trino --server http://localhost:8080 --user admin --execute "SELECT * FROM iceberg.demo.filtered_data ORDER BY date"
echo ""

echo "10. User 'alice' - groups: [analyst, public]"
echo "    Checking current_groups():"
trino --server http://localhost:8080 --user alice --execute "SELECT current_groups()"
echo "    Querying stored view:"
trino --server http://localhost:8080 --user alice --execute "SELECT * FROM iceberg.demo.filtered_data ORDER BY date"
echo ""

echo "11. User 'guest' - groups: [public]"
echo "    Checking current_groups():"
trino --server http://localhost:8080 --user guest --execute "SELECT current_groups()"
echo "    Querying stored view:"
trino --server http://localhost:8080 --user guest --execute "SELECT * FROM iceberg.demo.filtered_data ORDER BY date"
echo ""

echo "12. User 'superuser' - groups: [admin] (no public!)"
echo "    Checking current_groups():"
trino --server http://localhost:8080 --user superuser --execute "SELECT current_groups()"
echo "    Querying stored view:"
trino --server http://localhost:8080 --user superuser --execute "SELECT * FROM iceberg.demo.filtered_data ORDER BY date"
echo ""

echo "13. User 'poweruser' - groups: [admin, analyst, public] (has all three)"
echo "    Checking current_groups():"
trino --server http://localhost:8080 --user poweruser --execute "SELECT current_groups()"
echo "    Querying stored view:"
trino --server http://localhost:8080 --user poweruser --execute "SELECT * FROM iceberg.demo.filtered_data ORDER BY date"
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
echo "Expected access (user -> groups -> visible dates):"
echo "  admin     [admin,public]:         Jan 1,3       (data: 100,300)"
echo "  alice     [analyst,public]:       Jan 2,3       (data: 200,300)"
echo "  guest     [public]:               Jan 3         (data: 300)"
echo "  superuser [admin]:                Jan 1         (data: 100)"
echo "  poweruser [admin,analyst,public]: Jan 1,2,3,4,5 (data: 100,200,300,400,500)"
echo ""
echo "=== POC Complete ==="
