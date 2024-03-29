#!/usr/bin/env bash

wget https://storage.googleapis.com/kubernetes-helm/helm-v2.12.2-linux-amd64.tar.gz
sudo tar xvf helm-v2.12.2-linux-amd64.tar.gz
cd linux-amd64 && sudo cp helm /usr/local/bin/

cd ~/
kubectl create serviceaccount tiller --namespace kube-system
sleep 10
kubectl apply -f manifest/helm-rbac-config.yaml
sleep 10
helm init --wait --service-account tiller
sleep 10

kubectl create ns development

kubectl apply -f guest-book/redis-master-deployment.yaml
kubectl apply -f guest-book/redis-master-service.yaml
kubectl apply -f guest-book/redis-slave-deployment.yaml
kubectl apply -f guest-book/redis-slave-service.yaml
kubectl apply -f guest-book/frontend-deployment.yaml
kubectl apply -f guest-book/frontend-service.yaml
kubectl apply -f guest-book/app-gateway.yaml




##### Istio
sleep 20
helm repo add istio.io https://storage.googleapis.com/istio-release/releases/1.1.4/charts/
helm install istio.io/istio-init --name istio-init --version 1.1.4 --namespace istio-system --wait
sleep 20

helm install istio.io/istio --name istio --version 1.1.4 --namespace istio-system

sleep 20
kubectl label namespace default istio-injection=enabled --overwrite

kubectl create ns monitoring

kubectl apply -f manifest/filebeat.yaml

helm install \
    --namespace=monitoring \
    --name=prometheus \
    --version=7.0.0 \
    stable/prometheus

helm install \
    --namespace=monitoring \
    --name=grafana \
    --version=1.12.0 \
    --set=adminUser=admin \
    --set=adminPassword=admin \
    --set=service.type=NodePort \
    stable/grafana
