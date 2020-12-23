# Assumptions
# 1. A Resource Group with IoT Hub exists and this depeloyment will use the existing Resource Group where IoTHub resides
# colors for formatting the ouput
YELLOW='\033[1;33m'
GREEN='\033[1;32m'
RED='\033[0;31m'
BLUE='\033[1;34m'
NC='\033[0m' # No Color



function loadInputs() {
    inputs=`cat local.settings.json`
    RESOURCE_GROUP=`echo $inputs | jq '.RESOURCE_GROUP'`
    RESOURCE_GROUP=`echo $RESOURCE_GROUP | tr -d '"'`

    FUNCTIONAPP_NAME=`echo $inputs | jq '.FUNCTIONAPP_NAME'`
    FUNCTIONAPP_NAME=`echo $FUNCTIONAPP_NAME | tr -d '"'`

    FUNCTIONAPP_STORAGE_ACCOUNT_NAME=`echo $inputs | jq '.FUNCTIONAPP_STORAGE_ACCOUNT_NAME'`
    FUNCTIONAPP_STORAGE_ACCOUNT_NAME=`echo $FUNCTIONAPP_STORAGE_ACCOUNT_NAME | tr -d '"'`

    LOCATION=`echo $inputs | jq '.LOCATION'`
    LOCATION=`echo $LOCATION | tr -d '"'`

    APPINSIGHTS_NAME=`echo $inputs | jq '.APPINSIGHTS_NAME'`
    APPINSIGHTS_NAME=`echo $APPINSIGHTS_NAME | tr -d '"'`

    IOTHUB_NAME=`echo $inputs | jq '.IOTHUB_NAME'`
    IOTHUB_NAME=`echo $IOTHUB_NAME | tr -d '"'`

    IOTHUB_CONN_STRING_CSHARP=`echo $inputs | jq '.IOTHUB_CONN_STRING_CSHARP'`
    IOTHUB_CONN_STRING_CSHARP=`echo $IOTHUB_CONN_STRING_CSHARP | tr -d '"'`

    ACRUSER=`echo $inputs | jq '.ACRUSER'`
    ACRUSER=`echo $ACRUSER | tr -d '"'`

    ACRPASSWORD=`echo $inputs | jq '.ACRPASSWORD'`
    ACRPASSWORD=`echo $ACRPASSWORD | tr -d '"'`

    ACR=`echo $inputs | jq '.ACR'`
    ACR=`echo $ACR | tr -d '"'`

    COSMOSACCOUNTNAME=`echo $inputs | jq '.COSMOSACCOUNTNAME'`
    COSMOSACCOUNTNAME=`echo $COSMOSACCOUNTNAME | tr -d '"'`

    COSMOSDBNAME=`echo $inputs | jq '.COSMOSDBNAME'`
    COSMOSDBNAME=`echo $COSMOSDBNAME | tr -d '"'`

    COSMOSCONTAINER_ALLMODULES=`echo $inputs | jq '.COSMOSCONTAINER_ALLMODULES'`
    COSMOSCONTAINER_ALLMODULES=`echo $COSMOSCONTAINER_ALLMODULES | tr -d '"'`

    COSMOSCONTAINER_MANIFEST=`echo $inputs | jq '.COSMOSCONTAINER_MANIFEST'`
    COSMOSCONTAINER_MANIFEST=`echo $COSMOSCONTAINER_MANIFEST | tr -d '"'`

    echo "${YELLOW}Please confirm all inputs."
    echo "${BLUE}RESOURCE_GROUP=${GREEN}${RESOURCE_GROUP}"
    echo "${BLUE}FUNCTIONAPP_NAME=${GREEN}${FUNCTIONAPP_NAME}"
    echo "${BLUE}FUNCTIONAPP_STORAGE_ACCOUNT_NAME=${GREEN}${FUNCTIONAPP_STORAGE_ACCOUNT_NAME}"
    echo "${BLUE}LOCATION=${GREEN}${LOCATION}"
    echo "${BLUE}APPINSIGHTS_NAME=${GREEN}${APPINSIGHTS_NAME}"
    echo "${BLUE}IOTHUB_NAME=${GREEN}${IOTHUB_NAME}"
    echo "${BLUE}IOTHUB_CONN_STRING_CSHARP=${GREEN}${IOTHUB_CONN_STRING_CSHARP}"
    echo "${BLUE}ACRUSER=${GREEN}${ACRUSER}"
    echo "${BLUE}ACRPASSWORD=${GREEN}${ACRPASSWORD}"
    echo "${BLUE}ACR=${GREEN}${ACR}"
    echo "${BLUE}COSMOSACCOUNTNAME=${GREEN}${COSMOSACCOUNTNAME}"
    echo "${BLUE}COSMOSDBNAME=${GREEN}${COSMOSDBNAME}"
    echo "${BLUE}COSMOSCONTAINER_ALLMODULES=${GREEN}${COSMOSCONTAINER_ALLMODULES}"
    echo "${BLUE}COSMOSCONTAINER_MANIFEST=${GREEN}${COSMOSCONTAINER_MANIFEST}"

}

