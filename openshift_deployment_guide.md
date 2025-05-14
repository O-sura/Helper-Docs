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
1. Starting from v4.5.0, each component has a separate Docker image (All-in-one, Control-plane, Gateway, Traffic-manager).
2. These Docker images do not contain any database connectors; therefore, we need to build custom Docker images based on each Docker image in order to make the deployment work with a seperate DB.
3. Download a connector which is compatible with the DB version and copy the connector while building the image

Ex:
```Dockerfile
# copy MySQL driver into the server’s lib directory
COPY --chown=${USER}:${USER_GROUP} mysql-connector.jar ${WSO2_SERVER_HOME}/repository/components/lib/
```

Sample Dockerfile should look something like this:
```Dockerfile
FROM wso2/wso2am-acp:4.5.0-rocky
ARG WSO2_SERVER_HOME=/home/wso2carbon/wso2am-acp-4.5.0
# copy MySQL connector to WSO2 server lib directory
COPY --chown=${USER}:${USER_GROUP} mysql-connector.jar ${WSO2_SERVER_HOME}/repository/components/lib/
```

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


---

## APIM ALL-IN-ONE Deployment

- Navigate to the all-in-one deployment`(helm-apim/all-in-one)` and inside the ```default_values.yaml```
  - Change the DB related info(Type,URL, Credentials, etc.) and the container image related info(repositoy, digest, etc.) if needed in the values.yaml

  - Change the `wso2.apim.configurations.security.jksSecretName` to the secret name created earlier.
<br>
- Apply the helm chart using
 ```helm install <deoplyment-name> . -f default_values.yaml```

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
