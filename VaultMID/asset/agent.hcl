listener "tcp" {
  address = "127.0.0.1:8200"
  tls_disable = true
}

cache {
  use_auto_auth_token = true
}

vault {
  address = "http://vault.server.ip.address:8200"
}

auto_auth {
    method {
        type = "approle"
        config = {
            role_id_file_path = "/opt/snc_mid_server/roleID"
            secret_id_file_path = "/opt/snc_mid_server/secretID"
            remove_secret_id_file_after_reading = false
        }
    }
}
