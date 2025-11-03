# Используем Ubuntu 20.04 как базовый образ
FROM ubuntu:20.04

# Установка переменных среды для предотвращения интерактивных запросов при установке
ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=UTC

# Обновление системы и установка необходимых пакетов
RUN apt-get update && apt-get install -y \
    python3 \
    python3-pip \
    openssh-server \
    curl \
    gnupg \
    lsb-release \
    apt-transport-https \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Установка Docker
RUN curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
    | tee /etc/apt/sources.list.d/docker.list > /dev/null \
    && apt-get update \
    && apt-get install -y docker-ce docker-ce-cli containerd.io \
    && rm -rf /var/lib/apt/lists/*

# Создание рабочей директории
WORKDIR /app

# Копирование файлов проекта
COPY virtual_terminal.py /app/
COPY manage_users.py /app/
COPY requirements.txt /app/
COPY install_dependencies.sh /app/

# Установка Python зависимостей
RUN pip3 install --no-cache-dir -r requirements.txt

# Создание необходимых директорий для SSH
RUN mkdir -p /run/sshd \
    && mkdir -p /root/.ssh

# Генерация SSH ключей для хоста при первом запуске
RUN ssh-keygen -t rsa -b 4096 -f /app/ssh_host_key -N ''

# Настройка прав доступа
RUN chmod 600 /app/ssh_host_key \
    && chmod +x /app/install_dependencies.sh

# Безопасное добавление пользователя в группу docker
RUN getent group docker || groupadd docker; \
    usermod -aG docker root

# Открытие порта для SSH
EXPOSE 2222

# Создание скрипта запуска
RUN echo '#!/bin/bash\n\
service docker start\n\
python3 /app/virtual_terminal.py\n\
' > /app/start.sh \
    && chmod +x /app/start.sh

# Команда запуска контейнера
ENTRYPOINT ["/app/start.sh"]