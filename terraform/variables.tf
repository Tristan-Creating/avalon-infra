variable "postgres_user" {
  description = "Postgres application user"
  type        = string
  default     = "avalon"
}

variable "postgres_password" {
  description = "Postgres password (override via TF_VAR_postgres_password)"
  type        = string
  default     = "avalon_dev_password"
  sensitive   = true
}

variable "postgres_db" {
  description = "Application database name"
  type        = string
  default     = "avalon"
}

variable "grafana_admin_password" {
  description = "Grafana admin password"
  type        = string
  default     = "avalon_grafana"
  sensitive   = true
}

variable "postgres_port" {
  type    = number
  default = 5432
}

variable "kafka_external_port" {
  type    = number
  default = 9094
}

variable "kafka_ui_port" {
  type    = number
  default = 8080
}

variable "prometheus_port" {
  type    = number
  default = 9090
}

variable "grafana_port" {
  type    = number
  default = 3000
}
