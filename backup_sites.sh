#!/bin/bash
set -e
set -o pipefail

# Carrega o arquivo de configuração
CONFIG_FILE="backup_sites.conf"
if [ ! -f "$CONFIG_FILE" ]; then
    echo "Erro: Arquivo de configuração $CONFIG_FILE não encontrado." >&2
    exit 1
fi
source "$CONFIG_FILE"

# Valida variáveis críticas
if [ -z "$LOG_DIR" ] || [ -z "$AWS_S3_BUCKET" ] || [ -z "$BACKUP_DIR" ]; then
    echo "Erro: Variáveis LOG_DIR, AWS_S3_BUCKET ou BACKUP_DIR não definidas em $CONFIG_FILE." >&2
    exit 1
fi

mkdir -p "$LOG_DIR" "$BACKUP_DIR"
LOG_FILE="$LOG_DIR/backup-sites-$(date '+%Y-%m-%d_%H-%M-%S').log"

# === Funções Globais ===
log_message() {
    local level="$1"; shift; local message="$*"; local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] $level: $message" | tee -a "$LOG_FILE"
}

send_error_email() {
    local error_msg="$1"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local subject="$EMAIL_SUBJECT"
    local body="Erro detectado no script de backup às $timestamp.\n\nDetalhes do erro: $error_msg\n\nConteúdo completo do log:\n\n$(cat "$LOG_FILE" 2>/dev/null || echo 'Log indisponível')\n\n---\nScript executado em: $(pwd)"

    if [ "$EMAIL_ALERTS_ENABLED" = true ]; then
        if command -v ssmtp >/dev/null 2>&1; then
            # Monta o e-mail completo (cabeçalhos + corpo) e envia via pipe para o ssmtp.
            # A linha em branco (\n\n) entre o assunto e o corpo é essencial.
            if printf "To: %s\nFrom: %s\nSubject: %s\n\n%s\n" "$EMAIL_TO" "$EMAIL_FROM" "$subject" "$body" | ssmtp "$EMAIL_TO"; then
                log_message "INFO" "E-mail de alerta enviado para $EMAIL_TO via ssmtp."
            else
                log_message "ERROR" "Falha ao enviar e-mail de alerta via ssmtp para $EMAIL_TO. Verifique a configuração do ssmtp e os logs."
            fi
        else
            log_message "WARNING" "Comando 'ssmtp' não encontrado. Instale ssmtp para alertas por e-mail."
        fi
    fi
}

error_exit() {
    log_message "ERROR" "$@"
    send_error_email "$@"
    exit 1
}

cleanup_s3_backups() {
    local site_name="$1"
    local retention_days="$2"
    local full_prefix="${AWS_S3_PREFIX:+$AWS_S3_PREFIX/}$site_name/"

    log_message "INFO" "  - Limpando backups antigos em s3://$AWS_S3_BUCKET/$full_prefix (mais de $retention_days dias)..."

    local cutoff_date
    cutoff_date=$(date -d "-$retention_days days" --iso-8601=seconds)

    local objects_to_delete
    objects_to_delete=$(aws s3api list-objects-v2 --bucket "$AWS_S3_BUCKET" --prefix "$full_prefix" --query "Contents[?LastModified<='${cutoff_date}'].{Key: Key}" --output json)

    if [ -n "$objects_to_delete" ] && [ "$objects_to_delete" != "[]" ]; then
        log_message "INFO" "  - Encontrados backups antigos para deletar."
        aws s3api delete-objects --bucket "$AWS_S3_BUCKET" --delete "{\"Objects\":$(echo "$objects_to_delete"),\"Quiet\":true}" || log_message "WARNING" "  - Falha parcial ou total na exclusão de backups antigos para '$site_name'."
        log_message "INFO" "  - Limpeza de backups antigos concluída."
    else
        log_message "INFO" "  - Nenhum backup antigo para deletar."
    fi
}

# === Conteúdo Principal ===
trap 'error_exit "Erro inesperado na linha $LINENO (comando: $BASH_COMMAND). Verifique o log."' ERR

log_message "INFO" "=== INÍCIO DA EXECUÇÃO DO SCRIPT DE BACKUP ==="
find "$LOG_DIR" -name "backup-sites-*.log" -mtime "+$LOG_RETENTION_DAYS" -delete 2>/dev/null || true
DATE=$(date +%Y-%m-%d)

