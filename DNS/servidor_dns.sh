#!/bin/bash

set -e

# Configurações da empresa
EMPRESA="PipeVendas"
DOMINIO="pipevendas.com.br"
DNS_IP="192.168.10.2"

# IPs dos servidores
IP_ROTEADOR="192.168.10.254"
IP_DNS="192.168.10.2"
IP_WWW="192.168.10.3"
IP_DHCP="192.168.10.4"
IP_SMTP="192.168.10.5"

# DNS públicos para forwarding
DNS_FORWARD1="8.8.8.8"      # Google
DNS_FORWARD2="1.1.1.1"      # Cloudflare
DNS_FORWARD3="9.9.9.9"      # Quad9

echo "========= Instalando BIND para $EMPRESA... ========="

sudo apt update
sudo apt install -y bind9 bind9utils dnsutils

echo ""
echo "Configurando opções do BIND (com forwarding para internet)..."

sudo tee /etc/bind/named.conf.options > /dev/null <<EOF
options {
    directory "/var/cache/bind";

    // ============================================
    // FORWARDING PARA INTERNET
    // ============================================
    // Quando o DNS não conhecer o domínio, ele
    // encaminha a consulta para estes servidores
    // ============================================
    forwarders {
        $DNS_FORWARD1;
        $DNS_FORWARD2;
        $DNS_FORWARD3;
    };

    // Política: SÓ usa os forwarders para consultas externas
    forward only;

    // ============================================
    // SEGURANÇA
    // ============================================
    // Só permite recursão para nossa rede interna
    allow-recursion { 192.168.10.0/24; };
    
    // Aceita consultas de qualquer um (mas só recursão da rede interna)
    allow-query { any; };
    
    // Validação DNSSEC (segurança)
    dnssec-validation auto;
    
    // Escuta em todas as interfaces
    listen-on { any; };
    listen-on-v6 { any; };
    
    // Não permite transferência de zona para qualquer um
    allow-transfer { none; };
    
    // Versão oculta (segurança)
    version "not available";
};

// Incluir as zonas locais
include "/etc/bind/named.conf.local";
EOF

echo ""
echo "===== Configurando resolver... ======"

sudo tee /etc/resolv.conf > /dev/null <<EOF
domain $DOMINIO
search $DOMINIO
nameserver $DNS_IP
EOF

echo ""
echo "===== Configurando zonas locais... ====="

sudo tee /etc/bind/named.conf.local > /dev/null <<EOF
// Zona direta do domínio $DOMINIO
zone "$DOMINIO" {
    type master;
    file "/etc/bind/db.$DOMINIO";
    allow-update { 192.168.10.4; };
};

// Zona reversa para rede 192.168.10.0/24
zone "10.168.192.in-addr.arpa" {
    type master;
    file "/etc/bind/db.10.168.192";
    allow-update { 192.168.10.4; };
};

EOF

echo ""
echo "===== Criando zona direta para $DOMINIO... ====="

sudo tee /etc/bind/db.$DOMINIO > /dev/null <<EOF
\$TTL 86400

@ IN SOA ns1.$DOMINIO. admin.$DOMINIO. (
    2026062001
    21600
    1800
    604800
    86400
)

; Servidores DNS
@ IN NS ns1.$DOMINIO.
@ IN NS ns2.$DOMINIO.

; Email
@ IN MX 10 mail.$DOMINIO.

; Servidores (IPs fixos)
localhost IN A 127.0.0.1

ns1     IN A $IP_DNS
ns2     IN A $IP_DNS
router  IN A $IP_ROTEADOR
www     IN A $IP_WWW
dhcp    IN A $IP_DHCP
mail    IN A $IP_SMTP

; Aliases
smtp    IN CNAME mail.$DOMINIO.
pop3    IN CNAME mail.$DOMINIO.
imap    IN CNAME mail.$DOMINIO.
site    IN CNAME www.$DOMINIO.
portal  IN CNAME www.$DOMINIO.

EOF

echo ""
echo "===== Criando zona reversa... ====="

sudo tee /etc/bind/db.10.168.192 > /dev/null <<EOF
\$TTL 86400

@ IN SOA ns1.$DOMINIO. admin.$DOMINIO. (
    2026062001
    21600
    1800
    604800
    86400
)

@ IN NS ns1.$DOMINIO.
@ IN NS ns2.$DOMINIO.

254 IN PTR router.$DOMINIO.
2   IN PTR ns1.$DOMINIO.
3   IN PTR www.$DOMINIO.
4   IN PTR dhcp.$DOMINIO.
5   IN PTR mail.$DOMINIO.

EOF

echo ""
echo "===== Configurando permissões... ====="

sudo chown bind:bind /etc/bind/db.$DOMINIO
sudo chown bind:bind /etc/bind/db.10.168.192

echo ""
echo "===== Validando configuração... ====="

sudo named-checkconf
sudo named-checkzone $DOMINIO /etc/bind/db.$DOMINIO
sudo named-checkzone 10.168.192.in-addr.arpa /etc/bind/db.10.168.192

echo ""
echo "===== Reiniciando BIND... ====="

sudo systemctl restart bind9
sudo systemctl enable bind9

echo ""
echo "=== CONFIGURAÇÃO DNS CONCLUÍDA ==="
echo ""
echo "=== COMO FUNCIONA O FORWARDING ==="
echo ""
echo "1. Cliente consulta: www.pipevendas.com.br"
echo "   → DNS local (192.168.10.2) conhece → retorna 192.168.10.3"
echo ""
echo "2. Cliente consulta: google.com"
echo "   → DNS local NÃO conhece"
echo "   → Encaminha para 8.8.8.8, 1.1.1.1, etc."
echo "   → Recebe a resposta e repassa ao cliente"
echo ""
echo "=== TESTES ==="
echo ""
echo "Teste local (deve funcionar):"
echo "  host www.$DOMINIO"
echo "  nslookup www.$DOMINIO"
echo ""
echo "Teste externo (deve funcionar via forwarding):"
echo "  host google.com"
echo "  nslookup google.com"
echo "  ping google.com"
echo ""
echo "Teste de rastreamento:"
echo "  dig google.com +trace  # Mostra toda a cadeia de resolução"
echo ""
echo "Ver logs:"
echo "  sudo tail -f /var/log/syslog | grep -i named"
echo ""
echo "Status:"
echo "  sudo systemctl status bind9"
echo ""
echo "Concluído."