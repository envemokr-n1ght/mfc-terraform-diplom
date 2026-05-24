#Создаем облачную сеть
resource "yandex_vpc_network" "fortress" {
  name = "fortress-network"
}

#Создаем подсеть zone A
resource "yandex_vpc_subnet" "fortress_a" {
  name           = "fortress-a"
  zone           = "ru-central1-a"
  network_id     = yandex_vpc_network.fortress.id
  v4_cidr_blocks = ["10.0.1.0/24"]
  route_table_id = yandex_vpc_route_table.rt.id
}

#Создаем подсеть zone B
resource "yandex_vpc_subnet" "fortress_b" {
  name           = "fortress-b"
  zone           = "ru-central1-b"
  network_id     = yandex_vpc_network.fortress.id
  v4_cidr_blocks = ["10.0.2.0/24"]
  route_table_id = yandex_vpc_route_table.rt.id
}

#Создаем NAT для выхода в интернет
resource "yandex_vpc_gateway" "nat_gateway" {
  name = "fortress-gateway"
  shared_egress_gateway {}
}

#Создаем сетевой маршрут для выхода в интернет через NAT
resource "yandex_vpc_route_table" "rt" {
  name       = "fortress-route-table"
  network_id = yandex_vpc_network.fortress.id

  static_route {
    destination_prefix = "0.0.0.0/0"
    gateway_id         = yandex_vpc_gateway.nat_gateway.id
  }
}

#Создаем группы безопасности (firewall)
resource "yandex_vpc_security_group" "bastion_sg" {
  name        = "bastion-sg"
  description = "Группа безопасности для bastion-хоста"
  network_id  = yandex_vpc_network.fortress.id

  ingress {
    description    = "Allow 0.0.0.0/0 на 22 порт"
    protocol       = "TCP"
    v4_cidr_blocks = ["0.0.0.0/0"]
    port           = 22
  }

  egress {
    description    = "Permit ALL"
    protocol       = "ANY"
    v4_cidr_blocks = ["0.0.0.0/0"]
    from_port      = 0
    to_port        = 65535
  }
}

resource "yandex_vpc_security_group" "LAN" {
  name        = "LAN-sg"
  description = "Группа безопасности для всех локальных ВМ"
  network_id  = yandex_vpc_network.fortress.id

  ingress {
    description    = "Allow 10.0.0.0/8"
    protocol       = "ANY"
    v4_cidr_blocks = ["10.0.0.0/8"]
    from_port      = 0
    to_port        = 65535
  }

  egress {
    description    = "Permit ANY"
    protocol       = "ANY"
    v4_cidr_blocks = ["0.0.0.0/0"]
    from_port      = 0
    to_port        = 65535
  }
}

resource "yandex_vpc_security_group" "web_sg" {
  name        = "web-sg"
  description = "Группа безопасности для web-сайтов"
  network_id  = yandex_vpc_network.fortress.id

  ingress {
    description    = "Allow HTTPS"
    protocol       = "TCP"
    port           = 443
    v4_cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description    = "Allow HTTP"
    protocol       = "TCP"
    port           = 80
    v4_cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description    = "Allow SSH from bastion"
    protocol       = "TCP"
    v4_cidr_blocks = ["10.0.1.5/32"]
    port           = 22
  } 

  egress {
    description    = "Allow web servers to connect to PostgreSQL database"
    protocol       = "TCP"
    v4_cidr_blocks = ["10.0.1.15/32"]  # IP-адрес db-primary
    port           = 5432
  }

  egress {
    description    = "Allow Zabbix агенту подключаться к Zabbix серверу"
    protocol       = "TCP"
    v4_cidr_blocks = ["10.0.1.10/32"] # IP Zabbix-сервера
    port           = 10051
  }

  egress {
    description    = "Limited outgoing for updates"
    protocol       = "TCP"
    v4_cidr_blocks = ["0.0.0.0/0"]
    port           = 443  # Только HTTPS для обновлений
  }

  egress {
    description    = "DNS for updates"
    protocol       = "UDP"
    v4_cidr_blocks = ["0.0.0.0/0"]
    port           = 53
  }
}

resource "yandex_vpc_security_group" "zabbix_sg" {
  name        = "zabbix-sg"
  description = "Группа безопасности для zabbix-сервера"
  network_id  = yandex_vpc_network.fortress.id

  ingress {
    description    = "Allow HTTP"
    protocol       = "TCP"
    port           = 80
    v4_cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description    = "Allow SSH from bastion"
    protocol       = "TCP"
    v4_cidr_blocks = ["10.0.1.5/32"]
    port           = 22
  } 

  ingress {
    description = "Allow Zabbix agents to send data"
    protocol    = "TCP"
    v4_cidr_blocks = [
      "10.0.1.0/24",
      "10.0.2.0/24"
    ]
    port = 10051
  }

  egress {
    description    = "Outgoing for updates and notifications"
    protocol       = "TCP"
    v4_cidr_blocks = ["0.0.0.0/0"]
    port           = 443
  }

  egress {
    description    = "DNS"
    protocol       = "UDP"
    v4_cidr_blocks = ["0.0.0.0/0"]
    port           = 53
  }
}

resource "yandex_vpc_security_group" "db_server_sg" {
  name        = "db-server-sg"
  description = "Группа безопасности для базы данных"
  network_id  = yandex_vpc_network.fortress.id

  ingress {
    description       = "Allow database access from the web-server"
    protocol          = "TCP"
    v4_cidr_blocks    = [] # Оставить пустым
    security_group_id = yandex_vpc_security_group.web_sg.id
    port              = 5432
  }

  ingress {
    description    = "Replication from secondary DB"
    protocol       = "TCP"
    v4_cidr_blocks = ["10.0.2.15/32"]
    port           = 5432
  }

  ingress {
    description    = "Allow SSH from bastion"
    protocol       = "TCP"
    v4_cidr_blocks = ["10.0.1.5/32"]
    port           = 22
  } 

  egress {
    description    = "Allow Zabbix agent to connent to Zabbix server"
    protocol       = "TCP"
    v4_cidr_blocks = ["10.0.1.10/32"] # IP Zabbix-сервера
    port           = 10051
  }

  #Ограничение доступа в интернет (кроме репозиториев)
  egress {
    description    = "Limited outgoing for updates"
    protocol       = "TCP"
    v4_cidr_blocks = ["0.0.0.0/0"]
    port           = 443 # HTTPS для apt/yum репозиториев
  }

  egress {
    description    = "DNS for updates"
    protocol       = "UDP"
    v4_cidr_blocks = ["0.0.0.0/0"]
    port           = 53
  }
}
