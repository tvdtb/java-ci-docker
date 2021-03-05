# A Standard Java Container-based Development and Continuous Integration Pipeline

## What it is
A docker-compose based infrastructure containing gitlab, jenkins, sonarqube, nexus and registry (optional, also included
in nexus)

This is NOT a security tutorial, this setup uses http and weak passwords which is NOT recommended!

This setup works on both Linux (virtual) machines as well as on Docker Desktop for Windows (WSL 2) - see comments below.

# Guide

This is a one-time step to setup your Linux (virtual) machine

Linux/ virtual machine:
```{r, engine='bash', count_lines}
sudo sh -c "echo vm.max_map_count=262144 >> /etc/sysctl.conf"
sudo sysctl -p
```

WSL:
```{r, engine='bash', count_lines}
# In PowerShell
wsl -d docker-desktop
echo vm.max_map_count=262144 >> /etc/sysctl.conf
sysctl -p
```

Changes are instantly effective.


## Configure Environment

Edit `.env` and adjust relevant values.

If using a virtual machine, I suggest using the real host name to access the machine - or use an alias e.g. `docker.vm` 
for virtual machines or `docker.win` for Docker desktop.

## Loadbalanacer

Loadbalancer is the single point of access to all services and removes the need for adding the specific ports to the URL
of each service. The only requirement is that it's reachable from everywhere using the same (virtual) hostname
by providing an alias (in docker-compose.yml) and possibly your local hosts file.

The Loadbalancer service forwards HTTP(s) requests to the appropriate servers and connects its port 10022 to gitlab
port 22. By that, all clients only need to connect to the loadbalancer in order to access any service.
 
There is an alias name HOST_EXTERNAL which is assigned to loadbalancer in order to make this network name available
in the docker network without having to connect to the external network. Use the real hostname or your chosen alias for that.

### Setup 

Decide whether to use ssl, if yes, follow comments in services/loadbalancer/Dockerfile

Create the Loadbalancer using 

```{r, engine='bash', count_lines}
docker-compose up -d --build loadbalancer
```

Try to open the hostname you configured in `.env` as `HOST_EXTERNAL`

This README assumes URL_EXTERNAL to be `docker.vm`, so open `http://docker.vm`, you should see
a HTML page linking to the services which will be started in the next steps.

### Useful commands

```{r, engine='bash', count_lines}
docker-compose start loadbalancer
docker-compose stop  loadbalancer
docker-compose exec  loadbalancer tail -f /var/log/httpd/access_log    
```


## Nexus

Start nexus using

```{r, engine='bash', count_lines}
docker-compose up -d nexus
docker-compose exec nexus cat /nexus-data/admin.password
```

Open

```{r, engine='bash', count_lines}
http://docker.vm/nexus/
```

Access Nexus, login as `admin` with the password printed out by the second command.

* Change Password, e.g. to `admin`
* Enable anonymous access

### Useful commands

```{r, engine='bash', count_lines}
docker-compose start nexus
docker-compose stop  nexus
docker-compose logs -f --tail 1000 nexus    
```

### Nexus and Apache Maven

Create a repository

* Server Administration -> Blob stores -> Create a blob store, e.g. `my-store`
* Server Administration -> Repositories -> Create a hosted repository of type `maven/hosted` e.g. `ci-java` using the 
created blob store and version policy `mixed`
* Modify repository `maven-public` and add `ci-java` 
* Create a role eg. `nx-java`
* Assign Privilege `nx-repository-view-`[repository-type]`-`[repository-name]`-*`
* Assign Roles `nx-anonymous`
* Create User `nx-java`
* Assign created group `nx-java`
* Try to login using the new user using the Web UI

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
			<id>demo-releases</id>
			<name>demo Repository Releases</name>
			<url>http://docker.vm/nexus/repository/ci-java/</url>
		</repository>
		<snapshotRepository>
			<id>demo-snapshots</id>
			<name>demo Repository Snapshots</name>
			<url>http://docker.vm/nexus/repository/ci-java/</url>
		</snapshotRepository>
	</distributionManagement>
