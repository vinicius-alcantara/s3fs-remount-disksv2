# Script de Remontagem de Discos S3FS

Este script foi desenvolvido para **remontar discos S3FS** em instâncias EC2, com o objetivo de **liberar memória RAM** do sistema operacional.  
Além disso, o script **envia notificações** de status via **Telegram** e **e-mail**, informando sobre o processo de desmontagem e remontagem dos discos.

## Pré-requisitos

Antes de utilizar o script, é necessário garantir que os seguintes pré-requisitos estejam atendidos:

### Instalações necessárias na instância

- `awscli` instalado e configurado (IAM Role associada)
- `s3fs` instalado
- `sendmail` instalado e configurado para envio de e-mails
- `curl` instalado
- `lsof` instalado

### Configuração de IAM Role para a EC2

A EC2 precisa de uma **IAM Role** associada com a seguinte política de permissões:

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "ssm:GetParameter",
                "s3:ListBucket",
                "s3:GetObject"
            ],
            "Resource": "*"
        }
    ]
}
```
> **Nota:** Para mais segurança, é recomendado restringir o `Resource` aos buckets e parâmetros necessários.

### Configurações no AWS SSM Parameter Store

Crie os seguintes parâmetros **criptografados** (**SecureString**) no AWS Systems Manager Parameter Store:

| Nome do Parâmetro                 | Descrição                                           |
|------------------------------------|-----------------------------------------------------|
| `TOKEN_BOT_API_TELEGRAM`           | Token de acesso da API do Bot do Telegram           |
| `CHAT_ID_TELEGRAM`                 | ID do Chat ou Grupo do Telegram para notificações   |
| `MAIL_FROM_NOTIFICATION_S3FS`      | Endereço de e-mail remetente                        |
| `MAIL_TO_NOTIFICATION_S3FS`        | Endereço de e-mail destinatário                     |

Garanta que estes parâmetros estejam configurados com criptografia KMS apropriada e permissões corretas para leitura pela instância.

---

## Como funciona

1. **Descoberta de Discos Montados:**  
   O script identifica os pontos de montagem atuais do `s3fs`.

2. **Desmontagem Segura:**  
   Desmonta apenas os discos `s3fs` que **não estão em uso**.

3. **Remontagem:**  
   Remonta os buckets S3 nos diretórios de destino usando `s3fs` com cache temporário.

4. **Notificações:**  
   Envia relatórios detalhados para um grupo no Telegram e também por e-mail.

---

## Agendamento via Crontab

Para que o script seja executado periodicamente (por exemplo, a cada 6 horas), configure no **crontab** da instância:

```bash
# Editar o crontab
crontab -e
```

Adicione a seguinte linha:

```bash
0 */6 * * * /caminho/para/o/seu/script.sh >> /var/log/remount_s3fs.log 2>&1
```

Explicação:

- `0 */6 * * *` → Executa o script a cada 6 horas, exatamente no minuto 0.
- Redireciona logs de execução para `/var/log/remount_s3fs.log`.

> **Importante:** Garanta que o script tenha permissão de execução (`chmod +x script.sh`).

---

## Personalização

Alguns valores podem ser ajustados diretamente no script para atender ao seu ambiente:

| Variável                         | Descrição                                  |
|-----------------------------------|--------------------------------------------|
| `CUSTOMER_NAME`                  | Nome do cliente para identificar alertas  |
| `AWS_REGION`                     | Região da AWS onde os parâmetros estão    |
| `BUCKETS_NAME`                   | Lista dos nomes dos buckets S3            |
| `MOUNT_PATH_BUCKET`              | Diretórios de montagem locais             |
| `CACHE_FILE_S3FS`                | Diretórios de cache para o `s3fs`          |
| `UID_S3FS` e `GID_S3FS`           | UID/GID do usuário e grupo no sistema      |

---

## Observações

- Caso todos os discos estejam ocupados (`busy`), o script irá **pular** a desmontagem para evitar problemas.
- Em caso de falha de montagem/desmontagem, o erro será notificado imediatamente por Telegram e e-mail.
- O script foi desenvolvido para ambientes de produção que utilizam `s3fs` em alta demanda.

---

## Licença

Este projeto está licenciado sob os termos da licença **MIT**.  
Veja o arquivo [LICENSE](LICENSE) para mais detalhes.

```
MIT License

Copyright (c) 2025 Marcus Vinícius Braga Alcântara

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

