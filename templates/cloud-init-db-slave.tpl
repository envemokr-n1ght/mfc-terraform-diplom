#cloud-config
package_update: true
package_upgrade: false
packages: []

runcmd:
  - hostnamectl set-hostname ${vm_name}
  - timedatectl set-timezone Asia/Yekaterinburg
  
  # ============================================
  # ДОБАВЛЕНИЕ РЕПОЗИТОРИЯ POSTGRESQL
  # ============================================
  - apt-get update
  - apt-get install -y wget curl ca-certificates netcat-openbsd
  - wget -q --no-check-certificate https://www.postgresql.org/media/keys/ACCC4CF8.asc -O- | sudo apt-key add -
  - echo "deb https://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list
  - apt-get update
  
  # ============================================
  # УСТАНОВКА ПАКЕТОВ
  # ============================================
  - apt-get install -y postgresql-17 postgresql-client-17
  
  # ============================================
  # ZABBIX AGENT 2
  # ============================================
  - wget -q https://repo.zabbix.com/zabbix/7.0/ubuntu/pool/main/z/zabbix-release/zabbix-release_latest_7.0+ubuntu24.04_all.deb
  - dpkg -i zabbix-release_latest_7.0+ubuntu24.04_all.deb
  - apt-get update
  - apt-get install -y zabbix-agent2
  - sed -i "s/^Server=127.0.0.1/Server=${zabbix_server_ip}/" /etc/zabbix/zabbix_agent2.conf
  - sed -i "s/^ServerActive=127.0.0.1/ServerActive=${zabbix_server_ip}/" /etc/zabbix/zabbix_agent2.conf
  - sed -i "s/^Hostname=Zabbix server/Hostname=db-secondary/" /etc/zabbix/zabbix_agent2.conf
  - systemctl restart zabbix-agent2
  - systemctl enable zabbix-agent2
  
  # ============================================
  # POSTGRESQL REPLICA
  # ============================================
  
  # Остановка и очистка
  - systemctl stop postgresql || true
  - rm -rf /var/lib/postgresql/17/main
  - mkdir -p /var/lib/postgresql/17/main
  - chown postgres:postgres /var/lib/postgresql/17/main
  - chmod 700 /var/lib/postgresql/17/main

  # Ожидание мастера
  - |
    echo "Waiting for master PostgreSQL on ${master_db_ip}:5432..."
    for i in $(seq 1 60); do
      if PGPASSWORD='repl_pass_123' psql -h ${master_db_ip} -p 5432 -U repl_user -d postgres -c "SELECT 1" >/dev/null 2>&1; then
        echo "Master is ready!"
        break
      fi
      echo "Attempt $i/60: Master not ready, sleeping 10 seconds..."
      sleep 10
    done

  # Копирование данных с мастером (через .pgpass)
  - echo "${master_db_ip}:5432:*:repl_user:repl_pass_123" > /tmp/.pgpass
  - chmod 600 /tmp/.pgpass
  - sudo -u postgres pg_basebackup -h ${master_db_ip} -p 5432 -U repl_user -D /var/lib/postgresql/17/main -Fp -Xs -P -R --no-password
  - rm -f /tmp/.pgpass

  # Настройка primary_conninfo с application_name
  - |
    echo "primary_conninfo = 'host=${master_db_ip} port=5432 user=repl_user password=${replication_password} application_name=db_secondary'" > /var/lib/postgresql/17/main/postgresql.auto.conf
  
  # Включение режима реплики
  - touch /var/lib/postgresql/17/main/standby.signal
  - chown -R postgres:postgres /var/lib/postgresql/17/main
  - chmod 700 /var/lib/postgresql/17/main

  # Настройка postgresql.conf
  - sed -i "s/^#listen_addresses =.*/listen_addresses = 'localhost'/" /etc/postgresql/17/main/postgresql.conf
  - sed -i "s/^#hot_standby =.*/hot_standby = on/" /etc/postgresql/17/main/postgresql.conf

  # Запуск PostgreSQL
  - systemctl start postgresql
  - systemctl enable postgresql

final_message: "POSTGRESQL SLAVE IS READY"