using System;
using System.IO;
using System.Threading.Tasks;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Azure.WebJobs;
using Microsoft.Azure.WebJobs.Extensions.Http;
using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.Logging;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;
using System.Collections.Generic;
using System.Linq;
using System.Text.Json;
using Microsoft.Azure.Cosmos;
using System.Diagnostics;
using Microsoft.Azure.Devices;
using Microsoft.Azure.Devices.Shared;


namespace IotEdgeConfigurationManager.Manifest
{
    public class IoTEdgeCTL
    {

        private readonly RegistryManager _registryManager;
        private readonly IotEdgeConfigReader _iotedgeConfigReader;
        // Maximum number of elements per query.
        private const int QueryPageSize = 100;
        private string _errMsg ="";

        public string GetErrMsg(){
            return _errMsg;
        }
        public IoTEdgeCTL(RegistryManager registryManager, IotEdgeConfigReader configReader)
        {
            //Need to build a better class setupfor injecting the dependents 
            _registryManager = registryManager ?? throw new ArgumentNullException(nameof(registryManager));
            _iotedgeConfigReader = configReader ?? throw new ArgumentNullException(nameof(configReader));
        }
        
        private async Task<IDictionary<String,Object>> BuildModuleDefinitionDICT( List<ModuleDesiredPropertiesRoutes> requestMDPR, ILogger log)
        {
            IDictionary<string,object> moduleDefinitionDICT = new Dictionary<string,object>();   
            foreach (ModuleDesiredPropertiesRoutes instanceMDPR in requestMDPR)
            {
                //Get the Module Definition
                IDictionary<string,object> moduleConfigCMDB = await _iotedgeConfigReader.GetModuleConfig(instanceMDPR.Module);
                string moduleConfigCMDBstr = JsonConvert.SerializeObject(moduleConfigCMDB[instanceMDPR.Module]);
                moduleConfigCMDB = JsonConvert.DeserializeObject<IDictionary<string, object>>(moduleConfigCMDBstr);   
                //Replace Key in moduleConfigCMDB with ModuleInstanceName as specified in the Request
                moduleConfigCMDB.Add(instanceMDPR.ModuleInstanceName,moduleConfigCMDB[instanceMDPR.Module]);
                moduleConfigCMDB.Remove(instanceMDPR.Module);
                moduleDefinitionDICT.Add(instanceMDPR.ModuleInstanceName,moduleConfigCMDB[instanceMDPR.ModuleInstanceName]);  
            }
            return moduleDefinitionDICT;
        }
        private IDictionary<String,Object> BuildDesiredPropertiesDICT(List<ModuleDesiredPropertiesRoutes> requestMDPR, ILogger log)
        {
            IDictionary<string,object> modulesDesiredPropertiesDICT = new Dictionary<string,object>();   
            foreach (ModuleDesiredPropertiesRoutes instanceMDPR in requestMDPR)
            {
                    //Next is applying  Desired  Properties for each module
                    string mdprDPJSON = JsonConvert.SerializeObject(instanceMDPR.DesiredProperties);
                    //The moduleInstanceconfig now contains 2 Keys - "properties.desired" & "routes"
                    //Extract properties.desired
                    //construct properties.desired object
                    string desiredPropertiesJSON = $"{{\"properties.desired\":{mdprDPJSON}}}";
                    Object desiredPropertiesObj  = JsonConvert.DeserializeObject(desiredPropertiesJSON);
                    modulesDesiredPropertiesDICT.Add(instanceMDPR.ModuleInstanceName,desiredPropertiesObj);            
            }
            return modulesDesiredPropertiesDICT;        
        }
        private IDictionary<String,Object> GenerateEdgeHub(IDictionary<string,object> modulesContentManifestTemplateObj, List<ModuleDesiredPropertiesRoutes> requestMDPR, ILogger log){
                //Attach ROUTES
                /*{
                        "PySendModuleToIoTHub": "FROM /messages/modules/PySendModule/outputs/* INTO $upstream",
                        "LVAToHub": "FROM /messages/modules/lvaEdge/outputs/* INTO $upstream",
                        "sensorToPySendModule": "FROM /messages/modules/SimulatedTemperatureSensor/outputs/temperatureOutput INTO BrokeredEndpoint(\"/modules/PySendModule/inputs/input1\")",
                        "factoryaiToIoTHub": "FROM /messages/modules/factoryai/outputs/* INTO $upstream"
                }*/
                //Loop through request to extract routes

                string routeFrom="", routeTo="", routes="";
                foreach (ModuleDesiredPropertiesRoutes instanceMDPR in requestMDPR)
                {
                    //Form the Routes
                    foreach(ModuleRoute r in instanceMDPR.Routes) 
                    {
                        routeFrom = String.Format("\"{0}\":\"FROM /messages/modules/{1}/outputs/{2}",r.RouteInstanceName, r.FromModule, r.FromChannel);
                        if (r.ToIoThub) {
                            routeTo = $" INTO $upstream\"";
                        } else
                        {
                            routeTo = String.Format(" INTO BrokeredEndpoint(\\\"/modules/{0}/inputs/{1}\\\")\"",r.ToModule,r.ToChannel);
                        }
                        if  (routes.Length > 0)
                            routes = routes + ",\n" + $"{routeFrom}{routeTo}";
                        else
                            routes = routes + "\n" + $"{routeFrom}{routeTo}";
                    }
                }
                routes = $"{{ {routes} }}";
                //Transform $edgeHub 
                //Extract $edgeHub from modulesContentManifestTemplate
                string edgeHubObjStr = JsonConvert.SerializeObject(modulesContentManifestTemplateObj["$edgeHub"]);
                IDictionary<string,object> edgeHubObj = JsonConvert.DeserializeObject<IDictionary<string,object>>(edgeHubObjStr);
                //Extract properties.desired for $edgeHub from modulesContentManifestTemplate
                string edgeHubDesiredPropertiesObjStr = JsonConvert.SerializeObject(edgeHubObj["properties.desired"]);
                IDictionary<string,object> edgeHubDesiredPropertiesObj = JsonConvert.DeserializeObject<IDictionary<string,object>>(edgeHubDesiredPropertiesObjStr);
                string routesObjStr = JsonConvert.SerializeObject(edgeHubDesiredPropertiesObj["routes"]);
                //Replace routes in properties.desired for $edgeHub with routes from input
                edgeHubDesiredPropertiesObj["routes"] = JsonConvert.DeserializeObject(routes);
                return edgeHubObj;

        }
        private IDictionary<String,Object> GenerateEdgeAgent(IDictionary<string,object> modulesContentManifestTemplateObj, IDictionary<String,Object> moduleDefinitionDICT, ILogger log)
        {
            //Transform $edgeAgent 
            string edgeAgentTemplateObjStr = JsonConvert.SerializeObject(modulesContentManifestTemplateObj["$edgeAgent"]);
            IDictionary<string,object> edgeAgentTemplateDesiredPropertiesObj = JsonConvert.DeserializeObject<IDictionary<string,object>>(edgeAgentTemplateObjStr);
            string edgeAgentTemplateDesiredPropertiesObjStr = JsonConvert.SerializeObject(edgeAgentTemplateDesiredPropertiesObj["properties.desired"]);
            /*
            $edgeAgent segment of the JSON contains the following
            "$edgeAgent": {
                "properties.desired": {
                    "schemaVersion": "1.0",
                    "runtime": {},
                    "systemModules": {},
                    "modules": {}
                }
            }
            */
            //Add modules to $edgeAgent properties.desired
            //These are the modules that need to be scheduled on IoT Edge 
            IDictionary<string,object> modulesTemplateObj = JsonConvert.DeserializeObject<IDictionary<string,object>>(edgeAgentTemplateDesiredPropertiesObjStr);
            //Replace modulesObj["modules"] with moduleDefinition Dictionary built from CMDB
            modulesTemplateObj["modules"] = (object) moduleDefinitionDICT;
            edgeAgentTemplateDesiredPropertiesObj["properties.desired"] = modulesTemplateObj;
            //Apply to the Manifest Template, we continue to build ModulesContentManifesTemplate
            return edgeAgentTemplateDesiredPropertiesObj;
        }
        private IDictionary<String,Object> GenerateModuleTwins(IDictionary<string,object> modulesContentManifestTemplateObj, IDictionary<String,Object> modulesDesiredPropertiesDICT, ILogger log){
            foreach (var m in modulesDesiredPropertiesDICT)
            {
                modulesContentManifestTemplateObj.Add(m.Key,m.Value);
            }   
            return modulesContentManifestTemplateObj;
        }
        private ConfigurationContent AssembleConfigurationContent(IDictionary<string,object> modulesContentManifestTemplateObj, ILogger log)
        {
            IDictionary<string, IDictionary<string,object>> modulesContentConfigContent = new Dictionary<string, IDictionary<string,object>>();
            foreach (var item in modulesContentManifestTemplateObj)
            {
                string valueStr = JsonConvert.SerializeObject(modulesContentManifestTemplateObj[item.Key]);
                IDictionary<string,object> valueObj = JsonConvert.DeserializeObject<IDictionary<string,object>>(valueStr);
                modulesContentConfigContent.Add(item.Key,valueObj);
            }

            ConfigurationContent modConfigContent = new ConfigurationContent
            {
                ModulesContent = modulesContentConfigContent
            }; 
            return modConfigContent;
        }
    

