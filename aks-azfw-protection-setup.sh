#!/bin/bash

# Environment Variables
PREFIX="aks-azfw-protection"
RG="${PREFIX}-rg"
LOC="eastus"  #you can change the location
PLUGIN=azure
AKSNAME="${PREFIX}"
VNET_NAME="${PREFIX}-vnet"
AKSSUBNET_NAME="aks-subnet"
# DO NOT CHANGE FWSUBNET_NAME - This is currently a requirement for Azure Firewall.
FWSUBNET_NAME="AzureFirewallSubnet"
FWNAME="${PREFIX}-fw"
FWPUBLICIP_NAME="${PREFIX}-fwpublicip"
FWIPCONFIG_NAME="${PREFIX}-fwconfig"
FWROUTE_TABLE_NAME="${PREFIX}-fwrt"
FWROUTE_NAME="${PREFIX}-fwrn"
FWROUTE_NAME_INTERNET="${PREFIX}-fwinternet"
# FILL IN WITH YOUR SUBSCRIPTION ID
SUB_ID="7a06e974-7329-4485-87e7-3211b06c15aa" ##change this subscription id
POD_CIDR=""
VM_SIZE=Standard_D2s_v3

# Script Usage
usage()
{
    echo "usage: aks-azfw-protection-setup.sh [[[-p Network_Plugin ] [-s NODE_VM_SIZE] [-k K8S_VERSION] [- LOC]] | [-h]]"
}

# Dynamic Environment Variables
while [ "$1" != "" ]; do
  case $1 in
  -p | '--plugin' )         
    shift
    PLUGIN=$1
    if [[ $PLUGIN == "kubenet" ]]; then POD_CIDR=192.168.0.0/16; fi
    ;;
  -s | '--node-vm-size' )
    shift   
    VM_SIZE=$1
    ;;
  -k | '--kubernetes-version' )
    shift   
    K8S_VERSION=$1
    ;;
  -l | '--location' )
    shift   
    LOC=$1
    ;;
  -h | '--help' )
    usage
    exit
    ;;
  * )
    usage
    exit 1
  esac
  shift
done

# Set Location
az configure --defaults location=$LOC

# Set Subscription
az account set --subscription $SUB_ID
echo "SUBSCRIPTION SET"

# Install Azure Firewall CLI Extension
az extension add --name azure-firewall
echo "FW EXTENSION ADDED"

# Install AKS CLI Extension
az aks install-cli
echo "AKS CLI ADDED"

# Pre-Clean Up
az group delete -y -n $RG
echo "CLEAN UP COMPLETE"

# Create Resource Group
az group create --name $RG --location $LOC
echo "RESOURCE GROUP CREATED"

# Create Managed Identity
PRINCIPAL_ID=$(az identity create --name aks-azfw-protection-principal-id --resource-group $RG -l $LOC --query principalId -o tsv)
echo "PRINCIPAL ID CREATED"
IDENTITY_ID=$(az identity show --name aks-azfw-protection-principal-id --resource-group $RG --query id -o tsv)
echo "IDENTITY ID ACQUIRED"

# Create Virtual Network & Subnets for AKS, k8s Services, and Firewall
# Dedicated Virtual Network with AKS Subnet
az network vnet create \
    --resource-group $RG \
    --name $VNET_NAME \
    --location $LOC \
    --address-prefixes 10.42.0.0/16 \
    --subnet-name $AKSSUBNET_NAME \
    --subnet-prefix 10.42.1.0/24   
echo "VNET, AKS SUBNET CREATED"
# Dedicated Subnet for Azure Firewall
az network vnet subnet create \
    --resource-group $RG \
    --vnet-name $VNET_NAME \
    --name $FWSUBNET_NAME \
    --address-prefix 10.42.2.0/24
echo "FW SUBNET CREATED"

# Create Public IP
az network public-ip create -g $RG -n $FWPUBLICIP_NAME -l $LOC --sku "Standard"
echo "FW PUBLIC IP CREATED"

# Create Firewall
FW_ID=$(az network firewall create -g $RG -n $FWNAME -l $LOC --enable-dns-proxy true --query id -o tsv)
echo "FW CREATED"

# Configure Firewall IP Config
az network firewall ip-config create -g $RG -f $FWNAME -n $FWIPCONFIG_NAME --public-ip-address $FWPUBLICIP_NAME --vnet-name $VNET_NAME
echo "FW IP CONFIGURED"

# Capture Firewall IP Address for Later Use
FWPUBLIC_IP=$(az network public-ip show -g $RG -n $FWPUBLICIP_NAME --query "ipAddress" -o tsv)
FWPRIVATE_IP=$(az network firewall show -g $RG -n $FWNAME --query "ipConfigurations[0].privateIpAddress" -o tsv)

