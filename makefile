# |-----------------------------------------------------------------------------
# | Variable definitions
# |-----------------------------------------------------------------------------

# Defines the target executed when running `make` without
# arguments
.DEFAULT_GOAL := help

CONTEXT=kind-klanik-cluster
PROJECTNAME=ti-tempo
NAMESPACE=monitoring
NAMESPACE-TRACE-GEN=trace-generator
NAMESPACE-QUARKUS-NOAGENT=quarkus-no-agent
NAMESPACE-QUARKUS-OTEL=quarkus-otel
NAMESPACE-QUARKUS-DOUBLE=quarkus-double
NAMESPACE-QUARKUS-APPDYN=quarkus-appdyn
NAMESPACE-APPDYN=appdynamics
NAMESPACE-LOKI=loki-distributed

VERSION_GRAFANA=8.2.26 # grafana 9.1.2, v 7.9.11 default PE
VERSION_PROMETHEUS=8.1.7
VERSION_OTEL=0.45.0
VERSION_TEMPO=0.16.0
VERSION_LOKI=4.5.0
VERSION_OTEL_OPERATOR=0.18.2


NAMESPACEVCLUSTER=nsvcluster-${PROJECTNAME}
VCLUSTERNAME=${PROJECTNAME}

## command local
CMDLOCAL='kubectl kubens kubectx vcluster helm'

### Function mise en forme
STEP := 0
RED=$(shell tput setaf 1)
GREEN=$(shell tput setaf 2)
NC=$(shell tput sgr0) # No Color

.PHONY: help
help: ## Affiche l'aide
	@grep -E '^[a-zA-Z\/_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'

# |-----------------------------------------------------------------------------
# | Global targets
# |-----------------------------------------------------------------------------


.PHONY: connect
connect: ## Connecte au vcluster
	$(call title, 'connection au vcluster $(NAMESPACEVCLUSTER)')
	@kubectx $(CONTEXT)
	@kubens $(NAMESPACE)

.PHONY: connectns
connectns: connect ## Connecte au ns
	@kubens $(NAMESPACE)

.PHONY: clean
clean: ## Clean environnement
	$(call title, 'delete du namespace vcluster env TI')
	@kubectx $(CONTEXT)
	@kubectl create namespace $(NAMESPACE);\
	@-kubectl get namespace $(NAMESPACE) ;\
	if [ $$? -eq 0 ]; \
	then \
		echo 'Namespace $(NAMESPACE) found';\
		kubectl delete namespace $(NAMESPACE);\
	else \
		echo 'Namespace $(NAMESPACE) not found';\
	fi

.PHONY: prometheus
prometheus: connectns ## Déploie prometheus
	$(call title, 'ajout repository bitnami')
	@helm repo add helm-bitnami-virtual https://repository.pole-emploi.intra/artifactory/helm-bitnami-virtual

	$(call title, 'deploiement helm prometheus version $(VERSION_PROMETHEUS) dans le vcluster $(VCLUSTERNAME)')
	$(call uninstall_helm, 'prometheus')
	@helm upgrade --install prometheus bitnami/kube-prometheus --version $(VERSION_PROMETHEUS) --create-namespace --namespace $(NAMESPACE) --values prometheus/values.yaml --atomic --timeout 300s

.PHONY: otel
otel: connectns ## Déploie open telemetry
	$(call title, 'ajout repository open-telemetry')
	@helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts

	$(call title, 'mise à jour du repository open-telemetry')
	@helm repo update open-telemetry
	
	$(call title, 'deploiement helm opentelemetry version $(VERSION_OTEL) dans le vcluster $(VCLUSTERNAME)')
	@helm upgrade --install opentelemetry-collector open-telemetry/opentelemetry-collector --version $(VERSION_OTEL) --create-namespace --namespace $(NAMESPACE) --values opentelemetry/values.yaml

.PHONY: otel-operator
otel-operator: connectns ## Déploie opentelemtry operator
	$(call title, 'ajout repository open-telemetry')
	@helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts

	$(call title, 'mise à jour du repository open-telemetry')
	@helm repo update open-telemetry

	$(call title, 'deploiement helm Opentelemetry operator version $(VERSION_OTEL_OPERATOR) dans le vcluster $(VCLUSTERNAME)')
	@helm upgrade --install opentelemetry-operator open-telemetry/opentelemetry-operator --version ${VERSION_OTEL_OPERATOR} --create-namespace --namespace $(NAMESPACE) --values otel_operator/values.yaml
    
	@sleep 30

	$(call title, 'ajout instrumentation CRD pour Otel Operator')
	@kubectl apply -f otel_operator/instrumentation_crd.yaml

