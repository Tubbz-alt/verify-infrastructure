# frontend
#
# needs to connect to:
#   - config
#   - saml proxy
#   - policy
#
# frontend applications are run on the ingress asg

resource "aws_security_group" "frontend_task" {
  name        = "${var.deployment}-frontend-task"
  description = "${var.deployment}-frontend-task"

  vpc_id = "${aws_vpc.hub.id}"
}

data "template_file" "frontend_task_def" {
  template = "${file("${path.module}/files/tasks/frontend.json")}"

  vars {
    account_id    = "${data.aws_caller_identity.account.account_id}"
    deployment    = "${var.deployment}"
    image_and_tag = "${local.tools_account_ecr_url_prefix}-verify-frontend:latest"
    domain        = "${local.root_domain}"
    region        = "${data.aws_region.region.id}"
  }
}

module "frontend_ecs_roles" {
  source = "modules/ecs_iam_role_pair"

  deployment       = "${var.deployment}"
  tools_account_id = "${var.tools_account_id}"
  service_name     = "frontend"
  image_name       = "verify-frontend"
}

resource "aws_ecs_task_definition" "frontend" {
  family                = "${var.deployment}-frontend"
  container_definitions = "${data.template_file.frontend_task_def.rendered}"
  network_mode          = "awsvpc"
  execution_role_arn    = "${module.frontend_ecs_roles.execution_role_arn}"
}

resource "aws_ecs_service" "frontend" {
  name            = "${var.deployment}-frontend"
  cluster         = "${aws_ecs_cluster.ingress.id}"
  task_definition = "${aws_ecs_task_definition.frontend.arn}"
  desired_count   = 1

  load_balancer {
    target_group_arn = "${aws_lb_target_group.ingress_frontend.arn}"
    container_name   = "frontend"
    container_port   = "8080"
  }

  network_configuration {
    subnets         = ["${aws_subnet.internal.*.id}"]
    security_groups = ["${aws_security_group.frontend_task.id}"]
  }
}

module "frontend_can_connect_to_config" {
  source = "modules/microservice_connection"

  source_sg_id      = "${aws_security_group.frontend_task.id}"
  destination_sg_id = "${module.config.lb_sg_id}"
}

module "frontend_can_connect_to_policy" {
  source = "modules/microservice_connection"

  source_sg_id      = "${aws_security_group.frontend_task.id}"
  destination_sg_id = "${module.policy.lb_sg_id}"
}

module "frontend_can_connect_to_saml_proxy" {
  source = "modules/microservice_connection"

  source_sg_id      = "${aws_security_group.frontend_task.id}"
  destination_sg_id = "${module.saml_proxy.lb_sg_id}"
}

resource "random_string" "frontend_secret_key_base" {
  length  = 64
  special = false
}

resource "aws_ssm_parameter" "frontend_secret_key_base" {
  name   = "/${var.deployment}/frontend/secret-key-base"
  type   = "SecureString"
  key_id = "${aws_kms_key.frontend.key_id}"
  value  = "${random_string.frontend_secret_key_base.result}"
}

resource "aws_iam_policy" "frontend_parameter_execution" {
  name = "${var.deployment}-frontend-parameter-execution"

  policy = <<-EOF
  {
    "Version": "2012-10-17",
    "Statement": [{
      "Effect": "Allow",
      "Action": [
        "ssm:GetParameters",
        "kms:Decrypt"
      ],
      "Resource": [
        "arn:aws:ssm:${data.aws_region.region.id}:${data.aws_caller_identity.account.account_id}:parameter/${var.deployment}/frontend/*",
        "arn:aws:kms:${data.aws_region.region.id}:${data.aws_caller_identity.account.account_id}:alias/${var.deployment}-frontend"
      ]
    }]
  }
  EOF
}

resource "aws_iam_role_policy_attachment" "frontend_parameter_execution" {
  role       = "${var.deployment}-frontend-execution"
  policy_arn = "${aws_iam_policy.frontend_parameter_execution.arn}"
}
