FROM ubuntu:latest

# Установка необходимых пакетов
RUN apt-get update && apt-get install -y \
    gcc \
    libfuse3-dev \
    make \
    pkg-config \
    fuse3 \
    && rm -rf /var/lib/apt/lists/*

# Создание рабочей директории
WORKDIR /memfs

# Копирование исходных файлов
COPY memfs.c .
COPY test_memfs_debug.sh .

# Компиляция MemFS
RUN gcc -o memfs memfs.c `pkg-config fuse3 --cflags --libs` -pthread \
    && chmod +x memfs \
    && chmod +x test_memfs_debug.sh

# Копирование entrypoint скрипта
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Точка входа не указывается здесь, так как она передается в команде docker run
