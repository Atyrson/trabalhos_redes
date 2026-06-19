🛠️ 1. O que foi implementado (Sua Parte: Servidor WWW)

Você deixou pronto e validado o coração da entrega de relatórios e a vitrine da intranet da empresa fictícia:  

    Servidor Base Apache2: Instalado, ativo e testado em ambiente isolado Linux.  

    Portal Central (index.html): Uma página web unificada contendo a identificação do grupo, a tabela com as faixas de IP da rede e caixas de texto estruturadas prontas para receber os relatórios de todos os outros serviços.  

    Diretórios de Usuários (public_html): Ativação do módulo userdir que permite ao Apache hospedar páginas independentes para cada usuário do sistema Linux dentro de suas respectivas pastas /home/usuario/public_html.  

    Segurança e Restrição de Acesso (.htaccess): Configuração de diretivas locais com AllowOverride All e criação do arquivo .htaccess injetando a regra Options -Indexes, impedindo que usuários externos listem de forma maliciosa os arquivos do diretório de um aluno.  

    Domínios Virtuais (Virtual Hosts): Criação de arquivos de mapeamento em sites-available configurando o Apache para segmentar conexões HTTP de domínios diferentes (ex: www.atyrson.com.br) dentro da mesma máquina.  

    Server Side Includes (SSI): Ativação do processamento dinâmico nativo do Apache para arquivos .shtml, habilitando a inserção automática de variáveis de ambiente (como data e hora do servidor) sem o uso de linguagens de script externas.  

🔄 2. Como isso se conecta com os outros servidores

O servidor Web não funciona de forma isolada em uma intranet; ele opera no topo da camada de aplicação e depende diretamente do ecossistema que os outros integrantes do seu grupo estão montando.  

    A Conexão com o DNS (Membro 4): O Apache escuta conexões puramente através do protocolo HTTP (porta 80) utilizando endereços IP numéricos. Ele depende inteiramente do servidor BIND9 (DNS) do seu colega. É o DNS que vai receber a requisição de texto (como www.alunos.com.br ou www.atyrson.com.br) feita por qualquer computador da bancada e traduzi-la para o IP exato da sua máquina servidor web. Sem essa tradução do DNS, os domínios virtuais que você criou ficam inacessíveis pelo nome.  

    A Conexão com o DHCP (Membro 2): O servidor DHCP do seu colega distribui as configurações automáticas para as estações clientes da bancada. Quando ele configura as opções do escopo, ele injeta os parâmetros de domain-name-servers apontando para o servidor DNS do grupo. É graças a esse fluxo que um computador cliente consegue descobrir quem é o DNS e, consequentemente, abrir as páginas do seu Apache.  

    A Conexão com o SMTP/Postfix (Membro 5): O serviço de correio eletrônico Postfix gerencia o envio e recebimento de mensagens baseando-se em contas locais de usuários criadas no Linux. O acoplamento ocorre porque os mesmos usuários do sistema que possuem as caixas de correio em /var/mail/ são os usuários que possuem as pastas public_html que você configurou para hospedar os relatórios web.  

    A Conexão com o Roteador/NAT (Membro 1): O integrante responsável pelo roteamento garante que a sub-rede privada 192.168.10.0/24 consiga realizar o encaminhamento de pacotes de dados para a rede externa da UnB via masquerading (NAT).  

📋 3. O que falta para integrar com o grupo na bancada

Para consolidar o projeto final de forma integrada no laboratório real, o grupo precisará realizar os seguintes ajustes conjuntos:

    Definição das Máquinas Físicas: O grupo deve decidir se todos os serviços (DHCP, DNS, SMTP e WWW) rodarão concentrados em uma única máquina física da bancada atuando como servidor central, ou se cada membro usará uma máquina separada. Se usarem uma máquina única, certifique-se de que o IP dela seja estático (ex: 192.168.10.2).  

    Alimentação de Dados no DNS: Você precisa passar a lista exata dos seus domínios virtuais para o integrante do DNS inserir no arquivo de zona dele. Ele deverá adicionar os registros do tipo A apontando para o seu IP:  
    Plaintext

    www.alunos.com.br.    IN  A  192.168.10.2
    www.atyrson.com.br.   IN  A  192.168.10.2

    Sincronização de Usuários Linux: Você e o integrante do SMTP precisam executar a criação dos usuários no mesmo sistema operacional utilizando o comando adduser. Garanta que os nomes criados batam exatamente com os nomes definidos nos arquivos aluno.conf de Virtual Hosts do Apache.  

    Alinhamento do Registro MX: O membro do DNS precisa criar um registro do tipo MX (Mail Exchanger) apontando para o IP do servidor onde o postfix estará instalado.  

    Carga dos Relatórios: Cada integrante deve te entregar a resolução das questões teóricas e os scripts de seus respectivos roteiros em formato de texto limpo. Você irá abrir o arquivo /var/www/html/index.html do servidor e colará os textos dentro das divs marcadas para cada serviço.
