provider "aws" {
  region     = "${var.aws_region}"
  profile    = "${var.aws_profile}"
  access_key = "${var.aws_access_key}"
  secret_key = "${var.aws_secret_key}"

  assume_role {
    role_arn = "${var.aws_assume_role}"
  }
}

data "aws_availability_zones" "available" {}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "1.65.0"
  name    = "${var.vpc_name}"
  cidr    = "${var.vpc_cidr}"
  azs     = ["${data.aws_availability_zones.available.names[0]}", "${data.aws_availability_zones.available.names[1]}"]

  private_subnets         = "${var.vpc_private_subnet_list}"
  public_subnets          = "${var.vpc_public_subnet_list}"
  enable_nat_gateway      = true
  single_nat_gateway      = true
  map_public_ip_on_launch = true

  enable_dhcp_options      = true
  enable_dns_hostnames     = true
  enable_dns_support       = true
  dhcp_options_domain_name = "${var.vpc_internal_domain_name}"

  dhcp_options_domain_name_servers = "${var.dns_server_list}"

  # Enable s3 vpc endpoint for private subnet
  enable_s3_endpoint = true

  secondary_cidr_blocks              = "${var.secondary_cidr_blocks}"
  create_redshift_subnet_group       = false
  create_elasticache_subnet_group    = false
  create_database_subnet_group       = false
  map_public_ip_on_launch            = false
  create_redshift_subnet_route_table = false
  create_database_subnet_route_table = false
}

resource "null_resource" "create_kubeconfig" {
  provisioner "local-exec" {
    command = "cd configs && export WORKER0_HOST=${aws_instance.worker0.private_dns} && export WORKER1_HOST=${aws_instance.worker1.private_dns} && export KUBERNETES_ADDRESS=${aws_instance.api_server.private_ip} && bash create_kubeconfig.sh"
  }

  depends_on = ["aws_instance.controller0", "aws_instance.controller1", "aws_instance.api_server", "aws_instance.worker0", "aws_instance.worker1"]
}

resource "null_resource" "configure_workers_controllers" {
  provisioner "local-exec" {
    command = "cd configs && export WORKER0_HOST=${aws_instance.worker0.private_dns} && export WORKER0_IP=${aws_instance.worker0.private_ip} && export WORKER1_HOST=${aws_instance.worker1.private_dns} && export WORKER1_IP=${aws_instance.worker1.private_ip} && export CERT_HOSTNAME=10.32.0.1,${aws_instance.controller1.public_dns},${aws_instance.controller1.private_ip},${aws_instance.controller1.private_ip},${aws_instance.controller1.public_dns},${aws_instance.api_server.private_ip},${aws_instance.api_server.public_dns},127.0.0.1,localhost,kubernetes.default && bash command.sh"
  }

  connection {
    host        = "${self.public_ip}"
    type        = "ssh"
    timeout     = "6m"
    user        = "ubuntu"
    private_key = "${file("~/.ssh/id_rsa")}"
  }

  provisioner "remote-exec" {
    inline = [
      "export ENVIRONMENT=BLAH",
      "export CREATEDBY=BLAH",
    ]
  }

  lifecycle {
    ignore_changes = ["*"]
  }

  depends_on = ["aws_instance.controller0", "aws_instance.controller1", "aws_instance.api_server", "aws_instance.worker0", "aws_instance.worker1"]
}

resource "null_resource" "etcd0" {
  connection {
    host        = "${aws_instance.controller0.public_ip}"
    type        = "ssh"
    timeout     = "6m"
    user        = "ubuntu"
    private_key = "${file("~/.ssh/id_rsa")}"
  }

  provisioner "local-exec" {
    command = "ETCD_NAME=${aws_instance.controller0.private_dns} && INTERNAL_IP=${aws_instance.controller0.private_ip} && INITIAL_CLUSTER=${aws_instance.controller0.private_dns}=https://${aws_instance.controller0.private_ip}:2380,${aws_instance.controller1.private_dns}=https://${aws_instance.controller1.private_ip}:2380 && cd configs && envsubst '$${ETCD_NAME} $${INTERNAL_IP}' < etcd-service > etcd.service-0"
  }

  provisioner "file" {
    source      = "configs/etcd.service-0"
    destination = "/etc/systemd/system/etcd.service"
  }

  provisioner "remote-exec" {
    inline = ["sudo systemctl daemon-reload",
      "sudo systemctl enable etcd",
      "sudo systemctl start etcd",
    ]
  }

  depends_on = ["aws_instance.controller0", "aws_instance.controller1", "aws_instance.api_server"]
}

