# Backup Solution

## Sumário

- [Visão geral](#visão-geral)
- [Estrutura do projeto](#estrutura-do-projeto)
- [Componentes e funcionamento](#componentes-e-funcionamento)
	- [compose.yml](#composeyml)
	- [Dockerfile](#dockerfile)
	- [config.yaml](#configyaml)
	- [Retenção e peculiaridades do config.yaml](#retenção-e-peculiaridades-do-configyaml)
- [Instalação e uso](#instalação-e-uso)
- [Restauração de backup](#restauração-de-backup)
- [Logs e rotação de arquivos](#logs-e-rotação-de-arquivos)
- [Comandos úteis de manutenção](#comandos-úteis-de-manutenção)
	- [Execução: Docker Compose vs. Docker Engine](#comandos-úteis-de-manutenção)
- [Segurança e recomendações](#segurança-e-recomendações)
- [Observações importantes](#observações-importantes)

## Visão geral

Este projeto cria um serviço de backup automatizado usando:
- [Borg Backup](https://www.borgbackup.org/) como mecanismo de snapshot e deduplicação
- [Borgmatic](https://torsion.org/borgmatic/) para orquestrar backups e verificações
- [Rclone](https://rclone.org/) para sincronizar o repositório Borg local com um remoto Google Drive
- [Docker](https://docs.docker.com) para empacotar a aplicação em um container
- [Supercronic](https://github.com/aptible/supercronic) para executar backups diários automaticamente

O objetivo é fazer backup do volume `vaultwarden-data` para um repositório Borg presente em um volume Docker local e, em seguida, sincronizar esse repositório para o remoto `gcp-storage:BACKUP-VOLUMES`.

---

## Estrutura do projeto

Arquivos e diretórios principais:
```bash
.
├── Dockerfile
├── borg-keys
│   ├── repository-paper.txt
│   ├── repository-qr.html
│   └── repository.key
├── compose.yml
├── config
│   ├── logrotate.conf
│   └── supercronic.conf
├── config.yaml
├── example.env
├── rclone_config
│   └── rclone.conf
├── readme.md
└── scripts
    ├── backup.sh
    ├── bootstrap.sh
    └── logrotate.sh
```

- `compose.yml` : definição do serviço Docker Compose
- `Dockerfile` : imagem personalizada que instala Borg Backup, borgmatic, rclone e dependências
- `.env` : variáveis de ambiente sensíveis
- `config.yaml` : configuração do borgmatic
- `config/logrotate.conf` : configuração de rotação de logs
- `scripts/bootstrap.sh` : inicialização do container, criação do repositório e arranque do supercronic
- `scripts/backup.sh` : comando de backup Borgmatic executado pelo supercronic
- `config/` : agendamento supercronic para backup e logrotate
- `rclone_config/rclone.conf` : configuração do rclone para o remoto Google Drive
- `borg-keys/` : local onde as chaves de repositório Borg são exportadas

---

## Componentes e funcionamento

### compose.yml

O serviço `borg-backup` é construído a partir do `Dockerfile` deste repositório. Ele monta:
- `vaultwarden-data` como fonte de backup em modo somente leitura
- `backup-local-borg` como repositório Borg local
- `./borg-keys` para armazenar chaves e material de recuperação
- `./rclone_config` como configuração do rclone
- `./config.yaml` como configuração do borgmatic
- `./scripts` para o código de bootstrap e backup

O `entrypoint` do container é `scripts/bootstrap.sh`, que inicializa o repositório Borg se necessário e inicia o `cron` em primeiro plano.

### Dockerfile

A imagem base usa `debian:bookworm-slim` e instala:
- dependências de sistema necessárias para compilação e execução de Borg Backup
- `rclone`
- Python 3, `uv`, e pacotes Python de desenvolvimento

Depois, cria um ambiente virtual em `/app/borg-env` e instala:
- BorgBackup a partir do código fonte
- `borgmatic`
- `apprise`

O container resultante expõe o comando `borg --version` por padrão, mas na execução do Compose o `entrypoint` subscreve esse comportamento.

## config.yaml

Configuração do borgmatic:
- `source_directories`: `/volumes/vaultwarden-data`
- `repositories`: `/volumes/backup-local-borg/`
- `keep_daily`, `keep_weekly`, `keep_monthly` para retenção de snapshots
- `checks` de integridade do repositório e dos arquivos
- `apprise` para enviar notificações por e-mail em caso de falha e conclusão
- `commands` para rodar `rclone sync` após verificações de `repository`

A sincronização final faz:

`rclone sync /volumes/backup-local-borg/ gcp-storage:BACKUP-VOLUMES --config /root/.config/rclone/rclone.conf`

Isso garante que o repositório local Borg seja espelhado no remoto Google Drive.

### Retenção e peculiaridades do `config.yaml`

- **Política de retenção**:
	- `keep_daily: 7` — mantém os snapshots diários mais recentes (tipicamente 7 dias).
	- `keep_weekly: 4` — mantém as últimas 4 snapshots semanais (tipicamente 4 semanas).
	- `keep_monthly: 6` — mantém as últimas 6 snapshots mensais (tipicamente 6 meses).

- **Formato de nome de archive**:
	- `archive_name_format: "{hostname}-{now:%Y-%m-%dT%H:%M:%S}"` — inclui timestamp com precisão de segundos para evitar colisões e facilitar rastreio.

- **Checks e frequência**:
	- `checks` contém `repository` e `archives` (com `frequency: 2 weeks`). Essas verificações ajudam a detectar corrupção, mas podem ser custosas em I/O/CPU para repositórios grandes.

- **Notificações (Apprise)**:
	- `send_logs: true` faz com que os logs sejam enviados nas notificações.
	- A URL configurada usa `mailtos://${SMTP_USER}:${SMTP_PASS}@smtp.gmail.com:${SMTP_PORT}?to=${SMTP_TO}&name=Borgmatic&starttls=yes || exit 1` — observe que o `|| exit 1` está dentro da string. Verifique se Apprise/ borgmatic aceitam a URL literal; caso cause erro, remova `|| exit 1`.

- **Comandos pós-check**:
	- O bloco `commands` executa `rclone sync /volumes/backup-local-borg/ gcp-storage:BACKUP-VOLUMES --config /root/.config/rclone/rclone.conf` após o `repository` check quando o estado for `finish`.

- **Efeitos práticos / exemplos**:
	- Com backups diários, os valores atuais mantêm ~7 snapshots recentes, agrupam versões semanais e mensais conforme as políticas acima.
	- Se houver múltiplos backups por dia, o pruning considera os intervalos (diário/semana/mês) ao escolher quais arquivos manter.

- **Recomendações**:
	- Testar `rclone sync` manualmente antes de confiar na sincronização automática.
	- Agendar verificações de integridade em janelas com baixa atividade I/O.
	- Implementar restaurações periódicas de teste para garantir que chaves e arquivos funcionem.

- **Comandos úteis**:
	- Listar archives:
		```bash
		docker compose exec borg-backup borg list -r /volumes/backup-local-borg
		```
	- Simular prune/listar retenção aplicada:
		```bash
		docker compose exec borg-backup /bin/sh -c 'borgmatic prune --list --verbosity 2'
		```
	- Testar `rclone`:
		```bash
		docker compose run --rm debian_container rclone lsd gcp-storage: --config /root/.config/rclone/rclone.conf
		```

### .env

Variáveis de ambiente carregadas pelo Compose:
- `SMTP_USER`
- `SMTP_PASS`
- `SMTP_PORT`
- `SMTP_TO`
- `BORG_PASSPHRASE`

A configuração atual do borgmatic utiliza Gmail como servidor SMTP fixo (`smtp.gmail.com`).

> Segurança: nunca versionar `.env` em repositórios públicos. Proteja `BORG_PASSPHRASE` e as credenciais SMTP.

### `scripts/bootstrap.sh`

Fluxo de inicialização:
1. Carrega variáveis de `/etc/cron.env` se existir
2. Exporta o `PATH` para usar o ambiente virtual Borg
3. Verifica se o repositório Borg existe
4. Se não existir, cria o repositório e exporta as chaves para `borg-keys/`
7. Executa `supercronic /etc/cron.d/supercronic.conf` para manter o container ativo

### `scripts/backup.sh`

O job executa `borgmatic create` e grava o status do backup no log.

---

## Instalação e uso

### 1. Configurar variáveis de ambiente

Edite `.env` com as credenciais SMTP e a senha do repositório Borg:

```env
SMTP_USER=<seu_usuario>
SMTP_PASS=<sua_senha>
SMTP_PORT=587
SMTP_TO=<destinatario>
BORG_PASSPHRASE=<senha_forte>
```

Use uma senha forte para `BORG_PASSPHRASE`.

### 2. Configurar o rclone

O arquivo `rclone_config/rclone.conf` deve conter o remote `gcp-storage` configurado para acesso ao Google Drive.

Atenção: Recomendo que instale o Rclone no host e faça autenticação. Posteriormente copie o arquivo rclone.conf para /rclone_config.
Caso faça isso basta pular para [Teste o acesso](#teste-o-acesso) e [Iniciar o serviço](#3-iniciar-o-serviço-docker-compose)

### Para reautorizar o remote no container:

```bash
docker compose run --rm debian_container rclone config reconnect gcp-storage: --config /root/.config/rclone/rclone.conf
```

### Para reautorizar pelo host:

```powershell
rclone config reconnect gcp-storage: --config .\rclone_config\rclone.conf
```

### Teste o acesso:

```bash
docker compose run --rm debian_container rclone lsd gcp-storage: --config /root/.config/rclone/rclone.conf
```

### 3. Iniciar o serviço Docker Compose

```bash
docker compose up -d --build
```

No primeiro start, o script `bootstrap.sh`:
- cria o repositório Borg se necessário
- exporta as chaves e arquivos de recuperação para `borg-keys`
- inicia o supercronic

### 4. Executar um backup manual

Para disparar manualmente o backup dentro do container:

(logs serão gerados automáticamente)
```bash
docker compose exec borg-backup /bin/sh -c '/scripts/backup.sh'
```


### 5. Verificar logs

Os logs do backup são armazenados em `/var/log/borg/borg-backup.log` dentro do container:

```bash
docker compose exec borg-backup tail -n 50 /var/log/borg/borg-backup.log
```

---

## Logs e rotação de arquivos

### Localização

Os logs dos backups são centralizados em:

- **Container**: `/var/log/borg/borg-backup.log`
- **Host**: Volume do container (acessível via `docker compose exec`)

### Configuração logrotate

O projeto inclui configuração automática de `logrotate` para:

- **Política**: Rotação mensal
- **Retenção**: Últimos 12 meses (comprimidos)
- **Compressão**: gzip (`.gz`)
- **Arquivo original**: Truncado (`copytruncate`)

Arquivo de configuração: `logrotate/logrotate.conf`

```
/var/log/borg/*.log {
    monthly
    rotate 12
    compress
    missingok
    notifempty
    copytruncate
}
```

### Agendamento

Logrotate é executado automaticamente:

- **Horário**: 17:05 (5 minutos após o backup)
- **Frequência**: Diária
- **Cron job**: `05 17 * * * /usr/sbin/logrotate -s /var/log/logrotate.status /etc/logrotate.conf`

### Acesso aos logs arquivados

Listar logs comprimidos:

```bash
docker compose exec borg-backup ls -lh /var/log/borg/
```

Extrair e visualizar um log antigo:

```bash
docker compose exec borg-backup sh -c 'gunzip -c /var/log/borg/<NOME DO ARQUIVO> | tail -n 50'
```

### Monitoramento

Ver logs em tempo real:

```bash
docker compose exec borg-backup tail -f /var/log/borg/borg-backup.log
```

---

## Restauração de backup

A restauração envolve recuperar o repositório do remoto e extrair os arquivos desejados.

### 1. Sincronizar repositório remoto para local temporário

```bash
docker compose exec borg-backup rclone sync gcp-storage:BACKUP-VOLUMES /tmp/backup-local-borg --config /root/.config/rclone/rclone.conf
```

### 2. Listar o repositório

```bash
docker compose exec borg-backup borg repo-list -r /tmp/backup-local-borg
```

### 3. Extrair um snapshot específico
Se tiver executando os comandos via compose é necessário adicionar o comando para entrar no repositório antes de fazer a extração, se não irá para o diretório WORKDIR setado no Dockerfile.
```bash
docker compose exec borg-backup sh -c "cd / && borg extract -r /tmp/backup-local-borg::<NOME_DO_ARQUIVO> /destino/de/restauração"
```
No caso como nosso volumes de dados do vaultwarden fica em volumes, o comando ficaria assim:
```bash
docker compose exec borg-backup sh -c "cd / && borg extract -r /tmp/backup-local-borg <NOME_DO_ARQUIVO> /volumes/vaultwarden-data"
```

### 4. Recuperar arquivos específicos

Para extrair apenas um arquivo ou diretório específicos:

```bash
docker compose exec borg-backup borg extract -r /tmp/backup-local-borg::<NOME_DO_ARQUIVO> path/do/arquivo
```

---

## Comandos úteis de manutenção
### Escolhendo entre docker compose e docker

Ao interagir com o seu container de backup, a escolha do comando altera o contexto de execução:

* **`docker compose exec borg-backup <comando>`**: Use esta opção quando estiver no diretório raiz do projeto. Ele é mais seguro pois utiliza o nome do serviço definido no seu `compose.yml`, abstraindo o nome real do container (`backup-solution-borg-backup-1`) e garantindo que você está dentro do contexto do projeto.
* **`docker exec -it <nome_do_container> <comando>`**: Use esta opção se estiver em outro diretório ou se precisar rodar um comando rápido sem depender da estrutura do projeto. É a forma mais direta de acessar qualquer container pelo nome que ele recebeu no Docker Engine.

**Exemplo Prático (Verificação de Integridade):**

Se estiver dentro da pasta do projeto:

```bash
docker compose exec borg-backup borg check --repo /volumes/backup-local-borg/ --verify-data -v

```

Se estiver em qualquer outro lugar (acessando pelo nome específico do container):

```bash
docker exec -it debian_container borg check --repo /volumes/backup-local-borg/ --verify-data -v

```

---


### Listar arquivos remotos do Google Drive

```bash
docker compose run --rm debian_container rclone lsd gcp-storage: --config /root/.config/rclone/rclone.conf
```

### Comparar duas versões Borg

```bash
docker compose exec borg-backup borg diff -r /volumes/backup-local-borg <ARCHIVE1> <ARCHIVE2>
```

Exemplo:

```bash
docker compose exec borg-backup borg diff -r /volumes/backup-local-borg <arquivo1> <arquivo2>
```

### Extrair um arquivo para stdout para comparação

```bash
docker compose exec borg-backup borg extract --stdout -r /volumes/backup-local-borg <arquivo2> volumes/vaultwarden-data/config.json > /tmp/v2.txt
```

---

## Segurança e recomendações

- Proteja `.env`, `borg-keys/` e `rclone_config/rclone.conf`
- Faça backup seguro das chaves exportadas em `borg-keys/repository.key`, `repository-paper.txt` e `repository-qr.html`
- Não compartilhe `BORG_PASSPHRASE`
- Valide o acesso SMTP antes de depender de notificações por e-mail

---

## Observações importantes

- O backup local é armazenado no volume Docker `backup-local-borg`
- O repositório Borg é sincronizado automaticamente para o remoto Google Drive após cada execução de backup
- Se desejar alterar o remoto ou a pasta de destino no Drive, modifique o comando `rclone sync` em `config.yaml`
- O serviço atual assume `/volumes/vaultwarden-data` como fonte de backup. Ajuste `config.yaml` para incluir outras pastas ou volumes.
