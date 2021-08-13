# A Standard Java Container-based Development and Continuous Integration Pipeline

## What it is

A docker compose based infrastructure containing gitlab, jenkins, sonarqube, nexus and registry (optional, also included
in nexus)

This is NOT a security tutorial, this setup uses http and weak passwords which is NOT recommended!

This setup works on both Linux (virtual) machines as well as on Docker Desktop for Windows (WSL 2) - see comments below.

This guide will walk you through all steps required to connect the systems, it's highly recommended to start with 
using Nexus deployment or Sonarqube integration from local builds!

# Guide

## Windows/git setup

In order to checkout files using unix line endings you should configure git on windows:

We need to checkout linux files in Windows for WSL 2:

```
git config --global core.autocrlf input
```

## Linux/ virtual machine:
This is a one-time step to setup your machine
```{r, engine='bash', count_lines}
sudo sh -c "echo vm.max_map_count=262144 >> /etc/sysctl.conf"
sudo sysctl -p
```

## WSL 2
One-time setup

```{r, engine='bash', count_lines}
# In PowerShell
wsl -d docker-desktop
echo vm.max_map_count=262144 >> /etc/sysctl.conf
```


Required after each restart

```{r, engine='bash', count_lines}
# In PowerShell
wsl -d docker-desktop
echo vm.max_map_count=262144 >> /etc/sysctl.conf
sysctl -p
```

Changes are instantly effective.

## Network setup

There are different scenarios to access the environment:
- physical machine using a real hostname
  - in this case, everything should be fine by default
  - this hostname will be the value for `.env` variable `HOST_EXTERNAL` below
  - this hostname is available from everywhere, even from within docker containers
- WSL 2 setup, supported only locally
  - Docker Desktop configures an alias `host.docker.internal` in your windows hosts file pointing to the virtual docker network
  - this will be the value for `.env` variable `HOST_EXTERNAL` below
  - this hostname is available from everywhere, even from within docker containers
- VirtualBox/VMWare machine
  - define the machine's ip in the machine's /etc/hosts and your windows hosts file using e.g. `docker.vm`
  - this will be the value for `.env` variable `HOST_EXTERNAL` below
  - docker containers should be started in the docker network `nw`
    - you can install a DNS server to make this hostname avaiable for all docker containers
    - install and enable `dnsmasq` and configure the machine's ip for [Docker as DNS server](https://docs.docker.com/engine/reference/commandline/dockerd/#daemon-configuration-file)


## Configure Environment

Create / edit `.env` and adjust relevant values.

See above for hints regarding HOST_EXTERNAL. The main goal is to use the same name from everywhere to access all services
using the loadbalancer.

```
# External NAME of your machine (if required add to hosts file)
HOST_EXTERNAL=host.docker.internal

# Host and Port of the chosen docker registry. Default=nexus, you may use docker-distribution by uncommenting service `registry` in docker compose.yml, see https://hub.docker.com/_/registry
REGISTRY_ADDRESS=nexus:5000
#REGISTRY_ADDRESS=registry:5000

# Defaults 
COMPOSE_PROJECT_NAME=ci
PASSWORD_SONAR=stdcdevenv
```

## Loadbalancer

Loadbalancer is the single point of access to all services and removes the need for adding the specific ports to the URL
of each service. The only requirement is that it's reachable from everywhere using the same (virtual) hostname
by providing an alias (in docker compose.yml) using HOST_EXTERNAL, see network setup above.

The Loadbalancer service forwards HTTP(s) requests to the appropriate servers and connects its port 10022 to gitlab
port 22. By that, all clients only need to connect to the loadbalancer in order to access any service.

There is an alias name HOST_EXTERNAL which is assigned to loadbalancer in order to make this network name available
in the docker network without having to connect to the external network. Use the real hostname or your chosen alias for that.

Because of being isolated in containers and docker networks, the different products cannot determine their external address on 
their own. That's why most software needs to be configured if it generates external links, even though the loadbalancer passes
X_FORWARDED_* headers.


### Setup 

Decide whether to use ssl, if yes, follow comments in services/loadbalancer/Dockerfile

Create the Loadbalancer using 

```{r, engine='bash', count_lines}
docker compose up -d --build loadbalancer
```

Try to open the hostname you configured in `.env` as `HOST_EXTERNAL`

This README assumes URL_EXTERNAL to be `host.docker.internal`, so open `http://host.docker.internal`, you should see
a HTML page linking to the services which will be started in the next steps.

