# teklive-opentelemetry

Attention, si on doit reconstruire le cluster :

il faudra faire un port forward sur minio pour créer un bucket "toto"
aussi lancer les commandes de récupération des images docker avant de les pousser dans le clutster Kind

par exemple :

 docker pull nginxinc/nginx-unprivileged:1.20.2-alpine
 kind load docker-image nginxinc/nginx-unprivileged:1.20.2-alpine  --name klanik-cluster
