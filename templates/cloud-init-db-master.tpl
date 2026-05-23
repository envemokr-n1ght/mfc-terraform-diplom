#cloud-config
package_update: true
package_upgrade: false
packages:
  - curl
  - ca-certificates
  - wget

runcmd:
  - hostnamectl set-hostname ${vm_name}
  - timedatectl set-timezone Asia/Yekaterinburg
  
  # Добавление репозитория PostgreSQL 17
  - apt install -y curl ca-certificates
  - install -d /usr/share/postgresql-common/pgdg
  - curl -o /usr/share/postgresql-common/pgdg/apt.postgresql.org.asc --fail https://www.postgresql.org/media/keys/ACCC4CF8.asc
  - sh -c 'echo "deb [signed-by=/usr/share/postgresql-common/pgdg/apt.postgresql.org.asc] https://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list'
  - apt-get update
  - apt-get install -y postgresql-17 postgresql-client-17
  - systemctl enable postgresql
  - systemctl start postgresql
  
  # Создание пользователей
  - sudo -u postgres psql -c "CREATE USER repl_user WITH REPLICATION ENCRYPTED PASSWORD '${replication_password}';"
  - sudo -u postgres psql -c "CREATE USER zbx_monitor WITH PASSWORD '${monitor_password}';"
  - sudo -u postgres psql -c "GRANT pg_monitor TO zbx_monitor;"

  # Создание пользователя и БД для веб-приложения
  - sudo -u postgres psql -c "CREATE USER app_user WITH PASSWORD '${monitor_password}';"
  - sudo -u postgres psql -c "CREATE DATABASE app_db OWNER app_user;"
  - sudo -u postgres psql -d app_db -c "GRANT ALL PRIVILEGES ON SCHEMA public TO app_user;"
  - sudo -u postgres psql -d app_db -c "ALTER SCHEMA public OWNER TO app_user;"
  
  # Создание таблицы feedback
  - sudo -u postgres psql -d app_db -c "CREATE TABLE IF NOT EXISTS feedback (
        id SERIAL PRIMARY KEY,
        message TEXT NOT NULL,
        server_name VARCHAR(50),
        created_at TIMESTAMP DEFAULT NOW()
    );"
  - sudo -u postgres psql -d app_db -c "GRANT ALL PRIVILEGES ON TABLE feedback TO app_user;"
  - sudo -u postgres psql -d app_db -c "GRANT ALL PRIVILEGES ON SEQUENCE feedback_id_seq TO app_user;"
  
  # Настройка postgresql.conf
  - sed -i "s/^#listen_addresses =.*/listen_addresses = '*'/" /etc/postgresql/17/main/postgresql.conf
  - sed -i "s/^#wal_level =.*/wal_level = replica/" /etc/postgresql/17/main/postgresql.conf
  - sed -i "s/^#max_wal_senders =.*/max_wal_senders = 10/" /etc/postgresql/17/main/postgresql.conf
  - sed -i "s/^#wal_keep_size =.*/wal_keep_size = 512MB/" /etc/postgresql/17/main/postgresql.conf
  - sed -i "s/^#hot_standby =.*/hot_standby = on/" /etc/postgresql/17/main/postgresql.conf

  # НАСТРОЙКИ СИНХРОННОЙ РЕПЛИКАЦИИ
  - echo "synchronous_commit = on" >> /etc/postgresql/17/main/postgresql.conf
  - echo "synchronous_standby_names = 'db_secondary'" >> /etc/postgresql/17/main/postgresql.conf
  
  # Настройка pg_hba.conf
  - echo "host    replication     repl_user       ${slave_db_ip}/32            trust" >> /etc/postgresql/17/main/pg_hba.conf
  - echo "host    postgres        repl_user       ${slave_db_ip}/32            trust" >> /etc/postgresql/17/main/pg_hba.conf
  - echo "host    all             zbx_monitor     127.0.0.1/32            md5" >> /etc/postgresql/17/main/pg_hba.conf
  - echo "host    all             app_user        10.0.1.0/24              md5" >> /etc/postgresql/17/main/pg_hba.conf
  - echo "host    all             app_user        10.0.2.0/24              md5" >> /etc/postgresql/17/main/pg_hba.conf
  
  # Перезапуск PostgreSQL
  - systemctl reload postgresql
  
  # Установка Zabbix Agent 2
  - wget -q https://repo.zabbix.com/zabbix/7.0/ubuntu/pool/main/z/zabbix-release/zabbix-release_latest_7.0+ubuntu24.04_all.deb
  - dpkg -i zabbix-release_latest_7.0+ubuntu24.04_all.deb
  - apt-get update
  - apt-get install -y zabbix-agent2 zabbix-agent2-plugin-postgresql
  
  # Настройка zabbix_agent2.conf
  - sed -i "s/^Server=127.0.0.1/Server=${zabbix_server_ip}/" /etc/zabbix/zabbix_agent2.conf
  - sed -i "s/^ServerActive=127.0.0.1/ServerActive=${zabbix_server_ip}/" /etc/zabbix/zabbix_agent2.conf
  - sed -i "s/^Hostname=Zabbix server/Hostname=PostgreSQL-Master/" /etc/zabbix/zabbix_agent2.conf
  - sed -i 's/^Include=\/etc\/zabbix\/zabbix_agent2.d\/plugins.d\/\*.conf/#Include=\/etc\/zabbix\/zabbix_agent2.d\/plugins.d\/\*.conf/' /etc/zabbix/zabbix_agent2.conf
  
  # Настройка плагина PostgreSQL
  - rm -f /etc/zabbix/zabbix_agent2.d/postgresql.conf
  - echo "Plugins.PostgreSQL.Uri=tcp://127.0.0.1:5432" >> /etc/zabbix/zabbix_agent2.d/postgresql.conf
  - echo "Plugins.PostgreSQL.User=zbx_monitor" >> /etc/zabbix/zabbix_agent2.d/postgresql.conf
  - echo "Plugins.PostgreSQL.Password=${monitor_password}" >> /etc/zabbix/zabbix_agent2.d/postgresql.conf
  - echo "Plugins.PostgreSQL.Database=postgres" >> /etc/zabbix/zabbix_agent2.d/postgresql.conf
  
  # Запуск агента
  - /usr/sbin/zabbix_agent2 -T
  - systemctl restart zabbix-agent2
  - systemctl enable zabbix-agent2

  - systemctl restart postgresql

final_message: "POSTGRESQL MASTER IS READY"