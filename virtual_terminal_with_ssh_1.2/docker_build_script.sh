#!/bin/bash

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Функция для вывода статуса
print_status() {
    echo -e "${YELLOW}[*] $1${NC}"
}

# Функция для вывода успеха
print_success() {
    echo -e "${GREEN}[+] $1${NC}"
}

# Функция для вывода ошибки
print_error() {
    echo -e "${RED}[-] $1${NC}"
    exit 1
}

# Проверка наличия docker и docker-compose
print_status "Проверка наличия Docker и Docker Compose..."
if ! command -v docker &> /dev/null; then
    print_error "Docker не установлен. Установите Docker перед запуском скрипта."
fi

if ! command -v docker-compose &> /dev/null; then
    print_error "Docker Compose не установлен. Установите Docker Compose перед запуском скрипта."
fi

# Создание необходимых директорий
print_status "Создание необходимых директорий..."
mkdir -p data

# Проверка наличия необходимых файлов
print_status "Проверка наличия необходимых файлов..."
required_files=("virtual_terminal.py" "manage_users.py" "requirements.txt")
for file in "${required_files[@]}"; do
    if [ ! -f "$file" ]; then
        print_error "Файл $file не найден!"
    fi
done

# Сборка и запуск контейнеров
print_status "Сборка и запуск контейнеров..."
docker-compose up --build -d

# Проверка статуса запуска
if [ $? -eq 0 ]; then
    print_success "Виртуальный терминал успешно запущен!"
    echo -e "${GREEN}Для подключения используйте команду:${NC}"
    echo -e "ssh -p 2222 username@localhost или ssh -o PreferredAuthentications=password -o PubkeyAuthentication=no -p 2222 username@hostname"
    echo -e "${YELLOW}Не забудьте создать пользователя с помощью:${NC}"
    echo -e "docker exec -it virtual-terminal python3 /app/manage_users.py <username> <password>"
else
    print_error "Ошибка при запуске контейнеров"
fi