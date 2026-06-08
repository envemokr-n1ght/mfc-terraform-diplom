# ID облака
variable "cloud_id" {
  description = "Yandex Cloud ID"
  type        = string
  sensitive   = true
}

# ID каталога
variable "folder_id" {
  description = "Yandex Cloud Folder ID"
  type        = string
  sensitive   = true
}

# Параметры для ВМ
variable "vms" {
  description = "план конфигурации виртуальных машин"
  type = map(object({
    name               = string
    cores              = number
    memory             = number
    disk_size          = number
    image_family       = string
    subnet_id          = string
    assign_public_ip   = bool
    nat_ip_address     = optional(string)
    user_data_script   = optional(string)
    availability_zone  = string
    private_ip         = optional(string)
    security_group_ids = optional(list(string), [])
    serial_port_enable = optional(number, 0)
  }))
}

# Пароли для Zabbix и PostgreSQL (sensitive)
variable "zabbix_db_password" {
  type        = string
  sensitive   = true
  description = "Пароль для пользователя zabbix в PostgreSQL (на Zabbix Server)"
}

variable "replication_password" {
  type        = string
  sensitive   = true
  description = "Пароль для пользователя repl_user (репликация PostgreSQL)"
}

variable "monitor_password" {
  type        = string
  sensitive   = true
  description = "Пароль для пользователя zbx_monitor (мониторинг PostgreSQL)"
}
