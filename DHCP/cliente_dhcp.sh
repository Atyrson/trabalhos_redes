#!/bin/bash
#
# Configuração da estação CLIENTE para obter IP via DHCP.
# Roda na máquina cliente (NÃO no servidor).

set -e

# Ajuste para a interface do cliente (veja com: ip a)
INTERFACE="enp0s3"

echo "Solicitando endereço via DHCP na interface $INTERFACE..."

# Libera qualquer lease anterior e pede um novo
sudo dhclient -r "$INTERFACE"   # release
sudo dhclient -v "$INTERFACE"   # discover/request (modo verboso mostra o diálogo)

echo ""
echo "Endereço obtido:"
ip -4 addr show "$INTERFACE" | grep inet

echo ""
echo "Teste de resolução pelo DNS do grupo:"
echo "   ping -c2 192.168.10.254     # gateway"
echo "   host www.pipevendas.com.br  # depende do DNS do colega no ar"
