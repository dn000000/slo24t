#define FUSE_USE_VERSION 31

#include <fuse3/fuse.h>
#include <stdio.h>
#include <string.h>
#include <errno.h>
#include <fcntl.h>
#include <stddef.h>
#include <stdlib.h>
#include <pthread.h>
#include <sys/types.h>
#include <time.h>
#include <unistd.h>    // Для getuid() и getgid()
#include <libgen.h>    // Для dirname() и basename()

typedef struct vfs_node {
    char *name;
    mode_t mode;
    uid_t uid;
    gid_t gid;
    size_t size;
    time_t atime;
    time_t mtime;
    time_t ctime;
    struct vfs_node *parent;
    struct vfs_node **children; // Для каталогов
    size_t children_count;
    size_t children_capacity;
    char *data; // Для файлов
} vfs_node_t;

// Корневой узел
vfs_node_t *root;

// Мьютекс для защиты общей структуры данных
pthread_mutex_t vfs_lock = PTHREAD_MUTEX_INITIALIZER;

vfs_node_t* create_node(const char *name, mode_t mode, vfs_node_t *parent) {
    vfs_node_t *node = malloc(sizeof(vfs_node_t));
    if (!node) return NULL;

    node->name = strdup(name);
    node->mode = mode;
    node->uid = getuid();
    node->gid = getgid();
    node->size = 0;
    time(&node->atime);
    time(&node->mtime);
    time(&node->ctime);
    node->parent = parent;
    node->children = NULL;
    node->children_count = 0;
    node->children_capacity = 0;
    node->data = NULL;

    return node;
}

void free_node(vfs_node_t *node) {
    if (node->children) {
        for (size_t i = 0; i < node->children_count; i++) {
            free_node(node->children[i]);
        }
        free(node->children);
    }
    if (node->data) {
        free(node->data);
    }
    free(node->name);
    free(node);
}

vfs_node_t* find_node(const char *path) {
    if (strcmp(path, "/") == 0) {
        return root;
    }

    char *path_dup = strdup(path);
    if (!path_dup) return NULL;

    char *token = strtok(path_dup, "/");
    vfs_node_t *current = root;

    while (token != NULL && current != NULL) {
        int found = 0;
        for (size_t i = 0; i < current->children_count; i++) {
            if (strcmp(current->children[i]->name, token) == 0) {
                current = current->children[i];
                found = 1;
                break;
            }
        }
        if (!found) {
            current = NULL;
            break;
        }
        token = strtok(NULL, "/");
    }

    free(path_dup);
    return current;
}

int add_child(vfs_node_t *parent, vfs_node_t *child) {
    if (!parent->children) {
        parent->children_capacity = 4;
        parent->children = malloc(parent->children_capacity * sizeof(vfs_node_t*));
        if (!parent->children) return -ENOMEM;
    }

    if (parent->children_count == parent->children_capacity) {
        parent->children_capacity *= 2;
        vfs_node_t **temp = realloc(parent->children, parent->children_capacity * sizeof(vfs_node_t*));
        if (!temp) return -ENOMEM;
        parent->children = temp;
    }

    parent->children[parent->children_count++] = child;
    parent->mtime = parent->ctime = time(NULL);
    return 0;
}

int remove_child(vfs_node_t *parent, const char *name) {
    size_t index = parent->children_count;
    for (size_t i = 0; i < parent->children_count; i++) {
        if (strcmp(parent->children[i]->name, name) == 0) {
            index = i;
            break;
        }
    }

    if (index == parent->children_count) return -ENOENT;

    free_node(parent->children[index]);

    for (size_t i = index; i < parent->children_count - 1; i++) {
        parent->children[i] = parent->children[i+1];
    }
    parent->children_count--;
    parent->mtime = parent->ctime = time(NULL);
    return 0;
}

static void *vfs_init_fs(struct fuse_conn_info *conn, struct fuse_config *cfg) {
    (void) conn;
    cfg->kernel_cache = 0;

    pthread_mutex_lock(&vfs_lock);
    root = create_node("/", S_IFDIR | 0755, NULL);
    pthread_mutex_unlock(&vfs_lock);

    return NULL;
}

static void vfs_destroy_fs(void *private_data) {
    (void) private_data;

    pthread_mutex_lock(&vfs_lock);
    free_node(root);
    root = NULL;
    pthread_mutex_unlock(&vfs_lock);
}

