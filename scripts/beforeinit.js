//checking quotas
var perEnv = "environment.maxnodescount",
    maxEnvs = "environment.maxcount",
    perNodeGroup = "environment.maxsamenodescount",
    maxCloudletsPerRec = "environment.maxcloudletsperrec",
    diskIOPSlimit = "disk.iopslimit",
    envsCount = jelastic.env.control.GetEnvs({lazy: true}).infos.length,
    nodesPerProdEnv = 10,
    nodesPerProdEnvWOStorage = 7,
    nodesPerDevEnv = 3,
    nodesPerDevEnvWOStorage = 2,
    nodesPerCplaneNG = 3,
    nodesPerWorkerNG = 2,
    maxCloudlets = 16,
    iopsLimit = 1000,
    markup = "", cur = null, text = "used", prod = true, dev = true, prodStorage = true, devStorage = true, storage = false;

var hasCollaboration = (parseInt('${fn.compareEngine(7.0)}', 10) >= 0),
    quotas = [], group;

if (hasCollaboration) {
    quotas = [
        { quota : { name: perEnv }, value: parseInt('${quota.environment.maxnodescount}', 10) },
        { quota : { name: maxEnvs }, value: parseInt('${quota.environment.maxcount}', 10) },
        { quota : { name: perNodeGroup }, value: parseInt('${quota.environment.maxsamenodescount}', 10) },
        { quota : { name: maxCloudletsPerRec }, value: parseInt('${quota.environment.maxcloudletsperrec}', 10) },
        { quota : { name: diskIOPSlimit }, value: parseInt('${quota.disk.iopslimit}', 10) }
    ];
    group = { groupType: '${account.groupType}' };
} else {
    quotas = jelastic.billing.account.GetQuotas(perEnv + ";"+maxEnvs+";" + perNodeGroup + ";" + maxCloudletsPerRec + ";" + diskIOPSlimit).array;
    group = jelastic.billing.account.GetAccount(appid, session);
}

for (var i = 0, l = quotas.length; i < l; i++) {
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

    if (n == perNodeGroup && nodesPerCplaneNG > q.value){
        if (!markup) err(q, "required", nodesPerCplaneNG);
        prod = false;
    }

    if (n == perNodeGroup && nodesPerWorkerNG > q.value){
        if (!markup) err(q, "required", nodesPerWorkerNG);
        prod = false;
    }
}
var resp = {result:0};
var url = "https://raw.githubusercontent.com/jelastic-jps/kubernetes/main/configs/settings.yaml";
resp.settings = toNative(new org.yaml.snakeyaml.Yaml().load(new com.hivext.api.core.utils.Transport().get(url)));
var f = resp.settings.fields;

if (!prod && dev) {
    //f[2].values[1].disabled = true;
    f[1].items[0].disabled = true;
    f[2].hidden = false;
    f[2].markup =  "Production topology is not available. " + markup + "Please upgrade your account.";
    f[2].height =  50;
    if (!devStorage) {
        f[4].disabled = true;
        f[4].value = false;
        f[4]['default'] = false;
    }
}

if (prod && !prodStorage){
    f[4].disabled = true;
    f[4].value = false;
    f[4]['default'] = false;
}

if (!prod && !dev || group.groupType == 'trial') {
    for (var i = 0, n = f.length; i < n; i++)
        if (f[i].type == "compositefield") {
            for (var j = 0, l = f[i].items.length; j < l; j++)  f[i].items[j].disabled = true;
        } else f[i].disabled = true;

    f[2].hidden = false;
    f[2].disabled = false;
    f[2].markup =  "Production and Development topologies are not available. " + markup + "Please upgrade your account.";
    if (group.groupType == 'trial')
        f[2].markup = "Production and Development topologies are not available for " + group.groupType + " account. Please upgrade your account.";
    f[2].height =  60;
    f[4].value = false;
    f[4]['default'] = false;

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

if (hasCollaboration) {
    f.push({
        "type": "owner",
        "name": "ownerUid",
        "caption": "Owner"
    });
    f[9].dependsOn = "ownerUid";
}

return resp;

function err(e, text, cur, override){
    var m = (e.quota.description || e.quota.name) + " - " + e.value + ", " + text + " - " + cur + ". ";
    if (override) markup = m; else markup += m;
}
