#!/bin/bash

# Цвета для вывода
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Функции для вывода сообщений
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Функция для проверки наличия команды
check_command() {
    if ! command -v "$1" &> /dev/null
    then
        log_error "$1 не установлен. Пожалуйста, установите его перед запуском скрипта."
        exit 1
    fi
}

# Функция очистки
cleanup() {
    log_info "Очистка контейнеров и временных файлов..."
    docker-compose down --volumes --remove-orphans
    rm -f tmp_test_output.log
}

# Обработка сигналов прерывания
trap cleanup EXIT
trap 'exit 1' INT TERM

# Проверка наличия необходимых команд
log_info "Проверка необходимых зависимостей..."
check_command "docker"
check_command "docker-compose"

# Создание необходимых директорий
log_info "Создание структуры проекта..."
mkdir -p configs data

# Проверка наличия необходимых файлов
required_files=("version_control.py" "test_version_control.sh" "Dockerfile" "docker-compose.yml")
for file in "${required_files[@]}"
do
    if [ ! -f "$file" ]
    then
        log_error "Файл $file не найден!"
        exit 1
    fi
done

# Создание requirements.txt если его нет
if [ ! -f "requirements.txt" ]
then
    log_info "Создание requirements.txt..."
    echo "watchdog==3.0.0" > requirements.txt
fi

# Остановка существующих контейнеров
log_info "Остановка существующих контейнеров..."
docker-compose down --volumes --remove-orphans

# Сборка образа
log_info "Сборка Docker образа..."
if ! docker-compose build
then
    log_error "Ошибка при сборке Docker образа"
    exit 1
fi

# Запуск контейнера в фоновом режиме
log_info "Запуск контейнера..."
if ! docker-compose up -d
then
    log_error "Ошибка при запуске контейнера"
    exit 1
fi

# Ожидание запуска контейнера
log_info "Ожидание запуска контейнера..."
sleep 5

# Запуск тестов
log_info "Запуск тестов..."
if ! docker-compose exec -T version-control ./test_version_control.sh > tmp_test_output.log 2>&1
then
    if [ -f tmp_test_output.log ]; then
        log_error "Тесты завершились с ошибкой"
        cat tmp_test_output.log
    else
        log_error "Не удалось получить вывод тестов"
    fi
    exit 1
fi

# Проверка результатов тестов
if grep -q "FAILED" tmp_test_output.log
then
    log_error "Обнаружены провальные тесты:"
    grep -A 2 "FAILED" tmp_test_output.log
    exit 1
else
    log_info "Все тесты успешно пройдены!"
    cat tmp_test_output.log
fi

# Вывод информации о использовании
log_info "Сборка и тестирование успешно завершены!"
echo
log_info "Для использования системы контроля версий выполните следующие команды:"
echo -e "${GREEN}Мониторинг изменений:${NC}"
echo "docker-compose exec version-control python3 version_control.py monitor --config_dir ./configs --db_path ./data/versions.db"
echo
echo -e "${GREEN}Просмотр истории:${NC}"
echo "docker-compose exec version-control python3 version_control.py history --file ./configs/example.conf --config_dir ./configs --db_path ./data/versions.db"
echo
echo -e "${GREEN}Для остановки системы:${NC}"
echo "docker-compose down"

exit 0
