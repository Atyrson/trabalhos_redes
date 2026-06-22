# Serviço de Correio Eletrônico – SMTP com Postfix e POP3 com Dovecot

Este guia documenta a instalação, configuração e validação do servidor de e-mails da intranet do grupo, executado na **máquina física do laboratório da UnB Gama**. O servidor SMTP utiliza o **Postfix** e o serviço de liberação POP3 utiliza o **Dovecot**.

---

## A) Pré-requisitos

- IP estático configurado: `192.168.10.2/24` (mesma máquina que serve o WWW/Apache2).
- Registro `MX` no servidor DNS (BIND9) do grupo apontando `mail.alunos.com.br` para `192.168.10.2`.
- Acesso root/sudo na máquina servidora.

**Verificação do registro MX no DNS (execute no servidor DNS do grupo):**
```bash
# No servidor BIND9, o arquivo de zona deve conter:
# alunos.com.br.    IN  MX  10  mail.alunos.com.br.
# mail.alunos.com.br. IN A  192.168.10.2

# Para testar a resolução a partir de qualquer máquina da bancada:
nslookup -type=MX alunos.com.br 192.168.10.2
```

---

## B) Fase 1 – Instalação do Postfix

### 1. Verificar se o Postfix já está instalado

```bash
whereis postfix
```

Se instalado, a saída será semelhante a:
```
postfix: /usr/sbin/postfix /etc/postfix /usr/lib/postfix /usr/man/man1/postfix.1.bz2
```

### 2. Instalar o Postfix (se não estiver instalado)

```bash
sudo apt-get install postfix
```

Durante a instalação, será apresentado um assistente de configuração. Siga os passos abaixo.

---

## C) Fase 2 – Configuração do Postfix via dpkg-reconfigure

Para configurar (ou reconfigurar) o Postfix com a interface interativa:

```bash
sudo dpkg-reconfigure postfix
```

Siga as telas na ordem abaixo, selecionando os valores indicados:

| Tela | Valor a selecionar |
|------|-------------------|
| Tipo de configuração geral do e-mail | **Internet Site** |
| Destinos SMTP a aceitar e-mails | **(deixar em branco / NONE)** |
| Nome do sistema de e-mail (System mail name) | `mail.alunos.com.br` |
| Outros destinos aceitos | `mail.alunos.com.br, localhost.localdomain, localhost` |
| Forçar atualizações síncronas da fila de e-mail | **No** |
| Redes locais (mynetworks) | `127.0.0.0/8, 192.168.10.0/24` |
| Usar procmail para entrega local | **Yes** |
| Tamanho máximo de caixa de correio (0 = ilimitado) | `0` |
| Extensão de endereço local | `+` |
| Protocolos de internet a usar | **all** |

> **Obs.:** `mail.alunos.com.br` é o hostname definido pelo grupo no DNS. Substitua `192.168.10.0/24` pela faixa de rede da bancada caso seja diferente.

Após o assistente, o Postfix é reiniciado automaticamente.

---

## D) Fase 3 – Verificação e Testes do Servidor SMTP Local

### 1. Verificar se o Postfix está em execução

```bash
ps -aux | grep postfix
```

Saída esperada: processos `master`, `qmgr`, `pickup` rodando.

Caso não esteja ativo:
```bash
sudo systemctl start postfix
# ou, no método legado do roteiro:
sudo /etc/init.d/postfix start
```

Verificar também se a porta 25 (SMTP) está aberta:
```bash
sudo ss -tlnp | grep :25
```

### 2. Criar usuários no sistema operacional

Os usuários do Linux são as caixas de correio do Postfix. Crie um usuário para cada integrante do grupo:

```bash
sudo adduser aluno1
sudo adduser aluno2
# (repita para cada integrante, usando o nome real)
```

### 3. Enviar um e-mail de teste via linha de comando

```bash
# Instalar o utilitário 'mail' caso não esteja disponível
sudo apt-get install mailutils

# Enviar um e-mail para o usuário aluno1
mail aluno1@mail.alunos.com.br
```

O terminal pedirá o assunto (Subject) e depois o corpo da mensagem. Finalize com **Ctrl+D** para enviar (o `.` sozinho é sintaxe do protocolo SMTP bruto via telnet, não do comando `mail`).

Alternativa para envio não-interativo:
```bash
echo "Corpo do e-mail de teste" | mail -s "Assunto Teste" aluno1@mail.alunos.com.br
```

### 4. Verificar se o e-mail foi entregue

O Postfix, por padrão, usa o formato **mbox** e armazena os e-mails em `/var/mail/<usuario>`:

```bash
ls /var/mail/
# deve aparecer o arquivo com o nome do usuário (ex: aluno1)

cat /var/mail/aluno1
# exibe todos os e-mails recebidos por aluno1
```

---

## E) Fase 4 – Configuração do Dovecot (POP3)

O **Dovecot** é o MDA (Mail Delivery Agent) que permite que clientes de e-mail externos acessem a caixa postal via protocolo POP3 (porta 110) ou IMAP (porta 143).

### 1. Instalar o Dovecot

```bash
sudo apt-get install dovecot-pop3d dovecot-imapd
```

### 2. Configurar o Dovecot para ler o formato mbox

Edite o arquivo de configuração principal de caixas de correio:

```bash
sudo nano /etc/dovecot/conf.d/10-mail.conf
```

Localize e defina o parâmetro `mail_location`:
```
mail_location = mbox:~/mail:INBOX=/var/mail/%u
```

> Se quiser usar o formato **maildir** (recomendado para ambientes modernos), veja a Questão 2 do relatório.

### 3. Configurar autenticação simples (sem TLS, ambiente de laboratório)

Edite o arquivo de autenticação:
```bash
sudo nano /etc/dovecot/conf.d/10-auth.conf
```

Localize e ajuste:
```
disable_plaintext_auth = no
auth_mechanisms = plain login
```

Edite o arquivo de listeners:
```bash
sudo nano /etc/dovecot/conf.d/10-master.conf
```

Certifique-se de que os serviços `imap-login` e `pop3-login` estejam sem SSL para o laboratório:
```
service pop3-login {
  inet_listener pop3 {
    port = 110
  }
}
```

### 4. Iniciar e verificar o Dovecot

```bash
sudo systemctl restart dovecot
sudo systemctl status dovecot

# Verificar se as portas POP3 (110) e IMAP (143) estão abertas
sudo ss -tlnp | grep -E ':110|:143'
```

---

## F) Fase 5 – Testes de Protocolo via Telnet

### Questão F5 – Enviar e-mail via Telnet na porta SMTP (25)

Conecte-se diretamente ao servidor SMTP e envie um e-mail usando os comandos brutos do protocolo:

```bash
telnet 192.168.10.2 25
```

Após a conexão, execute os comandos na sequência:
```
HELO mail.alunos.com.br
MAIL FROM:<aluno2@mail.alunos.com.br>
RCPT TO:<aluno1@mail.alunos.com.br>
DATA
Subject: Teste via Telnet SMTP
From: aluno2@mail.alunos.com.br
To: aluno1@mail.alunos.com.br

Este é um e-mail enviado diretamente pelo protocolo SMTP via Telnet.
.
QUIT
```

> Cada ponto final (`.`) em linha sozinha encerra o corpo e dispara o envio. O servidor deve responder `250 Ok: queued as <id>`.

### Questão F6 – Receber e-mail via Telnet na porta POP3 (110)

Conecte-se diretamente ao servidor POP3 para ler os e-mails de aluno1:

```bash
telnet 192.168.10.2 110
```

Após a conexão, execute os comandos:
```
USER aluno1
PASS <senha_do_aluno1>
LIST
RETR 1
QUIT
```

Significado de cada comando:
- `USER` – informa o nome do usuário da caixa postal.
- `PASS` – autentica com a senha do usuário Linux.
- `LIST` – lista os e-mails disponíveis na caixa (número e tamanho em bytes).
- `RETR 1` – baixa e exibe o conteúdo do e-mail número 1.
- `QUIT` – encerra a sessão e aplica as alterações (marca mensagens como lidas/excluídas).

---

## G) Questões para o Relatório

### G1 – Modificações em `/etc/postfix/main.cf` e `master.cf`

**`/etc/postfix/main.cf`** – arquivo de configuração principal. Parâmetros alterados pelo `dpkg-reconfigure`:

| Parâmetro | Valor definido | Efeito |
|-----------|---------------|--------|
| `myhostname` | `mail.alunos.com.br` | Nome FQDN do servidor de e-mail. É anunciado no banner SMTP e usado pelo DNS reverso. |
| `mydomain` | `alunos.com.br` | Domínio base do servidor. |
| `myorigin` | `$mydomain` | Domínio que aparece no campo `From` de e-mails enviados localmente sem domínio explícito. |
| `inet_interfaces` | `all` | O Postfix escuta em todas as interfaces de rede (0.0.0.0), aceitando conexões externas. |
| `mydestination` | `mail.alunos.com.br, localhost.localdomain, localhost` | Lista de domínios cujos e-mails são entregues localmente (não retransmitidos). |
| `mynetworks` | `127.0.0.0/8, 192.168.10.0/24` | Faixas de IP autorizadas a usar o servidor como relay sem autenticação. |
| `mailbox_size_limit` | `0` | Sem limite de tamanho de caixa postal. |
| `recipient_delimiter` | `+` | Caractere separador para extensões de endereço (ex: `user+tag@dominio`). |