### Useful commands

```{r, engine='bash', count_lines}
docker compose start loadbalancer
docker compose stop  loadbalancer
docker compose exec  loadbalancer tail -f /var/log/httpd/access_log    
```

### How to verify your network setup:

All these commands should respond with a simple html page saying 'Loadbalancer access works' 

```
# Both of these are required to work
docker compose exec loadbalancer curl http://host.docker.internal/test.html
docker run --rm -it --network ci_nw alpine wget -O - http://host.docker.internal/test.html

# if this one gives the same result, you could omit the --network parameter in the Jenkinsfile agent.
docker run --rm -it alpine wget -O - http://host.docker.internal/test.html 
```


## Nexus

Start nexus using

```{r, engine='bash', count_lines}
docker compose up -d nexus
docker compose exec nexus cat /nexus-data/admin.password
```

Open

```{r, engine='bash', count_lines}
http://host.docker.internal/nexus/
```

Access Nexus, login as `admin` with the password printed out by the command `docker compose exec nexus cat /nexus-data/admin.password`.
this should look like `71a6bbfc-6cc2-4e21-817e-60f0cba42c9a` 

* Change Password, e.g. to `admin`
* Enable anonymous access

### Useful commands

```{r, engine='bash', count_lines}
docker compose start nexus
docker compose stop  nexus
docker compose logs -f --tail 1000 nexus    
```

### Nexus and Apache Maven

Create a repository

* Server Administration -> Blob stores -> Create a blob store, e.g. `my-store`
* Server Administration -> Repositories -> Create a hosted repository of type `maven2/hosted` e.g. `ci-java-releases` and `ci-java-snapshots` using the 
created blob store and matching version policy
* Modify repository `maven-public` and add `ci-java` 
* For e.g. Spring Boot create a proxied m2-repository  `maven2-spring`for `https://repo.spring.io/release/` and add this to 
`maven-public` as well
* Create a role eg. `nx-java`
* Assign Privilege `nx-repository-view-`[repository-type]`-`[repository-name]`-*`
* Assign Roles `nx-anonymous`
* Create User `nx-java`
* Assign created group `nx-java`
* Try to login using the new user using the Web UI http://host.docker.internal/nexus/ (e.g. in a private browser tab)

For documentation see 

* mirror settings: https://maven.apache.org/guides/mini/guide-mirror-settings.html
* server settings: https://maven.apache.org/settings.html#Servers
* deploy plugin: https://maven.apache.org/plugins/maven-deploy-plugin/usage.html

#### Example

Create a project, e.g. using http://start.spring.io 

Add `distributionManagement` to your pom:

```xml
  <distributionManagement>
    <repository>
      <id>ci-java-releases</id>
      <name>demo Repository Releases</name>
      <url>http://host.docker.internal/nexus/repository/ci-java-releases/</url>
    </repository>
    <snapshotRepository>
      <id>ci-java-snapshots</id>
      <name>demo Repository Snapshots</name>
      <url>http://host.docker.internal/nexus/repository/ci-java-snapshots/</url>
    </snapshotRepository>
  </distributionManagement>
```

You can also add your nexus' public repo to the pom, this is necessary if the project won't build with
public repositories only or without internet/proxy access.

```xml
  <repositories>
    <repository>
      <id>central</id>
      <name>Nexus Repository Mirror</name>
      <releases>
        <enabled>true</enabled>
      </releases>
      <snapshots>
        <enabled>true</enabled>
        <updatePolicy>always</updatePolicy>
      </snapshots>
      <url>http://host.docker.internal/nexus/repository/maven-public/</url>
    </repository>
  </repositories>
  <pluginRepositories>
    <pluginRepository>
      <id>central</id>
      <name>Nexus Repository Mirror</name>
      <releases>
        <enabled>true</enabled>
      </releases>
      <snapshots>
        <enabled>true</enabled>
      </snapshots>
      <url>http://host.docker.internal/nexus/repository/maven-public/</url>
    </pluginRepository>
  </pluginRepositories>```

Configure your `[HOME]/.m2/settings.xml` to always download from your nexus (`mirror`) if required and the server credentials.
If you need more public repositories, you need to configure those as a proxy repository in nexus and add them
to the repository group maven-public. The same applies to your own repositories.