function createRG() {
    # Create a resource group
    az group create --resource-group $RESOURCE_GROUP --location $LOCATION --output none
}

function createCosmosDBwithContainers(){
    echo "${BLUE} Creating CosmosDB Account ${COSMOSACCOUNTNAME}"
    # Create a Cosmos account for SQL API
    az cosmosdb create \
        --name $COSMOSACCOUNTNAME \
        --resource-group $RESOURCE_GROUP \
        --default-consistency-level Eventual \
        --locations regionName=$LOCATION \
        --output none

    # Create a SQL API database
    echo "${BLUE} Creating SQL API Database ${COSMOSDBNAME}"
    az cosmosdb sql database create \
        -a $COSMOSACCOUNTNAME \
        -g $RESOURCE_GROUP \
        -n $COSMOSDBNAME \
        --output  none

    # Define the index policy for the container, include spatial and composite indexes
    # Create a SQL API container for storing Module definitions
    echo "${BLUE} Creating CosmosDB Container ${COSMOSCONTAINER_ALLMODULES}"
    az cosmosdb sql container create \
        -a $COSMOSACCOUNTNAME \
        -g $RESOURCE_GROUP \
        -d $COSMOSDBNAME \
        -n $COSMOSCONTAINER_ALLMODULES \
        -p '/moduleid' \
        --throughput 400 \
        --idx @./idxpolicy.json \
        --output  none

    # Create a SQL API container for storing Manifest definitions
    echo "${BLUE} Creating CosmosDB Container ${COSMOSCONTAINER_MANIFEST}"
    az cosmosdb sql container create \
        -a $COSMOSACCOUNTNAME \
        -g $RESOURCE_GROUP \
        -d $COSMOSDBNAME \
        -n $COSMOSCONTAINER_MANIFEST \
        -p '/version' \
        --throughput 400 \
        --idx @./idxpolicy.json \
        --output  none
        
}

function retreiveCosmosDBkeys(){
     # Get the Keys for CosmosDB
    echo "${BLUE}Retreiving Connection Information for CosmosDB ${COSMOSACCOUNTNAME}"
    COSMOSKEY=`az cosmosdb keys list --name $COSMOSACCOUNTNAME --resource-group $RESOURCE_GROUP  --type keys | jq '.primaryMasterKey'`
    #Remove "
    COSMOSKEY=`echo $COSMOSKEY | tr -d '"'`
    COSMOSINFO=`az cosmosdb show --name $COSMOSACCOUNTNAME --resource-group $RESOURCE_GROUP`
    COSMOSENDPOINT=`echo $COSMOSINFO | jq '.documentEndpoint'`
    COSMOSENDPOINT=`echo $COSMOSENDPOINT | tr -d '"'`

}

