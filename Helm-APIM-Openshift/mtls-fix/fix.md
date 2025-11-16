#### For Generating the Certificate Chain


- Root CA

```
# Generate Root CA private key
openssl genrsa -out rootCA.key 4096

# Create Root CA certificate (self-signed)
openssl req -x509 -new -nodes -key rootCA.key -sha256 -days 3650 -out rootCA.crt \
  -subj "/C=US/ST=CA/L=SanFrancisco/O=MyOrg/OU=RootCA/CN=RootCA"

```

- Intermediate CA

```
# Generate Intermediate CA private key
openssl genrsa -out intermediateCA.key 4096

# Generate CSR for Intermediate CA
openssl req -new -key intermediateCA.key -out intermediateCA.csr \
  -subj "/C=US/ST=CA/L=SanFrancisco/O=MyOrg/OU=IntermediateCA/CN=IntermediateCA"

# Sign Intermediate CSR with RootCA
openssl x509 -req -in intermediateCA.csr -CA rootCA.crt -CAkey rootCA.key -CAcreateserial \
  -out intermediateCA.crt -days 1825 -sha256 -extfile <(printf "basicConstraints=CA:TRUE,pathlen:0")
```

- Leaf Certificate

```
# Generate Leaf private key
openssl genrsa -out leaf.key 2048

# Generate CSR for Leaf
openssl req -new -key leaf.key -out leaf.csr \
  -subj "/C=US/ST=CA/L=SanFrancisco/O=MyOrg/OU=Leaf/CN=leaf.myorg.com"

# Sign Leaf CSR with Intermediate CA
openssl x509 -req -in leaf.csr -CA intermediateCA.crt -CAkey intermediateCA.key -CAcreateserial \
  -out leaf.crt -days 825 -sha256 -extfile <(printf "basicConstraints=CA:FALSE")
```

- Certificate Chain

```
# Build certificate chain file (Intermediate + Root)
cat intermediateCA.crt rootCA.crt > chain.crt

# Verify Leaf certificate against chain
openssl verify -CAfile chain.crt leaf.crt
```

- Create a PKCS#12 for the Leaf cert

```
openssl pkcs12 -export \
  -inkey leaf.key \
  -in leaf.crt \
  -certfile chain.crt \
  -name "leaf.myorg.com" \
  -out leaf.p12
```

- Started APIM with following config,

> [apimgt.mutual_ssl]
> enable_client_validation = true
> enable_certificate_chain_validation = true

- Created API and enabled, Mutual SSL with Mandatory and attached intermediate cert.

- Deploy and Published.

- Added leaf cert to the postman(Use the .p12).

- Invoke the API.

#### Modify the entrypoint.yaml to the following

