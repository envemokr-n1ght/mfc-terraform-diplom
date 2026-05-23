output "all_vm_ips" {
  value = merge(
    # Zabbix-сервер
    { for key, vm in yandex_compute_instance.zabbix : key => {
        public_ip  = vm.network_interface[0].nat_ip_address
        private_ip = vm.network_interface[0].ip_address
      }
    },
    # db-primary
    { for key, vm in yandex_compute_instance.db_primary : key => {
        public_ip  = vm.network_interface[0].nat_ip_address
        private_ip = vm.network_interface[0].ip_address
      }
    },
    # db-secondary
    { for key, vm in yandex_compute_instance.db_secondary : key => {
        public_ip  = vm.network_interface[0].nat_ip_address
        private_ip = vm.network_interface[0].ip_address
      }
    },
    # Остальные ВМ (bastion, web-1, web-2)
    { for key, vm in yandex_compute_instance.others : key => {
        public_ip  = vm.network_interface[0].nat_ip_address
        private_ip = vm.network_interface[0].ip_address
      }
    }
  )
  description = "Публичные и внутренние IP-адреса всех ВМ"
}

output "nlb_public_balancer" {
  value       = one(one(yandex_lb_network_load_balancer.web-nlb.listener).external_address_spec).address
  description = "Публичный IP-адрес Network Loader Balancer"  
}

output "ssh_connection_command" {
  value       = "ssh -J ubuntu@${yandex_compute_instance.others["bastion"].network_interface[0].nat_ip_address} ubuntu@<private_ip>"
  description = "Команда для подключения к ВМ с помощью bastion"
}
