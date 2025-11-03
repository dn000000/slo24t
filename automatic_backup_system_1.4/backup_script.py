import os
import shutil
import logging
from datetime import datetime
from apscheduler.schedulers.background import BackgroundScheduler
import time
import argparse

# Конфигурация
config = {
    'backup_directories': ['/path/to/directory1', '/path/to/directory2'],
    'backup_destination': '/path/to/backup_destination',  # Укажите абсолютный путь
    'backup_method': 'incremental',  # варианты: 'incremental', 'differential', 'full'
    'schedule': {
        'interval': 'daily',  # варианты: 'daily', 'weekly', 'monthly' или число секунд
        'time': '02:00',  # время в формате 'HH:MM' для выполнения бэкапа
    },
    'log_file': 'backup.log',
}

# Настройка логирования
logging.basicConfig(filename=config['log_file'], level=logging.INFO,
                    format='%(asctime)s %(levelname)s %(message)s')

def get_last_backup():
    backup_dest = config['backup_destination']
    backups = [os.path.join(backup_dest, d) for d in os.listdir(backup_dest)
               if os.path.isdir(os.path.join(backup_dest, d)) and d.startswith('backup_')]
    backups.sort(reverse=True)
    if backups:
        return backups[0]
    else:
        return None

def get_last_full_backup():
    backup_dest = config['backup_destination']
    backups = [os.path.join(backup_dest, d) for d in os.listdir(backup_dest)
               if os.path.isdir(os.path.join(backup_dest, d)) and
               d.startswith('backup_') and '_full' in d]
    backups.sort(reverse=True)
    if backups:
        return backups[0]
    else:
        return None

def full_backup(backup_folder):
    for directory in config['backup_directories']:
        directory_name = os.path.basename(os.path.normpath(directory))
        dest = os.path.join(backup_folder, directory_name)
        shutil.copytree(directory, dest)
    logging.info(f"Полный бэкап выполнен в {backup_folder}")

def incremental_backup(backup_folder):
    last_backup = get_last_backup()
    if not last_backup:
        # Если предыдущих бэкапов нет, выполнить полный бэкап
        full_backup(backup_folder)
        return

    for directory in config['backup_directories']:
        directory_name = os.path.basename(os.path.normpath(directory))
        for root, dirs, files in os.walk(directory):
            for file in files:
                source_file = os.path.join(root, file)
                rel_path = os.path.relpath(source_file, directory)
                dest_file = os.path.join(backup_folder, directory_name, rel_path)

                last_backup_file = os.path.join(last_backup, directory_name, rel_path)
                if not os.path.exists(last_backup_file) or os.path.getmtime(source_file) > os.path.getmtime(last_backup_file):
                    os.makedirs(os.path.dirname(dest_file), exist_ok=True)
                    shutil.copy2(source_file, dest_file)
    logging.info(f"Инкрементальный бэкап выполнен в {backup_folder}")

def differential_backup(backup_folder):
    last_full_backup = get_last_full_backup()
    if not last_full_backup:
        # Если предыдущих полных бэкапов нет, выполнить полный бэкап
        full_backup(backup_folder)
        return

    for directory in config['backup_directories']:
        directory_name = os.path.basename(os.path.normpath(directory))
        for root, dirs, files in os.walk(directory):
            for file in files:
                source_file = os.path.join(root, file)
                rel_path = os.path.relpath(source_file, directory)
                dest_file = os.path.join(backup_folder, directory_name, rel_path)

                last_full_backup_file = os.path.join(last_full_backup, directory_name, rel_path)
                if not os.path.exists(last_full_backup_file) or os.path.getmtime(source_file) > os.path.getmtime(last_full_backup_file):
                    os.makedirs(os.path.dirname(dest_file), exist_ok=True)
                    shutil.copy2(source_file, dest_file)
    logging.info(f"Дифференциальный бэкап выполнен в {backup_folder}")

