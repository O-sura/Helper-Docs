# <center>APIM Setup for APIM-Common-Agent + KGW</center>

- Previously the gateway was able to communicate with the APIM CP without requiring any cert validation. But with the envoy integration, proper TLS verification is mandatory or else all the requests made from the gateway to the CP will fail eventually.

#### To configure the APIM properly
1. Download the relevant APIM ACP pack.

2. Create a new keystore using the APIM official guide([Click here for the guide](https://apim.docs.wso2.com/en/latest/install-and-setup/setup/security/configuring-keystores/keystore-basics/creating-new-keystores/#creating-a-keystore-using-a-new-certificate)). 

> When generating the keystore, make sure to add the exact jwks endpoint host as the "CN"

3. In the same guide, there is a step for adding the keystore to the trustore. Using that, add the newly generate keystore to the truststore.

4. Using the keystore file, generate the ca.crt, tls.crt and tls.key(public and private keys). These are required for creating the secret once we are installing the agent.

5. Using the dockerfile provided in the docker-apim, create a new docker image using the downloaded and modified pack which includes the newly added keystore(Modify the dockerfile to use that local pack instead of downloading it from the releases). And then push the docker image to a personal docker hub.

6. In the helm chart, modify the image name and sha to use the one in the personal dockerhub. Also change the cert info to the new .jks which was created earlier.
> Sample [values.yaml](https://raw.githubusercontent.com/O-sura/JunkYard/refs/heads/main/apim-4.6.0-alpha-values.yaml)

7. In the agent repo, inside the agent-ca-certificate.yaml, change the ca.crt, tls.crt and tls.key contents with relevant once which was generated earlier.
> Note: Make sure to paste them in base64 encoded format.

By doing this, the agent will create the relevant secret inside the dataplane namespace. Also when a keymanager is added, it will create a backend CR and a backendTLSPolicy CR for it which refers to the secret created. And once a request comes in and when the gateway tries to establish a tls communication, it will use the created BackendTLS and the secret to make the required request.