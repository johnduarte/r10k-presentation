# r10k {data-background="images/dark-mario.png"}

##

This is a repackaging of tutorials offered by

  * [Adrien Thebo](https://github.com/adrienthebo/r10k-workshop/blob/master/WORKSHOP.mkd)
  * [Gary Larizza](http://garylarizza.com/blog/2014/08/31/r10k-plus-directory-environments/)


## What is it?

  * A deployment tool
  * Manage environments with git
  * Manage modules with Puppetfile (YAML file for defining module sources)
  * Simple tool with great power


## Key components

  * r10k.yaml
  * git branches
  * Puppetfile


## Key concept

  * r10k creates (and destroys) environments corresponding to your git repo
    branches
  * r10k allows you to specify modules to install, including versions via
    Puppetfile
  * This allows you to rapidly test on classified systems and merge your
    changes



# Install Puppet {data-background="images/dark-dirty-hands.jpg"}

## Resolve puppet

~~~~
/etc/hosts
~~~~

Make sure that both machines can resolve `puppet` to the master


## SSH in a for loop {data-background="images/dark-austin-powers.jpg"}


Add puppetlabs apt repo to systems

On *local machine*

~~~~
hosts=('master' 'agent')
for host in ${hosts[@]}
do
    ssh root@$host "wget https://apt.puppetlabs.com/puppetlabs-release-precise.deb"
    ssh root@$host "dpkg -i puppetlabs-release-precise.deb"
    ssh root@$host "apt-get update"
done
~~~~


## Install Puppet Master {data-background="images/dark-puppet.jpg"}

On *master*, install puppet master

    apt-get install -y puppetmaster-passenger


## Stop Master Server {data-background="images/dark-puppet.jpg"}

On *master*, stop apache

    service apache2 stop


## Install Puppet Agent {data-background="images/dark-puppet.jpg"}

On *agent*, install puppet

    apt-get install -y puppet


# Configure Puppet master {data-background="images/dark-puppet.jpg"}


##

On *master*, comment out the templatedir directive in the `main` section of `puppet.conf`

    sed -i s/^templatedir/#templatedir/ /etc/puppet/puppet.conf


##

On *master*, create CA

    puppet master --verbose --no-daemonize

NOTE: Kill this process after the following is displayed:

    Notice: Starting Puppet master version <VERSION>


##

On *master*, start apache

    service apache2 start


# Configure Puppet agent {data-background="images/dark-puppet.jpg"}


##

On *agent*, comment out the templatedir directive in the `main` section of `puppet.conf`

    sed -i s/^templatedir/#templatedir/ /etc/puppet/puppet.conf


##

On *agent*, run agent to generate cert

    puppet agent -t


##

On *master*, sign agent cert

    puppet cert sign --all


##

On *agent*, run agent to get catalog

    puppet agent -t


# Configure git {data-background="images/dark-git.png"}

~~~~
apt-get install -y git
git config --global user.email "test@example.com"
git config --global user.name "test user"
~~~~


# Configure r10k on master {data-background="images/dark-mario.png"}


##

On *master*, install r10k modules and dependencies

    puppet module install zack/r10k


##

On *master*, install and configure r10k using module

~~~~
cat > configure_r10k.pp <<EOD
class { 'r10k':
  version           => '1.3.2',
  sources           => {
    'puppet' => {
        'remote'  => 'file:///root/puppet-repo/git/controller.git',
        'basedir' => "\${::settings::confdir}/environments",
        'prefix'  => false,
    }
  },
  purgedirs         => ["\${::settings::confdir}/environments"],
  manage_modulepath => false,
}
EOD
puppet apply configure_r10k.pp
~~~~


# Configure directory environments {data-background="images/dark-directory.jpg"}


##

On *master*, add directives to `main` section of `puppet.conf`

~~~~
[main]
....
environmentpath = $confdir/environments
basemodulepath  = $confdir/modules
~~~~

# Set up git resources {data-background="images/dark-git.png"}


## Create git repo for r10k controller

On *master*, but in the real world this would be on a development system

~~~~
mkdir -p puppet-repo/src puppet-repo/git
cd puppet-repo/git
git init --bare controller.git
~~~~


## Create git repo for test module

On *master*, but in the real world this would be on a development system

    git init --bare helloworld.git


## Create an external module

On *master*, but in the real world this would be on a development system

~~~~
cd ../src
git clone ../git/helloworld.git
cd helloworld
puppet module generate testing/helloworld --skip-interview
mv testing-helloworld/* .
rm -rf testing-helloworld
cat > manifests/init.pp <<EOD
class helloworld {
    notify { "Hello world!":
        message => "I am in the \${environment} environment",
    }
}
EOD
git add --all
git commit -m "Add helloworld module"
git push -u origin master
~~~~


## Checkout a working copy of your r10k controller

On *master*, but in the real world this would be on a development system

~~~~
cd ..
git clone ../git/controller.git
cd controller
~~~~


## Prepare production environment

In git checkout of controller ...

~~~~
cat > environment.conf <<EOD
modulepath = modules:\$basemodulepath
EOD
git add environment.conf
git commit -m "Add environment.conf"
git branch -m production
git push -u origin production
~~~~


## Include the module in site.pp

~~~~
mkdir manifests
cd manifests
cat > site.pp <<EOD
node default {
    include helloworld
}
EOD
cd ../
git add manifests
git commit -m "Add helloworld module to default node"
git push
~~~~


## Add module to Puppetfile

~~~~
cat > Puppetfile <<EOD
mod "helloworld",
  :git => "file:///root/puppet-repo/git/helloworld.git"
EOD
git add Puppetfile
git commit -m "Add Puppetfile to r10k controller"
git push
~~~~


# Fully Operational {data-background="images/dark-death-star.jpg"}

## Contents of control checkout

In git checkout of controller ...

~~~~
tree ../controller
../controller/
├── environment.conf
├── manifests
│   └── site.pp
└── Puppetfile
~~~~

## Deploy

On *master*, run r10k to deploy production environment

    r10k deploy environment -p -v
    service apache2 restart


## Inspect

You should now have the helloworld module associated with the production
environment on the system.

On *master*, inspect helloworld in production environment

    cat /etc/puppet/environments/production/modules/helloworld/manifests/init.pp


## Apply

Applying the production environment on the agent should result in the hello
world message notifying you that it is classified to the production
environment.

On *agent*, run agent to get catalog

    puppet agent -t


## Create post-update hook {data-background="images/dark-git.png"}

Manually deploying is something git can automate for us.

Create a post-update hook to do this for us

~~~~
cat >> ../../git/controller.git/hooks/post-update <<EOD
#!/bin/sh
r10k deploy environment -p -v && service apache2 restart
EOD
chmod +x ../../git/controller.git/hooks/post-update
~~~~


## Create branch


On *master*, but in the real world this would be on a development system

In git checkout of controller ...

    git checkout -b testing
    git push -u origin testing


## Inspect

You should now have the helloworld module associated with the testing
environment on the system.

On *master*, inspect helloworld in testing environment

    cat /etc/puppet/environments/testing/modules/helloworld/manifests/init.pp


## Classify agent to branch

On *agent*, add the following section to the `puppet.conf`

    [agent]
    environment = testing


## Apply

On *agent*, run agent to get catalog

    puppet agent -t


## Add module to Puppetfile

We will now add an module to the Puppetfile in the testing branch.

On *master*, but in the real world this would be on a development system

In git checkout of controller ...

~~~~
cat >> Puppetfile <<EOD

mod "puppetlabs/motd"
EOD
git add Puppetfile
git commit -m "Add motd to testing env"
git push
~~~~


## Inspect

The motd module is now installed in the testing
environment on the system, but not in the production environment.

On *master*, inspect the modules installed for both the production and testing
environments.

    ls /etc/puppet/environments/testing/modules
    ls /etc/puppet/environments/production/modules


## Destroy Environment

We will now destroy the testing environment by deleting the testing branch.

On *master*, but in the real world this would be on a development system

In git checkout of controller ...

~~~~
git checkout production
git branch -D testing
git push origin --delete testing
~~~~


## Inspect

The testing environment is now history.

On *master*, inspect the environments installed on the master

    ls /etc/puppet/environments


# r10k {data-background="images/dark-mario.png"}

## Questions?
