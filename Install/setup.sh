# Assumptions
# 1. A Resource Group with IoT Hub exists and this depeloyment will use the existing Resource Group where IoTHub resides


# Input Variables
RESOURCE_GROUP="INSTALL_RG"
FUNCTIONAPP_NAME="IoTEdgeCTL"
FUNCTIONAPP_STORAGE_ACCOUNT_NAME="iotedgectlstore"
LOCATION="CentralUS"
APPINSIGHTS_NAME="iotedgectlappinsight"
IOTHUB_NAME="mythicaledge1"
IOTHUB_CONN_STRING_CSHARP="HostName=mythicaledge1.azure-devices.net;SharedAccessKeyName=registryReadWrite;SharedAccessKey=YTgU/mWWzu4X5dUY1umtj76mFNhrLDHRcbMprKvtlnI="
ACRUSER="paddycontainers"
ACRPASSWORD="WjPE2ARO6sAs/ytqEjyLlhmVG7PiuXd1"
ACR="paddycontainers.azurecr.io"
COSMOSACCOUNTNAME="edgeconfiguration"
COSMOSDBNAME="configdb"
COSMOSCONTAINER_ALLMODULES="allmodules"
COSMOSCONTAINER_MANIFEST="manifest"

function createRG() {
    # Create a resource group
    az group create --resource-group $RESOURCE_GROUP --location $LOCATION
}

function createCosmosDBwithContainers(){
    echo "Creating CosmosDB Account ${COSMOSACCOUNTNAME}"
    # Create a Cosmos account for SQL API
    az cosmosdb create \
        --name $COSMOSACCOUNTNAME \
        --resource-group $RESOURCE_GROUP \
        --default-consistency-level Eventual \
        --locations regionName=$LOCATION 
    echo "Press to continue..."
    read input

    # Create a SQL API database
    echo "Creating SQL API Database ${COSMOSDBNAME}"
    az cosmosdb sql database create \
        -a $COSMOSACCOUNTNAME \
        -g $RESOURCE_GROUP \
        -n $COSMOSDBNAME
    echo "Press to continue..."
    read input

    # Define the index policy for the container, include spatial and composite indexes
    # Create a SQL API container for storing Module definitions
    echo "Creating CosmosDB Container ${COSMOSCONTAINER_ALLMODULES}"
    az cosmosdb sql container create \
        -a $COSMOSACCOUNTNAME \
        -g $RESOURCE_GROUP \
        -d $COSMOSDBNAME \
        -n $COSMOSCONTAINER_ALLMODULES \
        -p '/moduleid' \
        --throughput 400 \
        --idx @./idxpolicy.json
    echo "Press to continue..."
    read input

    # Create a SQL API container for storing Manifest definitions
    echo "Creating CosmosDB Container ${COSMOSCONTAINER_MANIFEST}"
    az cosmosdb sql container create \
        -a $COSMOSACCOUNTNAME \
        -g $RESOURCE_GROUP \
        -d $COSMOSDBNAME \
        -n $COSMOSCONTAINER_MANIFEST \
        -p '/version' \
        --throughput 400 \
        --idx @./idxpolicy.json
}

function retreiveCosmosDBkeys(){
     # Get the Keys for CosmosDB
    echo "Retreiving Connection Information for CosmosDB ${COSMOSACCOUNTNAME}"
    COSMOSKEY=`az cosmosdb keys list --name $COSMOSACCOUNTNAME --resource-group $RESOURCE_GROUP  --type keys | jq '.primaryMasterKey'`
    #Remove "
    COSMOSKEY=`echo $COSMOSKEY | tr -d '"'`
    COSMOSINFO=`az cosmosdb show --name $COSMOSACCOUNTNAME --resource-group $RESOURCE_GROUP`
    COSMOSENDPOINT=`echo $COSMOSINFO | jq '.documentEndpoint'`
    COSMOSENDPOINT=`echo $COSMOSENDPOINT | tr -d '"'`

}

function createFunctionApp() {
    echo "Creating Azure Function Storage Account ${FUNCTIONAPP_STORAGE_ACCOUNT_NAME}"
    az storage account create \
    -n $FUNCTIONAPP_STORAGE_ACCOUNT_NAME \
    -g $RESOURCE_GROUP \
    --sku Standard_LRS 
    echo "Press to continue..."
    read input   

    echo "Retreiving Azure Function Storage Account ${FUNCTIONAPP_STORAGE_ACCOUNT_NAME}"
    FUNCTIONAPP_STORAGE_CONN_STRING=`az storage account show-connection-string \
    -g $RESOURCE_GROUP \
    -n $FUNCTIONAPP_STORAGE_ACCOUNT_NAME \
    | jq '.connectionString'`
    #Remove doublequots
    FUNCTIONAPP_STORAGE_CONN_STRING=`echo $FUNCTIONAPP_STORAGE_CONN_STRING | tr -d '"'`
    echo "Press to continue..."
    read input 

    echo "Creating App Insights ${APPINSIGHTS_NAME}"
    az resource create \
    -g $RESOURCE_GROUP -n $APPINSIGHTS_NAME \
    --resource-type "Microsoft.Insights/components" \
    --properties "{\"Application_Type\":\"web\"}"
    echo "Press to continue..."
    read input

    echo "Creating Azure Function App ${FUNCTIONAPP_NAME}"
    az functionapp create \
    -n $FUNCTIONAPP_NAME \
    --storage-account $FUNCTIONAPP_STORAGE_ACCOUNT_NAME \
    --consumption-plan-location $LOCATION \
    --app-insights $APPINSIGHTS_NAME \
    --runtime dotnet \
    --functions-version 3 \
    -g $RESOURCE_GROUP
}