function createFunctionApp() {
    echo "${BLUE}Creating Azure Function Storage Account ${FUNCTIONAPP_STORAGE_ACCOUNT_NAME}"
    az storage account create \
    -n $FUNCTIONAPP_STORAGE_ACCOUNT_NAME \
    -g $RESOURCE_GROUP \
    --sku Standard_LRS  \
    --output  none

    echo "${BLUE}Retreiving Azure Function Storage Account ${FUNCTIONAPP_STORAGE_ACCOUNT_NAME}"
    FUNCTIONAPP_STORAGE_CONN_STRING=`az storage account show-connection-string \
    -g $RESOURCE_GROUP \
    -n $FUNCTIONAPP_STORAGE_ACCOUNT_NAME \
    | jq '.connectionString'`
    #Remove doublequots
    FUNCTIONAPP_STORAGE_CONN_STRING=`echo $FUNCTIONAPP_STORAGE_CONN_STRING | tr -d '"'`

    echo "${BLUE}Creating App Insights ${APPINSIGHTS_NAME}"
    az resource create \
    -g $RESOURCE_GROUP -n $APPINSIGHTS_NAME \
    --resource-type "Microsoft.Insights/components" \
    --properties "{\"Application_Type\":\"web\"}"  \
    --output  none

    echo "${BLUE}Creating Azure Function App ${FUNCTIONAPP_NAME}"
    az functionapp create \
    -n $FUNCTIONAPP_NAME \
    --storage-account $FUNCTIONAPP_STORAGE_ACCOUNT_NAME \
    --consumption-plan-location $LOCATION \
    --app-insights $APPINSIGHTS_NAME \
    --runtime dotnet \
    --functions-version 3 \
    -g $RESOURCE_GROUP  \
    --output  none
}

function deployFunction(){
    # publish the code
    az functionapp deployment `
    source config --branch master --manual-integration `
    --name $FUNCTIONAPP_NAME `
    --repo-url https://github.com/jaypaddy/MythicalPGPy `
    --resource-group $RESOURCE_GROUP
}

function applyFunctionAppSettings() {
    echo "${BLUE}Applying App Setings to ${FUNCTIONAPP_NAME}"
    #Create a JSON of all the webapp settings
    appsettingsJSON="[ \
                {
                    \"name\": \"AzureWebJobsStorage\",
                    \"slotSetting\": false,
                    \"value\": \"$FUNCTIONAPP_STORAGE_CONN_STRING\"
                },
                {
                    \"name\": \"IOTHUB_CONN_STRING_CSHARP\",
                    \"slotSetting\": false,
                    \"value\": \"$IOTHUB_CONN_STRING_CSHARP\"
                },
                {
                    \"name\": \"ACRUSER\",
                    \"slotSetting\": false,
                    \"value\": \"$ACRUSER\"
                },            
                {
                    \"name\": \"ACRPASSWORD\",
                    \"slotSetting\": false,
                    \"value\": \"$ACRPASSWORD\"
                },      
                {
                    \"name\": \"ACR\",
                    \"slotSetting\": false,
                    \"value\": \"$ACR\"
                },  
                {
                    \"name\": \"COSMOSACCOUNTNAME\",
                    \"slotSetting\": false,
                    \"value\": \"$COSMOSACCOUNTNAME\"
                },
                {
                    \"name\": \"COSMOSDBNAME\",
                    \"slotSetting\": false,
                    \"value\": \"$COSMOSDBNAME\"
                },
                {
                    \"name\": \"COSMOSENDPOINT\",
                    \"slotSetting\": false,
                    \"value\": \"$COSMOSENDPOINT\"
                },  
                {
                    \"name\": \"COSMOSKEY\",
                    \"slotSetting\": false,
                    \"value\": \"$COSMOSKEY\"
                }, 
                {
                    \"name\": \"COSMOSCONTAINER_ALLMODULES\",
                    \"slotSetting\": false,
                    \"value\": \"allmodules\"
                },    
                {
                    \"name\": \"COSMOSCONTAINER_MANIFEST\",
                    \"slotSetting\": false,
                    \"value\": \"manifest\"
                }
             ]"
    echo $appsettingsJSON > appsettings.json
    az functionapp config appsettings set \
        --name $FUNCTIONAPP_NAME  \
        --resource-group $RESOURCE_GROUP \
        --settings @appsettings.json  \
    --output  none
    
    rm ./appsettings.json

    #Restart Azure Function
    echo "${YELLOW}Restarting ${FUNCTIONAPP_NAME}"
    az functionapp restart --name $FUNCTIONAPP_NAME --resource-group $RESOURCE_GROUP  --output  none
}