static int vfs_getattr(const char *path, struct stat *stbuf, struct fuse_file_info *fi){
    (void) fi;
    int res = 0;

    memset(stbuf, 0, sizeof(struct stat));

    pthread_mutex_lock(&vfs_lock);
    vfs_node_t *node = find_node(path);
    if (!node) {
        res = -ENOENT;
    } else {
        stbuf->st_mode = node->mode;
        stbuf->st_nlink = (node->mode & S_IFDIR) ? 2 : 1;
        stbuf->st_uid = node->uid;
        stbuf->st_gid = node->gid;
        stbuf->st_size = node->size;
        stbuf->st_atime = node->atime;
        stbuf->st_mtime = node->mtime;
        stbuf->st_ctime = node->ctime;
    }
    pthread_mutex_unlock(&vfs_lock);

    return res;
}

static int vfs_readdir(const char *path, void *buf, fuse_fill_dir_t filler,
                       off_t offset, struct fuse_file_info *fi,
                       enum fuse_readdir_flags flags){
    (void) offset;
    (void) fi;
    (void) flags;

    pthread_mutex_lock(&vfs_lock);
    vfs_node_t *node = find_node(path);
    if (!node) {
        pthread_mutex_unlock(&vfs_lock);
        return -ENOENT;
    }

    if (!(node->mode & S_IFDIR)) {
        pthread_mutex_unlock(&vfs_lock);
        return -ENOTDIR;
    }

    filler(buf, ".", NULL, 0, 0);
    filler(buf, "..", NULL, 0, 0);

    for (size_t i = 0; i < node->children_count; i++) {
        filler(buf, node->children[i]->name, NULL, 0, 0);
    }

    pthread_mutex_unlock(&vfs_lock);
    return 0;
}

static int vfs_create_file(const char *path, mode_t mode, struct fuse_file_info *fi){
    (void) fi;
    char *path_dup = strdup(path);
    if (!path_dup) return -ENOMEM;

    char *dir_path = dirname(path_dup);
    char *file_name = basename((char*)path);

    pthread_mutex_lock(&vfs_lock);
    vfs_node_t *parent = find_node(dir_path);
    if (!parent) {
        pthread_mutex_unlock(&vfs_lock);
        free(path_dup);
        return -ENOENT;
    }

    if (!(parent->mode & S_IFDIR)) {
        pthread_mutex_unlock(&vfs_lock);
        free(path_dup);
        return -ENOTDIR;
    }

    // Проверка наличия файла с таким именем
    for (size_t i = 0; i < parent->children_count; i++) {
        if (strcmp(parent->children[i]->name, file_name) == 0) {
            pthread_mutex_unlock(&vfs_lock);
            free(path_dup);
            return -EEXIST;
        }
    }

    vfs_node_t *new_file = create_node(file_name, S_IFREG | 0644, parent);
    if (!new_file) {
        pthread_mutex_unlock(&vfs_lock);
        free(path_dup);
        return -ENOMEM;
    }

    int res = add_child(parent, new_file);
    pthread_mutex_unlock(&vfs_lock);
    free(path_dup);

    return res;
}

static int vfs_make_dir(const char *path, mode_t mode){
    pthread_mutex_lock(&vfs_lock);

    char *path_dup = strdup(path);
    if (!path_dup) {
        pthread_mutex_unlock(&vfs_lock);
        return -ENOMEM;
    }

    char *dir_path = dirname(path_dup);
    char *dir_name = basename((char*)path);

    vfs_node_t *parent = find_node(dir_path);
    if (!parent) {

        pthread_mutex_unlock(&vfs_lock);
        free(path_dup);
        return -ENOENT;
    }

    if (!(parent->mode & S_IFDIR)) {
        pthread_mutex_unlock(&vfs_lock);
        free(path_dup);
        return -ENOTDIR;
    }

    // Проверка наличия каталога с таким именем
    for (size_t i = 0; i < parent->children_count; i++) {
        if (strcmp(parent->children[i]->name, dir_name) == 0) {
            pthread_mutex_unlock(&vfs_lock);
            free(path_dup);
            return -EEXIST;
        }
    }

    vfs_node_t *new_dir = create_node(dir_name, S_IFDIR | mode, parent);
    if (!new_dir) {
        pthread_mutex_unlock(&vfs_lock);
        free(path_dup);
        return -ENOMEM;
    }

    int res = add_child(parent, new_dir);
    pthread_mutex_unlock(&vfs_lock);
    free(path_dup);

    return res;
}