        /*Query Devices upto QueryPageSize*/
        public async Task<IDictionary<string, Twin>> GetDevicesByTagFilter(string tagFilter) {

            IDictionary<string,Twin> devices = new Dictionary<string,Twin>();

            try {
                tagFilter = tagFilter ?? throw new ArgumentNullException(nameof(tagFilter));
                //Query for the given devices
                string query = $"select * From devices where {tagFilter}";
                var queryResults = _registryManager.CreateQuery(query, QueryPageSize);
                while (queryResults.HasMoreResults)
                {
                    IEnumerable<Twin> twins = await queryResults.GetNextAsTwinAsync().ConfigureAwait(false);
                    foreach (Twin twin in twins)
                    {
                        devices.Add(twin.DeviceId,twin);
                    }
                }
            }
            catch (Exception e)
            {
                Console.WriteLine($"{e}");
            }

            return devices;
        }

        /*Query Devices - Not Designed for Large Datasets*/
        /* To be updated for large datasets */
        public async Task<IDictionary<string, Twin>> GetAllDevices() {

            IDictionary<string,Twin> devices = new Dictionary<string,Twin>();

            try {
                //Query for the given devices
                string query = $"select * From devices";
                var queryResults = _registryManager.CreateQuery(query, QueryPageSize);
                while (queryResults.HasMoreResults)
                {
                    IEnumerable<Twin> twins = await queryResults.GetNextAsTwinAsync().ConfigureAwait(false);
                    foreach (Twin twin in twins)
                    {
                        devices.Add(twin.DeviceId,twin);
                    }
                }
            }
            catch (Exception e)
            {
                Console.WriteLine($"{e}");
            }

            return devices;
        }


