# ============================================================================
# Application Gateway
# ============================================================================
# Reverse proxy providing public HTTPS endpoint for internal Container Apps.
# Routes traffic from internet to Container Apps via internal FQDN resolution
# using Private DNS zone.
#
# Dependencies:
#   - Private DNS zone virtual network link (dns-private.tf)
#   - Container Apps internal ingress (container-apps.tf)
#   - NSG rule allowing Application Gateway → Container Apps (security.tf)
# ============================================================================

# ----------------------------------------------------------------------------
# Public IP Address
# ----------------------------------------------------------------------------
# T016: Application Gateway public IP
# Standard SKU required for zone redundancy and Application Gateway v2

resource "azurerm_public_ip" "appgw" {
  allocation_method   = "Static"
  location            = var.location
  name                = local.appgw_pip_name
  resource_group_name = var.resource_group_name
  sku                 = "Standard"
  zones               = var.enable_zone_redundancy ? ["1", "2", "3"] : null

  tags = var.tags
}

# ----------------------------------------------------------------------------
# WAF Policy (Optional)
# ----------------------------------------------------------------------------
# T031-T032: Web Application Firewall policy
# Provides OWASP CRS 3.2 protection when enabled

resource "azurerm_web_application_firewall_policy" "appgw" {
  count = var.enable_waf ? 1 : 0

  location            = var.location
  name                = "${local.appgw_name}-wafpolicy"
  resource_group_name = var.resource_group_name

  managed_rules {
    managed_rule_set {
      type    = "OWASP"
      version = "3.2"
    }
  }

  policy_settings {
    enabled                     = true
    file_upload_limit_in_mb     = 100
    max_request_body_size_in_kb = 128
    mode                        = var.waf_mode
    request_body_check          = true
  }

  tags = var.tags
}

# ----------------------------------------------------------------------------
# Application Gateway
# ----------------------------------------------------------------------------
# T017-T025: Application Gateway resource with listeners, backend, routing

resource "azurerm_application_gateway" "main" {
  depends_on = [
    azurerm_private_dns_zone_virtual_network_link.container_apps[0]
  ]

  location            = var.location
  name                = local.appgw_name
  resource_group_name = var.resource_group_name
  zones               = var.enable_zone_redundancy ? ["1", "2", "3"] : null

  # T017: Frontend IP configuration
  frontend_ip_configuration {
    name                 = "public"
    public_ip_address_id = azurerm_public_ip.appgw.id
  }

  # T017: Frontend ports
  frontend_port {
    name = "https"
    port = 443
  }

  frontend_port {
    name = "http"
    port = 80
  }

  # T017: Gateway IP configuration
  gateway_ip_configuration {
    name      = "gateway"
    subnet_id = azurerm_subnet.app_gateway.id
  }

  # T018: HTTPS listener
  http_listener {
    frontend_ip_configuration_name = "public"
    frontend_port_name             = "https"
    name                           = "https"
    protocol                       = "Https"
    host_name                      = var.domain_name
    require_sni                    = var.domain_name != null
    ssl_certificate_name           = var.domain_name != null ? "main" : null
  }

  # T019: HTTP listener (for redirect)
  http_listener {
    frontend_ip_configuration_name = "public"
    frontend_port_name             = "http"
    name                           = "http"
    protocol                       = "Http"
  }

  # T020: Backend pool - uses custom domain (resolved via Private DNS to CA static IP)
  backend_address_pool {
    name  = "container-apps"
    fqdns = [var.domain_name]
  }

  # T021: Backend HTTP settings - HTTP to Container Apps (TLS terminated at App Gateway)
  backend_http_settings {
    affinity_cookie_name                = "ApplicationGatewayAffinity"
    cookie_based_affinity               = "Enabled"
    name                                = "http"
    path                                = "/"
    pick_host_name_from_backend_address = true
    port                                = 80
    probe_name                          = "http"
    protocol                            = "Http"
    request_timeout                     = 180
  }

  # T022: Health probe - HTTP to Container Apps
  probe {
    interval                                  = 30
    minimum_servers                           = 0
    name                                      = "http"
    path                                      = "/"
    pick_host_name_from_backend_http_settings = true
    protocol                                  = "Http"
    timeout                                   = 30
    unhealthy_threshold                       = 3

    match {
      status_code = ["200-399"]
    }
  }

  # T024: HTTP → HTTPS redirect configuration (optional)
  dynamic "redirect_configuration" {
    for_each = var.enable_http_redirect ? [1] : []

    content {
      include_path         = true
      include_query_string = true
      name                 = "http-to-https"
      redirect_type        = "Permanent"
      target_listener_name = "https"
    }
  }

  # T023: HTTPS routing rule
  request_routing_rule {
    backend_address_pool_name  = "container-apps"
    backend_http_settings_name = "http"
    http_listener_name         = "https"
    name                       = "https"
    priority                   = 100
    rule_type                  = "Basic"
  }

  # T025: HTTP redirect routing rule (optional)
  dynamic "request_routing_rule" {
    for_each = var.enable_http_redirect ? [1] : []

    content {
      http_listener_name          = "http"
      name                        = "http-redirect"
      priority                    = 200
      redirect_configuration_name = "http-to-https"
      rule_type                   = "Basic"
    }
  }

  # T017: SKU configuration
  sku {
    capacity = var.enable_zone_redundancy ? null : var.appgw_capacity_min
    name     = var.appgw_sku_name
    tier     = var.appgw_tier
  }

  # Auto-scaling configuration (zone redundancy requires autoscale)
  dynamic "autoscale_configuration" {
    for_each = var.enable_zone_redundancy ? [1] : []

    content {
      max_capacity = var.appgw_capacity_max
      min_capacity = var.appgw_capacity_min
    }
  }

  # T030: SSL certificate (conditional on domain_name and ACME certificate)
  dynamic "ssl_certificate" {
    for_each = var.domain_name != null ? [1] : []

    content {
      name     = "main"
      data     = acme_certificate.main[0].certificate_p12
      password = random_password.certificate_p12[0].result
    }
  }

  # T018: SSL policy
  ssl_policy {
    policy_type = "Predefined"
    policy_name = "AppGwSslPolicy20220101S"
  }

  # T032: Attach WAF policy (optional)
  firewall_policy_id = var.enable_waf ? azurerm_web_application_firewall_policy.appgw[0].id : null

  tags = var.tags

  lifecycle {
    # Certificate data changes trigger replace, but we want in-place update
    ignore_changes = [
      ssl_certificate
    ]
  }
}
