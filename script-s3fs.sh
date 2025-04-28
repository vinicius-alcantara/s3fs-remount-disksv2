#!/bin/bash

declare -a MOUNTED_POINTS;
declare -a DISK_BUSY;
declare -a DISK_FREE;

CUSTOMER_NAME="XPTO";
INSTANCE_NAME=$(hostname);
AWS_REGION="us-east-1";
PARAMETER_NAME_BOT_TOKEN="TOKEN_BOT_API_TELEGRAM";
PARAMETER_NAME_CHAT_ID="CHAT_ID_TELEGRAM";
PARAMETER_NAME_MAIL_FROM="MAIL_FROM_NOTIFICATION_S3FS";
PARAMETER_NAME_MAIL_TO="MAIL_TO_NOTIFICATION_S3FS";

BOT_TOKEN=$(aws ssm get-parameter --region "$AWS_REGION" --name "$PARAMETER_NAME_BOT_TOKEN" --with-decryption --query "Parameter.Value" --output text);
CHAT_ID=$(aws ssm get-parameter --region "$AWS_REGION" --name "$PARAMETER_NAME_CHAT_ID" --with-decryption --query "Parameter.Value" --output text);
MAIL_FROM=$(aws ssm get-parameter --region "$AWS_REGION" --name "$PARAMETER_NAME_MAIL_FROM" --with-decryption --query "Parameter.Value" --output text);
MAIL_TO=$(aws ssm get-parameter --region "$AWS_REGION" --name "$PARAMETER_NAME_MAIL_TO" --with-decryption --query "Parameter.Value" --output text);

send_notification_telegram(){
  curl -s -X POST "https://api.telegram.org/bot$BOT_TOKEN/sendMessage" \
        -d chat_id="$CHAT_ID" \
        -d text="$FULL_MESSAGE" \
        -d parse_mode="HTML" > /dev/null;
}

send_notification_email(){
  echo -e "To: $MAIL_TO\nSubject: $TITULO\n\n$FULL_MESSAGE" | /usr/sbin/sendmail -t -f "$MAIL_FROM" "$MAIL_TO";
}

validate_exist_bucket(){
  if aws s3 ls "s3://$BUCKET" > /dev/null 2>&1;
  then
    BUCKET_EXIST=true;
  else
    BUCKET_EXIST=false;
  fi
}

validate_exist_directory_mount_point(){
  if [ -d "$DESTINO" ];
  then
    DIRECTORY_EXIST=true;
  else
    DIRECTORY_EXIST=false;
  fi
}

mount_all_disks_s3fs() {
    BUCKETS_NAME=("s3fs-directory-artifacts" "s3fs-directory-snaps" "s3fs-directory-backup");
    MOUNT_PATH_BUCKET=("/s3fs_dir/dados/artifacts" "/s3fs_dir/dados/snaps" "/s3fs_dir/dados/backup");
    CACHE_FILE_S3FS=("/tmp/s3fs_cache1" "/tmp/s3fs_cache2" "/tmp/s3fs_cache3");

    UID_S3FS=502;
    GID_S3FS=503;

    for INDEX in "${!BUCKETS_NAME[@]}"; do
        BUCKET="${BUCKETS_NAME[$INDEX]}";
        DESTINO="${MOUNT_PATH_BUCKET[$INDEX]}";
        CACHE="${CACHE_FILE_S3FS[$INDEX]}";

        SKIP_DISK=false;
        for BUSY_ENTRY in "${DISK_BUSY[@]}";
	do
            if echo "$BUSY_ENTRY" | grep -q "$DESTINO";
	    then
                SKIP_DISK=true;
                break;
            fi
        done

        if [ "$SKIP_DISK" = true ];
	then
            S3FS_MOUNTED_SKIP+=("🪣  $BUCKET → $DESTINO - Skip/Busy (Já estava montado) ⚠️"$'\n');
            continue;
        fi

        validate_exist_bucket;
        validate_exist_directory_mount_point;

        if [ "$BUCKET_EXIST" = false ];
	then
            S3FS_MOUNTED_ERROR+=("🪣  $BUCKET → $DESTINO - 🚨 Erro ao montar o disco ❌❌❌"$'\n');
            continue;
        fi

        if [ "$DIRECTORY_EXIST" = false ];
	then
            S3FS_MOUNTED_ERROR+=("🪣  $BUCKET → $DESTINO - 🚨 Erro ao montar o disco ❌❌❌"$'\n');
            continue;
        fi

        s3fs "$BUCKET" "$DESTINO" \
            -o _netdev \
            -o stat_cache_expire=60 \
            -o multireq_max=4 \
            -o allow_other \
            -o umask=0000 \
            -o dbglevel=info \
            -o iam_role=auto \
            -o use_cache="$CACHE" \
            -o max_stat_cache_size=1000 \
            -o uid="$UID_S3FS" \
            -o gid="$GID_S3FS"

        if [ $? -eq 0 ]; then
            S3FS_MOUNTED_SUCCESS+=("🪣  $BUCKET → $DESTINO - Montado com sucesso! ✅"$'\n');
        else
            S3FS_MOUNTED_ERROR+=("🪣  $BUCKET → $DESTINO - Erro ao montar o disco ❌"$'\n');
        fi
    done
}

