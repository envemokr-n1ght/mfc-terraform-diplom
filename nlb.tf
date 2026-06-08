# Создание целевой группы балансировщика
resource "yandex_lb_target_group" "web-tg" {
    name = "target-group"
    
    target {
        subnet_id = yandex_vpc_subnet.fortress_a.id
        address   = yandex_compute_instance.others["web_1"].network_interface[0].ip_address
    }

    target {
        subnet_id = yandex_vpc_subnet.fortress_b.id
        address   = yandex_compute_instance.others["web_2"].network_interface[0].ip_address
    }
}

# Создание балансировщика
resource "yandex_lb_network_load_balancer" "web-nlb" {
    name = "network-load-balancer"

    listener {
      name = "http-listener"
      port = 80
      external_address_spec {
        ip_version = "ipv4"
      }
    }

    # Проверка жизни целевой группы
    attached_target_group {
      target_group_id = yandex_lb_target_group.web-tg.id

      healthcheck {
        name = "http-check"
        http_options {
          port = 80
          path = "/"
        }
      }
    }
}
