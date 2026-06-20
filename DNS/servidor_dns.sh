#!/bin/bash

set -e

# Configurações da empresa
EMPRESA="PipeVendas"
DOMINIO="pipevendas.com.br"
DNS_IP="192.168.10.2"  # Servidor DNS dedicado

# IPs dos servidores conforme planejado
IP_ROTEADOR="192.168.10.254"
IP_DNS="192.168.10.2"
IP_WWW="192.168.10.3"
IP_DHCP="192.168.10.4"
IP_SMTP="192.168.10.5"

# Etapa 1 ==========================================
echo "========= Instalando BIND para $EMPRESA... ========="

sudo apt update
sudo apt install -y bind9 bind9utils dnsutils

# Etapa 2 ==========================================
echo "Configurando resolver..."

sudo tee /etc/resolv.conf > /dev/null <<EOF
domain $DOMINIO
search $DOMINIO
nameserver $DNS_IP
EOF

# Etapa 3 ==========================================
echo "Configurando zonas do $DOMINIO..."

sudo tee /etc/bind/named.conf.local > /dev/null <<EOF
// Zona direta do domínio $DOMINIO
zone "$DOMINIO" {
    type master;
    file "/etc/bind/db.$DOMINIO";
    allow-update { 192.168.10.4; };  // DHCP pode atualizar
};

// Zona reversa para rede 192.168.10.0/24
zone "10.168.192.in-addr.arpa" {
    type master;
    file "/etc/bind/db.10.168.192";
    allow-update { 192.168.10.4; };  // DHCP pode atualizar
};

EOF

# Etapa 4 ==========================================
echo "Criando zona direta para $DOMINIO..."

sudo tee /etc/bind/db.$DOMINIO > /dev/null <<EOF
\$TTL 86400

@ IN SOA ns1.$DOMINIO. admin.$DOMINIO. (
    2026062001  ; Serial (YYYYMMDDNN)
    21600       ; Refresh (6 horas)
    1800        ; Retry (30 minutos)
    604800      ; Expire (1 semana)
    86400       ; Minimum TTL (24 horas)
)

; Servidores DNS
@ IN NS ns1.$DOMINIO.
@ IN NS ns2.$DOMINIO.

; Servidor de email (MX)
@ IN MX 10 mail.$DOMINIO.

; Registros A (mapeamento nome → IP) - SOMENTE SERVIDORES FIXOS
localhost IN A 127.0.0.1

; Servidores da infraestrutura (IPs fixos)
ns1     IN A $IP_DNS          ; Servidor DNS principal
ns2     IN A $IP_DNS          ; Servidor DNS secundário (mesmo IP no lab)
router  IN A $IP_ROTEADOR     ; Gateway/Roteador
www     IN A $IP_WWW          ; Servidor Web
dhcp    IN A $IP_DHCP         ; Servidor DHCP
mail    IN A $IP_SMTP         ; Servidor de email

; Aliases (CNAME) para serviços
smtp    IN CNAME mail.$DOMINIO.
pop3    IN CNAME mail.$DOMINIO.
imap    IN CNAME mail.$DOMINIO.

; ===================================================
; NOTA: Os registros para as estações dos membros
; serão adicionados DINAMICAMENTE pelo DHCP via DDNS
; ===================================================

EOF

# Etapa 5 ==========================================
echo "Criando zona reversa para 192.168.10.0/24..."

sudo tee /etc/bind/db.10.168.192 > /dev/null <<EOF
\$TTL 86400

@ IN SOA ns1.$DOMINIO. admin.$DOMINIO. (
    2026062001  ; Serial (YYYYMMDDNN)
    21600       ; Refresh (6 horas)
    1800        ; Retry (30 minutos)
    604800      ; Expire (1 semana)
    86400       ; Minimum TTL (24 horas)
)

@ IN NS ns1.$DOMINIO.
@ IN NS ns2.$DOMINIO.

; Registros PTR para SERVIDORES (IPs fixos)
254 IN PTR router.$DOMINIO.
2   IN PTR ns1.$DOMINIO.
3   IN PTR www.$DOMINIO.
4   IN PTR dhcp.$DOMINIO.
5   IN PTR mail.$DOMINIO.