.PHONY: tempo
tempo: connectns ## Déploie tempo
	$(call title, 'ajout repository grafana')
	@helm repo add grafana https://grafana.github.io/helm-charts

	$(call title, 'deploiement helm tempo version $(VERSION_TEMPO) dans le vcluster $(VCLUSTERNAME)')
	@helm upgrade --install tempo grafana/tempo --version $(VERSION_TEMPO) --create-namespace --namespace $(NAMESPACE) --values tempo/values.yaml


.PHONY: minio
minio: connectns ## Déploie minio
	$(call title, 'deploiement minio $(VERSION_TEMPO) pour stockage S3 dans le vcluster $(VCLUSTERNAME)')
	@helm upgrade --install tempo grafana/tempo --version $(VERSION_TEMPO) --create-namespace --namespace $(NAMESPACE) --values tempo/values.yaml
	@kubectl apply -f minio/deploiement.yaml


.PHONY: grafana
grafana: connectns ## Déploie grafana
	$(call title, 'ajout repository grafana')
	@helm repo add grafana https://grafana.github.io/helm-charts

	$(call title, 'deploiement helm grafana version $(VERSION_GRAFANA) dans le vcluster $(VCLUSTERNAME)')
	$(call uninstall_helm, 'grafana')
	@kubectl apply -f grafana/grafana.ini.yaml
	@kubectl apply -f grafana/grafana-tempo-datasource.yaml
	# applique les dashboards ( utilisation de --server-side=true --force-conflicts pour eviter le problème de taille maximale)
	@kubectl apply --server-side=true --force-conflicts -f grafana/configmap-dashboards.yaml 
	@helm upgrade --install grafana bitnami/grafana --version $(VERSION_GRAFANA) --create-namespace --namespace $(NAMESPACE) --values grafana/values.yaml

.PHONY: loki
loki: connectns ## Déploie loki
	$(call title, 'création du namespace $(NAMESPACE-LOKI) sur le cluster $(CONTEXT)')
	@kubectl get namespace ${NAMESPACE-LOKI} || kubectl create namespace ${NAMESPACE-LOKI}
	@kubens ${NAMESPACE-LOKI}
	
	$(call title, 'ajout repository loki')
	@helm repo add grafana https://grafana.github.io/helm-charts
	@helm upgrade --install loki grafana/loki-distributed --namespace=$(NAMESPACE-LOKI) --values loki/values.yaml
	


.PHONY: traces-manual-petclinic
traces-manual-petclinic: connect ## Déploie le générateur de traces manuel Petclinic
	$(call title, 'deploiement du générateur de traces manuel Petclinic')
	@kubectl get namespace ${NAMESPACE} || kubectl create namespace ${NAMESPACE}
	@kubens ${NAMESPACE}
	@kubectl apply -f petclinic/petclinic.yaml



.PHONY: deploy
deploy: clean prometheus minio tempo grafana otel otel-operator loki ## Déploie tout l'environnement   , ingress

## créer les ingress 

.PHONY: ingress
ingress: connectns ## Déploie tous les ingress
	$(call title, 'creation ingress grafana prometheus et tempo ')
	@kubectl apply -f poc/src/grafana/ingress.yaml
	@kubectl apply -f poc/src/prometheus/ingress.yaml
	@kubectl apply -f poc/src/opentelemetry/ingress.yaml

.PHONY: deploy-quarkus-otel
deploy-quarkus-otel: connectns ## Déploie le quarkus avec agent otel dans le vcluster
	$(call title, 'déploiement de quarkus sous agent otel')
	@kubectl get namespace ${NAMESPACE-QUARKUS-OTEL} || kubectl create namespace ${NAMESPACE-QUARKUS-OTEL}
	@kubens ${NAMESPACE-QUARKUS-OTEL}
	@kubectl apply -f poc/src/quarkus-otel-agent/deploy/deployment.yaml
	@kubectl apply -f poc/src/quarkus-otel-agent/deploy/ingress.yaml
	@kubectl apply -f poc/src/quarkus-otel-agent/deploy/servicemonitor.yaml


define title 
	@echo '✨ $(GREEN)$1$(NC) ...' 
endef

define uninstall_helm
	@echo 'check if $1 installed'
	@helm status $1 ;\
	if [ $$? -eq 0 ]; \
	then \
		helm uninstall $1;\
	else \
		echo '$1 not installed';\
	fi
endef
