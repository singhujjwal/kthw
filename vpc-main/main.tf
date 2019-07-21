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

resource "null_resource" "create_cert_and_kubeconfig" {
  provisioner "local-exec" {
    command = "cd configs && export WORKER0_HOST=${aws_instance.worker0.private_dns} && export WORKER1_HOST=${aws_instance.worker1.private_dns} && export KUBERNETES_ADDRESS=${aws_instance.api_server.private_ip} && bash create_kubeconfig.sh"
  }

  provisioner "local-exec" {
    command = "cd configs && export WORKER0_HOST=${aws_instance.worker0.private_dns} && export WORKER0_IP=${aws_instance.worker0.private_ip} && export WORKER1_HOST=${aws_instance.worker1.private_dns} && export WORKER1_IP=${aws_instance.worker1.private_ip} && export CERT_HOSTNAME=10.32.0.1,${aws_instance.controller1.public_dns},${aws_instance.controller1.private_ip},${aws_instance.controller1.private_ip},${aws_instance.controller1.public_dns},${aws_instance.api_server.private_ip},${aws_instance.api_server.public_dns},127.0.0.1,localhost,kubernetes.default && bash command.sh"
  }

  depends_on = ["aws_instance.controller0", "aws_instance.controller1", "aws_instance.api_server", "aws_instance.worker0", "aws_instance.worker1"]
}