function deployFunction(){
    # publish the code
    az functionapp deployment `
    source config --branch master --manual-integration `
    --name $FUNCTIONAPP_NAME `
    --repo-url https://github.com/jaypaddy/MythicalPGPy `
    --resource-group $RESOURCE_GROUP
    echo "Press to continue..."
    read input
}

function applyFunctionAppSettings() {
    echo "Applying App Setings to ${FUNCTIONAPP_NAME}"
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
        --settings @appsettings.json
    
    rm ./appsettings.json
    echo "Press to continue..."
    read input

    #Restart Azure Function
    echo "Restarting ${FUNCTIONAPP_NAME}"
    az functionapp restart --name $FUNCTIONAPP_NAME --resource-group $RESOURCE_GROUP 
}


function insertManifestAndModuleDocs() {
    echo "Retreiving URL for Function : SetupConfigurationDB"
    # Setup CosmosDB with Starter Documents....
    funcURL=`az functionapp function show -g $RESOURCE_GROUP -n $FUNCTIONAPP_NAME --function-name SetupConfigurationDB | jq .'href'`
    funcURL=`echo $funcURL | tr -d '"'`

    funcKey=`az functionapp keys list -g $RESOURCE_GROUP -n $FUNCTIONAPP_NAME | jq .'functionKeys.default'`
    funcKey=`echo $funcKey | tr -d '"'`
    funcURL="$funcURL?code=$funcKey"
    echo $funcURL

    #Add Manifest Document
    echo "Adding Manifest to CosmosDB via Function:SetupConfigurationDB"
    setupConfigurationDburl="${funcURL}code=${funcKey}"
    manifesturl=$setupConfigurationDburl"&coll=man"
    echo $manifesturl
    curl -X POST -H "Content-Type: application/json" -d @manifest.json $manifesturl

    #Add Module Document
    echo "Adding Module to CodmosDB via Function:SetupConfigurationDB"
    setupConfigurationDburl="${funcURL}code=${funcKey}"
    moduleurl=$setupConfigurationDburl"&coll=mod"
    echo $moduleurl
    curl -X POST -H "Content-Type: application/json" -d @SimulatedTempSensor.json $moduleurl 
}

echo "login with your Corp/Enterprise Azure AD Tenant"
az login  
echo "Press to continue..."
read input

echo "***************************************************************************************"
echo "This is a bare minimum script with no checks.....so please check all inputs are correct"
echo "***************************************************************************************"

echo "Press to continue..."
read input

echo "Create Resource Group ${RESOURCE_GROUP}"
createRG
echo "Press to continue..."
read input

echo "Create CosmosDBwithContainers ${COSMOSACCOUNTNAME}"
dbExists=`az cosmosdb sql database exists \
        --account-name $COSMOSACCOUNTNAME \
        --name $COSMOSDBNAME \
        --resource-group $RESOURCE_GROUP`
if [ $dbExists ] ;
then
   echo "CosmosDB exists, so skipping creation..."
else 
    createCosmosDBwithContainers
fi
echo "Press to continue..."
read input

echo "Retreive CosmosDB Info for ${COSMOSACCOUNTNAME}"
retreiveCosmosDBkeys
echo "Press to continue..."
read input


echo "Create Function App ${FUNCTIONAPP_NAME}"
funcAppExists=`az functionapp show --name  $FUNCTIONAPP_NAME --resource-group $RESOURCE_GROUP`
if [ -z "$funcAppExists" ];
then
    createFunctionApp
else 
    echo "Function App exists, so skipping creation..."
fi
echo "Press to continue..."
read input

echo "Deploy Function App ${FUNCTIONAPP_NAME}"
echo "This step attempts to deploy the function. You can choose manual deployment and deploy it from VSCode manually."
read -p "Type m for manual deployment or g for git deployment:" DEPTYPE
if [ $DEPTYPE == "m" ];
then
    echo "Please open VSCode and deploy the function to $FUNCTIONAPP_NAME...."
else
    echo "git deployment not implemented"
    echo "fix deployFunction()"
fi
echo "Press to continue..."
read input

echo "Apply App Settings for ${FUNCTIONAPP_NAME}"
applyFunctionAppSettings
echo "Press to continue..."
read input

echo "Insert Manifest & Module docs for ${FUNCTIONAPP_NAME}"
insertManifestAndModuleDocs
echo "Press to continue..."
read input





