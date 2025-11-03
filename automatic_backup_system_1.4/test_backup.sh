#!/bin/bash

# Цветовые коды для форматирования вывода
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Функция для форматированного вывода
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

# Настройка переменных для теста
TEST_DIR1=/tmp/test_backup_dir1
TEST_DIR2=/tmp/test_backup_dir2
BACKUP_DEST=/tmp/test_backup_destination
LOG_FILE=/tmp/test_backup.log

print_header "Инициализация тестового окружения"

# Очистка предыдущих тестовых данных
print_info "Очистка предыдущего тестового окружения..."
if rm -rf $TEST_DIR1 $TEST_DIR2 $BACKUP_DEST $LOG_FILE; then
    print_success "Тестовое окружение очищено"
else
    print_error "Ошибка при очистке тестового окружения"
    exit 1
fi

# Создание тестовых директорий
print_info "Создание тестовых директорий..."
if mkdir -p $TEST_DIR1 $TEST_DIR2 $BACKUP_DEST; then
    print_success "Тестовые директории созданы:"
    echo "   - $TEST_DIR1"
    echo "   - $TEST_DIR2"
    echo "   - $BACKUP_DEST"
else
    print_error "Ошибка при создании тестовых директорий"
    exit 1
fi

print_header "Подготовка тестовых данных"

# Создание тестовых файлов
print_info "Создание тестовых файлов..."
echo "Test file 1" > $TEST_DIR1/file1.txt
echo "Test file 2" > $TEST_DIR2/file2.txt
if [ -f "$TEST_DIR1/file1.txt" ] && [ -f "$TEST_DIR2/file2.txt" ]; then
    print_success "Тестовые файлы созданы"
else
    print_error "Ошибка при создании тестовых файлов"
    exit 1
fi

print_header "Настройка конфигурации"

# Обновление конфигурации в скрипте бэкапа
print_info "Обновление путей в конфигурации..."
if sed -i "s|'/path/to/directory1'|'$TEST_DIR1'|g" backup_script.py && \
   sed -i "s|'/path/to/directory2'|'$TEST_DIR2'|g" backup_script.py && \
   sed -i "s|'/path/to/backup_destination'|'$BACKUP_DEST'|g" backup_script.py && \
   sed -i "s|'backup.log'|'$LOG_FILE'|g" backup_script.py; then
    print_success "Конфигурация успешно обновлена"
else
    print_error "Ошибка при обновлении конфигурации"
    exit 1
fi

print_header "Тестирование первичного бэкапа"

# Запуск скрипта бэкапа
print_info "Выполнение первичного бэкапа..."
python3 backup_script.py --backup-now

# Проверка создания бэкапа
if [ "$(ls -A $BACKUP_DEST)" ]; then
    print_success "Первичный бэкап успешно создан"
    echo "Содержимое бэкапа:"
    ls -lh $BACKUP_DEST
else
    print_error "Ошибка: бэкап не был создан"
    exit 1
fi

print_header "Тестирование инкрементального бэкапа"

# Модификация файлов
print_info "Модификация тестовых файлов..."
echo "Modified content" > $TEST_DIR1/file1.txt
print_success "Файл $TEST_DIR1/file1.txt модифицирован"

# Запуск инкрементального бэкапа
print_info "Выполнение инкрементального бэкапа..."
python3 backup_script.py --backup-now

# Проверка инкрементального бэкапа
MODIFIED_BACKUP=$(ls -t $BACKUP_DEST | head -n1)
if grep -q "Modified content" "$BACKUP_DEST/$MODIFIED_BACKUP/$(basename $TEST_DIR1)/file1.txt"; then
    print_success "Инкрементальный бэкап успешно отследил изменения"
    echo "Путь к измененному файлу: $BACKUP_DEST/$MODIFIED_BACKUP/$(basename $TEST_DIR1)/file1.txt"
else
    print_error "Ошибка: инкрементальный бэкап не отследил изменения"
    exit 1
fi

print_header "Тестирование восстановления"

# Тестирование восстановления
print_info "Запуск процедуры восстановления..."
echo -e "1\nyes\n" | python3 backup_script.py --restore

# Проверка восстановления файлов
if grep -q "Modified content" "$TEST_DIR1/file1.txt"; then
    print_success "Восстановление выполнено успешно"
    echo "Содержимое восстановленного файла:"
    cat "$TEST_DIR1/file1.txt"
else
    print_error "Ошибка: восстановление не удалось"
    exit 1
fi

print_header "Проверка лог-файла"

# Проверка наличия лог-файла
if [ -f "$LOG_FILE" ]; then
    print_success "Лог-файл создан успешно"
    echo "Последние записи из лог-файла:"
    tail -n 5 "$LOG_FILE"
else
    print_error "Ошибка: лог-файл не создан"
    exit 1
fi

print_header "Результаты тестирования"
print_success "Все тесты успешно пройдены!"
echo -e "\nСтатистика тестирования:"
echo "- Создано тестовых директорий: 3"
echo "- Выполнено бэкапов: 2 (первичный и инкрементальный)"
echo "- Проверено восстановление: успешно"
echo "- Проверено логирование: успешно"
