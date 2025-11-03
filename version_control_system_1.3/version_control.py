#!/usr/bin/env python3
# version_control.py

import argparse
import difflib
import os
import sqlite3
import sys
import time
import threading
from watchdog.observers import Observer
from watchdog.events import FileSystemEventHandler

class ConfigEventHandler(FileSystemEventHandler):
    """
    Обработчик событий файловой системы для отслеживания изменений в конфигурационных файлах.
    """

    def __init__(self, config_dir, db_path):
        super().__init__()
        self.config_dir = config_dir
        self.db_path = db_path
        # Создаём локальное подключение к БД для потока обработчика
        self.local = threading.local()

    def get_db(self):
        """
        Получает соединение с БД для текущего потока
        """
        if not hasattr(self.local, 'conn'):
            self.local.conn = sqlite3.connect(self.db_path)
            self.local.cursor = self.local.conn.cursor()
        return self.local.conn, self.local.cursor

    def on_created(self, event):
        if not event.is_directory:
            self.handle_event('created', event.src_path)

    def on_modified(self, event):
        if not event.is_directory:
            self.handle_event('modified', event.src_path)

    def on_deleted(self, event):
        if not event.is_directory:
            self.handle_event('deleted', event.src_path)

    def handle_event(self, event_type, file_path):
        """
        Обрабатывает событие изменения файла: создаёт запись в базе данных.
        """
        conn, cursor = self.get_db()
        rel_path = os.path.relpath(file_path, self.config_dir)
        timestamp = time.strftime("%Y-%m-%d %H:%M:%S", time.localtime())
        author = os.getenv('USER') or os.getenv('USERNAME') or 'unknown'
        description = f'File {event_type}'

        version_number = self.get_next_version(cursor, rel_path)

        if event_type == 'deleted':
            file_content = None
        else:
            try:
                with open(file_path, 'rb') as f:
                    file_content = f.read()
            except Exception as e:
                print(f'Ошибка при чтении файла {file_path}: {e}')
                file_content = None

        cursor.execute('''
            INSERT INTO versions (file_path, version_number, timestamp, author, description, file_content)
            VALUES (?, ?, ?, ?, ?, ?)
        ''', (rel_path, version_number, timestamp, author, description, file_content))
        conn.commit()
        print(f'Версия {version_number} сохранена для {rel_path}')

    def get_next_version(self, cursor, file_path):
        """
        Получает следующий номер версии для указанного файла.
        """
        cursor.execute('''
            SELECT MAX(version_number) FROM versions WHERE file_path=?
        ''', (file_path,))

        result = cursor.fetchone()
        return (result[0] or 0) + 1


class VersionControl:
    """
    Класс, реализующий систему контроля версий для конфигурационных файлов.
    """

    def __init__(self, config_dir, db_path):
        self.config_dir = os.path.abspath(config_dir)
        self.db_path = os.path.abspath(db_path)
        self.init_db()

    def init_db(self):
        """
        Инициализирует базу данных SQLite для хранения версий файлов.
        """
        with sqlite3.connect(self.db_path) as conn:
            cursor = conn.cursor()
            cursor.execute('''
                CREATE TABLE IF NOT EXISTS versions (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    file_path TEXT,
                    version_number INTEGER,
                    timestamp TEXT,
                    author TEXT,
                    description TEXT,
                    file_content BLOB
                )
            ''')
            conn.commit()

    def compare_versions(self, file_path, version1, version2):
        """
        Сравнивает содержимое двух версий файла и возвращает разницу.
        """
        with sqlite3.connect(self.db_path) as conn:
            cursor = conn.cursor()
            rel_path = os.path.relpath(file_path, self.config_dir)

            cursor.execute('''
                SELECT file_content FROM versions 
                WHERE file_path=? AND version_number=?
            ''', (rel_path, version1))
            result1 = cursor.fetchone()
            if not result1 or not result1[0]:
                print(f'Нет содержимого для {rel_path} версии {version1}')
                return

            cursor.execute('''
                SELECT file_content FROM versions 
                WHERE file_path=? AND version_number=?
            ''', (rel_path, version2))
            result2 = cursor.fetchone()
            if not result2 or not result2[0]:
                print(f'Нет содержимого для {rel_path} версии {version2}')
                return

            content1 = result1[0].decode('utf-8', errors='replace').splitlines()
            content2 = result2[0].decode('utf-8', errors='replace').splitlines()

            diff = difflib.unified_diff(
                content1,
                content2,
                fromfile=f'Version {version1}',
                tofile=f'Version {version2}',
                lineterm=''
            )
            return '\n'.join(diff)

    def rollback(self, file_path, version_number):
        """
        Откатывает файл к указанной версии.
        """
        with sqlite3.connect(self.db_path) as conn:
            cursor = conn.cursor()
            rel_path = os.path.relpath(file_path, self.config_dir)

            cursor.execute('''
                SELECT file_content FROM versions 
                WHERE file_path=? AND version_number=?
            ''', (rel_path, version_number))
            result = cursor.fetchone()
            if result and result[0]:
                abs_file_path = os.path.join(self.config_dir, rel_path)
                os.makedirs(os.path.dirname(abs_file_path), exist_ok=True)
                with open(abs_file_path, 'wb') as f:
                    f.write(result[0])
                print(f'Файл {rel_path} откатан к версии {version_number}')
            else:
                print(f'Нет содержимого для {rel_path} версии {version_number}')

    def show_history(self, file_path):
        """
        Выводит историю изменений для указанного файла.
        """
        with sqlite3.connect(self.db_path) as conn:
            cursor = conn.cursor()
            rel_path = os.path.relpath(file_path, self.config_dir)
            cursor.execute('''
                SELECT version_number, timestamp, author, description 
                FROM versions 
                WHERE file_path=?
                ORDER BY version_number
            ''', (rel_path,))
            history = cursor.fetchall()
            if history:
                print(f'История изменений для {rel_path}:')
                for record in history:
                    print(f'  Версия: {record[0]}, Время: {record[1]}, Автор: {record[2]}, Описание: {record[3]}')
            else:
                print(f'Нет истории изменений для {rel_path}')

    def start_monitoring(self):
        """
        Запускает мониторинг директории конфигурационных файлов.
        """
        event_handler = ConfigEventHandler(self.config_dir, self.db_path)
        observer = Observer()
        observer.schedule(event_handler, self.config_dir, recursive=True)
        observer.start()
        print(f'Запущен мониторинг директории: {self.config_dir}')
        print('Нажмите Ctrl+C для остановки.')
        try:
            while True:
                time.sleep(1)
        except KeyboardInterrupt:
            observer.stop()
            print('\nМониторинг остановлен.')
        observer.join()


