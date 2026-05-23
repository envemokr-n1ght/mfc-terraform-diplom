#cloud-config
package_update: true
package_upgrade: false
packages:
    - postgresql
    - postgresql-contrib
    - wget
    - perl

runcmd:
    - hostnamectl set-hostname ${vm_name}
    - timedatectl set-timezone Asia/Yekaterinburg
  
    - sudo -u postgres psql -c "CREATE USER zabbix WITH PASSWORD '${zabbix_db_password}';"
    - sudo -u postgres psql -c "CREATE DATABASE zabbix OWNER zabbix;"
  
    - wget -q https://repo.zabbix.com/zabbix/7.0/ubuntu/pool/main/z/zabbix-release/zabbix-release_latest_7.0+ubuntu24.04_all.deb
    - dpkg -i zabbix-release_latest_7.0+ubuntu24.04_all.deb
    - apt-get update
  
    - apt-get install -y zabbix-server-pgsql zabbix-frontend-php php8.3-pgsql zabbix-nginx-conf zabbix-sql-scripts zabbix-agent2
  
    - zcat /usr/share/zabbix-sql-scripts/postgresql/server.sql.gz | sudo -u zabbix psql zabbix
  
    - sed -i 's/^# DBHost=localhost/DBHost=localhost/' /etc/zabbix/zabbix_server.conf
    - sed -i 's/^# DBName=zabbix/DBName=zabbix/' /etc/zabbix/zabbix_server.conf
    - sed -i 's/^# DBUser=zabbix/DBUser=zabbix/' /etc/zabbix/zabbix_server.conf
    - sed -i 's/^# DBPassword=/DBPassword=${zabbix_db_password}/' /etc/zabbix/zabbix_server.conf
  
    - chown root:root /etc/zabbix/nginx.conf
    - chmod 644 /etc/zabbix/nginx.conf
    - perl -pi -e 's/^#\s*listen\s*8080;/    listen 80;/' /etc/zabbix/nginx.conf
    - perl -pi -e 's/^#\s*server_name\s*example.com;/    server_name _;/' /etc/zabbix/nginx.conf  # ← _ означает "любой IP"

    # Удаляем стандартный сайт Nginx
    - rm -f /etc/nginx/sites-enabled/default
  
    # Создаём символическую ссылку для конфига Zabbix
    - ln -sf /etc/zabbix/nginx.conf /etc/nginx/conf.d/zabbix.conf

    # Создаём символическую ссылку для правильного пути сокета
    - ln -sf /var/run/php/php8.3-fpm.sock /var/run/php/zabbix.sock
  
    # Убеждаемся, что сокет доступен для Nginx
    - chown www-data:www-data /var/run/php/php8.3-fpm.sock
    - chmod 660 /var/run/php/php8.3-fpm.sock
  
    # Перезапуск служб в правильном порядке
    - systemctl restart php8.3-fpm
    - sleep 2
    - systemctl restart nginx
    - systemctl restart zabbix-server zabbix-agent2
  
    # Включение автозапуска
    - systemctl enable zabbix-server zabbix-agent2 nginx php8.3-fpm
  
    # Настройка локали
    - sed -i 's/^# ru_RU.UTF-8 UTF-8/ru_RU.UTF-8 UTF-8/' /etc/locale.gen
    - locale-gen
    - systemctl restart nginx php8.3-fpm

final_message: |
    ZABBIX SERVER IS READY
    Логин: Admin, Пароль: zabbix