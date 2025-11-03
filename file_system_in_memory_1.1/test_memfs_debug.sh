#!/bin/bash

# Настройка цветного вывода
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Директория для монтирования
MOUNT_DIR="/tmp/memfs_test"

# Функция для вывода результатов тестов
print_result() {
    if [ $1 -eq 0 ]; then
        echo -e "${GREEN}✓ $2${NC}"
    else
        echo -e "${RED}✗ $2${NC}"
        echo "Error details: $3"
    fi
}

# Функция для отладочного вывода
debug_print() {
    echo -e "${YELLOW}DEBUG: $1${NC}"
}

# Функция очистки
cleanup() {
    debug_print "Unmounting filesystem..."
    fusermount -u $MOUNT_DIR 2>/dev/null
    debug_print "Removing mount directory..."
    rm -rf $MOUNT_DIR
    debug_print "Killing memfs process..."
    killall memfs 2>/dev/null
    sleep 1
}

# Начальная очистка
cleanup

# Создание директории для монтирования
mkdir -p $MOUNT_DIR
debug_print "Created mount directory at $MOUNT_DIR"

# Запуск файловой системы с выводом информации
debug_print "Starting memfs..."
./memfs -f $MOUNT_DIR &
MEMFS_PID=$!
debug_print "memfs PID: $MEMFS_PID"
sleep 2 # Ждем монтирования

echo "Starting MemFS tests..."

# Тест 1: Создание директории
debug_print "Creating test directory..."
mkdir "$MOUNT_DIR/test_dir" 2>/dev/null
print_result $? "Create directory test" "Failed to create directory"

# Тест 2: Создание файла
debug_print "Creating test file..."
echo "Hello, World!" > "$MOUNT_DIR/test_file.txt" 2>/dev/null
print_result $? "Create file test" "Failed to create file"

# Тест 3: Чтение файла
debug_print "Reading file content..."
content=$(cat "$MOUNT_DIR/test_file.txt" 2>/dev/null)
debug_print "Read content: '$content'"
if [ "$content" == "Hello, World!" ]; then
    print_result 0 "Read file test" ""
else
    print_result 1 "Read file test" "Content mismatch: '$content'"
fi

# Тест 4: Запись в существующий файл
debug_print "Writing new content to file..."
echo "New content" > "$MOUNT_DIR/test_file.txt" 2>/dev/null
content=$(cat "$MOUNT_DIR/test_file.txt" 2>/dev/null)
debug_print "New content read: '$content'"
if [ "$content" == "New content" ]; then
    print_result 0 "Write to existing file test" ""
else
    print_result 1 "Write to existing file test" "Content mismatch: '$content'"
fi

# Тест 5: Проверка списка файлов
debug_print "Listing directory content..."
ls_output=$(ls -la "$MOUNT_DIR" 2>/dev/null)
debug_print "Directory listing:\n$ls_output"
if [[ $ls_output == *"test_dir"* ]] && [[ $ls_output == *"test_file.txt"* ]]; then
    print_result 0 "List directory content test" ""
else
    print_result 1 "List directory content test" "Missing files in listing"
fi

# Тест 6: Создание вложенной директории
debug_print "Creating nested directory..."
mkdir "$MOUNT_DIR/test_dir/nested_dir" 2>/dev/null
print_result $? "Create nested directory test" "Failed to create nested directory"

# Тест 7: Создание файла во вложенной директории
debug_print "Creating file in nested directory..."
echo "Nested content" > "$MOUNT_DIR/test_dir/nested_dir/nested_file.txt" 2>/dev/null
print_result $? "Create file in nested directory test" "Failed to create nested file"

# Тест 8: Удаление файла
debug_print "Deleting test file..."
rm "$MOUNT_DIR/test_file.txt" 2>/dev/null
print_result $? "Delete file test" "Failed to delete file"

# Тест 9: Проверка удаления файла
debug_print "Verifying file deletion..."
if [ ! -f "$MOUNT_DIR/test_file.txt" ]; then
    print_result 0 "Verify file deletion test" ""
else
    print_result 1 "Verify file deletion test" "File still exists"
fi

# Тест 10: Удаление пустой директории
debug_print "Deleting nested directory..."
ls -la "$MOUNT_DIR/test_dir/nested_dir" 2>/dev/null
rmdir "$MOUNT_DIR/test_dir/nested_dir" 2> /tmp/rmdir_error
error_output=$(cat /tmp/rmdir_error)
debug_print "rmdir error output: $error_output"
print_result $? "Delete empty directory test" "Failed to delete directory: $error_output"

# Тест 11: Попытка удаления непустой директории
debug_print "Attempting to delete non-empty directory..."
rmdir "$MOUNT_DIR/test_dir" 2>/dev/null
if [ $? -ne 0 ]; then
    print_result 0 "Non-empty directory deletion prevention test" ""
else
    print_result 1 "Non-empty directory deletion prevention test" "Directory was deleted when it shouldn't have been"
fi

# Очистка и размонтирование
echo "Cleaning up..."
cleanup

echo "Tests completed!"