resource "null_resource" "setup_controller0" {
  connection {
    host        = "${aws_instance.controller0.public_ip}"
    type        = "ssh"
    timeout     = "6m"
    user        = "ubuntu"
    private_key = "${file("~/.ssh/id_rsa")}"
  }

  provisioner "file" {
    source      = "configs/ca.pem"
    destination = "/home/ubuntu/ca.pem"
  }

  provisioner "file" {
    source      = "configs/ca-key.pem"
    destination = "/home/ubuntu/ca-key.pem"
  }

  provisioner "file" {
    source      = "configs/kubernetes-key.pem"
    destination = "/home/ubuntu/kubernetes-key.pem"
  }

  provisioner "file" {
    source      = "configs/kubernetes.pem"
    destination = "/home/ubuntu/kubernetes.pem"
  }

  provisioner "file" {
    source      = "configs/service-account-key.pem"
    destination = "/home/service-account-key.pem"
  }

  provisioner "file" {
    source      = "configs/service-account.pem"
    destination = "/home/service-account.pem"
  }

  provisioner "file" {
    source      = "configs/admin.kubeconfig"
    destination = "/home/ubuntu/admin.kubeconfig"
  }

  provisioner "file" {
    source      = "configs/kube-controller-manager.kubeconfig"
    destination = "/home/ubuntu/kube-controller-manager.kubeconfig"
  }

  provisioner "file" {
    source      = "configs/kube-scheduler.kubeconfig"
    destination = "/home/ubuntu/kube-scheduler.kubeconfig"
  }

  provisioner "local-exec" {
    command = "ENCRYPTION_KEY=$(head -c 32 /dev/urandom | base64) && cd configs && envsubst $${ENCRYPTION_KEY} < encryption-config.yaml > encryption-config-0.yaml"
  }

  provisioner "file" {
    source      = "configs/encryption-config-0.yaml"
    destination = "/home/ubuntu/encryption-config.yaml"
  }

  provisioner "local-exec" {
    command = "ETCD_NAME=${aws_instance.controller0.private_dns} && INTERNAL_IP=${aws_instance.controller0.private_ip} && INITIAL_CLUSTER=${aws_instance.controller0.private_dns}=https://${aws_instance.controller0.private_ip}:2380,${aws_instance.controller1.private_dns}=https://${aws_instance.controller1.private_ip}:2380 && cd configs && envsubst '$${ETCD_NAME} $${INTERNAL_IP}' < etcd-service > etcd.service-0"
  }

  provisioner "file" {
    source      = "configs/etcd.service-0"
    destination = "/home/ubuntu/etcd.service"
  }

  provisioner "file" {
    source      = "configs/kube-controller-manager.service"
    destination = "/home/ubuntu/kube-controller-manager.service"
  }

  provisioner "file" {
    source      = "configs/kube-scheduler.yaml"
    destination = "/home/ubuntu/kube-scheduler.yaml"
  }

  provisioner "file" {
    source      = "configs/kube-scheduler.service"
    destination = "/home/ubuntu/kube-scheduler.service"
  }
  provisioner "file" {
    source      = "configs/kubernetes.default.svc.cluster.local"
    destination = "/home/ubuntu/kubernetes.default.svc.cluster.local"
  }

  provisioner "file" {
    source      = "configs/rbac.yaml"
    destination = "/home/ubuntu/rbac.yaml"
  }

    provisioner "file" {
    source      = "configs/user-rbac.yaml"
    destination = "/home/ubuntu/user-rbac.yaml"
  }


  provisioner "remote-exec" {
    inline = [
      "wget https://github.com/coreos/etcd/releases/download/v3.3.5/etcd-v3.3.5-linux-amd64.tar.gz",
      "tar -xvf etcd-v3.3.5-linux-amd64.tar.gz",
      "sudo mv etcd-v3.3.5-linux-amd64/etcd* /usr/local/bin/",
      "sudo mkdir -p /etc/etcd /var/lib/etcd /etc/systemd/system/",
      "sudo cp etcd.service /etc/systemd/system/etcd.service",
      "sudo cp ca.pem kubernetes-key.pem kubernetes.pem /etc/etcd/",
      "sudo systemctl daemon-reload",
      "sudo systemctl enable etcd",
      "sudo systemctl start etcd",
      "sudo mkdir -p /etc/kubernetes/config",
      "wget https://storage.googleapis.com/kubernetes-release/release/v1.10.2/bin/linux/amd64/kube-apiserver",
      "wget https://storage.googleapis.com/kubernetes-release/release/v1.10.2/bin/linux/amd64/kube-controller-manager",
      "wget https://storage.googleapis.com/kubernetes-release/release/v1.10.2/bin/linux/amd64/kube-scheduler",
      "wget https://storage.googleapis.com/kubernetes-release/release/v1.10.2/bin/linux/amd64/kubectl",
      "chmod +x kube-apiserver kube-controller-manager kube-scheduler kubectl",
      "sudo mv kube-apiserver kube-controller-manager kube-scheduler kubectl /usr/local/bin/",
      "sudo cp kube-controller-manager.service /etc/systemd/system/kube-controller-manager.service",
      "sudo cp kube-scheduler.yaml /etc/kubernetes/config/kube-scheduler.yaml",
      "sudo cp kube-scheduler.yaml /etc/systemd/system/kube-scheduler.service",
      "sudo systemctl daemon-reload",
      "sudo systemctl enable kube-apiserver kube-controller-manager kube-scheduler",
      "sudo systemctl start kube-apiserver kube-controller-manager kube-scheduler",
      "sudo systemctl status kube-apiserver kube-controller-manager kube-scheduler",
      "kubectl get componentstatuses --kubeconfig admin.kubeconfig",
      "sudo apt-get install -y nginx",
      "sudo mv kubernetes.default.svc.cluster.local /etc/nginx/sites-available/kubernetes.default.svc.cluster.local",
      "sudo ln -s /etc/nginx/sites-available/kubernetes.default.svc.cluster.local /etc/nginx/sites-enabled/",
      "sudo systemctl restart nginx",
      "sudo systemctl enable nginx",
      "kubectl apply --kubeconfig admin.kubeconfig -f rbac.yaml",
      "kubectl apply --kubeconfig admin.kubeconfig -f user-rbac.yaml",
      "export ENVIRONMENT=BLAH",
      "export CREATEDBY=BLAH",
    ]
  }

  depends_on = ["null_resource.create_cert_and_kubeconfig"]
}

