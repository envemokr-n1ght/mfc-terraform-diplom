#считываем данные об образе ОС
data "yandex_compute_image" "ubuntu_2404_lts" {
  family = "ubuntu-2404-lts"
}

locals {
  # Преобразование имён security групп в их ID
  security_group_map = {
    "LAN"          = yandex_vpc_security_group.LAN.id
    "bastion_sg"   = yandex_vpc_security_group.bastion_sg.id
    "zabbix_sg"    = yandex_vpc_security_group.zabbix_sg.id
    "db_server_sg" = yandex_vpc_security_group.db_server_sg.id
    "web_sg"       = yandex_vpc_security_group.web_sg.id
  }

  # Обработка user-data через templatefile
  user_data_map = {
    for key, vm in var.vms : key => (
      vm.user_data_script != null ? templatefile("${path.module}/${vm.user_data_script}", {
        # Все IP берём из статических переменных (не из ресурсов)
        zabbix_server_ip = var.vms["zabbix"].private_ip
        master_db_ip     = var.vms["db_primary"].private_ip
        slave_db_ip      = var.vms["db_secondary"].private_ip
        bastion_ip       = var.vms["bastion"].private_ip

        # Пароли
        zabbix_db_password   = var.zabbix_db_password
        replication_password = var.replication_password
        monitor_password     = var.monitor_password

        # Имя текущей ВМ
        vm_name = vm.name

        # Переменные для веб-серверов (используются только в web-1.tpl и web-2.tpl)
        server_number = key == "web_1" ? "1" : key == "web_2" ? "2" : "0"
        server_name   = key == "web_1" ? "web-1" : key == "web_2" ? "web-2" : vm.name
        header_text   = key == "web_1" ? "MFC-PERM KRAI-1" : key == "web_2" ? "MFC-PERM KRAI-2" : ""
      }) : null
    )
  }

  # Определение подсети по зоне доступности
  subnet_map = {
    "ru-central1-a" = yandex_vpc_subnet.fortress_a.id
    "ru-central1-b" = yandex_vpc_subnet.fortress_b.id
  }
}

# ============================================
# 1. СОЗДАЁМ ZABBIX-СЕРВЕР (ПЕРВЫМ)
# ============================================
resource "yandex_compute_instance" "zabbix" {
  for_each = {
    for k, v in var.vms : k => v
    if k == "zabbix"
  }

  name        = each.value.name
  platform_id = "standard-v3"
  zone        = each.value.availability_zone

  resources {
    cores  = each.value.cores
    memory = each.value.memory
  }

  boot_disk {
    initialize_params {
      image_id = data.yandex_compute_image.ubuntu_2404_lts.id
      size     = each.value.disk_size
    }
  }

  metadata = {
    user-data          = local.user_data_map[each.key]
    serial-port-enable = each.value.serial_port_enable
    ssh-keys           = "ubuntu:${file("~/.ssh/id_rsa.pub")}"
  }

  scheduling_policy {
    preemptible = false
  }

  network_interface {
    subnet_id      = local.subnet_map[each.value.availability_zone]
    nat            = each.value.assign_public_ip
    nat_ip_address = each.value.nat_ip_address
    ip_address     = each.value.private_ip
    security_group_ids = concat(
      [yandex_vpc_security_group.LAN.id],
      [for sg_name in each.value.security_group_ids : local.security_group_map[sg_name]]
    )
  }
}

