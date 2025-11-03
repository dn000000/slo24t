#!/bin/bash

# Цвета для вывода
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Директории для тестирования
TEST_DIR="test_version_control"
CONFIG_DIR="$TEST_DIR/configs"
DB_PATH="$TEST_DIR/versions.db"
PYTHON_SCRIPT="version_control.py"
MONITOR_PID_FILE="$TEST_DIR/monitor.pid"

# Функция для проверки результата команды
check_result() {
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}[PASSED]${NC} $1"
    else
        echo -e "${RED}[FAILED]${NC} $1"
        exit 1
    fi
}

# Очистка тестового окружения
cleanup() {
    echo "Очистка тестового окружения..."
    # Остановка всех процессов мониторинга, если они еще работают
    if [ -f "$MONITOR_PID_FILE" ]; then
        PID=$(cat "$MONITOR_PID_FILE")
        if ps -p $PID > /dev/null; then
            pkill -P $PID
            kill -9 $PID 2>/dev/null
        fi
        rm -f "$MONITOR_PID_FILE"
    fi
    
    # Очистка тестовой директории
    rm -rf $TEST_DIR
    check_result "Очистка тестового окружения"
}

# Подготовка тестового окружения
setup() {
    echo "Подготовка тестового окружения..."
    mkdir -p $CONFIG_DIR
    check_result "Создание тестовых директорий"
    
    # Создание тестового конфигурационного файла
    echo "initial_config=value1" > $CONFIG_DIR/test.conf
    check_result "Создание тестового конфига"
}

# Запуск мониторинга в фоновом режиме
start_monitoring() {
    echo "Запуск мониторинга..."
    # Запуск процесса мониторинга в фоновом режиме
    python3 $PYTHON_SCRIPT monitor --config_dir $CONFIG_DIR --db_path $DB_PATH &
    MONITOR_PID=$!
    echo $MONITOR_PID > "$MONITOR_PID_FILE"
    
    # Ждем инициализации мониторинга
    sleep 2
    
    # Проверяем, что процесс все еще работает
    if ps -p $MONITOR_PID > /dev/null; then
        check_result "Запуск мониторинга"
    else
        echo -e "${RED}[FAILED]${NC} Процесс мониторинга не запустился"
        exit 1
    fi
}

# Тест создания и модификации файла
test_file_modifications() {
    echo "Тестирование модификаций файла..."
    
    # Модификация файла
    echo "modified_config=value2" >> $CONFIG_DIR/test.conf
    sleep 1
    check_result "Модификация конфига"
    
    # Создание нового файла
    echo "new_config=value3" > $CONFIG_DIR/test2.conf
    sleep 1
    check_result "Создание нового конфига"
}

# Тест просмотра истории
test_history() {
    echo "Тестирование просмотра истории..."
    python3 $PYTHON_SCRIPT history --file $CONFIG_DIR/test.conf \
        --config_dir $CONFIG_DIR --db_path $DB_PATH
    check_result "Просмотр истории"
}

# Тест сравнения версий
test_compare() {
    echo "Тестирование сравнения версий..."
    python3 $PYTHON_SCRIPT compare --file $CONFIG_DIR/test.conf \
        --version1 1 --version2 2 \
        --config_dir $CONFIG_DIR --db_path $DB_PATH
    check_result "Сравнение версий"
}

# Тест отката к предыдущей версии
test_rollback() {
    echo "Тестирование отката версии..."
    python3 $PYTHON_SCRIPT rollback --file $CONFIG_DIR/test.conf \
        --rollback_version 1 \
        --config_dir $CONFIG_DIR --db_path $DB_PATH
    check_result "Откат версии"
    
    # Проверка содержимого файла после отката
    if grep -q "initial_config=value1" "$CONFIG_DIR/test.conf"; then
        check_result "Проверка содержимого после отката"
    else
        echo -e "${RED}[FAILED]${NC} Содержимое файла после отката не соответствует ожидаемому"
        exit 1
    fi
}

# Остановка мониторинга
stop_monitoring() {
    echo "Остановка мониторинга..."
    if [ -f "$MONITOR_PID_FILE" ]; then
        PID=$(cat "$MONITOR_PID_FILE")
        if ps -p $PID > /dev/null; then
            # Сначала пытаемся остановить процесс корректно
            pkill -P $PID
            kill $PID
            sleep 1
            
            # Если процесс все еще работает, останавливаем принудительно
            if ps -p $PID > /dev/null; then
                pkill -9 -P $PID
                kill -9 $PID
            fi
            
            # Проверяем, что процесс действительно остановлен
            if ! ps -p $PID > /dev/null; then
                check_result "Остановка мониторинга"
            else
                echo -e "${RED}[FAILED]${NC} Не удалось остановить процесс мониторинга"
                exit 1
            fi
        else
            echo -e "${RED}[WARNING]${NC} Процесс мониторинга уже не работает"
        fi
        rm -f "$MONITOR_PID_FILE"
    else
        echo -e "${RED}[ERROR]${NC} Файл PID не найден"
        exit 1
    fi
}

# Обработка прерывания выполнения скрипта
trap cleanup EXIT SIGINT SIGTERM

# Главная функция тестирования
main() {
    echo "Начало тестирования системы контроля версий..."
    
    # Очистка и подготовка
    cleanup
    setup
    
    # Запуск тестов
    start_monitoring
    test_file_modifications
    test_history
    test_compare
    test_rollback
    stop_monitoring
    
    # Финальная очистка
    cleanup
    
    echo -e "${GREEN}Все тесты успешно завершены!${NC}"
}

# Запуск тестов
main
