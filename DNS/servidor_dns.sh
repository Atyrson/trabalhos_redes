#!/bin/bash

set -e

DOMINIO="starwars.unb.br"

DNS_IP="192.168.10.66"

# Etapa 1 ==========================================
echo "========= Instalando BIND... ========="

sudo apt update
sudo apt install -y bind9 bind9utils dnsutils

# Etapa 2 ==========================================
echo "Configurando resolver..."

sudo tee /etc/resolv.conf > /dev/null <<EOF
domain $DOMINIO

nameserver $DNS_IP
EOF

# Etapa 3 ==========================================
echo "Configurando zonas..."

sudo tee /etc/bind/named.conf.local > /dev/null <<EOF

zone "$DOMINIO" {
    type master;
    file "/etc/bind/db.starwars";
};

zone "10.168.192.in-addr.arpa" {
    type master;
    file "/etc/bind/db.warsstar";
};

EOF

# Etapa 4 ==========================================
echo "Criando zona direta..."

sudo tee /etc/bind/db.starwars > /dev/null <<EOF
\$TTL 86400

@ IN SOA vader.$DOMINIO. root.vader.$DOMINIO. (
2026061701
21600
1800
604800
86400
)

@ IN NS vader.$DOMINIO.

@ IN MX 10 R2D2.$DOMINIO.

localhost IN A 127.0.0.1

yoda    IN A 192.168.10.1
obiwan  IN A 192.168.10.2
leia    IN A 192.168.10.3
luke    IN A 192.168.10.4
vader   IN A 192.168.10.66
R2D2    IN A 192.168.10.100

EOF

# Etapa 5 ==========================================
echo "Criando zona reversa..."

sudo tee /etc/bind/db.warsstar > /dev/null <<EOF
\$TTL 86400

@ IN SOA vader.$DOMINIO. root.vader.$DOMINIO. (
2026061701
21600
1800
604800
86400
)

@ IN NS vader.$DOMINIO.

1 IN PTR yoda.$DOMINIO.
2 IN PTR obiwan.$DOMINIO.
3 IN PTR leia.$DOMINIO.
4 IN PTR luke.$DOMINIO.
66 IN PTR vader.$DOMINIO.
100 IN PTR R2D2.$DOMINIO.

EOF

# Etapa 6 ==========================================
echo "Validando configuração..."

sudo named-checkconf

sudo named-checkzone $DOMINIO /etc/bind/db.starwars

sudo named-checkzone 10.168.192.in-addr.arpa /etc/bind/db.warsstar

# Etapa 7 ==========================================
echo "Reiniciando BIND..."

sudo systemctl restart bind9
sudo systemctl enable bind9

# Etapa 8 ==========================================
echo ""
echo "=== TESTES ==="
echo ""

echo "Consulta direta:"
echo "host luke.$DOMINIO"

echo ""
echo "Consulta reversa:"
echo "host 192.168.10.4"

echo ""
echo "Modo debug:"
echo "sudo named -f -g -d 1"

echo ""
echo "Status:"
echo "sudo systemctl status bind9"

echo ""
echo "Concluído."