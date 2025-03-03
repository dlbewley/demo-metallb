#!/bin/bash

. /tmp/demo-magic.sh -d

DEMO_PROMPT="${CYAN}bgp-rtr ${BLUE}$ ${COLOR_RESET}"
DEMO_COMMENT_COLOR=$BLUE
PROMPT_TIMEOUT=2

p "# 💡 use vtysh to talk to frr interactively or pass each command via -c"
p "# 🔍 show the running config"
pei "vtysh -c 'show run'"
p

p "# 🔍 check bgp peers and expect 'Established'"
pei "vtysh -c 'show ip bgp peer-group'"
p

p "# 🔍 show the bgp summary"
pei "vtysh -c 'show ip bgp summary'"
p "# 💡 notice from each neighbor we have 1 PfxRcd (prefix received) ^"
p

p "# 🔍 view the linux routing table and see it has learned from BGP"
p "#  5 equal cost routes to the IP allocated for the service"
pei "ip -c route list proto bgp"
p
p "exit"

# remove demo scripts
[[ -f "/tmp/demo-magic.sh" ]] && rm "/tmp/demo-magic.sh"
[[ -f "$0" ]] && rm "$0"