#!/bin/bash

# Проверяем, установлен ли Python 3.x
if ! command -v python3 &> /dev/null
then
    echo "Python 3.x требуется, но не найден. Пожалуйста, установите Python 3.x."
    exit 1
fi

# Проверяем, установлен ли pip
if ! command -v pip3 &> /dev/null
then
    echo "pip требуется, но не найден. Пожалуйста, установите pip."
    exit 1
fi

# Устанавливаем необходимый Python-пакет
echo "Устанавливаем пакет apscheduler..."
pip3 install apscheduler
if [ $? -eq 0 ]; then
    echo "Пакет apscheduler успешно установлен."
else
    echo "Не удалось установить пакет apscheduler. Проверьте интернет-соединение и попробуйте снова."
    exit 1
fi

echo "Все необходимые зависимости установлены."