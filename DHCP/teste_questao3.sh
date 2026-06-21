#!/bin/bash
#
# QUESTÃO 3 do roteiro: o que acontece com MAIS DE UM servidor DHCP na
# mesma rede? Faça testes e mostre as conclusões.
#
# Monta um "switch" virtual (bridge) com:
#   - Servidor A (192.168.10.4)  -> entrega faixa .100-.150, gateway correto
#   - Servidor B (192.168.10.5)  -> entrega faixa .160-.200, gateway DIFERENTE
#                                    (simula um servidor não autorizado / rogue)
#   - 1 cliente que pede IP várias vezes
#
# Mostra que o cliente aceita a PRIMEIRA oferta que chegar - de forma
# não-determinística - podendo pegar gateway/DNS errados do servidor rogue.
#
# Isolado em namespaces. NÃO toca na sua rede real.
# Uso:  sudo bash teste_questao3.sh

set -e

BR=br_dhcp
NS_A=dhcp_a; NS_B=dhcp_b; NS_C=dhcp_c
CONF_A=/etc/dhcp/dhcpd-a.conf; CONF_B=/etc/dhcp/dhcpd-b.conf
LEASES_A=/var/lib/dhcp/dhcpd.leases-a
LEASES_B=/var/lib/dhcp/dhcpd.leases-b
AA_PROFILE=/etc/apparmor.d/usr.sbin.dhcpd

[ "$(id -u)" -eq 0 ] || { echo "Rode com sudo: sudo bash $0"; exit 1; }

cleanup() {
  for ns in $NS_A $NS_B $NS_C; do
    ip netns pids $ns 2>/dev/null | xargs -r kill 2>/dev/null || true
    ip netns del $ns 2>/dev/null || true
  done
  ip link del $BR 2>/dev/null || true
}
restore_apparmor() { [ -f "$AA_PROFILE" ] && apparmor_parser -r "$AA_PROFILE" 2>/dev/null || true; }
trap 'cleanup; restore_apparmor' EXIT

command -v dhcpd >/dev/null || { apt-get update -qq; DEBIAN_FRONTEND=noninteractive apt-get install -y isc-dhcp-server >/dev/null; }
systemctl disable --now isc-dhcp-server 2>/dev/null || true

# ---- Config do Servidor A (legítimo) ----
cat > $CONF_A <<'EOF'
default-lease-time 600; max-lease-time 7200;
subnet 192.168.10.0 netmask 255.255.255.0 {
    range 192.168.10.100 192.168.10.150;
    option routers 192.168.10.254;            # gateway CORRETO
    option domain-name-servers 192.168.10.2;  # DNS CORRETO (do grupo)
}
EOF

# ---- Config do Servidor B (rogue / não autorizado) ----
cat > $CONF_B <<'EOF'
default-lease-time 600; max-lease-time 7200;
subnet 192.168.10.0 netmask 255.255.255.0 {
    range 192.168.10.160 192.168.10.200;
    option routers 192.168.10.111;            # gateway ERRADO
    option domain-name-servers 8.8.8.8;       # DNS de fora (não é o do grupo)
}
EOF

echo "== Validando as duas configurações =="
dhcpd -t -cf $CONF_A && dhcpd -t -cf $CONF_B && echo "   OK"

# ---- Monta o switch virtual e as 3 máquinas ----
cleanup
ip link add $BR type bridge
ip link set $BR up

conecta() {  # $1 = namespace, $2 = sufixo
    local h="h$2" p="p$2"
    ip netns add "$1"
    ip link add "$h" type veth peer name "$p"
    ip link set "$h" master $BR
    ip link set "$h" up
    ip link set "$p" netns "$1"
    ip netns exec "$1" ip link set lo up
    ip netns exec "$1" ip link set "$p" up
}
conecta $NS_A a
conecta $NS_B b
conecta $NS_C c
ip netns exec $NS_A ip addr add 192.168.10.4/24 dev pa
ip netns exec $NS_B ip addr add 192.168.10.5/24 dev pb

# ---- Sobe os dois servidores ----
[ -f "$AA_PROFILE" ] && apparmor_parser -C -r "$AA_PROFILE" 2>/dev/null || true
: > $LEASES_A && chmod 666 $LEASES_A
: > $LEASES_B && chmod 666 $LEASES_B
ip netns exec $NS_A dhcpd -4 -d -cf $CONF_A -lf $LEASES_A pa > /tmp/dhcpd-a.log 2>&1 &
ip netns exec $NS_B dhcpd -4 -d -cf $CONF_B -lf $LEASES_B pb > /tmp/dhcpd-b.log 2>&1 &
sleep 2

# Script do udhcpc: mostra IP, servidor, gateway e DNS recebidos
cat > /tmp/udhcpc-q3.script <<'EOF'
#!/bin/sh
if [ "$1" = "bound" ]; then
    ip -4 addr flush dev "$interface"; ip -4 addr add "$ip/24" dev "$interface"
    echo "    -> IP=$ip | servidor=$serverid | gateway=$router | dns=$dns"
fi
exit 0
EOF
chmod +x /tmp/udhcpc-q3.script

# Captura as ofertas (deve aparecer 1 discover e 2 offers)
ip netns exec $NS_C timeout 25 tcpdump -i pc -n -U 'port 67 or port 68' -w /tmp/dhcp-q3.pcap 2>/dev/null &
sleep 1

echo
echo "===== Cliente pedindo IP 5 vezes (observe de qual servidor vem) ====="
A=0; B=0
for i in 1 2 3 4 5; do
    echo "--- Tentativa $i ---"
    ip netns exec $NS_C ip -4 addr flush dev pc 2>/dev/null || true
    out=$(ip netns exec $NS_C timeout 12 busybox udhcpc -i pc -f -q -n -t 3 -T 2 -s /tmp/udhcpc-q3.script 2>&1)
    echo "$out" | grep -E 'lease of|-> IP='
    srv=$(echo "$out" | grep -o 'server 192.168.10.[0-9]*' | grep -o '192.168.10.[0-9]*' | head -1)
    [ "$srv" = "192.168.10.4" ] && A=$((A+1))
    [ "$srv" = "192.168.10.5" ] && B=$((B+1))
    sleep 1
done

echo
echo "===================== CONCLUSÃO ====================="
echo "Das 5 tentativas: $A vieram do Servidor A (.4, correto)"
echo "                  $B vieram do Servidor B (.5, rogue)"
echo
echo "Ofertas vistas pelo cliente na rede (tcpdump):"
tcpdump -r /tmp/dhcp-q3.pcap -n 2>/dev/null | grep -iE 'discover|offer' | head -12 || true
echo
echo "-> Como há DOIS servidores, o cliente aceita a 1a oferta que chegar."
echo "   O resultado é não-determinístico: às vezes pega o gateway/DNS"
echo "   ERRADOS do servidor rogue (.5), quebrando o acesso à rede."
echo "====================================================="
