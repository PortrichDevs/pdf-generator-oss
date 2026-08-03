variable "function_name" {}
variable "repository_url" {}

resource "aws_iam_role" "this" {
  assume_role_policy = file("${path.module}/assume_policy.json")
}

resource "aws_iam_role_policy_attachment" "this" {
  role       = aws_iam_role.this.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_lambda_function" "this" {
  function_name = var.function_name
  role          = aws_iam_role.this.arn
  package_type  = "Image"
  image_uri     = "${var.repository_url}:latest"

  timeout     = 60
  memory_size = 1536

  # image_uri は CI (ecr-lambda.yml) が digest 指定で更新するため Terraform では追随しない
  lifecycle {
    ignore_changes = [image_uri]
  }
}

output "invoke_arn" {
  value = aws_lambda_function.this.invoke_arn
}
