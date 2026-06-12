# Avalon University — Data Platform Architecture

Self-hosted data infrastructure for Avalon University (fictional public university, Paris).
It underpins three deliverables: this infrastructure (Block 2), the real-time pipeline
(Block 3) and the course-recommendation ML service (Block 4).

## Design decisions

| Decision | Choice | Why |
|---|---|---|
| Hosting | Self-hosted, Docker | Reproducible anywhere, no cloud billing, aligns with the GDPR/data-sovereignty posture of the governance plan (Block 1) |
| Warehouse | PostgreSQL 16 (dedicated `warehouse` schema) | dbt-compatible, free, swappable for a cloud warehouse without changing the architecture |
| Streaming | Apache Kafka 3.9, KRaft mode | Industry standard; no ZooKeeper; single broker is enough at this scale |
| IaC | Terraform (Docker provider) + Docker Compose | Compose for fast local loops, Terraform as the reviewable IaC definition |
| Monitoring | Prometheus + exporters + Grafana | Standard pull-based observability; one dashboard provisioned as code |

## Component view

```mermaid
flowchart LR
    subgraph sources [Sources]
        GEN["Synthetic data generator<br/>(scripts/generate_data.py)"]
        INTRANET["Avalon intranet<br/>(events, Block 3)"]
    end

    subgraph platform [Docker network: avalon]
        PG[("PostgreSQL 16<br/>app + warehouse schemas")]
        KAFKA[/"Kafka 3.9 (KRaft)<br/>avalon.enrollments<br/>avalon.course_events"/]
        KUI["Kafka UI :8080"]
        PEX["postgres-exporter"]
        KEX["kafka-exporter"]
        PROM["Prometheus :9090"]
        GRAF["Grafana :3000"]
    end

    GEN -->|seed| PG
    INTRANET -.->|produce| KAFKA
    KAFKA -.->|"consume (Block 3 pipeline)"| PG
    PG --> PEX --> PROM
    KAFKA --> KEX --> PROM
    KAFKA --- KUI
    PROM --> GRAF
    PG -->|SQL datasource| GRAF
```

Dashed arrows are Block 3 flows: the foundation provisions the broker and topics,
the pipeline code lives in the Block 3 repository.

## Operational data model (ERD, `app` schema)

```mermaid
erDiagram
    FACULTIES ||--o{ PROGRAMS : offers
    FACULTIES ||--o{ TEACHERS : employs
    FACULTIES ||--o{ COURSES : owns
    PROGRAMS ||--o{ STUDENTS : "enrolls"
    TEACHERS ||--o{ COURSES : teaches
    STUDENTS ||--o{ ENROLLMENTS : has
    COURSES ||--o{ ENROLLMENTS : receives

    FACULTIES {
        int faculty_id PK
        text code UK
        text name UK
    }
    PROGRAMS {
        int program_id PK
        int faculty_id FK
        text name
        text level "bachelor|master"
        int duration_years
    }
    TEACHERS {
        int teacher_id PK
        int faculty_id FK
        text first_name
        text last_name
        text email UK
    }
    STUDENTS {
        int student_id PK
        int program_id FK
        text first_name
        text last_name
        text email UK
        int enrollment_year
        text status "active|graduated|withdrawn"
    }
    COURSES {
        int course_id PK
        int faculty_id FK
        int teacher_id FK
        text code UK
        text title
        text level
        text semester "S1|S2"
        int ects
        int capacity
    }
    ENROLLMENTS {
        bigint enrollment_id PK
        int student_id FK
        int course_id FK
        int academic_year
        timestamptz enrolled_at
        numeric grade "0-20, NULL until graded"
        text status "in_progress|completed|failed|dropped"
    }
```

## Analytical model (star schema, `warehouse` schema)

```mermaid
erDiagram
    DIM_DATE ||--o{ FACT_ENROLLMENTS : "date_key"
    DIM_STUDENT ||--o{ FACT_ENROLLMENTS : "student_key"
    DIM_COURSE ||--o{ FACT_ENROLLMENTS : "course_key"

    FACT_ENROLLMENTS {
        bigint enrollment_key PK
        int date_key FK
        int student_key FK
        int course_key FK
        int academic_year
        numeric grade
        int ects_attempted
        int ects_earned
        text status
    }
    DIM_DATE {
        int date_key PK "YYYYMMDD"
        date full_date
        int year
        int month
        int academic_year
        text semester
    }
    DIM_STUDENT {
        int student_key PK
        text full_name
        text program
        text program_level
        text faculty
        int enrollment_year
        text status
    }
    DIM_COURSE {
        int course_key PK
        text code
        text title
        text faculty
        text level
        text semester
        int ects
        text teacher
    }
```

Grain of the fact table: **one row per student × course × academic year**.
Typical questions it answers: ECTS earned per faculty per year, failure rates by
course, enrollment volume per semester — and it is the training source for the
Block 4 course recommender.

The warehouse is loaded by `scripts/load_warehouse.sql` (full reload, idempotent).
In Block 3 this hand-written ELT is replaced by an orchestrated dbt project; the
schemas stay the same.

## Network & ports

| Service | Container | Host port |
|---|---|---|
| PostgreSQL | avalon-postgres | 5432 |
| Kafka (EXTERNAL listener) | avalon-kafka | 9094 |
| Kafka UI | avalon-kafka-ui | 8080 |
| Prometheus | avalon-prometheus | 9090 |
| Grafana | avalon-grafana | 3000 |

Exporters (postgres-exporter :9187, kafka-exporter :9308) are reachable only on the
internal `avalon` network — they have no published host ports.