for SITE in $(printf '%s\n' "${!SITES[@]}" | sort); do
    log_message "INFO" "Iniciando backup do site '$SITE'..."
    
    IFS=' ' read -r SITE_PATH DB_NAME MYSQL_USER MYSQL_PASS <<< "${SITES[$SITE]}"
    
    if [ ! -d "$SITE_PATH" ]; then
        log_message "ERROR" "Diretório $SITE_PATH não existe para o site '$SITE'. Pulando."
        continue
    fi
    
    S3_BASE_PATH="s3://${AWS_S3_BUCKET}/${AWS_S3_PREFIX:+$AWS_S3_PREFIX/}$SITE"
    S3_FILES_PATH="$S3_BASE_PATH/$SITE-files-$DATE.tar.gz"
    S3_DB_PATH="$S3_BASE_PATH/$SITE-db-$DATE.sql.gz"

    # Verificação de backup existente
    files_key="${AWS_S3_PREFIX:+$AWS_S3_PREFIX/}$SITE/$SITE-files-$DATE.tar.gz"
    db_key="${AWS_S3_PREFIX:+$AWS_S3_PREFIX/}$SITE/$SITE-db-$DATE.sql.gz"
    files_exist=$(aws s3api head-object --bucket "$AWS_S3_BUCKET" --key "$files_key" >/dev/null 2>&1 && echo "true" || echo "false")
    db_exist_needed=$([ -n "$DB_NAME" ] && echo "true" || echo "false")
    db_exist=$([ "$db_exist_needed" = "true" ] && aws s3api head-object --bucket "$AWS_S3_BUCKET" --key "$db_key" >/dev/null 2>&1 && echo "true" || echo "false")

    if [ "$files_exist" = "true" ] && ( [ "$db_exist_needed" = "false" ] || [ "$db_exist" = "true" ] ); then
        log_message "INFO" "  - Backup completo para '$SITE' do dia $DATE já existe no S3. Pulando."
        continue
    fi

    site_backup_failed=0
    error_details=""
    SITE_SNAPSHOT_DIR="$BACKUP_DIR/$SITE-snapshot"

    # Lógica de Snapshot com Rsync
    log_message "INFO" "  - Criando snapshot local consistente para '$SITE' em $SITE_SNAPSHOT_DIR"
    rm -rf "$SITE_SNAPSHOT_DIR"
    mkdir -p "$SITE_SNAPSHOT_DIR" || { site_backup_failed=1; error_details="Falha ao criar diretório de snapshot $SITE_SNAPSHOT_DIR."; }
    
    if [ "$site_backup_failed" -eq 0 ]; then
        RSYNC_EXCLUDE_FLAGS=""
        if [ -n "${EXCLUDE_SITES[$SITE]}" ]; then
            for SUBFOLDER in ${EXCLUDE_SITES[$SITE]}; do RSYNC_EXCLUDE_FLAGS="$RSYNC_EXCLUDE_FLAGS --exclude=$SUBFOLDER"; done
        fi

        log_message "INFO" "    - Sincronização (passo 1/2)..."
        if ! rsync -a --delete $RSYNC_EXCLUDE_FLAGS "$SITE_PATH/" "$SITE_SNAPSHOT_DIR/"; then
            site_backup_failed=1; error_details="Falha no rsync (passo 1).";
        else
            log_message "INFO" "    - Sincronização de consistência (passo 2/2)..."
            if ! rsync -a --delete $RSYNC_EXCLUDE_FLAGS "$SITE_PATH/" "$SITE_SNAPSHOT_DIR/"; then
                site_backup_failed=1; error_details="Falha no rsync (passo 2).";
            fi
        fi
    fi

    # 1. Backup de arquivos a partir do snapshot
    if [ "$site_backup_failed" -eq 0 ]; then
        log_message "INFO" "  - Compactando snapshot e enviando para $S3_FILES_PATH..."
        set +e
        tar -czf - -C "$SITE_SNAPSHOT_DIR" . | aws s3 cp - "$S3_FILES_PATH" --no-progress
        tar_ec="${PIPESTATUS[0]}"; aws_ec="${PIPESTATUS[1]}";
        set -e
        if ([ -n "$tar_ec" ] && [ "$tar_ec" -ne 0 ]) || ([ -n "$aws_ec" ] && [ "$aws_ec" -ne 0 ]); then
            site_backup_failed=1
            error_details="Falha ao compactar/enviar o snapshot. Código tar: ${tar_ec:-n/a}, Código aws: ${aws_ec:-n/a}."
        else
            log_message "INFO" "  - Backup de arquivos concluído."
        fi
    fi

    # 2. Backup do banco de dados
    if [ "$site_backup_failed" -eq 0 ] && [ -n "$DB_NAME" ]; then
        log_message "INFO" "  - Fazendo dump do banco '$DB_NAME' para $S3_DB_PATH..."
        set +e
        mysqldump -u "$MYSQL_USER" -p"$MYSQL_PASS" "$DB_NAME" | gzip | aws s3 cp - "$S3_DB_PATH" --no-progress
        mysqldump_ec="${PIPESTATUS[0]}"; aws_ec="${PIPESTATUS[2]}";
        set -e
        if ([ -n "$mysqldump_ec" ] && [ "$mysqldump_ec" -ne 0 ]) || ([ -n "$aws_ec" ] && [ "$aws_ec" -ne 0 ]); then
            site_backup_failed=1
            error_details="Falha no backup do banco. Código mysqldump: ${mysqldump_ec:-n/a}, Código aws: ${aws_ec:-n/a}."
        else
            log_message "INFO" "  - Dump do banco concluído."
        fi
    fi

    # Limpeza do snapshot local
    log_message "INFO" "  - Limpando snapshot local '$SITE_SNAPSHOT_DIR'..."
    rm -rf "$SITE_SNAPSHOT_DIR"

    # Lógica de limpeza no S3 em caso de falha
    if [ "$site_backup_failed" -eq 1 ]; then
        log_message "ERROR" "Backup para '$SITE' falhou. Detalhes: $error_details"
        send_error_email "Backup para '$SITE' falhou. Detalhes: $error_details"
        log_message "INFO" "  - Limpando arquivos de backup parciais do S3 para '$SITE'..."
        aws s3 rm "$S3_FILES_PATH" 2>/dev/null || true
        aws s3 rm "$S3_DB_PATH" 2>/dev/null || true
        log_message "INFO" "  - Limpeza de S3 concluída. Pulando para o próximo site."
        continue
    fi

    # Limpeza de backups antigos no S3
    cleanup_s3_backups "$SITE" "$RETENTION_DAYS"

    log_message "INFO" "Backup do site '$SITE' concluído com sucesso."
done

log_message "INFO" "=== FIM DA EXECUÇÃO DO SCRIPT DE BACKUP (SUCESSO) ==="
trap - ERR