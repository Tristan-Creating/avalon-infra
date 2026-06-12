output "postgres_dsn" {
  description = "Connection string for the application database"
  value       = "postgresql://${var.postgres_user}:***@localhost:${var.postgres_port}/${var.postgres_db}"
}

output "kafka_bootstrap" {
  description = "Kafka bootstrap server (host listener)"
  value       = "localhost:${var.kafka_external_port}"
}

output "urls" {
  description = "Web interfaces"
  value = {
    kafka_ui   = "http://localhost:${var.kafka_ui_port}"
    prometheus = "http://localhost:${var.prometheus_port}"
    grafana    = "http://localhost:${var.grafana_port}"
  }
}
