//checking quotas
var perEnv = "environment.maxnodescount",
    maxEnvs = "environment.maxcount",
    perNodeGroup = "environment.maxsamenodescount";
    maxCloudletsPerRec = "environment.maxcloudletsperrec";
    diskIOPSlimit = "disk.iopslimit";
var envsCount = jelastic.env.control.GetEnvs({lazy: true}).infos.length,
    nodesPerProdEnv = 8,
    nodesPerProdEnvWOStorage = 7,
    nodesPerDevEnv = 3,
    nodesPerDevEnvWOStorage = 2,
    nodesPerMasterNG = 3,
    nodesPerWorkerNG = 2,
    maxCloudlets = 16,
    iopsLimit = 1000,
    markup = "", cur = null, text = "used", prod = true, dev = true, prodStorage = true, devStorage = true, storage = false;

var quotas = jelastic.billing.account.GetQuotas(perEnv + ";"+maxEnvs+";" + perNodeGroup + ";" + maxCloudletsPerRec + ";" + diskIOPSlimit).array;
var group = jelastic.billing.account.GetAccount(appid, session);
for (var i = 0; i < quotas.length; i++){
    var q = quotas[i], n = toNative(q.quota.name);

    if (n == maxEnvs && envsCount >= q.value){
        err(q, "already used", envsCount, true);
        prod = dev = false; break;
    }

    if (n == maxCloudletsPerRec && maxCloudlets > q.value){
        err(q, "required", maxCloudlets, true);
        prod = dev = false;
    }
    
     if (n == diskIOPSlimit && iopsLimit > q.value){
        err(q, "required", iopsLimit, true);
        prod = dev = false;
    }

    if (n == perEnv && nodesPerDevEnvWOStorage > q.value){
        if (!markup) err(q, "required", nodesPerDevEnvWOStorage, true);
        prod = dev = false;
    }

    if (n == perEnv && nodesPerDevEnvWOStorage  == q.value) devStorage = false;

    if (n == perEnv && nodesPerProdEnvWOStorage > q.value){
        if (!markup) err(q, "required", nodesPerProdEnvWOStorage);
        prod = false;
    }

    if (n == perEnv && nodesPerProdEnvWOStorage  == q.value) prodStorage = false;

    if (n == perNodeGroup && nodesPerMasterNG > q.value){
        if (!markup) err(q, "required", nodesPerMasterNG);
        prod = false;
    }

    if (n == perNodeGroup && nodesPerWorkerNG > q.value){
        if (!markup) err(q, "required", nodesPerWorkerNG);
        prod = false;
    }
}
var resp = {result:0};
var url = "https://raw.githubusercontent.com/jelastic-jps/kubernetes/v1.17.4/configs/settings.yaml";
resp.settings = toNative(new org.yaml.snakeyaml.Yaml().load(new com.hivext.api.core.utils.Transport().get(url)));
var f = resp.settings.fields;

if (!prod && !dev){
    for (var i = 0; i < f.length; i++) f[i].disabled = true;
    f[3].hidden = false;
    f[3].disabled = false;
    f[3].markup =  "Production and Development topologies are not available. " + markup + "Please upgrade your account.";
    f[3].height =  60;
    f[6].value = false;

    f.push({
        "type": "compositefield",
        "height": 0,
        "hideLabel": true,
        "width": 0,
        "items": [{
            "height": 0,
            "type": "string",
            "required": true,
        }]
    });
}

if (!prod && dev){
    f[2].values[1].disabled = true;
    f[3].hidden = false;
    f[3].markup =  "Production topology is not available. " + markup + "Please upgrade your account.";
    f[3].height =  50;
    if (!devStorage){
        f[6].disabled = true;
        f[6].value = false;
    }
}

if (prod && !prodStorage){
    f[6].disabled = true;
    f[6].value = false;
}

if (group.groupType == 'trial') {
    f[6].showIf['true'].unshift({
      type: "displayfield",
      cls: "warning",
      height: 30,
      hideLabel: true,
      markup: "Additional components are not available for " + group.groupType + " account. Please upgrade your account."
    });
    f[6].showIf['true'][1].disabled = true;
    f[6].showIf['true'][2].disabled = true;
}

return resp;

function err(e, text, cur, override){
  var m = (e.quota.description || e.quota.name) + " - " + e.value + ", " + text + " - " + cur + ". ";
  if (override) markup = m; else markup += m;
}
