# IoT Deployment Manifest Generator

**Table of contents**
- [Overview](#solution-need)
- [Deploying a Workload using the REST API](#solution-architecture)
- [Understanding the sample data, calculations, and dashboard elements](#understanding-the-sample-data-calculations-and-dashboard-elements)
- [Deploying the sample](#deploying-the-sample)

## Overview
An IoTEdge deployment manifest is a JSON document that describes:

Adapted from [link](https://docs.microsoft.com/en-us/azure/iot-edge/module-composition?view=iotedge-2018-06):

1. The IoT Edge agent module twin, which includes three components:
    - The container image for each module that runs on the device.
    - The credentials to access private container registries that contain module images.
    - Instructions for how each module should be created and managed.
2. The IoT Edge hub module twin, which includes how messages flow between modules and eventually to IoT Hub.
3. The desired properties of any additional module twins (optional). 

```json
{
  "modulesContent": {
    "$edgeAgent": { // required
      "properties.desired": {
        // desired properties of the IoT Edge agent
        // includes the image URIs of all deployed modules
        // includes container registry credentials
      }
    },
    "$edgeHub": { //required
      "properties.desired": {
        // desired properties of the IoT Edge hub
        // includes the routing information between modules, and to IoT Hub
      }
    },
    "module1": {  // optional
      "properties.desired": {
        // desired properties of module1
      }
    },
    "module2": {  // optional
      "properties.desired": {
        // desired properties of module2
      }
    }
  }
}
```


## Solution architecture

The solution consists of the following components:

1. CosmosDB Database with 2 collections\containers
  - manifest - a single document that defines the template for Edge Manifest
  - allmodules - the listing of all modules and its definition
2. A single Azure Functions Project that contains the following Azure Function
  - HttpTrigger : DeployToIoTEdge

![Diagram showing the rest api architecture](../../media/restapiflow.png)



## Understanding the REST API
The REST API consists of the following Classes.

* DeployToIoTEdge : This class forms the Azure Function with httpTrigger. Accepts as input a JSON document that represents {Modules, Desired Properties & Routes}. This function in turn createes supporting objects for the generation and depeloyment of IoT Edge Manifest
* IoTEdgeConfigReader : A simple abstraction to read documents from CosmosDB. 
* IoTEdgeCTL : The core class that generates the Manifest as per the request and applies the manifest to IoT Edge.

## Deploying the sample
* CosmosDB
  - Create a CosmosDB Account
  - Create a CosmosDB Database
  - Create a CosmosDB collection named "manifest" with partitionkey : /version
  - Create a CosmosDB collection named "allmodules" with partitionkey : /moduleid 
  - Add an item to "manifest" collection in CosmosDB with 2 elements "version" and "modulesContent" 
  ```json
      "version": "1.0",
      "modulesContent": {
          "$edgeAgent": {
              "properties.desired": {
                  "schemaVersion": "1.0",
                  "runtime": {
                      "type": "docker",
                      "settings": {
                          "minDockerVersion": "v1.25",
                          "loggingOptions": "",
                          "registryCredentials": {
                              "default": {
                                  "username": "{$ACRUSER}",
                                  "password": "{$ACRPASSWORD}",
                                  "address": "{$ACR}"
                              }
                          }
                      }
                  },
                  "systemModules": {
                      "edgeAgent": {
                          "type": "docker",
                          "settings": {
                              "image": "mcr.microsoft.com/azureiotedge-agent:1.0.10",
                              "createOptions": "{}"
                          }
                      },
                      "edgeHub": {
                          "type": "docker",
                          "status": "running",
                          "restartPolicy": "always",
                          "settings": {
                              "image": "mcr.microsoft.com/azureiotedge-hub:1.0.10",
                              "createOptions": "{\"HostConfig\":{\"PortBindings\":{\"5671/tcp\":[{\"HostPort\":\"5671\"}],\"8883/tcp\":[{\"HostPort\":\"8883\"}],\"443/tcp\":[{\"HostPort\":\"443\"}]}}}"
                          }
                      }
                  },
                  "modules": {}
              }
          },
          "$edgeHub": {
              "properties.desired": {
                  "schemaVersion": "1.0",
                  "routes": {},
                  "storeAndForwardConfiguration": {
                      "timeToLiveSecs": 7200
                  }
              }
          }
      }
  ```
  - Add items to "allmodules" collection in CosmosDB with 2 elements "moduleid" and definition of the module
  ```json
      "moduleid": "lvaEdge",
      "lvaEdge": {
          "version": "1.0",
          "type": "docker",
          "status": "running",
          "restartPolicy": "always",
          "settings": {
              "image": "mcr.microsoft.com/media/live-video-analytics:1",
              "createOptions": "{\"HostConfig\":{\"LogConfig\":{\"Type\":\"\",\"Config\":{\"max-size\":\"10m\",\"max-file\":\"10\"}},\"Binds\":[\"/Users/jaypaddy/lva/lvaadmin/samples/output:/var/media/\",\"/Users/jaypaddy/lva/local/mediaservices:/var/lib/azuremediaservices/\"]}}"
          }
      }
  ``` 

* Azure Function
  - Create a Resource Group
  - Deploy Azure Function DeployToIoTEdge 
  - Update Application Settings with appropriate environment variables as defined in local.settings.json
    - "AzureWebJobsStorage": "<CONNECTION STRING>"
    - "IOTHUB_CONN_STRING_CSHARP": "<IOT HUB SERVICE CONNECTIONSTRING>"
    - "ACRUSER": "<AZURE CONTAINER REGISTRY USER NAME>"
    - "ACRPASSWORD": "<AZURE CONTAINER REGISTRY PASSWORD>"
    - "ACR": "<AZURE CONTAINER REGISTRY SERVER>"
    - "COSMOSENDPOINT": "<COSMOSDB ACCOUNT URI>"
    - "COSMOSKEY": "<COSMOSDB ACCOUNT KEY>"
    - "COSMOSDATABASEID": "<COSMOSDB DATABASE NAME>"
    - "COSMOSCONTAINER_ALLMODULES": "<COSMOSDB ALLMODULES COLLECTION NAME>"
    - "COSMOSCONTAINER_MANIFEST": "<COSMOSDB MANIFEST COLLECTION NAME>"



* Sample Request to Azure Function HTTPTrigger (please replace with your modules as mentioned in CosmosDB collection)
```json
[
  {
    "ModuleInstanceName": "CameraA",
    "Module": "lvaEdge",
    "DesiredProperties": "{\"applicationDataDirectory\": \"/var/lib/azuremediaservices\",\"azureMediaServicesArmId\": \"/subscriptions/XXXXXXXX-d417-4791-b2a9-XXXXXXXXXXXX/resourceGroups/lva-resources/providers/microsoft.media/mediaservices/lva\",\"aadTenantId\": \"XXXXXXXX-86f1-41af-91ab-XXXXXXXXXXXX\",\"aadServicePrincipalAppId\": \"XXXXXXXX-9ebd-4e16-a1f3-XXXXXXXXXXXX\",\"aadServicePrincipalSecret\": \"XXXXXXXX-fb0e-4dac-b49a-XXXXXXXXXXXX\",\"aadEndpoint\": \"https://login.microsoftonline.com\",\"aadResourceId\": \"https://management.core.windows.net/\",\"armEndpoint\": \"https://management.azure.com/\",\"diagnosticsEventsOutputName\": \"AmsDiagnostics\",\"operationalEventsOutputName\": \"AmsOperational\",\"logLevel\": \"Information\",\"logCategories\": \"Application,Events\",\"allowUnsecuredEndpoints\": true,\"telemetryOptOut\": false}",
    "Routes": [
      {
        "RouteInstanceName": "CameraAtoIoTHub",
        "FromModule": "CameraA",
        "ToModule": null,
        "FromChannel": "*",
        "ToChannel": null,
        "ToIoThub": true
      },
      {
        "RouteInstanceName": "CameraAtoCustomVision",
        "FromModule": "CameraA",
        "ToModule": "CustomVision",
        "FromChannel": "*",
        "ToChannel": "tempin",
        "ToIoThub": false
      }
    ]
  },
  {
    "ModuleInstanceName": "TempSensor2",
    "Module": "SimulatedTemperatureSensor",
    "DesiredProperties": "{\"name\":\"pysender\"}",
    "Routes": [
      {
        "RouteInstanceName": "PySenderToIoThub",
        "FromModule": "TempSensor2",
        "ToModule": null,
        "FromChannel": "triggerout",
        "ToChannel": null,
        "ToIoThub": true
      }
    ]
  }
]
```