resource "null_resource" "setup_controller1" {
  connection {
    host        = "${aws_instance.controller1.public_ip}"
    type        = "ssh"
    timeout     = "6m"
    user        = "ubuntu"
    private_key = "${file("~/.ssh/id_rsa")}"
  }

  provisioner "file" {
    source      = "configs/ca.pem"
    destination = "/home/ubuntu/ca.pem"
  }

  provisioner "file" {
    source      = "configs/ca-key.pem"
    destination = "/home/ubuntu/ca-key.pem"
  }

  provisioner "file" {
    source      = "configs/kubernetes-key.pem"
    destination = "/home/ubuntu/kubernetes-key.pem"
  }

  provisioner "file" {
    source      = "configs/kubernetes.pem"
    destination = "/home/ubuntu/kubernetes.pem"
  }

  provisioner "file" {
    source      = "configs/service-account-key.pem"
    destination = "/home/service-account-key.pem"
  }

  provisioner "file" {
    source      = "configs/service-account.pem"
    destination = "/home/service-account.pem"
  }

  provisioner "file" {
    source      = "configs/admin.kubeconfig"
    destination = "/home/ubuntu/admin.kubeconfig"
  }

  provisioner "file" {
    source      = "configs/kube-controller-manager.kubeconfig"
    destination = "/home/ubuntu/kube-controller-manager.kubeconfig"
  }

  provisioner "file" {
    source      = "configs/kube-scheduler.kubeconfig"
    destination = "/home/ubuntu/kube-scheduler.kubeconfig"
  }

  provisioner "local-exec" {
    command = "ENCRYPTION_KEY=$(head -c 32 /dev/urandom | base64) && cd configs && envsubst $${ENCRYPTION_KEY} < encryption-config.yaml > encryption-config-1.yaml"
  }

  provisioner "file" {
    source      = "configs/encryption-config-1.yaml"
    destination = "/home/ubuntu/encryption-config.yaml"
  }

  provisioner "local-exec" {
    command = "ETCD_NAME=${aws_instance.controller1.private_dns} && INTERNAL_IP=${aws_instance.controller1.private_ip} && INITIAL_CLUSTER=${aws_instance.controller0.private_dns}=https://${aws_instance.controller0.private_ip}:2380,${aws_instance.controller1.private_dns}=https://${aws_instance.controller1.private_ip}:2380 && cd configs && envsubst '$${ETCD_NAME} $${INTERNAL_IP}' < etcd-service > etcd.service-1"
  }

  provisioner "file" {
    source      = "configs/etcd.service-1"
    destination = "/home/ubuntu/etcd.service"
  }

  provisioner "file" {
    source      = "configs/kube-controller-manager.service"
    destination = "/home/ubuntu/kube-controller-manager.service"
  }

  provisioner "file" {
    source      = "configs/kube-scheduler.yaml"
    destination = "/home/ubuntu/kube-scheduler.yaml"
  }

  provisioner "file" {
    source      = "configs/kube-scheduler.service"
    destination = "/home/ubuntu/kube-scheduler.service"
  }

    provisioner "file" {
    source      = "configs/kubernetes.default.svc.cluster.local"
    destination = "/home/ubuntu/kubernetes.default.svc.cluster.local"
  }

  provisioner "remote-exec" {
    inline = [
      "wget https://github.com/coreos/etcd/releases/download/v3.3.5/etcd-v3.3.5-linux-amd64.tar.gz",
      "tar -xvf etcd-v3.3.5-linux-amd64.tar.gz",
      "sudo mv etcd-v3.3.5-linux-amd64/etcd* /usr/local/bin/",
      "sudo mkdir -p /etc/etcd /var/lib/etcd /etc/systemd/system/",
      "sudo cp etcd.service /etc/systemd/system/etcd.service",
      "sudo cp ca.pem kubernetes-key.pem kubernetes.pem /etc/etcd/",
      "sudo systemctl daemon-reload",
      "sudo systemctl enable etcd",
      "sudo systemctl start etcd",
      "sudo mkdir -p /etc/kubernetes/config",
      "wget https://storage.googleapis.com/kubernetes-release/release/v1.10.2/bin/linux/amd64/kube-apiserver",
      "wget https://storage.googleapis.com/kubernetes-release/release/v1.10.2/bin/linux/amd64/kube-controller-manager",
      "wget https://storage.googleapis.com/kubernetes-release/release/v1.10.2/bin/linux/amd64/kube-scheduler",
      "wget https://storage.googleapis.com/kubernetes-release/release/v1.10.2/bin/linux/amd64/kubectl",
      "chmod +x kube-apiserver kube-controller-manager kube-scheduler kubectl",
      "sudo mv kube-apiserver kube-controller-manager kube-scheduler kubectl /usr/local/bin/",
      "sudo cp kube-controller-manager.service /etc/systemd/system/kube-controller-manager.service",
      "sudo cp kube-scheduler.yaml /etc/kubernetes/config/kube-scheduler.yaml",
      "sudo cp kube-scheduler.yaml /etc/systemd/system/kube-scheduler.service",
      "sudo systemctl daemon-reload",
      "sudo systemctl enable kube-apiserver kube-controller-manager kube-scheduler",
      "sudo systemctl start kube-apiserver kube-controller-manager kube-scheduler",
      "sudo systemctl status kube-apiserver kube-controller-manager kube-scheduler",
      "kubectl get componentstatuses --kubeconfig admin.kubeconfig",
          "sudo apt-get install -y nginx",
      "sudo mv kubernetes.default.svc.cluster.local /etc/nginx/sites-available/kubernetes.default.svc.cluster.local",
      "sudo ln -s /etc/nginx/sites-available/kubernetes.default.svc.cluster.local /etc/nginx/sites-enabled/",
      "sudo systemctl restart nginx",
      "sudo systemctl enable nginx",
      "export ENVIRONMENT=BLAH",
      "export CREATEDBY=BLAH",
    ]
  }

  depends_on = ["null_resource.create_cert_and_kubeconfig"]
}

