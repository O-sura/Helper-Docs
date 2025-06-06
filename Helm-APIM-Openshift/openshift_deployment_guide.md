# <center>Deploying API-M in Openshift</center>

---
## Prerequisites:

- Install Git, Helm, Openshift Client(OC) and Kubernetes client in order to run the steps provided in the following quick start guide.
<br>
- An already setup Openshift cluster.
<br>

- Install NGINX Ingress Controller. Please note that Helm resources for WSO2 product deployment patterns are compatible with NGINX Ingress Controller Git release nginx-0.22.0. Below here is a simple guide to setup ingress


##### Installing Ingress(Optional to install it in this way)

- Use the deploy.yaml file given in [Kubernetes/nginx-ingress](https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.12.2/deploy/static/provider/cloud/deploy.yaml) and remove the runAsUser and runAsGroup values given except for the runAsUser define under 'Deployment'(runAsGroup given in the Deployemnt should also be deleted).
<br>

```yaml
# custom-ingress-nginx.yaml

apiVersion: security.openshift.io/v1
kind: SecurityContextConstraints
metadata:
  name: ingress-nginx-scc
allowPrivilegedContainer: false
allowHostDirVolumePlugin: false
allowHostNetwork: false
allowHostPID: false
allowHostPorts: true
allowHostIPC: false
defaultAddCapabilities: []
requiredDropCapabilities:
  - ALL
allowedCapabilities:
  - NET_BIND_SERVICE
volumes:
  - configMap
  - secret
  - downwardAPI
  - emptyDir
  - projected
readOnlyRootFilesystem: false
runAsUser:
  type: MustRunAsNonRoot
seLinuxContext:
  type: MustRunAs
fsGroup:
  type: RunAsAny
supplementalGroups:
  type: RunAsAny
seccompProfiles:
  - "runtime/default"
users:
  - system:serviceaccount:ingress-nginx:ingress-nginx
  - system:serviceaccount:ingress-nginx:ingress-nginx-admission
priority: 10

```

<br>

- Run 
```oc apply -f ingress-custom-scc.yaml``` and then ```oc adm policy add-scc-to-user ingress-nginx-scc -z ingress-nginx,ingress-nginx-admission -n ingress-nginx```
<br>

- Now check for the pods and nginx should be up and running. Get the services to find the EXTERNAL-IP

---
## General Steps

