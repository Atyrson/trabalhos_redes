#!/bin/bash
#
# QUESTÃO 2 do roteiro: configurar o servidor para entregar IP APENAS
# para estações cujo MAC já é conhecido (cadastrado).
#
# Demonstra: um cliente com MAC CADASTRADO recebe IP; o mesmo cliente
# com um MAC DESCONHECIDO é recusado (não recebe nada).
#
# Tudo isolado em network namespaces. NÃO toca na sua rede real.
# Uso:  sudo bash teste_questao2.sh

set -e

SRV_NS=dhcp_srv
CLI_NS=dhcp_cli
CONF=/etc/dhcp/dhcpd-q2.conf
LEASES=/var/lib/dhcp/dhcpd.leases
AA_PROFILE=/etc/apparmor.d/usr.sbin.dhcpd

MAC_CONHECIDO="02:00:00:00:00:11"   # cadastrado no servidor
MAC_DESCONHECIDO="02:00:00:00:00:99" # NÃO cadastrado

[ "$(id -u)" -eq 0 ] || { echo "Rode com sudo: sudo bash $0"; exit 1; }

cleanup() {
  ip netns pids $SRV_NS 2>/dev/null | xargs -r kill 2>/dev/null || true
  ip netns pids $CLI_NS 2>/dev/null | xargs -r kill 2>/dev/null || true
  ip netns del $SRV_NS 2>/dev/null || true
  ip netns del $CLI_NS 2>/dev/null || true
}
restore_apparmor() { [ -f "$AA_PROFILE" ] && apparmor_parser -r "$AA_PROFILE" 2>/dev/null || true; }
trap 'cleanup; restore_apparmor' EXIT

# Dependências
command -v dhcpd >/dev/null || { apt-get update -qq; DEBIAN_FRONTEND=noninteractive apt-get install -y isc-dhcp-server >/dev/null; }
systemctl disable --now isc-dhcp-server 2>/dev/null || true

# Config: note o "deny unknown-clients;" e o bloco host com o MAC conhecido
cat > $CONF <<EOF
default-lease-time 600;
max-lease-time 7200;
authoritative;
option subnet-mask 255.255.255.0;
option routers 192.168.10.254;
option domain-name-servers 192.168.10.2;
option domain-name "pipevendas.com.br";

subnet 192.168.10.0 netmask 255.255.255.0 {
    range 192.168.10.100 192.168.10.200;
    deny unknown-clients;          # <<< só atende MACs declarados abaixo
    option routers 192.168.10.254;
}

# Estação CADASTRADA: recebe sempre o IP fixo 192.168.10.50
host estacao-conhecida {
    hardware ethernet $MAC_CONHECIDO;
    fixed-address 192.168.10.50;
}
EOF

echo "== Validando configuração =="
dhcpd -t -cf $CONF && echo "   OK"

# Sobe a rede virtual + servidor
cleanup
ip netns add $SRV_NS; ip netns add $CLI_NS
ip link add veth-srv type veth peer name veth-cli
ip link set veth-srv netns $SRV_NS; ip link set veth-cli netns $CLI_NS
ip netns exec $SRV_NS ip link set lo up; ip netns exec $CLI_NS ip link set lo up
ip netns exec $SRV_NS ip addr add 192.168.10.4/24 dev veth-srv
ip netns exec $SRV_NS ip link set veth-srv up

[ -f "$AA_PROFILE" ] && apparmor_parser -C -r "$AA_PROFILE" 2>/dev/null || true
: > $LEASES && chmod 666 $LEASES
ip netns exec $SRV_NS dhcpd -4 -d -cf $CONF -lf $LEASES veth-srv > /tmp/dhcpd-q2.log 2>&1 &
sleep 2

# Script que o udhcpc usa para aplicar o IP
cat > /tmp/udhcpc-q2.script <<'EOF'
#!/bin/sh
if [ "$1" = "bound" ] || [ "$1" = "renew" ]; then
    ip -4 addr flush dev "$interface"; ip -4 addr add "$ip/24" dev "$interface"
fi
exit 0
EOF
chmod +x /tmp/udhcpc-q2.script

testar_mac() {  # $1 = mac, $2 = rótulo
    ip netns exec $CLI_NS ip link set veth-cli down
    ip netns exec $CLI_NS ip link set veth-cli address "$1"
    ip netns exec $CLI_NS ip -4 addr flush dev veth-cli 2>/dev/null || true
    ip netns exec $CLI_NS ip link set veth-cli up
    echo
    echo "================================================================"
    echo ">>> Cliente com MAC $2: $1"
    echo "================================================================"
    if ip netns exec $CLI_NS timeout 12 busybox udhcpc -i veth-cli -f -q -n -t 3 -T 2 \
         -s /tmp/udhcpc-q2.script 2>&1; then
        echo "RESULTADO: recebeu IP ->$(ip netns exec $CLI_NS ip -4 addr show veth-cli | grep -o 'inet [0-9.]*')"
    else
        echo "RESULTADO: NENHUM IP recebido (servidor recusou - MAC não cadastrado)."
    fi
}

testar_mac "$MAC_CONHECIDO"   "CADASTRADO"
testar_mac "$MAC_DESCONHECIDO" "DESCONHECIDO"

echo
echo "============== O QUE O SERVIDOR REGISTROU NO LOG =============="
grep -iE "DHCPDISCOVER|DHCPOFFER|DHCPACK|no free|not authorized|unknown" /tmp/dhcpd-q2.log || true
echo "=============================================================="
echo
echo "Conclusão esperada: o MAC CADASTRADO recebe 192.168.10.50;"
echo "o MAC DESCONHECIDO não recebe nada (DHCPDISCOVER sem DHCPOFFER)."
