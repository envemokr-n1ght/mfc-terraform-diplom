# Отказоустойчивая облачная инфраструктура для МФЦ на базе Yandex Cloud

## Описание проекта

Данный проект представляет собой реализацию отказоустойчивой и защищённой облачной инфраструктуры для информационной системы МФЦ на платформе Yandex Cloud. Инфраструктура полностью описана как код (Infrastructure as Code) с использованием Terraform.

## Архитектура

- **2 зоны доступности:** `ru-central1-a`, `ru-central1-b`
- **Виртуальные машины:** 6 ВМ (Bastion, Zabbix, web-1, web-2, db-primary, db-secondary)
- **Балансировщик нагрузки:** NLB (L4) с динамическим публичным IP
- **База данных:** PostgreSQL 17, синхронная репликация
- **Мониторинг:** Zabbix 7.0
- **Автоматическая настройка ВМ:** cloud-init
- **ОС:** Ubuntu 24.04

## Структура репозитория
```
.
├── main.tf # Основной файл Terraform (ВМ, локальные переменные)
├── network.tf # Сеть, подсети, security groups, NAT
├── nlb.tf # Network Load Balancer
├── providers.tf # Провайдеры и аутентификация
├── variables.tf # Объявление переменных
├── outputs.tf # Выходные данные (IP-адреса)
├── terraform.tfvars.example # Пример файла с переменными (скопировать в .tfvars)
├── .gitignore # Исключаемые файлы
├── README.md # Этот файл
└── templates/
  ├── cloud-init-bastion.tpl # Cloud-init для Bastion
  ├── cloud-init-zabbix.tpl # Cloud-init для Zabbix
  ├── cloud-init-web-1.tpl # Cloud-init для web-1
  ├── cloud-init-web-2.tpl # Cloud-init для web-2
  ├── cloud-init-db-master.tpl # Cloud-init для мастер-БД
  ├── cloud-init-db-slave.tpl # Cloud-init для реплики БД
  └── ssh-config.tpl # Шаблон SSH-конфигурации для подключения через Bastion
```

## Требования для развёртывания

- Terraform >= 1.5.0
- Yandex Cloud CLI (опционально)
- Аккаунт в Yandex Cloud
- Сервисный аккаунт с ключом (`.authorized_key.json`)
- SSH-ключ для доступа к ВМ (`~/.ssh/id_rsa`)

## Настройка и развёртывание

### 1. Клонирование репозитория

  git clone https://github.com/envemokr-n1ght/mfc-terraform-diplom.git
  cd mfc-terraform-diplom

### 2. Настройка переменных

  cp terraform.tfvars.example terraform.tfvars

Отредактируйте terraform.tfvars, указав:
- cloud_id и folder_id из вашего облака Yandex Cloud
- Пароли для баз данных и мониторинга (zabbix_db_password, replication_password, monitor_password)

### 3. Настройка ключей

- Поместите ключ сервисного аккаунта в папку проекта с именем .authorized_key.json
- Убедитесь, что SSH-ключ существует в ~/.ssh/id_rsa (или измените путь в коде)

### 4. Инициализация и запуск

  terraform init
  terraform plan
  terraform apply

После успешного применения будут выведены IP-адреса всех ресурсов.

### Подключение к ресурсам

- Через Bastion-хост
# Получить публичный IP Bastion
  terraform output bastion_public_ip

# Подключиться к любой внутренней ВМ
  ssh -J ubuntu@<bastion_ip> ubuntu@<private_ip>

- К веб-сайту
# Получить IP балансировщика
  terraform output nlb_public_ip

# Открыть в браузере: http://<nlb_ip>

- К Zabbix
# Получить публичный IP Zabbix
terraform output zabbix_public_ip

# Открыть в браузере: http://<zabbix_ip>/zabbix
# Логин: Admin, пароль: zabbix (или заданный в переменных)

### Тестирование отказоустойчивости

- Веб-уровень
# Остановить один из веб-серверов
  ssh -J ubuntu@<bastion_ip> ubuntu@10.0.1.20
  sudo systemctl stop nginx

# Проверить, что сайт продолжает работать через балансировщик
  curl http://<nlb_ip>

- База данных
# Проверить режим реплики
  ssh -J ubuntu@<bastion_ip> ubuntu@10.0.2.15
  sudo -u postgres psql -c "SELECT pg_is_in_recovery();"  # Должно быть 't'

# Проверить синхронную репликацию на мастере
  sudo -u postgres psql -c "SELECT application_name, sync_state FROM pg_stat_replication;"

### Проверка записи в базе данных
# Подключиться к мастер-БД
  ssh -J ubuntu@<bastion_ip> ubuntu@10.0.1.15

# Посмотреть последние 5 сообщений
  sudo -u postgres psql -d app_db -c "SELECT id, message, server_name, created_at FROM feedback ORDER BY id DESC LIMIT 5;"

### Очистка таблицы с сообщениями
# Подключиться к мастер-БД
ssh -J ubuntu@<bastion_ip> ubuntu@10.0.1.15

# Удалить все записи из таблицы feedback
sudo -u postgres psql -d app_db -c "TRUNCATE TABLE feedback;"

# Проверить, что таблица пуста
sudo -u postgres psql -d app_db -c "SELECT COUNT(*) FROM feedback;"

### Очистка ресурсов
  terraform destroy

  
