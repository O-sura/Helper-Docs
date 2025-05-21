### All-in-one

```Dockerfile
FROM wso2/wso2am:4.5.0

ARG USER=wso2carbon
ARG USER_ID=10001
ARG USER_HOME=/home/${USER}
ARG WSO2_SERVER_NAME=wso2am
ARG WSO2_SERVER_VERSION=4.5.0
ARG WSO2_SERVER_REPOSITORY=product-apim
ARG WSO2_SERVER=${WSO2_SERVER_NAME}-${WSO2_SERVER_VERSION}
ARG WSO2_SERVER_HOME=${USER_HOME}/${WSO2_SERVER}

# Change direcrtory permissions
USER root
RUN chgrp -R 0 ${USER_HOME} && chmod -R g=u ${USER_HOME} \
    && chgrp -R 0 ${WSO2_SERVER_HOME} && chmod -R g=u ${WSO2_SERVER_HOME} \
    && chgrp -R 0 ${USER_HOME}/solr && chmod -R g=u ${USER_HOME}/solr
USER wso2carbon
# Copy JDBC MySQL driver
COPY mysql-connector.jar ${WSO2_SERVER_HOME}/repository/components/lib
```

### ACP

```dockerfile
FROM wso2/wso2am-acp:4.5.0

ARG USER=wso2carbon
ARG USER_ID=10001
ARG USER_HOME=/home/${USER}
ARG WSO2_SERVER_NAME=wso2am-acp
ARG WSO2_SERVER_VERSION=4.5.0
ARG WSO2_SERVER_REPOSITORY=product-apim
ARG WSO2_SERVER=${WSO2_SERVER_NAME}-${WSO2_SERVER_VERSION}
ARG WSO2_SERVER_HOME=${USER_HOME}/${WSO2_SERVER}

# Change direcrtory permissions
USER root
RUN chgrp -R 0 ${USER_HOME} && chmod -R g=u ${USER_HOME} \
    && chgrp -R 0 ${WSO2_SERVER_HOME} && chmod -R g=u ${WSO2_SERVER_HOME} \
    && chgrp -R 0 ${USER_HOME}/solr && chmod -R g=u ${USER_HOME}/solr
USER wso2carbon
# Copy JDBC MySQL driver
COPY mysql-connector.jar ${WSO2_SERVER_HOME}/repository/components/lib
```

### GW

```dockerfile
FROM wso2/wso2am-universal-gw:4.5.0

ARG USER=wso2carbon
ARG USER_ID=10001
ARG USER_HOME=/home/${USER}
ARG WSO2_SERVER_NAME=wso2am-universal-gw
ARG WSO2_SERVER_VERSION=4.5.0
ARG WSO2_SERVER_REPOSITORY=product-apim
ARG WSO2_SERVER=${WSO2_SERVER_NAME}-${WSO2_SERVER_VERSION}
ARG WSO2_SERVER_HOME=${USER_HOME}/${WSO2_SERVER}

# Change direcrtory permissions
USER root
RUN chgrp -R 0 ${USER_HOME} && chmod -R g=u ${USER_HOME} \
    && chgrp -R 0 ${WSO2_SERVER_HOME} && chmod -R g=u ${WSO2_SERVER_HOME} \
    && chgrp -R 0 ${USER_HOME}/solr && chmod -R g=u ${USER_HOME}/solr
USER wso2carbon
# Copy JDBC MySQL driver
COPY mysql-connector.jar ${WSO2_SERVER_HOME}/repository/components/lib
```

### TM
```dockerfile
FROM wso2/wso2am-tm:4.5.0

ARG USER=wso2carbon
ARG USER_ID=10001
ARG USER_HOME=/home/${USER}
ARG WSO2_SERVER_NAME=wso2am-tm
ARG WSO2_SERVER_VERSION=4.5.0
ARG WSO2_SERVER_REPOSITORY=product-apim
ARG WSO2_SERVER=${WSO2_SERVER_NAME}-${WSO2_SERVER_VERSION}
ARG WSO2_SERVER_HOME=${USER_HOME}/${WSO2_SERVER}

# Change direcrtory permissions
USER root
RUN chgrp -R 0 ${USER_HOME} && chmod -R g=u ${USER_HOME} \
    && chgrp -R 0 ${WSO2_SERVER_HOME} && chmod -R g=u ${WSO2_SERVER_HOME} \
    && chgrp -R 0 ${USER_HOME}/solr && chmod -R g=u ${USER_HOME}/solr
USER wso2carbon
# Copy JDBC MySQL driver
COPY mysql-connector.jar ${WSO2_SERVER_HOME}/repository/components/lib
```
