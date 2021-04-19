#!/bin/bash
producto="mySistema"
ambiente="production"
region="sfo3"
namespace="cliente1"


name=$(doctl kubernetes cluster get cluster-$producto-$ambiente --format Name)
name=${name//Name}
name=${name//$'\n'/}
context="do-${region}-${name}"

echo [Step 1] ------- Creando namespace-------

kubectl --context $context create namespace $namespace

echo [Step 2] ------- Creando Secrets -------

kubectl --context $context create secret docker-registry regcred --docker-server=https://index.docker.io/v1/ --docker-username=<tu-usuario> --docker-password=<tu-password> --docker-email=<tu-email> --namespace $namespace

echo [Step 3] ------- Apply Kustomization -------

kubectl --context $context apply -k ./ # Implementacion con kustomization.yaml
# kubectl --context $context apply -f ./my-deployment.yaml # Implementación mediante archivos .yaml
echo [Step 4] ------- Obteniendo IP -------

external_ip=""
none="<none>"
while [ -z $external_ip ]; do
  echo "Esperando External IP"
  # ip=$(kubectl --namespace=ingress-nginx get service ingress-nginx -o=custom-columns=IP:.status.loadBalancer.ingress[0].ip)
  ip=$(kubectl --context $context get svc --namespace=ingress-nginx -o=custom-columns=IP:.status.loadBalancer.ingress[0].ip)
  ip=${ip//IP} ## Remueve la palabra IP del ip y solo queda el 0.0.0.0
  ip=${ip//$'\n'/} ## Remueve todos los espacios
  if [ "$ip" != "$none" ]; then 
    external_ip=$ip
  fi
  [ -z "$external_ip" ] && sleep 10
done 


echo [Step 5] ------- Creando Certificados HTTPS letsencrypt Staging-------

kubectl --context $context apply -f ./staging_issuer.yaml --namespace $namespace

echo [Step 6] ------- Aplicando Ingress Yaml Staging ------- # Antes de solicitar un certificado de producción es muy importante primero pasar por staging

kubectl --context $context apply -f ./ingress-staging.yaml

echo [Step 7] ------- Esperando Certificado Staging ------- # Esperamos hasta que letsencrypt nos certifique en staging

while [[ $(kubectl --context $context get certificate echo-tls --namespace $namespace -o 'jsonpath={..status.conditions[?(@.type=="Ready")].status}') != "True" ]]; 
do echo "Esperando Staing Certificate" && sleep 1; done
kubectl --context $context get certificate --namespace $namespace

echo [Step 8] ------- Creando Certificados HTTPS letsencrypt Prod------- 

kubectl --context $context apply -f ./prod_issuer.yaml --namespace $namespace

echo [Step 9] ------- Aplicando Ingress Yaml Staging -------

kubectl --context $context apply -f ./ingress-prod.yaml

echo [Step 10] ------- Esperando Certificado Production ------- # Esperamos hasta que letsencrypt nos certifique en staging

while [[ $(kubectl --context $context get certificate echo-tls --namespace $namespace -o 'jsonpath={..status.conditions[?(@.type=="Ready")].status}') != "True" ]]; 
do echo "Esperando Production Certificate" && sleep 1; done
kubectl --context $context get certificate --namespace $namespace

# Al finalizar debe entregar un mensaje similar con el estado Ready en True
# NAME      READY   SECRET    AGE
# echo-tls   True    3dm-tls   116m

echo [Step 5] ------- Creando Registros -------

doctl compute domain records create midominio.cl --record-name record1 --record-type A --record-data $external_ip 
doctl compute domain records create midominio.cl --record-name record2 --record-type A --record-data $external_ip 

read _exit
