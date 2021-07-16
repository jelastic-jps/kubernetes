var k8smCount = '${settings.topo}' == '0-dev' ? 1 : 3,
    workerCount = k8smCount > 1 ? 2 : 1,
    storageCount = k8smCount > 1 ? 3 : 1,
    tag = "${settings.version}";
var resp = {
  result: 0,
  ssl: !!jelastic.billing.account.GetQuotas('environment.jelasticssl.enabled').array[0].value,
  nodes: [{
    count: k8smCount,
    options: ["extra_small_vm"],
    nodeType: "ubuntu2004",
    scalingMode: "stateless",
    nodeGroup: "k8sm",
    isRedeploySupport: false,
    addons: ["conf-k8s-addon", "upgrade-k8s-addon", "monitor-k8s-addon", "certman-k8s-addon", "rancher-k8s-addon"],
    displayName: "Master",
    extip: false
  }, {
    count: workerCount,
    options: ["extra_small_vm"],
    nodeGroup: "cp",
    nodeType: "ubuntu2004",
    scalingMode: "stateless",
    displayName: "Workers",
    isRedeploySupport: false,
    extip: ${settings.extip:false}
  }, {
    count: workerCount,
    options: ["extra_small_vm"],
    nodeGroup: "wincp",
    nodeType: "windows2019",
    scalingMode: "stateless",
    displayName: "WinWorkers",
    isRedeploySupport: false,
    extip: ${settings.extip:false}
  }]
}

if (k8smCount > 1) {
  resp.nodes.push({
    count: 2,
    nodeType: "haproxy",
    cloudlets: 8,
    displayName: "API Balancer",
    nodeGroup: "mbl",
    env: {
      JELASTIC_PORTS: 6443
    }
  })
}

if ('${settings.storage}' == 'true') {
  var path = "/data";
  resp.nodes.push({
    count: storageCount,
    nodeType: "storage",
    cloudlets: 8,
    displayName: "Storage",
    nodeGroup: "storage",
    cluster: storageCount > 1,
    volumes: [
      path
    ]
  })

  for (var i = 0; i < 2; i++){
    var n = resp.nodes[i];
    n.volumes = [path];
    n.volumeMounts = {};
    n.volumeMounts[path] = {
        readOnly: false,
        sourcePath: path,
        sourceNodeGroup: "storage"
    };
    if (storageCount > 1) {
        n.volumeMounts[path].sourceAddressType = "NODE_GROUP";
    }
  }
}
return resp;