resource "null_resource" "setup_apiserver" {
  connection {
    host        = "${aws_instance.api_server.public_ip}"
    type        = "ssh"
    timeout     = "6m"
    user        = "ubuntu"
    private_key = "${file("~/.ssh/id_rsa")}"
  }

  provisioner "file" {
    source      = "configs/ca.pem"
    destination = "/home/ubuntu/ca.pem"
  }

  provisioner "file" {
    source      = "configs/ca-key.pem"
    destination = "/home/ubuntu/ca-key.pem"
  }

  provisioner "file" {
    source      = "configs/kubernetes-key.pem"
    destination = "/home/ubuntu/kubernetes-key.pem"
  }

  provisioner "file" {
    source      = "configs/kubernetes.pem"
    destination = "/home/ubuntu/kubernetes.pem"
  }

  provisioner "file" {
    source      = "configs/service-account-key.pem"
    destination = "/home/service-account-key.pem"
  }

  provisioner "file" {
    source      = "configs/service-account.pem"
    destination = "/home/service-account.pem"
  }

  provisioner "file" {
    source      = "configs/admin.kubeconfig"
    destination = "/home/ubuntu/admin.kubeconfig"
  }

  provisioner "file" {
    source      = "configs/kube-controller-manager.kubeconfig"
    destination = "/home/ubuntu/kube-controller-manager.kubeconfig"
  }

  provisioner "file" {
    source      = "configs/kube-scheduler.kubeconfig"
    destination = "/home/ubuntu/kube-scheduler.kubeconfig"
  }

  provisioner "local-exec" {
    command = "ENCRYPTION_KEY=$(head -c 32 /dev/urandom | base64) && cd configs && envsubst $${ENCRYPTION_KEY} < encryption-config.yaml > encryption-config-apiserver.yaml"
  }

  provisioner "file" {
    source      = "configs/encryption-config-apiserver.yaml"
    destination = "/home/ubuntu/encryption-config.yaml"
  }

  provisioner "local-exec" {
    command = "INTERNAL_IP=$(curl http://169.254.169.254/latest/meta-data/local-ipv4) && CONTROLLER0_IP=${aws_instance.controller0.private_ip} && CONTROLLER1_IP=${aws_instance.controller1.private_ip} && cd configs && envsubst '$${INTERNAL_IP} $${CONTROLLER0_IP} $${CONTROLLER1_IP}' < kube-apiserver.service.template > kube-apiserver.service"
  }

  provisioner "file" {
    source      = "configs/kube-apiserver.service"
    destination = "/home/ubuntu/kube-apiserver.service"
  }

  provisioner "remote-exec" {
    inline = [
      "sudo mkdir -p /var/lib/kubernetes/",
      "sudo cp ca.pem ca-key.pem kubernetes-key.pem kubernetes.pem service-account-key.pem service-account.pem encryption-config.yaml /var/lib/kubernetes/",
      "sudo cp kube-apiserver.service /etc/systemd/system/kube-apiserver.service",
      "CONTROLLER0_IP=${aws_instance.controller0.private_ip}",
      "CONTROLLER1_IP=${aws_instance.controller1.private_ip}",
    ]
  }

  depends_on = ["null_resource.create_cert_and_kubeconfig"]
}

