# Only secret metadata is Terraform-managed; values must never enter state.
resource "aws_secretsmanager_secret" "db" {
  name = "${var.project_name}/${var.environment}/db"
  description = "Floci PostgreSQL credentials"
}
