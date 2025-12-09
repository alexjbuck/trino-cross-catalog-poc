# Trino Cross-Catalog View POC

Proof of concept demonstrating Trino's ability to execute views that reference tables across multiple catalogs (Iceberg REST + PostgreSQL).

## The Problem

Access control requires joining:
- Data in Iceberg tables (via REST catalog / Lakekeeper)
- Access requirements in PostgreSQL

Views stored in the Iceberg catalog need to reference both catalogs for row-level filtering.

## Architecture

```
┌─────────────────┐     ┌──────────────────┐
│  Trino (478)    │────▶│  PostgreSQL      │
│                 │     │  requirements    │
│                 │     └──────────────────┘
│                 │
│                 │     ┌──────────────────┐     ┌─────────┐
│                 │────▶│  Lakekeeper      │────▶│  MinIO  │
│                 │     │  (Iceberg REST)  │     │  (S3)   │
└─────────────────┘     └──────────────────┘     └─────────┘
```

## Quick Start

```bash
# Start all services
docker compose up -d

# Wait for services, then run test
./test.sh
```

## Test Data

**Requirements table** (postgres.public.requirements):
| date       | requirement |
|------------|-------------|
| 2024-01-01 | admin       |
| 2024-01-02 | analyst     |
| 2024-01-03 | public      |
| 2024-01-04 | admin       |
| 2024-01-04 | analyst     |
| 2024-01-05 | admin       |
| 2024-01-05 | analyst     |
| 2024-01-05 | public      |
| 2024-01-06 | secret      |
| 2024-01-07 | secret      |
| 2024-01-07 | admin       |

**Data table** (iceberg.demo.data):
| date       | data |
|------------|------|
| 2024-01-01 | 100  |
| 2024-01-02 | 200  |
| 2024-01-03 | 300  |
| 2024-01-04 | 400  |
| 2024-01-05 | 500  |
| 2024-01-06 | 600  |
| 2024-01-07 | 700  |

## Expected Results

User must have ALL requirements for a date to see that date's data.

| User Groups              | Visible Dates     | Visible Data      |
|--------------------------|-------------------|-------------------|
| [admin, analyst, public] | Jan 1,2,3,4,5     | 100,200,300,400,500 |
| [analyst, public]        | Jan 2,3           | 200,300           |
| [public]                 | Jan 3             | 300               |

## Access Control Query Pattern

```sql
SELECT d.date, d.data
FROM iceberg.demo.data d
WHERE NOT EXISTS (
    SELECT 1
    FROM postgres.public.requirements r
    WHERE r.date = d.date
    AND NOT contains(current_groups(), r.requirement)
);
```

The test script simulates this with hardcoded group lists since Trino OSS doesn't include a built-in file-based group provider.

## Files

- `docker-compose.yml` - Service definitions
- `init-postgres.sql` - Requirements table setup
- `setup-iceberg.sql` - Iceberg table DDL (run manually or via test.sh)
- `create-view.sql` - Cross-catalog view DDL
- `test.sh` - Automated test script
- `trino-config/catalog/` - Trino catalog configurations
