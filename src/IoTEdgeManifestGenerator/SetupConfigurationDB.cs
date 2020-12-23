using System;
using System.IO;
using System.Threading.Tasks;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Azure.WebJobs;
using Microsoft.Azure.WebJobs.Extensions.Http;
using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.Logging;
using Newtonsoft.Json;
using System.Collections.Generic;
using System.Linq;
using System.Text.Json;
using Microsoft.Azure.Cosmos;
using System.Diagnostics;
using System.Net;

namespace IoTEdgeConfigurationManager.Manifest
{
    public static class SetupConfigurationDB
    {
        [FunctionName("SetupConfigurationDB")]
        public static async Task<IActionResult> Run(
            [HttpTrigger(AuthorizationLevel.Function, "get", "post", Route = null)] HttpRequest req,
            ILogger log)
        {
            /*
                Accept the following
                query string : coll=man/mod
                body : json
            */

            log.LogInformation("SetupConfigurationDB Triggered.");
            string collName = req.Query["coll"];
            if (string.IsNullOrEmpty(collName))
                return new BadRequestObjectResult("Missing coll in request");
            log.LogInformation($"coll={collName}");

            string requestBody = await new StreamReader(req.Body).ReadToEndAsync();
            if (string.IsNullOrEmpty(requestBody))
                return new BadRequestObjectResult("Missing Body in request");            
            /*
                request can be Manifest or a module
            */
            //Clean up \n 
            requestBody = requestBody.Replace("\\n","");
            //Clean up \"
            requestBody = requestBody.Replace("\\\"","\"");
            //Clean up "{
            requestBody = requestBody.Replace("\"{","{");
            //Clean up }"
            requestBody = requestBody.Replace("}\"","}");


            CosmosClient cosmosClient;
            Database cosmosDatabase;
            string templateColl, moduleColl;
            string cosmosaccountname, cosmosdatabasename, cosmosendpoint, cosmoskey;

            cosmosaccountname = Environment.GetEnvironmentVariable("COSMOSACCOUNTNAME");
            cosmosendpoint = Environment.GetEnvironmentVariable("COSMOSENDPOINT");
            cosmoskey = Environment.GetEnvironmentVariable("COSMOSKEY");
            cosmosdatabasename = Environment.GetEnvironmentVariable("COSMOSDBNAME");
            templateColl = Environment.GetEnvironmentVariable("COSMOSCONTAINER_MANIFEST");
            moduleColl  = Environment.GetEnvironmentVariable("COSMOSCONTAINER_ALLMODULES");

            if (string.IsNullOrEmpty(cosmosaccountname))
                return new BadRequestObjectResult("Missing cosmosaccountname in environment");
            if (string.IsNullOrEmpty(cosmosendpoint))
                return new BadRequestObjectResult("Missing cosmosendpoint in environment");
            if (string.IsNullOrEmpty(cosmoskey))
                return new BadRequestObjectResult("Missing cosmoskey in environment");



            try{
                cosmosClient = new CosmosClient(cosmosendpoint, cosmoskey);
                cosmosDatabase = cosmosClient.GetDatabase(cosmosdatabasename);
                Container cosmosCollection;
                ItemResponse<Object> item;
                Object requestBodyObj = JsonConvert.DeserializeObject<Object>(requestBody);
                if ( collName == "man") {
                    cosmosCollection = cosmosDatabase.GetContainer(templateColl);   
                }
                else if (collName == "mod" ) {
                    cosmosCollection = cosmosDatabase.GetContainer(moduleColl);   
                }
                else {
                    return new BadRequestObjectResult("Invalid coll in request"); 
                }
                item = await cosmosCollection.UpsertItemAsync(requestBodyObj);  
                string responseMessage;
                if ( item.StatusCode == HttpStatusCode.Created ){
                    responseMessage =  $"Hello, Caller. Document inserted into {collName}";
                    return new OkObjectResult(responseMessage);
                }
                else {
                    responseMessage = $"Error Creating configuration data for {collName}";
                    return new BadRequestObjectResult(responseMessage);
                }
            }
            catch (Exception e)
            {
                Console.WriteLine($"{e}");
                log.LogError($"{e}");
                return new BadRequestObjectResult($"{e}");
            }
        }
    }
}
