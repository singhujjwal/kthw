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
  enable_nat_gateway      = false
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

resource "aws_instance" "master" {
  # Amazon optimized EKS AMI
  ami           = "ami-08e2b16807644cf1d"
  count         = 1
  subnet_id     = "${module.vpc.public_subnets[0]}"
  instance_type = "t2.large"

  # iam_instance_profile = "${var.bastion_instance_profile_name}"
  key_name = "${aws_key_pair.main.id}"

  associate_public_ip_address = "true"

  vpc_security_group_ids = ["${aws_security_group.cluster_security_group.id}", "${aws_security_group.all_worker_mgmt.id}", "${aws_security_group.allow_bootstrap_access.id}"]

  root_block_device {
    volume_type           = "gp2"
    volume_size           = "60"
    delete_on_termination = true
  }

  connection {
    host        = "${self.public_ip}"
    type        = "ssh"
    timeout     = "6m"
    user        = "centos"
    private_key = "${file("~/.ssh/id_rsa")}"
  }

  provisioner "file" {
    source      = "configs/kubernetes.repo"
    destination = "/home/centos/kubernetes.repo"
  }

  provisioner "file" {
    source      = "configs/k8s.conf"
    destination = "/home/centos/k8s.conf"
  }

  provisioner "remote-exec" {
    inline = ["sudo swapoff -a",
      "sudo cp kubernetes.repo /etc/yum.repos.d/kubernetes.repo",
      "sudo yum install -y kubelet kubeadm kubectl",
      "sudo systemctl enable kubelet",
      "sudo systemctl start kubelet",
      "sudo cp k8s.conf /etc/sysctl.d/k8s.conf",
      "sudo sysctl --system",
      "sudo kubeadm init --pod-network-cidr=10.244.0.0/16",
      "mkdir -p $HOME/.kube",
      "sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config",
      "sudo chown $(id -u):$(id -g) $HOME/.kube/config",
      "kubectl apply -f https://raw.githubusercontent.com/coreos/flannel/bc79dd1505b0c8681ece4de4c0d86c5cd2643275/Documentation/kube-flannel.yml",
    ]
  }

  depends_on = ["aws_security_group.allow_bootstrap_access", "aws_key_pair.main"]
}

resource "aws_instance" "worker0" {
  # Amazon optimized EKS AMI
  ami           = "ami-08e2b16807644cf1d"
  count         = 1
  subnet_id     = "${module.vpc.public_subnets[0]}"
  instance_type = "t2.large"

  # iam_instance_profile = "${var.bastion_instance_profile_name}"
  key_name = "${aws_key_pair.main.id}"

  associate_public_ip_address = "true"

  vpc_security_group_ids = ["${aws_security_group.cluster_security_group.id}", "${aws_security_group.all_worker_mgmt.id}", "${aws_security_group.allow_bootstrap_access.id}"]

  root_block_device {
    volume_type           = "gp2"
    volume_size           = "60"
    delete_on_termination = true
  }

  connection {
    host        = "${self.public_ip}"
    type        = "ssh"
    timeout     = "6m"
    user        = "centos"
    private_key = "${file("~/.ssh/id_rsa")}"
  }

  provisioner "file" {
    source      = "configs/kubernetes.repo"
    destination = "/home/centos/kubernetes.repo"
  }

  provisioner "file" {
    source      = "configs/k8s.conf"
    destination = "/home/centos/k8s.conf"
  }

  provisioner "remote-exec" {
    inline = ["sudo swapoff -a",
      "sudo cp kubernetes.repo /etc/yum.repos.d/kubernetes.repo",
      "sudo yum install -y kubelet kubeadm kubectl",
      "sudo systemctl enable kubelet",
      "sudo systemctl start kubelet",
      "sudo cp k8s.conf /etc/sysctl.d/k8s.conf",
      "sudo sysctl --system",
    ]
  }

  lifecycle {
    ignore_changes = ["*"]
  }

  depends_on = ["aws_security_group.allow_bootstrap_access", "aws_key_pair.main"]
}

resource "aws_instance" "worker1" {
  # Amazon optimized EKS AMI
  ami           = "ami-08e2b16807644cf1d"
  count         = 1
  subnet_id     = "${module.vpc.public_subnets[0]}"
  instance_type = "t2.large"

  # iam_instance_profile = "${var.bastion_instance_profile_name}"
  key_name = "${aws_key_pair.main.id}"

  associate_public_ip_address = "true"

  vpc_security_group_ids = ["${aws_security_group.cluster_security_group.id}", "${aws_security_group.all_worker_mgmt.id}", "${aws_security_group.allow_bootstrap_access.id}"]

  root_block_device {
    volume_type           = "gp2"
    volume_size           = "60"
    delete_on_termination = true
  }

  connection {
    host        = "${self.public_ip}"
    type        = "ssh"
    timeout     = "6m"
    user        = "centos"
    private_key = "${file("~/.ssh/id_rsa")}"
  }

  provisioner "file" {
    source      = "configs/kubernetes.repo"
    destination = "/home/centos/kubernetes.repo"
  }

  provisioner "file" {
    source      = "configs/k8s.conf"
    destination = "/home/centos/k8s.conf"
  }

  provisioner "remote-exec" {
    inline = ["sudo swapoff -a",
      "sudo cp kubernetes.repo /etc/yum.repos.d/kubernetes.repo",
      "sudo yum install -y kubelet kubeadm kubectl",
      "sudo systemctl enable kubelet",
      "sudo systemctl start kubelet",
      "sudo cp k8s.conf /etc/sysctl.d/k8s.conf",
      "sudo sysctl --system",
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

resource "null_resource" "run_kubeadm" {
  provisioner "remote-exec" {
    inline = ["sudo kubeadm token create --print-join-command > command.txt"]

    connection {
      host        = "${aws_instance.master.public_ip}"
      type        = "ssh"
      timeout     = "6m"
      user        = "centos"
      private_key = "${file("~/.ssh/id_rsa")}"
    }
  }

  provisioner "local-exec" {
    command = "scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null  centos@${aws_instance.master.public_ip}:~/command.txt ."
  }

  provisioner "file" {
    source      = "command.txt"
    destination = "command.txt"

    connection {
      host        = "${aws_instance.worker0.public_ip}"
      type        = "ssh"
      timeout     = "6m"
      user        = "centos"
      private_key = "${file("~/.ssh/id_rsa")}"
    }
  }

  provisioner "remote-exec" {
    inline = ["sudo $(cat command.txt) --ignore-preflight-errors=All"]

    connection {
      host        = "${aws_instance.worker0.public_ip}"
      type        = "ssh"
      timeout     = "6m"
      user        = "centos"
      private_key = "${file("~/.ssh/id_rsa")}"
    }
  }

  provisioner "file" {
    source      = "command.txt"
    destination = "command.txt"

    connection {
      host        = "${aws_instance.worker1.public_ip}"
      type        = "ssh"
      timeout     = "6m"
      user        = "centos"
      private_key = "${file("~/.ssh/id_rsa")}"
    }
  }

  provisioner "remote-exec" {
    inline = ["sudo $(cat command.txt) --ignore-preflight-errors=All"]

    connection {
      host        = "${aws_instance.worker0.public_ip}"
      type        = "ssh"
      timeout     = "6m"
      user        = "centos"
      private_key = "${file("~/.ssh/id_rsa")}"
    }
  }
}
