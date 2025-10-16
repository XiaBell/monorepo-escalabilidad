data "aws_iam_role" "existing_execution_role" {
  # Reutiliza un rol existente permitido en Voclabs. "LabRole" suele estar disponible.
  # Si tu entorno usa otro nombre (p.ej. "ecsTaskExecutionRole"), cámbialo aquí.
  name = "LabRole"
}