resource "null_resource" "etcd1" {
  connection {
    host        = "${aws_instance.controller1.public_ip}"
    type        = "ssh"
    timeout     = "6m"
    user        = "ubuntu"
    private_key = "${file("~/.ssh/id_rsa")}"
  }

  provisioner "local-exec" {
    command = "ETCD_NAME=${aws_instance.controller1.private_dns} && INTERNAL_IP=${aws_instance.controller1.private_ip} && INITIAL_CLUSTER=${aws_instance.controller0.private_dns}=https://${aws_instance.controller0.private_ip}:2380,${aws_instance.controller1.private_dns}=https://${aws_instance.controller1.private_ip}:2380 && cd configs && envsubst '$${ETCD_NAME} $${INTERNAL_IP}' < etcd-service > etcd.service-1"
  }

  provisioner "file" {
    source      = "configs/etcd.service-1"
    destination = "/etc/systemd/system/etcd.service"
  }

  provisioner "remote-exec" {
    inline = ["sudo systemctl daemon-reload",
      "sudo systemctl enable etcd",
      "sudo systemctl start etcd",
    ]
  }

  depends_on = ["aws_instance.controller0", "aws_instance.controller1", "aws_instance.api_server"]
}

resource "aws_instance" "controller0" {
  # Amazon optimized EKS AMI
  ami           = "ami-0cfee17793b08a293"
  count         = 1
  subnet_id     = "${module.vpc.public_subnets[0]}"
  instance_type = "t2.large"

  # iam_instance_profile = "${var.bastion_instance_profile_name}"
  key_name = "${aws_key_pair.main.id}"

  associate_public_ip_address = "true"

  vpc_security_group_ids = ["${aws_security_group.cluster_security_group.id}", "${aws_security_group.all_worker_mgmt.id}", "${aws_security_group.allow_bootstrap_access.id}"]

  root_block_device {
    volume_type           = "gp2"
    volume_size           = "35"
    delete_on_termination = true
  }

  connection {
    host        = "${self.public_ip}"
    type        = "ssh"
    timeout     = "6m"
    user        = "ubuntu"
    private_key = "${file("~/.ssh/id_rsa")}"
  }

  provisioner "local-exec" {
    command = "ENCRYPTION_KEY=$(head -c 32 /dev/urandom | base64) && cd configs && envsubst $${ENCRYPTION_KEY} < encryption-config.yaml > encryption-config-0.yaml"
  }

  provisioner "file" {
    source      = "configs/encryption-config-0.yaml"
    destination = "/home/ubuntu/encryption-config.yaml"
  }

  provisioner "remote-exec" {
    inline = [
      "wget https://github.com/coreos/etcd/releases/download/v3.3.5/etcd-v3.3.5-linux-amd64.tar.gz",
      "tar -xvf etcd-v3.3.5-linux-amd64.tar.gz",
      "sudo mv etcd-v3.3.5-linux-amd64/etcd* /usr/local/bin/",
      "sudo mkdir -p /etc/etcd /var/lib/etcd",
      "sudo cp ca.pem kubernetes-key.pem kubernetes.pem /etc/etcd/",
      "export ENVIRONMENT=BLAH",
      "export CREATEDBY=BLAH",
    ]
  }

  lifecycle {
    ignore_changes = ["*"]
  }

  depends_on = ["aws_security_group.allow_bootstrap_access", "aws_key_pair.main"]
}

resource "aws_instance" "controller1" {
  # Amazon optimized EKS AMI
  ami           = "ami-0cfee17793b08a293"
  count         = 1
  subnet_id     = "${module.vpc.public_subnets[0]}"
  instance_type = "t2.large"

  # iam_instance_profile = "${var.bastion_instance_profile_name}"
  key_name = "${aws_key_pair.main.id}"

  associate_public_ip_address = "true"

  vpc_security_group_ids = ["${aws_security_group.cluster_security_group.id}", "${aws_security_group.all_worker_mgmt.id}", "${aws_security_group.allow_bootstrap_access.id}"]

  root_block_device {
    volume_type           = "gp2"
    volume_size           = "35"
    delete_on_termination = true
  }

  connection {
    host        = "${self.public_ip}"
    type        = "ssh"
    timeout     = "6m"
    user        = "ubuntu"
    private_key = "${file("~/.ssh/id_rsa")}"
  }

  provisioner "local-exec" {
    command = "ENCRYPTION_KEY=$(head -c 32 /dev/urandom | base64) && cd configs && envsubst $${ENCRYPTION_KEY} < encryption-config.yaml > encryption-config-1.yaml"
  }

  provisioner "file" {
    source      = "configs/encryption-config-1.yaml"
    destination = "/home/ubuntu/encryption-config.yaml"
  }

  provisioner "remote-exec" {
    inline = [
      "wget https://github.com/coreos/etcd/releases/download/v3.3.5/etcd-v3.3.5-linux-amd64.tar.gz",
      "tar -xvf etcd-v3.3.5-linux-amd64.tar.gz",
      "sudo mv etcd-v3.3.5-linux-amd64/etcd* /usr/local/bin/",
      "sudo mkdir -p /etc/etcd /var/lib/etcd",
      "sudo cp ca.pem kubernetes-key.pem kubernetes.pem /etc/etcd/",
      "export ENVIRONMENT=BLAH",
      "export CREATEDBY=BLAH",
    ]
  }

  lifecycle {
    ignore_changes = ["*"]
  }

  depends_on = ["aws_security_group.allow_bootstrap_access", "aws_key_pair.main"]
}

