# <center>Configuring APIM using Puppet</center>


#### 1. Get the API KEY from puppet(Create an account for a test key)

Install puppet. To decide which version to install, use the following table.

| Package file                             | Target OS & Version             | Package type |
| ---------------------------------------- | ------------------------------- | ------------ |
| `puppet8-release-amazon-2.noarch.rpm`    | Amazon Linux 2                  | RPM (YUM)    |
| `puppet8-release-amazon-2023.noarch.rpm` | Amazon Linux 2023               | RPM (YUM)    |
| `puppet8-release-el-7.noarch.rpm`        | RHEL/CentOS 7                   | RPM (YUM)    |
| `puppet8-release-el-8.noarch.rpm`        | RHEL/CentOS 8                   | RPM (YUM)    |
| `puppet8-release-el-9.noarch.rpm`        | RHEL/CentOS 9                   | RPM (YUM)    |
| `puppet8-release-fedora-36.noarch.rpm`   | Fedora 36                       | RPM (YUM)    |
| `puppet8-release-fedora-40.noarch.rpm`   | Fedora 40                       | RPM (YUM)    |
| `puppet8-release-sles-12.noarch.rpm`     | SUSE Linux Enterprise Server 12 | RPM (Zypper) |
| `puppet8-release-sles-15.noarch.rpm`     | SUSE Linux Enterprise Server 15 | RPM (Zypper) |
| `puppet8-release-buster.deb`             | Debian 10 “Buster”              | DEB (APT)    |
| `puppet8-release-bullseye.deb`           | Debian 11 “Bullseye”            | DEB (APT)    |
| `puppet8-release-bookworm.deb`           | Debian 12 “Bookworm”            | DEB (APT)    |
| `puppet8-release-bionic.deb`             | Ubuntu 18.04 “Bionic Beaver”    | DEB (APT)    |
| `puppet8-release-focal.deb`              | Ubuntu 20.04 “Focal Fossa”      | DEB (APT)    |
| `puppet8-release-jammy.deb`              | Ubuntu 22.04 “Jammy Jellyfish”  | DEB (APT)    |
| `puppet8-release-noble.deb`              | Ubuntu 23.04 “Noble Numbat”     | DEB (APT)    |

- [Install Guide Official Docs](https://help.puppet.com/osp/8/Content/PuppetCore/server/install_from_packages.htm)
- [Releases List](https://apt-puppetcore.puppet.com/public/index.html)
- [Install Guide Blog 1](https://www.cloudbees.com/blog/install-and-configure-puppet-agent)
- [Install Guide Blog 2](https://community.hetzner.com/tutorials/install-and-configure-puppet-master-and-agent)

<br>

#### 2. In Server VM, open the 8140 port and in agent, for testing we should enable 80,443 and other relevent ports depending on the deployment :
```
ACP - 9443,5672
GW - 9443,9099,8099,8280,8243
TM - 9443,5672,9611,9711
KM - 9443
```

#### 3. Install server and agent and add to path and source ```~/.bashrc```. 
- For puppet: ```echo 'export PATH="/opt/puppetlabs/bin:/opt/puppetlabs/puppet/bin:$PATH"' \ >> ~/.bashrc```
- For puppet server: ```echo 'export PATH="/opt/puppetlabs/puppet/bin:/opt/puppetlabs/server/apps/puppetserver/bin:$PATH"' \>> ~/.bashrc```

#### 4. For Host mapping resolution -> In both client and server ```/etc/hosts```

In server:
```bash
[puppet server ip] puppetmaster puppet
[puppet agent ip] <AGENT_1_NAME>
[puppet agent ip] <AGENT_2_NAME>
[puppet agent ip] <AGENT_3_NAME>
[puppet agent ip] <AGENT_4_NAME>
```

In agent:
```bash
[puppet server ip] puppetmaster puppet
[puppet agent ip] <AGENT_NAME>
[puppet agent ip] cp.wso2.com
[puppet agent ip] gw.wso2.com
[puppet agent ip] tm.wso2.com
[puppet agent ip] km.wso2.com
```

#### 5. Then, on the agent machine, open the agent configuration file using your preferred text editor.
 
> sudo vim /etc/puppetlabs/puppet/puppet.conf
	
Then, add the following lines to the file:
```bash
[main]
certname = <ANY_NAME>
server   = puppet

[agent]
environment = <ENV_NAME>
runinterval  = 1y
splay        = false

```
This certname is the one that will be shown when listing all the signed and requested certs in step 7. If the names are conflicting or something, then some further actions might needed.

#### 6. For time sync:
```bash
#Debian/Ubuntu-family
sudo apt-get install -y chrony
sudo systemctl enable --now chrony
```


#### 7. Sign the certificate in server:
```bash
sudo /opt/puppetlabs/bin/puppetserver ca list --all
sudo /opt/puppetlabs/bin/puppetserver ca sign --all
```

#### 8. Create the **profile.txt**
- Path to create the file: 
```/etc/puppetlabs/facter/facts.d/profile.txt```
- Copy the pack and the jar to to the relevant folders

#### 9. Check whether agent pulls the configs properly:
 ```sudo /opt/puppetlabs/bin/puppet agent -vt```


**For puppet Code on the server:**
```/etc/puppetlabs/code/environments/<FOLDER_NAME>```

> Here the folder name can be any allowed env name. Make sure the same env is used by the agents in the .conf file

**For logs:**
> tail -f /mnt/<APIM_PROFILE_NAME>/<APIM_PACK>/repository/logs/wso2carbon.log
> Ex: tail -f /mnt/apim_gateway/wso2am-4.4.0/repository/logs/wso2carbon.log

**For toml:**
> cat /mnt/<APIM_PROFILE_NAME>/<APIM_PACK>/repository/conf/deployment.toml

> **Note:** 
> For internal /etc/hosts, use the private IPs when using VM setups(Make sure they exists within the same VNet)