# Backup Solution

Serviço de backup automatizado do volume `vaultwarden-data`: snapshots deduplicados com [Borg](https://www.borgbackup.org/) orquestrados pelo [Borgmatic](https://torsion.org/borgmatic/), sincronizados ao Google Drive via [Rclone](https://rclone.org/) e agendados pelo [Supercronic](https://github.com/aptible/supercronic) em container [Docker](https://docs.docker.com).

## Sumário

- [Arquitetura](#arquitetura)
- [Quickstart](#quickstart)
- [Fluxo de inicialização](#fluxo-de-inicialização)
- [Configuração interna](#configuração-interna)
- [Referência de comandos](#referência-de-comandos)
- [Restauração](#restauração)
- [Segurança](#segurança)

---

## Arquitetura

```mermaid
flowchart LR
    cron[Supercronic<br/>cron diário] --> backup["scripts/backup.sh"]
    backup --> borgmatic["borgmatic create"]
    data[("data<br/>")] --> borgmatic
    borgmatic --> repo[("Repositório Borg<br/>volume backup-local-borg")]
    repo -- "pós-check: rclone sync" --> drive[("Google Drive<br/>gcp-storage:BACKUP-VOLUMES")]
    borgmatic -- "falha/conclusão" --> mail["E-mail via Apprise<br/>Gmail SMTP"]
```

- **Retenção**: `keep_daily: 7`, `keep_weekly: 4`, `keep_monthly: 6`
- **Checks**: integridade de `repository` e `archives` a cada 2 semanas
- **Logs**: `/var/log/borg/borg-backup.log`, rotação mensal com retenção de 12 meses (gzip)

---

## Quickstart

### 1. Configurar variáveis de ambiente

```bash
cp example.env .env
```

Edite `.env` com credenciais SMTP (Gmail) e senha forte para o repositório:

```env
SMTP_USER=<seu_usuario>
SMTP_PASS=<sua_senha>
SMTP_PORT=587
SMTP_TO=<destinatario>
DATA_DIR=<diretório_de_dados>
BORG_PASSPHRASE=<senha_forte>
```

### 2. Configurar o rclone

O arquivo `rclone_config/rclone.conf` deve conter o remote `gcp-storage` apontando para o Google Drive.

> Recomendado: instale o rclone no host, autentique o remote e copie o `rclone.conf` para `rclone_config/`.

Teste o acesso:

```bash
docker compose run --rm debian_container rclone lsd gcp-storage: --config /root/.config/rclone/rclone.conf
```

Para reautorizar o remote (token expirado):

```powershell
# no host
rclone config reconnect gcp-storage: --config .\rclone_config\rclone.conf
```

### 3. Iniciar o serviço

```bash
docker compose up -d --build
```

No primeiro start, o `bootstrap.sh` cria o repositório Borg e exporta chaves para `borg-keys/`.

### 4. Executar um backup manual

```bash
docker compose exec borg-backup /bin/sh -c '/scripts/backup.sh'
```

### 5. Verificar logs

```bash
docker compose exec borg-backup tail -f /var/log/borg/borg-backup.log
```

Logs antigos rotacionados ficam comprimidos em `/var/log/borg/` (`gunzip -c <arquivo>` para ler).

---

## Fluxo de inicialização

Resumo do `scripts/bootstrap.sh` (entrypoint do container):

```mermaid
flowchart TD
    A[Container inicia] --> B[Carrega /etc/cron.env se existir]
    B --> C[Ajusta PATH para o venv do Borg]
    C --> D{Repositório Borg existe?}
    D -- não --> E[Cria repositório e exporta chaves<br/>para borg-keys/]
    D -- sim --> F[supercronic em foreground<br/>mantém container ativo]
    E --> F
```

---

## Configuração interna

| Arquivo | Função |
| --- | --- |
| `compose.yml` | Serviço `borg-backup`: monta `data`, volume Borg local, `borg-keys/`, configs e scripts; entrypoint é o `bootstrap.sh` |
| `Dockerfile` | `debian:bookworm-slim` + rclone + venv Python (`uv`) com BorgBackup, borgmatic e apprise |
| `config.yaml` | Fonte/repositório, retenção, checks, notificações Apprise e `rclone sync` pós-check |

| `.env` | Credenciais SMTP e `BORG_PASSPHRASE` |
| `config/supercronic.conf` | Agenda backup diário e logrotate às 17:05 |
| `scripts/backup.sh` | Executa `borgmatic create` e grava status no log |
| `config/logrotate.conf` | Rotação mensal dos logs, 12 rotações gzip com `copytruncate` |

Observações:

- O repositório local é espelhado no Drive após cada backup; para mudar destino/remoto, edite o comando `rclone sync` em `config.yaml`.
- Para incluir outras fontes, ajuste `source_directories` em `config.yaml`.

---

## Referência de comandos

No diretório do projeto use `docker compose exec borg-backup <comando>`; fora dele, `docker exec -it <nome_do_container> <comando>`.

| Ação | Comando |
| --- | --- |
| Listar archives | `docker compose exec borg-backup borg list -r /volumes/backup-local-borg` |
| Simular prune (retenção) | `docker compose exec borg-backup /bin/sh -c 'borgmatic prune --list --verbosity 2'` |
| Verificação de integridade | `docker compose exec borg-backup borg check --repo /volumes/backup-local-borg/ --verify-data -v` |
| Comparar dois archives | `docker compose exec borg-backup borg diff -r /volumes/backup-local-borg <ARCHIVE1> <ARCHIVE2>` |
| Extrair arquivo p/ stdout | `docker compose exec borg-backup borg extract --stdout -r /volumes/backup-local-borg <ARCHIVE> volumes/vaultwarden-data/config.json > /tmp/v2.txt` |
| Listar pastas no Drive | `docker compose run --rm debian_container rclone lsd gcp-storage: --config /root/.config/rclone/rclone.conf` |
| Reautorizar rclone (host) | `rclone config reconnect gcp-storage: --config .\rclone_config\rclone.conf` |

---

## Restauração

> **Observação:** o `borg extract` extrai para o diretório corrente do container, e cada `docker compose exec` abre um shell novo no `WORKDIR` da imagem (`/app`) — o `cd` não persiste entre execuções. Por isso o destino é definido no mesmo comando com `sh -c "mkdir -p <pasta> && cd <pasta> && borg extract ..."`. As extrações usam a pasta dedicada `/volumes/extracoes` (efêmera: perde ao recriar o container) e `--strip-components 2`, que remove o prefixo `volumes/data/` e deixa os arquivos direto na pasta.

1. Sincronizar o repositório do Drive para um diretório temporário:

```bash
docker compose exec borg-backup rclone sync gcp-storage:BACKUP-VOLUMES /tmp/backup-local-borg --config /root/.config/rclone/rclone.conf -v
```

2. Listar archives disponíveis:

```bash
docker compose exec borg-backup borg repo-list -r /tmp/backup-local-borg
```

3. Visualizar o conteúdo de um archive antes de extrair:

```bash
docker compose exec borg-backup borg list -r /tmp/backup-local-borg <NOME_DO_ARQUIVO>
```

> Use `| grep <padrão>` ou `| head -n 50` para filtrar a saída. Para simular a extração sem gravar nada: `borg extract --list --dry-run -r /tmp/backup-local-borg::<NOME_DO_ARQUIVO>`.

4. Extrair um snapshot completo para a pasta de extração dedicada:

```bash
docker compose exec borg-backup sh -c "mkdir -p /volumes/extracoes && cd /volumes/extracoes && borg extract --strip-components 2 -r /tmp/backup-local-borg <NOME_DO_ARQUIVO>"
```

O `--strip-components 2` remove o prefixo `volumes/data/` dos caminhos do archive, então os arquivos aparecem direto em `/volumes/extracoes`. Para disponibilizá-los no host, mova-os para `/volumes/data`.

5. Verificar o que foi extraído:

```bash
docker compose exec borg-backup ls -lhR /volumes/extracoes | head -n 30
```

6. Ou apenas arquivos/diretórios específicos (o caminho inclui o prefixo interno do archive):

```bash
docker compose exec borg-backup sh -c "mkdir -p /volumes/extracoes && cd /volumes/extracoes && borg extract --strip-components 2 -r /tmp/backup-local-borg <NOME_DO_ARQUIVO> volumes/data/path/do/arquivo"
```

7. Mova dados restaurados da snapshot para o diretório original com:

```bash
docker compose exec borg-backup bash -c "cd / && cp -r /volumes/extracoes/. /volumes/data/"
```

---

## Segurança

- Proteja `.env`, `borg-keys/` e `rclone_config/rclone.conf` — nunca os versionem.
- Guarde cópia offline das chaves (`repository.key`, `repository-paper.txt`, `repository-qr.html`); sem elas o repositório é irrecuperável.
- Nunca compartilhe `BORG_PASSPHRASE`.
- Valide o acesso SMTP antes de depender das notificações por e-mail.
- Faça restaurações de teste periódicas para garantir que chaves e backups funcionam.
