using System;
using System.IO;
using System.Threading.Tasks;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Azure.WebJobs;
using Microsoft.Azure.WebJobs.Extensions.Http;
using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.Logging;
using Newtonsoft.Json;
using Microsoft.Azure.Devices;
using Microsoft.Azure.Devices.Shared;
using System.Collections.Generic;
using Microsoft.Azure.Cosmos;

namespace IotEdgeConfigurationManager.Manifest
{

    public class DeployToIoTEdge
    {
        private readonly ILogger<DeployToIoTEdge> _log;

        private static CosmosClient _cosmosClient;
        private static RegistryManager _registryManager;

        public DeployToIoTEdge(ILogger<DeployToIoTEdge> log)
        {
            _log = log;
        }
        [FunctionName("GenerateIoTEdgeManifest")]
        public async Task<IActionResult> Run(
            [HttpTrigger(AuthorizationLevel.Function, "get", "post", Route = null)] HttpRequest req)
        {
            _log.LogInformation("C# HTTP trigger.");
            string deviceid = req.Query["deviceid"];
            
            if (string.IsNullOrEmpty(deviceid))
                return new BadRequestObjectResult("Missing deviceid in request");


            string requestBody = await new StreamReader(req.Body).ReadToEndAsync();
            /*
                [
                    {
                        "ModuleInstanceName": "ModuleA",
                        "Module": "lvaEdge",
                        "ToIoThub": true,
                        "DesiredProperties": "{\"NAME\":\"MODULEA\"}",
                        "RouteInstanceName": "A1toIoTHub",
                        "FromModule": "lvaEdge",
                        "ToModule": null,
                        "FromChannel": "ONE",
                        "ToChannel": null
                    }
                ]
                1. Remove \n
                2. Convert \" to "
                3. Convert \"{ to {
                4. Convert \"} to }
                5. Convert from Array into Json Doc
            */

            //Clean up \n 
            requestBody = requestBody.Replace("\\n","");
            //Clean up \"
            requestBody = requestBody.Replace("\\\"","\"");
            //Clean up "{
            requestBody = requestBody.Replace("\"{","{");
            //Clean up }"
            requestBody = requestBody.Replace("}\"","}");

            _log.LogInformation(requestBody);
            //Load as  List of Objects
            List<ModuleDesiredPropertiesRoutes> mdprInstances = JsonConvert.DeserializeObject<List<ModuleDesiredPropertiesRoutes>>(requestBody);

            string s_connectionString = Environment.GetEnvironmentVariable("IOTHUB_CONN_STRING_CSHARP");
            string s_acruser = Environment.GetEnvironmentVariable("ACRUSER");
            string s_acrpassword = Environment.GetEnvironmentVariable("ACRPASSWORD");
            string s_acr = Environment.GetEnvironmentVariable("ACR");

            string s_cosmosendpoint = Environment.GetEnvironmentVariable("COSMOSENDPOINT");
            string s_cosmoskey = Environment.GetEnvironmentVariable("COSMOSKEY");
            string s_cosmosAccountName = Environment.GetEnvironmentVariable("COSMOSACCOUNTNAME");

            //Connect to IoTHub
            _registryManager = RegistryManager.CreateFromConnectionString(s_connectionString);
            //Connect to CosmosDB for Modules and Manifest information - IoTEdge Configuration 
            _cosmosClient = new CosmosClient(s_cosmosendpoint, s_cosmoskey);

            IotEdgeConfigReader cosmosDBConfigReader = IotEdgeConfigReader.CreateWithCosmosDBConn(_cosmosClient,
                                        s_cosmosAccountName,
                                        Environment.GetEnvironmentVariable("COSMOSCONTAINER_MANIFEST"),
                                        Environment.GetEnvironmentVariable("COSMOSCONTAINER_ALLMODULES"));
            string iotEdgeTemplateJSON = await cosmosDBConfigReader.GetIoTEdgeTemplate();
            //Replace $ACRUSER $ACRPASSWORD $ACR
            iotEdgeTemplateJSON = iotEdgeTemplateJSON.Replace("$ACRUSER",s_acruser).Replace("$ACRPASSWORD",s_acrpassword).Replace("$ACR",s_acr);
            
            
            IoTEdgeCTL iotedgeCTL = new IoTEdgeCTL(_registryManager, cosmosDBConfigReader);
            ConfigurationContent iotEdgeConfigContent = await iotedgeCTL.GenerateManifestConfigContent(iotEdgeTemplateJSON,mdprInstances, _log);
            string responseMessage;
            if ( iotEdgeConfigContent == null )
            {
                responseMessage = $"Error Generating ConfigurationContent for {deviceid} - {iotedgeCTL.GetErrMsg()}";
                return new BadRequestObjectResult(responseMessage);
            }

            var bRet = await iotedgeCTL.ApplyManifestConfigContent(deviceid, iotEdgeConfigContent, _log);
            if (bRet)
            {
                responseMessage =  $"Hello, Caller. This HTTP triggered function executed successfully for {deviceid}";
                return new OkObjectResult(responseMessage);
            }
            else{
                responseMessage = $"Error Applying ConfigurationContent for  {deviceid} - {iotedgeCTL.GetErrMsg()}";
                return new BadRequestObjectResult(responseMessage);
            }

        }
    }

}
