#!/bin/bash
#
# Teste ISOLADO do servidor DHCP usando network namespaces.
# Cria uma mini-rede virtual dentro do Linux (servidor + cliente),
# sobe o dhcpd com a SUA configuração e faz um cliente pedir IP.
#
# >>> NÃO toca na sua rede/Wi-Fi real. Tudo acontece em namespaces. <<<
#
# Uso:  sudo bash teste_isolado.sh

set -e

SRV_NS=dhcp_srv
CLI_NS=dhcp_cli
# OBS.: o AppArmor do Ubuntu só deixa o dhcpd ler de /etc/dhcp/ e gravar
# leases em /var/lib/dhcp/, por isso NÃO usamos /tmp para esses arquivos.
CONF=/etc/dhcp/dhcpd-test.conf
LEASES=/var/lib/dhcp/dhcpd.leases
PCAP=/tmp/dhcp-test.pcap   # tcpdump pode gravar qualquer *.pcap

if [ "$(id -u)" -ne 0 ]; then
  echo "Rode com sudo:  sudo bash $0"; exit 1
fi

AA_PROFILE=/etc/apparmor.d/usr.sbin.dhcpd

cleanup() {
  ip netns pids $SRV_NS 2>/dev/null | xargs -r kill 2>/dev/null || true
  ip netns pids $CLI_NS 2>/dev/null | xargs -r kill 2>/dev/null || true
  ip netns del $SRV_NS 2>/dev/null || true
  ip netns del $CLI_NS 2>/dev/null || true
}

restore_apparmor() {
  # Recoloca o perfil do dhcpd em enforce (estado original)
  [ -f "$AA_PROFILE" ] && apparmor_parser -r "$AA_PROFILE" 2>/dev/null || true
}

trap 'cleanup; restore_apparmor' EXIT

# 0) Dependências ----------------------------------------------------
if ! command -v dhcpd >/dev/null || ! command -v tcpdump >/dev/null; then
  echo "== Instalando isc-dhcp-server e tcpdump =="
  apt-get update -qq
  DEBIAN_FRONTEND=noninteractive apt-get install -y isc-dhcp-server tcpdump >/dev/null
fi
# Garante que o serviço REAL não suba na sua placa de rede de verdade
systemctl disable --now isc-dhcp-server 2>/dev/null || true

# 1) Configuração de teste (idêntica à do servidor_dhcp.sh) ----------
cat > $CONF <<'EOF'
default-lease-time 600;
max-lease-time 7200;
authoritative;
option subnet-mask 255.255.255.0;
option broadcast-address 192.168.10.255;
option routers 192.168.10.254;
option domain-name-servers 192.168.10.2;
option domain-name "pipevendas.com.br";
subnet 192.168.10.0 netmask 255.255.255.0 {
    range 192.168.10.100 192.168.10.200;
    option routers 192.168.10.254;
    option domain-name-servers 192.168.10.2;
    option domain-name "pipevendas.com.br";
}
host estacao-fixa {
    hardware ethernet 08:00:27:aa:bb:cc;
    fixed-address 192.168.10.50;
    option host-name "estacao1";
}
EOF
: > $LEASES

echo "== 1) Validando a sintaxe do dhcpd.conf =="
dhcpd -t -cf $CONF
echo "   sintaxe OK"

# 2) Monta a rede virtual (2 namespaces ligados por um cabo veth) ----
echo "== 2) Criando rede virtual isolada =="
cleanup
ip netns add $SRV_NS
ip netns add $CLI_NS
ip link add veth-srv type veth peer name veth-cli
ip link set veth-srv netns $SRV_NS
ip link set veth-cli netns $CLI_NS
ip netns exec $SRV_NS ip link set lo up
ip netns exec $CLI_NS ip link set lo up
ip netns exec $SRV_NS ip addr add 192.168.10.4/24 dev veth-srv
ip netns exec $SRV_NS ip link set veth-srv up
ip netns exec $CLI_NS ip link set veth-cli up

# 3) Começa a capturar o tráfego DHCP (para a Questão 1) -------------
# -U grava cada pacote no arquivo imediatamente (senão fica no buffer)
ip netns exec $SRV_NS timeout 30 tcpdump -i veth-srv -n -U 'port 67 or port 68' -w $PCAP 2>/dev/null &
sleep 1

# 4) Sobe o servidor DHCP dentro do namespace do servidor -----------
# No Ubuntu 24.04 o AppArmor bloqueia o dhcpd de abrir o leases em modo
# append. Colocamos o perfil em complain (não-bloqueante) só durante o
# teste; o trap EXIT restaura para enforce no final.
echo "== 3) Subindo o servidor DHCP (192.168.10.4) =="
[ -f "$AA_PROFILE" ] && apparmor_parser -C -r "$AA_PROFILE" 2>/dev/null || true
: > $LEASES && chmod 666 $LEASES
ip netns exec $SRV_NS dhcpd -4 -d -cf $CONF -lf $LEASES veth-srv > /tmp/dhcpd-test.log 2>&1 &
sleep 2

# 5) Cliente pede um endereço --------------------------------------
# O Ubuntu 24.04 não traz mais 'dhclient'; usamos o cliente DHCP do
# busybox (udhcpc). O script abaixo aplica o IP recebido na interface.
echo "== 4) Cliente solicitando IP via DHCP (busybox udhcpc) =="
cat > /tmp/udhcpc-test.script <<'EOF'
#!/bin/sh
if [ "$1" = "bound" ] || [ "$1" = "renew" ]; then
    ip -4 addr flush dev "$interface"
    ip -4 addr add "$ip/24" dev "$interface"
fi
exit 0
EOF
chmod +x /tmp/udhcpc-test.script
ip netns exec $CLI_NS timeout 20 busybox udhcpc -i veth-cli -f -q -n \
  -s /tmp/udhcpc-test.script 2>&1 || true

# 6) Resultado ------------------------------------------------------
echo
echo "===================== RESULTADO ====================="
echo "-> IP que o cliente recebeu:"
ip netns exec $CLI_NS ip -4 addr show veth-cli | grep inet || echo "   (nenhum - veja /tmp/dhcpd-test.log)"
echo
echo "-> Lease registrado pelo servidor:"
grep -A7 "^lease" $LEASES | tail -20 || echo "   (sem leases)"
echo
sleep 2
echo "-> Diálogo DHCP segundo o log do servidor (sequência DORA da Questão 1):"
grep -iE "DHCPDISCOVER|DHCPOFFER|DHCPREQUEST|DHCPACK" /tmp/dhcpd-test.log || echo "   (nada no log)"
echo
echo "-> Mesmo diálogo capturado na rede (tcpdump):"
tcpdump -r $PCAP -n 2>/dev/null | grep -iE "discover|offer|request|ack" || echo "   (nada capturado)"
echo "====================================================="
echo
echo "Captura completa salva em: $PCAP  (abra no Wireshark para o print do relatório)"
echo "Log do servidor:           /tmp/dhcpd-test.log"
