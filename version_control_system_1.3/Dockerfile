# Dockerfile
FROM python:3.9-slim

# Установка необходимых системных зависимостей
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    bash \
    procps \
    sqlite3 \
    && rm -rf /var/lib/apt/lists/*

# Установка рабочей директории
WORKDIR /app

# Копирование файлов проекта
COPY version_control.py .
COPY test_version_control.sh .
COPY requirements.txt .

# Создание пользователя для запуска приложения
RUN useradd -m -d /app appuser && \
    # Создание необходимых директорий
    mkdir -p configs data && \
    # Установка прав на директории и файлы
    chown -R appuser:appuser /app && \
    chmod +x test_version_control.sh

# Установка Python зависимостей
RUN pip install --no-cache-dir -r requirements.txt

# Том для хранения конфигурационных файлов и базы данных
VOLUME ["/app/configs", "/app/data"]

# Установка переменной окружения для базы данных
ENV DB_PATH=/app/data/versions.db

# Переключение на пользователя appuser
USER appuser

# Команда по умолчанию для запуска мониторинга
CMD ["python3", "version_control.py", "monitor", "--config_dir", "./configs", "--db_path", "./data/versions.db"]
