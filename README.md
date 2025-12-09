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

## Prerequisites

- Docker (with compose)

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

**User groups** (trino-config/group.txt):
| Group   | Members                     |
|---------|-----------------------------|
| admin   | admin, superuser, poweruser |
| analyst | analyst, alice, bob, poweruser |
| public  | admin, analyst, alice, bob, guest, public, poweruser |

## Expected Results

User must have ALL requirements for a date to see that date's data.

| User      | Groups                   | Visible Dates | Visible Data        |
|-----------|--------------------------|---------------|---------------------|
| poweruser | [admin, analyst, public] | Jan 1,2,3,4,5 | 100,200,300,400,500 |
| admin     | [admin, public]          | Jan 1,3       | 100,300             |
| alice     | [analyst, public]        | Jan 2,3       | 200,300             |
| guest     | [public]                 | Jan 3         | 300                 |
| superuser | [admin]                  | Jan 1         | 100                 |

## Access Control Query Pattern

The stored view `iceberg.demo.filtered_data` uses this pattern:

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

User groups are configured via Trino's file-based group provider (`trino-config/group.txt`).

## Files

- `docker-compose.yml` - Service definitions
- `init-postgres.sql` - Requirements table setup
- `setup-iceberg.sql` - Iceberg table DDL (reference)
- `create-view.sql` - Cross-catalog view DDL (reference)
- `test.sh` - Automated test script
- `trino-config/catalog/` - Trino catalog configurations
- `trino-config/group-provider.properties` - File group provider config
- `trino-config/group.txt` - User to group mappings
