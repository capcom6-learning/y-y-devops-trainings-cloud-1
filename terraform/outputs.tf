output "loadbalancer-ip" {
  value = yandex_alb_load_balancer.catgpt-balancer.listener[0].endpoint[0].address[0].external_ipv4_address[0].address
}