// Исправленная версия функции удаления узла
static int vfs_unlink_node(const char *path) {
    if (strcmp(path, "/") == 0) return -EBUSY;

    pthread_mutex_lock(&vfs_lock);
    vfs_node_t *node = find_node(path);
    if (!node) {
        pthread_mutex_unlock(&vfs_lock);
        return -ENOENT;
    }

    // Проверяем, является ли узел директорией
    if (node->mode & S_IFDIR) {
        // Для директорий проверяем, пуста ли она
        if (node->children_count > 0) {
            pthread_mutex_unlock(&vfs_lock);
            return -ENOTEMPTY;
        }
    }

    vfs_node_t *parent = node->parent;
    if (!parent) {
        pthread_mutex_unlock(&vfs_lock);
        return -EINVAL;
    }

    int res = remove_child(parent, node->name);
    pthread_mutex_unlock(&vfs_lock);

    return res;
}

static int vfs_read_file(const char *path, char *buf, size_t size, off_t offset,
                         struct fuse_file_info *fi){
    (void) fi;

    pthread_mutex_lock(&vfs_lock);
    vfs_node_t *node = find_node(path);
    if (!node) {
        pthread_mutex_unlock(&vfs_lock);
        return -ENOENT;
    }

    if (!(node->mode & S_IFREG)) {
        pthread_mutex_unlock(&vfs_lock);
        return -EISDIR;
    }

    if (offset < node->size) {
        if (offset + size > node->size)
            size = node->size - offset;
        memcpy(buf, node->data + offset, size);
    } else {
        size = 0;
    }

    node->atime = time(NULL);
    pthread_mutex_unlock(&vfs_lock);
    return size;
}

// Исправленная версия функции записи файла
static int vfs_write_file(const char *path, const char *buf, size_t size,
                          off_t offset, struct fuse_file_info *fi) {
    (void) fi;

    pthread_mutex_lock(&vfs_lock);
    vfs_node_t *node = find_node(path);
    if (!node) {
        pthread_mutex_unlock(&vfs_lock);
        return -ENOENT;
    }

    if (!(node->mode & S_IFREG)) {
        pthread_mutex_unlock(&vfs_lock);
        return -EISDIR;
    }

    // Вычисляем необходимый размер файла
    size_t new_size = offset + size;
    
    // Выделяем новую память или переиспользуем существующую
    if (new_size > node->size) {
        char *new_data = realloc(node->data, new_size);
        if (!new_data) {
            pthread_mutex_unlock(&vfs_lock);
            return -ENOMEM;
        }
        // Заполняем нулями новое пространство
        if (node->size < new_size) {
            memset(new_data + node->size, 0, new_size - node->size);
        }
        node->data = new_data;
    }
    
    // Копируем данные
    memcpy(node->data + offset, buf, size);
    
    // Обновляем размер файла только если новые данные выходят за текущие границы
    if (new_size > node->size) {
        node->size = new_size;
    }

    node->mtime = node->ctime = time(NULL);
    pthread_mutex_unlock(&vfs_lock);
    return size;
}

// Обновленная функция rmdir
static int vfs_rmdir(const char *path) {
    pthread_mutex_lock(&vfs_lock);
    vfs_node_t *node = find_node(path);
    
    if (!node) {
        pthread_mutex_unlock(&vfs_lock);
        return -ENOENT;
    }

    // Проверяем, является ли узел директорией
    if (!(node->mode & S_IFDIR)) {
        pthread_mutex_unlock(&vfs_lock);
        return -ENOTDIR;
    }

    // Проверяем, пуста ли директория
    if (node->children_count > 0) {
        pthread_mutex_unlock(&vfs_lock);
        return -ENOTEMPTY;
    }

    vfs_node_t *parent = node->parent;
    if (!parent) {
        pthread_mutex_unlock(&vfs_lock);
        return -EINVAL;
    }

    int res = remove_child(parent, node->name);
    pthread_mutex_unlock(&vfs_lock);
    return res;
}

static int vfs_unlink(const char *path) {
    return vfs_unlink_node(path);
}

static struct fuse_operations vfs_oper = {
    .init       = vfs_init_fs,
    .destroy    = vfs_destroy_fs,
    .getattr    = vfs_getattr,
    .readdir    = vfs_readdir,
    .mkdir      = vfs_make_dir,
    .rmdir      = vfs_rmdir,
    .unlink     = vfs_unlink,
    .create     = vfs_create_file,
    .read       = vfs_read_file,
    .write      = vfs_write_file,
};

int main(int argc, char *argv[]) {
    // Проверка аргументов
    if (argc < 2) {
        fprintf(stderr, "Usage: %s <mountpoint>\n", argv[0]);
        return 1;
    }

    // Запуск FUSE
    return fuse_main(argc, argv, &vfs_oper, NULL);
}
