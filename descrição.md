Aqui está o passo a passo técnico completo e definitivo para realizar a implantação na **máquina física real** do laboratório da UnB Gama. Este guia reúne todos os comandos necessários tanto para configurar o seu servidor quanto para orientar os seus colegas a testarem e se comunicarem com a sua máquina a partir dos outros computadores da bancada.

---

## 🔌 Fase 1: Infraestrutura Física e Rede Local (Todas as Máquinas)

Antes de rodar qualquer comando, o grupo deve realizar a interconexão física da bancada:

1. Conecte todas as máquinas físicas (servidor e clientes) ao **Switch** do laboratório utilizando os cabos de rede de par trançado.


2. Em **todas** as máquinas, identifique o nome exato da interface de rede física ativa:
```bash
ip addr

```


*(Identifique o nome que aparece, como `enp3s0` ou `eth0`. Substitua nos comandos abaixo caso mude).*
3. Conforme exigido no roteiro, desative o gerenciador automático de rede para evitar que ele mude as configurações durante o experimento:


```bash
sudo systemctl stop NetworkManager
sudo systemctl disable NetworkManager

```



---

## 🖥️ Fase 2: Configuração do Servidor Web (A Sua Máquina)

Execute estes comandos na máquina física que atuará como o Servidor Central da Intranet:

### 1. Mascaramento e IP Estático

Defina o IP Classe C fixo do servidor para que a rede tenha um ponto central estável:

```bash
sudo ip addr flush dev enp3s0
sudo ip addr add 192.168.10.2/24 dev enp3s0
sudo ip link set enp3s0 up

```

### 2. Verificação do Serviço Apache2

Certifique-se de que o servidor Web está ativo no sistema operacional:

```bash
ps aux | grep apache

```

(Caso precise inicializar, use `sudo systemctl start apache2` ou o comando do roteiro `/etc/init.d/apache2 start`).

### 3. Implantação do Portal Central

Abra o arquivo principal do servidor para colar o código HTML limpo da nossa conversa anterior:

```bash
sudo nano /var/www/html/index.html

```

### 4. Criação dos Usuários e Pastas Pessoais (`public_html`)

Ative o módulo de pastas domésticas e configure o usuário de exemplo (`atyrson`) com as permissões restritas do roteiro:

```bash
# Ativa o módulo de diretórios de usuários
sudo a2enmod userdir

# Cria o usuário do aluno no sistema operacional
sudo adduser atyrson

# Cria a pasta de publicação do aluno e define permissões estritas
sudo mkdir -p /home/atyrson/public_html
sudo chmod 755 /home/atyrson
sudo chmod 755 /home/atyrson/public_html
sudo chown -R atyrson:atyrson /home/atyrson/public_html

# Cria o arquivo index.html dentro da pasta dele
sudo nano /home/atyrson/public_html/index.html

# Cria a restrição de listagem de arquivos (.htaccess)
sudo nano /home/atyrson/public_html/.htaccess

```

*(Dentro do `.htaccess`, escreva apenas `Options -Indexes`. Salve e saia).*

```bash
# Corrige a propriedade do arquivo oculto de diretivas
sudo chown atyrson:atyrson /home/atyrson/public_html/.htaccess

```

### 5. Habilitar Diretivas Locais e Virtual Hosts

Abra o arquivo de configuração do módulo para permitir a leitura do `.htaccess`:

```bash
sudo nano /etc/apache2/mods-enabled/userdir.conf

```

*(Garanta que o bloco `<Directory /home/*/public_html>` contenha a linha `AllowOverride All`).*

Crie o arquivo do domínio virtual do aluno:

```bash
sudo nano /etc/apache2/sites-available/atyrson.conf

```

Cole a estrutura de Virtual Host:

```apache
<VirtualHost *:80>
    ServerName www.atyrson.com.br
    DocumentRoot /home/atyrson/public_html
    ErrorLog ${APACHE_LOG_DIR}/atyrson_error.log
    CustomLog ${APACHE_LOG_DIR}/atyrson_access.log combined
</VirtualHost>

```

Ative o site virtual e o módulo SSI para a exibição de conteúdos dinâmicos:

```bash
sudo a2ensite atyrson.conf
sudo a2enmod include

```

### 6. Validação Geral do Servidor

```bash
sudo apache2ctl configtest
sudo systemctl restart apache2

```

---

## 💻 Fase 3: Comandos de Comunicação para as Outras Máquinas (Clientes)

Distribua estes comandos para os outros integrantes do grupo executarem em suas respectivas máquinas físicas da bancada para acessar o seu servidor:

### 1. Configuração do IP do Cliente

Cada máquina cliente deve assumir um IP diferente na mesma sub-rede (ex: máquina do Aluno 2 usa o final `.3`, Aluno 4 usa o final `.4`):

```bash
sudo ip addr flush dev enp3s0
sudo ip addr add 192.168.10.3/24 dev enp3s0
sudo ip link set enp3s0 up

```

### 2. Teste de Conectividade de Baixo Nível (Ping)

Antes de testar o navegador, o cliente deve validar se alcança a sua máquina fisicamente através do cabo de rede:

```bash
ping 192.168.10.2

```

### 3. Resolução de Nomes (Fallback enquanto o DNS do grupo não liga)

Se o integrante do DNS (BIND9) ainda estiver configurando o servidor dele, os clientes podem apontar diretamente para você editando o arquivo de hosts estáticos local:

```bash
sudo nano /etc/hosts

```

Adicione a seguinte linha apontando os domínios para o IP do seu servidor:

```text
192.168.10.2    www.alunos.com.br www.atyrson.com.br

```

### 4. Acessando o Servidor via Linha de Comando (Modo Texto)

Para demonstrar o funcionamento rápido diretamente pelo terminal ou testar cabeçalhos:

```bash
# Baixa e exibe o código do portal principal na tela
curl http://www.alunos.com.br

# Baixa e exibe o código do relatório do aluno específico
curl http://www.atyrson.com.br

```

### 5. Simulação do Protocolo Bruto HTTP via Telnet (Questão 8)

Para responder à Questão 8 do relatório, qualquer membro pode abrir uma conexão TCP direta na porta 80 do seu servidor:

```bash
telnet 192.168.10.2 80

```

Assim que a conexão estabelecer, o aluno deve digitar os comandos e apertar **Enter duas vezes seguidas**:

```http
GET /index.html HTTP/1.1
Host: www.alunos.com.br


```

### 6. Acesso Visual via Navegador

Por fim, basta abrir o Mozilla Firefox ou Google Chrome na máquina cliente e digitar as URLs na barra de endereços para a validação visual completa exigida na apresentação:

* 
`http://www.alunos.com.br` (Carrega o portal corporativo com os dados do grupo).


* 
`http://www.atyrson.com.br` (Acessa o domínio virtual isolado com o relatório individual do aluno).
