#!/bin/bash

#global vars should be defined ASAP, otherwise they should be exported from the function they run in
export NODEID=`hostid | tr '[:lower:]' '[:upper:]'`
	
export MAINEVENT_GIT_URL="https://github.com/kzamore/mainevent"
export MAINEVENT_INSTALL_PATH=/root/mainevent
export TERRAFORM_VERSION="1.0.1"
export TERRAFORM_URL="https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_amd64.zip"
export STARTERPACK_PATH=/root/starterpack/files
export PACKSTACK_ZIP_URL=https://github.com/kzamore/starterpack/archive/refs/heads/master.zip
export PACKSTACK_ANSWER_TEMPLATE_URL=https://raw.githubusercontent.com/kzamore/starterpack/master/openstack/files/dmzcloud.ans.template
export PACKSTACK_ANSWER_TEMPLATE_PATH=${STARTERPACK_PATH}/dmzcloud.ans.template
export NODELOGIC_CHECKIN_URL="https://api.nodelogic.net/v1/node/checkin?nodeID=$NODEID"
export NODELOGIC_STARTERPACK_DOWNLOAD_URL="https://api.nodelogic.net/v1/starterpack/openstack/download?nodeID=$NODEID"

. /root/.global.vars

#we should
# update_system
# update_getty "configuring system"
# configure_nameserver
# configure_hosts
# configure_sshd
# configure_ssh_known_hosts
# packstack_build
# mainevent_apply
# branding
# configure_final

