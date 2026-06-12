# Avalon University data platform — IaC definition of the self-hosted stack.
# Equivalent to docker/docker-compose.yml; pick ONE driver per environment:
#   terraform apply          (this file)
#   docker compose up -d     (compose)

locals {
  config_root = abspath("${path.module}/../docker")
}

resource "docker_network" "avalon" {
  name = "avalon-tf"
}

resource "docker_volume" "pgdata" {
  name = "avalon-tf-pgdata"
}

resource "docker_volume" "kafkadata" {
  name = "avalon-tf-kafkadata"
}

resource "docker_volume" "promdata" {
  name = "avalon-tf-promdata"
}

resource "docker_volume" "grafanadata" {
  name = "avalon-tf-grafanadata"
}

# ---------- images ----------

resource "docker_image" "postgres" {
  name = "postgres:16.6"
}

resource "docker_image" "kafka" {
  name = "apache/kafka:3.9.0"
}

resource "docker_image" "kafka_ui" {
  name = "provectuslabs/kafka-ui:v0.7.2"
}

resource "docker_image" "postgres_exporter" {
  name = "prometheuscommunity/postgres-exporter:v0.16.0"
}

resource "docker_image" "kafka_exporter" {
  name = "danielqsj/kafka-exporter:v1.8.0"
}

resource "docker_image" "prometheus" {
  name = "prom/prometheus:v3.1.0"
}

resource "docker_image" "grafana" {
  name = "grafana/grafana:11.4.0"
}

# ---------- core services ----------

resource "docker_container" "postgres" {
  name    = "avalon-tf-postgres"
  image   = docker_image.postgres.image_id
  restart = "unless-stopped"

  env = [
    "POSTGRES_USER=${var.postgres_user}",
    "POSTGRES_PASSWORD=${var.postgres_password}",
    "POSTGRES_DB=${var.postgres_db}",
  ]

  ports {
    internal = 5432
    external = var.postgres_port
  }

  volumes {
    volume_name    = docker_volume.pgdata.name
    container_path = "/var/lib/postgresql/data"
  }

  volumes {
    host_path      = "${local.config_root}/postgres/initdb"
    container_path = "/docker-entrypoint-initdb.d"
    read_only      = true
  }

  networks_advanced {
    name = docker_network.avalon.name
  }

  healthcheck {
    test     = ["CMD-SHELL", "pg_isready -U ${var.postgres_user} -d ${var.postgres_db}"]
    interval = "5s"
    timeout  = "3s"
    retries  = 12
  }
}

resource "docker_container" "kafka" {
  name    = "avalon-tf-kafka"
  image   = docker_image.kafka.image_id
  restart = "unless-stopped"

  env = [
    "KAFKA_NODE_ID=1",
    "KAFKA_PROCESS_ROLES=broker,controller",
    "KAFKA_CONTROLLER_QUORUM_VOTERS=1@avalon-tf-kafka:9093",
    "KAFKA_LISTENERS=INTERNAL://:9092,CONTROLLER://:9093,EXTERNAL://:9094",
    "KAFKA_ADVERTISED_LISTENERS=INTERNAL://avalon-tf-kafka:9092,EXTERNAL://localhost:${var.kafka_external_port}",
    "KAFKA_LISTENER_SECURITY_PROTOCOL_MAP=INTERNAL:PLAINTEXT,CONTROLLER:PLAINTEXT,EXTERNAL:PLAINTEXT",
    "KAFKA_INTER_BROKER_LISTENER_NAME=INTERNAL",
    "KAFKA_CONTROLLER_LISTENER_NAMES=CONTROLLER",
    "KAFKA_OFFSETS_TOPIC_REPLICATION_FACTOR=1",
    "KAFKA_TRANSACTION_STATE_LOG_REPLICATION_FACTOR=1",
    "KAFKA_TRANSACTION_STATE_LOG_MIN_ISR=1",
    "KAFKA_AUTO_CREATE_TOPICS_ENABLE=false",
    "CLUSTER_ID=avalon-kraft-cluster-001",
  ]

  ports {
    internal = 9094
    external = var.kafka_external_port
  }

  volumes {
    volume_name    = docker_volume.kafkadata.name
    container_path = "/var/lib/kafka/data"
  }

  networks_advanced {
    name = docker_network.avalon.name
  }
}

# ---------- observability ----------

resource "docker_container" "postgres_exporter" {
  name    = "avalon-tf-postgres-exporter"
  image   = docker_image.postgres_exporter.image_id
  restart = "unless-stopped"

  env = [
    "DATA_SOURCE_NAME=postgresql://${var.postgres_user}:${var.postgres_password}@avalon-tf-postgres:5432/${var.postgres_db}?sslmode=disable",
  ]

  networks_advanced {
    name = docker_network.avalon.name
  }

  depends_on = [docker_container.postgres]
}

resource "docker_container" "kafka_exporter" {
  name    = "avalon-tf-kafka-exporter"
  image   = docker_image.kafka_exporter.image_id
  restart = "unless-stopped"
  command = ["--kafka.server=avalon-tf-kafka:9092"]

  networks_advanced {
    name = docker_network.avalon.name
  }

  depends_on = [docker_container.kafka]
}

resource "docker_container" "prometheus" {
  name    = "avalon-tf-prometheus"
  image   = docker_image.prometheus.image_id
  restart = "unless-stopped"

  ports {
    internal = 9090
    external = var.prometheus_port
  }

  volumes {
    host_path      = "${local.config_root}/prometheus/prometheus.yml"
    container_path = "/etc/prometheus/prometheus.yml"
    read_only      = true
  }

  volumes {
    volume_name    = docker_volume.promdata.name
    container_path = "/prometheus"
  }

  networks_advanced {
    name = docker_network.avalon.name
  }
}

resource "docker_container" "kafka_ui" {
  name    = "avalon-tf-kafka-ui"
  image   = docker_image.kafka_ui.image_id
  restart = "unless-stopped"

  env = [
    "KAFKA_CLUSTERS_0_NAME=avalon",
    "KAFKA_CLUSTERS_0_BOOTSTRAPSERVERS=avalon-tf-kafka:9092",
  ]

  ports {
    internal = 8080
    external = var.kafka_ui_port
  }

  networks_advanced {
    name = docker_network.avalon.name
  }

  depends_on = [docker_container.kafka]
}

resource "docker_container" "grafana" {
  name    = "avalon-tf-grafana"
  image   = docker_image.grafana.image_id
  restart = "unless-stopped"

  env = [
    "GF_SECURITY_ADMIN_USER=admin",
    "GF_SECURITY_ADMIN_PASSWORD=${var.grafana_admin_password}",
    "GF_USERS_ALLOW_SIGN_UP=false",
  ]

  ports {
    internal = 3000
    external = var.grafana_port
  }

  volumes {
    volume_name    = docker_volume.grafanadata.name
    container_path = "/var/lib/grafana"
  }

  volumes {
    host_path      = "${local.config_root}/grafana/provisioning"
    container_path = "/etc/grafana/provisioning"
    read_only      = true
  }

  volumes {
    host_path      = "${local.config_root}/grafana/dashboards"
    container_path = "/var/lib/grafana/dashboards"
    read_only      = true
  }

  networks_advanced {
    name = docker_network.avalon.name
  }

  depends_on = [docker_container.prometheus]
}
