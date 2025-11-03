import asyncssh
import asyncio
import bcrypt
import docker
import sys
import os
import uuid
from typing import Dict

# Constants
SSH_HOST_KEY = 'ssh_host_key'
SSH_PORT = 2222
DOCKER_IMAGE = 'ubuntu:20.04'
MEMORY_LIMIT = '512m'
CPU_QUOTA = 500000000
USERS_FILE = 'users.txt'
IO_TIMEOUT = 60  # Timeout in seconds for I/O operations

try:
    docker_client = docker.from_env()
except docker.errors.DockerException as e:
    print(f"Docker initialization error: {e}")
    sys.exit(1)

users_db: Dict[str, bytes] = {}

def load_users():
    if not os.path.exists(USERS_FILE):
        print(f"Users file '{USERS_FILE}' not found. Please create it using 'manage_users.py'.")
        sys.exit(1)
    
    print(f"Loading users from '{USERS_FILE}'...")
    with open(USERS_FILE, 'r') as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith('#'):
                continue
            try:
                username, hashed = line.split(':', 1)
                users_db[username] = hashed.encode()
                print(f"Loaded user: {username}")
            except ValueError:
                print(f"Invalid line in users file: {line}")
                continue
    print(f"Total users loaded: {len(users_db)}")

def verify_user(username: str, password: str) -> bool:
    if username in users_db:
        hashed = users_db[username]
        result = bcrypt.checkpw(password.encode(), hashed)
        return result
    return False

def create_container(username: str) -> docker.models.containers.Container:
    container_name = f'session_{username}_{uuid.uuid4()}'
    try:
        container = docker_client.containers.run(
            image=DOCKER_IMAGE,
            command="/bin/bash",
            tty=True,
            stdin_open=True,
            detach=True,
            name=container_name,
            mem_limit=MEMORY_LIMIT,
            nano_cpus=CPU_QUOTA,
            environment={
                "TERM": "xterm",
                "PATH": "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin",
                "SHELL": "/bin/bash"
            }
        )
        print(f"Created container '{container_name}' for user '{username}'.")
        return container
    except docker.errors.DockerException as e:
        print(f"Error creating container: {e}")
        return None

def cleanup_container(container: docker.models.containers.Container):
    try:
        print(f"Stopping container '{container.name}'.")
        container.kill()
    except docker.errors.DockerException as e:
        print(f"Error stopping container '{container.name}': {e}")
    
    try:
        print(f"Removing container '{container.name}'.")
        container.remove()
    except docker.errors.DockerException as e:
        print(f"Error removing container '{container.name}': {e}")