```

Configure your `[HOME]/.m2/settings.xml` to always download from your nexus (`mirror`) and the server credentials.
If you need more public repositories, you need to configure those as a proxy repository in nexus and add them
to the repository group maven-public. The same applies to your own repositories.

```xml
<settings>
	<mirrors>
		<mirror>
			<id>nexus</id>
			<url>http://docker.vm/nexus/repository/maven-public/</url>
			<mirrorOf>*</mirrorOf>
		</mirror>
	</mirrors>
	<servers>
        <server>
            <id>demo-releases</id>
            <username>nx-java</username>
            <password>[password here]</password>
        </server>
        <server>
            <id>demo-snapshots</id>
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
npm adduser --registry http://docker.vm/nexus/repository/ci-npm/
```

Configure your project (or global, $USER_HOME) `.npmrc` to contain the url to the repository group:

```
registry=http://docker.vm/nexus/repository/npm-public/
```

Npm install should now download from your nexus instance, check using http://docker.vm/nexus/#browse/browse:npm-public 
before and after running 

`npm install`

Configure your project for publishing, the trailing `/` in the URL is important!

```
...
  "publishConfig": {
    "registry": "http://docker.vm/nexus/repository/ci-npm/"
  },
...
```

And run the appropriate script to build & deploy your code
```
 npm publish dist   # only an example, might be different compared to your project
```


## Sonarqube

```{r, engine='bash', count_lines}
http://docker.vm/sonarqube/
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
docker-compose up -d sonardb sonarqube
docker-compose stop sonarqube && sleep 10 && docker-compose stop sonardb
docker-compose logs -f --tail 1000 sonarqube
```

### Sonarqube and Apache MAVEN

Documentation: https://docs.sonarqube.org/latest/analysis/scan/sonarscanner-for-maven/

Run Sonar using the maven plugin by adding

```
sonar:sonar -Dsonar.host.url=http://docker.vm/sonarqube/ -Dsonar.login=${SONAR_TOKEN}
```

to your maven command

```
docker-here openjdk:11 sh ./mvnw --settings ./settings.xml -Dsonar.host.url=http://docker.vm/sonarqube/ -Dsonar.login=${SONAR_TOKEN} clean deploy sonar:sonar
```

and the project should appear in Sonarqube

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

## Gitlab

Gitlab is a rather heavy container and takes some minutes to start up.

The default admin user is `root` and you have to change the password on first access. On first login, you need to
change passwords for new users. Due to the password policy, a simple valid password is `gitlab123`.

http://docker.vm/gitlab

Set up additional users and projects as required, this README will use project `demo-java` for user root.

### Useful commands

```{r, engine='bash', count_lines}
docker-compose up -d gitlab
docker-compose stop  gitlab
docker-compose logs -f gitlab    
```

### Gitlab Access 

Gitlab offers http and ssh access. For HTTP the base URL is `http://docker.vm/gitlab/` which is proxied by the 
loadbalancer. SSH in gitlab might collide with your machine's SSH, therefore it is by default configured for 
port 10022, so your SSH access to gitlab git repositories has to be configured.

Both docker port forwarding and loadbalancer provide port 10022 to connect to gitlab Port 22. 

It is
- Machine SSH: Port    22
- Gitlab SSH:  Port 10022

The default URL `git@docker.vm:root/demo-java.git` will not work out of the box.

For SSH access you need a key pair, which might already be generated in `~/.ssh/id_*` and should be added to your
gitlab account using http://docker.vm/gitlab/profile/keys

To generate a key pair e.g. for jenkins use (without -f ... it generates your personal keys)
* `ssh-keygen -t rsa -b 4096 -f keys-jenkins.rsa` 
* or `ssh-keygen -t ed25519 -f keys-jenkins.ed25519`


#### Option 1: Use ssh URLs (best option, no network setup required)

Cloning and ssh access works with the following commands, ssh access needs to be converted to URL form in order to
add the port specification starting with `ssh://`
In all cases, `docker.vm` is used as `HOST_EXTERNAL`, so actually all connects go to loadbalancer which forwards
those connections. 

