# Avalon University — Data Infrastructure (Block 2)

Self-hosted data platform for **Avalon University**, a fictional public university in
Paris: PostgreSQL (operational + warehouse schemas), Apache Kafka (KRaft), and a
Prometheus/Grafana monitoring stack — all defined as code and seeded with realistic
synthetic data.

This repository is the infrastructure layer of a four-part project:

| Block | Deliverable | Where |
|---|---|---|
| 1 — Data governance | Governance plan & policy for Avalon | separate documents |
| **2 — Infrastructure (this repo)** | **Postgres + Kafka + monitoring, IaC, data models** | here |
| 3 — Real-time pipeline | Kafka → warehouse pipeline, orchestration, dbt | consumes these topics |
| 4 — AI solution | Course-recommendation API + MLOps | trains on this warehouse |

## Quickstart (5 minutes)

Prerequisites: Docker (with Compose), Python 3.9+.

```bash
# 1. start the platform (8 services)
docker compose -f docker/docker-compose.yml up -d

# 2. seed it with synthetic data (5 000 students, ~150 000 enrollments)
pip install -r scripts/requirements.txt
./scripts/seed.sh

# 3. look around
open http://localhost:3000   # Grafana  (admin / avalon_grafana)
open http://localhost:8080   # Kafka UI
open http://localhost:9090   # Prometheus
```

Connection string: `postgresql://avalon:avalon_dev_password@localhost:5432/avalon`

## What gets deployed

| Service | Image | Purpose |
|---|---|---|
| postgres | postgres:16.6 | `app` schema (OLTP) + `warehouse` schema (star) |
| kafka | apache/kafka:3.9.0 | Event streaming, KRaft single broker, topics `avalon.enrollments` & `avalon.course_events` |
| kafka-init | apache/kafka:3.9.0 | One-shot topic creation, then exits |
| kafka-ui | provectuslabs/kafka-ui | Browser view of topics & messages |
| postgres-exporter | prometheuscommunity/postgres-exporter | DB metrics → Prometheus |
| kafka-exporter | danielqsj/kafka-exporter | Broker/topic metrics → Prometheus |
| prometheus | prom/prometheus:v3.1.0 | Metrics store, scrapes every 15 s |
| grafana | grafana/grafana:11.4.0 | "Avalon Platform Overview" dashboard, provisioned as code |

Architecture, ERD and star schema diagrams: **[docs/architecture.md](docs/architecture.md)**

## Repository layout

```
├── docker/                  # runtime definition (compose) + service configs
│   ├── docker-compose.yml
│   ├── postgres/initdb/     # schemas created on first boot (ERD + star)
│   ├── prometheus/          # scrape config
│   └── grafana/             # provisioned datasources + dashboard
├── terraform/               # the same stack as Terraform (Docker provider)
├── scripts/
│   ├── generate_data.py     # deterministic synthetic data (Faker fr_FR, --seed)
│   ├── load_warehouse.sql   # ELT: app schema → star schema (idempotent)
│   └── seed.sh              # one-command seed: generate + load warehouse
└── docs/architecture.md     # diagrams & design decisions
```

## Terraform path

The same stack can be managed declaratively (uses distinct `avalon-tf-*` names, so
don't run both drivers at once):

```bash
cd terraform
terraform init
terraform plan
terraform apply
```

Outputs print the DSN and the web UIs. `terraform destroy` tears everything down;
named volumes keep the data across re-applies.

## The synthetic dataset

`scripts/generate_data.py` produces a coherent university, reproducible from a seed:

- 5 faculties, 15 programs (bachelor/master), 40 teachers, 200 courses (ECTS 2-6)
- 5 000 students (French names, Faker `fr_FR`), cohorts spread over 4 academic years
- ~150 000 enrollments: 80 % inside the student's own faculty, level-matched,
  graded on the French 0-20 scale for past years, `in_progress` for 2025-2026

Tune it: `./scripts/seed.sh --students 20000 --years 5 --seed 7`

The same generator seeds Block 3's event replay and Block 4's training data, so all
three blocks tell one consistent story.

## Monitoring

Prometheus scrapes itself, postgres-exporter and kafka-exporter every 15 s. Grafana
auto-provisions a Prometheus datasource, a direct SQL datasource on the warehouse,
and the **Avalon Platform Overview** dashboard (DB health, connections, insert rate,
Kafka topics/throughput). Nothing is configured by hand in the UI.

## Security notes (dev posture)

Default credentials live in `.env.example` and are for local development only —
override them via environment variables (`POSTGRES_PASSWORD`, `TF_VAR_postgres_password`,
`GRAFANA_PASSWORD`) for any shared deployment. Exporters are not exposed on the host;
only the five user-facing ports are published.