def main():
    parser = argparse.ArgumentParser(
        description='Система Контроля Версий для Конфигурационных Файлов'
    )
    subparsers = parser.add_subparsers(dest='command', required=True, help='Доступные команды')

    # Команда monitor
    monitor_parser = subparsers.add_parser('monitor', help='Запустить мониторинг изменений')
    monitor_parser.add_argument(
        '--config_dir',
        default='./configs',
        help='Директория с конфигурационными файлами (по умолчанию ./configs)'
    )
    monitor_parser.add_argument(
        '--db_path',
        default='./versions.db',
        help='Путь к базе данных SQLite (по умолчанию ./versions.db)'
    )

    # Команда compare
    compare_parser = subparsers.add_parser('compare', help='Сравнить две версии файла')
    compare_parser.add_argument('--file', required=True, help='Путь к файлу для сравнения')
    compare_parser.add_argument('--version1', type=int, required=True, help='Первая версия для сравнения')
    compare_parser.add_argument('--version2', type=int, required=True, help='Вторая версия для сравнения')
    compare_parser.add_argument(
        '--config_dir',
        default='./configs',
        help='Директория с конфигурационными файлами (по умолчанию ./configs)'
    )
    compare_parser.add_argument(
        '--db_path',
        default='./versions.db',
        help='Путь к базе данных SQLite (по умолчанию ./versions.db)'
    )

    # Команда rollback
    rollback_parser = subparsers.add_parser('rollback', help='Откатить файл к указанной версии')
    rollback_parser.add_argument('--file', required=True, help='Путь к файлу для отката')
    rollback_parser.add_argument('--rollback_version', type=int, required=True, help='Версия для отката')
    rollback_parser.add_argument(
        '--config_dir',
        default='./configs',
        help='Директория с конфигурационными файлами (по умолчанию ./configs)'
    )
    rollback_parser.add_argument(
        '--db_path',
        default='./versions.db',
        help='Путь к базе данных SQLite (по умолчанию ./versions.db)'
    )

    # Команда history
    history_parser = subparsers.add_parser('history', help='Показать историю изменений файла')
    history_parser.add_argument('--file', required=True, help='Путь к файлу для просмотра истории')
    history_parser.add_argument(
        '--config_dir',
        default='./configs',
        help='Директория с конфигурационными файлами (по умолчанию ./configs)'
    )
    history_parser.add_argument(
        '--db_path',
        default='./versions.db',
        help='Путь к базе данных SQLite (по умолчанию ./versions.db)'
    )

    args = parser.parse_args()

    if args.command == 'monitor':
        vc = VersionControl(args.config_dir, args.db_path)
        try:
            vc.start_monitoring()
        except KeyboardInterrupt:
            print('\nМониторинг остановлен.')

    elif args.command == 'compare':
        vc = VersionControl(args.config_dir, args.db_path)
        diff = vc.compare_versions(args.file, args.version1, args.version2)
        if diff:
            print(diff)

    elif args.command == 'rollback':
        vc = VersionControl(args.config_dir, args.db_path)
        vc.rollback(args.file, args.rollback_version)

    elif args.command == 'history':
        vc = VersionControl(args.config_dir, args.db_path)
        vc.show_history(args.file)

    else:
        parser.print_help()


if __name__ == "__main__":
    main()