```{r, engine='bash', count_lines}
# modify        git@docker.vm:root/demo-java.git        to
git clone ssh://git@docker.vm:10022/root/demo-java.git

ssh user@docker.vm
```

#### Option 2: Use http for gitlab

But HTTP is not secure for passwords. In git for Windows, the Credentials Manager will handle saved passwords.

Cloning and ssh access works with the commands

```{r, engine='bash', count_lines}
git clone http://docker.vm/gitlab/root/demo-java.git

ssh user@docker.vm
```

#### Option 3: Configure networking

See blog post: TODO

##### Option 2.1: Make gitlab use port 22, move SSH to another port

TODO - document how to do this with vagrant

Cloning and ssh access works with the commands (you need to add -p ... for pure ssh)

```{r, engine='bash', count_lines}
git clone git@docker.vm:root/demo-java.git

ssh -p [another port] user@docker.vm
```

##### Option 2.2: Configure ssh access default

`~/.ssh/config` modifies the port used by default

```{r, engine='bash', count_lines}
vi ~/.ssh/config
```

Content 

```{r, engine='bash', count_lines}
Host docker.vm
  Hostname docker.vm
  User git
  Port 10022
```

Cloning and ssh access work with the commands (you need to add -p 22 for pure ssh)

```{r, engine='bash', count_lines}
git clone git@docker.vm:root/demo-java.git

ssh -p 22 user@docker.vm
```

## Jenkins

```{r, engine='bash', count_lines}
http://docker.vm/jenkins/
```

Get the initial Secret

```{r, engine='bash', count_lines}
docker-compose exec jenkins cat /var/jenkins_home/secrets/initialAdminPassword
```

Install suggested plugins, setup account for administrator, e.g. `admin` / `admin` and use the appropriate URL
as Jenkins URL, e.g. http://docker.vm/jenkins/

To create a read-only `Jenkins` user in gitlab, follow the following steps:

Gitlab:
* Login gitlab with admin account and create a new user `jenkins`, ignore password.
* Admin area ---> users ---> edit `jenkins` user ---> set password (e.g. `jenkins123`)
* Add `jenkins` as member with role `Reporter` to project(s)
* Login using `jenkins`
* Change password as advised
* Add ssh key for jenkins to this account

Jenkins:
* Login to Jenkins as admin
* Jenkins -> Manage Jenkins -> System Configuration
  * Check the `Jenkins Location` URL to match the URL you see in the browser, e.g. http://docker.vm/jenkins/
* Jenkins -> Manage Jenkins -> Configure Global Security
  * Authorization Strategy: Project-based Matrix Authorization Strategy
* Jenkins -> Manage Jenkins -> Plugins
  * Update all Plugins http://docker.vm/jenkins/pluginManager/
  * Install Docker Pipeline Plugin: https://plugins.jenkins.io/docker-workflow/
  * Install Authorize Project: https://plugins.jenkins.io/authorize-project/
  * Check restart checkbox which will restart jenkins when finished installing to apply plugin updates
* Jenkins -> Manage Jenkins -> Configure Global Security
  * Access Control for Builds: Add `Project default build authorization`
  * `Run as SYSTEM`
  
* Jenkins -> Manage Jenkins -> Security -> Manage Credentials -> Global credentials - add
  * add `SSH username with private key` credentials `gitlab-ssh` for user `jenkins` and copy-paste the keyfile contents
  * add `secret file` credentials `demo-settings` containing the maven `settings.xml` from above
  * add `secret text` credentials `demo-sonar-token` containing the Sonarqube token created earlier  

It's important to define the names above as credential ID.

Manage credentials is in http://docker.vm/jenkins/credentials/store/system/domain/_/
  
After that, not only jenkins but the whole jenkins container needs to be restarted once. The reason for that
is the custom entrypoint script provided in this jenkins container. It adjusts the group id of the docker group
in the container to the docker group id on the host system. But this won't be effective until

```
docker-compose restart jenkins
```

To check if jenkins has access to your local docker daemon, run

