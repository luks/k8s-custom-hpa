# Makefile for generating TLS certs for the Prometheus custom metrics API adapter

SHELL=bash
UNAME := $(shell uname)
PURPOSE:=metrics
SERVICE_NAME:=custom-metrics-apiserver
ALT_NAMES:='"custom-metrics-apiserver.monitoring","custom-metrics-apiserver.monitoring.svc"'
SECRET_FILE:=custom-metrics/cm-adapter-serving-certs.yaml

certs: gensecret rmcerts

.PHONY: gencerts
gencerts:
	@echo Generating TLS certs
	@mkdir -p output
	@touch output/apiserver.pem
	@touch output/apiserver-key.pem
	@openssl req -x509 -sha256 -new -nodes -days 365 -newkey rsa:2048 -keyout $(PURPOSE)-ca.key -out $(PURPOSE)-ca.crt -subj "/CN=ca"
	@echo '{"signing":{"default":{"expiry":"43800h","usages":["signing","key encipherment", "client auth", "server auth", "'$(PURPOSE)'"]}}}' > "$(PURPOSE)-ca-config.json"
	@echo '{"CN":"'$(SERVICE_NAME)'","hosts":['$(ALT_NAMES)'],"key":{"algo":"ecdsa","size": 256 }}' | cfssl gencert -ca=metrics-ca.crt -ca-key=metrics-ca.key -config=metrics-ca-config.json - | cfssljson  -bare output/apiserver
	##@echo '{"CN":"'$(SERVICE_NAME)'","hosts":['$(ALT_NAMES)'],"key":{"algo":"ecdsa","size": 256 }}' | cfssl gencert -ca=k8st1.ko/k8s/ca/ca.pem -ca-key=k8st1.ko/k8s/ca/ca-key.pem -config=metrics-ca-config.json - | cfssljson  -bare output/apiserver

.PHONY: gensecret
gensecret: gencerts
	@echo Generating $(SECRET_FILE)
	@echo "apiVersion: v1" > $(SECRET_FILE)
	@echo "kind: Secret" >> $(SECRET_FILE)
	@echo "metadata:" >> $(SECRET_FILE)
	@echo " name: cm-adapter-serving-certs" >> $(SECRET_FILE)
	@echo " namespace: monitoring" >> $(SECRET_FILE)
	@echo "data:" >> $(SECRET_FILE)
ifeq ($(UNAME), Darwin)
	@echo " serving.crt: $$(cat output/apiserver.pem | base64)" >> $(SECRET_FILE)
	@echo " serving.key: $$(cat output/apiserver-key.pem | base64)" >> $(SECRET_FILE)
endif
ifeq ($(UNAME), Linux)
	@echo " serving.crt: $$(cat output/apiserver.pem | base64 -w 0)" >> $(SECRET_FILE)
	@echo " serving.key: $$(cat output/apiserver-key.pem | base64 -w 0)" >> $(SECRET_FILE)
endif

.PHONY: rmcerts
rmcerts:
	@rm -f apiserver-key.pem apiserver.csr apiserver.pem
	@rm -f metrics-ca-config.json metrics-ca.crt metrics-ca.key

.PHONY: deploy
deploy:
	kubectl create -f ./namespaces.yaml
	kubectl create -f ./prometheus
	kubectl create -f ./custom-metrics
