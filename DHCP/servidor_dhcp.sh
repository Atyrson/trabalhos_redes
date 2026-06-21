#!/bin/bash
#
# Configuração do Servidor DHCP - Empresa PipeVendas
# Fundamentos de Redes de Computadores - 2026.1
#
# Roda na máquina que será o servidor DHCP (IP fixo 192.168.10.4).
# Distribui IPs dinâmicos para as estações da bancada, entregando
# junto o gateway (roteador) e o servidor DNS do grupo.

set -e

# Configurações da empresa ==========================
EMPRESA="PipeVendas"
DOMINIO="pipevendas.com.br"

# IPs da infraestrutura (mesmo plano do DNS) ========
IP_ROTEADOR="192.168.10.254"   # gateway
IP_DNS="192.168.10.2"          # servidor DNS do grupo
IP_DHCP="192.168.10.4"         # este servidor
REDE="192.168.10.0"
MASCARA="255.255.255.0"
BROADCAST="192.168.10.255"

# Faixa de IPs ofertada aos clientes ================
RANGE_INI="192.168.10.100"
RANGE_FIM="192.168.10.200"

# Interface de rede onde o DHCP vai escutar ==========
# AJUSTE para a interface da sua máquina (veja com: ip a)
INTERFACE="enp0s3"

# Etapa 1 ===========================================
echo "========= Instalando servidor DHCP para $EMPRESA... ========="
sudo apt update
sudo apt install -y isc-dhcp-server

# Etapa 2 ===========================================
# OBS.: o roteiro antigo cita 'dhcp3-server' e '/etc/dhcpd.conf'.
# Nas versões atuais do Ubuntu/Debian o pacote é 'isc-dhcp-server'
# e o arquivo de configuração fica em '/etc/dhcp/dhcpd.conf'.
echo "Escrevendo /etc/dhcp/dhcpd.conf..."

sudo tee /etc/dhcp/dhcpd.conf > /dev/null <<EOF
# ===== Configuração DHCP - $EMPRESA =====

# Tempos de lease (em segundos)
default-lease-time 600;     # 10 min
max-lease-time 7200;        # 2 horas

# Este servidor é a autoridade oficial de DHCP nesta rede.
# Corrige clientes que pedem endereços incoerentes (envia DHCPNAK).
authoritative;

# Opções globais entregues a todos os clientes
option subnet-mask $MASCARA;
option broadcast-address $BROADCAST;
option routers $IP_ROTEADOR;
option domain-name-servers $IP_DNS;
option domain-name "$DOMINIO";

# Sub-rede da intranet $REDE/24
subnet $REDE netmask $MASCARA {
    range $RANGE_INI $RANGE_FIM;
    option routers $IP_ROTEADOR;
    option domain-name-servers $IP_DNS;
    option domain-name "$DOMINIO";
}

# ---------------------------------------------------------
# RESERVA POR MAC (responde a Questão 2 do roteiro)
# Uma estação cujo MAC seja conhecido recebe SEMPRE o mesmo IP.
# Troque o MAC abaixo pelo da estação cliente real (ip a no cliente).
# ---------------------------------------------------------
host estacao-fixa {
    hardware ethernet 08:00:27:aa:bb:cc;
    fixed-address 192.168.10.50;
    option host-name "estacao1";
}
EOF

# Etapa 3 ===========================================
echo "Definindo a interface de escuta ($INTERFACE)..."
sudo sed -i "s/^INTERFACESv4=.*/INTERFACESv4=\"$INTERFACE\"/" /etc/default/isc-dhcp-server

# Etapa 4 ===========================================
echo "Validando a sintaxe do dhcpd.conf..."
sudo dhcpd -t -cf /etc/dhcp/dhcpd.conf

# Etapa 5 ===========================================
echo "Reiniciando o servidor DHCP..."
sudo systemctl restart isc-dhcp-server
sudo systemctl enable isc-dhcp-server

# Etapa 6 ===========================================
echo ""
echo "=== CONFIGURAÇÃO CONCLUÍDA ==="
echo "Servidor DHCP: $IP_DHCP  (interface $INTERFACE)"
echo "Faixa ofertada: $RANGE_INI - $RANGE_FIM"
echo "Gateway: $IP_ROTEADOR | DNS: $IP_DNS | Domínio: $DOMINIO"
echo ""
echo "Ver status:        sudo systemctl status isc-dhcp-server"
echo "Ver leases ativos: cat /var/lib/dhcp/dhcpd.leases"
echo "Rodar em modo debug (mostra o diálogo na tela):"
echo "   sudo systemctl stop isc-dhcp-server"
echo "   sudo /usr/sbin/dhcpd -d -f $INTERFACE"
echo ""
echo "Concluído."