def perform_backup():
    try:
        backup_method = config['backup_method']
        backup_dest = config['backup_destination']
        timestamp = datetime.now().strftime('%Y%m%d%H%M%S')
        backup_folder_name = f'backup_{timestamp}_{backup_method}'
        backup_folder = os.path.join(backup_dest, backup_folder_name)

        os.makedirs(backup_folder, exist_ok=True)

        if backup_method == 'full':
            full_backup(backup_folder)
        elif backup_method == 'incremental':
            incremental_backup(backup_folder)
        elif backup_method == 'differential':
            differential_backup(backup_folder)
        else:
            # По умолчанию выполняем полный бэкап
            full_backup(backup_folder)

        logging.info(f'Успешно выполнен {backup_method} бэкап.')
    except Exception as e:
        logging.error(f'Ошибка во время выполнения бэкапа: {str(e)}')

def restore_backup():
    backup_dest = config['backup_destination']
    backups = [d for d in os.listdir(backup_dest)
               if os.path.isdir(os.path.join(backup_dest, d)) and d.startswith('backup_')]
    if not backups:
        print("Нет доступных бэкапов для восстановления.")
        return

    print("Доступные бэкапы:")
    for idx, backup in enumerate(backups, start=1):
        print(f"{idx}. {backup}")

    choice = int(input("Введите номер бэкапа для восстановления: "))
    if choice < 1 or choice > len(backups):
        print("Неверный выбор.")
        return

    backup_to_restore = os.path.join(backup_dest, backups[choice - 1])

    # Подтверждение восстановления
    confirm = input(f"Вы уверены, что хотите восстановить бэкап '{backups[choice - 1]}'? Это перезапишет текущие данные. (yes/no): ")
    if confirm.lower() != 'yes':
        print("Восстановление отменено.")
        return

    for directory in config['backup_directories']:
        directory_name = os.path.basename(os.path.normpath(directory))
        backup_directory = os.path.join(backup_to_restore, directory_name)

        if os.path.exists(backup_directory):
            # Удаляем текущую директорию
            if os.path.exists(directory):
                shutil.rmtree(directory)
            # Восстанавливаем из бэкапа
            shutil.copytree(backup_directory, directory)
            logging.info(f"Успешно восстановлена директория {directory} из бэкапа.")
        else:
            logging.warning(f"Бэкап не содержит директорию {directory_name}.")

def main():
    parser = argparse.ArgumentParser(description='Система Автоматического Бэкапа')
    parser.add_argument('--restore', action='store_true', help='Восстановить из бэкапа')
    parser.add_argument('--backup-now', action='store_true', help='Выполнить бэкап немедленно')
    args = parser.parse_args()

    if args.restore:
        restore_backup()
    elif args.backup_now:
        perform_backup()
    else:
        # Настройка планировщика
        scheduler = BackgroundScheduler()

        schedule_interval = config['schedule']['interval']
        schedule_time = config['schedule']['time']  # Формат 'HH:MM'

        hour, minute = map(int, schedule_time.split(':'))

        if schedule_interval == 'daily':
            scheduler.add_job(perform_backup, 'cron', hour=hour, minute=minute)
        elif schedule_interval == 'weekly':
            scheduler.add_job(perform_backup, 'cron', day_of_week='sun', hour=hour, minute=minute)
        elif schedule_interval == 'monthly':
            scheduler.add_job(perform_backup, 'cron', day=1, hour=hour, minute=minute)
        else:
            # Для пользовательских интервалов, например, каждые N секунд

            interval_seconds = int(schedule_interval)
            scheduler.add_job(perform_backup, 'interval', seconds=interval_seconds)

        scheduler.start()
        print("Система Автоматического Бэкапа запущена. Для остановки нажмите Ctrl+C.")
        try:
            while True:
                time.sleep(1)
        except (KeyboardInterrupt, SystemExit):
            scheduler.shutdown()
            print("Система остановлена.")

if __name__ == '__main__':
    main()
