#!/bin/bash

# git clone https://github.com/paxtonhare/demo-magic.git
source ~/src/demos/demo-magic/demo-magic.sh
TYPE_SPEED=100
PROMPT_TIMEOUT=2
#DEMO_PROMPT="${CYAN}\W${GREEN}➜ ${COLOR_RESET}"
DEMO_PROMPT="${CYAN}\W-bgp ${GREEN}$ ${COLOR_RESET}"
DEMO_COMMENT_COLOR=$GREEN
GIT_ROOT=$(git rev-parse --show-toplevel)
DEMO_ROOT=$GIT_ROOT
BGP_ROUTER=192.168.4.1

# https://archive.zhimingwang.org/blog/2015-09-21-zsh-51-and-bracketed-paste.html
#unset zle_bracketed_paste
clear

p "# 🔍 all the things"
pei "git remote -v"
pei tree -L 3 $DEMO_ROOT/instance
p

p "# 🔧 install MetalLB operator"
pei "oc apply -k $DEMO_ROOT/operator"
p "# 🔧 enable MetalLB operator"
pei "oc apply -k $DEMO_ROOT/instance/base"
p
# pei "oc wait pod -l  component=controller -n metallb-system --for=condition=Ready=true"

p "# 📓 now we can create a configuration for BGP"
p "#  first we need to identify our routing peer (${BGP_ROUTER}),"
p "#  our made up autonomous system number (65002),"
p "#  and our made up peer AS (65001)"
pei "bat $DEMO_ROOT/instance/overlays/bgp/bgppeer.yaml"
p

p '# 🔍 next we need to identify an IP Address Pool (192.168.179.224/29)'
pei "bat $DEMO_ROOT/instance/overlays/bgp/ipaddresspool.yaml"
p

p "# 🔍 finally we need to define a bgp advertisement for this IP range"
pei "bat $DEMO_ROOT/instance/overlays/bgp/bgpadvertisement.yaml"
p

p "# 🔧 now apply these MetalLB BGP configs"
pei "oc apply -k $DEMO_ROOT/instance/overlays/bgp"
p

p "# ⌛ wait for FRR pods to come up..."
pei "oc wait pod -l app=frr-k8s -n metallb-system --for=condition=Ready=true"
p

p "# 🔍 these frr pods will be our BGP speakers and the router needs to know their IPs"
pei "oc get pods -l app=frr-k8s -n metallb-system -o jsonpath='{.items[*].status.podIP}{\"\n\"}'"
p

p "# 🔍 here is the FRR config on the peer router"
pei "bat -r 8: -l properties $DEMO_ROOT/instance/overlays/bgp/unifi-frr.conf"
sleep 3
p "# 🔍 the neighbor IPs of our cluster frr pods are placed in a 'ocp-hub' peer-group (line 20)"
p "#  the 'allow-ocp-hub' route-map is applied to announcements from this peer-group (line 33)"
p "#  the route-map uses the 'ocp-hub' prefix list to ensure only relevant prefixes are listened to (line 38)"
p

p "# 🚀 deploy an application to metallb-app namespace"
pei "oc apply -k $DEMO_ROOT/example-app/overlays/bgp"
p " 🔍 the app has a service of type loadbalancer"
pei "oc kustomize $DEMO_ROOT/example-app | kfilt -k service | bat -l yaml"
p

SVC_IP=$(oc get svc/static -n metallb-app -o jsonpath='{.status.loadBalancer.ingress[].ip}')

p "# 💻 the service recieved the IP $SVC_IP from the pool we defined earlier"
pei "oc get svc -n metallb-app -o wide"
p "#  it is reachable because all the following works as expected 😄"
pei "curl ${SVC_IP}:8080/app/"
p

p "# 🔍 the cluster frr speakers should now announce to their peers that they are"
p "#  next-hops to this IP and the BGP peer should accept and use these routes"
p

p "# 💻 now log into one of the frr pods and check the status"
POD=$(oc get pods -l app=frr-k8s -n metallb-system -o jsonpath='{.items[0].metadata.name}')
p "POD=\$(oc get pods -l app=frr-k8s -n metallb-system -o jsonpath='{.items[0].metadata.name}')"
p "oc -n metallb-system -c frr rsh \$POD vtysh -c 'show ip bgp summary'"
oc -n metallb-system -c frr rsh $POD vtysh -c 'show ip bgp summary'
p "# 💡 notice to our neighbor we have a value for PfxSnt (prefix sent) ^"
p "#  these should be visible on the router"
p

# copy demo script to Unifi router and continue demo there
scp ~/src/demos/demo-magic/demo-magic.sh root@${BGP_ROUTER}:/tmp/ > /dev/null 2>&1
scp demo-script-rtr.sh root@${BGP_ROUTER}:/tmp/ > /dev/null 2>&1
p "# 💻 ssh to the ${BLUE}Unifi Router${GREEN} and view status"
p "ssh root@${BGP_ROUTER}"
ssh -t root@${BGP_ROUTER} /tmp/demo-script-rtr.sh

#p "# 🚿 time to clean up"
p "# 🎉 SUCCESS!"
p "exit"
