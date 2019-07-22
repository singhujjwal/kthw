# MStakx Test Solution

##Tasks:
1.	Create a Highly available Kubernetes cluster manually using Google Compute Engines (GCE). Do not create a Kubernetes hosted solution using Google Kubernetes Engine (GKE). Use Kubeadm(preferred)/kubespray. Do not use kops.
2.	Create a CI/CD pipeline using Jenkins (or a CI tool of your choice) outside Kubernetes cluster (not as a pod inside Kubernetes cluster).
3.	Create a development namespace.
4.	Deploy guest-book application (or any other application which you think is more suitable to showcase your ability, kindly justify why you have chosen a different application) in the development namespace.
5.	Install and configure Helm in Kubernetes
6.	Use Helm to deploy the application on Kubernetes Cluster from CI server.
7.	Create a monitoring namespace in the cluster.
8.	Setup Prometheus (in monitoring namespace) for gathering host/container metrics along with health check status of the application. 
9.	Create a dashboard using Grafana to help visualize the Node/Container/API Server etc. metrices from Prometheus server. Optionally create a custom dashboard on Grafana
10.	Setup log analysis using Elasticsearch, Fluentd (or Filebeat), Kibana.
11.	Demonstrate Blue/Green and Canary deployment for the application (For e.g. Change the background color or font in the new version etc.,)
12.	Write a wrapper script (or automation mechanism of your choice) which does all the steps above.
13.	Document the whole process in a README file at the root of your repo. Mention any pre-requisites in the README.

## Solution Steps
### Highly available Kubernetes cluster
A highly available kubernetes cluster comprises of highly available API server and
highly available etcd cluster which is the datastore for the 
name value pair. Preferred cloud provider is GCE but AWS can 
be used as well

The option to create cluster using automation is to write 
scripts to bootstrap the server or try to use ansbile playbooks
to do the same, 

* Use terraform to create the infrastructure VPC with nodes (
I will be not doing this, as this is not in the scope of the test, although 
 i would like to detail what goes behind the scenes
 
 
    a) It creates a VPC with two public (with internet gateway attached,  
    and two private subnets(with nat gateway to download packages).
 
    b) Creates two nodes in public subnets for kube controller nodes
 
    c) Creates two nodes in private subnets for worker nodes
    
    d) I have a precreated ssh key which i will be using through out
    
    e) The public and private subnets can talk to each other, i.e. the security
    group is enabled to allow access between private and 
    public subnets.
 )
 
* I will be using the git repo https://github.com/kelseyhightower/kubernetes-the-hard-way to deploy
the kubernetes cluster

* Since the requirement is to create the kubernetes cluster manually
i will not create automation for that, although if required there
are few choices to do that.
    1. Using ansible role/playbook for controller nodes and worker nodes 
    2. Using simple `remote-exec` automation as part of VM creation via terraform, while creating instances have
    a `remote-exec section` to run the shell commands to setup the master and 
    worker nodes
* I think there is a confusing instruction in point 12 which talks about writing a 
wrapper script to automate all this, i believe it is asking
to automate the Kubernetes cluster creationion as well.
For that i am now creating terraform based 
automation to deploy the kubernetes cluster.
    
* PREREQUISITE 
cfssl and kubectl should be installed

1. Kubernetes cluster is created using terraform
2. Sample Pipeline Jenkinsfile is present.
3. `platform.sh` script takes care of 
> creating development namespace

>deploying guest-book application

>Helm installation

>Helm install other applications like monitoring package, although the application is deployed via `kubectl`

>Creating a monitoring namespace

>Setting up prometheous

>Grafana is installed, filebeat config is included but not deployed.

>Blue/Green and Canary deployment will be taken care using app-gateway.yaml, changing the weight and with help of
istio

>Almost everything is automated.
