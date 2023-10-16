## 1. Setup PostgreSQL

PostgreSQL setup guide: https://github.com/joetanx/setup/blob/main/postgres.md

## 2. Prepare database secret engine

Enable SSH database engine

```console
[root@vault ~]# vault secrets enable -path=postgresql database
Success! Enabled the database secrets engine at: postgresql/
```

Create database connection `foxtrot`

```console
[root@vault ~]# POSTGRES_URL=foxtrot.vx
[root@vault ~]# vault write postgresql/config/foxtrot \
plugin_name=postgresql-database-plugin \
connection_url="postgresql://{{username}}:{{password}}@$POSTGRES_URL/postgres" \
allowed_roles=monitor \
username="vault" \
password="vaultpassword"
Success! Data written to: postgresql/config/foxtrot
```

Create role `monitor` linked to database connection `foxtrot` that uses `monitor.sql` creation statements to create the database credential

```console
[root@vault ~]# cat << EOF > monitor.sql
CREATE ROLE "{{name}}" WITH LOGIN PASSWORD '{{password}}' VALID UNTIL '{{expiration}}' INHERIT;
GRANT ro TO "{{name}}";
EOF
[root@vault ~]# vault write postgresql/roles/monitor \
db_name=foxtrot \
creation_statements=@monitor.sql \
default_ttl=1h \
max_ttl=24h
Success! Data written to: postgresql/roles/monitor
```

## 3. Prepare test user

Create policy to allow credential request

```console
[root@vault ~]# vault policy write postgresql-access -<< EOF
path "postgresql/*" {
  capabilities = [ "list" ]
}
path "postgresql/creds/monitor" {
  capabilities = ["read"]
}
EOF
Success! Uploaded policy: postgresql-access
```

Enable userpass auth method

```console
[root@vault ~]# vault auth enable userpass
Success! Enabled userpass auth method at: userpass/
```

Create user `test` with the `postgresql-access` access policy

```console
[root@vault ~]# vault write auth/userpass/users/test password=P@ssw0rd policies=postgresql-access
Success! Data written to: auth/userpass/users/test
```

## 4. Request PostgreSQL credentials and test connection

Request PostgreSQL credentials using `test` user

```console
[root@vault ~]# USER_TOKEN=$(vault login -method=userpass username=test password=P@ssw0rd -format=json | jq -r '.auth | .client_token')
[root@vault ~]# VAULT_TOKEN=$USER_TOKEN vault read postgresql/creds/monitor
Key                Value
---                -----
lease_id           postgresql/creds/monitor/3UGdFhVZm16LmAWXqbsYGeQt
lease_duration     1h
lease_renewable    true
password           I2RjCXtzLpi-qFaVZJEZ
username           v-userpass-monitor-3kJjQD48jcv57wK6rcic-1696769975
```

Verify user create from PostgreSQL

```console
[root@foxtrot ~]# sudo -u postgres psql -c "SELECT usename,valuntil FROM pg_user;"
                       usename                       |        valuntil
-----------------------------------------------------+------------------------
 postgres                                            |
 vault                                               |
 v-userpass-monitor-3kJjQD48jcv57wK6rcic-1696769975 | 2023-10-08 21:59:40+08
(3 rows)
```

Test connection to PostgreSQL using the Vault-generated credentials

```console
[root@vault ~]# psql -U v-userpass-monitor-3kJjQD48jcv57wK6rcic-1696769975 -h foxtrot.vx -d postgres
Password for user v-userpass-monitor-3kJjQD48jcv57wK6rcic-1696769975:
psql (13.10)
Type "help" for help.

postgres=> SELECT current_user;
                    current_user
-----------------------------------------------------
 v-userpass-monitor-3kJjQD48jcv57wK6rcic-1696769975
(1 row)

postgres=> \conninfo
You are connected to database "postgres" as user "v-userpass-monitor-3kJjQD48jcv57wK6rcic-1696769975" on host "foxtrot.vx" (address "192.168.17.80") at port "5432".
```
