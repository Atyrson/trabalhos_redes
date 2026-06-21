# Guia rápido — Montando as VMs para o DHCP (VirtualBox)

Objetivo: 1 VM **servidor DHCP** (192.168.10.4) + 1 VM **cliente** que pega IP
automático, numa rede isolada (igual ao que vai na apresentação do laboratório).

---

## 0. Instalar o VirtualBox (no seu Ubuntu)

```bash
sudo apt update
sudo apt install -y virtualbox
```

Baixe uma ISO leve para as VMs: **Ubuntu Server 24.04** (https://ubuntu.com/download/server).
Server é mais leve que o Desktop e basta para os serviços.

---

## 1. Criar a VM do SERVIDOR

1. VirtualBox → **Novo** → nome `dhcp-server`, tipo Linux/Ubuntu 64-bit, 2 GB RAM, 10 GB disco.
2. Aponte a ISO do Ubuntu Server e instale o sistema (usuário/senha simples).
3. **Configure 2 placas de rede** (Configurações → Rede), ANTES de ligar:
   - **Adaptador 1**: `NAT`  → serve só para baixar pacotes (apt) e ter internet.
   - **Adaptador 2**: `Rede Interna`, nome `intranet`  → é a rede do laboratório.

> Importante: a "Rede Interna" do VirtualBox **não tem DHCP próprio**, então
> quem vai distribuir IP nela é o SEU servidor. É isso que queremos.

---

## 2. Criar a VM do CLIENTE

Jeito mais rápido: **clonar** a VM do servidor.
- Clique direito em `dhcp-server` → **Clonar** → nome `dhcp-cliente` → *Clone completo*
  → marque **"Gerar novos endereços MAC para todas as placas"**.

Confira que o cliente também tem:
   - Adaptador 1: `NAT`
   - Adaptador 2: `Rede Interna` nome `intranet` (o mesmo nome do servidor!)

---

## 3. Configurar IP fixo no SERVIDOR

Ligue a VM `dhcp-server`. Descubra os nomes das placas:

```bash
ip a
```

Geralmente: `enp0s3` = NAT (Adaptador 1), `enp0s8` = Rede Interna (Adaptador 2).
A rede da intranet é a **enp0s8**. Dê IP fixo a ela com netplan:

```bash
sudo tee /etc/netplan/99-intranet.yaml > /dev/null <<'EOF'
network:
  version: 2
  ethernets:
    enp0s8:
      dhcp4: false
      addresses: [192.168.10.4/24]
EOF
sudo chmod 600 /etc/netplan/99-intranet.yaml
sudo netplan apply
```

Confirme: `ip a show enp0s8` deve mostrar `192.168.10.4`.

---

## 4. Subir o servidor DHCP

Copie os scripts da pasta `DHCP/` para a VM (pen drive, scp, ou git).
**Edite `servidor_dhcp.sh`** e ajuste a interface para a da rede interna:

```bash
INTERFACE="enp0s8"
```

Depois rode:

```bash
sudo bash servidor_dhcp.sh
sudo systemctl status isc-dhcp-server   # deve estar "active (running)"
```

---

## 5. Testar no CLIENTE

Ligue a VM `dhcp-cliente`. A placa da intranet (enp0s8) deve pedir IP:

```bash
sudo dhclient -v enp0s8
ip -4 addr show enp0s8        # deve mostrar um IP 192.168.10.100-200
```

Pronto: o cliente pegou IP do SEU servidor. Para o relatório (Questão 1),
no servidor rode antes do cliente pedir:

```bash
sudo tcpdump -i enp0s8 -n 'port 67 or port 68'
```

e capture as 4 mensagens DORA (Discover → Offer → Request → Ack).

---

## Dicas / problemas comuns

- **Cliente não pega IP**: confirme que as duas VMs estão na MESMA "Rede Interna"
  (mesmo nome `intranet`) e que o servidor está `active (running)`.
- **Conflito de IP**: garanta que o range (.100–.200) não bate com os IPs fixos
  dos servidores (.2 .3 .4 .5 .254).
- **Quer internet nas VMs também**: já está resolvido pelo Adaptador 1 (NAT).
- Para a integração com o DNS do colega, depois aponte `option domain-name-servers`
  para 192.168.10.2 (já está assim no script).
```
