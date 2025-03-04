
> [!IMPORTANT]
> This is an example MetalLB configuration with BGP support. It is intentionally rather simple and could be enhanced by adding a password to the BGP peer relationships and it could be more responsive to topology changes by enabling BFD.

[![asciicast](https://asciinema.org/a/OJimzY6tlKYT8AexAVeBkp9eP.svg)](https://asciinema.org/a/OJimzY6tlKYT8AexAVeBkp9eP)

# Enable BGP in MetalLB

* [Install MetalLB](../../operator/) operator

*  Enable MetalLB by [creating a MetalLB](../base/) resource

* Define an IP [address pool](ipaddresspool.yaml). In my case I'm using 192.168.179.224/29 but we'll pretend it's all of 192.168.179.0/24.

>[!NOTE]
> This IP range is not in use on my nodes or anywhere in my network. I just made it up. BGP runs on TCP port 179 so I chose that for the third octet.

```yaml
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: lab-192-168-179-224-b29
  annotations:
    description: "Unique, arbitrary IP range that is not otherwise configured in any way."
spec:
  addresses:
    - 192.168.179.224-192.168.179.231
  autoAssign: true
  # ignore .0 and .255
  avoidBuggyIPs: true 
  # optional limitation on use of pool
  serviceAllocation:
    namespaces:
      - metallb-app
```

* Define a [BGP Peer](bgppeer.yaml). This is a reference to your router running BGP which you want your cluster to peer with. We will use a Unifi Dream Machine and detail the setup below. Your BGPPeer will have settings appropriate to your network. For example the autonomous system number and IP addresses will differ at a minimum.

```yaml
apiVersion: metallb.io/v1beta2
kind: BGPPeer
metadata:
  name: bgp-peer-udmpro
  namespace: metallb-system
spec:
  disableMP: false
  enableGracefulRestart: true
  myASN: 65002
  peerASN: 65001
  peerAddress: 192.168.4.1
  peerPort: 179
  #  password: xxxxEXAMPLE
```

* Defing a [BGP Advertisement](bgpadvertisement.yaml) to begin announcing and IPs assigned from the address pool as being reachable via our cluster node IPs, more specifically our nodes running frr.

```bash
$ oc get pods -l app=frr-k8s -n metallb-system -o wide
NAME            READY   STATUS    RESTARTS        AGE     IP              NODE                       NOMINATED NODE   READINESS GATES
frr-k8s-5mhzx   6/6     Running   6               4d19h   192.168.4.152   hub-q7dgr-worker-0-5n47d   <none>           <none>
frr-k8s-6w9vv   6/6     Running   7 (3d19h ago)   4d19h   192.168.4.193   hub-q7dgr-cnv-nzwp7        <none>           <none>
frr-k8s-k7wm6   6/6     Running   6               4d19h   192.168.4.98    hub-q7dgr-worker-0-z9mgb   <none>           <none>
frr-k8s-n5wgs   6/6     Running   6               4d19h   192.168.4.182   hub-q7dgr-cnv-tffcm        <none>           <none>
frr-k8s-nrhkz   6/6     Running   6               4d19h   192.168.4.195   hub-q7dgr-cnv-dhkgw        <none>           <none>
```

# Enable a peer FRR outside the OpenShift Cluster

> [!NOTE]
> Peer groups can help minimize redundancy in the router configuration.

* Obtain the IPs of the cluster nodes running frr. These will be the neighbors or peers with the bgp router.

```bash
$ CLUSTER=ocp-hub
$ for ip in $(oc get pods -l app=frr-k8s \
    -n metallb-system -o jsonpath='{.items[*].status.podIP}'); do 
    echo "neighbor $ip peer-group $CLUSTER";
  done

neighbor 192.168.4.152 peer-group ocp-hub
neighbor 192.168.4.193 peer-group ocp-hub
neighbor 192.168.4.98 peer-group ocp-hub
neighbor 192.168.4.182 peer-group ocp-hub
neighbor 192.168.4.195 peer-group ocp-hub
```

* Identify the IP range that the router should expect to recieve from the cluster. Ensure that the router does not accept any unexpected routes from it's neighbors. In this case the range is 192.168.179.0/24 and we want to accept route prefixes all the way up to 32 bits in length. This prefix-list and route-map will be used to apply this constraint to the 'ocp-hub' peer-group we just defined.

```bash
! allow any advertised routes in this range with up to 32 bits mask length
ip prefix-list ocp-hub seq 5 permit 192.168.179.0/24 le 32
!
route-map allow-ocp-hub permit 10
 match ip address prefix-list ocp-hub
```

* Construct an [frr.conf](unifi-frr.conf) with this peer-group and other settings.

* Place the frr.conf on the router at `/etc/frr/frr.conf`

```bash
!
frr version 8.1
frr defaults traditional
hostname UDMPRO
domainname home.bewley.net
log syslog informational
service integrated-vtysh-config
!
router bgp 65001
 ! this is an IP on the Unifi
 bgp router-id 192.168.4.1
 bgp log-neighbor-changes
 no bgp default ipv4-unicast
 neighbor ocp-hub peer-group
 neighbor ocp-hub remote-as 65002
 neighbor 192.168.4.98 peer-group ocp-hub
 neighbor 192.168.4.152 peer-group ocp-hub
 neighbor 192.168.4.182 peer-group ocp-hub
 neighbor 192.168.4.193 peer-group ocp-hub
 neighbor 192.168.4.195 peer-group ocp-hub
 !
 address-family ipv4 unicast
  neighbor ocp-hub activate
  neighbor ocp-hub soft-reconfiguration inbound
  neighbor ocp-hub route-map allow-ocp-hub in
 exit-address-family
exit
!
! allow any advertised routes in this range with up to 32 bits mask length
ip prefix-list ocp-hub seq 5 permit 192.168.179.0/24 le 32
!
route-map allow-ocp-hub permit 10
 match ip address prefix-list ocp-hub
exit
!
```

* Modify `/etc/frr/daemons` file on the router. Set `bgpd=yes`.

* Enable and start the `frr` service

```bash
systemctl enable frr
systemctl start frr
```

## Confirm Peer Relationship

```bash
vtysh
# any neighbor state that is not "Established" is less than successful
sh ip bgp peer-group
sh ip bgp neighbor
sh ip bgp sum
```

# Creating a Load Balanced Service

IPs assigned from the address pool above will be advertised to our BGP peers as a `/32` or 'host' route.

# References

* https://www.cisco.com/c/en/us/td/docs/ios-xml/ios/iproute_bgp/configuration/xe-16/irg-xe-16-book.html
* https://metallb.io/configuration/_advanced_bgp_configuration/
* https://www.redhat.com/en/blog/metallb-in-bgp-mode