function insertManifestAndModuleDocs() {
    echo "${BLUE}Retreiving URL for Function : SetupConfigurationDB"
    # Setup CosmosDB with Starter Documents....
    funcURL=`az functionapp function show -g $RESOURCE_GROUP -n $FUNCTIONAPP_NAME --function-name SetupConfigurationDB | jq .'invokeUrlTemplate'`
    funcURL=`echo $funcURL | tr -d '"'`

    funcKey=`az functionapp function keys list -g $RESOURCE_GROUP -n $FUNCTIONAPP_NAME --function-name SetupConfigurationDB | jq .'default'`
    funcKey=`echo $funcKey | tr -d '"'`
    funcURL="$funcURL?code=$funcKey"
    echo $funcURL


    #Add Manifest Document
    echo "${BLUE}Adding Manifest to CosmosDB via Function:SetupConfigurationDB"
    manifesturl=$funcURL"&coll=man"
    curl -X POST -H "Content-Type: application/json" -d @manifest.json $manifesturl

    #Add Module Document
    echo "${BLUE}Adding Module to CodmosDB via Function:SetupConfigurationDB"
    moduleurl=$funcURL"&coll=mod"
    curl -X POST -H "Content-Type: application/json" -d @SimulatedTempSensor.json $moduleurl 
}


echo "${BLUE}Checking prerequisites."
echo "${BLUE}Checking for az cli"
if ! command -v az &> /dev/null
then
    echo "${RED}azure cli could not be found"
    echo "${RED}Please install azure cli"
    echo "${BLUE}https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
    exit
fi
echo "${BLUE}Checking for jq"
if ! command -v jq &> /dev/null
then
    echo "${RED}jq could not be found"
    echo "${RED}Please install jq"
    echo "${BLUE}https://stedolan.github.io/jq/download/"
    exit
fi

echo "${BLUE}Load inputs."
loadInputs
echo "${YELLOW}Press to continue..."
read input


echo "${BLUE}login with your Corp/Enterprise Azure AD Tenant"
az login --output none 
echo "${YELLOW}Press to continue..."
read input

echo "***************************************************************************************"
echo "This is a bare minimum script with no checks.....so please check all inputs are correct"
echo "***************************************************************************************"

echo "${YELLOW}Press to continue..."
read input

echo "${BLUE}Create Resource Group ${RESOURCE_GROUP}"
createRG
echo "${YELLOW}Press to continue..."
read input

echo "${BLUE}Create CosmosDBwithContainers ${COSMOSACCOUNTNAME}"
dbExists=`az cosmosdb sql database exists \
        --account-name $COSMOSACCOUNTNAME \
        --name $COSMOSDBNAME \
        --resource-group $RESOURCE_GROUP`
if [ $dbExists == true ] ;
then
   echo "${YELLOW}CosmosDB exists, so skipping creation..."
else 
    createCosmosDBwithContainers
fi
echo "${YELLOW}Press to continue..."
read input

echo "${BLUE}Retreive CosmosDB Info for ${COSMOSACCOUNTNAME}"
retreiveCosmosDBkeys
echo "${YELLOW}Press to continue..."
read input

echo "${BLUE}Create Function App ${FUNCTIONAPP_NAME}"
funcAppExists=`az functionapp show --name  $FUNCTIONAPP_NAME --resource-group $RESOURCE_GROUP`
if [ -z "$funcAppExists" ];
then
    createFunctionApp
else 
    echo "${YELLOW}Function App exists, so skipping creation..."
fi
echo "${YELLOW}Press to continue..."
read input

echo "${YELLOW}***************************************************************************"
echo "${BLUE}Deploy Function App ${FUNCTIONAPP_NAME}."
echo "${YELLOW}Please deploy function app from VSCode Command Palette."
echo "${BLUE}https://docs.microsoft.com/en-us/azure/developer/javascript/tutorial/tutorial-vscode-serverless-node-deploy-hosting#:~:text=%20Use%20Visual%20Studio%20Code%20extension%20to%20deploy,Function%20App%20and%20press%20Enter.%20Valid...%20More%20"
echo "${YELLOW}***************************************************************************"
echo "${YELLOW}Press to continue after having deployed the function app..."
read input

echo "${BLUE}Apply App Settings for ${FUNCTIONAPP_NAME}"
applyFunctionAppSettings
echo "${YELLOW}Press to continue..."
read input

echo "${BLUE}Insert Manifest & Module docs for ${FUNCTIONAPP_NAME}"
insertManifestAndModuleDocs
echo ""
echo "${GREEN}Deployment of IoTEdgeCTL is complete."
echo "${GREEN}To use IoTEdgeCTL, deploy PowerTools4IoTEdge or POST a ModuleDesiredPropertiesRoutes document to IoTEdgeCTL/GenerateApplyIoTEdgeManifest"
echo "${YELLOW}Press to continue..."
read input
