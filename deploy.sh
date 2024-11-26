#!/bin/bash

APP_NAME=$1
USER=$2

sudo apt-get update
sudo apt-get install build-essential libffi-dev python3-dev
sudo apt-get install libpq-dev
sudo apt install python3-venv

sudo apt install redis-server

sudo apt install postgresql

sudo systemctl start postgresql

sudo systemctl enable postgresql


python3 -m venv ~/env

source ~/env/bin/activate

pip install -r ~/$APP_NAME/requirements.txt

pip install gunicorn


sudo apt-get install nginx

MAIN_NGINX_CONF="/etc/nginx/nginx.conf"

NGINX_CONF="/etc/nginx/sites-available/$APP_NAME.conf"

NGINX_SYMLINK="/etc/nginx/sites-enabled/$APP_NAME.conf"

RESTART_FILE="~/restart.sh"

SERVER_IP=$(curl -s http://checkip.amazonaws.com)

sudo sed -i "s/^user .*/user $USER;/" "$MAIN_NGINX_CONF"

cat <<EOL | sudo tee "$NGINX_CONF" > /dev/null
server {
    listen 80;
    server_name $SERVER_IP;
    location = /favicon.ico { access_log off; log_not_found off; }
    location /static/ {
        alias /home/$USER/${APP_NAME}/static_root/;
    }
    location /media/ {
        alias /home/$USER/${APP_NAME}/media/;
    }
    location / {
        include proxy_params;
        proxy_pass http://unix:/home/$USER/${APP_NAME}/app.sock;
        client_max_body_size 50M;
    }
}
EOL

echo "Nginx configuration file created at $NGINX_CONF"

sudo ln -s "$NGINX_CONF" "$NGINX_SYMLINK"

echo "Nginx symlink created at $NGINX_SYMLINK"

sudo nginx -t



sudo apt-get install supervisor

CELERY_CONF="/etc/supervisor/conf.d/celery.conf"

sudo mkdir /var/log/celery

cat <<EOL | sudo tee "$CELERY_CONF" > /dev/null
[program:celery]
command=/home/$USER/env/bin/celery -A ${APP_NAME} worker -l info
directory=/home/$USER/${APP_NAME}
user=${USER}
autostart=true
autorestart=true
stderr_logfile=/var/log/celery/celery.out.log
stdout_logfile=/var/log/celery/celery.err.log
EOL

echo "Supervisor configuration file created at $CELERY_CONF"



GUNICORN_CONF="/etc/supervisor/conf.d/gunicorn.conf"

sudo mkdir /var/log/gunicorn

cat <<EOL | sudo tee "$GUNICORN_CONF" > /dev/null
[program:gunicorn]
command=/home/$USER/env/bin/gunicorn --workers 3 --bind unix:/home/$USER/${APP_NAME}/app.sock ${APP_NAME}.wsgi:application
directory=/home/$USER/${APP_NAME}
user=${USER}
autostart=true
autorestart=true
stderr_logfile=/var/log/gunicorn/gunicorn.out.log
stdout_logfile=/var/log/gunicorn/gunicorn.err.log
EOL


echo "Supervisor configuration file created at $GUNICORN_CONF"

sudo supervisorctl reread
sudo supervisorctl update
sudo supervisorctl status

echo "Supervisor has been updated and the status of Celery has been checked."

echo "create restart file"

cat <<EOL | sudo tee "$RESTART_FILE" > /dev/null
#!/bin/bash

sudo systemctl restart nginx
sudo systemctl restart supervisor
EOL

chmod +x ~/restart.sh

