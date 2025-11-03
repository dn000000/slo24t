# docker_build_script.sh
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

# Проверка наличия Docker
check_docker() {
    if ! command -v docker &> /dev/null; then
        echo -e "${RED}Docker не установлен!${NC}"
        echo "Установите Docker и повторите попытку"
        exit 1
    fi
    print_status "Docker установлен"
}

# Сборка образа
build_image() {
    echo -e "${YELLOW}Сборка Docker образа...${NC}"
    docker build -t memfs:latest .
    print_status "Сборка Docker образа завершена"
}

# Запуск контейнера
run_container() {
    echo -e "${YELLOW}Запуск контейнера...${NC}"
    docker run --rm \
        --device /dev/fuse \
        --cap-add SYS_ADMIN \
        --security-opt apparmor:unconfined \
        -it \
        memfs:latest /entrypoint.sh
    print_status "Контейнер завершил работу"
}

# Запуск тестов в контейнере
run_tests() {
    echo -e "${YELLOW}Запуск тестов в контейнере...${NC}"
    docker run --rm \
        --device /dev/fuse \
        --cap-add SYS_ADMIN \
        --security-opt apparmor:unconfined \
        -it \
        memfs:latest /memfs/test_memfs_debug.sh
    print_status "Тесты выполнены"
}

# Основной блок
main() {
    echo -e "${YELLOW}=== Сборка и запуск MemFS в Docker ===${NC}"
    
    # Проверка Docker
    check_docker
    
    # Сборка образа
    build_image
    
    # Спрашиваем пользователя о запуске тестов
    echo -ne "${YELLOW}Запустить тесты? [y/N]: ${NC}"
    read -r response
    if [[ "$response" =~ ^([yY][eE][sS]|[yY])+$ ]]; then
        run_tests
    fi
    
    # Запуск контейнера
    echo -ne "${YELLOW}Запустить MemFS? [Y/n]: ${NC}"
    read -r response
    if [[ ! "$response" =~ ^([nN][oO]|[nN])+$ ]]; then
        run_container
    fi
}

# Запуск скрипта
main