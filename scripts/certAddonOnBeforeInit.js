var domainCommand = "kubectl get secret -n cert-manager jelastic-domain -o jsonpath='{.data.certificate_domain}' | base64 --decode";
var envName = "${env.envName}", nodeId = "${nodes.k8sm.master.id}";
var resp = api.env.control.ExecCmdById(envName, session, nodeId, toJSON([{ "command": domainCommand, "params": "" }]), true, "root");
if (resp.result != 0) return resp;
var installedDomainName = resp.responses[0].out;
if (installedDomainName.length > 0) {
    addon_installed_markup = "Kubernetes Certficate Manager is already configured. Please use the Certificate settings to adjust it. The domain configured now: " + installedDomainName;
    settings.fields[0].hidden = true;
    settings.fields[1].hidden = true;
    settings.fields[2].hidden = true;
    settings.fields.push({ "type": "displayfield", "cls": "warning", "height": 30, "hideLabel": true, "markup": addon_installed_markup });
}
return settings;
