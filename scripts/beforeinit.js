import com.hivext.api.Response;
import org.yaml.snakeyaml.Yaml;
import com.hivext.api.core.utils.Transport;

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

var url = "https://raw.githubusercontent.com/sych74/kubernetes/v1.15.5/configs/settings.yaml";
var settings = toNative(new Yaml().load(new Transport().get(url)));
var fields = settings.fields;

if (markup) {
    if (!prod && dev){
        fields.push({
            "name": "topo",
            "type": "radio-fieldset",
            "default": "0-dev",
            "values": [{
                "0-dev": "<b>Development:</b> one master (1) and one scalable worker (1+)"
            }]   
        });

        fields.push({
            "type": "radio-fieldset",
            "disabled": true,
            "values": [{
                "1-prod": "<b>Production:</b> multi master (3) with API balancers (2+) and scalable workers (2+)"
            }]   
        });

        fields.push({
            "type": "displayfield",
            "cls": "warning",
            "height": 30,
            "hideLabel": true,
            "markup": "Production topology is not available. " + markup + "Please upgrade your account."
        });
    }

    if (!prod && !dev){
        fields.push({
            "name": "topo-disabled",
            "type": "radio-fieldset",
            "default": "0-dev",
            "disabled": true,
            "values": {
               "0-dev": "<b>Development:</b> one master (1) and one scalable worker (1+)",
               "1-prod": "<b>Production:</b> multi master (3) with API balancers (2+) and scalable workers (2+)"
            }
        });

        fields.push({
            "type": "displayfield",
            "cls": "warning",
            "height": 30,
            "hideLabel": true,
            "markup": "Production and Development topologies are not available. " + markup + "Please upgrade your account."
        });
        
       fields.push({
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
    }
    
    fields.push({
        "name": "ingress-controller",
        "type": "list",
        "caption": "Ingress Controller",
        "values": {
            "Nginx": "Nginx",
            "HAProxy": "HAProxy",
            "Traefik": "Traefik"
        },
        "default": "Nginx",
        "hideLabel": false,
        "editable": false
    });

    fields.push({
        "name": "dashboard",
        "type": "list",
        "caption": "Kubernetes Dashboard",
        "values": {
            "version1": "Kubernetes Dashboard v1 (Stable)",
            "version2": "Kubernetes Dashboard v2 (Beta)"
        },
        "default": "version2",
        "hideLabel": false,
        "editable": false
    });
    
    fields.push({
        "name": "dashboard",
        "type": "list",
        "caption": "Kubernetes Dashboard",
        "values": {
            "version1": "Kubernetes Dashboard v1 (Stable)",
            "version2": "Kubernetes Dashboard v2 (Beta)"
        },
        "default": "version2",
        "hideLabel": false,
        "editable": false
    });

    if (storage){
        fields.push({
            "type": "checkbox",
            "name": "storage",
            "caption": "Attach dedicated NFS Storage with dynamic volume provisioning",
            "value": true
        }); 
    } else {
        fields.push({
            "type": "checkbox",
            "name": "storage",
            "caption": "Attach dedicated NFS Storage with dynamic volume provisioning",
            "value": false,
            "disabled": true
        }); 
    }

    if (!prod && !dev){
        fields.push({
            "type": "checkbox",
            "name": "api",
            "caption": "Enable Remote API Access",
            "value": "false",
            "disabled": true
        }); 
    } else {
        fields.push({
            "type": "checkbox",
            "name": "api",
            "caption": "Enable Remote API Access",
            "value": "false",
        }); 
    }
    
    fields.push({
        "type": "checkbox",
        "name": "monitoring",
        "caption": "Install Prometheus & Grafana",
        "value": false,
        "disabled": true
    });
        
    fields.push({
        "type": "checkbox",
        "name": "jaeger",
        "caption": "Install Jaeger tracing tools",
        "value": false,
        "disabled": true
    });         
}
return {
    result: 0,
    settings: settings
};

function err(e, text, cur, override){
    var m = (e.quota.description || e.quota.name) + " - " + e.value + ", " + text + " - " + cur + ". ";
    if (override) markup = m; else markup += m;
}
