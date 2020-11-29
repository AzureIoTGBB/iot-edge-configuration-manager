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

namespace IotEdgeConfigurationManager.Manifest
{
    public  class IotEdgeConfigReader 
    {
        private CosmosClient _cosmosClient;
        private Database _cosmosDatabase;
        private string _databaseName;
        private string _templateColl, _moduleColl;

        public static IotEdgeConfigReader CreateWithCosmosDBConn(CosmosClient cosmosClient, string databaseName, string templateColl, string moduleColl){
            //Need Error Handling
            IotEdgeConfigReader configReader = new IotEdgeConfigReader();
            configReader._cosmosClient = cosmosClient;
            configReader._databaseName = databaseName;
            configReader._cosmosDatabase = cosmosClient.GetDatabase(databaseName);
            configReader._templateColl = templateColl;
            configReader._moduleColl = moduleColl;
            return  configReader;
        }
        public  async Task<string> GetIoTEdgeTemplate(){
            Container cosmosCollection = _cosmosClient.GetContainer(_databaseName,_templateColl);
            QueryDefinition query = new QueryDefinition($" SELECT e.modulesContent FROM manifest e");
            FeedIterator<Object> resultSetIterator = cosmosCollection.GetItemQueryIterator<Object>(query);
            {
                while (resultSetIterator.HasMoreResults)
                {
                    FeedResponse<Object> resultList = await resultSetIterator.ReadNextAsync();
                    foreach (Object m in resultList)
                    {
                        string jsonStr =  JsonConvert.SerializeObject(m);
                        Console.WriteLine(jsonStr);
                        return jsonStr;

                    }
                }
            }
            return "";
        }
        public async Task<IDictionary<string,object>> GetModuleConfig(string moduleId){
            Container cosmosCollection = _cosmosClient.GetContainer(_databaseName,_moduleColl);
            QueryDefinition query = new QueryDefinition($" SELECT e.{moduleId} FROM allmodules e WHERE e.moduleid = @moduleId ")
                .WithParameter("@moduleId", moduleId);
            IDictionary<string, object> moduleConfigObjList = new Dictionary<string, object>();
            FeedIterator<Object> resultSetIterator = cosmosCollection.GetItemQueryIterator<Object>(query);
            {
                while (resultSetIterator.HasMoreResults)
                {
                    FeedResponse<Object> resultList = await resultSetIterator.ReadNextAsync();
                    foreach (Object m in resultList)
                    {
                        moduleConfigObjList.Add(moduleId, m);
                    }
                }
            }
            //CosmosDB SDK still uses Newtonsoft, while the current code is with System.Text.Json.... hence the below conversion
            string moduleConfigObjListStr = JsonConvert.SerializeObject(moduleConfigObjList);
            moduleConfigObjList = JsonConvert.DeserializeObject<IDictionary<string,object>>(moduleConfigObjListStr);

            return moduleConfigObjList;

        }
    
    }


}