```xml
<settings>
	<!--mirrors>
		<mirror>
			<id>nexus</id>
			<url>http://host.docker.internal/nexus/repository/maven-public/</url>
			<mirrorOf>*</mirrorOf>
		</mirror>
	</mirrors-->
	<servers>
        <server>
            <id>ci-java-releases</id>
            <username>nx-java</username>
            <password>[password here]</password>
        </server>
        <server>
            <id>ci-java-snapshots</id>
            <username>nx-java</username>
            <password>[password here]</password>
        </server>
    </servers>
</settings>
```

To deploy to nexus, run in the project folder the command

```xml
 ./mvnw -DskipTests deploy
```

On a docker machine you may run with settings.xml in the project folder you may run
(for docker-here see https://blog.oio.de/2019/06/27/docker-best-practices-alle-wege-fuhren-nach-docker/)
```
docker-here openjdk:11 sh ./mvnw --settings ./settings.xml clean deploy
```

### Nexus and npm

Configure Nexus for npm:

* In Administration -> Security -> Realms add "npm Bearer Token" for NPM login

Create a repository

* Server Administration -> Repositories -> Create a hosted repository of type `npm/hosted` e.g. `ci-npm`
* Create a proxy npm repository `npmjs` for https://registry.npmjs.org
* Create a npm group repository `npm-public` containing `npmjs` and `ci-npm` 
* Create a group eg. `nx-npm`
* Assign Privilege `nx-repository-view-`[repository-type]`-`[repository-name]`-*`
* Assign Roles `nx-anonymous`
* Create User `nx-npm`
* Assign created group `nx-npm`
* Try to login using the new user using the Web UI

For documentation see 

* npm: https://blog.sonatype.com/using-nexus-3-as-your-repository-part-2-npm-packages
  * Check in Nexus -> Server Administration -> Realms, active `npm Bearer realm`
  * create `~/.npmrc`, add line `email=...`
  * `npm adduser --registry [url of your npm repo]`
  * `npm whoami --registry [url of your npm repo]` should print your username

#### Example

Add your credentials to nexus with npm:

```
npm adduser --registry http://host.docker.internal/nexus/repository/ci-npm/
```

Configure your project (or global, $USER_HOME) `.npmrc` to contain the url to the repository group:

```
registry=http://host.docker.internal/nexus/repository/npm-public/
```

Npm install should now download from your nexus instance, check using http://host.docker.internal/nexus/#browse/browse:npm-public 
before and after running 

`npm install`

Configure your project for publishing, the trailing `/` in the URL is important!

```
...
  "publishConfig": {
    "registry": "http://host.docker.internal/nexus/repository/ci-npm/"
  },
...
```

And run the appropriate script to build & deploy your code
```
 npm publish dist   # only an example, might be different compared to your project
```

### Nexus and Docker

- Create a hosted docker repository in nexus, e.g. named ci-docker and add a http connector for port 5000
- `docker compose exec loadbalancer curl nexus:5000/v2/_catalog` should return a json with an empty `repositories` array
- `docker compose exec jenkins curl host.docker.internal/v2/_catalog` should return the same json
- create a nexus role `nx-docker` and add privilege `nx-repository-view-docker-ci-docker` and role `nx-anonymous`
- create a user `nx-docker` and assign the created role `nx-docker` (sometimes the save button won't switch to enabled)

In your docker's configuration (/etc/docker/daemon.json or preferences in docker desktop UI) you have to configure our
nexus as insecure unless you configured ssl (but depending on your certificates you might struggle with them)

Verify that your configuration contains

```
{
  "insecure-registries": [
    "host.docker.internal"
  ]
}
```

If you had to change it, please restart the docker engine itself.


`docker compose exec jenkins bash`
`docker login host.docker.internal`

if you used nx-docker as username and password, this will create a file in /var/jenkins_home/.docker/config.json

```
{
        "auths": {
                "host.docker.internal": {
                        "auth": "bngtZG9ja2VyOm54LWRvY2tlcg=="
                }
        }
}
```

Now your jenkins user would be able to pull/push images, but we want to provide this as a secret in docker.
- copy-paste the file contents to a new temp file on your pc
- Upload this file as a new secret file with id `docker-config` in jenkins
- delete the file again in jenkins `rm /var/jenkins_home/.docker/config.json`

you might as well `docker login ...` on windows desktop which uses the `Windows Credentials Manager` to store these
accounts.  That's why we did use the jenkins container to create the file

In your Jenkinsfile you can now add stages to build and push your image:

```
        stage('docker') {
            steps {
                sh '''
                    cd ${basePath}
                    docker build . -t ${dockerRepo}:${dockerTag}
                '''
            }
        }
        stage('docker-push') {
            steps {
                withCredentials([file(credentialsId: 'docker-config', variable: 'DOCKER_CONFIG_FILE')]) {            
                    sh '''
                        cd ${basePath}
                        export DOCKER_CONFIG=$(dirname $DOCKER_CONFIG_FILE)
                        docker history ${dockerRepo}:${dockerTag}
                        docker push ${dockerRepo}:${dockerTag}
                    '''
                }
            }
        }
```



## Docker registry

### Docker-Distribution

As mentioned above, the loadbalancer is configured to use nexus as docker registry.

But you can also switch to docker-distribution by configuring `REGISTRY_ADDRESS=registry:5000` in `.env` and 
bringing up `registry`by running `docker compose up -d registry`.
This registry works out of the box without security.

Check by using your browser http://host.docker.internal/v2/_catalog or running `docker compose exec loadbalancer  curl -s http://registry:5000/v2/_catalog`, both should respond with an emtpy json `{"repositories":[]}`

### To use Nexus as Docker registry

* In Administration -> Security -> Realms add "Docker Bearer Token" for Docker login

Create a repository

* Server Administration -> Repositories -> Create a hosted repository of type `docker/hosted` e.g. `ci-docker`
* Check create http connector and define port 5000
* Port 5000 is mapped in loadbalancer as /v2 and preconfigured in `.env` as  `REGISTRY_ADDRESS=nexus:5000`
* Check by using your browser http://host.docker.internal/v2/_catalog or running `docker compose exec loadbalancer  curl -s http://nexus:5000/v2/_catalog`, both should respond with an emtpy json `{"repositories":[]}`

* Create a group eg. `nx-docker`
* Assign Privilege `nx-repository-view-`[repository-type]`-`[repository-name]`-*`
* Assign Roles `nx-anonymous`
* Create User `nx-docker`
* Assign created group `nx-docker`

* Without SSL you have to configure docker to use this server as an insecure registry in /etc/docker/daemon.json or in Docker Desktop
on WSL2 in Settings ->Docker-Engine
```
{
  ... other settings...
  "insecure-registries": [ "host.docker.internal" ],
  ... other settings...
}
```
* run `docker login host.docker.internal` and use the user created above
* create or tag and push your first image
```
docker pull alpine:latest
docker tag alpine:latest host.docker.internal/base/alpine:latest
docker push host.docker.internal/base/alpine:latest
``` 

Check http://host.docker.internal/nexus/#browse/browse:ci-docker:v2%2Fbase%2Falpine%2Ftags%2Flatest


## Sonarqube

```{r, engine='bash', count_lines}
http://host.docker.internal/sonarqube/
```

Default sonar user is `admin` using password `admin`, Generate a token for your account and save it ... 

My Account -> Security -> Add token

e.g. to set as environment property in bash

```{r, engine='bash', count_lines}
SONAR_TOKEN=04aee6c96c4887d64917b6c163e2820f91ccd546

# another Token
SONAR_TOKEN=6fc8588c9646dac657b10dd290e0fab909c548eb
```

Administration->Marketplace->Updates only -> install plugin updates

### Useful commands

```
docker compose up -d sonardb sonarqube
docker compose stop sonarqube && sleep 10 && docker compose stop sonardb
docker compose logs -f --tail 100 sonarqube
```

### Sonarqube and Apache MAVEN

Documentation: https://docs.sonarqube.org/latest/analysis/scan/sonarscanner-for-maven/

Run Sonar using the maven plugin by adding

```
sonar:sonar -Dsonar.host.url=http://host.docker.internal/sonarqube/ -Dsonar.login=${SONAR_TOKEN}
```

to your maven command, the parameter `-Dsonar.login=...` is optional as this sonar instance by default 
allows anonymous analysis

```
docker-here openjdk:11 sh ./mvnw --settings ./settings.xml -Dsonar.host.url=http://host.docker.internal/sonarqube/ -Dsonar.login=${SONAR_TOKEN} clean deploy sonar:sonar
```

and the project should appear in Sonarqube

For code coverage analysis with maven and sonarqube, you need to add to build-plugins

```xml
...
      <plugin>
        <groupId>org.jacoco</groupId>
        <artifactId>jacoco-maven-plugin</artifactId>
        <version>0.8.6</version>
        <executions>
          <execution>
            <goals>
              <goal>prepare-agent</goal>
            </goals>
            <id>default-prepare-agent</id>
          </execution>
          <execution>
            <goals>
              <goal>report</goal>
            </goals>
            <id>default-report</id>
            <phase>prepare-package</phase>
          </execution>
        </executions>
      </plugin>
...
```

The Jacoco-plugin defines the `argLine` variable for the by default included surefire plugin. If you need to configure
the surefire pluginn, you can include it using the following pom.xml fragment.
If you need to configure `argLine` for surefire, you have to add the `argLine` variable to not loose jacoco functions:

```
...
<!-- surefire plugin for tests -->
<plugin>
    <groupId>org.apache.maven.plugins</groupId>
    <artifactId>maven-surefire-plugin</artifactId>
    <version>2.22.2</version>
    <configuration>
        <argLine>-DmySystemProperty=somevalue @{argLine}</argLine>
    </configuration>
</plugin>
...

```

### Sonarqube and npm

Documentation: 
* Sonar scanner npm package: https://www.npmjs.com/package/sonar-scanner
* Sonar scanner official homepage: https://docs.sonarqube.org/latest/analysis/scan/sonarscanner/
* `sonar-project.properties` according to https://docs.sonarqube.org/latest/analysis/scan/sonarscanner/#header-1

For sonar-scanner setup:

```
npm install --save-dev sonar-scanner
```

and create

add script to package.json

```
   ...
"sonar": "sonar-scanner -Dsonar.login=${SONAR_TOKEN}"
   ...
```

Run 

```
npm run sonar
```

## Gitlab

Gitlab is a rather heavy container and takes some minutes to start up as it's a complete ci/cd solution for itself.

That's why it's commented out by default in docker-compose.yml. Simply uncomment all lines containing gitlab (volumes, service).


The default admin user is `root` and you have to change the password on first access. On first login, you need to
change passwords for new users. Due to the password policy, a simple valid password is `gitlab123`.

http://host.docker.internal/gitlab

gitlab relies on email addresses to identify users, so user's emails have to be unique. By default SMTP is off.
For emails you can use your real mail server or the fake smtp server included in the configuration.

For that edit the config using `docker compose exec gitlab vi /etc/gitlab/gitlab.rb`

```
...
# this is for fake smtp at http://host.docker.internal/smtp/emails
gitlab_rails['smtp_enable'] = true
gitlab_rails['smtp_address'] = "smtp"
gitlab_rails['smtp_port'] = 1025
gitlab_rails['smtp_domain'] = 'test.dummy';
gitlab_rails['smtp_tls'] = false;
gitlab_rails['smtp_openssl_verify_mode'] = 'none'
gitlab_rails['smtp_enable_starttls_auto'] = false
gitlab_rails['smtp_ssl'] = false
gitlab_rails['smtp_force_ssl'] = false
...
```

Use `docker compose restart gitlab` to activate.


Set up additional users and projects as required, e.g. user `demo` having password `demo1234`.
This README will use project `demo-java` for user root.

For WebHooks in order to send events to jenkins, in admin settings -> network -> Outbound requests you might need to enable
requests to local adresses.


### Useful commands

```{r, engine='bash', count_lines}
docker compose up -d gitlab
docker compose stop  gitlab
docker compose logs -f --tail 100 gitlab    
```

### Gitlab Access 

Gitlab offers http and ssh access. For HTTP the base URL is `http://host.docker.internal/gitlab/` which is proxied by the 
loadbalancer. In its run-script, the loadbalancer also forwards TCP ports 22 and 10022 to gitlab, allowing direct ssh access.

Docker port forwarding and loadbalancer provide port 10022 to connect to gitlab Port 22. 

Because of virtual machines and WSL 2 typically blocking port 22, then it is
- Machine/WSL2 SSH: Port    22
- Gitlab SSH:  Port 10022

The default URL `git@host.docker.internal:root/demo-java.git` will then not work out of the box, but does for local (e.g. WSL2) docker setup.

For SSH access you need a key pair, which might already be generated in `~/.ssh/id_*` and should be added to your
gitlab account using http://host.docker.internal/gitlab/profile/keys

To generate a key pair e.g. for jenkins use (without -f ... it generates your personal keys)
* `ssh-keygen -t rsa -b 4096 -f keys-jenkins.rsa` 
* or `ssh-keygen -t ed25519 -f keys-jenkins.ed25519`

Login to gitlab using your project's user, then click on you user's icon (top bar, right side) and choose settings.
Click ssh keys and add the contents of `keys-jenkins.rsa.pub` 


The following options show how to configure gitlab access, option 1 is the easiest, but option 2.1 the most convenient.


#### Option 1: Use ssh URLs (easiest option, no network setup required)

Cloning and ssh access works with the following commands, ssh access needs to be converted to URL form in order to
add the port specification starting with `ssh://`
In all cases, `host.docker.internal` is used as `HOST_EXTERNAL`, so actually all connects go to loadbalancer which forwards
those connections. 

```{r, engine='bash', count_lines}
# modify        git@host.docker.internal:root/demo-java.git        to
git clone ssh://git@host.docker.internal:10022/root/demo-java.git

ssh user@host.docker.internal
```

#### Option 2: Configure ssh

##### Option 2.1: Configure ssh access default (best and most secure option)

`~/.ssh/config` modifies the port used by default

```{r, engine='bash', count_lines}
vi ~/.ssh/config
```

Content 

```{r, engine='bash', count_lines}
Host host.docker.internal
  Port 10022
```

Cloning and ssh access work with the commands (you need to add -p 22 for pure ssh)

```{r, engine='bash', count_lines}
git clone git@host.docker.internal:root/demo-java.git

ssh -p 22 user@host.docker.internal
```

##### Option 2.2: Make gitlab use port 22, move SSH to another port

(currently not documented for VirtualBox, not required for WSL)

Cloning and ssh access works with the commands (you need to add -p ... for pure ssh)

```{r, engine='bash', count_lines}
git clone git@host.docker.internal:root/demo-java.git

ssh -p [another port] user@host.docker.internal
```

#### Option 2: Use http for gitlab

But HTTP is not secure for passwords. In git for Windows, the Credentials Manager will handle saved passwords.

Cloning and ssh access works with the commands

```{r, engine='bash', count_lines}
git clone http://host.docker.internal/gitlab/root/demo-java.git

ssh user@host.docker.internal
```


### Pushing to gitlab

Having created a user `demo` and a project named `java-ci-docker_demo-java-spring` you can use the following commands to
push `master` branch to gitlab:

```
git remote add gitlab git remote add gitlab git@host.docker.internal:demo/java-ci-docker_demo-java-spring.git
git push gitlab master
```


## Jenkins

```{r, engine='bash', count_lines}
http://host.docker.internal/jenkins/
```

Get the initial Secret

```{r, engine='bash', count_lines}
docker compose exec jenkins cat /var/jenkins_home/secrets/initialAdminPassword
```

Install suggested plugins, setup account for administrator, e.g. `admin` / `admin` and use the appropriate URL
as Jenkins URL, e.g. http://host.docker.internal/jenkins/

To create a read-only `Jenkins` user your repository, follow the following steps:

For Azure devops:
* To generate a key pair e.g. for jenkins use (without -f ... it generates your personal keys)
  * `ssh-keygen -t rsa -b 4096 -f keys-jenkins.rsa` 
  * or `ssh-keygen -t ed25519 -f keys-jenkins.ed25519`
* Open Azure https://dev.azure.com and click the Person icon left of you Account logo (second from the left) 
  * Choose "SSH public keys"
  * Add the contents of you `keys-jenkins.rsa.pub` file as a new SSH public key

For Gitlab:
* Login gitlab with admin account and create a new user `jenkins`, ignore password.
* Admin area ---> users ---> edit `jenkins` user ---> set password (e.g. `jenkins123`)
* In opened user `jenkins` click `impersonate`
* Add ssh key for jenkins to this account
* Add `jenkins` as member with role `Developer` to project(s)
* Login using `jenkins` and change password as advised, you can use `jenkins123` again

Jenkins:
* Login to Jenkins as admin
* Jenkins -> Manage Jenkins -> System Configuration
  * Check the `Jenkins Location` URL to match the URL you see in the browser, e.g. http://host.docker.internal/jenkins/
* Jenkins -> Manage Jenkins -> Configure Global Security
  * Authorization Strategy: Project-based Matrix Authorization Strategy
* Jenkins -> Manage Jenkins -> Plugins
  * http://host.docker.internal/jenkins/updateCenter/ - Click restart checkbox at the very bottom
  * Update all Plugins http://host.docker.internal/jenkins/pluginManager/
  * Install Docker Pipeline Plugin: https://plugins.jenkins.io/docker-workflow/
  * Install Pipeline Utility Steps Plugin
  * Install Authorize Project: https://plugins.jenkins.io/authorize-project/
  * Check restart checkbox which will restart jenkins when finished installing to apply plugin updates
* Jenkins -> Manage Jenkins -> Configure Global Security
  * Access Control for Builds: Add `Project default build authorization`
  * `Run as SYSTEM`
  
As this README is not a security tutorial but instructions to get this up quickly, you should reconsider different options for production use.
  
* Jenkins -> Manage Jenkins -> Security -> Manage Credentials -> Global credentials (http://host.docker.internal/jenkins/credentials/store/system/domain/_/)  - add
  * add `SSH username with private key` credentials `git-ssh` for user `jenkins` and copy-paste (direct input) the keyfile contents of `keys-jenkins.rsa`
  * add `secret file` credentials `demo-settings` containing the maven `settings.xml` from above
  * add `secret text` credentials `demo-sonar-token` containing the Sonarqube token created earlier  

It's important to define the names above as credential ID.

Manage credentials is in http://host.docker.internal/jenkins/credentials/store/system/domain/_/
  

After that, not only jenkins but the whole jenkins container needs to be restarted once. The reason for that
is the custom entrypoint script provided in this jenkins container. It adjusts the group id of the docker group
in the container to the docker group id on the host system. But this won't be effective until

```
# VirtualBox / Linux only
docker compose restart jenkins
```

To check if jenkins has access to your local docker daemon, run

```
docker compose exec jenkins docker ps
```

You should see the same output as `docker ps` outputs on the machine's console.
  
Create a jenkins project 
* named `demo-java` 
* using type `Multibranch Pipeline`
* Add branch source of type `git` with repository `ssh://git@host.docker.internal:10022/root/demo-java.git`
* Choose the created credentials
* Save

If you pushed at least an empty file named `Jenkinsfile`to the project root, the `master` branch will show up 
in Jenkins. For Multibranch Pipeline projects, you only need to click on `Scan multibranch pipeline now` which will
check for new, deleted or changes branches and launch the appropriate builds.

Modify the Jenkinsfile to contain your job definition:

```
pipeline {
    agent {
        docker {
            image 'openjdk:11'
            args '--network ci'
        }
    }
    stages {
        stage('Build') {
            steps {
                withCredentials([file(credentialsId: 'demo-settings', variable: 'MVN_SETTINGS')]) {                
                    sh '''
                        sh ./mvnw --settings $MVN_SETTINGS clean deploy
                    '''
                }
            }
        }
    }
}
```

* agent -> docker  instructs docker to start your build within docker. Therefore the docker binaries are built into
the image and the appropriate permissions are defined at startup
  * the --network ci_nw makes the container start in the ci network, so all other containers will be available by their
  docker compose service name
* Only Java is required to build java, maven is downloaded by maven wrapper
* Maven Settings File are provided as a secret file and passed to maven using `--settings`. It contains the nexus 
 credentials
* SONAR Token works the same way, documentation about `withCredentials` is in 
https://www.jenkins.io/doc/pipeline/steps/credentials-binding/

If you're using the default openjdk image, jenkins will launch the build in its workspace directory which is mounted
from the jenkins container to the build container (--volumes-from) . As the jenkins user is unknown in this builder 
image, the maven resources will be downloaded to a virtual home directory named `?` within the workspace, which is 
acceptable for the first builds. It's a best practice to create an image containing all the software you need and an 
user with id "1000" which is the jenkins user.

Then you could modify the docker agent definition to mount
1. the docker socket for building docker images
2. a named volume which will automatically be created to store maven downloads

the agent definition then looks as follows

```
    agent {
        docker {
            image 'my-builder-image'
            alwaysPull true
            args ' -v /var/run/docker.sock:/var/run/docker.sock -v m2-jenkins:/home/user/.m2'
        }
    }
```


To integrate gitlab with Jenkins:

* Create a user `gitlab` in Jenkins
* Assign "Overall - Read" permission to gitlab in Global Security
* As user `gitlab` create an API token in http://host.docker.internal/jenkins/user/gitlab/configure which should look like this:
`115e09e85a035e5f2a166f0cffa7abad0c`
* In your project Open `Configure` (http://host.docker.internal/jenkins/job/demo-java/configure) 
   * check Properties -> Enable project-based security
   * Add user `gitlab` and allow Job -> Build  and Project -> Read
* Check by running `curl -v --user gitlab:115e09e85a035e5f2a166f0cffa7abad0c -X POST http://host.docker.internal/jenkins/job/demo-java/build`
or `http://gitlab:115e09e85a035e5f2a166f0cffa7abad0c@host.docker.internal/jenkins/job/demo-java/build`
the response should be HTTP 302 redirecting to the build log in  http://host.docker.internal/jenkins/job/demo-java/
* In gitlab navigate to your project -> Settings -> WebHooks (make sure you enabled local outbound network connections, see gitlab setup)
* Add WebHook for Push events to URL `http://[user]:[token]@host.docker.internal/jenkins/job/[job-name]/build` which is for this 
example `http://gitlab:115e09e85a035e5f2a166f0cffa7abad0c@host.docker.internal/jenkins/job/demo-java/build` which actually
corresponds to scanning the multibranch pipeline
* Uncheck SSL verification if you used self-signed certificates
* Click on Test, which should return the message `Hook executed successfully: HTTP 200`
* Now open jenkins again and push a change to gitlab, Jenkins should instantly build your code

If you created a folder, e.g. `demo` for your project, insert `demo/job` in the url above.

Documentation for WebHooks with Jenkins are based on Jenkins API: https://www.jenkins.io/doc/book/using/remote-access-api/


# Shutdown and Destroy, Backup and Restore 

Useful commands are

```
# bring everything up
docker compose up -d --build

# start all existing services
docker compose start

# stop all services
docker compose stop

# remove all services (keeps volumes, so data remains in the system)
docker compose down

# remove all services - DELETE ALL DATA (volumes)
docker compose down -v

# backup all volumes to tgz files
# it's better to stop all services before creating a backup
docker compose stop
docker run --rm -v ci_gitlab_config:/mnt alpine tar czf - /mnt > ci_gitlab_config.tgz
docker run --rm -v ci_gitlab_data:/mnt   alpine tar czf - /mnt > ci_gitlab_data.tgz
docker run --rm -v ci_gitlab_logs:/mnt   alpine tar czf - /mnt > ci_gitlab_logs.tgz
docker run --rm -v ci_jenkins_data:/mnt  alpine tar czf - /mnt > ci_jenkins_data.tgz
docker run --rm -v ci_nexus_data:/mnt    alpine tar czf - /mnt > ci_nexus_data.tgz
docker run --rm -v ci_sonardb_data:/mnt  alpine tar czf - /mnt > ci_sonardb_data.tgz

# restore all volumes from tgz files
# the volumes should be emtpy or non-existent an will be created by these commands
cat gitlab_config.tgz | docker run --rm -i -v ci_gitlab_config:/mnt alpine tar xzf - -C /mnt
cat gitlab_data.tgz   | docker run --rm -i -v ci_gitlab_data:/mnt   alpine tar xzf - -C /mnt
cat gitlab_logs.tgz   | docker run --rm -i -v ci_gitlab_logs:/mnt   alpine tar xzf - -C /mnt
cat ci_jenkins_data.tgz  | docker run --rm -i -v ci_jenkins_data:/mnt  alpine tar xzf -
cat ci_nexus_data.tgz    | docker run --rm -i -v ci_nexus_data:/mnt    alpine tar xzf -
cat ci_sonardb_data.tgz  | docker run --rm -i -v ci_sonardb_data:/mnt  alpine tar xzf -

```

## Gitlab official backup and upgrading process

For gitlab you can use it's built-in backup/restore functionality
https://docs.gitlab.com/ee/raketasks/backup_restore.html

the backups will be located in /var/opt/gitlab/backups/, e.g.

`docker cp gitlab:/var/opt/gitlab/backups/1627650905_2021_07_30_10.5.3_gitlab_backup.tar .` copies it to your local machine

For upgrading gitlab, you can just update the version in docker-compose.yml, following the steps
- Upgrade to the latest minor version of the current major version - e.g. from X.2.y to X.7.z
- Upgrade to the first minor version of the next major version - e.g. FROM X.7.z to A.0.b
- Repeat the process until you reach the desired version
	
see https://docs.gitlab.com/ee/update/index.html#upgrading-to-a-new-major-version


## Mirror all git repositories

- As `root` create a Access Token for API calls and export it to your shell's environment: `export API_TOKEN=...`
- List all projects to `projects.json`: `curl "http://host.docker.internal/gitlab/api/v4/projects?private_token=$API_TOKEN&per_page=100&page=1" | jq > projects.json`
  - if there are more than 100 you have to repeat this for page=2 and so on
- Define your git clone base url (containing user and password if not locally/ssh authenticated): `export GIT_BASE_URL=http://root:[insert password here]@host.docker.internal/gitlab/`
- 
- close shell and clean history from recorded commands using cleartext passwords






