🌐 Disponível em: [English](README.md) | [Português BR](README.pt-br.md)

# Robust Shell Backup

Um sistema de backup completo e confiável, escrito em Bash, projetado para automatizar a cópia de segurança de múltiplos websites (arquivos e bancos de dados) para um bucket AWS S3.

<br>

## Índice

-   [O Projeto: Intuito e Propósito](#o-projeto-intuito-e-propósito)
-   [Principais Funcionalidades](#-principais-funcionalidades)
-   [Requisitos](#requisitos)
-   [Guia de Instalação e Configuração (Passo a Passo)](#-guia-de-instalação-e-configuração-passo-a-passo)
    -   [Passo 0: Configuração das Credenciais AWS](#passo-0-configuração-das-credenciais-aws)
    -   [Passo 1: Clonar o Repositório e Dar Permissões](#passo-1-clonar-o-repositório-e-dar-permissões)
    -   [Passo 2: Configurar o Envio de E-mail (SSMTP)](#passo-2-configurar-o-envio-de-e-mail-ssmtp)
    -   [Passo 3: Personalizar o Arquivo de Configuração](#passo-3-personalizar-o-arquivo-de-configuração)
    -   [Passo 4: Agendar a Automação com Cron](#passo-4-agendar-a-automação-com-cron)
-   [Análise Detalhada dos Arquivos](#-análise-detalhada-dos-arquivos)
    -   [O Arquivo de Configuração: `backup_sites.conf`](#o-arquivo-de-configuração-backup_sitesconf)
    -   [O Script Principal: `backup_sites.sh`](#o-script-principal-backup_sitessh)
-   [Uso e Testes Manuais](#uso-e-testes-manuais)
-   [Como Contribuir](#como-contribuir)
-   [Sobre o autor](#-sobre-o-autor)
-   [Licença](#-licença)

---

## O Projeto: Intuito e Propósito

Este projeto nasceu da necessidade de criar uma solução de backup automatizada, robusta e de baixo impacto para servidores web que hospedam múltiplos sites. Muitas soluções existentes são complexas, caras ou consomem recursos valiosos, como espaço em disco, o que é um fator crítico em ambientes de hospedagem compartilhada ou servidores cloud de menor porte.

O **Robust Shell Backup** foi projetado para ser:

-   **Confiável:** Utiliza técnicas como `rsync` em duas passagens para garantir que os arquivos sejam copiados de forma consistente, mesmo que estejam sendo modificados durante o processo.
-   **Eficiente:** Envia os backups compactados diretamente para o AWS S3 via *streaming*, eliminando a necessidade de armazenar arquivos temporários volumosos no disco local do servidor.
-   **Customizável:** Através de um arquivo de configuração centralizado e de fácil compreensão, o sistema pode ser adaptado para diferentes cenários de hospedagem, gerenciando múltiplos sites, bancos de dados e regras de exclusão específicas.
-   **Extensível:** Embora atualmente focado em bancos de dados MySQL, a arquitetura do script foi pensada para ser modular, permitindo que a comunidade o adapte e melhore para suportar outras tecnologias de banco de dados (como PostgreSQL, MongoDB) ou diferentes sistemas de armazenamento.

Seu propósito é fornecer a administradores de sistemas e desenvolvedores uma ferramenta "configure e esqueça" que oferece paz de espírito, sabendo que os dados críticos de seus websites estão seguros, consistentes e armazenados externamente.

---

## ✨ Principais Funcionalidades

-   **Snapshots Consistentes**: Cria um snapshot local dos arquivos usando `rsync` em duas passagens, minimizando inconsistências de arquivos que mudam durante o backup.
-   **Streaming Direto para S3**: Compacta e envia os backups via stream (`|`) para a AWS, economizando espaço em disco e acelerando o processo.
-   **Gerenciamento Centralizado**: Configura todos os sites, bancos de dados e exclusões em um único arquivo `.conf`.
-   **Backup de Banco de Dados MySQL**: Realiza o dump e a compressão de bancos MySQL.
-   **Limpeza Automatizada**: Remove backups antigos do S3 com base em um período de retenção configurável.
-   **Execução Idempotente**: Verifica se o backup do dia já existe e pula a execução para evitar trabalho redundante.
-   **Operações Atômicas por Site**: Se uma etapa do backup falhar, os arquivos parciais daquele dia são removidos do S3 para manter a integridade.
-   **Alertas de Erro por E-mail**: Envia notificações detalhadas em caso de falha, usando `ssmtp` para garantir a entrega através de um SMTP externo.
-   **Logs Detalhados**: Cada execução é registrada em um arquivo de log com timestamp para fácil auditoria.

---

## Requisitos

Para que o script funcione corretamente, seu servidor precisa ter as seguintes ferramentas instaladas:

-   `aws-cli`: A interface de linha de comando da AWS.
-   `rsync`: Utilitário para sincronização de arquivos.
-   `mysqldump`: Ferramenta para exportação de bancos de dados MySQL.
-   `ssmtp`: Um cliente de e-mail simples para retransmitir e-mails via SMTP externo.

---

## 🚀 Guia de Instalação e Configuração (Passo a Passo)

### Passo 0: Configuração das Credenciais AWS

Antes de tudo, o script precisa de permissão para acessar seu bucket S3. A maneira mais segura de fazer isso é configurar as credenciais da AWS para o usuário que executará o script.

Instale o cliente AWS (aws-cli) se ainda não tiver:
```sh
    # Para sistemas baseados em Debian/Ubuntu
    sudo apt-get install aws-cli
    # Para sistemas baseados em RHEL/CentOS
    sudo yum install aws-cli
```

Realize a configuração inicial das credenciais de acesso ao S3:
```sh
aws configure
```
Siga as instruções para inserir sua `AWS Access Key ID`, `AWS Secret Access Key`, `Default region name` e `Default output format`.

### Passo 1: Clonar o Repositório e Dar Permissões

Primeiro, obtenha os arquivos e torne o script executável.

```sh
# Clone este repositório para o seu servidor
git clone https://github.com/irlemos/robust-shell-backup.git

# Navegue para o diretório do projeto
cd robust-shell-backup

# Dê permissão de execução ao script principal
chmod +x backup_sites.sh
```

### Passo 2: Configurar o Envio de E-mail (SSMTP)

Para que os alertas de erro funcionem, você precisa configurar o `ssmtp` para usar um servidor de e-mail externo (como Gmail, SendGrid, etc.). Isso é necessário porque a maioria dos provedores de nuvem (incluindo a AWS) bloqueia a porta de saída 25 para evitar spam.

1.  Instale o `ssmtp` (se ainda não o tiver):
    ```sh
    # Para sistemas baseados em Debian/Ubuntu
    sudo apt-get install ssmtp
    # Para sistemas baseados em RHEL/CentOS
    sudo yum install ssmtp
    ```

2.  Edite o arquivo de configuração `/etc/ssmtp/ssmtp.conf` com as informações do seu provedor de e-mail. Exemplo para o Gmail:
    ```ini
    # /etc/ssmtp/ssmtp.conf
    root=seu-email-de-envio@gmail.com
    mailhub=smtp.gmail.com:587
    hostname=seu-servidor.com
    FromLineOverride=YES
    UseSTARTTLS=YES
    AuthUser=seu-email-de-envio@gmail.com
    AuthPass=sua-senha-de-app-do-google
    ```
    **Importante:** Para serviços como o Gmail, você deve gerar uma "Senha de App" específica.

### Passo 3: Personalizar o Arquivo de Configuração

Este é o coração do sistema. Abra o arquivo `backup_sites.conf` e ajuste todas as variáveis para o seu ambiente. A seção abaixo detalha cada variável.

### Passo 4: Agendar a Automação com Cron

Finalmente, agende o script para ser executado automaticamente.

1.  Abra o editor de `cron` para o usuário que deve executar o backup:
    ```sh
    crontab -e
    ```

2.  Adicione a seguinte linha no final do arquivo para executar o backup todos os dias às 3h da manhã:
    ```crontab
    0 3 * * * cd /caminho/completo/para/robust-shell-backup/ && ./backup_sites.sh >/dev/null 2>&1
    ```
    **Lembre-se de substituir `/caminho/completo/para/robust-shell-backup/` pelo caminho real onde você clonou o projeto.**

---

## 🔧 Análise Detalhada dos Arquivos

### O Arquivo de Configuração: `backup_sites.conf`

Este arquivo centraliza todas as configurações do script.

| Variável | Descrição | Exemplo |
| :--- | :--- | :--- |
| `LOG_DIR` | O diretório onde os arquivos de log serão armazenados. | `"$SCRIPT_DIR/log"` |
| `LOG_RETENTION_DAYS`| Quantos dias os arquivos de log devem ser mantidos. | `30` |
| `BACKUP_DIR` | Pasta temporária para criar os snapshots locais com `rsync`. | `"/home/user/backups_temp"`|
| `AWS_S3_BUCKET` | **Apenas** o nome do seu bucket S3. Não inclua `s3://` ou subpastas. | `"meu-bucket-de-backup"` |
| `AWS_S3_PREFIX` | A subpasta (prefixo) dentro do bucket onde os backups serão armazenados. Pode ser deixada em branco. | `"backups-servidor-1"` |
| `RETENTION_DAYS` | Quantos dias os backups devem ser mantidos no S3. | `7` |
| `EMAIL_ALERTS_ENABLED`| Ativa (`true`) ou desativa (`false`) o envio de e-mails de erro. | `true` |
| `EMAIL_TO` | O endereço de e-mail do destinatário dos alertas. | `"admin@meudominio.com"` |
| `EMAIL_FROM` | O endereço de e-mail que aparecerá como remetente. | `"backup-bot@meudominio.com"`|
| `EMAIL_SUBJECT` | O assunto do e-mail de alerta. Pode incluir comandos como `date`. | `"ALERTA: Erro no Backup - $(date)"` |

**Arrays de Configuração:**

-   **`SITES`**: Um array associativo que define cada site.
    -   **Chave**: O nome do site, que também será usado como o nome da pasta no S3.
    -   **Valor**: Uma string com os parâmetros separados por espaço: `/caminho/absoluto/dos/arquivos nome_do_banco usuario_do_banco senha_do_banco`.
    -   *Se um site não tiver banco de dados, omita as últimas três informações.*
    ```bash
    SITES["meusite.com"]="/var/www/meusite meudb_prod meudb_user 'senhaForte'"
    SITES["outrosite.com"]="/var/www/meusite/outrosite outrodb_prod outrodb_user 'senhaForte'"
    SITES["blog.meusite.com"]="/var/www/blog" # Sem banco de dados
    ```

-   **`EXCLUDE_SITES`**: Um array associativo para excluir subpastas do backup de arquivos.
    -   **Chave**: O nome do site (deve corresponder a uma chave em `SITES`).
    -   **Valor**: Uma string com os nomes das pastas a serem excluídas, separados por espaço.
    ```bash
    # Exclui a pasta de cache e de uploads temporários
    EXCLUDE_SITES["meusite.com"]="/wp-content/cache /tmp/uploads /outrosite"
    EXCLUDE_SITES["outrosite.com"]="/wp-content/cache"
    ```

### O Script Principal: `backup_sites.sh`

O script segue um fluxo lógico e robusto para cada site configurado:

1.  **Carregamento e Validação**: O script carrega o `backup_sites.conf` e valida se as variáveis críticas foram definidas.
2.  **Loop Principal**: Itera sobre cada site definido no array `SITES`.
3.  **Verificação de Backup Existente**: Antes de iniciar, ele verifica no S3 se um backup completo (arquivos e, se aplicável, banco) para a data atual já existe. Se sim, ele pula para o próximo site.
4.  **Criação do Snapshot `rsync`**:
    -   Cria um diretório temporário para o snapshot do site.
    -   Executa `rsync` uma primeira vez para copiar a maior parte dos dados.
    -   Executa `rsync` uma segunda vez. Esta passagem é muito rápida e sincroniza apenas os arquivos que mudaram durante a primeira passagem, garantindo um estado altamente consistente.
5.  **Backup de Arquivos**: O script usa `tar` para compactar o conteúdo do diretório de snapshot (que agora está estático) e envia a saída diretamente (`|`) para o comando `aws s3 cp`, que faz o upload do stream para o S3.
6.  **Backup do Banco de Dados**: Se um banco de dados estiver configurado, `mysqldump` exporta o banco, `gzip` o compacta, e o resultado é enviado via stream (`|`) para o S3.
7.  **Tratamento de Falhas e Limpeza**:
    -   Uma variável `site_backup_failed` rastreia o sucesso de cada etapa.
    -   Se qualquer comando (`rsync`, `tar`, `mysqldump`, `aws`) falhar, a variável é marcada.
    -   O snapshot local é sempre removido para liberar espaço.
    -   Se a variável de falha estiver marcada, o script envia um e-mail de alerta e remove ativamente do S3 quaisquer arquivos parciais que possam ter sido enviados para aquele site naquele dia.
8.  **Limpeza de Backups Antigos**: Se o backup do dia foi um sucesso, o script chama uma função que lista e remove os backups mais antigos que o `RETENTION_DAYS` do S3.

---

## Uso e Testes Manuais

Para testar a configuração ou executar um backup fora do horário agendado, você pode chamar o script diretamente.

-   **Para executar e ver a saída em tempo real:**
    ```sh
    # Navegue até o diretório do projeto
    cd /caminho/completo/para/robust-shell-backup/
    
    # Execute o script
    ./backup_sites.sh
    ```
    Isso imprimirá todos os logs no seu terminal.

-   **Para simular a execução do cron (silenciosa):**
    ```sh
    cd /caminho/completo/para/robust-shell-backup/ && ./backup_sites.sh >/dev/null 2>&1
    ```
    Depois de executar, verifique os resultados na pasta `log/` e no seu bucket S3.

---

## Como Contribuir

Contribuições são o que tornam a comunidade de código aberto um lugar incrível para aprender, inspirar e criar. Qualquer contribuição que você fizer será **muito apreciada**.

1.  Faça um Fork do Projeto
2.  Crie sua Feature Branch (`git checkout -b feature/AmazingFeature`)
3.  Faça o Commit de suas alterações (`git commit -m 'Add some AmazingFeature'`)
4.  Faça o Push para a Branch (`git push origin feature/AmazingFeature`)
5.  Abra um Pull Request

---

## 👤 Sobre o Autor

Desenvolvido por [Rodrigo Lemos](https://linkedin.com/in/irlemos)  

💻 **Experiência ampla em desenvolvimento de software, integrações e soluções complexas**  
Com vasta experiência em múltiplas linguagens de programação, plataformas e projetos escaláveis.

---

## 📜 Licença

Distribuído sob a Licença MIT. Veja `LICENSE` para mais informações.