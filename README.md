# Demo MetalLB

Simple examples illustrating the use of [MetalLB](https://metallb.io/) in Layer2 and BGP modes
on [OpenShift](https://www.redhat.com/en/technologies/cloud-computing/openshift).

> [!NOTE]
> * Node machines are on 192.168.4.0/24
> * MetalLB layer2 mode example [IP address pool](metallb/instance/l2/ipaddresspool.yaml) is defined as 192.168.4.224/29
> * MetalLB BGP mode example [IP address pool](metallb/instance/bgp/ipaddresspool.yaml) is defined as 192.168.179.224/29

# Deploying MetalLB

* Install the MetalLB operator 

```bash
oc apply -k metallb/operator
```

* Enable MetalLB operator by creating an MetalLB instance

```bash
oc apply -k metallb/instance/base
```

## Enabling MetalLB Layer 2 Load Balancing

The nodes already have an IP address on the 192.168.4.0/24 network, and only on that network. To use layer2 mode the nodes must already have an ability to GARP and respond to ARPs for IP addresses being advertised. This is why we are using a small portion of IPs (192.168.4.224/29). Alternatively another VLAN interface could be created on each node.

* [Deploy](metallb/instance/l2) an ip address pool from within the machine network, and define the layer 2 advertisment

```bash
oc apply -k metallb/instance/l2
```

## Enabling MetalLB Layer 3 Load Balancing via BGP

BGP operates at layer 3. There is no need for nodes to have a presence on the subnet being advertised by BGP. In this case we will choose a made up subnet of 192.168.179.0/24 and select a subset of those IPs (192.168.179.224/29) for not particular reason.

* [Deploy](metallb/instance/bgp) an ip address pool and bgp advertistment along with supporting configuration

```bash
oc apply -k metallb/instance/bgp
```

# Using MetalLB in an Application Service

An example app was generated as follows plus [this patch](example-app/patch-service.yaml) to make it use MetalLB.

`oc new-app --name static nginx~https://github.com/dlbewley/static.git --dry-run -o yaml > application.yaml`

Deploy the app.

```bash
oc apply -k example-app
```

## Examine the results

Notice the service has a Cluster-IP and an External-IP from the AddressPool range.

Also notice that the containers are using NodePorts.

```bash
oc get svc -n metallb-app
NAME     TYPE           CLUSTER-IP      EXTERNAL-IP     PORT(S)                         AGE
static   LoadBalancer   172.30.74.176   192.168.4.227   8080:30759/TCP,8443:31161/TCP   11m

$ oc get service/static -n metallb-app -o yaml | yq e '.spec.ports' -
- name: 8080-tcp
  nodePort: 30759
  port: 8080
  protocol: TCP
  targetPort: 8080
- name: 8443-tcp
  nodePort: 31161
  port: 8443
  protocol: TCP
  targetPort: 8443
```

![service-static.png](img/service-static.png)

That means all nodes have that port open.

```bash
$ for node in $(oc get nodes -l node-role.kubernetes.io/worker -o name); do oc debug $node -- netstat -tupln |grep 30759; done
Starting pod/hub-kmbtb-store-1-5cw2f-debug ...
To use host binaries, run `chroot /host`
tcp        0      0 0.0.0.0:30759           0.0.0.0:*               LISTEN      4141/openshift-sdn-

Removing debug pod ...
Starting pod/hub-kmbtb-store-2-kcj5d-debug ...
To use host binaries, run `chroot /host`
tcp        0      0 0.0.0.0:30759           0.0.0.0:*               LISTEN      4544/openshift-sdn-

Removing debug pod ...
Starting pod/hub-kmbtb-store-3-hkln5-debug ...
To use host binaries, run `chroot /host`
tcp        0      0 0.0.0.0:30759           0.0.0.0:*               LISTEN      3946/openshift-sdn-

Removing debug pod ...
Starting pod/hub-kmbtb-worker-l5hxw-debug ...
To use host binaries, run `chroot /host`
tcp        0      0 0.0.0.0:30759           0.0.0.0:*               LISTEN      3411/openshift-sdn-

Removing debug pod ...
Starting pod/hub-kmbtb-worker-p9pws-debug ...
To use host binaries, run `chroot /host`
tcp        0      0 0.0.0.0:30759           0.0.0.0:*               LISTEN      3255/openshift-sdn-

Removing debug pod ...
Starting pod/hub-kmbtb-worker-t6czb-debug ...
To use host binaries, run `chroot /host`
tcp        0      0 0.0.0.0:30759           0.0.0.0:*               LISTEN      3398/openshift-sdn-

Removing debug pod ...
```

```bash
$ oc get pods -n metallb-app -o wide
NAME                      READY   STATUS      RESTARTS   AGE   IP            NODE                     NOMINATED NODE   READINESS GATES
static-1-build            0/1     Completed   0          19m   10.128.4.67   hub-kmbtb-worker-t6czb   <none>           <none>
static-699d8bb6f4-shxjq   1/1     Running     0          18m   10.131.1.2    hub-kmbtb-worker-p9pws   <none>           <none>

$ oc get endpoints -n metallb-app
NAME     ENDPOINTS                         AGE
static   10.131.1.2:8080,10.131.1.2:8443   11m
```

Access the app using the external IP on the service and the request will find an endpoint to respond. 

```bash
$ curl 192.168.4.227:8080/app/
<html>
<head>
<title>Static Web Site</title>
</head>
<body>
<h1>Static Content</h1>
<p><img src="https://upload.wikimedia.org/wikipedia/commons/7/7e/Random_static.gif" /></p>
</body>
</html>
```

# DNS

Feel free to create DNS A resource records pointing to 192.168.4.227 for clients outside the OpenShift cluster.

Remember that clients inside the cluster can take advantage of DNS service discovery.

```bash
oc run oc-client --labels="app=oc-client" --rm -i --tty --image openshift4/ose-cli -n metallb-app -- /bin/bash
If you don't see a command prompt, try pressing enter.

[root@oc-client /]# host static
static.metallb-app.svc.cluster.local has address 172.30.74.176

[root@oc-client /]# curl static:8080/app/
<html>
<head>
<title>Static Web Site</title>
</head>
<body>
<h1>Static Content</h1>
<p><img src="https://upload.wikimedia.org/wikipedia/commons/7/7e/Random_static.gif" /></p>
</body>
</html>
```