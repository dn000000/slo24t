import bcrypt
import sys
import os

USERS_FILE = 'users.txt'

def load_users():
    """
    Load existing users from the USERS_FILE.
    Returns a dictionary of username: hashed_password.
    """
    users = {}
    if os.path.exists(USERS_FILE):
        with open(USERS_FILE, 'r') as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith('#'):
                    continue
                try:
                    username, hashed = line.split(':', 1)
                    users[username] = hashed
                except ValueError:
                    print(f"Invalid line in users file: {line}")
                    continue
    return users

def add_user(username: str, password: str):
    """
    Add a new user with the given username and password.
    """
    users = load_users()
    if username in users:
        print(f"Error: User '{username}' already exists.")
        sys.exit(1)
    
    # Hash the password
    hashed = bcrypt.hashpw(password.encode(), bcrypt.gensalt())
    
    # Append the new user to the USERS_FILE
    with open(USERS_FILE, 'a') as f:
        f.write(f"{username}:{hashed.decode()}\n")
    
    print(f"User '{username}' added successfully.")

def main():
    if len(sys.argv) != 3:
        print(f"Usage: {sys.argv[0]} <username> <password>")
        sys.exit(1)
    
    username = sys.argv[1]
    password = sys.argv[2]
    add_user(username, password)

if __name__ == '__main__':
    main()