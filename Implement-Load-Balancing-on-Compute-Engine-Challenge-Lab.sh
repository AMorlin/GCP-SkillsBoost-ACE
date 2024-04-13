# Setar REGIAO e ZONA
gcloud config set compute/region europe-west1
gcloud config set compute/zone europe-west1-c 

# Criar VARIÁVEL de AMBIENTE para ARMAZENAR REGIAO e ZONA
export REGION=$(gcloud config get-value compute/region)
export ZONE=$(gcloud config get-value compute/zone)

# Criar VM INSTANCE Jumphost no Gloud (usar o nome do LAB)
gcloud compute instances create nucleus-jumphost-322 \
    --zone $ZONE \
    --machine-type e2-micro \
    --image-family=debian-11 \
    --image-project=debian-cloud

# Criar Script de Instalacao NGINX
cat << EOF > startup.sh
#! /bin/bash
apt-get update
apt-get install -y nginx
service nginx start
sed -i -- 's/nginx/Google Cloud Platform - '"\$HOSTNAME"'/' /var/www/html/index.nginx-debian.html
EOF

# Criar Template Instance
gcloud compute instance-templates create lb-backend-template \
   --region=$REGION \
   --network=default \
   --subnet=default \
   --tags=http-server \
   --machine-type=e2-medium \
   --image-family=debian-11 \
   --image-project=debian-cloud \
   --metadata-from-file startup-script=startup.sh

# Criar Grupo gerenciado de instancias baseado no Template
gcloud compute instance-groups managed create lb-backend-group \
   --base-instance-name=nginx \
   --template=lb-backend-template \
   --size=2 \
   --zone=$ZONE

# Define named port
gcloud compute instance-groups managed set-named-ports lb-backend-group \
  --named-ports http:80 \
  --zone=$ZONE

# Criar regra de FIREWALL para permitir tragefo HTTP - Usar nome do LAB
gcloud compute firewall-rules create allow-tcp-rule-489 \
  --network=default \
  --action=allow \
  --direction=ingress \
  --target-tags=http-server \
  --rules=tcp:80

# Criar HEALTH CHECK para o LB
gcloud compute health-checks create http http-basic-check \
  --port 80

# Criar SERVIÇO DE BACK END
gcloud compute backend-services create web-backend-service \
  --protocol=HTTP \
  --port-name=http \
  --health-checks=http-basic-check \
  --global

# Adicionar Instance Group como Back-end do serviço do Back-End
gcloud compute backend-services add-backend web-backend-service \
  --instance-group=lb-backend-group \
  --instance-group-zone=$ZONE \
  --global

# Criar Mapa de URL
gcloud compute url-maps create web-map-http \
    --default-service web-backend-service

# Criar HTTP Proxy
gcloud compute target-http-proxies create http-lb-proxy \
    --url-map web-map-http

# Criar rergra de encaminhamento 
gcloud compute forwarding-rules create http-content-rule \
   --global \
   --target-http-proxy=http-lb-proxy \
   --ports=80
