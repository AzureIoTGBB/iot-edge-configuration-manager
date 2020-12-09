# Assumptions
# 1. A Resource Group with IoT Hub exists and this depeloyment will use the existing Resource Group where IoTHub resides


# Input Variables
RESOURCE_GROUP=""
FUNCTIONAPP_NAME=""
FUNCTIONAPP_STORAGE_ACCOUNT_NAME=""
LOCATION=""
APPINSIGHTS_NAME=""
IOTHUB_CONN_STRING_CSHARP: "<IOT HUB SERVICE CONNECTIONSTRING>"
ACRUSER: "<AZURE CONTAINER REGISTRY USER NAME>"
ACRPASSWORD: "<AZURE CONTAINER REGISTRY PASSWORD>"
ACR: "<AZURE CONTAINER REGISTRY SERVER>"
COSMOSENDPOINT: "<COSMOSDB ACCOUNT URI>"
COSMOSKEY: "<COSMOSDB ACCOUNT KEY>"
COSMOSDATABASEID: "<COSMOSDB DATABASE NAME>"
COSMOSCONTAINER_ALLMODULES: "<COSMOSDB ALLMODULES COLLECTION NAME>"
COSMOSCONTAINER_MANIFEST: "<COSMOSDB MANIFEST COLLECTION NAME>"

# Login to Azure 
echo "login with your Corp/Enterprise Azure AD Tenant"
az login  
echo "Press to continue..."
read input

echo "This is a bare minimum script with no checks.....so please check all inputs are correct"

echo "Azure Function Storage Account"
az storage account create `
  -n $FUNCTIONAPP_STORAGE_ACCOUNT_NAME `
  -g $RESOURCE_GROUP `
  --sku Standard_LRS

az resource create `
  -g $RESOURCE_GROUP -n $APPINSIGHTS_NAME `
  --resource-type "Microsoft.Insights/components" `
  --properties '{\"Application_Type\":\"web\"}'

az functionapp create `
  -n $FUNCTIONAPP_NAME `
  --storage-account $FUNCTIONAPP_STORAGE_ACCOUNT_NAME `
  --consumption-plan-location $LOCATION `
  --app-insights $APPINSIGHTS_NAME `
  --runtime dotnet `
  -g $RESOURCE_GROUP

# publish the code

az functionapp deployment `
source config --branch master --manual-integration `
--name $FUNCTIONAPP_NAME `
--repo-url https://github.com/AzureIoTGBB/iot-edge-configuration-manager/tree/main/src/IoTEdgeManifestGenerator `
--resource-group $RESOURCE_GROUP

DEPOTEST

az functionapp create \
  -n depotestfuncapp \
  --storage-account depoteststorage \
  --consumption-plan-location CentralUS \
  --app-insights depotestai \
  --runtime dotnet \
  -g DEPOTEST

az functionapp deployment \
source config --branch master --manual-integration \
--name depotestfuncapp \
--repo-url https://github.com/AzureIoTGBB/iot-edge-configuration-manager/tree/main/src/IoTEdgeManifestGenerator \
--resource-group DEPOTEST