discovery_s3fs_no_mounted_disks(){
  while IFS= read -r POINT;
  do
    MOUNTED_POINTS+=("$POINT");
  done < <(df -hT | sort | awk '$2 == "fuse.s3fs" {print $NF}');

  if [ ${#MOUNTED_POINTS[@]} -eq 0 ];
  then
    local TITULO="<b>🚨  [$CUSTOMER_NAME] CRITICAL: RESTARTANDO DISCOS S3FS:</b>";
    local INSTANCE_INFO="<b>Nome da Instância:</b> $INSTANCE_NAME";
    local INF1="<b>Verificando os discos s3fs atualmente montados:</b>  ⏳ ⏳ ⏳";
    local INF2="<b>Não há discos S3FS montados:</b> ❌ ❌ ❌";
    FULL_MESSAGE="$TITULO"$'\n'"$INSTANCE_INFO"$'\n'"$INF1"$'\n'"$INF2";
    send_notification_telegram;
    send_notification_email;
    exit 0;
  fi
}

restart_s3fs_disks() {
    local TITULO="<b>ℹ️  [$CUSTOMER_NAME] INF: RESTARTANDO DISCOS S3FS:</b>";
    local INSTANCE_INFO="<b>Nome da Instância:</b> $INSTANCE_NAME";
    local INF1="<b>Discos s3fs atualmente montados:</b>";
    local INF2="<b>Desmontando os discos s3fs:</b> ⏳ ⏳ ⏳"$'\n';
    FULL_MESSAGE="$TITULO"$'\n'"$INSTANCE_INFO"$'\n'"$INF1"$'\n';

    for S3FS_DISKS in "${MOUNTED_POINTS[@]}";
    do
        FULL_MESSAGE="$FULL_MESSAGE"$'\n'"$S3FS_DISKS ✅";
    done

    FULL_MESSAGE="$FULL_MESSAGE"$'\n'$'\n'"$INF2";

    for S3FS_DISKS_LIST in "${MOUNTED_POINTS[@]}";
    do
        DISK_STATUS_USE=$(lsof +D "$S3FS_DISKS_LIST" 2>/dev/null);
        if [ -z "$DISK_STATUS_USE" ];
	then
            fusermount -u "$S3FS_DISKS_LIST";
            if [ $? -eq 0 ];
	    then
                DISK_FREE+=("$S3FS_DISKS_LIST - Desmontado com sucesso ✅");
            else
                DISK_FREE_ERROR_UMOUNT+=("🚨 Erro ao desmontar o disco $S3FS_DISKS_LIST - Por favor verificar pessoalmente! ❌❌❌"$'\n');
            fi
        else
            DISK_BUSY+=("$S3FS_DISKS_LIST - Skip/Busy!!! ⚠️");
        fi
    done

    #TESTE - UMOUNT ERROR
    #DISK_FREE_ERROR_UMOUNT[0]="🚨 Erro ao desmontar o disco $S3FS_DISKS_LIST - Por favor verificar pessoalmente! ❌❌❌"$'\n';

    if [ ${#DISK_FREE_ERROR_UMOUNT[@]} -gt 0 ];
    then
        DISK_FREE_UMOUNTED_FAILED=$(printf "%s\n" "${DISK_FREE_ERROR_UMOUNT[@]}");
        FULL_MESSAGE="$FULL_MESSAGE"$'\n'"$DISK_FREE_UMOUNTED_FAILED"$'\n';
        send_notification_telegram;
        exit 0;
    elif [ ${#DISK_FREE[@]} -gt 0 ] && [ ${#DISK_BUSY[@]} -eq 0 ];
    then
        DISK_FREE_UMOUNTED_SUCCESS=$(printf "%s\n" "${DISK_FREE[@]}");
        FULL_MESSAGE="$FULL_MESSAGE"$'\n'"$DISK_FREE_UMOUNTED_SUCCESS"$'\n';
        FULL_MESSAGE="$FULL_MESSAGE"$'\n'"<b>Montando os discos s3fs (Remount): 🛠️  🛠️  🛠️ </b>"$'\n';
        mount_all_disks_s3fs;

        if [ ${#S3FS_MOUNTED_ERROR[@]} -gt 0 ];
	then
            VALIDATE_S3FS_MOUNT_FAILED=$(printf "%s\n" "${S3FS_MOUNTED_ERROR[@]}");
            FULL_MESSAGE="$FULL_MESSAGE"$'\n'"$VALIDATE_S3FS_MOUNT_FAILED"$'\n';
        fi

        if [ ${#S3FS_MOUNTED_SUCCESS[@]} -gt 0 ];
	then
            VALIDATE_S3FS_MOUNTED_DISKS=$(printf "%s\n" "${S3FS_MOUNTED_SUCCESS[@]}");
            FULL_MESSAGE="$FULL_MESSAGE"$'\n'"$VALIDATE_S3FS_MOUNTED_DISKS"$'\n';
        fi

        if [ ${#S3FS_MOUNTED_SKIP[@]} -gt 0 ];
	then
            VALIDATE_S3FS_SKIP_DISKS=$(printf "%s\n" "${S3FS_MOUNTED_SKIP[@]}");
            FULL_MESSAGE="$FULL_MESSAGE"$'\n'"$VALIDATE_S3FS_SKIP_DISKS"$'\n';
        fi

        send_notification_telegram;

    elif [ ${#DISK_FREE[@]} -gt 0 ] && [ ${#DISK_BUSY[@]} -gt 0 ];
    then
        DISK_FREE_UMOUNTED_SUCCESS=$(printf "%s\n" "${DISK_FREE[@]}");
        WARNING_DISK_BUSY=$(printf "%s\n" "${DISK_BUSY[@]}");
        FULL_MESSAGE="$FULL_MESSAGE"$'\n'"$DISK_FREE_UMOUNTED_SUCCESS"$'\n'"$WARNING_DISK_BUSY"$'\n';
        FULL_MESSAGE="$FULL_MESSAGE"$'\n'"<b>Montando os discos s3fs (Remount): 🛠️  🛠️  🛠️  </b>"$'\n';
        mount_all_disks_s3fs;

        if [ ${#S3FS_MOUNTED_ERROR[@]} -gt 0 ];
	then
            VALIDATE_S3FS_MOUNT_FAILED=$(printf "%s\n" "${S3FS_MOUNTED_ERROR[@]}");
            FULL_MESSAGE="$FULL_MESSAGE"$'\n'"$VALIDATE_S3FS_MOUNT_FAILED"$'\n';
        fi

        if [ ${#S3FS_MOUNTED_SUCCESS[@]} -gt 0 ];
	then
            VALIDATE_S3FS_MOUNTED_DISKS=$(printf "%s\n" "${S3FS_MOUNTED_SUCCESS[@]}");
            FULL_MESSAGE="$FULL_MESSAGE"$'\n'"$VALIDATE_S3FS_MOUNTED_DISKS"$'\n';
        fi

        if [ ${#S3FS_MOUNTED_SKIP[@]} -gt 0 ];
	then
            VALIDATE_S3FS_SKIP_DISKS=$(printf "%s\n" "${S3FS_MOUNTED_SKIP[@]}");
            FULL_MESSAGE="$FULL_MESSAGE"$'\n'"$VALIDATE_S3FS_SKIP_DISKS"$'\n';
        fi

        send_notification_telegram;

    elif [ ${#DISK_FREE[@]} -eq 0 ] && [ ${#DISK_BUSY[@]} -gt 0 ];
    then
        WARNING_DISK_BUSY=$(printf "%s\n" "${DISK_BUSY[@]}");
        ALL_DISKS_BUSY="<b>Todos os discos s3fs estão em uso: Nada a ser feito!!!</b>";
        FULL_MESSAGE="$FULL_MESSAGE"$'\n'"$ALL_DISKS_BUSY"$'\n'"$WARNING_DISK_BUSY";
        send_notification_telegram;
        exit 0
    fi
}

discovery_s3fs_no_mounted_disks;
restart_s3fs_disks;