# ============================================
# 2. DB-PRIMARY (ВТОРОЙ, ПОСЛЕ ZABBIX)
# ============================================
resource "yandex_compute_instance" "db_primary" {
  for_each = {
    for k, v in var.vms : k => v
    if k == "db_primary"
  }

  depends_on = [yandex_compute_instance.zabbix]

  name        = each.value.name
  platform_id = "standard-v3"
  zone        = each.value.availability_zone

  resources {
    cores  = each.value.cores
    memory = each.value.memory
  }

  boot_disk {
    initialize_params {
      image_id = data.yandex_compute_image.ubuntu_2404_lts.id
      size     = each.value.disk_size
    }
  }

  metadata = {
    user-data          = local.user_data_map[each.key]
    serial-port-enable = each.value.serial_port_enable
    ssh-keys           = "ubuntu:${file("~/.ssh/id_rsa.pub")}"
  }

  scheduling_policy {
    preemptible = false
  }

  network_interface {
    subnet_id          = local.subnet_map[each.value.availability_zone]
    nat                = each.value.assign_public_ip
    nat_ip_address     = each.value.nat_ip_address
    ip_address         = each.value.private_ip
    security_group_ids = concat(
      [yandex_vpc_security_group.LAN.id],
      [for sg_name in each.value.security_group_ids : local.security_group_map[sg_name]]
    )
  }
}

resource "time_sleep" "wait_for_master" {
  create_duration = "60s"
  depends_on      = [yandex_compute_instance.db_primary]
}

# ============================================
# 3. DB-SECONDARY (ТРЕТИЙ, ПОСЛЕ DB-PRIMARY)
# ============================================
resource "yandex_compute_instance" "db_secondary" {
  for_each = {
    for k, v in var.vms : k => v
    if k == "db_secondary"
  }

  depends_on = [time_sleep.wait_for_master]

  name        = each.value.name
  platform_id = "standard-v3"
  zone        = each.value.availability_zone

  resources {
    cores  = each.value.cores
    memory = each.value.memory
  }

  boot_disk {
    initialize_params {
      image_id = data.yandex_compute_image.ubuntu_2404_lts.id
      size     = each.value.disk_size
    }
  }

  metadata = {
    user-data          = local.user_data_map[each.key]
    serial-port-enable = each.value.serial_port_enable
    ssh-keys           = "ubuntu:${file("~/.ssh/id_rsa.pub")}"
  }

  scheduling_policy {
    preemptible = false
  }

  network_interface {
    subnet_id          = local.subnet_map[each.value.availability_zone]
    nat                = each.value.assign_public_ip
    nat_ip_address     = each.value.nat_ip_address
    ip_address         = each.value.private_ip
    security_group_ids = concat(
      [yandex_vpc_security_group.LAN.id],
      [for sg_name in each.value.security_group_ids : local.security_group_map[sg_name]]
    )
  }
}

# ============================================
# 4. ОСТАЛЬНЫЕ ВМ (БАСТИОН, WEB-1, WEB-2)
# ============================================
resource "yandex_compute_instance" "others" {
  for_each = {
    for k, v in var.vms : k => v
    if !contains(["zabbix", "db_primary", "db_secondary"], k)
  }

  depends_on = [yandex_compute_instance.db_secondary]

  name        = each.value.name
  platform_id = "standard-v3"
  zone        = each.value.availability_zone

  resources {
    cores  = each.value.cores
    memory = each.value.memory
  }

  boot_disk {
    initialize_params {
      image_id = data.yandex_compute_image.ubuntu_2404_lts.id
      size     = each.value.disk_size
    }
  }

  metadata = {
    user-data          = local.user_data_map[each.key]
    serial-port-enable = each.value.serial_port_enable
    ssh-keys           = "ubuntu:${file("~/.ssh/id_rsa.pub")}"
  }

  scheduling_policy {
    preemptible = false
  }

  network_interface {
    subnet_id          = local.subnet_map[each.value.availability_zone]
    nat                = each.value.assign_public_ip
    nat_ip_address     = each.value.nat_ip_address
    ip_address         = each.value.private_ip
    security_group_ids = concat(
      [yandex_vpc_security_group.LAN.id],
      [for sg_name in each.value.security_group_ids : local.security_group_map[sg_name]]
    )
  }
}

# ============================================
# SSH-КОНФИГ ДЛЯ ПОДКЛЮЧЕНИЯ
# ============================================
resource "local_file" "ssh_config" {
  depends_on = [yandex_compute_instance.others]
  
  content = templatefile("${path.module}/templates/ssh-config.tpl", {
    bastion_public_ip = yandex_compute_instance.others["bastion"].network_interface[0].nat_ip_address
  })
  filename = "./ssh-config"
}