resource "null_resource" "setup_worker0" {
  connection {
    host        = "${aws_instance.worker0.public_ip}"
    type        = "ssh"
    timeout     = "6m"
    user        = "ubuntu"
    private_key = "${file("~/.ssh/id_rsa")}"
  }

  provisioner "file" {
    source      = "configs/ca-key.pem"
    destination = "/home/ubuntu/ca-key.pem"
  }

  provisioner "file" {
    source      = "configs/${aws_instance.worker0.private_dns}-key.pem"
    destination = "/home/ubuntu/${aws_instance.worker0.private_dns}-key.pem"
  }

  provisioner "file" {
    source      = "configs/${aws_instance.worker0.private_dns}.kubeconfig"
    destination = "/home/ubuntu/${aws_instance.worker0.private_dns}.kubeconfig"
  }

  provisioner "file" {
    source      = "configs/kube-proxy.kubeconfig"
    destination = "/home/ubuntu/kube-proxy.kubeconfig"
  }

  provisioner "file" {
    source      = "configs/kube-proxy.kubeconfig"
    destination = "/home/ubuntu/kube-proxy.kubeconfig"
  }

  provisioner "file" {
    source      = "configs/config.toml"
    destination = "/home/ubuntu/config.toml"
  }

   provisioner "local-exec" {
    command = "HOSTNAME=${aws_instance.worker0.private_dns} && cd configs && envsubst $${HOSTNAME} < kubelet-config.yaml > kubelet-config0.yaml"
  }

   provisioner "file" {
    source      = "configs/kubelet-config0.yaml"
    destination = "/home/ubuntu/kubelet-config.yaml"
  }

   provisioner "local-exec" {
    command = "HOSTNAME=${aws_instance.worker0.private_dns} && cd configs && envsubst $${HOSTNAME} < kubelet.service > kubelet.service0"
  }

   provisioner "file" {
    source      = "configs/kubelet.service0"
    destination = "/home/ubuntu/kubelet.service"
  }

   provisioner "file" {
    source      = "configs/kube-proxy-config.yaml"
    destination = "/home/ubuntu/kube-proxy-config.yaml"
  }

   provisioner "file" {
    source      = "configs/kube-proxy.service"
    destination = "/home/ubuntu/kube-proxy.service"
  }


  provisioner "remote-exec" {
    inline = [
      "sudo apt-get -y install socat conntrack ipset",
      "wget https://github.com/kubernetes-incubator/cri-tools/releases/download/v1.0.0-beta.0/crictl-v1.0.0-beta.0-linux-amd64.tar.gz",
      "wget https://storage.googleapis.com/kubernetes-the-hard-way/runsc",
      "wget https://github.com/opencontainers/runc/releases/download/v1.0.0-rc5/runc.amd64",
      "wget https://github.com/containernetworking/plugins/releases/download/v0.6.0/cni-plugins-amd64-v0.6.0.tgz",
      "wget https://github.com/containernetworking/plugins/releases/download/v0.6.0/cni-plugins-amd64-v0.6.0.tgz",
      "wget https://storage.googleapis.com/kubernetes-release/release/v1.10.2/bin/linux/amd64/kubectl",
      "wget https://storage.googleapis.com/kubernetes-release/release/v1.10.2/bin/linux/amd64/kube-proxy",
      "wget https://storage.googleapis.com/kubernetes-release/release/v1.10.2/bin/linux/amd64/kubelet",
      "sudo mkdir -p /etc/cni/net.d  /opt/cni/bin /var/lib/kubelet /var/lib/kube-proxy /var/lib/kubernetes /var/run/kubernetes",
      "chmod +x kubectl kube-proxy kubelet runc.amd64 runsc",
      "sudo mv runc.amd64 runc",
      "sudo mv kubectl kube-proxy kubelet runc runsc /usr/local/bin/",
      "sudo tar -xvf crictl-v1.0.0-beta.0-linux-amd64.tar.gz -C /usr/local/bin/",
      "sudo tar -xvf cni-plugins-amd64-v0.6.0.tgz -C /opt/cni/bin/",
      "sudo tar -xvf containerd-1.1.0.linux-amd64.tar.gz -C /",
      "sudo mkdir -p /etc/containerd/",
      "sudo cp config.toml /etc/containerd/config.toml",
      "sudo cp containerd.service /etc/systemd/system/containerd.service"
      "sudo mv ${aws_instance.worker0.private_dns}-key.pem /var/lib/kubelet/${aws_instance.worker0.private_dns}.pem",
      "sudo mv ${aws_instance.worker0.private_dns}.kubeconfig /var/lib/kubelet/kubeconfig",
      "sudo mv ca.pem /var/lib/kubernetes/",
      "sudo cp kubelet-config.yaml /var/lib/kubelet/kubelet-config.yaml",
      "sudo cp kubelet.service /etc/systemd/system/kubelet.service",
      "sudo mv kube-proxy.kubeconfig /var/lib/kube-proxy/kubeconfig",
      "sudo cp kube-proxy-config.yaml /var/lib/kube-proxy/kube-proxy-config.yaml",
      "sudo cp kube-proxy.service /etc/systemd/system/kube-proxy.service",
      "sudo systemctl daemon-reload",
      "sudo systemctl enable containerd kubelet kube-proxy",
      "sudo systemctl start containerd kubelet kube-proxy",
      "sudo systemctl status containerd kubelet kube-proxy"
    ]
  }

  depends_on = ["null_resource.create_cert_and_kubeconfig"]
}

