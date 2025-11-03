# entrypoint.sh
#!/bin/bash

# Создаем точку монтирования
mkdir -p /mnt/memfs

# Запускаем MemFS в фоновом режиме
/memfs/memfs /mnt/memfs &

# Ждем немного, чтобы MemFS успел смонтироваться
sleep 2

# Проверяем, что файловая система смонтирована
if mountpoint -q /mnt/memfs; then
    echo "MemFS успешно смонтирована в /mnt/memfs"
    echo "Доступные команды:"
    echo "  ls /mnt/memfs       - просмотр содержимого"
    echo "  cd /mnt/memfs       - перейти в директорию"
    echo "  touch /mnt/memfs/file.txt  - создать файл"
    echo "  echo 'test' > /mnt/memfs/file.txt  - записать в файл"
    echo "  cat /mnt/memfs/file.txt    - прочитать файл"
    echo "Для выхода нажмите Ctrl+D или введите 'exit'"
    echo ""
else
    echo "Ошибка: MemFS не смонтирована"
    exit 1
fi

# Запускаем оболочку
/bin/bash

# При выходе из оболочки, размонтируем MemFS
fusermount -u /mnt/memfs
