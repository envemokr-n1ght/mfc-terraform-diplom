#cloud-config

package_update: true
package_upgrade: false

packages: []

write_files:
  - path: /var/www/html/index.php
    content: |
      <?php
      $dbhost = '${master_db_ip}';
      $dbname = 'app_db';
      $dbuser = 'app_user';
      $dbpass = '${monitor_password}';
      
      try {
          $pdo = new PDO("pgsql:host=$dbhost;dbname=$dbname", $dbuser, $dbpass);
          $pdo->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
          
          if ($_SERVER['REQUEST_METHOD'] === 'POST') {
              $stmt = $pdo->prepare("INSERT INTO feedback (message, server_name) VALUES (?, ?)");
              $stmt->execute([$_POST['msg'], 'web-2']);
              echo "<h3>✅ Сохранено!</h3>";
          }
          
          $count = $pdo->query("SELECT COUNT(*) FROM feedback")->fetchColumn();
      } catch (PDOException $e) {
          echo "<h3>❌ Ошибка: " . htmlspecialchars($e->getMessage()) . "</h3>";
      }
      ?>
      <h1>MFC-PERM KRAI-2</h1>
      <p>Всего сообщений: <?= $count ?? 0 ?></p>
      <form method="post">
          <input name="msg" placeholder="Ваше сообщение">
          <button type="submit">Отправить</button>
      </form>
  - path: /etc/nginx/sites-available/web-site
    content: |
      server {
          listen 80;
          root /var/www/html;
          index index.php;
          location ~ \.php$ {
              include snippets/fastcgi-php.conf;
              fastcgi_pass unix:/var/run/php/php8.3-fpm.sock;
          }
      }

runcmd:
  # ----- 1. Настройка имени хоста и времени -----
  - hostnamectl set-hostname ${vm_name}
  - timedatectl set-timezone Asia/Yekaterinburg
  
  # ----- 2. Ожидание освобождения dpkg -----
  - |
    while fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1; do
      echo "Waiting for dpkg lock to be released..."
      sleep 5
    done
  
  # ----- 3. Добавление репозитория PostgreSQL -----
  - apt-get install -y curl ca-certificates
  - install -d /usr/share/postgresql-common/pgdg
  - curl -o /usr/share/postgresql-common/pgdg/apt.postgresql.org.asc --fail https://www.postgresql.org/media/keys/ACCC4CF8.asc
  - sh -c 'echo "deb [signed-by=/usr/share/postgresql-common/pgdg/apt.postgresql.org.asc] https://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list'
  - apt-get update

  # ----- 4. Установка Nginx и PHP с PostgreSQL поддержкой -----
  - apt-get install -y nginx php8.3-fpm php8.3-pgsql php8.3-pdo postgresql-client-17

  # ----- 5. Настройка Nginx для PHP -----
  - rm -f /etc/nginx/sites-enabled/default
  - ln -s /etc/nginx/sites-available/web-site /etc/nginx/sites-enabled/
  - systemctl enable nginx php8.3-fpm
  - systemctl restart nginx php8.3-fpm
  
  # ----- 6. Установка Zabbix Agent 2 -----
  - wget -q https://repo.zabbix.com/zabbix/7.0/ubuntu/pool/main/z/zabbix-release/zabbix-release_latest_7.0+ubuntu24.04_all.deb
  - dpkg -i zabbix-release_latest_7.0+ubuntu24.04_all.deb
  - apt-get update
  - apt-get install -y zabbix-agent2
  - sed -i "s/^Server=127.0.0.1/Server=${zabbix_server_ip}/" /etc/zabbix/zabbix_agent2.conf
  - sed -i "s/^ServerActive=127.0.0.1/ServerActive=${zabbix_server_ip}/" /etc/zabbix/zabbix_agent2.conf
  - sed -i "s/^Hostname=Zabbix server/Hostname=Web-2/" /etc/zabbix/zabbix_agent2.conf
  - systemctl restart zabbix-agent2
  - systemctl enable zabbix-agent2

final_message: "WEB-1 IS READY"
