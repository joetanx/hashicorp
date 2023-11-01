## 1. Install vault

- Configure Hashicorp repository and install Vault
- Configure TLS with [lab certs](https://github.com/joetanx/lab-certs/)
- Edit vault configuration file `/etc/vault.d/vault.hcl` to enable vault UI and set API address

```sh
curl -sLo/etc/yum.repos.d/hashicorp.repo https://rpm.releases.hashicorp.com/RHEL/hashicorp.repo
yum -y install vault && rm -f /etc/yum.repos.d/hashicorp.repo
firewall-cmd --permanent --add-port 8200/tcp && firewall-cmd --reload
curl -sLo /opt/vault/tls/tls.crt https://github.com/joetanx/lab-certs/raw/main/others/vault.vx.pem
curl -sLo /opt/vault/tls/tls.key https://github.com/joetanx/lab-certs/raw/main/others/vault.vx.key
chown vault:vault /opt/vault/tls/tls.*
echo 'ui = true' >> /etc/vault.d/vault.hcl
echo 'api_addr = "https://vault.vx:8200"' >> /etc/vault.d/vault.hcl
```

## 2. Start and initialize Vault

> [!Warning]
> 
> For lab convenience, the commands below perform the following:
> - Write the init output (containing the unseal keys and root token) to `/opt/vault/init.log`
> - Create an auto-unseal service to run on boot
> - Write the root token to `~/.vault-token`
> 
> In production, follow the best practices on [vault unseal](https://developer.hashicorp.com/vault/tutorials/recommended-patterns/pattern-unseal) and [production hardening](https://developer.hashicorp.com/vault/tutorials/operations/production-hardening) to secure the vault

```sh
systemctl enable --now vault
vault operator init | tee /opt/vault/init.log
cat << EOF > /opt/vault/unseal
#!/bin/bash
UNSEAL_KEY=\$(grep 'Unseal Key 1' /opt/vault/init.log | cut -d ':' -f 2 | cut -d ' ' -f 2)
vault operator unseal \$UNSEAL_KEY
UNSEAL_KEY=\$(grep 'Unseal Key 2' /opt/vault/init.log | cut -d ':' -f 2 | cut -d ' ' -f 2)
vault operator unseal \$UNSEAL_KEY
UNSEAL_KEY=\$(grep 'Unseal Key 3' /opt/vault/init.log | cut -d ':' -f 2 | cut -d ' ' -f 2)
vault operator unseal \$UNSEAL_KEY
EOF
chmod +x /opt/vault/unseal
cat << EOF > /usr/lib/systemd/system/vault-unseal.service
[Unit]
Description=Unseal vault on system start up
After=vault.service

[Service]
Type=simple
ExecStart=/bin/bash /opt/vault/unseal

[Install]
WantedBy=multi-user.target
EOF
systemctl enable vault-unseal
grep 'Initial Root Token' /opt/vault/init.log | cut -d ':' -f 2 | cut -d ' ' -f 2 > .vault-token
```

> [!Note]
> 
> Vault CLI checks the following for vault token in sequence:
> 1. `VAULT_TOKEN` environment variable
> 2. `~/.vault-token` file