function deploy_traefik() {
	. /root/.global.vars
	update_getty "deploying the loadbalancer for the portainer experience"
	mkdir -p /${ADMIN_USER}/traefik/volume/traefik /${ADMIN_USER}/traefik/volume/keycloak/config
cat << EOF > /${ADMIN_USER}/traefik/docker-compose.yml
version: "3"

services:
  traefik:
    image: traefik:v2.5
    restart: unless-stopped
    stdin_open: true
    ports:
      - "127.0.0.1:9002:8080"
      - "0.0.0.0:80:80"
      - "0.0.0.0:443:443"
    command:
      - --providers.docker=true
      - --providers.file=true
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - /${ADMIN_USER}/traefik/volume/traefik/traefik.yml:/etc/traefik/traefik.yml
      - /${ADMIN_USER}/traefik/volume/traefik/tls-certs.yml:/etc/traefik/tls-certs.yml
      - /${ADMIN_USER}/traefik/volume/traefik/sso.toml:/etc/traefik/sso.toml
    labels:
      - "traefik.http.routers.traefik.rule=Host(\`traefik-admin.${DOMAIN_NAME}\`)"
      - traefik.http.routers.traefik.middlewares=sso@file
      - "traefik.http.routers.traefik.service=api@internal"
      - traefik.http.routers.traefik.entryPoints=websecure
      - traefik.http.routers.traefik.rule=host(\`traefik-admin.${DOMAIN_NAME}\`)
      - traefik.http.routers.traefik.tls=true

  traefik-fa:
    image: thomseddon/traefik-forward-auth
    container_name: traefik-fa
    restart: unless-stopped

    volumes:
      - /${ADMIN_USER}/traefik/volume/traefik/forward.ini:/forward.ini

    environment:
      - CONFIG=/forward.ini

    labels:
      - traefik.docker.network=traefik_default
      - traefik.http.services.traefik-fa.loadBalancer.server.port=4181
      - "traefik.http.routers.traefik-fa.rule=Host(\`auth.${DOMAIN_NAME}\`)"
      - traefik.http.routers.traefik-fa.middlewares=sso@file

      # SSL configuration
      - traefik.http.routers.traefik-fa-ssl.entryPoints=websecure
      - traefik.http.routers.traefik-fa-ssl.rule=host(\`auth.${DOMAIN_NAME}\`)
      - traefik.http.routers.traefik-fa-ssl.middlewares=sso@file
      - traefik.http.routers.traefik-fa-ssl.tls=true

  whoami:
    image: emilevauge/whoami
    container_name: whoami
    restart: unless-stopped

    labels:
      - traefik.docker.network=traefik_default
      - "traefik.http.routers.whoami.rule=Host(\`auth.${DOMAIN_NAME}\`)"
      - traefik.http.routers.whoami.entryPoints=websecure
      - traefik.http.routers.whoami.rule=host(\`whoami.${DOMAIN_NAME}\`)
      - traefik.http.routers.whoami.middlewares=sso@file
      - traefik.http.routers.whoami.tls=true

  postgres:
    container_name: postgres
    image: postgres:latest
    restart: unless-stopped
    environment:
      TZ: America/Chicago
      POSTGRES_DB: judo
      POSTGRES_USER: judo
      POSTGRES_PASSWORD: judo
    ports:
      - "5432:5432"

    volumes:
      - /${ADMIN_USER}/traefik/volume/postgres/data:/var/lib/postgresql/data

  keycloak:
    container_name: keycloak
    image: quay.io/keycloak/keycloak:12.0.4
    restart: unless-stopped
    environment:
      TZ: America/Chicago
      DB_VENDOR: POSTGRES
      DB_ADDR: postgres
      DB_DATABASE: judo
      DB_USER: judo
      DB_SCHEMA: public
      DB_PASSWORD: judo
      KEYCLOAK_USER: admin
      KEYCLOAK_PASSWORD: supersecret
      PROXY_ADDRESS_FORWARDING: true
      KEYCLOAK_FRONTEND_URL: https://keycloak.${DOMAIN_NAME}/auth

    command:
      [
        '-b',
        '0.0.0.0',
        '-Djboss.http.port=80',
        '-Djboss.https.port=443',
        '-Djboss.socket.binding.port-offset=0',
        '-Dkeycloak.migration.action=import',
        '-Dkeycloak.migration.provider=dir',
        '-Dkeycloak.migration.dir=/realm-config',
        '-Dkeycloak.migration.strategy=IGNORE_EXISTING',
      ]

    volumes:
       - /${ADMIN_USER}/traefik/volume/keycloak/config:/realm-config

    labels:
      - traefik.http.services.keycloak.loadBalancer.server.port=80
      - traefik.http.routers.keycloak.entryPoints=websecure
      - traefik.http.routers.keycloak.rule=host(\`keycloak.${DOMAIN_NAME}\`)
      - traefik.http.routers.keycloak.tls=true

EOF

	cat << EOF > /${ADMIN_USER}/traefik/volume/traefik/traefik.yml
## traefik.yml


log:
  level: DEBUG

# Docker configuration backend
providers:
  docker:
    defaultRule: "Host(\`{{ trimPrefix \`/\` .Name }}.${DOMAIN_NAME}\`)"
  file:
    filename: /etc/traefik/tls-certs.yml

# API and dashboard configuration
api:
  insecure: true


entryPoints:
  web:
    address: ":80"
    http:
      redirections:
        entrypoint:
          to: websecure
    forwardedHeaders:
      trustedIPs:
        - "127.0.0.1/32"
  websecure:
    address: ":443"
    forwardedHeaders:
      insecure: true
      trustedIPs:
        - "127.0.0.1/32"
EOF


cat << 'EOF' > /${ADMIN_USER}/traefik/volume/traefik/tls-certs.yml
http:
  middlewares:
    sso:
      forwardAuth:
        address: "http://traefik-fa:4181"
        authResponseHeaders:
         - "X-Forwarded-User"
         - "X-WebAuth-User"
        trustForwardHeader: "true"
tls:
  options:
    default:
      minVersion: VersionTLS12
      maxVersion: VersionTLS12
      preferServerCipherSuites: true
EOF

cat << 'EOF' > /${ADMIN_USER}/traefik/volume/traefik/sso.toml
[http.middlewares]
  [http.middlewares.sso.forwardAuth]
    address = "http://traefik-fa:4181"
    authResponseHeaders = ["X-Forwarded-User", "X-WebAuth-User"]
    trustForwardHeader = "true"
  [http.middlewares.httpsredirect.redirectScheme]
    scheme = "https"
EOF

OIDC_SECRET=$(openssl rand -hex 10)
OIDC_CLIENT_SECRET=$(uuidgen)
cat << EOF > /${ADMIN_USER}/traefik/volume/traefik/forward.ini
default-provider = oidc

# Cookie signing nonce, replace this with something random
secret = ${OIDC_SECRET}

# This client id / secret is defined in keycloak-realm-config/master-realm.json
providers.oidc.client-id = oauth-proxy
providers.oidc.client-secret = ${OIDC_CLIENT_SECRET}
providers.oidc.issuer-url = https://keycloak.${DOMAIN_NAME}/auth/realms/master

log-level = debug

cookie-domain = ${DOMAIN_NAME}
auth-host = auth.${DOMAIN_NAME}

# Add authorized users here
whitelist = ${ADMIN_USER}@{$DOMAIN_NAME}
EOF

cat << 'EOF' > /${ADMIN_USER}/traefik/volume/keycloak/config/master-realm.json
{
  "id" : "master",
  "realm" : "master",
  "displayName" : "Keycloak",
EOF

echo -n '  "displayNameHtml" : "<div class=\"kc-logo-text\"><span>' >> /${ADMIN_USER}/traefik/volume/keycloak/config/master-realm.json
echo -n $DOMAIN_NAME >> /${ADMIN_USER}/traefik/volume/keycloak/config/master-realm.json
echo '</span></div>",' >> /${ADMIN_USER}/traefik/volume/keycloak/config/master-realm.json


cat << 'EOF' >> /${ADMIN_USER}/traefik/volume/keycloak/config/master-realm.json
  "notBefore" : 0,
  "revokeRefreshToken" : false,
  "refreshTokenMaxReuse" : 0,
  "accessTokenLifespan" : 60,
  "accessTokenLifespanForImplicitFlow" : 900,
  "ssoSessionIdleTimeout" : 1800,
  "ssoSessionMaxLifespan" : 36000,
  "ssoSessionIdleTimeoutRememberMe" : 0,
  "ssoSessionMaxLifespanRememberMe" : 0,
  "offlineSessionIdleTimeout" : 2592000,
  "offlineSessionMaxLifespanEnabled" : false,
  "offlineSessionMaxLifespan" : 5184000,
  "clientSessionIdleTimeout" : 0,
  "clientSessionMaxLifespan" : 0,
  "accessCodeLifespan" : 60,
  "accessCodeLifespanUserAction" : 300,
  "accessCodeLifespanLogin" : 1800,
  "actionTokenGeneratedByAdminLifespan" : 43200,
  "actionTokenGeneratedByUserLifespan" : 300,
  "enabled" : true,
  "sslRequired" : "external",
  "registrationAllowed" : false,
  "registrationEmailAsUsername" : false,
  "rememberMe" : false,
  "verifyEmail" : false,
  "loginWithEmailAllowed" : true,
  "duplicateEmailsAllowed" : false,
  "resetPasswordAllowed" : false,
  "editUsernameAllowed" : false,
  "bruteForceProtected" : false,
  "permanentLockout" : false,
  "maxFailureWaitSeconds" : 900,
  "minimumQuickLoginWaitSeconds" : 60,
  "waitIncrementSeconds" : 60,
  "quickLoginCheckMilliSeconds" : 1000,
  "maxDeltaTimeSeconds" : 43200,
  "failureFactor" : 30,
  "roles" : {
    "realm" : [ {
      "id" : "32626c92-4327-40f1-b318-76a6b5c7eee5",
      "name" : "offline_access",
      "description" : "${role_offline-access}",
      "composite" : false,
      "clientRole" : false,
      "containerId" : "master",
      "attributes" : { }
    }, {
      "id" : "e36da570-7ae0-4323-8b39-73eb92ce722f",
      "name" : "admin",
      "description" : "${role_admin}",
      "composite" : true,
      "composites" : {
        "realm" : [ "create-realm" ],
        "client" : {
          "master-realm" : [ "query-groups", "create-client", "query-realms", "view-authorization", "view-realm", "manage-clients", "query-users", "manage-realm", "view-events", "manage-events", "view-identity-providers", "view-users", "manage-identity-providers", "manage-authorization", "manage-users", "view-clients", "query-clients", "impersonation" ]
        }
      },
      "clientRole" : false,
      "containerId" : "master",
      "attributes" : { }
    }, {
      "id" : "71aca46c-6fcf-4456-ba87-6374e70108a2",
      "name" : "uma_authorization",
      "description" : "${role_uma_authorization}",
      "composite" : false,
      "clientRole" : false,
      "containerId" : "master",
      "attributes" : { }
    }, {
      "id" : "6ca3fee8-1a3f-4068-a311-6e81223a884b",
      "name" : "create-realm",
      "description" : "${role_create-realm}",
      "composite" : false,
      "clientRole" : false,
      "containerId" : "master",
      "attributes" : { }
    } ],
    "client" : {
      "oauth-proxy" : [ ],
      "security-admin-console" : [ ],
      "admin-cli" : [ ],
      "account-console" : [ ],
      "broker" : [ {
        "id" : "2cc5e40c-0a28-4c09-85eb-20cd47ac1351",
        "name" : "read-token",
        "description" : "${role_read-token}",
        "composite" : false,
        "clientRole" : true,
        "containerId" : "380985f1-61c7-4940-93ae-7a09458071ca",
        "attributes" : { }
      } ],
      "master-realm" : [ {
        "id" : "a8271c2c-6437-4ca5-ae83-49ea5fe1318d",
        "name" : "query-groups",
        "description" : "${role_query-groups}",
        "composite" : false,
        "clientRole" : true,
        "containerId" : "7174c175-1887-4e57-b95b-969fe040deff",
        "attributes" : { }
      }, {
        "id" : "5a7cb1ae-7dac-486b-bf7b-4d7fbc5adb31",
        "name" : "create-client",
        "description" : "${role_create-client}",
        "composite" : false,
        "clientRole" : true,
        "containerId" : "7174c175-1887-4e57-b95b-969fe040deff",
        "attributes" : { }
      }, {
        "id" : "a9e6a2fa-c31b-4959-bf8a-a46fcc9c65ec",
        "name" : "view-authorization",
        "description" : "${role_view-authorization}",
        "composite" : false,
        "clientRole" : true,
        "containerId" : "7174c175-1887-4e57-b95b-969fe040deff",
        "attributes" : { }
      }, {
        "id" : "1cef34e3-569a-4d2b-ba5c-aafe5c7ab423",
        "name" : "query-realms",
        "description" : "${role_query-realms}",
        "composite" : false,
        "clientRole" : true,
        "containerId" : "7174c175-1887-4e57-b95b-969fe040deff",
        "attributes" : { }
      }, {
        "id" : "efc46075-30cd-4600-aa92-2ae4a171d0c2",
        "name" : "view-realm",
        "description" : "${role_view-realm}",
        "composite" : false,
        "clientRole" : true,
        "containerId" : "7174c175-1887-4e57-b95b-969fe040deff",
        "attributes" : { }
      }, {
        "id" : "9ffacaf0-afc6-49e9-8708-ef35ac40f3f8",
        "name" : "manage-clients",
        "description" : "${role_manage-clients}",
        "composite" : false,
        "clientRole" : true,
        "containerId" : "7174c175-1887-4e57-b95b-969fe040deff",
        "attributes" : { }
      }, {
        "id" : "90662091-b3bc-4ae4-83c9-a4f53e7e9eeb",
        "name" : "query-users",
        "description" : "${role_query-users}",
        "composite" : false,
        "clientRole" : true,
        "containerId" : "7174c175-1887-4e57-b95b-969fe040deff",
        "attributes" : { }
      }, {
        "id" : "9a5fbc9d-6fae-4155-86f6-72fd399aa126",
        "name" : "manage-realm",
        "description" : "${role_manage-realm}",
        "composite" : false,
        "clientRole" : true,
        "containerId" : "7174c175-1887-4e57-b95b-969fe040deff",
        "attributes" : { }
      }, {
        "id" : "03f46127-9436-477d-8c7f-58569f45237c",
        "name" : "view-events",
        "description" : "${role_view-events}",
        "composite" : false,
        "clientRole" : true,
        "containerId" : "7174c175-1887-4e57-b95b-969fe040deff",
        "attributes" : { }
      }, {
        "id" : "f10eaea2-90ab-4310-9d5f-8d986564d061",
        "name" : "view-identity-providers",
        "description" : "${role_view-identity-providers}",
        "composite" : false,
        "clientRole" : true,
        "containerId" : "7174c175-1887-4e57-b95b-969fe040deff",
        "attributes" : { }
      }, {
        "id" : "2403e038-2cf7-4b06-b5cb-33a417a00d8d",
        "name" : "manage-events",
        "description" : "${role_manage-events}",
        "composite" : false,
        "clientRole" : true,
        "containerId" : "7174c175-1887-4e57-b95b-969fe040deff",
        "attributes" : { }
      }, {
        "id" : "677d057b-66f8-4163-9948-95fdbd06dfdc",
        "name" : "view-users",
        "description" : "${role_view-users}",
        "composite" : true,
        "composites" : {
          "client" : {
            "master-realm" : [ "query-groups", "query-users" ]
          }
        },
        "clientRole" : true,
        "containerId" : "7174c175-1887-4e57-b95b-969fe040deff",
        "attributes" : { }
      }, {
        "id" : "dc140fa6-bf2c-49f2-b8c9-fc34ef8a2c63",
        "name" : "manage-identity-providers",
        "description" : "${role_manage-identity-providers}",
        "composite" : false,
        "clientRole" : true,
        "containerId" : "7174c175-1887-4e57-b95b-969fe040deff",
        "attributes" : { }
      }, {
        "id" : "155bf234-4895-4855-95c2-a460518f57e8",
        "name" : "manage-authorization",
        "description" : "${role_manage-authorization}",
        "composite" : false,
        "clientRole" : true,
        "containerId" : "7174c175-1887-4e57-b95b-969fe040deff",
        "attributes" : { }
      }, {
        "id" : "5441ec71-3eac-4696-9e68-0de54fbdde98",
        "name" : "manage-users",
        "description" : "${role_manage-users}",
        "composite" : false,
        "clientRole" : true,
        "containerId" : "7174c175-1887-4e57-b95b-969fe040deff",
        "attributes" : { }
      }, {
        "id" : "2db0f052-cb91-4170-81fd-107756b162f7",
        "name" : "view-clients",
        "description" : "${role_view-clients}",
        "composite" : true,
        "composites" : {
          "client" : {
            "master-realm" : [ "query-clients" ]
          }
        },
        "clientRole" : true,
        "containerId" : "7174c175-1887-4e57-b95b-969fe040deff",
        "attributes" : { }
      }, {
        "id" : "e1d7f235-8bf2-40b8-be49-49aca70a5088",
        "name" : "query-clients",
        "description" : "${role_query-clients}",
        "composite" : false,
        "clientRole" : true,
        "containerId" : "7174c175-1887-4e57-b95b-969fe040deff",
        "attributes" : { }
      }, {
        "id" : "e743f66a-2f56-4b97-b34b-33f06ff1e739",
        "name" : "impersonation",
        "description" : "${role_impersonation}",
        "composite" : false,
        "clientRole" : true,
        "containerId" : "7174c175-1887-4e57-b95b-969fe040deff",
        "attributes" : { }
      } ],
      "account" : [ {
        "id" : "64d8f532-839e-4386-b2eb-fe8848b0a9de",
        "name" : "manage-consent",
        "description" : "${role_manage-consent}",
        "composite" : true,
        "composites" : {
          "client" : {
            "account" : [ "view-consent" ]
          }
        },
        "clientRole" : true,
        "containerId" : "a367038f-fe01-4459-9f91-7ad0cf498533",
        "attributes" : { }
      }, {
        "id" : "3ec22748-960f-4f96-a43e-50f54a02dc23",
        "name" : "view-profile",
        "description" : "${role_view-profile}",
        "composite" : false,
        "clientRole" : true,
        "containerId" : "a367038f-fe01-4459-9f91-7ad0cf498533",
        "attributes" : { }
      }, {
        "id" : "177d18e4-46b0-4ea3-8b70-327486ce5bb2",
        "name" : "view-applications",
        "description" : "${role_view-applications}",
        "composite" : false,
        "clientRole" : true,
        "containerId" : "a367038f-fe01-4459-9f91-7ad0cf498533",
        "attributes" : { }
      }, {
        "id" : "703643d6-0542-4e27-9737-7c442925c18c",
        "name" : "manage-account-links",
        "description" : "${role_manage-account-links}",
        "composite" : false,
        "clientRole" : true,
        "containerId" : "a367038f-fe01-4459-9f91-7ad0cf498533",
        "attributes" : { }
      }, {
        "id" : "c64f9f66-d762-4337-8833-cf31c316e8a7",
        "name" : "view-consent",
        "description" : "${role_view-consent}",
        "composite" : false,
        "clientRole" : true,
        "containerId" : "a367038f-fe01-4459-9f91-7ad0cf498533",
        "attributes" : { }
      }, {
        "id" : "611f568b-0fdd-4d2e-ba34-03136cd486c4",
        "name" : "manage-account",
        "description" : "${role_manage-account}",
        "composite" : true,
        "composites" : {
          "client" : {
            "account" : [ "manage-account-links" ]
          }
        },
        "clientRole" : true,
        "containerId" : "a367038f-fe01-4459-9f91-7ad0cf498533",
        "attributes" : { }
      } ]
    }
  },
  "groups" : [ ],
  "defaultRoles" : [ "offline_access", "uma_authorization" ],
  "requiredCredentials" : [ "password" ],
  "otpPolicyType" : "totp",
  "otpPolicyAlgorithm" : "HmacSHA1",
  "otpPolicyInitialCounter" : 0,
  "otpPolicyDigits" : 6,
  "otpPolicyLookAheadWindow" : 1,
  "otpPolicyPeriod" : 30,
  "otpSupportedApplications" : [ "FreeOTP", "Google Authenticator" ],
  "webAuthnPolicyRpEntityName" : "keycloak",
  "webAuthnPolicySignatureAlgorithms" : [ "ES256" ],
  "webAuthnPolicyRpId" : "",
  "webAuthnPolicyAttestationConveyancePreference" : "not specified",
  "webAuthnPolicyAuthenticatorAttachment" : "not specified",
  "webAuthnPolicyRequireResidentKey" : "not specified",
  "webAuthnPolicyUserVerificationRequirement" : "not specified",
  "webAuthnPolicyCreateTimeout" : 0,
  "webAuthnPolicyAvoidSameAuthenticatorRegister" : false,
  "webAuthnPolicyAcceptableAaguids" : [ ],
  "webAuthnPolicyPasswordlessRpEntityName" : "keycloak",
  "webAuthnPolicyPasswordlessSignatureAlgorithms" : [ "ES256" ],
  "webAuthnPolicyPasswordlessRpId" : "",
  "webAuthnPolicyPasswordlessAttestationConveyancePreference" : "not specified",
  "webAuthnPolicyPasswordlessAuthenticatorAttachment" : "not specified",
  "webAuthnPolicyPasswordlessRequireResidentKey" : "not specified",
  "webAuthnPolicyPasswordlessUserVerificationRequirement" : "not specified",
  "webAuthnPolicyPasswordlessCreateTimeout" : 0,
  "webAuthnPolicyPasswordlessAvoidSameAuthenticatorRegister" : false,
  "webAuthnPolicyPasswordlessAcceptableAaguids" : [ ],
  "scopeMappings" : [ {
    "clientScope" : "offline_access",
    "roles" : [ "offline_access" ]
  } ],
  "clientScopeMappings" : {
    "account" : [ {
      "client" : "account-console",
      "roles" : [ "manage-account" ]
    } ]
  },
  "clients" : [ {
    "id" : "a367038f-fe01-4459-9f91-7ad0cf498533",
    "clientId" : "account",
    "name" : "${client_account}",
    "rootUrl" : "${authBaseUrl}",
    "baseUrl" : "/realms/master/account/",
    "surrogateAuthRequired" : false,
    "enabled" : true,
    "alwaysDisplayInConsole" : false,
    "clientAuthenticatorType" : "client-secret",
    "secret" : "0896a464-da81-4454-bee9-b56bdbad9e7f",
    "defaultRoles" : [ "view-profile", "manage-account" ],
    "redirectUris" : [ "/realms/master/account/*" ],
    "webOrigins" : [ ],
    "notBefore" : 0,
    "bearerOnly" : false,
    "consentRequired" : false,
    "standardFlowEnabled" : true,
    "implicitFlowEnabled" : false,
    "directAccessGrantsEnabled" : false,
    "serviceAccountsEnabled" : false,
    "publicClient" : false,
    "frontchannelLogout" : false,
    "protocol" : "openid-connect",
    "attributes" : { },
    "authenticationFlowBindingOverrides" : { },
    "fullScopeAllowed" : false,
    "nodeReRegistrationTimeout" : 0,
    "defaultClientScopes" : [ "web-origins", "role_list", "roles", "profile", "email" ],
    "optionalClientScopes" : [ "address", "phone", "offline_access", "microprofile-jwt" ]
  }, {
    "id" : "72f75604-1e21-407c-b967-790aafd11534",
    "clientId" : "account-console",
    "name" : "${client_account-console}",
    "rootUrl" : "${authBaseUrl}",
    "baseUrl" : "/realms/master/account/",
    "surrogateAuthRequired" : false,
    "enabled" : true,
    "alwaysDisplayInConsole" : false,
    "clientAuthenticatorType" : "client-secret",
    "secret" : "91f85142-ee18-4e30-9949-e5acb701bdee",
    "redirectUris" : [ "/realms/master/account/*" ],
    "webOrigins" : [ ],
    "notBefore" : 0,
    "bearerOnly" : false,
    "consentRequired" : false,
    "standardFlowEnabled" : true,
    "implicitFlowEnabled" : false,
    "directAccessGrantsEnabled" : false,
    "serviceAccountsEnabled" : false,
    "publicClient" : true,
    "frontchannelLogout" : false,
    "protocol" : "openid-connect",
    "attributes" : {
      "pkce.code.challenge.method" : "S256"
    },
    "authenticationFlowBindingOverrides" : { },
    "fullScopeAllowed" : false,
    "nodeReRegistrationTimeout" : 0,
    "protocolMappers" : [ {
      "id" : "2772c101-0dba-49b7-9627-5aaddc666939",
      "name" : "audience resolve",
      "protocol" : "openid-connect",
      "protocolMapper" : "oidc-audience-resolve-mapper",
      "consentRequired" : false,
      "config" : { }
    } ],
    "defaultClientScopes" : [ "web-origins", "role_list", "roles", "profile", "email" ],
    "optionalClientScopes" : [ "address", "phone", "offline_access", "microprofile-jwt" ]
  }, {
    "id" : "b13fd0de-3be0-4a08-bc5d-d1de34421b1a",
    "clientId" : "admin-cli",
    "name" : "${client_admin-cli}",
    "surrogateAuthRequired" : false,
    "enabled" : true,
    "alwaysDisplayInConsole" : false,
    "clientAuthenticatorType" : "client-secret",
    "secret" : "4640af2e-b4a6-44eb-85ec-6278a62a4f01",
    "redirectUris" : [ ],
    "webOrigins" : [ ],
    "notBefore" : 0,
    "bearerOnly" : false,
    "consentRequired" : false,
    "standardFlowEnabled" : false,
    "implicitFlowEnabled" : false,
    "directAccessGrantsEnabled" : true,
    "serviceAccountsEnabled" : false,
    "publicClient" : true,
    "frontchannelLogout" : false,
    "protocol" : "openid-connect",
    "attributes" : { },
    "authenticationFlowBindingOverrides" : { },
    "fullScopeAllowed" : false,
    "nodeReRegistrationTimeout" : 0,
    "defaultClientScopes" : [ "web-origins", "role_list", "roles", "profile", "email" ],
    "optionalClientScopes" : [ "address", "phone", "offline_access", "microprofile-jwt" ]
  }, {
    "id" : "380985f1-61c7-4940-93ae-7a09458071ca",
    "clientId" : "broker",
    "name" : "${client_broker}",
    "surrogateAuthRequired" : false,
    "enabled" : true,
    "alwaysDisplayInConsole" : false,
    "clientAuthenticatorType" : "client-secret",
    "secret" : "65d2ba2b-bcae-49ff-9f56-77c818f55930",
    "redirectUris" : [ ],
    "webOrigins" : [ ],
    "notBefore" : 0,
    "bearerOnly" : false,
    "consentRequired" : false,
    "standardFlowEnabled" : true,
    "implicitFlowEnabled" : false,
    "directAccessGrantsEnabled" : false,
    "serviceAccountsEnabled" : false,
    "publicClient" : false,
    "frontchannelLogout" : false,
    "protocol" : "openid-connect",
    "attributes" : { },
    "authenticationFlowBindingOverrides" : { },
    "fullScopeAllowed" : false,
    "nodeReRegistrationTimeout" : 0,
    "defaultClientScopes" : [ "web-origins", "role_list", "roles", "profile", "email" ],
    "optionalClientScopes" : [ "address", "phone", "offline_access", "microprofile-jwt" ]
  }, {
    "id" : "7174c175-1887-4e57-b95b-969fe040deff",
    "clientId" : "master-realm",
    "name" : "master Realm",
    "surrogateAuthRequired" : false,
    "enabled" : true,
    "alwaysDisplayInConsole" : false,
    "clientAuthenticatorType" : "client-secret",
    "secret" : "40f73851-a94c-4091-90de-aeee8ca1acf8",
    "redirectUris" : [ ],
    "webOrigins" : [ ],
    "notBefore" : 0,
    "bearerOnly" : true,
    "consentRequired" : false,
    "standardFlowEnabled" : true,
    "implicitFlowEnabled" : false,
    "directAccessGrantsEnabled" : false,
    "serviceAccountsEnabled" : false,
    "publicClient" : false,
    "frontchannelLogout" : false,
    "attributes" : { },
    "authenticationFlowBindingOverrides" : { },
    "fullScopeAllowed" : true,
    "nodeReRegistrationTimeout" : 0,
    "defaultClientScopes" : [ "web-origins", "role_list", "roles", "profile", "email" ],
    "optionalClientScopes" : [ "address", "phone", "offline_access", "microprofile-jwt" ]
  },
    {
      "id": "0493c7c6-6e20-49ea-9acb-627c0b52d400",
      "clientId": "oauth-proxy",
      "surrogateAuthRequired": false,
      "enabled": true,
      "alwaysDisplayInConsole": false,
      "clientAuthenticatorType": "client-secret",
EOF

echo "      \"secret\": \"${OIDC_CLIENT_SECRET}\"," >>  /${ADMIN_USER}/traefik/volume/keycloak/config/master-realm.json

cat << 'EOF' >> /${ADMIN_USER}/traefik/volume/keycloak/config/master-realm.json
      "redirectUris": [
EOF

echo "        \"https://keycloak.${DOMAIN_NAME}/_oauth\"" >>  /${ADMIN_USER}/traefik/volume/keycloak/config/master-realm.json

cat << 'EOF' >> /${ADMIN_USER}/traefik/volume/keycloak/config/master-realm.json
      ],
      "webOrigins": [],
      "notBefore": 0,
      "bearerOnly": false,
      "consentRequired": false,
      "standardFlowEnabled": true,
      "implicitFlowEnabled": false,
      "directAccessGrantsEnabled": true,
      "serviceAccountsEnabled": false,
      "publicClient": false,
      "frontchannelLogout": false,
      "protocol": "openid-connect",
      "attributes": {
        "saml.assertion.signature": "false",
        "saml.force.post.binding": "false",
        "saml.multivalued.roles": "false",
        "saml.encrypt": "false",
        "saml.server.signature": "false",
        "saml.server.signature.keyinfo.ext": "false",
        "exclude.session.state.from.auth.response": "false",
        "saml_force_name_id_format": "false",
        "saml.client.signature": "false",
        "tls.client.certificate.bound.access.tokens": "false",
        "saml.authnstatement": "false",
        "display.on.consent.screen": "false",
        "saml.onetimeuse.condition": "false"
      },
      "authenticationFlowBindingOverrides": {},
      "fullScopeAllowed": true,
      "nodeReRegistrationTimeout": -1,
      "defaultClientScopes": [
        "web-origins",
        "role_list",
        "roles",
        "profile",
        "email"
      ],
      "optionalClientScopes": [
        "address",
        "phone",
        "offline_access",
        "microprofile-jwt"
      ]
    }, {
    "id" : "2a3ad1fd-a30d-4b72-89c4-bed12f178338",
    "clientId" : "security-admin-console",
    "name" : "${client_security-admin-console}",
    "rootUrl" : "${authAdminUrl}",
    "baseUrl" : "/admin/master/console/",
    "surrogateAuthRequired" : false,
    "enabled" : true,
    "alwaysDisplayInConsole" : false,
    "clientAuthenticatorType" : "client-secret",
    "secret" : "b234b7aa-8417-410f-b3fd-c57434d3aa4a",
    "redirectUris" : [ "/admin/master/console/*" ],
    "webOrigins" : [ "+" ],
    "notBefore" : 0,
    "bearerOnly" : false,
    "consentRequired" : false,
    "standardFlowEnabled" : true,
    "implicitFlowEnabled" : false,
    "directAccessGrantsEnabled" : false,
    "serviceAccountsEnabled" : false,
    "publicClient" : true,
    "frontchannelLogout" : false,
    "protocol" : "openid-connect",
    "attributes" : {
      "pkce.code.challenge.method" : "S256"
    },
    "authenticationFlowBindingOverrides" : { },
    "fullScopeAllowed" : false,
    "nodeReRegistrationTimeout" : 0,
    "protocolMappers" : [ {
      "id" : "5885b0d3-a917-4b52-8380-f37d0754a2ef",
      "name" : "locale",
      "protocol" : "openid-connect",
      "protocolMapper" : "oidc-usermodel-attribute-mapper",
      "consentRequired" : false,
      "config" : {
        "userinfo.token.claim" : "true",
        "user.attribute" : "locale",
        "id.token.claim" : "true",
        "access.token.claim" : "true",
        "claim.name" : "locale",
        "jsonType.label" : "String"
      }
    } ],
    "defaultClientScopes" : [ "web-origins", "role_list", "roles", "profile", "email" ],
    "optionalClientScopes" : [ "address", "phone", "offline_access", "microprofile-jwt" ]
  } ],
  "clientScopes" : [ {
    "id" : "47ea3b67-4f0c-4c7e-8ac6-a33a3d655894",
    "name" : "address",
    "description" : "OpenID Connect built-in scope: address",
    "protocol" : "openid-connect",
    "attributes" : {
      "include.in.token.scope" : "true",
      "display.on.consent.screen" : "true",
      "consent.screen.text" : "${addressScopeConsentText}"
    },
    "protocolMappers" : [ {
      "id" : "4be0ca19-0ec7-4cc1-b263-845ea539ff12",
      "name" : "address",
      "protocol" : "openid-connect",
      "protocolMapper" : "oidc-address-mapper",
      "consentRequired" : false,
      "config" : {
        "user.attribute.formatted" : "formatted",
        "user.attribute.country" : "country",
        "user.attribute.postal_code" : "postal_code",
        "userinfo.token.claim" : "true",
        "user.attribute.street" : "street",
        "id.token.claim" : "true",
        "user.attribute.region" : "region",
        "access.token.claim" : "true",
        "user.attribute.locality" : "locality"
      }
    } ]
  }, {
    "id" : "aba72e57-540f-4825-95b7-2d143be028cc",
    "name" : "email",
    "description" : "OpenID Connect built-in scope: email",
    "protocol" : "openid-connect",
    "attributes" : {
      "include.in.token.scope" : "true",
      "display.on.consent.screen" : "true",
      "consent.screen.text" : "${emailScopeConsentText}"
    },
    "protocolMappers" : [ {
      "id" : "7fe82724-5748-4b6d-9708-a028f5d3b970",
      "name" : "email verified",
      "protocol" : "openid-connect",
      "protocolMapper" : "oidc-usermodel-property-mapper",
      "consentRequired" : false,
      "config" : {
        "userinfo.token.claim" : "true",
        "user.attribute" : "emailVerified",
        "id.token.claim" : "true",
        "access.token.claim" : "true",
        "claim.name" : "email_verified",
        "jsonType.label" : "boolean"
      }
    }, {
      "id" : "e42f334e-cfae-44a0-905d-c3ef215feaae",
      "name" : "email",
      "protocol" : "openid-connect",
      "protocolMapper" : "oidc-usermodel-property-mapper",
      "consentRequired" : false,
      "config" : {
        "userinfo.token.claim" : "true",
        "user.attribute" : "email",
        "id.token.claim" : "true",
        "access.token.claim" : "true",
        "claim.name" : "email",
        "jsonType.label" : "String"
      }
    } ]
  }, {
    "id" : "ec765598-bd71-4318-86c3-b3f81a41c99e",
    "name" : "microprofile-jwt",
    "description" : "Microprofile - JWT built-in scope",
    "protocol" : "openid-connect",
    "attributes" : {
      "include.in.token.scope" : "true",
      "display.on.consent.screen" : "false"
    },
    "protocolMappers" : [ {
      "id" : "90694036-4014-4672-a2c8-c68319e9308a",
      "name" : "upn",
      "protocol" : "openid-connect",
      "protocolMapper" : "oidc-usermodel-property-mapper",
      "consentRequired" : false,
      "config" : {
        "userinfo.token.claim" : "true",
        "user.attribute" : "username",
        "id.token.claim" : "true",
        "access.token.claim" : "true",
        "claim.name" : "upn",
        "jsonType.label" : "String"
      }
    }, {
      "id" : "f7b0fcc0-6139-4158-ac45-34fd9a58a5ef",
      "name" : "groups",
      "protocol" : "openid-connect",
      "protocolMapper" : "oidc-usermodel-realm-role-mapper",
      "consentRequired" : false,
      "config" : {
        "multivalued" : "true",
        "user.attribute" : "foo",
        "id.token.claim" : "true",
        "access.token.claim" : "true",
        "claim.name" : "groups",
        "jsonType.label" : "String"
      }
    } ]
  }, {
    "id" : "8a09267b-3634-4a9c-baab-6f2fb4137347",
    "name" : "offline_access",
    "description" : "OpenID Connect built-in scope: offline_access",
    "protocol" : "openid-connect",
    "attributes" : {
      "consent.screen.text" : "${offlineAccessScopeConsentText}",
      "display.on.consent.screen" : "true"
    }
  }, {
    "id" : "3a48c5dd-33a8-4be0-9d2e-30fd7f98363a",
    "name" : "phone",
    "description" : "OpenID Connect built-in scope: phone",
    "protocol" : "openid-connect",
    "attributes" : {
      "include.in.token.scope" : "true",
      "display.on.consent.screen" : "true",
      "consent.screen.text" : "${phoneScopeConsentText}"
    },
    "protocolMappers" : [ {
      "id" : "5427d1b4-ba79-412a-b23c-da640a98980c",
      "name" : "phone number",
      "protocol" : "openid-connect",
      "protocolMapper" : "oidc-usermodel-attribute-mapper",
      "consentRequired" : false,
      "config" : {
        "userinfo.token.claim" : "true",
        "user.attribute" : "phoneNumber",
        "id.token.claim" : "true",
        "access.token.claim" : "true",
        "claim.name" : "phone_number",
        "jsonType.label" : "String"
      }
    }, {
      "id" : "31d4a53f-6503-40e8-bd9d-79a7c46c4fbe",
      "name" : "phone number verified",
      "protocol" : "openid-connect",
      "protocolMapper" : "oidc-usermodel-attribute-mapper",
      "consentRequired" : false,
      "config" : {
        "userinfo.token.claim" : "true",
        "user.attribute" : "phoneNumberVerified",
        "id.token.claim" : "true",
        "access.token.claim" : "true",
        "claim.name" : "phone_number_verified",
        "jsonType.label" : "boolean"
      }
    } ]
  }, {
    "id" : "5921a9e9-7fec-4471-95e3-dd96eebdec58",
    "name" : "profile",
    "description" : "OpenID Connect built-in scope: profile",
    "protocol" : "openid-connect",
    "attributes" : {
      "include.in.token.scope" : "true",
      "display.on.consent.screen" : "true",
      "consent.screen.text" : "${profileScopeConsentText}"
    },
    "protocolMappers" : [ {
      "id" : "4fa92092-ee0d-4dc7-a63b-1e3b02d35ebb",
      "name" : "zoneinfo",
      "protocol" : "openid-connect",
      "protocolMapper" : "oidc-usermodel-attribute-mapper",
      "consentRequired" : false,
      "config" : {
        "userinfo.token.claim" : "true",
        "user.attribute" : "zoneinfo",
        "id.token.claim" : "true",
        "access.token.claim" : "true",
        "claim.name" : "zoneinfo",
        "jsonType.label" : "String"
      }
    }, {
      "id" : "1a5cc2e2-c983-4150-8583-23a7f5c826bf",
      "name" : "family name",
      "protocol" : "openid-connect",
      "protocolMapper" : "oidc-usermodel-property-mapper",
      "consentRequired" : false,
      "config" : {
        "userinfo.token.claim" : "true",
        "user.attribute" : "lastName",
        "id.token.claim" : "true",
        "access.token.claim" : "true",
        "claim.name" : "family_name",
        "jsonType.label" : "String"
      }
    }, {
      "id" : "67931f77-722a-492d-b581-a953e26b7d44",
      "name" : "full name",
      "protocol" : "openid-connect",
      "protocolMapper" : "oidc-full-name-mapper",
      "consentRequired" : false,
      "config" : {
        "id.token.claim" : "true",
        "access.token.claim" : "true",
        "userinfo.token.claim" : "true"
      }
    }, {
      "id" : "10f6ac36-3a63-4e1c-ac69-c095588f5967",
      "name" : "locale",
      "protocol" : "openid-connect",
      "protocolMapper" : "oidc-usermodel-attribute-mapper",
      "consentRequired" : false,
      "config" : {
        "userinfo.token.claim" : "true",
        "user.attribute" : "locale",
        "id.token.claim" : "true",
        "access.token.claim" : "true",
        "claim.name" : "locale",
        "jsonType.label" : "String"
      }
    }, {
      "id" : "205d9dce-b6c8-4b1d-9c9c-fa24788651cf",
      "name" : "picture",
      "protocol" : "openid-connect",
      "protocolMapper" : "oidc-usermodel-attribute-mapper",
      "consentRequired" : false,
      "config" : {
        "userinfo.token.claim" : "true",
        "user.attribute" : "picture",
        "id.token.claim" : "true",
        "access.token.claim" : "true",
        "claim.name" : "picture",
        "jsonType.label" : "String"
      }
    }, {
      "id" : "638216c8-ea8c-40e3-9429-771e9278920e",
      "name" : "gender",
      "protocol" : "openid-connect",
      "protocolMapper" : "oidc-usermodel-attribute-mapper",
      "consentRequired" : false,
      "config" : {
        "userinfo.token.claim" : "true",
        "user.attribute" : "gender",
        "id.token.claim" : "true",
        "access.token.claim" : "true",
        "claim.name" : "gender",
        "jsonType.label" : "String"
      }
    }, {
      "id" : "39c17eae-8ea7-422c-ae21-b8876bf12184",
      "name" : "birthdate",
      "protocol" : "openid-connect",
      "protocolMapper" : "oidc-usermodel-attribute-mapper",
      "consentRequired" : false,
      "config" : {
        "userinfo.token.claim" : "true",
        "user.attribute" : "birthdate",
        "id.token.claim" : "true",
        "access.token.claim" : "true",
        "claim.name" : "birthdate",
        "jsonType.label" : "String"
      }
    }, {
      "id" : "01c559cf-94f2-46ad-b965-3b2e1db1a2a6",
      "name" : "updated at",
      "protocol" : "openid-connect",
      "protocolMapper" : "oidc-usermodel-attribute-mapper",
      "consentRequired" : false,
      "config" : {
        "userinfo.token.claim" : "true",
        "user.attribute" : "updatedAt",
        "id.token.claim" : "true",
        "access.token.claim" : "true",
        "claim.name" : "updated_at",
        "jsonType.label" : "String"
      }
    }, {
      "id" : "1693b5ab-28eb-485d-835d-2ae070ccb3ba",
      "name" : "profile",
      "protocol" : "openid-connect",
      "protocolMapper" : "oidc-usermodel-attribute-mapper",
      "consentRequired" : false,
      "config" : {
        "userinfo.token.claim" : "true",
        "user.attribute" : "profile",
        "id.token.claim" : "true",
        "access.token.claim" : "true",
        "claim.name" : "profile",
        "jsonType.label" : "String"
      }
    }, {
      "id" : "a0e08332-954c-46d2-9795-56eb31132580",
      "name" : "given name",
      "protocol" : "openid-connect",
      "protocolMapper" : "oidc-usermodel-property-mapper",
      "consentRequired" : false,
      "config" : {
        "userinfo.token.claim" : "true",
        "user.attribute" : "firstName",
        "id.token.claim" : "true",
        "access.token.claim" : "true",
        "claim.name" : "given_name",
        "jsonType.label" : "String"
      }
    }, {
      "id" : "cea0cd9c-d085-4d19-acc3-4bb41c891b68",
      "name" : "nickname",
      "protocol" : "openid-connect",
      "protocolMapper" : "oidc-usermodel-attribute-mapper",
      "consentRequired" : false,
      "config" : {
        "userinfo.token.claim" : "true",
        "user.attribute" : "nickname",
        "id.token.claim" : "true",
        "access.token.claim" : "true",
        "claim.name" : "nickname",
        "jsonType.label" : "String"
      }
    }, {
      "id" : "3122097d-4cba-46c2-8b3b-5d87a4cc605e",
      "name" : "middle name",
      "protocol" : "openid-connect",
      "protocolMapper" : "oidc-usermodel-attribute-mapper",
      "consentRequired" : false,
      "config" : {
        "userinfo.token.claim" : "true",
        "user.attribute" : "middleName",
        "id.token.claim" : "true",
        "access.token.claim" : "true",
        "claim.name" : "middle_name",
        "jsonType.label" : "String"
      }
    }, {
      "id" : "a3b97897-d913-4e0a-a4cf-033ce78f7d24",
      "name" : "username",
      "protocol" : "openid-connect",
      "protocolMapper" : "oidc-usermodel-property-mapper",
      "consentRequired" : false,
      "config" : {
        "userinfo.token.claim" : "true",
        "user.attribute" : "username",
        "id.token.claim" : "true",
        "access.token.claim" : "true",
        "claim.name" : "preferred_username",
        "jsonType.label" : "String"
      }
    }, {
      "id" : "a44eeb9d-410d-49c5-b0e0-5d84787627ad",
      "name" : "website",
      "protocol" : "openid-connect",
      "protocolMapper" : "oidc-usermodel-attribute-mapper",
      "consentRequired" : false,
      "config" : {
        "userinfo.token.claim" : "true",
        "user.attribute" : "website",
        "id.token.claim" : "true",
        "access.token.claim" : "true",
        "claim.name" : "website",
        "jsonType.label" : "String"
      }
    } ]
  }, {
    "id" : "651408a7-6704-4198-a60f-988821b633ea",
    "name" : "role_list",
    "description" : "SAML role list",
    "protocol" : "saml",
    "attributes" : {
      "consent.screen.text" : "${samlRoleListScopeConsentText}",
      "display.on.consent.screen" : "true"
    },
    "protocolMappers" : [ {
      "id" : "a8c56c7b-ccbc-4b01-8df5-3ecb6328755f",
      "name" : "role list",
      "protocol" : "saml",
      "protocolMapper" : "saml-role-list-mapper",
      "consentRequired" : false,
      "config" : {
        "single" : "false",
        "attribute.nameformat" : "Basic",
        "attribute.name" : "Role"
      }
    } ]
  }, {
    "id" : "13ec0fd3-e64a-4d6f-9be7-c8760f2c9d6b",
    "name" : "roles",
    "description" : "OpenID Connect scope for add user roles to the access token",
    "protocol" : "openid-connect",
    "attributes" : {
      "include.in.token.scope" : "false",
      "display.on.consent.screen" : "true",
      "consent.screen.text" : "${rolesScopeConsentText}"
    },
    "protocolMappers" : [ {
      "id" : "75e741f8-dcd5-49d2-815e-8604ec1d08a1",
      "name" : "realm roles",
      "protocol" : "openid-connect",
      "protocolMapper" : "oidc-usermodel-realm-role-mapper",
      "consentRequired" : false,
      "config" : {
        "user.attribute" : "foo",
        "access.token.claim" : "true",
        "claim.name" : "realm_access.roles",
        "jsonType.label" : "String",
        "multivalued" : "true"
      }
    }, {
      "id" : "06a2d506-4996-4a33-8c43-2cf64af6a630",
      "name" : "client roles",
      "protocol" : "openid-connect",
      "protocolMapper" : "oidc-usermodel-client-role-mapper",
      "consentRequired" : false,
      "config" : {
        "user.attribute" : "foo",
        "access.token.claim" : "true",
        "claim.name" : "resource_access.${client_id}.roles",
        "jsonType.label" : "String",
        "multivalued" : "true"
      }
    }, {
      "id" : "3c3470df-d414-4e1c-87fc-3fb3cea34b8d",
      "name" : "audience resolve",
      "protocol" : "openid-connect",
      "protocolMapper" : "oidc-audience-resolve-mapper",
      "consentRequired" : false,
      "config" : { }
    } ]
  }, {
    "id" : "d85aba25-c74b-49e3-9ccb-77b4bb16efa5",
    "name" : "web-origins",
    "description" : "OpenID Connect scope for add allowed web origins to the access token",
    "protocol" : "openid-connect",
    "attributes" : {
      "include.in.token.scope" : "false",
      "display.on.consent.screen" : "false",
      "consent.screen.text" : ""
    },
    "protocolMappers" : [ {
      "id" : "86b3f64f-1525-4500-bcbc-9b889b25f995",
      "name" : "allowed web origins",
      "protocol" : "openid-connect",
      "protocolMapper" : "oidc-allowed-origins-mapper",
      "consentRequired" : false,
      "config" : { }
    } ]
  } ],
  "defaultDefaultClientScopes" : [ "roles", "profile", "role_list", "email", "web-origins" ],
  "defaultOptionalClientScopes" : [ "phone", "address", "offline_access", "microprofile-jwt" ],
  "browserSecurityHeaders" : {
    "contentSecurityPolicyReportOnly" : "",
    "xContentTypeOptions" : "nosniff",
    "xRobotsTag" : "none",
    "xFrameOptions" : "SAMEORIGIN",
    "xXSSProtection" : "1; mode=block",
    "contentSecurityPolicy" : "frame-src 'self'; frame-ancestors 'self'; object-src 'none';",
    "strictTransportSecurity" : "max-age=31536000; includeSubDomains"
  },
  "smtpServer" : { },
  "eventsEnabled" : false,
  "eventsListeners" : [ "jboss-logging" ],
  "enabledEventTypes" : [ ],
  "adminEventsEnabled" : false,
  "adminEventsDetailsEnabled" : false,
  "components" : {
    "org.keycloak.services.clientregistration.policy.ClientRegistrationPolicy" : [ {
      "id" : "59048b39-ad0f-4d12-8c52-7cfc2c43278a",
      "name" : "Allowed Protocol Mapper Types",
      "providerId" : "allowed-protocol-mappers",
      "subType" : "authenticated",
      "subComponents" : { },
      "config" : {
        "allowed-protocol-mapper-types" : [ "saml-user-attribute-mapper", "oidc-full-name-mapper", "oidc-sha256-pairwise-sub-mapper", "saml-user-property-mapper", "saml-role-list-mapper", "oidc-address-mapper", "oidc-usermodel-attribute-mapper", "oidc-usermodel-property-mapper" ]
      }
    }, {
      "id" : "760559a6-a59f-4175-9ac5-6f3612e20129",
      "name" : "Trusted Hosts",
      "providerId" : "trusted-hosts",
      "subType" : "anonymous",
      "subComponents" : { },
      "config" : {
        "host-sending-registration-request-must-match" : [ "true" ],
        "client-uris-must-match" : [ "true" ]
      }
    }, {
      "id" : "24f4cb42-76bd-499e-812a-4e0d270c9e13",
      "name" : "Full Scope Disabled",
      "providerId" : "scope",
      "subType" : "anonymous",
      "subComponents" : { },
      "config" : { }
    }, {
      "id" : "abbfc599-480a-44ef-8e33-73a83eaab166",
      "name" : "Allowed Protocol Mapper Types",
      "providerId" : "allowed-protocol-mappers",
      "subType" : "anonymous",
      "subComponents" : { },
      "config" : {
        "allowed-protocol-mapper-types" : [ "saml-user-attribute-mapper", "oidc-sha256-pairwise-sub-mapper", "oidc-full-name-mapper", "saml-role-list-mapper", "saml-user-property-mapper", "oidc-usermodel-property-mapper", "oidc-usermodel-attribute-mapper", "oidc-address-mapper" ]
      }
    }, {
      "id" : "3c6450f0-4521-402b-a247-c8165854b1fa",
      "name" : "Allowed Client Scopes",
      "providerId" : "allowed-client-templates",
      "subType" : "anonymous",
      "subComponents" : { },
      "config" : {
        "allow-default-scopes" : [ "true" ]
      }
    }, {
      "id" : "d9b64399-744b-498e-9d35-f68b1582bd7d",
      "name" : "Consent Required",
      "providerId" : "consent-required",
      "subType" : "anonymous",
      "subComponents" : { },
      "config" : { }
    }, {
      "id" : "22f15f1f-3116-4348-a1e5-fc0d7576452a",
      "name" : "Max Clients Limit",
      "providerId" : "max-clients",
      "subType" : "anonymous",
      "subComponents" : { },
      "config" : {
        "max-clients" : [ "200" ]
      }
    }, {
      "id" : "4ad7b291-ddbb-4674-8c3d-ab8fd76d4168",
      "name" : "Allowed Client Scopes",
      "providerId" : "allowed-client-templates",
      "subType" : "authenticated",
      "subComponents" : { },
      "config" : {
        "allow-default-scopes" : [ "true" ]
      }
    } ],
    "org.keycloak.keys.KeyProvider" : [ {
      "id" : "f71cc325-9907-4d27-a0e6-88fca7450e5e",
      "name" : "aes-generated",
      "providerId" : "aes-generated",
      "subComponents" : { },
      "config" : {
        "kid" : [ "6c7d982e-372f-49c6-a4f3-5c451fb85eca" ],
        "secret" : [ "yH6M3W7aOgh2_cKJ0srWbw" ],
        "priority" : [ "100" ]
      }
    }, {
      "id" : "7b50d0ab-dda5-4624-aa42-b4b397724ce1",
      "name" : "hmac-generated",
      "providerId" : "hmac-generated",
      "subComponents" : { },
      "config" : {
        "kid" : [ "587f0fb5-845d-4b45-87a0-84145092aaef" ],
        "secret" : [ "PuH8Lxh9GeNfGJRDk34SWIlBDdrJpC3U3SfcxqqQtlIf2DBzRKUu8VbDVrmMN5b5CoPsJhrQ2SVb-iE9Lzsb3A" ],
        "priority" : [ "100" ],
        "algorithm" : [ "HS256" ]
      }
    }, {
      "id" : "547c1c71-9f97-4e12-801b-ed5c2cc61bba",
      "name" : "rsa-generated",
      "providerId" : "rsa-generated",
      "subComponents" : { },
      "config" : {
        "privateKey" : [ "MIIEowIBAAKCAQEAjdo2HZ5ruNnIbkSeAfFYpbPvJw3vtz/VuKJerC4mUXYd7qRMhs3VLJZ3mFyeCuO8W81vkGrFiC9KQnX2lHj2dtA/RWEJw5bpz+JdOFr5pvXg0lQ0sa+hro9afWDygTU4FmLsEi5z98847TbH178RT6n7+JVqZ9jYU9rSpwVTC8E/4yxSuStmhGCcAkZ6dGhHNBdvGUgwxKYj7dYLRJiI+nilIdKuxPzxI/YZxZnXBHDdbNXJgDymTQPut99OnBxeZbH38CJ1MNo3VdV1fzOMGUHe+vn/EOD5E+pXC8PwvJnWU+XHUTFVZeyIXehh3pYLUsq/6bZ1MYsEaFIhznOkwwIDAQABAoIBAHB+64fVyUxRurhoRn737fuLlU/9p2xGfbHtYvNdrhnQeLB3MBGAT10K/1Gfsd6k+Q49AAsiAgGcr2HBt4nL3HohcOwOpvWsS0UIGjHFRFP6jw9+pEN+K9UJ7xObvPZnRFHMpbdNi76tYlINrbMV3h61ihR8OmSc/gKSeZjnihK5OkaNnlqGRaBM/koI+iAxUHuJPnBLBZmD4T8eIfE4S2TvUeVeQogI9Muvnb9tIPJ5XyP9iXWLdRjnek/+wTdxHHZuo06Tc0bMjRaTHiF6K9ntOM2EmQb6bS2J47zgzRLNFE22BWH7RJq659EzElkOn0C0k7dWDTur/3Lpx1+zxJECgYEA8t+J3J+9oGTFmY2VPH05Yr/R/iVDOyIOlO1CmgonOQ3KPhbfNBB3aTAJP20LOZChN4JoWuiZJg4UwzXOeY9DvdDkPO0YLlSjPAIwJNk+xcxFcp5hqMUul2db+cgEY8zp0Wg9kFOq3JmJjK4+1+fgsVnOB+B08ZYI6bZzsUVKzucCgYEAlYTrsxs6fQua0cvZNQPYNZzwF3LVwPBl/ntkdRBE3HGyZeCAhIj7e9pAUusCPsQJaCmW2UEmywD/aIxGrBkojzTKItshM3PN1PYKL8W0Zq+H67uF5KfdvsbabZWHfP/LGCpoKF8Ov7JVPPqGrZ03Z2SheeLZAtNeHN4OB1u9i8UCgYATkS7qN3Rvl67T0DRVy0D0U7/3Wckw2m2SUgsrneXLEvFYTz9sUmdMcjJMidx9pslWT4tYx6SPDFNf5tXbtU8f29SHlBJ+qRL9oq9+SIJmLS7rLRdxIXG/gPRIC3VPFRNBa8SJ/DOn0jbivqcRffz8TN/sgojpbc0KB0kK3ypHwQKBgCKVCcb1R0PgyUA4+9YNO5a647UotFPZxl1jwMpqpuKt0WtKz67X2AK/ah1DidNmmB5lcCRzsztE0c4mk7n+X6kvtoj1UeqKoFLfTV/bRGxzsOZPCxrl0J3tdFvgN+QrbZf7Rvf/dHPWFWzzLO8+66+YUNjWJQdIR/45Rdlh2KdZAoGBAMfF3ir+fe3KdQ6hAf9QyrLxJ5l+GO+IgtxXGbon7eeJBIZHHdMeDy4pC7DMcI214BmIntbyY+xS+gI3oM26EJUVmrZ6tkyIDFsCHm9rcXG9ogvffzQWM1Wqzm27hR/3s+EPWW9AOcIimiFV1UPp/mLjnrCuq58V2aJS/TT14oLe" ],
        "certificate" : [ "MIICmzCCAYMCBgFygL/j4DANBgkqhkiG9w0BAQsFADARMQ8wDQYDVQQDDAZtYXN0ZXIwHhcNMjAwNjA0MTkxMDU4WhcNMzAwNjA0MTkxMjM4WjARMQ8wDQYDVQQDDAZtYXN0ZXIwggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQCN2jYdnmu42chuRJ4B8Vils+8nDe+3P9W4ol6sLiZRdh3upEyGzdUslneYXJ4K47xbzW+QasWIL0pCdfaUePZ20D9FYQnDlunP4l04Wvmm9eDSVDSxr6Guj1p9YPKBNTgWYuwSLnP3zzjtNsfXvxFPqfv4lWpn2NhT2tKnBVMLwT/jLFK5K2aEYJwCRnp0aEc0F28ZSDDEpiPt1gtEmIj6eKUh0q7E/PEj9hnFmdcEcN1s1cmAPKZNA+63306cHF5lsffwInUw2jdV1XV/M4wZQd76+f8Q4PkT6lcLw/C8mdZT5cdRMVVl7Ihd6GHelgtSyr/ptnUxiwRoUiHOc6TDAgMBAAEwDQYJKoZIhvcNAQELBQADggEBAIAqydMYxa51kNEyfXyR2kStlglE4LDeLBLHDABeBPE0eN2awoH/mw3kXS4OA/C0e3c7bAwViOzOVERGeUNiBvP5rL1Amuu97nwFcxhkTaJH4ZwCGkxceaIo9LNDpAEesqHLQSdplFXIA4TbEFoKMem4k31KVU7i9/rUesrSRmxLptIOK7LLvRMYiY/t7tdAvoZAtoliuQlFKQywEuxXQrCkcoVEAARABWGt0rsWC2xK0tVxHRIrENwvMp/aUYd17sZ0403aaS9dlvfQ63ExnaHd+++RJtPku8P220Tw27YVmFAwzJgS0aUpEaDsgRNz6OMSyxEg/n7eKK08aU3szwQ=" ],
        "priority" : [ "100" ]
      }
    } ]
  },
  "internationalizationEnabled" : false,
  "supportedLocales" : [ ],
  "authenticationFlows" : [ {
    "id" : "3253f9b7-905d-4458-ad8a-8ada5e16d195",
    "alias" : "Account verification options",
    "description" : "Method with which to verity the existing account",
    "providerId" : "basic-flow",
    "topLevel" : false,
    "builtIn" : true,
    "authenticationExecutions" : [ {
      "authenticator" : "idp-email-verification",
      "requirement" : "ALTERNATIVE",
      "priority" : 10,
      "userSetupAllowed" : false,
      "autheticatorFlow" : false
    }, {
      "requirement" : "ALTERNATIVE",
      "priority" : 20,
      "flowAlias" : "Verify Existing Account by Re-authentication",
      "userSetupAllowed" : false,
      "autheticatorFlow" : true
    } ]
  }, {
    "id" : "75bd854e-ab99-46f1-90ed-a8bfc1559558",
    "alias" : "Authentication Options",
    "description" : "Authentication options.",
    "providerId" : "basic-flow",
    "topLevel" : false,
    "builtIn" : true,
    "authenticationExecutions" : [ {
      "authenticator" : "basic-auth",
      "requirement" : "REQUIRED",
      "priority" : 10,
      "userSetupAllowed" : false,
      "autheticatorFlow" : false
    }, {
      "authenticator" : "basic-auth-otp",
      "requirement" : "DISABLED",
      "priority" : 20,
      "userSetupAllowed" : false,
      "autheticatorFlow" : false
    }, {
      "authenticator" : "auth-spnego",
      "requirement" : "DISABLED",
      "priority" : 30,
      "userSetupAllowed" : false,
      "autheticatorFlow" : false
    } ]
  }, {
    "id" : "9b0e6cce-62c5-4fb6-a48d-e07c950e38c3",
    "alias" : "Browser - Conditional OTP",
    "description" : "Flow to determine if the OTP is required for the authentication",
    "providerId" : "basic-flow",
    "topLevel" : false,
    "builtIn" : true,
    "authenticationExecutions" : [ {
      "authenticator" : "conditional-user-configured",
      "requirement" : "REQUIRED",
      "priority" : 10,
      "userSetupAllowed" : false,
      "autheticatorFlow" : false
    }, {
      "authenticator" : "auth-otp-form",
      "requirement" : "REQUIRED",
      "priority" : 20,
      "userSetupAllowed" : false,
      "autheticatorFlow" : false
    } ]
  }, {
    "id" : "1c26fd14-ac06-4dc1-bdd8-8c34c1b41720",
    "alias" : "Direct Grant - Conditional OTP",
    "description" : "Flow to determine if the OTP is required for the authentication",
    "providerId" : "basic-flow",
    "topLevel" : false,
    "builtIn" : true,
    "authenticationExecutions" : [ {
      "authenticator" : "conditional-user-configured",
      "requirement" : "REQUIRED",
      "priority" : 10,
      "userSetupAllowed" : false,
      "autheticatorFlow" : false
    }, {
      "authenticator" : "direct-grant-validate-otp",
      "requirement" : "REQUIRED",
      "priority" : 20,
      "userSetupAllowed" : false,
      "autheticatorFlow" : false
    } ]
  }, {
    "id" : "254f7549-51ec-4565-a736-35c07b6e25f0",
    "alias" : "First broker login - Conditional OTP",
    "description" : "Flow to determine if the OTP is required for the authentication",
    "providerId" : "basic-flow",
    "topLevel" : false,
    "builtIn" : true,
    "authenticationExecutions" : [ {
      "authenticator" : "conditional-user-configured",
      "requirement" : "REQUIRED",
      "priority" : 10,
      "userSetupAllowed" : false,
      "autheticatorFlow" : false
    }, {
      "authenticator" : "auth-otp-form",
      "requirement" : "REQUIRED",
      "priority" : 20,
      "userSetupAllowed" : false,
      "autheticatorFlow" : false
    } ]
  }, {
    "id" : "b2413da8-3de9-4bfe-b77e-643fd1964c8f",
    "alias" : "Handle Existing Account",
    "description" : "Handle what to do if there is existing account with same email/username like authenticated identity provider",
    "providerId" : "basic-flow",
    "topLevel" : false,
    "builtIn" : true,
    "authenticationExecutions" : [ {
      "authenticator" : "idp-confirm-link",
      "requirement" : "REQUIRED",
      "priority" : 10,
      "userSetupAllowed" : false,
      "autheticatorFlow" : false
    }, {
      "requirement" : "REQUIRED",
      "priority" : 20,
      "flowAlias" : "Account verification options",
      "userSetupAllowed" : false,
      "autheticatorFlow" : true
    } ]
  }, {
    "id" : "f8392bfb-8dce-4a16-8af1-b2a4d1a0a273",
    "alias" : "Reset - Conditional OTP",
    "description" : "Flow to determine if the OTP should be reset or not. Set to REQUIRED to force.",
    "providerId" : "basic-flow",
    "topLevel" : false,
    "builtIn" : true,
    "authenticationExecutions" : [ {
      "authenticator" : "conditional-user-configured",
      "requirement" : "REQUIRED",
      "priority" : 10,
      "userSetupAllowed" : false,
      "autheticatorFlow" : false
    }, {
      "authenticator" : "reset-otp",
      "requirement" : "REQUIRED",
      "priority" : 20,
      "userSetupAllowed" : false,
      "autheticatorFlow" : false
    } ]
  }, {
    "id" : "fb69c297-b26e-44fa-aabd-d7b40eec3cd3",
    "alias" : "User creation or linking",
    "description" : "Flow for the existing/non-existing user alternatives",
    "providerId" : "basic-flow",
    "topLevel" : false,
    "builtIn" : true,
    "authenticationExecutions" : [ {
      "authenticatorConfig" : "create unique user config",
      "authenticator" : "idp-create-user-if-unique",
      "requirement" : "ALTERNATIVE",
      "priority" : 10,
      "userSetupAllowed" : false,
      "autheticatorFlow" : false
    }, {
      "requirement" : "ALTERNATIVE",
      "priority" : 20,
      "flowAlias" : "Handle Existing Account",
      "userSetupAllowed" : false,
      "autheticatorFlow" : true
    } ]
  }, {
    "id" : "de3a41a9-7018-4931-9c4d-d04f9501b2ce",
    "alias" : "Verify Existing Account by Re-authentication",
    "description" : "Reauthentication of existing account",
    "providerId" : "basic-flow",
    "topLevel" : false,
    "builtIn" : true,
    "authenticationExecutions" : [ {
      "authenticator" : "idp-username-password-form",
      "requirement" : "REQUIRED",
      "priority" : 10,
      "userSetupAllowed" : false,
      "autheticatorFlow" : false
    }, {
      "requirement" : "CONDITIONAL",
      "priority" : 20,
      "flowAlias" : "First broker login - Conditional OTP",
      "userSetupAllowed" : false,
      "autheticatorFlow" : true
    } ]
  }, {
    "id" : "6526b0d1-b48e-46c6-bb08-11ebcf458def",
    "alias" : "browser",
    "description" : "browser based authentication",
    "providerId" : "basic-flow",
    "topLevel" : true,
    "builtIn" : true,
    "authenticationExecutions" : [ {
      "authenticator" : "auth-cookie",
      "requirement" : "ALTERNATIVE",
      "priority" : 10,
      "userSetupAllowed" : false,
      "autheticatorFlow" : false
    }, {
      "authenticator" : "auth-spnego",
      "requirement" : "DISABLED",
      "priority" : 20,
      "userSetupAllowed" : false,
      "autheticatorFlow" : false
    }, {
      "authenticator" : "identity-provider-redirector",
      "requirement" : "ALTERNATIVE",
      "priority" : 25,
      "userSetupAllowed" : false,
      "autheticatorFlow" : false
    }, {
      "requirement" : "ALTERNATIVE",
      "priority" : 30,
      "flowAlias" : "forms",
      "userSetupAllowed" : false,
      "autheticatorFlow" : true
    } ]
  }, {
    "id" : "92a653ba-8f2d-4283-8354-ca55f9d89181",
    "alias" : "clients",
    "description" : "Base authentication for clients",
    "providerId" : "client-flow",
    "topLevel" : true,
    "builtIn" : true,
    "authenticationExecutions" : [ {
      "authenticator" : "client-secret",
      "requirement" : "ALTERNATIVE",
      "priority" : 10,
      "userSetupAllowed" : false,
      "autheticatorFlow" : false
    }, {
      "authenticator" : "client-jwt",
      "requirement" : "ALTERNATIVE",
      "priority" : 20,
      "userSetupAllowed" : false,
      "autheticatorFlow" : false
    }, {
      "authenticator" : "client-secret-jwt",
      "requirement" : "ALTERNATIVE",
      "priority" : 30,
      "userSetupAllowed" : false,
      "autheticatorFlow" : false
    }, {
      "authenticator" : "client-x509",
      "requirement" : "ALTERNATIVE",
      "priority" : 40,
      "userSetupAllowed" : false,
      "autheticatorFlow" : false
    } ]
  }, {
    "id" : "e365be39-78db-46f0-b2e8-4e7001c2f5d0",
    "alias" : "direct grant",
    "description" : "OpenID Connect Resource Owner Grant",
    "providerId" : "basic-flow",
    "topLevel" : true,
    "builtIn" : true,
    "authenticationExecutions" : [ {
      "authenticator" : "direct-grant-validate-username",
      "requirement" : "REQUIRED",
      "priority" : 10,
      "userSetupAllowed" : false,
      "autheticatorFlow" : false
    }, {
      "authenticator" : "direct-grant-validate-password",
      "requirement" : "REQUIRED",
      "priority" : 20,
      "userSetupAllowed" : false,
      "autheticatorFlow" : false
    }, {
      "requirement" : "CONDITIONAL",
      "priority" : 30,
      "flowAlias" : "Direct Grant - Conditional OTP",
      "userSetupAllowed" : false,
      "autheticatorFlow" : true
    } ]
  }, {
    "id" : "dd61caf5-a40f-48b7-9e8c-a1f3b67041dd",
    "alias" : "docker auth",
    "description" : "Used by Docker clients to authenticate against the IDP",
    "providerId" : "basic-flow",
    "topLevel" : true,
    "builtIn" : true,
    "authenticationExecutions" : [ {
      "authenticator" : "docker-http-basic-authenticator",
      "requirement" : "REQUIRED",
      "priority" : 10,
      "userSetupAllowed" : false,
      "autheticatorFlow" : false
    } ]
  }, {
    "id" : "7a055643-62e1-4ac1-b126-9a8d6c299635",
    "alias" : "first broker login",
    "description" : "Actions taken after first broker login with identity provider account, which is not yet linked to any Keycloak account",
    "providerId" : "basic-flow",
    "topLevel" : true,
    "builtIn" : true,
    "authenticationExecutions" : [ {
      "authenticatorConfig" : "review profile config",
      "authenticator" : "idp-review-profile",
      "requirement" : "REQUIRED",
      "priority" : 10,
      "userSetupAllowed" : false,
      "autheticatorFlow" : false
    }, {
      "requirement" : "REQUIRED",
      "priority" : 20,
      "flowAlias" : "User creation or linking",
      "userSetupAllowed" : false,
      "autheticatorFlow" : true
    } ]
  }, {
    "id" : "fe8bc7ee-6e8f-436e-8336-c60fcd350843",
    "alias" : "forms",
    "description" : "Username, password, otp and other auth forms.",
    "providerId" : "basic-flow",
    "topLevel" : false,
    "builtIn" : true,
    "authenticationExecutions" : [ {
      "authenticator" : "auth-username-password-form",
      "requirement" : "REQUIRED",
      "priority" : 10,
      "userSetupAllowed" : false,
      "autheticatorFlow" : false
    }, {
      "requirement" : "CONDITIONAL",
      "priority" : 20,
      "flowAlias" : "Browser - Conditional OTP",
      "userSetupAllowed" : false,
      "autheticatorFlow" : true
    } ]
  }, {
    "id" : "3646f08e-ab70-415b-a701-6ed2e2d214c9",
    "alias" : "http challenge",
    "description" : "An authentication flow based on challenge-response HTTP Authentication Schemes",
    "providerId" : "basic-flow",
    "topLevel" : true,
    "builtIn" : true,
    "authenticationExecutions" : [ {
      "authenticator" : "no-cookie-redirect",
      "requirement" : "REQUIRED",
      "priority" : 10,
      "userSetupAllowed" : false,
      "autheticatorFlow" : false
    }, {
      "requirement" : "REQUIRED",
      "priority" : 20,
      "flowAlias" : "Authentication Options",
      "userSetupAllowed" : false,
      "autheticatorFlow" : true
    } ]
  }, {
    "id" : "04176530-0972-47ad-83df-19d8534caac2",
    "alias" : "registration",
    "description" : "registration flow",
    "providerId" : "basic-flow",
    "topLevel" : true,
    "builtIn" : true,
    "authenticationExecutions" : [ {
      "authenticator" : "registration-page-form",
      "requirement" : "REQUIRED",
      "priority" : 10,
      "flowAlias" : "registration form",
      "userSetupAllowed" : false,
      "autheticatorFlow" : true
    } ]
  }, {
    "id" : "fa0ed569-6746-439e-b07e-89f7ed918c07",
    "alias" : "registration form",
    "description" : "registration form",
    "providerId" : "form-flow",
    "topLevel" : false,
    "builtIn" : true,
    "authenticationExecutions" : [ {
      "authenticator" : "registration-user-creation",
      "requirement" : "REQUIRED",
      "priority" : 20,
      "userSetupAllowed" : false,
      "autheticatorFlow" : false
    }, {
      "authenticator" : "registration-profile-action",
      "requirement" : "REQUIRED",
      "priority" : 40,
      "userSetupAllowed" : false,
      "autheticatorFlow" : false
    }, {
      "authenticator" : "registration-password-action",
      "requirement" : "REQUIRED",
      "priority" : 50,
      "userSetupAllowed" : false,
      "autheticatorFlow" : false
    }, {
      "authenticator" : "registration-recaptcha-action",
      "requirement" : "DISABLED",
      "priority" : 60,
      "userSetupAllowed" : false,
      "autheticatorFlow" : false
    } ]
  }, {
    "id" : "03680917-28f3-4ccd-bdf6-4a516f7c0018",
    "alias" : "reset credentials",
    "description" : "Reset credentials for a user if they forgot their password or something",
    "providerId" : "basic-flow",
    "topLevel" : true,
    "builtIn" : true,
    "authenticationExecutions" : [ {
      "authenticator" : "reset-credentials-choose-user",
      "requirement" : "REQUIRED",
      "priority" : 10,
      "userSetupAllowed" : false,
      "autheticatorFlow" : false
    }, {
      "authenticator" : "reset-credential-email",
      "requirement" : "REQUIRED",
      "priority" : 20,
      "userSetupAllowed" : false,
      "autheticatorFlow" : false
    }, {
      "authenticator" : "reset-password",
      "requirement" : "REQUIRED",
      "priority" : 30,
      "userSetupAllowed" : false,
      "autheticatorFlow" : false
    }, {
      "requirement" : "CONDITIONAL",
      "priority" : 40,
      "flowAlias" : "Reset - Conditional OTP",
      "userSetupAllowed" : false,
      "autheticatorFlow" : true
    } ]
  }, {
    "id" : "19a9d9aa-2d2b-4701-807f-c384ab921c7e",
    "alias" : "saml ecp",
    "description" : "SAML ECP Profile Authentication Flow",
    "providerId" : "basic-flow",
    "topLevel" : true,
    "builtIn" : true,
    "authenticationExecutions" : [ {
      "authenticator" : "http-basic-authenticator",
      "requirement" : "REQUIRED",
      "priority" : 10,
      "userSetupAllowed" : false,
      "autheticatorFlow" : false
    } ]
  } ],
  "authenticatorConfig" : [ {
    "id" : "534f01f4-45b3-43a0-91d1-238860cc126d",
    "alias" : "create unique user config",
    "config" : {
      "require.password.update.after.registration" : "false"
    }
  }, {
    "id" : "65bb9337-9633-4a21-8f6f-1d4129f664ac",
    "alias" : "review profile config",
    "config" : {
      "update.profile.on.first.login" : "missing"
    }
  } ],
  "requiredActions" : [ {
    "alias" : "CONFIGURE_TOTP",
    "name" : "Configure OTP",
    "providerId" : "CONFIGURE_TOTP",
    "enabled" : true,
    "defaultAction" : false,
    "priority" : 10,
    "config" : { }
  }, {
    "alias" : "terms_and_conditions",
    "name" : "Terms and Conditions",
    "providerId" : "terms_and_conditions",
    "enabled" : false,
    "defaultAction" : false,
    "priority" : 20,
    "config" : { }
  }, {
    "alias" : "UPDATE_PASSWORD",
    "name" : "Update Password",
    "providerId" : "UPDATE_PASSWORD",
    "enabled" : true,
    "defaultAction" : false,
    "priority" : 30,
    "config" : { }
  }, {
    "alias" : "UPDATE_PROFILE",
    "name" : "Update Profile",
    "providerId" : "UPDATE_PROFILE",
    "enabled" : true,
    "defaultAction" : false,
    "priority" : 40,
    "config" : { }
  }, {
    "alias" : "VERIFY_EMAIL",
    "name" : "Verify Email",
    "providerId" : "VERIFY_EMAIL",
    "enabled" : true,
    "defaultAction" : false,
    "priority" : 50,
    "config" : { }
  }, {
    "alias" : "update_user_locale",
    "name" : "Update User Locale",
    "providerId" : "update_user_locale",
    "enabled" : true,
    "defaultAction" : false,
    "priority" : 1000,
    "config" : { }
  } ],
  "browserFlow" : "browser",
  "registrationFlow" : "registration",
  "directGrantFlow" : "direct grant",
  "resetCredentialsFlow" : "reset credentials",
  "clientAuthenticationFlow" : "clients",
  "dockerAuthenticationFlow" : "docker auth",
  "attributes" : { },
  "keycloakVersion" : "10.0.0",
  "userManagedAccessAllowed" : false
}
EOF


cat << 'EOF' > /${ADMIN_USER}/traefik/volume/keycloak/config/master-users-0.json
{
  "realm" : "master",
  "users" : [ {
EOF

echo "    \"id\" : \"$(uuidgen)\"," >> /${ADMIN_USER}/traefik/volume/keycloak/config/master-users-0.json

cat << 'EOF' >> /${ADMIN_USER}/traefik/volume/keycloak/config/master-users-0.json
    "createdTimestamp" : 1591297959169,
EOF
echo "    \"username\" : \"${ADMIN_USER}@${DOMAIN_NAME}\"," >> /${ADMIN_USER}/traefik/volume/keycloak/config/master-users-0.json
echo "    \"email\" : \"${ADMIN_USER}@${DOMAIN_NAME}\"," >> /${ADMIN_USER}/traefik/volume/keycloak/config/master-users-0.json

cat << 'EOF' >> /${ADMIN_USER}/traefik/volume/keycloak/config/master-users-0.json
    "enabled" : true,
    "totp" : false,
    "emailVerified" : true,
    "credentials" : [ {
      "id" : "a1a06ecd-fdc0-4e67-92cd-2da22d724e32",
      "type" : "password",
      "createdDate" : 1591297959315,
EOF

#from passlib.hash import pbkdf2_sha256
#pbkdf2_sha256.hash("password", rounds=227500, salt='')
cat << 'EOF' >> /${ADMIN_USER}/traefik/volume/keycloak/config/master-users-0.json
      "secretData" : "{\"value\":\"6rt5zuqHVHopvd0FTFE0CYadXTtzY0mDY2BrqnNQGS51/7DfMJeGgj0roNnGMGvDv30imErNmiSOYl+cL9jiIA==\",\"salt\":\"LI0kqr09JB7J9wvr2Hxzzg==\"}",
      "credentialData" : "{\"hashIterations\":27500,\"algorithm\":\"pbkdf2-sha256\"}"
    } ],
    "disableableCredentialTypes" : [ ],
    "requiredActions" : [ ],
    "realmRoles" : [ "offline_access", "admin", "uma_authorization" ],
    "clientRoles" : {
      "account" : [ "view-profile", "manage-account" ]
    },
    "notBefore" : 0,
    "groups" : [ ]
  } ]
}
EOF

(cd /${ADMIN_USER}/traefik && docker compose up -d)
}
function deploy_portainer() {
mkdir -p /${ADMIN_USER}/portainer/
cat << EOF > /${ADMIN_USER}/portainer/docker-compose.yml
version: "3"

networks:
  default:
  traefik_default:
    external: true

services:
  portainer:
    image: portainer/portainer-ce:2.11.1
    restart: unless-stopped
    stdin_open: true
    networks:
      - default
      - traefik_default
    ports:
      - "127.0.0.1::9000"
    labels:
      - flame.type=application # "app" works too
      - flame.name=Portainer
      - flame.url=https://portainer.${DOMAIN_NAME}
      - "traefik.docker.network=traefik_default"
      - "traefik.http.services.portainer.loadbalancer.server.port=9000"
      - "traefik.http.routers.portainer.rule=Host(\`portainer.${DOMAIN_NAME}\`)"
      - "traefik.http.routers.portainer.entryPoints=websecure"
      - "traefik.http.routers.portainer.tls=true"
    volumes:
      - /${ADMIN_USER}/portainer/volume/portainer/data:/data
      - /var/run/docker.sock:/var/run/docker.sock
EOF

(cd /${ADMIN_USER}/portainer && docker compose up -d)
}