; ===================================================
; NOTA: Os registros PTR para as estações dos membros
; serão adicionados DINAMICAMENTE pelo DHCP via DDNS
; ===================================================

EOF

# Etapa 6 ==========================================
echo "Configurando permissões do diretório para atualizações dinâmicas..."

# Criar diretório para arquivos de zona com permissões adequadas
sudo chown bind:bind /etc/bind/db.$DOMINIO
sudo chown bind:bind /etc/bind/db.10.168.192

# Etapa 7 ==========================================
echo "Validando configuração..."

sudo named-checkconf

sudo named-checkzone $DOMINIO /etc/bind/db.$DOMINIO

sudo named-checkzone 10.168.192.in-addr.arpa /etc/bind/db.10.168.192

# Etapa 8 ==========================================
echo "Reiniciando BIND..."

sudo systemctl restart bind9
sudo systemctl enable bind9

# Etapa 9 ==========================================
echo ""
echo "=== CONFIGURAÇÃO CONCLUÍDA ==="
echo ""
echo "Domínio configurado: $DOMINIO"
echo "Servidor DNS: $DNS_IP"
echo ""
echo "=== REGISTROS DNS CONFIGURADOS (SERVIDORES FIXOS) ==="
echo ""
echo "SERVIDORES:"
echo "  ns1.$DOMINIO        → $IP_DNS"
echo "  router.$DOMINIO     → $IP_ROTEADOR"
echo "  www.$DOMINIO        → $IP_WWW"
echo "  dhcp.$DOMINIO       → $IP_DHCP"
echo "  mail.$DOMINIO       → $IP_SMTP"
echo ""
echo "=== INTEGRAÇÃO COM DHCP (DDNS) ==="
echo ""
echo "Para que as estações clientes sejam registradas automaticamente:"
echo ""
echo "1. No servidor DHCP (192.168.10.4), configure:"
echo ""
echo "   /etc/dhcp/dhcpd.conf:"
echo "   --------------------"
echo "   option domain-name \"$DOMINIO\";"
echo "   option domain-name-servers $IP_DNS;"
echo ""
echo "   ddns-update-style interim;"
echo "   ddns-updates on;"
echo ""
echo "   key rndc-key {"
echo "       algorithm hmac-md5;"
echo "       secret \"$(sudo rndc-confgen -a -b 256 -r /dev/urandom -q 2>/dev/null | grep -oP 'secret \"\K[^\"]+' || echo 'GERAR_SECRET')\";"
echo "   };"
echo ""
echo "   zone $DOMINIO. {"
echo "       primary $IP_DNS;"
echo "       key rndc-key;"
echo "   }"
echo ""
echo "   zone 10.168.192.in-addr.arpa. {"
echo "       primary $IP_DNS;"
echo "       key rndc-key;"
echo "   }"
echo ""
echo "   subnet 192.168.10.0 netmask 255.255.255.0 {"
echo "       range 192.168.10.100 192.168.10.200;"
echo "       option routers $IP_ROTEADOR;"
echo "       option domain-name \"$DOMINIO\";"
echo "       option domain-name-servers $IP_DNS;"
echo "   }"
echo ""
echo "2. No servidor DNS, crie a chave para comunicação com DHCP:"
echo "   sudo rndc-confgen -a -b 256"
echo ""
echo "3. Configure o arquivo /etc/bind/named.conf para incluir a chave:"
echo "   include \"/etc/bind/rndc.key\";"
echo ""
echo "=== TESTES ==="
echo ""
echo "Consulta direta (servidores):"
echo "  host www.$DOMINIO"
echo "  host mail.$DOMINIO"
echo ""
echo "Consulta reversa (servidores):"
echo "  host 192.168.10.3"
echo "  host 192.168.10.5"
echo ""
echo "Após os clientes obterem IP via DHCP, teste:"
echo "  host pedro.$DOMINIO  (se o cliente se identificou como 'pedro')"
echo "  host 192.168.10.xxx  (IP obtido pelo cliente)"
echo ""
echo "Status do serviço:"
echo "  sudo systemctl status bind9"
echo ""
echo "Monitorar atualizações DDNS:"
echo "  sudo tail -f /var/log/syslog | grep -i ddns"
echo ""
echo "Concluído."