#cloud-config

package_update: true
package_upgrade: false

packages:
  - wget
  - curl
  - net-tools
  - htop
  - mc

users:
  - name: ubuntu
    groups: sudo
    shell: /bin/bash
    sudo: ["ALL=(ALL) NOPASSWD:ALL"]
    ssh_authorized_keys:
      - ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDH+nKPMZt5LLAvFAfU0Qf3pLJfloX1UPzPT7pg9p/cuuvB2F42i5f6O7Xi0get6prEcvfmHqRcuVZjidTmCLhikwXPSXFRa+GtPDrVIrioiNQ7On6TEGF7KYBPfuEvvmAQ8pSodbPL0cLHXEvYJq2DuMOMpuzuU71aCvVRXyr7WvLDMB6CdekG23sZQxWZhdb4sAhpikwnTCez0E+lZ8ODl7IqR82wzOnrcxHoiCLt+te1E7eqr1HYc1BTItvNngYFjij+fd3uHNR2eg1ouQXbQQQejf9rO/Pq9/7YzG92sir0NtTajrV51DqpuIMX/wcjtHgIhCc9qdbNBAsINVzA8XiaUHNT6rpc0nM084NZqTK23k/J4n2MOF1MMwchN/cFISzkKsFLKcO1lSG08riGlIbE7TinHF0TKCLF8tIL9J4YcTM+5NaVRgFMhz+Cvmw7ed2p8WzGKEdHe64WCXhKDbPQGsU+XRlktssCN3xJIyKjrPAt9AHG7uKaSErqZA1Bksc/Whj8WDdjcrC8gEWVahQ0Y2rRCgoAyfMiRCR5X9CDKPi6ETj77cQ1O6LxbvE5sqGMuLD8h/jOcsl9R/CQ0al8/bAZWhx20F+FRorOIxiSvKeZnE3Qp1efu7kchVGi8MvjDgqu7ZLmvBfPGXPwsGB8VKOGRFnO3DpYGeFmUw== envem@DESKTOP-R4FCMIP

runcmd:
  # ----- 1. Настройка имени хоста и времени -----
  - hostnamectl set-hostname ${vm_name}
  - timedatectl set-timezone Asia/Yekaterinburg

  # ----- 2. Добавление репозитория Zabbix -----
  - wget -q https://repo.zabbix.com/zabbix/7.0/ubuntu/pool/main/z/zabbix-release/zabbix-release_latest_7.0+ubuntu24.04_all.deb
  - dpkg -i zabbix-release_latest_7.0+ubuntu24.04_all.deb
  - apt-get update

  # ----- 3. Установка Zabbix Agent 2 -----
  - DEBIAN_FRONTEND=noninteractive apt-get install -y zabbix-agent2

  # ----- 4. Настройка zabbix_agent2.conf -----
  - sed -i "s/^Server=127.0.0.1/Server=${zabbix_server_ip}/" /etc/zabbix/zabbix_agent2.conf
  - sed -i "s/^ServerActive=127.0.0.1/ServerActive=${zabbix_server_ip}/" /etc/zabbix/zabbix_agent2.conf
  - sed -i "s/^Hostname=Zabbix server/Hostname=${vm_name}/" /etc/zabbix/zabbix_agent2.conf

  # ----- 5. Удаляем конфликтующий Include (если есть) -----
  - sed -i '/plugins.d/d' /etc/zabbix/zabbix_agent2.conf

  # ----- 6. Добавляем пользовательские параметры для мониторинга SSH и сети -----
  - echo "UserParameter=ssh.sessions,who | wc -l" >> /etc/zabbix/zabbix_agent2.d/bastion.conf
  - echo "UserParameter=net.connections,ss -tun | wc -l" >> /etc/zabbix/zabbix_agent2.d/bastion.conf

  # ----- 7. Проверка конфигурации и запуск агента -----
  - /usr/sbin/zabbix_agent2 -T
  - systemctl restart zabbix-agent2
  - systemctl enable zabbix-agent2

final_message: "BASTION HOST IS READY"