resource "null_resource" "setup_worker1" {
  connection {
    host        = "${aws_instance.worker1.public_ip}"
    type        = "ssh"
    timeout     = "6m"
    user        = "ubuntu"
    private_key = "${file("~/.ssh/id_rsa")}"
  }

  provisioner "file" {
    source      = "configs/ca-key.pem"
    destination = "/home/ubuntu/ca-key.pem"
  }

  provisioner "file" {
    source      = "configs/${aws_instance.worker1.private_dns}-key.pem"
    destination = "/home/ubuntu/${aws_instance.worker1.private_dns}-key.pem"
  }

  provisioner "file" {
    source      = "configs/${aws_instance.worker1.private_dns}.kubeconfig"
    destination = "/home/ubuntu/${aws_instance.worker1.private_dns}.kubeconfig"
  }

  provisioner "file" {
    source      = "configs/kube-proxy.kubeconfig"
    destination = "/home/ubuntu/kube-proxy.kubeconfig"
  }

  provisioner "file" {
    source      = "configs/kube-proxy.kubeconfig"
    destination = "/home/ubuntu/kube-proxy.kubeconfig"
  }

   provisioner "remote-exec" {
    inline = [
      "sudo apt-get -y install socat conntrack ipset",
      "wget https://github.com/kubernetes-incubator/cri-tools/releases/download/v1.0.0-beta.0/crictl-v1.0.0-beta.0-linux-amd64.tar.gz",
      "wget https://storage.googleapis.com/kubernetes-the-hard-way/runsc",
      "wget https://github.com/opencontainers/runc/releases/download/v1.0.0-rc5/runc.amd64",
      "wget https://github.com/containernetworking/plugins/releases/download/v0.6.0/cni-plugins-amd64-v0.6.0.tgz",
      "wget https://github.com/containernetworking/plugins/releases/download/v0.6.0/cni-plugins-amd64-v0.6.0.tgz",
      "wget https://storage.googleapis.com/kubernetes-release/release/v1.10.2/bin/linux/amd64/kubectl",
      "wget https://storage.googleapis.com/kubernetes-release/release/v1.10.2/bin/linux/amd64/kube-proxy",
      "wget https://storage.googleapis.com/kubernetes-release/release/v1.10.2/bin/linux/amd64/kubelet",
      "sudo mkdir -p /etc/cni/net.d  /opt/cni/bin /var/lib/kubelet /var/lib/kube-proxy /var/lib/kubernetes /var/run/kubernetes",
      "chmod +x kubectl kube-proxy kubelet runc.amd64 runsc",
      "sudo mv runc.amd64 runc",
      "sudo mv kubectl kube-proxy kubelet runc runsc /usr/local/bin/",
      "sudo tar -xvf crictl-v1.0.0-beta.0-linux-amd64.tar.gz -C /usr/local/bin/",
      "sudo tar -xvf cni-plugins-amd64-v0.6.0.tgz -C /opt/cni/bin/",
      "sudo tar -xvf containerd-1.1.0.linux-amd64.tar.gz -C /"

    ]
  }

  depends_on = ["null_resource.create_cert_and_kubeconfig"]
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
