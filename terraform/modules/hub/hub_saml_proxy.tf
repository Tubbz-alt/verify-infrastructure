module "saml_proxy_ecs_asg" {
  source = "modules/ecs_asg"

  ami_id              = "${data.aws_ami.awslinux2.id}"
  deployment          = "${var.deployment}"
  cluster             = "saml-proxy"
  vpc_id              = "${aws_vpc.hub.id}"
  instance_subnets    = ["${aws_subnet.internal.*.id}"]
  number_of_instances = "${var.number_of_availability_zones}"
  domain              = "${var.domain}"

  additional_instance_security_group_ids = [
    "${aws_security_group.egress_via_proxy.id}",
  ]
}

data "template_file" "saml_proxy_task_def" {
  template = "${file("${path.module}/files/tasks/hub-saml-proxy.json")}"

  vars {
    image_and_tag = "${local.tools_account_ecr_url_prefix}-verify-saml-proxy:latest"
    domain        = "${var.domain}"
    deployment    = "${var.deployment}"
  }
}

module "saml_proxy" {
  source = "modules/ecs_app"

  deployment                 = "${var.deployment}"
  cluster                    = "saml-proxy"
  domain                     = "${var.domain}"
  vpc_id                     = "${aws_vpc.hub.id}"
  lb_subnets                 = ["${aws_subnet.internal.*.id}"]
  task_definition            = "${data.template_file.saml_proxy_task_def.rendered}"
  container_name             = "saml-proxy"
  container_port             = "8080"
  number_of_tasks            = 1
  health_check_protocol      = "HTTP"
  tools_account_id           = "${var.tools_account_id}"
  instance_security_group_id = "${module.saml_proxy_ecs_asg.instance_sg_id}"
  certificate_arn            = "${data.aws_acm_certificate.wildcard.arn}"
  image_name                 = "verify-saml-proxy"
}
