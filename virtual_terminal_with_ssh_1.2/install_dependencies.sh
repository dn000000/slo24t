#!/bin/bash

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

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
}

# Функция проверки успешности выполнения команды
check_status() {
    if [ $? -eq 0 ]; then
        print_success "$1"
    else
        print_error "$2"
        exit 1
    fi
}

# Проверка root прав
if [ "$EUID" -ne 0 ]; then
    print_error "Этот скрипт должен быть запущен с правами root"
    echo "Попробуйте: sudo $0"
    exit 1
fi

# Определение дистрибутива Linux
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$NAME
    VER=$VERSION_ID
else
    print_error "Невозможно определить дистрибутив Linux"
    exit 1
fi

print_status "Установка зависимостей для $OS $VER"

# Функция установки для Ubuntu/Debian
install_ubuntu_debian() {
    print_status "Обновление списка пакетов..."
    apt-get update
    check_status "Список пакетов обновлен" "Ошибка при обновлении списка пакетов"

    print_status "Установка необходимых системных пакетов..."
    apt-get install -y \
        apt-transport-https \
        ca-certificates \
        curl \
        gnupg \
        lsb-release \
        python3 \
        python3-pip \
        openssh-server
    check_status "Системные пакеты установлены" "Ошибка при установке системных пакетов"

    print_status "Установка Docker..."
    # Удаление старых версий Docker если есть
    apt-get remove -y docker docker-engine docker.io containerd runc

    # Добавление официального GPG-ключа Docker
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
    
    # Добавление репозитория Docker
    echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu \
    $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

    apt-get update
    apt-get install -y docker-ce docker-ce-cli containerd.io
    check_status "Docker установлен" "Ошибка при установке Docker"

    # Запуск и включение автозапуска Docker
    systemctl start docker
    systemctl enable docker
    check_status "Docker запущен и добавлен в автозапуск" "Ошибка при настройке Docker"
}

# Функция установки для CentOS
install_centos() {
    print_status "Установка необходимых системных пакетов..."
    yum install -y epel-release
    yum install -y \
        python3 \
        python3-pip \
        openssh-server \
        yum-utils
    check_status "Системные пакеты установлены" "Ошибка при установке системных пакетов"

    print_status "Установка Docker..."
    # Удаление старых версий Docker если есть
    yum remove -y docker docker-client docker-client-latest docker-common docker-latest docker-latest-logrotate docker-logrotate docker-engine

    # Добавление репозитория Docker
    yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
    
    yum install -y docker-ce docker-ce-cli containerd.io
    check_status "Docker установлен" "Ошибка при установке Docker"

    # Запуск и включение автозапуска Docker
    systemctl start docker
    systemctl enable docker
    check_status "Docker запущен и добавлен в автозапуск" "Ошибка при настройке Docker"
}

# Установка Python пакетов
install_python_packages() {
    print_status "Установка Python пакетов..."
    pip3 install asyncssh asyncio bcrypt docker
    check_status "Python пакеты установлены" "Ошибка при установке Python пакетов"
}

# Загрузка базового образа Ubuntu
install_docker_image() {
    print_status "Загрузка базового образа Ubuntu..."
    docker pull ubuntu:20.04
    check_status "Базовый образ Ubuntu загружен" "Ошибка при загрузке образа Ubuntu"
}

# Функция для генерации SSH ключей
generate_ssh_keys() {
    read -p "Хотите сгенерировать SSH ключи? (y/n): " generate_keys
    if [[ $generate_keys == "y" || $generate_keys == "Y" ]]; then
        print_status "Генерация SSH ключа хоста..."
        if [ ! -f "ssh_host_key" ]; then
            ssh-keygen -t rsa -b 4096 -f ssh_host_key -N ''
            check_status "SSH ключ хоста создан" "Ошибка при создании SSH ключа"
            chmod 600 ssh_host_key
            print_success "Ключи созданы и права доступа настроены"
        else
            print_error "Файл ssh_host_key уже существует. Пожалуйста, удалите его сначала, если хотите создать новый."
        fi
    else
        print_status "Пропуск генерации SSH ключей"
    fi
}

# Основная логика установки
case "$OS" in
    *"Ubuntu"*|*"Debian"*)
        install_ubuntu_debian
        ;;
    *"CentOS"*)
        install_centos
        ;;
    *)
        print_error "Неподдерживаемая операционная система: $OS"
        exit 1
        ;;
esac

install_python_packages
install_docker_image
generate_ssh_keys

print_success "Установка зависимостей завершена успешно!"
echo -e "${GREEN}Все необходимые компоненты установлены${NC}"
echo -e "${YELLOW}Теперь вы можете запустить систему виртуального терминала командой:${NC}"
echo -e "python3 virtual_terminal.py"