**`/etc/postfix/master.cf`** – arquivo de controle de serviços (daemons internos do Postfix). Define quais processos são iniciados, com quais permissões e parâmetros. Normalmente não é editado diretamente; o `dpkg-reconfigure` não o altera. Modificações manuais comuns incluem: habilitar a porta de submissão (587) e ativar autenticação SASL.

### G2 – Diferença entre `mbox` e `maildir`

| Critério | `mbox` | `maildir` |
|----------|--------|-----------|
| **Estrutura** | Um único arquivo por usuário (`/var/mail/usuario`). Todos os e-mails concatenados neste arquivo. | Um diretório por usuário (`~/Maildir/`). Cada e-mail é um arquivo separado. |
| **Concorrência** | Requer bloqueio de arquivo (lock) para leitura/escrita simultânea. Propenso a corrupção se o acesso for simultâneo. | Sem necessidade de lock. Múltiplos processos podem acessar simultaneamente sem risco de corrupção. |
| **Performance** | Lenta para caixas grandes: abrir a caixa exige ler o arquivo inteiro. | Rápida: acessar, apagar ou mover um e-mail é uma operação sobre um único arquivo pequeno. |
| **Portabilidade** | Formato histórico, amplamente suportado por clientes antigos. | Padrão moderno, suportado por Dovecot, Postfix, Mutt, Thunderbird etc. |

**Como instalar o maildir no Postfix:**

No arquivo `/etc/postfix/main.cf`, adicione:
```
home_mailbox = Maildir/
```

No Dovecot (`/etc/dovecot/conf.d/10-mail.conf`), altere:
```
mail_location = maildir:~/Maildir
```

Crie o diretório para cada usuário existente:
```bash
sudo maildirmake.dovecot /home/aluno1/Maildir aluno1
```

### G3 – Esquemas de Autenticação SASL/TLS

**SASL** (Simple Authentication and Security Layer) é uma framework que separa a lógica de autenticação do protocolo de aplicação. No Postfix, o SASL permite que clientes externos (ex: Thunderbird) se autentiquem antes de usar o servidor como relay, prevenindo uso por spammers.

**TLS** (Transport Layer Security) cifra o canal de comunicação SMTP, protegendo as credenciais e o conteúdo das mensagens em trânsito.

**Solução adotada para o laboratório: Dovecot SASL**

O Dovecot já instalado para o POP3 pode fornecer o serviço SASL para o Postfix sem instalar pacotes adicionais.

**Passos:**

1. Habilitar o socket SASL do Dovecot em `/etc/dovecot/conf.d/10-master.conf`:
```
service auth {
  unix_listener /var/spool/postfix/private/auth {
    mode = 0660
    user = postfix
    group = postfix
  }
}
```

2. Em `/etc/postfix/main.cf`, adicionar:
```
smtpd_sasl_type = dovecot
smtpd_sasl_path = private/auth
smtpd_sasl_auth_enable = yes
smtpd_recipient_restrictions = permit_sasl_authenticated, permit_mynetworks, reject_unauth_destination
```

3. Reiniciar ambos os serviços:
```bash
sudo systemctl restart dovecot postfix
```

### G4 – RFC822 e MIME types

**RFC822** (atualizado pela RFC2822/RFC5322) define o **formato de mensagens de e-mail texto simples**: cabeçalhos (`From`, `To`, `Subject`, `Date`) separados do corpo por uma linha em branco. Suporta apenas texto ASCII de 7 bits. Não prevê anexos ou caracteres internacionais.

**MIME** (Multipurpose Internet Mail Extensions – RFCs 2045–2049) estende o RFC822 para suportar:

| MIME Type | Exemplo | Descrição |
|-----------|---------|-----------|
| `text/plain` | Corpo de e-mail simples | Texto sem formatação |
| `text/html` | E-mail com HTML | Conteúdo formatado em HTML |
| `multipart/mixed` | E-mail com anexo | Combina múltiplas partes (texto + arquivo) |
| `multipart/alternative` | E-mail dual (texto/HTML) | Versões alternativas do mesmo conteúdo |
| `image/jpeg`, `image/png` | Imagem anexada | Arquivo de imagem codificado em Base64 |
| `application/pdf` | Documento PDF | Arquivo binário como anexo |
| `application/octet-stream` | Qualquer binário | Tipo genérico para arquivos arbitrários |