        public async Task<ConfigurationContent> GenerateManifestConfigContent(string manifestTemplate, List<ModuleDesiredPropertiesRoutes> requestMDPR, ILogger log){   
            log.LogInformation("Generate IoTEdge Manifest...");
            ConfigurationContent modConfigContent=null;
            try {

                //Read the entire manifestTemplate
                log.LogInformation($"Reading Manifest Template");
                IDictionary<string,object> manifestTemplateObj = JsonConvert.DeserializeObject<IDictionary<string,object>>(manifestTemplate);
                //What we essentially have is Dict<"ModulesContent",Object>
                string modulesContentManifestTemplateObjStr = JsonConvert.SerializeObject(manifestTemplateObj["modulesContent"]);
                IDictionary<string,object> modulesContentManifestTemplateObj = JsonConvert.DeserializeObject<IDictionary<string,object>>(modulesContentManifestTemplateObjStr);


                log.LogInformation($"Composing Modules & DesiredProperties DICT");
                IDictionary<string,object> modulesDesiredPropertiesDICT = this.BuildDesiredPropertiesDICT(requestMDPR,log);
                IDictionary<string,object> moduleDefinitionDICT = await this.BuildModuleDefinitionDICT(requestMDPR,log);  
                log.LogInformation($"Built Modules & DesiredProperties DICT");

                
                
                //EdgeAgent with Module Definition
                log.LogInformation($"Generating $edgeAgent modules");
                modulesContentManifestTemplateObj["$edgeAgent"] = this.GenerateEdgeAgent(modulesContentManifestTemplateObj,moduleDefinitionDICT,log);

                //EdgeHub with Routes
                log.LogInformation($"Generating $edgeHub routes");
                modulesContentManifestTemplateObj["$edgeHub"] = this.GenerateEdgeHub(modulesContentManifestTemplateObj,requestMDPR,log);

                //Module Twins
                log.LogInformation($"Generating Module Twins");
                modulesContentManifestTemplateObj = this.GenerateModuleTwins(modulesContentManifestTemplateObj,modulesDesiredPropertiesDICT,log );

                //Generate ConfigurationContent (modulesContent)
                modConfigContent = this.AssembleConfigurationContent(modulesContentManifestTemplateObj,log);


            }
            catch (Exception e)
            {
                log.LogInformation(e.Message);
                _errMsg = e.Message;
                return null;
            }
            return modConfigContent;
        }
    
        public async Task<Boolean> ApplyManifestConfigContent(string deviceid, ConfigurationContent  manifestConfigContent,  ILogger log){   
        log.LogInformation("Generate IoTEdge Manifest...");
        try {
            deviceid = deviceid ?? throw new ArgumentNullException(nameof(deviceid));
            Device targetDevice = await _registryManager.GetDeviceAsync(deviceid);
            //Check if the Device exists
            targetDevice = targetDevice ?? throw new ArgumentNullException(nameof(targetDevice));

            var modOnConfigTask =  _registryManager.ApplyConfigurationContentOnDeviceAsync(deviceid,manifestConfigContent);
            await Task.WhenAll(modOnConfigTask).ConfigureAwait(false);
        }
        catch (Exception e)
        {
            log.LogInformation(e.Message);
            _errMsg = e.Message;
            return false;
        }
        return true;
    }

    }


     public  class ModuleRoute {
        public string RouteInstanceName { get; set; } 
        public string FromModule { get; set; } 
        public string ToModule { get; set; } 
        public string FromChannel { get; set; } 
        public string ToChannel { get; set; } 
        public bool ToIoThub { get; set; } 
     }

     public  class ModuleDesiredPropertiesRoutes {
        public string ModuleInstanceName { get; set; } 
        public string Module { get; set; } 
        public Object DesiredProperties { get; set; }  
        public List<ModuleRoute> Routes { get; set; } 

    }
}