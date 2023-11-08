terraform {
  required_providers {
    yandex = {
      source = "yandex-cloud/yandex"
    }
  }
  required_version = ">= 0.13"
}

provider "yandex" {
  service_account_key_file = "./tf_key.json"
  folder_id                = local.folder_id
  zone                     = local.zone
}

data "yandex_vpc_network" "foo" {
  network_id = "enpk7rtkc5lgq4jqa1aq"
}

data "yandex_vpc_subnet" "foo" {
  subnet_id = "e9b6ngs1l5qei3dhsvch"
}

locals {
  zone      = "ru-central1-a"
  folder_id = "b1g2d4bl62dtukcmstmm"
  service-accounts = toset([
    "catgpt-sa",
  ])
  catgpt-sa-roles = toset([
    "container-registry.images.puller",
    "monitoring.editor",
  ])
}
resource "yandex_iam_service_account" "service-accounts" {
  for_each = local.service-accounts
  name     = each.key
}
resource "yandex_resourcemanager_folder_iam_member" "catgpt-roles" {
  for_each  = local.catgpt-sa-roles
  folder_id = local.folder_id
  member    = "serviceAccount:${yandex_iam_service_account.service-accounts["catgpt-sa"].id}"
  role      = each.key
}

data "yandex_compute_image" "coi" {
  family = "container-optimized-image"
}

resource "yandex_iam_service_account" "ig-sa" {
  name        = "ig-sa"
  description = "service account to manage IG"
}

resource "yandex_resourcemanager_folder_iam_binding" "editor" {
  folder_id = local.folder_id
  role      = "editor"
  members = [
    "serviceAccount:${yandex_iam_service_account.ig-sa.id}",
  ]
  depends_on = [
    yandex_iam_service_account.ig-sa,
  ]
}

resource "yandex_compute_instance_group" "catgpt" {
  depends_on = [yandex_resourcemanager_folder_iam_binding.editor]

  folder_id          = local.folder_id
  service_account_id = yandex_iam_service_account.ig-sa.id

  instance_template {
    platform_id        = "standard-v2"
    service_account_id = yandex_iam_service_account.service-accounts["catgpt-sa"].id

    resources {
      cores         = 2
      memory        = 1
      core_fraction = 5
    }
    scheduling_policy {
      preemptible = true
    }
    network_interface {
      network_id = data.yandex_vpc_network.foo.id
      subnet_ids = ["${data.yandex_vpc_subnet.foo.id}"]
      # nat        = true
    }
    boot_disk {
      initialize_params {
        type     = "network-hdd"
        size     = "30"
        image_id = data.yandex_compute_image.coi.id
      }
    }
    metadata = {
      docker-compose = templatefile("${path.module}/docker-compose.yaml", { folder_id = local.folder_id })
      ssh-keys       = "ubuntu:${file("~/.ssh/devops_training.pub")}"
      user-data      = "${templatefile("${path.module}/assets/cloud-init.yaml", { folder_id = local.folder_id })}"
    }
  }

  scale_policy {
    fixed_scale {
      size = 2
    }
  }

  allocation_policy {
    zones = [local.zone]
  }

  deploy_policy {
    max_unavailable = 1
    max_creating    = 1
    max_expansion   = 1
    max_deleting    = 1
  }

  application_load_balancer {
    target_group_name        = "target-group"
    target_group_description = "load balancer target group"
  }
}

resource "yandex_alb_backend_group" "catgpt-backend-group" {
  http_backend {
    name             = "catgpt-backend"
    weight           = 1
    port             = 8080
    target_group_ids = [yandex_compute_instance_group.catgpt.application_load_balancer[0].target_group_id]
    healthcheck {
      timeout             = "10s"
      interval            = "2s"
      healthy_threshold   = 10
      unhealthy_threshold = 15
      http_healthcheck {
        path = "/ping"
      }
    }
  }
}

resource "yandex_alb_http_router" "catgpt-router" {
  name = "catgpt-router"
}

resource "yandex_alb_virtual_host" "catgpt-virtual-host" {
  name           = "catgpt-virtual-host"
  http_router_id = yandex_alb_http_router.catgpt-router.id
  route {
    name = "catgpt-route"
    http_route {
      http_route_action {
        backend_group_id = yandex_alb_backend_group.catgpt-backend-group.id
        timeout          = "60s"
      }
    }
  }
}

resource "yandex_alb_load_balancer" "catgpt-balancer" {
  name       = "catgpt-balancer"
  network_id = data.yandex_vpc_network.foo.id

  allocation_policy {
    location {
      zone_id   = local.zone
      subnet_id = data.yandex_vpc_subnet.foo.id
    }
  }

  listener {
    name = "catgpt-listener"
    endpoint {
      address {
        external_ipv4_address {
        }
      }
      ports = [80]
    }
    http {
      handler {
        http_router_id = yandex_alb_http_router.catgpt-router.id
      }
    }
  }
}

# resource "yandex_compute_instance" "catgpt-1" {
#   platform_id        = "standard-v2"
#   service_account_id = yandex_iam_service_account.service-accounts["catgpt-sa"].id
#   resources {
#     cores         = 2
#     memory        = 1
#     core_fraction = 5
#   }
#   scheduling_policy {
#     preemptible = true
#   }
#   network_interface {
#     subnet_id = data.yandex_vpc_subnet.foo.id
#     nat       = true
#   }
#   boot_disk {
#     initialize_params {
#       type     = "network-hdd"
#       size     = "30"
#       image_id = data.yandex_compute_image.coi.id
#     }
#   }
#   metadata = {
#     serial-port-enable = 1
#     docker-compose     = file("${path.module}/docker-compose.yaml")
#     ssh-keys           = "ubuntu:${file("~/.ssh/devops_training.pub")}"
#   }
# }