A principal diferença: RFC822 é um formato de mensagem; MIME é um conjunto de extensões que define como conteúdos não-ASCII e múltiplas partes são codificados e transportados dentro desse formato.

### G5 – Sessão Telnet SMTP (Resultado da Experiência)

```
$ telnet 127.0.0.1 25

220 mail.alunos.com.br ESMTP Postfix (Ubuntu)
HELO mail.alunos.com.br
250 mail.alunos.com.br
MAIL FROM:<aluno2@mail.alunos.com.br>
250 2.1.0 Ok
RCPT TO:<aluno1@mail.alunos.com.br>
250 2.1.5 Ok
DATA
354 End data with <CR><LF>.<CR><LF>
Subject: Teste Telnet SMTP
From: aluno2@mail.alunos.com.br
To: aluno1@mail.alunos.com.br

E-mail enviado via Telnet - Questao F5 do roteiro.
.
250 2.0.0 Ok: queued as 872797C157C
QUIT
221 2.0.0 Bye
```

**Análise:** O código `220` é o banner de boas-vindas do servidor. `250 Ok` confirma que cada etapa foi aceita. `354` autoriza o envio do corpo. `221` encerra a conexão. O e-mail é enfileirado e entregue localmente ao `/var/mail/aluno1`.

### G6 – Sessão Telnet POP3 (Resultado da Experiência)

```
$ telnet 127.0.0.1 110

+OK Dovecot (Ubuntu) ready.
USER aluno1
+OK
PASS senha123
+OK Logged in.
LIST
+OK 2 messages:
1 551
2 577
.
RETR 1
+OK 551 octets
Return-Path: <aluno2@mail.alunos.com.br>
X-Original-To: aluno1@mail.alunos.com.br
Delivered-To: aluno1@mail.alunos.com.br
Received: by mail.alunos.com.br (Postfix, from userid 1000)
        id B14547C157A; Fri, 19 Jun 2026 10:42:36 -0300 (-03)
Subject: Teste SMTP - Roteiro FRC
From: aluno2@mail.alunos.com.br
To: <aluno1@mail.alunos.com.br>
Date: Fri, 19 Jun 2026 10:42:36 -0300
Message-Id: <20260619134236.B14547C157A@mail.alunos.com.br>

Este e-mail foi enviado via Postfix local. Teste do roteiro SMTP.
.
QUIT
+OK Logging out.
```

**Análise:** O prefixo `+OK` indica sucesso em todos os comandos POP3. `LIST` retornou 2 mensagens (551 e 577 bytes). `RETR 1` baixou o conteúdo completo, incluindo cabeçalhos adicionados pelo Postfix (`Return-Path`, `Received`, `Message-Id`). `-ERR` seria retornado em caso de falha (ex: senha errada ou mensagem inexistente).

---

## H) Resumo dos Arquivos de Configuração

| Arquivo | Propósito |
|---------|-----------|
| `/etc/postfix/main.cf` | Configuração principal do Postfix (domínio, redes, limites) |
| `/etc/postfix/master.cf` | Controle de serviços internos do Postfix (daemons, portas) |
| `/etc/dovecot/conf.d/10-mail.conf` | Define local e formato das caixas de correio |
| `/etc/dovecot/conf.d/10-auth.conf` | Define mecanismos de autenticação do Dovecot |
| `/etc/dovecot/conf.d/10-master.conf` | Configura os serviços de rede do Dovecot (POP3, IMAP, SASL) |
| `/var/mail/<usuario>` | Caixa de entrada no formato mbox (padrão) |
| `~/Maildir/` | Caixa de entrada no formato maildir (alternativa moderna) |

## I) Integração com os Outros Serviços da Intranet

- **DNS (BIND9):** O Postfix depende do registro `MX` para saber para qual servidor entregar e-mails externos ao domínio. O integrante do DNS deve adicionar: `alunos.com.br. IN MX 10 mail.alunos.com.br.` e `mail.alunos.com.br. IN A 192.168.10.2`.
- **WWW (Apache2):** Os mesmos usuários criados com `adduser` possuem tanto a caixa de correio em `/var/mail/` quanto a pasta `public_html` para o servidor web.
- **DHCP:** Os clientes da bancada configurados automaticamente pelo DHCP apontam para o DNS do grupo, que resolve `mail.alunos.com.br` e permite o envio de e-mails pelo servidor Postfix.
