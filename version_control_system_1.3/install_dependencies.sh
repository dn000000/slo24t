#!/bin/bash

# Цвета для вывода
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # Без цвета

# Функция для вывода цветных статусных сообщений
print_status() {
    echo -e "${GREEN}[*]${NC} $1"
}

print_error() {
    echo -e "${RED}[!]${NC} $1"
}

# Функция для проверки существования команды
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Проверка прав root
if [ "$EUID" -ne 0 ]; then
    print_error "Пожалуйста, запустите скрипт с sudo или от имени root"
    exit 1
fi

# Проверка и установка Python3
print_status "Проверка установки Python3..."
if ! command_exists python3; then
    print_status "Установка Python3..."
    if command_exists apt-get; then
        apt-get update
        apt-get install -y python3 python3-pip
    elif command_exists yum; then
        yum install -y python3 python3-pip
    else
        print_error "Не удалось определить пакетный менеджер. Пожалуйста, установите Python3 вручную."
        exit 1
    fi
fi

# Проверка версии Python
PYTHON_VERSION=$(python3 -c 'import sys; print(".".join(map(str, sys.version_info[:2])))')
print_status "Обнаружена версия Python $PYTHON_VERSION"

# Проверка и установка pip
print_status "Проверка установки pip..."
if ! command_exists pip3; then
    print_status "Установка pip..."
    if command_exists apt-get; then
        apt-get install -y python3-pip
    elif command_exists yum; then
        yum install -y python3-pip
    else
        print_error "Не удалось установить pip. Пожалуйста, установите его вручную."
        exit 1
    fi
fi

# Установка Python зависимостей
print_status "Установка Python зависимостей..."
pip3 install watchdog

# Создание необходимых директорий
print_status "Создание структуры проекта..."
mkdir -p configs

# Установка прав доступа для директории configs
print_status "Настройка прав доступа..."
chmod 755 configs

# Финальная проверка
echo
if command_exists python3 && command_exists pip3; then
    print_status "Все зависимости успешно установлены!"
    print_status "Структура проекта создана!"
    echo
    print_status "Теперь вы можете запустить систему контроля версий командой:"
    echo "    python3 version_control.py monitor --config_dir ./configs --db_path ./versions.db"
else
    print_error "Некоторые зависимости не удалось установить. Пожалуйста, проверьте сообщения об ошибках выше."
    exit 1
fi