```
docker-compose exec jenkins sudo docker ps
```

You should see the same output as `docker ps` outputs on the machine's console.
  
Create a jenkins project 
* named `demo-java` 
* using type `Multibranch Pipeline`
* Add branch source of type `git` with repository `ssh://git@docker.vm:10022/root/demo-java.git`
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


To integrate gitlab with Jenkins,

* Create a user `gitlab` in Jenkins
* Assign "Overall - Read" permission to gitlab in Global Security
* As user `gitlab` create an API token in http://docker.vm/jenkins/user/gitlab/configure which should look like this:
`115e09e85a035e5f2a166f0cffa7abad0c`
* In your project Open `Configure` (http://docker.vm/jenkins/job/demo-java/configure) 
   * check Properties -> Enable project-based security
   * Add user `gitlab` and allow Job -> Build  and Project -> Read
* Check by running `curl -v --user gitlab:115e09e85a035e5f2a166f0cffa7abad0c -X POST http://docker.vm/jenkins/job/demo-java/build`
or `http://gitlab:115e09e85a035e5f2a166f0cffa7abad0c@docker.vm/jenkins/job/demo-java/build`
the response should be HTTP 302 redirecting to the build log in  http://docker.vm/jenkins/job/demo-java/
* In gitlab navigate to your project -> Settings -> WebHooks
* Add WebHook for Push events to URL `http://[user]:[token]@docker.vm/jenkins/job/[job-name]/build` which is for this 
example `http://gitlab:115e09e85a035e5f2a166f0cffa7abad0c@docker.vm/jenkins/job/demo-java/build` which actually
corresponds to scanning the multibranch pipeline
* Uncheck SSL verification if you used self-signed certificates
* Click on Test, which should return the message `Hook executed successfully: HTTP 200`
* Now open jenkins again and push a change to gitlab, Jenkins should instantly build your code

Documentation for WebHooks with Jenkins are based on Jenkins API: https://www.jenkins.io/doc/book/using/remote-access-api/


# Shutdown and Destroy, Backup and Restore 

Useful commands are

```
# bring everything up
docker-compose up -d --build

# start all existing services
docker-compose start

# stop all services
docker-compose stop

# remove all services (keeps volumes, so data remains in the system)
docker-compose down

# remove all services - DELETE ALL DATA (volumes)
docker-compose down -v

# backup all volumes to tgz files
# it's better to stop all services before creating a backup
docker-compose stop
docker run --rm -v ci_gitlab_config:/mnt alpine tar czf - /mnt > ci_gitlab_config.tgz
docker run --rm -v ci_gitlab_data:/mnt   alpine tar czf - /mnt > ci_gitlab_data.tgz
docker run --rm -v ci_gitlab_logs:/mnt   alpine tar czf - /mnt > ci_gitlab_logs.tgz
docker run --rm -v ci_jenkins_data:/mnt  alpine tar czf - /mnt > ci_jenkins_data.tgz
docker run --rm -v ci_nexus_data:/mnt    alpine tar czf - /mnt > ci_nexus_data.tgz
docker run --rm -v ci_sonardb_data:/mnt  alpine tar czf - /mnt > ci_sonardb_data.tgz

# restore all volumes from tgz files
# the volumes should be emtpy or non-existent an will be created by these commands
cat ci_gitlab_config.tgz | docker run --rm -i -v ci_gitlab_config:/mnt alpine tar xzf -
cat ci_gitlab_data.tgz   | docker run --rm -i -v ci_gitlab_data:/mnt   alpine tar xzf -
cat ci_gitlab_logs.tgz   | docker run --rm -i -v ci_gitlab_logs:/mnt   alpine tar xzf -
cat ci_jenkins_data.tgz  | docker run --rm -i -v ci_jenkins_data:/mnt  alpine tar xzf -
cat ci_nexus_data.tgz    | docker run --rm -i -v ci_nexus_data:/mnt    alpine tar xzf -
cat ci_sonardb_data.tgz  | docker run --rm -i -v ci_sonardb_data:/mnt  alpine tar xzf -

```



