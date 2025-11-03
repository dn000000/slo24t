# build.sh
#!/bin/bash

# Цветовые коды для вывода
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Функции для форматированного вывода
print_header() {
    echo -e "\n${BLUE}=== $1 ===${NC}\n"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_info() {
    echo -e "${YELLOW}➜ $1${NC}"
}

# Проверка наличия Docker
check_docker() {
    if ! command -v docker &> /dev/null; then
        print_error "Docker не установлен. Пожалуйста, установите Docker и попробуйте снова."
        exit 1
    fi
}

# Функция для сборки Docker образа
build_docker_image() {
    print_header "Сборка Docker образа"
    if docker build -t backup-system .; then
        print_success "Docker образ успешно собран"
    else
        print_error "Ошибка при сборке Docker образа"
        exit 1
    fi
}

# Функция для запуска контейнера с тестами
run_with_tests() {
    print_header "Запуск контейнера с тестированием"
    if docker run --rm backup-system ./test_backup.sh; then
        print_success "Тестирование успешно завершено"
    else
        print_error "Тестирование завершилось с ошибками"
        exit 1
    fi
}

# Функция для запуска контейнера без тестов
run_without_tests() {
    print_header "Запуск контейнера в обычном режиме"
    if docker run -d --name backup-system-container backup-system; then
        print_success "Контейнер успешно запущен"
        print_info "Для просмотра логов используйте: docker logs backup-system-container"
        print_info "Для остановки контейнера используйте: docker stop backup-system-container"
    else
        print_error "Ошибка при запуске контейнера"
        exit 1
    fi
}

# Основная логика скрипта
main() {
    print_header "Система Автоматического Бэкапа - Сборка и Запуск"
    
    # Проверка Docker
    check_docker
    
    # Сборка образа
    build_docker_image
    
    # Запрос пользователю о запуске тестов
    print_info "Выберите режим запуска:"
    echo "1) Запустить с тестированием"
    echo "2) Запустить без тестирования"
    echo "3) Отмена"
    
    read -p "Введите номер опции (1-3): " choice
    
    case $choice in
        1)
            run_with_tests
            ;;
        2)
            run_without_tests
            ;;
        3)
            print_info "Операция отменена"
            exit 0
            ;;
        *)
            print_error "Неверный выбор"
            exit 1
            ;;
    esac
}

# Запуск скрипта
main