resource "aws_instance" "api_server" {
  # Amazon optimized EKS AMI
  ami           = "ami-0cfee17793b08a293"
  count         = 1
  subnet_id     = "${module.vpc.public_subnets[0]}"
  instance_type = "t2.large"

  # iam_instance_profile = "${var.bastion_instance_profile_name}"
  key_name = "${aws_key_pair.main.id}"

  associate_public_ip_address = "true"

  vpc_security_group_ids = ["${aws_security_group.cluster_security_group.id}", "${aws_security_group.all_worker_mgmt.id}", "${aws_security_group.allow_bootstrap_access.id}"]

  root_block_device {
    volume_type           = "gp2"
    volume_size           = "35"
    delete_on_termination = true
  }

  connection {
    host        = "${self.public_ip}"
    type        = "ssh"
    timeout     = "6m"
    user        = "ubuntu"
    private_key = "${file("~/.ssh/id_rsa")}"
  }

  provisioner "remote-exec" {
    inline = [
      "export ENVIRONMENT=BLAH",
      "export CREATEDBY=BLAH",
    ]
  }

  lifecycle {
    ignore_changes = ["*"]
  }

  depends_on = ["aws_security_group.allow_bootstrap_access", "aws_key_pair.main"]
}

resource "aws_security_group" "all_worker_mgmt" {
  name_prefix = "all_worker_management"
  vpc_id      = "${module.vpc.vpc_id}"

  ingress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"

    cidr_blocks = [
      "10.0.0.0/16",
    ]
  }
}

resource "aws_security_group" "cluster_security_group" {
  name   = "Test Kubernetes Cluster Security Group"
  vpc_id = "${module.vpc.vpc_id}"

  ingress {
    from_port = 443
    to_port   = 443
    protocol  = "tcp"
    self      = "true"
  }

  ingress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    self      = "true"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_key_pair" "main" {
  key_name   = "main"
  public_key = "${file("~/.ssh/id_rsa.pub")}"
}

data "http" "terraform_host_private_ip" {
  url = "http://169.254.169.254/latest/meta-data/local-ipv4"
}

data "http" "terraform_host_public_ip" {
  url = "http://ipecho.net/plain"
}

data "aws_vpc" "current_vpc" {
  id = "${module.vpc.vpc_id}"
}

resource "aws_security_group" "allow_bootstrap_access" {
  name        = "allow_bastion-access"
  description = "Allow all inbound traffic from bootstrap"
  vpc_id      = "${module.vpc.vpc_id}"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["${data.aws_vpc.current_vpc.cidr_block}", "${trimspace(data.http.terraform_host_public_ip.body)}/32"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "worker0" {
  ami           = "ami-0cfee17793b08a293"
  count         = 1
  subnet_id     = "${module.vpc.private_subnets[0]}"
  instance_type = "t2.large"

  # iam_instance_profile = "${var.bastion_instance_profile_name}"
  key_name = "${aws_key_pair.main.id}"

  associate_public_ip_address = "false"
  vpc_security_group_ids      = ["${aws_security_group.cluster_security_group.id}", "${aws_security_group.all_worker_mgmt.id}", "${aws_security_group.allow_bootstrap_access.id}"]

  root_block_device {
    volume_type           = "gp2"
    volume_size           = "35"
    delete_on_termination = true
  }

  depends_on = ["aws_security_group.allow_bootstrap_access", "aws_key_pair.main"]
}

resource "aws_instance" "worker1" {
  ami           = "ami-0cfee17793b08a293"
  count         = 1
  subnet_id     = "${module.vpc.private_subnets[1]}"
  instance_type = "t2.large"

  # iam_instance_profile = "${var.bastion_instance_profile_name}"
  key_name = "${aws_key_pair.main.id}"

  associate_public_ip_address = "false"
  vpc_security_group_ids      = ["${aws_security_group.cluster_security_group.id}", "${aws_security_group.all_worker_mgmt.id}", "${aws_security_group.allow_bootstrap_access.id}"]

  root_block_device {
    volume_type           = "gp2"
    volume_size           = "35"
    delete_on_termination = true
  }

  depends_on = ["aws_security_group.allow_bootstrap_access", "aws_key_pair.main"]
}