class SSHServerSession(asyncssh.SSHServerSession):
    def __init__(self, container: docker.models.containers.Container):
        super().__init__()
        self.container = container
        self.loop = asyncio.get_event_loop()
        self.transport_closed = False
        self._chan = None
        self.exec_sock = None
        self.exec_id = None
        self._stdout_task = None

    def connection_made(self, chan):
        """Called when the SSH connection is established"""
        try:
            self._chan = chan
            print(f"SSH session started for container '{self.container.name}'.")
            
            # Create interactive shell exec instance
            self.exec_id = self.container.client.api.exec_create(
                self.container.id,
                cmd=["/bin/bash"],
                tty=True,
                stdin=True,
                stdout=True,
                stderr=True,
                environment={
                    "TERM": "xterm",
                    "PATH": "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin",
                    "SHELL": "/bin/bash"
                }
            )
            
            print("Successfully created exec instance")
            
            # Start the interactive shell
            self.exec_sock = self.container.client.api.exec_start(
                self.exec_id['Id'],
                socket=True,
                tty=True
            )
            
            print("Successfully started exec instance")
            
            # Start background task for handling I/O
            self._stdout_task = asyncio.create_task(self._handle_output())
            print("Started output handling task")
            
        except Exception as e:
            print(f"Error in connection_made: {e}")
            if self.container:
                cleanup_container(self.container)
            if chan:
                chan.exit(1)

    async def _read_with_timeout(self, sock):
        """Read from socket with timeout"""
        try:
            data = await asyncio.wait_for(
                self.loop.run_in_executor(None, sock.recv, 4096),
                timeout=IO_TIMEOUT
            )
            return data
        except asyncio.TimeoutError:
            return None
        except Exception as e:
            print(f"Error reading from socket: {e}")
            return None

    def _write_to_channel(self, data):
        """Write data to SSH channel"""
        try:
            if isinstance(self._chan, (asyncssh.SSHServerChannel, asyncssh.editor.SSHLineEditorChannel)):
                self._chan.write(data)
            else:
                print(f"Warning: Unsupported channel type: {type(self._chan)}")
        except Exception as e:
            print(f"Error writing to channel: {e}")
            raise

    async def _handle_output(self):
        """Handle output from the container"""
        try:
            while not self.transport_closed and self.exec_sock and self._chan:
                try:
                    data = await self._read_with_timeout(self.exec_sock._sock)
                    if data is None:
                        # Timeout occurred, but connection is still active
                        continue
                    if not data:
                        print("No more data from container")
                        break
                    
                    # Write data to the channel
                    await self.loop.run_in_executor(None, self._write_to_channel, data)
                        
                except Exception as e:
                    print(f"Error processing container output: {e}")
                    break
        except Exception as e:
            print(f"Error in _handle_output: {e}")
        finally:
            if not self.transport_closed and self._chan:
                try:
                    self._chan.exit(0)
                except:
                    pass

    def data_received(self, data, datatype=None):
        """Handle data received from the SSH client"""
        if not self.transport_closed and self.exec_sock:
            try:
                # Ensure data is in bytes
                if isinstance(data, str):
                    data = data.encode()
                self.exec_sock._sock.send(data)
            except Exception as e:
                print(f"Error in data_received: {e}")

    def eof_received(self):
        """Called when EOF is received"""
        print("EOF received")
        if self.exec_sock:
            try:
                self.exec_sock._sock.shutdown(2)
            except Exception as e:
                print(f"Error in eof_received: {e}")
        return True

    def connection_lost(self, exc):
        """Called when the connection is lost"""
        print(f"Connection lost for container '{self.container.name}'" + (f": {exc}" if exc else ""))
        self.transport_closed = True
        
        if self.exec_sock:
            try:
                self.exec_sock._sock.close()
            except Exception as e:
                print(f"Error closing exec socket: {e}")

        if self._stdout_task and not self._stdout_task.done():
            self._stdout_task.cancel()
            try:
                self.loop.run_until_complete(self._stdout_task)
            except (asyncio.CancelledError, RuntimeError):
                pass
            
        cleanup_container(self.container)

    def shell_requested(self):
        """Called when a shell is requested"""
        print("Shell requested")
        return True

    def terminal_size_changed(self, width, height, pixwidth, pixheight):
        """Called when the terminal size changes"""
        if self.exec_sock and self.exec_id:
            try:
                self.container.client.api.exec_resize(
                    self.exec_id['Id'],
                    height=height,
                    width=width
                )
            except Exception as e:
                print(f"Error resizing terminal: {e}")

class SSHServer(asyncssh.SSHServer):
    def connection_made(self, conn):
        print(f"Connection received from {conn.get_extra_info('peername')}.")
        self.conn = conn
        self.username = None

    def connection_lost(self, exc):
        print(f"Connection closed{': ' + str(exc) if exc else ''}")

    def begin_auth(self, username):
        """Called when auth begins for a user"""
        print(f"Beginning authentication for user: {username}")
        self.username = username
        return True

    def password_auth_supported(self):
        return True

    def validate_password(self, username, password):
        return verify_user(username, password)

    def session_requested(self):
        """Called when a new session is requested"""
        if self.username:
            container = create_container(self.username)
            if container:
                return SSHServerSession(container)
            print(f"Failed to create container for user {self.username}")
        return None

async def start_server():
    """Start the SSH server."""
    if not os.path.exists(SSH_HOST_KEY):
        print(f"SSH host key '{SSH_HOST_KEY}' not found. Generate it using ssh-keygen.")
        sys.exit(1)

    server = await asyncssh.create_server(
        lambda: SSHServer(),
        '',
        SSH_PORT,
        server_host_keys=[SSH_HOST_KEY],
        process_factory=None,
        encoding=None
    )
    
    print(f"SSH server started on port {SSH_PORT}")
    
    try:
        await asyncio.get_event_loop().create_future()  # Run forever
    finally:
        server.close()
        await server.wait_closed()

def main():
    load_users()
    try:
        asyncio.get_event_loop().run_until_complete(start_server())
    except (OSError, asyncssh.Error) as exc:
        sys.exit(f"SSH server failed: {str(exc)}")
    except KeyboardInterrupt:
        print("\nShutting down server...")

if __name__ == '__main__':
    main()
