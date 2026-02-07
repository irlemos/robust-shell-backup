#!/bin/bash
set -e

# --- Carrega o Arquivo de Configuração ---
CONFIG_FILE="backup_sites.conf"
if [ ! -f "$CONFIG_FILE" ]; then
    echo "Erro: Arquivo de configuração $CONFIG_FILE não encontrado." >&2
    exit 1
fi
source "$CONFIG_FILE"

# --- Validações Iniciais ---
if [ -z "$AWS_S3_BUCKET" ] || [ -z "$BACKUP_DIR" ]; then
    echo "Erro: Variáveis AWS_S3_BUCKET ou BACKUP_DIR não definidas em $CONFIG_FILE." >&2
    exit 1
fi

# --- Funções Auxiliares ---
check_dependencies() {
    for cmd in aws tar gzip mysql sed; do
        if ! command -v "$cmd" &> /dev/null; then
            echo "Erro: O comando '$cmd' não foi encontrado. Por favor, instale-o." >&2
            exit 1
        fi
    done
}

# --- Início do Script Interativo ---
check_dependencies

echo "================================================="
echo "        Assistente de Restauração de Backup"
echo "================================================="
echo

# PASSO 1: SELECIONAR O SITE
# -----------------------------------------------
echo "Passo 1: Selecione o site que deseja restaurar:"
PS3="Digite o número do site: "
site_options=($(printf '%s\n' "${!SITES[@]}" | sort))
select SELECTED_SITE in "${site_options[@]}"; do
    if [[ -n "$SELECTED_SITE" ]]; then
        echo "Site selecionado: $SELECTED_SITE"
        break
    else
        echo "Opção inválida. Tente novamente."
    fi
done
echo

# PASSO 2: SELECIONAR A DATA DO BACKUP
# -----------------------------------------------
S3_PREFIX="${AWS_S3_PREFIX:+$AWS_S3_PREFIX/}$SELECTED_SITE/"
echo "Passo 2: Buscando backups disponíveis para '$SELECTED_SITE' no S3..."
backup_dates=($(aws s3 ls "s3://${AWS_S3_BUCKET}/${S3_PREFIX}" | grep -oP '\d{4}-\d{2}-\d{2}' | sort -u -r))