# Create UDR & Routing Table
RTID=$(az network route-table create -g $RG -l $LOC --name $FWROUTE_TABLE_NAME --query id -o tsv)
echo "ROUTE TABLE CREATED"
az network route-table route create -g $RG --name $FWROUTE_NAME --route-table-name $FWROUTE_TABLE_NAME --address-prefix 0.0.0.0/0 --next-hop-type VirtualAppliance --next-hop-ip-address $FWPRIVATE_IP
az network route-table route create -g $RG --name $FWROUTE_NAME_INTERNET --route-table-name $FWROUTE_TABLE_NAME --address-prefix $FWPUBLIC_IP/32 --next-hop-type Internet
echo "ROUTES ADDED"

# Add FW Network Rules
az network firewall network-rule create -g $RG -f $FWNAME --collection-name 'aksfwnr' -n 'apiudp' --protocols 'UDP' --source-addresses '*' --destination-addresses "AzureCloud.$LOC" --destination-ports 1194 --action allow --priority 100
az network firewall network-rule create -g $RG -f $FWNAME --collection-name 'aksfwnr' -n 'apitcp' --protocols 'TCP' --source-addresses '*' --destination-addresses "AzureCloud.$LOC" --destination-ports 9000 
az network firewall network-rule create -g $RG -f $FWNAME --collection-name 'aksfwnr' -n 'time' --protocols 'UDP' --source-addresses '*' --destination-fqdns 'ntp.ubuntu.com' --destination-ports 123
echo "FW NETWORK RULES ADDED"

# Add FW Application Rules
az network firewall application-rule create -g $RG -f $FWNAME --collection-name 'aksfwar' -n 'fqdn' --source-addresses '*' --protocols 'http=80' 'https=443' --fqdn-tags "AzureKubernetesService" --action allow --priority 100
echo "FW APPLICATION RULES ADDED"

# Associate Route Table to AKS
az network vnet subnet update -g $RG --vnet-name $VNET_NAME --name $AKSSUBNET_NAME --route-table $FWROUTE_TABLE_NAME
echo "ROUTE TABLE ASSOCIATED TO AKS SUBNET"

FW_ID=$(az network firewall show -g $RG -n $FWNAME --query id -o tsv)
VNET_ID=$(az network vnet show -g $RG -n $VNET_NAME --query id -o tsv)
SUBNETID=$(az network vnet subnet show -g $RG --vnet-name $VNET_NAME --name $AKSSUBNET_NAME --query id -o tsv)

# Assign Roles Based on Managed Identity
az role assignment create --assignee $PRINCIPAL_ID --scope $VNET_ID --role "Network Contributor"
az role assignment create --assignee $PRINCIPAL_ID --scope $RTID --role "Network Contributor"
echo "ROLES ASSIGNED BASED ON MANAGED IDENTITY"

sleep 60s 

echo "Plugin: $PLUGIN; k8s version: $K8S_VERSION; Pod CIDR: $POD_CIDR;"

# Create AKS Cluster
az aks create -g $RG -n $AKSNAME -l $LOC ${K8S_VERSION:+-k $K8S_VERSION} \
  --node-count 1 -s $VM_SIZE \
  --network-plugin $PLUGIN \
  --outbound-type userDefinedRouting \
  --service-cidr 10.41.0.0/16 \
  --dns-service-ip 10.41.0.10 \
  --docker-bridge-address 172.17.0.1/16 \
  ${POD_CIDR:+ --pod-cidr $POD_CIDR} \
  --vnet-subnet-id $SUBNETID \
  --assign-identity $IDENTITY_ID \
  --generate
echo "AKS CLUSTER CREATED"

# Get AKS Credentials so kubectl works
az aks get-credentials -g $RG -n $AKSNAME --admin --overwrite-existing
echo "AKS CREDENTIALS ACQUIRED"

# Get Nodes
kubectl get nodes -o wide

# Deploy a Public Service
kubectl apply -f example.yaml
echo "DEPLOYED EXAMPLE APPLICATION"

# Get Service IP of Voting App
SERVICE_IP=$(kubectl get svc voting-app -o jsonpath='{.status.loadBalancer.ingress[*].ip}')

# Add DNAT Rule for Ingress Traffic Access
az network firewall nat-rule create --collection-name aksfwdnat --destination-addresses $FWPUBLIC_IP --destination-ports 80 --firewall-name $FWNAME --name inboundrule --protocols Any --resource-group $RG --source-addresses '*' --translated-port 80 --action Dnat --priority 100 --translated-address $SERVICE_IP
echo "FW DNAT RULE ADDED"
