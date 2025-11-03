#!/bin/bash

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Функция для вывода статуса
print_status() {
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}[OK]${NC} $1"
    else
        echo -e "${RED}[ОШИБКА]${NC} $1"
        exit 1
    fi
}

# Функция проверки root прав
check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo -e "${RED}Этот скрипт требует прав администратора (root)${NC}"
        echo "Пожалуйста, запустите скрипт с помощью sudo"
        exit 1
    fi
}

# Определение дистрибутива
detect_distro() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$NAME
        VER=$VERSION_ID
    else
        echo -e "${RED}Невозможно определить дистрибутив Linux${NC}"
        exit 1
    fi
}

# Функция установки зависимостей
install_dependencies() {
    echo -e "${YELLOW}Установка необходимых зависимостей...${NC}"
    
    case $OS in
        "Ubuntu"|"Debian GNU/Linux")
            apt-get update
            print_status "Обновление списка пакетов"
            
            apt-get install -y gcc libfuse3-dev make pkg-config
            print_status "Установка основных зависимостей"
            ;;
            
        "Fedora")
            dnf update -y
            print_status "Обновление списка пакетов"
            
            dnf install -y gcc fuse3-devel make pkg-config
            print_status "Установка основных зависимостей"
            ;;
            
        "CentOS Linux"|"Red Hat Enterprise Linux")
            yum update -y
            print_status "Обновление списка пакетов"
            
            yum install -y gcc fuse3-devel make pkg-config
            print_status "Установка основных зависимостей"
            ;;
            
        *)
            echo -e "${RED}Неподдерживаемый дистрибутив: $OS${NC}"
            echo "Пожалуйста, установите следующие пакеты вручную:"
            echo "- gcc"
            echo "- libfuse3-dev или fuse3-devel"
            echo "- make"
            echo "- pkg-config"
            exit 1
            ;;
    esac
}

# Функция проверки установленных компонентов
check_installation() {
    echo -e "${YELLOW}Проверка установленных компонентов...${NC}"
    
    # Проверка GCC
    gcc --version >/dev/null 2>&1
    print_status "GCC установлен"
    
    # Проверка pkg-config
    pkg-config --version >/dev/null 2>&1
    print_status "pkg-config установлен"
    
    # Проверка make
    make --version >/dev/null 2>&1
    print_status "make установлен"
    
    # Проверка FUSE
    pkg-config --exists fuse3
    print_status "FUSE3 установлен"
}

# Создание точки монтирования
create_mount_point() {
    echo -ne "${YELLOW}Хотите создать точку монтирования? [y/N]: ${NC}"
    read -r response

    if [[ "$response" =~ ^([yY][eE][sS]|[yY])+$ ]]; then
        echo -ne "${YELLOW}Укажите путь для точки монтирования [/tmp/memfs]: ${NC}"
        read -r mount_point
        
        # Если пользователь не указал путь, используем значение по умолчанию
        mount_point=${mount_point:-/tmp/memfs}
        
        if [ ! -d "$mount_point" ]; then
            mkdir -p "$mount_point"
            print_status "Создана точка монтирования $mount_point"
        else
            echo -ne "${YELLOW}Точка монтирования $mount_point уже существует. Очистить её? [y/N]: ${NC}"
            read -r clear_response
            
            if [[ "$clear_response" =~ ^([yY][eE][sS]|[yY])+$ ]]; then
                rm -rf "${mount_point:?}"/*
                print_status "Точка монтирования $mount_point очищена"
            fi
        fi
        
        # Установка правильных прав доступа
        chmod 755 "$mount_point"
        print_status "Установлены права доступа для точки монтирования"
        
        echo -e "${GREEN}Точка монтирования готова к использованию:${NC} $mount_point"
    else
        echo -e "${YELLOW}Пропуск создания точки монтирования${NC}"
    fi
}

# Основной блок выполнения
main() {
    echo -e "${YELLOW}=== Установка MemFS ===${NC}"
    
    # Проверка root прав
    check_root
    
    # Определение дистрибутива
    detect_distro
    echo -e "${GREEN}Обнаружен дистрибутив:${NC} $OS $VER"
    
    # Установка зависимостей
    install_dependencies
    
    # Проверка установки
    check_installation
    
    # Создание точки монтирования
    create_mount_point
    
    echo -e "\n${GREEN}=== Установка MemFS успешно завершена ===${NC}"
    echo -e "Теперь вы можете собрать MemFS командой:"
    echo -e "${YELLOW}gcc -o memfs memfs.c \`pkg-config fuse3 --cflags --libs\` -pthread${NC}"
}

# Запуск основного блока
main
