#!/bin/bash

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Test user credentials
TEST_USER="testuser"
TEST_PASS="testpass"
SSH_PORT=2222

# Cleanup function
cleanup() {
    echo "Cleaning up..."
    # Kill virtual terminal process if running
    if [ -f ".vt.pid" ]; then
        kill $(cat .vt.pid) 2>/dev/null
        rm .vt.pid
    fi
    
    # Remove generated files
    rm -f ssh_host_key ssh_host_key.pub users.txt
    
    # Cleanup any remaining docker containers
    docker ps -a | grep "session_${TEST_USER}" | awk '{print $1}' | xargs -r docker rm -f
}

# Function to check if a command was successful
check_status() {
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}[✓] $1${NC}"
    else
        echo -e "${RED}[✗] $1${NC}"
        cleanup
        exit 1
    fi
}

# Set trap for cleanup on script exit
trap cleanup EXIT

echo "Starting virtual terminal system tests..."

# Generate SSH host keys
echo "Generating SSH host keys..."
ssh-keygen -t rsa -b 4096 -f ssh_host_key -N '' 2>/dev/null
check_status "SSH host key generation"

ssh-keygen -y -f ssh_host_key > ssh_host_key.pub 2>/dev/null
check_status "SSH public key generation"

# Create test user
echo "Creating test user..."
python3 manage_users.py $TEST_USER $TEST_PASS
check_status "Test user creation"

# Start virtual terminal in background
echo "Starting virtual terminal..."
python3 virtual_terminal.py & echo $! > .vt.pid
sleep 2 # Wait for server to start

# Test SSH connection
echo "Testing SSH connection..."
# Create expect script for automated SSH login
cat > test_ssh.exp << EOF
#!/usr/bin/expect -f
set timeout 10
spawn ssh -o PreferredAuthentications=password -o PubkeyAuthentication=no -o StrictHostKeyChecking=no -p $SSH_PORT $TEST_USER@localhost
expect "password:"
send "$TEST_PASS\r"
expect "~#"
send "echo 'TEST_SUCCESS'\r"
expect "TEST_SUCCESS"
send "exit\r"
expect eof
EOF

# Make expect script executable
chmod +x test_ssh.expect

# Run expect script
expect -f test_ssh.exp
check_status "SSH connection and authentication"

# Remove expect script
rm -f test_ssh.exp

# Test container creation
echo "Checking Docker container..."
CONTAINER_COUNT=$(docker ps | grep "session_${TEST_USER}" | wc -l)
if [ $CONTAINER_COUNT -eq 1 ]; then
    echo -e "${GREEN}[✓] Docker container created successfully${NC}"
else
    echo -e "${RED}[✗] Docker container creation failed${NC}"
    exit 1
fi

# Memory limit test
echo "Checking container resource limits..."
CONTAINER_ID=$(docker ps | grep "session_${TEST_USER}" | awk '{print $1}')
MEMORY_LIMIT=$(docker inspect $CONTAINER_ID | grep '"Memory":' | awk '{print $2}' | sed 's/,//')
if [ "$MEMORY_LIMIT" = "536870912" ]; then  # 512MB in bytes
    echo -e "${GREEN}[✓] Memory limit set correctly${NC}"
else
    echo -e "${RED}[✗] Memory limit incorrect${NC}"
fi

echo -e "\n${GREEN}All tests completed successfully!${NC}"
