#!/bin/bash
set -euo pipefail

LOGFILE="deploy_$(date +%Y%m%d_%H%M%S).log"
exec > >(tee -a "$LOGFILE") 2>&1

echo "===== DEPLOYMENT STARTED AT $(date) ====="

# USER INPUTS
read -p "Enter Git repository URL: " REPO_URL
read -s -p "Enter your Personal Access Token (PAT): " PAT
echo
read -p "Enter branch name (press Enter for 'main'): " BRANCH
BRANCH=${BRANCH:-main}

read -p "Enter remote server username: " REMOTE_USER
read -p "Enter remote server IP: " REMOTE_IP
read -p "Enter SSH key path: " SSH_KEY
read -p "Enter application internal port (e.g. 8000, press Enter to auto-detect): " APP_PORT
if [ -z "$APP_PORT" ]; then
  if grep -qi '^EXPOSE ' Dockerfile; then
    APP_PORT=$(grep -i '^EXPOSE ' Dockerfile | awk '{print $2}' | head -n1)
    echo "Detected EXPOSED port from Dockerfile: $APP_PORT"
  else
    echo "No EXPOSE directive found — defaulting to port 80"
    APP_PORT=80
  fi
fi

# AUTHENTICATE + CLONE / PULL
REPO_NAME=$(basename -s .git "$REPO_URL")
if [ -d "$REPO_NAME" ]; then
  echo "Repository exists, pulling latest changes..."
  cd "$REPO_NAME"
  git pull origin "$BRANCH"
else
  echo "Cloning repository..."
  AUTH_URL=$(echo "$REPO_URL" | sed "s#https://#https://${PAT}@#")

  git clone -b "$BRANCH" "$AUTH_URL"
  cd "$REPO_NAME"
fi

# VALIDATE PROJECT FILES
if [ ! -f "Dockerfile" ] && [ ! -f "docker-compose.yml" ]; then
  echo "Error: No Dockerfile or docker-compose.yml found in repo!"
  exit 1
fi

# TEST SSH CONNECTION
echo "Testing SSH connectivity..."
if ssh -i "$SSH_KEY" -o StrictHostKeyChecking=accept-new -o ConnectTimeout=5 "$REMOTE_USER@$REMOTE_IP" "exit" 2>/dev/null; then
  echo "SSH connection successful."
else
  echo "SSH connection failed!"
  exit 1
fi

# PREPARE REMOTE ENVIRONMENT
echo "Preparing remote environment..."
ssh -i "$SSH_KEY" "$REMOTE_USER@$REMOTE_IP" bash <<EOF
  set -e
  sudo apt-get update -y
  sudo apt-get install -y docker.io docker-compose nginx
  sudo systemctl enable --now docker nginx
  sudo usermod -aG docker $REMOTE_USER || true
EOF

# DEPLOY APP VIA DOCKER
echo "Transferring project to remote host..."

ssh -i "$SSH_KEY" "$REMOTE_USER@$REMOTE_IP" "sudo chown -R $REMOTE_USER:$REMOTE_USER /home/$REMOTE_USER"

rsync -avz -e "ssh -i $SSH_KEY" --exclude '.git' "$PWD/" "$REMOTE_USER@$REMOTE_IP:/home/$REMOTE_USER/$REPO_NAME/"


ssh -i "$SSH_KEY" "$REMOTE_USER@$REMOTE_IP" bash <<EOF
  cd /home/$REMOTE_USER/$REPO_NAME
  sudo docker build -t ${REPO_NAME,,}-app .
  sudo docker rm -f ${REPO_NAME,,}-app 2>/dev/null || true
  sudo docker run -d --name ${REPO_NAME,,}-app -p ${APP_PORT}:80 ${REPO_NAME,,}-app

EOF

# CONFIGURE NGINX REVERSE PROXY
echo "Configuring Nginx reverse proxy..."
ssh -i "$SSH_KEY" "$REMOTE_USER@$REMOTE_IP" bash -s <<EOF
  set -e

  REPO_NAME_LOWER=\$(echo "$REPO_NAME" | tr '[:upper:]' '[:lower:]')
  APP_PORT="$APP_PORT"

  echo "Cleaning old Nginx configs..."
  sudo rm -f /etc/nginx/sites-enabled/\${REPO_NAME_LOWER}.conf
  sudo rm -f /etc/nginx/sites-enabled/default || true

  echo "Creating new Nginx config for \${REPO_NAME_LOWER}..."
  sudo bash -c "cat > /etc/nginx/sites-available/\${REPO_NAME_LOWER}.conf" <<'NGINXCONF'
server {
    listen 80 default_server;
    server_name _;
    location / {
        proxy_pass http://127.0.0.1:APP_PORT;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }
}
NGINXCONF

  sudo sed -i "s/APP_PORT/\${APP_PORT}/g" /etc/nginx/sites-available/\${REPO_NAME_LOWER}.conf
  sudo ln -sf /etc/nginx/sites-available/\${REPO_NAME_LOWER}.conf /etc/nginx/sites-enabled/
  sudo nginx -t && sudo systemctl reload nginx
EOF

# VALIDATE DEPLOYMENT
echo "Validating deployment..."
ssh -i "$SSH_KEY" "$REMOTE_USER@$REMOTE_IP" bash <<EOF
  sudo docker ps --filter "name=${REPO_NAME,,}-app"
  curl -I http://127.0.0.1
EOF

echo "===== DEPLOYMENT COMPLETED SUCCESSFULLY ====="
