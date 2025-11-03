# Dockerfile
FROM python:3.9-slim

WORKDIR /app

# Установка необходимых зависимостей
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    bash \
    && rm -rf /var/lib/apt/lists/*

# Копирование файлов проекта
COPY backup_script.py /app/
COPY test_backup.sh /app/
COPY requirements.txt /app/

# Установка Python зависимостей
RUN pip install --no-cache-dir -r requirements.txt

# Делаем скрипт тестирования исполняемым
RUN chmod +x /app/test_backup.sh

# Точка входа по умолчанию
CMD ["python", "backup_script.py"]