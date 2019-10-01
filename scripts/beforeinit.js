//checking quotas
var perEnv = "environment.maxnodescount",
    maxEnvs = "environment.maxcount",
    perNodeGroup = "environment.maxsamenodescount";
var envsCount = jelastic.env.control.GetEnvs({lazy: true}).infos.length,
    nodesPerProdEnv = 8,
    nodesPerProdEnvWOStorage = 7,
    nodesPerDevEnv = 3,
    nodesPerDevEnvWOStorage = 2,
    nodesPerMasterNG = 3,
    nodesPerWorkerNG = 2,
    markup = "", cur = null, text = "used", prod = true, storage = true, dev = true;

var quotas = jelastic.billing.account.GetQuotas(perEnv + ";"+maxEnvs+";" + perNodeGroup).array;
for (var i = 0; i < quotas.length; i++){
    var q = quotas[i], n = toNative(q.quota.name);
    if (n == maxEnvs && envsCount >= q.value){
        err(q, "already used", envsCount, true);
        markup = "Maximum allowed environments: " + markup;
        prod = dev = storage = false; break;
    }
    if (n == perEnv && nodesPerProdEnv > q.value){
        if (!markup) err(q, "required", nodesPerProdEnv);
        prod = false;
        if (nodesPerProdEnvWOStorage <= q.value) {
          prod = true;
          storage = false;
        }
    }
    if (n == perEnv && nodesPerDevEnv > q.value){
        err(q, "required", nodesPerDevEnv, true);
        dev = false;
        if (nodesPerDevEnvWOStorage <= q.value) {
          dev = true;
          storage = false;
        }
    }
    if (n == perNodeGroup && nodesPerMasterNG > q.value){
        if (!markup) err(q, "required", nodesPerMasterNG);
        prod = false;
    }
    if (n == perNodeGroup && nodesPerWorkerNG > q.value){
        err(q, "required", nodesPerWorkerNG);
        dev = false;
    }
}
var resp = {result:0};
var url = "https://raw.githubusercontent.com/jelastic-jps/kubernetes/v1.15.5/configs/settings.yaml";
resp.settings = toNative(new org.yaml.snakeyaml.Yaml().load(new com.hivext.api.core.utils.Transport().get(url)));
if (markup) {
  var f = resp.settings.fields;
  f.push({
      "type": "displayfield",
      "cls": "warning",
      "height": 30,
      "hideLabel": true,
      "markup": (!prod && dev  ? "Production topology is not available. " : "") + markup + "Please upgrade your account."
  });
  if (!prod && !dev){
    f.push({
        "type": "compositefield",
        "height" : 0,
        "hideLabel": true,
        "width": 0,
        "items": [{
            "height" : 0,
            "type": "string",
            "required": true,
        }]
    });
  } else {
    if (!prod) delete f[2].values["1-prod"];
    if (!storage) f.splice(3, 1);
  }
}
return resp;

function err(e, text, cur, override){
  var m = (e.quota.description || e.quota.name) + " - " + e.value + ", " + text + " - " + cur + ". ";
  if (override) markup = m; else markup += m;
}