Required Dockerfiles can be found in the [docker-apim](https://github.com/wso2/docker-apim) repo and follow the given steps below for preparing the necessary images.

#### Preparing the Docker Images

To fully comply with OpenShift’s security model especially its use of arbitrary user IDs, user has to create a custom Docker image tailored for OpenShift environments. Following are the steps required for modifying the image to ensure compatibility, including how to set group ownership to the root group (GID 0), which allows access when OpenShift assigns a random UID at runtime.

The official WSO2 Docker images run as a non-root user with a fixed UID. While that works on standard Kubernetes clusters, OpenShift often injects a random UID and restricts container privileges. To prevent permission issues, update the image to:

1. Allow group write access to required directories
2. Assign root group ownership (GID 0)

Also 

1. Starting from v4.5.0, each component has a separate Docker image (All-in-one, Control-plane, Gateway, Traffic-manager).
2. These Docker images do not contain any database connectors; therefore, we need to build custom Docker images based on each Docker image in order to make the deployment work with a seperate DB.
3. Download a connector which is compatible with the DB version and copy the connector while building the image

Ex: Following is a sample modified dockerfile created using the existing ```ubuntu/apim``` as the base image. 
```Dockerfile
FROM ubuntu:24.04

ENV LANG='en_US.UTF-8' LANGUAGE='en_US:en' LC_ALL='en_US.UTF-8'

# install dependencies
RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends tzdata curl ca-certificates fontconfig locales python-is-python3 libxml2-utils netcat-traditional unzip wget \
    && echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen \
    && locale-gen en_US.UTF-8 \
    && rm -rf /var/lib/apt/lists/*

ENV JAVA_VERSION=jdk-21.0.5+11
ENV JAVA_HOME=/opt/java/openjdk \
    PATH="/opt/java/openjdk/bin:$PATH"

# install Temurin OpenJDK 21
RUN set -eux; \
    ARCH="$(dpkg --print-architecture)"; \
    case "${ARCH}" in \
       amd64) \
         ESUM='3c654d98404c073b8a7e66bffb27f4ae3e7ede47d13284c132d40a83144bfd8c'; \
         BINARY_URL='https://github.com/adoptium/temurin21-binaries/releases/download/jdk-21.0.5%2B11/OpenJDK21U-jdk_x64_linux_hotspot_21.0.5_11.tar.gz'; \
         ;; \
       arm64) \
         ESUM='6482639ed9fd22aa2e704cc366848b1b3e1586d2bf1213869c43e80bca58fe5c'; \
         BINARY_URL='https://github.com/adoptium/temurin21-binaries/releases/download/jdk-21.0.5%2B11/OpenJDK21U-jdk_aarch64_linux_hotspot_21.0.5_11.tar.gz'; \
         ;; \
       ppc64el) \
         ESUM='3c6f4c358facfb6c19d90faf02bfe0fc7512d6b0e80ac18146bbd7e0d01deeef'; \
         BINARY_URL='https://github.com/adoptium/temurin21-binaries/releases/download/jdk-21.0.5%2B11/OpenJDK21U-jdk_ppc64le_linux_hotspot_21.0.5_11.tar.gz'; \
         ;; \
       s390x) \
         ESUM='51a7ca42cc2e8cb5f3e7a326c28912ee84ff0791a1ca66650a8c53af07510a7c'; \
         BINARY_URL='https://github.com/adoptium/temurin21-binaries/releases/download/jdk-21.0.5%2B11/OpenJDK21U-jdk_s390x_linux_hotspot_21.0.5_11.tar.gz'; \
         ;; \
       *) \
         echo "Unsupported arch: ${ARCH}"; \
         exit 1; \
         ;; \
    esac; \
    curl -LfsSo /tmp/openjdk.tar.gz ${BINARY_URL}; \
    echo "${ESUM} */tmp/openjdk.tar.gz" | sha256sum -c -; \
    mkdir -p /opt/java/openjdk; \
    cd /opt/java/openjdk; \
    tar -xf /tmp/openjdk.tar.gz --strip-components=1; \
    rm -rf /tmp/openjdk.tar.gz; \
    java -Xshare:dump;

LABEL maintainer="WSO2 Docker Maintainers <dev@wso2.org>" \
      com.wso2.docker.source="https://github.com/wso2/docker-apim/releases/tag/v4.5.0.1"

# set Docker image build arguments
# build arguments for user/group configurations
ARG USER=wso2carbon
ARG USER_ID=10001
ARG USER_GROUP=root
ARG USER_GROUP_ID=0
ARG USER_HOME=/home/${USER}
# build arguments for WSO2 product installation
ARG WSO2_SERVER_NAME=wso2am
ARG WSO2_SERVER_VERSION=4.5.0
ARG WSO2_SERVER_REPOSITORY=product-apim
ARG WSO2_SERVER=${WSO2_SERVER_NAME}-${WSO2_SERVER_VERSION}
ARG WSO2_SERVER_HOME=${USER_HOME}/${WSO2_SERVER}
ARG WSO2_SERVER_DIST_URL=https://github.com/wso2/${WSO2_SERVER_REPOSITORY}/releases/download/v${WSO2_SERVER_VERSION}/${WSO2_SERVER}.zip
# build argument for MOTD
ARG MOTD="\n\
Welcome to WSO2 Docker resources.\n\
------------------------------------ \n\
This Docker container comprises of a WSO2 product, running with its latest GA release \n\
which is under the Apache License, Version 2.0. \n\
Read more about Apache License, Version 2.0 here @ http://www.apache.org/licenses/LICENSE-2.0.\n"

# create the non-root user and group and set MOTD login message
RUN useradd --system \
        --uid   "${USER_ID}" \
        --gid   "${USER_GROUP_ID}" \   
        --create-home --home-dir "${USER_HOME}" \
        --shell /bin/bash \
        "${USER}" \
    && echo '[ ! -z "${TERM}" -a -r /etc/motd ] && cat /etc/motd' \
        >> /etc/bash.bashrc \
    && echo "${MOTD}" > /etc/motd


# copy init script to user home
COPY docker-entrypoint.sh ${USER_HOME}

RUN chown ${USER} /home/${USER}/docker-entrypoint.sh \
    && chgrp -R 0 ${USER_HOME} \
    && chmod -R g+rwX ${USER_HOME}

# install required packages

# add the WSO2 product distribution to user's home directory
RUN \
    wget -O ${WSO2_SERVER}.zip "${WSO2_SERVER_DIST_URL}" \
    && unzip -d ${USER_HOME} ${WSO2_SERVER}.zip \
    && chown ${USER} -R ${WSO2_SERVER_HOME} \
    && chgrp -R 0 ${WSO2_SERVER_HOME} \
    && chmod -R g+rwX ${WSO2_SERVER_HOME} \
    && mkdir ${USER_HOME}/wso2-tmp \
    && bash -c 'mkdir -p ${USER_HOME}/solr/{indexed-data,database}' \
    && chown ${USER} -R ${USER_HOME}/solr \
    && chgrp -R 0 ${USER_HOME}/solr \
    && chmod -R g+rwX ${USER_HOME}/solr \
    && cp -r ${WSO2_SERVER_HOME}/repository/deployment/server/synapse-configs ${USER_HOME}/wso2-tmp \
    && cp -r ${WSO2_SERVER_HOME}/repository/deployment/server/executionplans ${USER_HOME}/wso2-tmp \
    && rm -f ${WSO2_SERVER}.zip


# copy MySQL driver into the server’s lib directory
COPY --chown=${USER}:${USER_GROUP} mysql-connector.jar ${WSO2_SERVER_HOME}/repository/components/lib/

# remove unnecesary packages
RUN apt-get purge -y netcat-traditional unzip wget

# set the user and work directory
USER ${USER_ID}
WORKDIR ${USER_HOME}

# set environment variables
ENV WORKING_DIRECTORY=${USER_HOME} \
    WSO2_SERVER_HOME=${WSO2_SERVER_HOME}

# expose ports
EXPOSE 9763 9443 9999 11111 8280 8243 5672 9711 9611 9099

# initiate container and start WSO2 Carbon server
ENTRYPOINT ["/home/wso2carbon/docker-entrypoint.sh"]

```
After making the changes, build and push the image to the to the registry and make sure to change the helm charts so that it will use these modified images when deploying.

#### Create a Database
Ex: Connecting with an External MySQL DB in Azure

1. Go to the Azure dashboard and navigate to `Azure Database for MySQL servers` to create a database.
2. Disable TLS:
    1. Go to the newly created database and navigate to Settings -> Server parameters.
    2. Find `require_secure_transport`, turn it OFF, and save the changes.
    3. Find `max_connections`, set it to 340
    4. Set `transaction_isolation` to `READ-COMMITTED`
3. Login to the DB instance and Create required databases and users
```sql
CREATE DATABASE apim_db character set latin1;
CREATE DATABASE shared_db character set latin1;

CREATE USER 'apimadmin'@'%' IDENTIFIED BY 'apimadmin';
GRANT ALL ON apim_db.* TO 'apimadmin'@'%';

CREATE USER 'sharedadmin'@'%' IDENTIFIED BY 'sharedadmin';
GRANT ALL ON shared_db.* TO 'sharedadmin'@'%';

FLUSH PRIVILEGES;
```
4. Run DB scripts(These can be found inside the dbscripts folder in an APIM Pack).
```bash
mysql -h <DB-URL> -P 3306 -u sharedadmin -p -Dshared_db < './dbscripts/mysql.sql';
mysql -h <DB-URL> -P 3306 -u apimadmin -p -Dapim_db < './dbscripts/apimgt/mysql.sql';
```

#### Login to the Openshift Cluster

```bash
oc login <API server URL> -u <user> -p <password>
```

#### Create Secret
1. Before deploying the Helm chart, we need to create a Kubernetes secret containing the keystores and truststore.
2. You can find the default keystore and truststore in the following location within any of the APIM packs: `repository/resources/security/`
<br>
    > kubectl create secret generic jks-secret --from-file=wso2carbon.jks --from-file=client-truststore.jks

#### Clone helm-apim
```bash
git clone https://github.com/wso2/helm-apim.git
```

#### Change Openshift Specific settings in values.yaml

In each corresponding values.yaml file, the following changes need to be made in order to make them compatible with the openshift environment. 

> 1. runAsUser: For allowing the assignment of arbitrary UIDs, you can set runAsUser as follows kubernetes.securityContext.runAsUser=null
> 2. seLinux Support: If you need SELinux support, you can enable it by setting kubernetes.securityContext.seLinux.enabled=true
> 3. AppArmor Support: If you need AppArmor disabled, you can do so by setting kubernetes.enableAppArmor=false
> 4. ConfigMap Access: If your runtime user doesn't have execute access to ConfigMaps, you can fix it by setting kubernetes.configMaps.scripts.defaultMode=0457
> 5. Seccomp: If you need to change which seccomp (secure computing mode) profile to apply, you can do it using
kubernetes.securityContext.seccompProfile.type

Ex: 

```yaml
  securityContext:
    # -- User ID of the container
    runAsUser: null
    # -- SELinux context for the container
    seLinux:
      enabled: false
      level: ""
    # -- Seccomp profile for the container
    seccompProfile:
      # -- Seccomp profile type(RuntimeDefault, Unconfined or Localhost)
      type: RuntimeDefault
      localhostProfile: ""
  # -- Enable AppArmor profiles for the deployment
  enableAppArmor: false
  # -- Set UNIX permissions over the executable scripts
  configMaps:
    scripts:
      defaultMode: "0457"
```

---

## APIM ALL-IN-ONE Deployment

- Navigate to the all-in-one deployment`(helm-apim/all-in-one)` and inside the ```default_values.yaml```
  - Change the DB related info(Type,URL, Credentials, etc.) and the container image related info(repositoy, digest, etc.) if needed in the values.yaml

  - Change the `wso2.apim.configurations.security.jksSecretName` to the secret name created earlier.
<br>
- Apply the helm chart using
 ```helm install <deoplyment-name> . -f default_values.yaml```

[Add the helm install command which sets the values within the command itself.]

---

## Distributed Setup

Helm charts for distributed setup can be found inside the  ```apim-helm/distributed``` folder. In each chart, change the DB related info(Type,URL, Credentials, etc.) and the container image related info(repositoy, digest, etc.) if needed in the values.yaml. Apart from that, the following changes need to be made with respect to the deployment pattern that is going to be followed.

### Without Seperate KM: 

##### 1. Deploy APIM-CP
- In control-plane/values.yaml:
  - oauth2JWKSUrl should point to the apim-acp service
<br>
- Deploy helm charts
```bash
helm install apim-acp ./control-plane
```

<br>

##### 2. Deploy APIM-TM

- In traffic-manager/values.yaml

```yaml
      km:
        serviceUrl: "apim-acp-wso2am-acp-service"

      eventhub:
        serviceUrl: "apim-acp-wso2am-acp-service"
        urls:
          - "apim-acp-wso2am-acp-1-service"
          - "apim-acp-wso2am-acp-2-service"
```
- Deploy helm charts
```bash
helm install apim-tm ./traffic-manager
```

<br>

##### 3. Deploy APIM-GW

- In gateway/values.yaml:
   Point the throtlling service urls to the deployed traffic-manager service and the eventhub service urls to the deployed control-plane service.

```yaml

      km:
        serviceUrl: "apim-acp-wso2am-acp-service"

      throttling:
        serviceUrl: "apim-tm-wso2am-tm-service"
        urls:
          - "apim-tm-wso2am-tm-1-service"
          - "apim-tm-wso2am-tm-2-service"


      eventhub:
        enabled: true
        serviceUrl: "apim-acp-wso2am-acp-service"
        urls:
          - "apim-acp-wso2am-acp-1-service"
          - "apim-acp-wso2am-acp-2-service"
```

- Deploy helm charts
```bash
helm install apim-gw ./gateway
```

<br>

### Deploying With KM Seperated: 

Follow the same deployment steps above for Gateway and the Traffic Manager components. 

##### 1. For Control Plane 
Make the following changes before deploying.

In control-plane/values.yaml:
- oauth2JWKSUrl should point to the km service 
Ex: https://apim-km-wso2am-km-service:9443/oauth2/jwks
(NOTE: No need to rebuild a seperate KM image. Same image build for ACP is used for the KM as well).
<br>
- Enable the seperate key manager and point to the km service

```yaml
      km:
        enabled: true
        serviceName: "apim-km-wso2am-km-service"
        servicePort: 9443

```
##### 2. Deploy the Key-Manager

- In key-manager/values.yaml
```yaml
      eventhub:
        # -- Event hub (control plane) loadbalancer service url
        serviceUrl: "apim-acp-wso2am-acp-service"
        # -- Event hub service urls
        urls:
          - "apim-acp-wso2am-acp-1-service"
          - "apim-acp-wso2am-acp-2-service"
```

- Deploy helm charts
```bash
helm install apim-km ./key-manager
```
