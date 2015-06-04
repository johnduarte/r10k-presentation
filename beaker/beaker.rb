test_name "Install puppet and r10k" do

step "Resolve puppet to master system"
hosts.each do |host|
  on host, "echo '#{master.get_ip} puppet' >> /etc/hosts"
end

step "Add puppetlabs repo to systems"
hosts.each do |host|
  platform = host['platform'].with_version_codename
  case platform
  when /^(fedora|el|centos)-(\d+)-(.+)$/
    variant = (($1 == 'centos') ? 'el' : $1)
    fedora_prefix = ((variant == 'fedora') ? 'f' : '')
    version = $2
    arch = $3
    on host, "rpm -ivh https://yum.puppetlabs.com/puppetlabs-release-#{variant}-#{version}.noarch.rpm"
  when /^(debian|ubuntu)-([^-]+)-(.+)$/
    variant = $1
    version = $2
    arch = $3
    on host, "wget https://apt.puppetlabs.com/puppetlabs-release-#{version}.deb"
    on host, "dpkg -i puppetlabs-release-#{version}.deb"
    on host, "apt-get update"
  else
    fail_test "unsupported os"
  end
end


step "Install puppet master"
master_platform = master['platform'].with_version_codename
case master_platform
when /^(fedora|el|centos)-(\d+)-(.+)$/
  on master, "yum install -y puppet-server"
when /^(debian|ubuntu)-([^-]+)-(.+)$/
  on master, "apt-get install -y puppetmaster-passenger"
else
  fail_test "unsupported os"
end

step "stop master server"
on(master, puppet('resource', 'service', master['puppetservice'], "ensure=stopped"))

step "Install puppet agent"
  install_package agent, 'puppet'

step "Configure puppet master"
on master, "sed -i s/^templatedir/#templatedir/ /etc/puppet/puppet.conf"
on master, "puppet master --verbose"
on master, "pkill puppet"
sleep 10
on(master, puppet('resource', 'service', master['puppetservice'], "ensure=running"))

step "Configure puppet agent"
on agent, "sed -i s/^templatedir/#templatedir/ /etc/puppet/puppet.conf"

on agent, "puppet agent -t", :acceptable_exit_codes => [0,1,2]
on master, "puppet cert sign --all"
on agent, "puppet agent -t"

step "Configure git on master"
install_package master, 'git'
on master, "git config --global user.email \"test@example.com\""
on master, "git config --global user.name \"test user\""

step "Configure r10k on master"
on master, "puppet module install zack/r10k"
r10k_man = <<EOD
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
create_remote_file(master, '/tmp/configure_r10k.pp', r10k_man)
on master, "puppet apply /tmp/configure_r10k.pp"
end

step "Configure directory environments"
on master, "sed -i '/^#templatedir/a environmentpath = $confdir/environments\\nbasemodulepath  = $confdir/modules' /etc/puppet/puppet.conf"
on master, "mkdir -p puppet-repo/src puppet-repo/git"
on master, "cd puppet-repo/git && git init --bare controller.git"
on master, "cd puppet-repo/git && git init --bare helloworld.git"
on master, "cd puppet-repo/src && git clone ../git/helloworld.git"
on master, "cd puppet-repo/src/helloworld && puppet module generate testing/helloworld --skip-interview"
on master, "cd puppet-repo/src/helloworld && mv testing-helloworld/* . && rm -rf testing-helloworld"
hello_man =<<EOD
class helloworld {
    notify { "Hello world!":
        message => "I am in the \${environment} environment",
    }
}
EOD
create_remote_file(master, '/root/puppet-repo/src/helloworld/manifests/init.pp', hello_man)
on master, "cd puppet-repo/src/helloworld && git add --all && git commit -m 'Add helloworld module' && git push -u origin master"


step "Checkout a working copy of your r10k controller"
on master, "cd puppet-repo/src && git clone ../git/controller.git"

env_man =<<EOD
modulepath = modules:\$basemodulepath
EOD
create_remote_file(master, '/root/puppet-repo/src/controller/environment.conf', env_man)
on master, "cd puppet-repo/src/controller && git add environment.conf && git commit -m 'Add environment.conf' && git branch -m production && git push -u origin production"

on master, "cd puppet-repo/src/controller && mkdir manifests"
site =<<EOD
node default {
    include helloworld
}
EOD

step "include module in site.pp"
create_remote_file(master, '/root/puppet-repo/src/controller/manifests/site.pp', site)
on master, "cd puppet-repo/src/controller && git add manifests && git commit -m 'Add helloworld module to default node' && git push"

step "add module to Puppetfile"
puppetfile =<<EOD
mod "helloworld",
  :git => "file:///root/puppet-repo/git/helloworld.git"
EOD
create_remote_file(master, '/root/puppet-repo/src/controller/Puppetfile', puppetfile)
on master, "cd puppet-repo/src/controller && git add Puppetfile && git commit -m 'Add Puppetfil to r10k controller' && git push"

step "Deploy"

on master, "r10k deploy environment -p -v"
on(master, puppet('resource', 'service', master['puppetservice'], "ensure=stopped"))
on(master, puppet('resource', 'service', master['puppetservice'], "ensure=running"))