if [ ${#backup_dates[@]} -eq 0 ]; then
    echo "Nenhum backup encontrado para o site '$SELECTED_SITE' em s3://${AWS_S3_BUCKET}/${S3_PREFIX}"
    exit 1
fi

echo "Selecione a data do backup que deseja restaurar:"
PS3="Digite o número da data: "
select SELECTED_DATE in "${backup_dates[@]}"; do
    if [[ -n "$SELECTED_DATE" ]]; then
        echo "Data selecionada: $SELECTED_DATE"
        break
    else
        echo "Opção inválida. Tente novamente."
    fi
done
echo

# PASSO 3: OBTER INFORMAÇÕES DE DESTINO
# -----------------------------------------------
echo "Passo 3: Informe os detalhes do destino da restauração."
read -p "Digite o caminho completo para restaurar os arquivos (ex: /home/user/public_html_restaurado): " RESTORE_FILES_PATH
while [ -z "$RESTORE_FILES_PATH" ]; do
    read -p "O caminho não pode ser vazio. Digite novamente: " RESTORE_FILES_PATH
done

IFS=' ' read -r _ DB_NAME _ _ <<< "${SITES[$SELECTED_SITE]}"
HAS_DB_BACKUP=false
RESTORE_DB_CONFIRM="n"

if [ -n "$DB_NAME" ]; then
    S3_DB_KEY="${S3_PREFIX}${SELECTED_SITE}-db-${SELECTED_DATE}.sql.gz"
    if aws s3api head-object --bucket "$AWS_S3_BUCKET" --key "$S3_DB_KEY" >/dev/null 2>&1; then
        HAS_DB_BACKUP=true
        echo
        echo "INFO: Um backup de banco de dados foi encontrado para esta data."
        read -p "Deseja restaurar o banco de dados? (s/n): " RESTORE_DB_CONFIRM
        if [[ "$RESTORE_DB_CONFIRM" =~ ^[Ss]$ ]]; then
            echo "Por favor, forneça as credenciais de um banco de dados JÁ EXISTENTE:"
            read -p "  - Nome do banco de dados de destino: " DEST_DB_NAME
            read -p "  - Nome do usuário MySQL com permissão: " DEST_DB_USER
            read -s -p "  - Senha para o usuário MySQL: " DEST_DB_PASS
            echo
            while [ -z "$DEST_DB_NAME" ] || [ -z "$DEST_DB_USER" ] || [ -z "$DEST_DB_PASS" ]; do
                echo "Erro: Todos os campos do banco de dados são obrigatórios."
                read -p "  - Nome do banco de dados de destino: " DEST_DB_NAME
                read -p "  - Nome do usuário MySQL com permissão: " DEST_DB_USER
                read -s -p "  - Senha para o usuário MySQL: " DEST_DB_PASS
                echo
            done
            echo "  - Testando conexão com o banco de dados..."
            if ! mysql -u"$DEST_DB_USER" -p"$DEST_DB_PASS" -e "USE \`$DEST_DB_NAME\`;" 2>/dev/null; then
                echo "Erro: Falha ao conectar ao banco de dados '$DEST_DB_NAME' com o usuário '$DEST_DB_USER'."
                echo "   Verifique se o banco de dados, o usuário e a senha estão corretos."
                exit 1
            fi
            echo "  - Conexão bem-sucedida."
        fi
    fi
fi
echo

# PASSO 4: CONFIRMAÇÃO FINAL
# -----------------------------------------------
echo "================================================="
echo "            ATENCAO: CONFIRMACAO FINAL"
echo "================================================="
echo "Por favor, revise os detalhes da restauração:"
echo "  - Site de Origem:   $SELECTED_SITE"
echo "  - Data do Backup:     $SELECTED_DATE"
echo "  - Restaurar Arquivos para: $RESTORE_FILES_PATH"
if [[ "$RESTORE_DB_CONFIRM" =~ ^[Ss]$ ]]; then
    echo "  - Restaurar Banco para:"
    echo "    - Banco de Destino:     $DEST_DB_NAME"
    echo "    - Usando Usuário:         $DEST_DB_USER"
    echo "    - AVISO: Todos os dados no banco '$DEST_DB_NAME' serão sobrescritos!"
fi
echo
read -p "Você tem certeza que deseja continuar? (digite 'sim' para continuar): " FINAL_CONFIRMATION

if [ "$FINAL_CONFIRMATION" != "sim" ]; then
    echo "Restauração cancelada pelo usuário."
    exit 0
fi
echo

# PASSO 5: EXECUÇÃO DA RESTAURAÇÃO
# -----------------------------------------------
TEMP_DOWNLOAD_DIR=$(mktemp -d -p "$BACKUP_DIR" "restore_${SELECTED_SITE}_XXXXXX")
echo "Iniciando a restauração... (arquivos temporários em $TEMP_DOWNLOAD_DIR)"

S3_FILES_KEY="${S3_PREFIX}${SELECTED_SITE}-files-${SELECTED_DATE}.tar.gz"
LOCAL_FILES_BACKUP="$TEMP_DOWNLOAD_DIR/files.tar.gz"
LOCAL_DB_BACKUP="$TEMP_DOWNLOAD_DIR/db.sql.gz"

echo "  - Baixando backup de arquivos do S3..."
aws s3 cp "s3://${AWS_S3_BUCKET}/${S3_FILES_KEY}" "$LOCAL_FILES_BACKUP"

echo "  - Criando diretório de destino: $RESTORE_FILES_PATH"
mkdir -p "$RESTORE_FILES_PATH"
echo "  - Descompactando arquivos em $RESTORE_FILES_PATH..."
tar -xzf "$LOCAL_FILES_BACKUP" -C "$RESTORE_FILES_PATH"
echo "  - Arquivos restaurados com sucesso."

if [[ "$RESTORE_DB_CONFIRM" =~ ^[Ss]$ ]]; then
    echo "  - Baixando backup de banco de dados do S3..."
    aws s3 cp "s3://${AWS_S3_BUCKET}/${S3_DB_KEY}" "$LOCAL_DB_BACKUP"

    echo "  - Importando dados para o banco '$DEST_DB_NAME' (isso pode levar alguns minutos)..."
    gunzip < "$LOCAL_DB_BACKUP" | mysql -u"$DEST_DB_USER" -p"$DEST_DB_PASS" "$DEST_DB_NAME"
    echo "  - Banco de dados restaurado com sucesso."

    # --- NOVA LÓGICA: ATUALIZAR WP-CONFIG.PHP ---
    WP_CONFIG_PATH="$RESTORE_FILES_PATH/wp-config.php"
    echo "  - Procurando por wp-config.php para atualização..."
    if [ -f "$WP_CONFIG_PATH" ]; then
        echo "    - Arquivo wp-config.php encontrado."
        echo "    - Criando backup do arquivo original em $WP_CONFIG_PATH.bak"
        
        # Prepara os valores para serem usados com segurança no `sed`
        # Escapa os caracteres que têm significado especial para o `sed` (\, &, /)
        SED_DB_NAME=$(printf '%s\n' "$DEST_DB_NAME" | sed -e 's/[\/&]/\\&/g')
        SED_DB_USER=$(printf '%s\n' "$DEST_DB_USER" | sed -e 's/[\/&]/\\&/g')
        SED_DB_PASS=$(printf '%s\n' "$DEST_DB_PASS" | sed -e 's/[\/&]/\\&/g')

        # Atualiza o nome do banco, usuário e senha usando `sed`
        sed -i.bak \
            -e "s/define( *'DB_NAME', *'[^']*' *);/define( 'DB_NAME', '$SED_DB_NAME' );/" \
            -e "s/define( *'DB_USER', *'[^']*' *);/define( 'DB_USER', '$SED_DB_USER' );/" \
            -e "s/define( *'DB_PASSWORD', *'[^']*' *);/define( 'DB_PASSWORD', '$SED_DB_PASS' );/" \
            "$WP_CONFIG_PATH"
        
        echo "    - Arquivo wp-config.php atualizado com as novas credenciais do banco de dados."
    else
        echo "    - AVISO: Arquivo wp-config.php não encontrado em '$RESTORE_FILES_PATH'. A atualização das credenciais do banco deverá ser feita manualmente."
    fi
    # --- FIM DA NOVA LÓGICA ---
fi

# Limpeza final
echo "  - Removendo arquivos temporários..."
rm -rf "$TEMP_DOWNLOAD_DIR"

echo
echo "Restauração concluída com sucesso!"
echo "================================================="