```

    #!/bin/bash
    set -e

    # volume mounts
    config_volume=${WORKING_DIRECTORY}/wso2-config-volume
    artifact_volume=${WORKING_DIRECTORY}/wso2-artifact-volume

    # check if the WSO2 non-root user home exists
    test ! -d ${WORKING_DIRECTORY} && echo "WSO2 Docker non-root user home does not exist" && exit 1

    # check if the WSO2 product home exists
    test ! -d ${WSO2_SERVER_HOME} && echo "WSO2 Docker product home does not exist" && exit 1

    # Copying carbon_db
    if ! test -f /home/wso2carbon/solr/database/WSO2CARBON_DB.mv.db
    then
      echo "Copying WSO2CARBON_DB.mv.db" >&2
      cp ${WSO2_SERVER_HOME}/repository/database/WSO2CARBON_DB.mv.db /home/wso2carbon/solr/database/
    fi

    # copy any configuration changes mounted to config_volume
    test -d ${config_volume} && [[ "$(ls -A ${config_volume})" ]] && cp -RL ${config_volume}/* ${WSO2_SERVER_HOME}/
    # copy any artifact changes mounted to artifact_volume
    test -d ${artifact_volume} && [[ "$(ls -A ${artifact_volume})" ]] && cp -RL ${artifact_volume}/* ${WSO2_SERVER_HOME}/

    {{- if .Values.wso2.apim.secureVaultEnabled }}
    # copy internal keystore credentials to password-tmp file for cipher-tool usage
    {{- if .Values.azure.enabled }}
    cp /mnt/secrets-store/{{ .Values.azure.keyVault.secretIdentifiers.internalKeystorePassword }} ${WSO2_SERVER_HOME}/password-tmp
    {{- else if .Values.aws.enabled }}
    cp /mnt/secrets-store/{{ .Values.aws.secretsManager.secretIdentifiers.internalKeystorePassword.secretKey }} ${WSO2_SERVER_HOME}/password-tmp
    {{- else if .Values.gcp.enabled }}
    cp /mnt/secrets-store/{{ .Values.gcp.secretsManager.secret.secretName }} ${WSO2_SERVER_HOME}/password-tmp
    {{- end }}
    {{- end }}


    # OpenShift mTLS workaround: Create security-1 directory with proper permissions
    setup_openshift_mtls_workaround() {
      echo "Setting up OpenShift mTLS workaround..."
      
      local security_dir="${WSO2_SERVER_HOME}/repository/resources/security"
      local security_1_dir="${WSO2_SERVER_HOME}/repository/resources/security-1"
      local axis2_config="${WSO2_SERVER_HOME}/repository/conf/axis2/axis2.xml"
      local axis2_template="${WSO2_SERVER_HOME}/repository/resources/conf/templates/repository/conf/axis2/axis2.xml.j2"
      
      # Create security-1 directory if it doesn't exist
      if [ ! -d "${security_1_dir}" ]; then
          mkdir -p "${security_1_dir}"
          echo "Created security-1 directory: ${security_1_dir}"
      fi
      
      # Copy security files to security-1 directory
      local files_to_copy=("wso2carbon.jks" "client-truststore.jks" "sslprofiles.xml" "listenerprofiles.xml")
      
      for file in "${files_to_copy[@]}"; do
          if [ -f "${security_dir}/${file}" ]; then
              cp "${security_dir}/${file}" "${security_1_dir}/${file}"
              echo "Copied ${file} to security-1 directory"
          else
              echo "Warning: ${file} not found in security directory"
          fi
      done
      
      if [ -f "${security_dir}/client-truststore-temp.jks" ]; then
          cp "${security_dir}/client-truststore-temp.jks" "${security_1_dir}/client-truststore-temp.jks"
          echo "Copied client-truststore-temp.jks to security-1 directory"
      fi
      
      if [ -f "${security_1_dir}/sslprofiles.xml" ]; then
          sed -i 's|repository/resources/security/wso2carbon.jks|repository/resources/security-1/wso2carbon.jks|g' "${security_1_dir}/sslprofiles.xml"
          sed -i 's|repository/resources/security/client-truststore.jks|repository/resources/security-1/client-truststore.jks|g' "${security_1_dir}/sslprofiles.xml"
          sed -i 's|repository/resources/security/client-truststore-temp.jks|repository/resources/security-1/client-truststore-temp.jks|g' "${security_1_dir}/sslprofiles.xml"
          echo "Updated keystore locations in sslprofiles.xml"
      fi
      
      if [ -f "${security_1_dir}/listenerprofiles.xml" ]; then
          sed -i 's|repository/resources/security/wso2carbon.jks|repository/resources/security-1/wso2carbon.jks|g' "${security_1_dir}/listenerprofiles.xml"
          sed -i 's|repository/resources/security/client-truststore.jks|repository/resources/security-1/client-truststore.jks|g' "${security_1_dir}/listenerprofiles.xml"
          sed -i 's|repository/resources/security/client-truststore-temp.jks|repository/resources/security-1/client-truststore-temp.jks|g' "${security_1_dir}/listenerprofiles.xml"
          echo "Updated keystore locations in listenerprofiles.xml"
      fi

      # Update Axis2 TEMPLATE to read profiles from security-1
      if [ -f "${axis2_template}" ]; then
          # Helm-escaped literal Jinja token for sender filePath
          local jinja_sender='{{ "{{" }}transport.passthru_https.sender.ssl_profile.file_path{{ "}}" }}'
          # Listener filePath in template is literal
          local listener_literal='repository/resources/security/listenerprofiles.xml'

          # Listener dynamicSSLProfilesConfig -> security-1
          sed -i "s|<filePath>${listener_literal}</filePath>|<filePath>repository/resources/security-1/listenerprofiles.xml</filePath>|g" "${axis2_template}"
          # Sender dynamicSSLProfilesConfig (Jinja token) -> security-1
          sed -i "s|<filePath>${jinja_sender}</filePath>|<filePath>repository/resources/security-1/sslprofiles.xml</filePath>|g" "${axis2_template}"

          echo "Updated axis2.xml.j2 to use security-1 for dynamicSSLProfilesConfig"
      else
          echo "Warning: Axis2 template not found at ${axis2_template}"
      fi

      chgrp -R 0 "${security_1_dir}" && chmod -R g=u "${security_1_dir}"
      echo "Set group write permissions on security-1 directory"
      
      echo "OpenShift mTLS workaround setup completed successfully"


      echo "=== Permission Verification ==="
      echo "Current user: $(id)"
      echo "Security-1 directory permissions:"
      ls -la "${WSO2_SERVER_HOME}/repository/resources/" | grep security
      echo "Security-1 file permissions:"
      ls -la "${WSO2_SERVER_HOME}/repository/resources/security-1/"
      echo "Testing write access to security-1:"
      touch "${WSO2_SERVER_HOME}/repository/resources/security-1/test-write" && echo "Write test: SUCCESS" || echo "Write test: FAILED"
      rm -f "${WSO2_SERVER_HOME}/repository/resources/security-1/test-write" 2>/dev/null
      echo "=== End Permission Verification ==="
    }

    setup_openshift_mtls_workaround

    # start WSO2 Carbon server
    sh ${WSO2_SERVER_HOME}/bin/api-manager.sh "$@" {{ .Values.wso2.apim.startupArgs }}


```

> Note: Enable ssl-passthrough in ingress or else it will terminate the cert in the ingress level. For distributed setup, make sure to add the cert chain validation to the gateway toml


- Official WSO2 Guide for mtls: https://apim.docs.wso2.com/en/4.5.0/manage-apis/design/api-security/api-authentication/secure-apis-using-mutual-ssl/