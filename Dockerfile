FROM debian:bookworm-slim

# Instalar dependências do sistema
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        git \
        python3 \
        python3-dev \
        python3-venv \
        build-essential \
        pkg-config \
        libssl-dev \
        libacl1-dev \
        liblz4-dev \
        libzstd-dev \
        libxxhash-dev \
        libfuse3-dev \
        fakeroot \
        curl \
        unzip \
        logrotate \
        tox && \
    rm -rf /var/lib/apt/lists/*

# Instalar rclone
RUN curl -fsSL https://rclone.org/install.sh | bash

# Copiar os binários do uv diretamente da imagem oficial (método mais rápido e limpo)
COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /bin/

WORKDIR /app

RUN git clone https://github.com/borgbackup/borg.git

WORKDIR /app/borg

# Definir as variáveis de ambiente para o virtual environment
ENV VIRTUAL_ENV="/app/borg-env"
ENV PATH="$VIRTUAL_ENV/bin:$PATH"

# Criar o ambiente virtual e instalar dependências usando o uv
RUN uv venv $VIRTUAL_ENV && \
    uv pip install -r requirements.d/development.txt \
                   -r requirements.d/docs.txt && \
    uv pip install -e .[pyfuse3] borgmatic apprise


ENV SETUPTOOLS_SCM_PRETEND_VERSION=""


ENV SUPERCRONIC_URL=https://github.com/aptible/supercronic/releases/download/v0.2.46/supercronic-linux-amd64 \
    SUPERCRONIC_SHA1SUM=5bcefed628e32adc08e32634db2d10e9230dbca0 \
    SUPERCRONIC=supercronic-linux-amd64

RUN curl -fsSLO "$SUPERCRONIC_URL" \
 && echo "${SUPERCRONIC_SHA1SUM}  ${SUPERCRONIC}" | sha1sum -c - \
 && chmod +x "$SUPERCRONIC" \
 && mv "$SUPERCRONIC" "/usr/local/bin/${SUPERCRONIC}" \
 && ln -s "/usr/local/bin/${SUPERCRONIC}" /usr/local/bin/supercronic

CMD ["borg", "--version"]
