# -*- mode: ruby -*-
# vi: set ft=ruby :

Vagrant.require_version ">= 1.6"

if ["up", "provision", "status"].include?(ARGV.first)
  require_relative "vagrant/ansible_galaxy_helper"

  AnsibleGalaxyHelper.install_dependent_roles("deployment/ansible")
end

if !ENV["VAGRANT_ENV"].nil? && ENV["VAGRANT_ENV"] == "TEST"
  ANSIBLE_ENV_GROUPS = {
    "test:children" => [
      "app-servers",
      "database-servers",
      "celery-servers"
    ]
  }
  VAGRANT_NETWORK_OPTIONS = { auto_correct: true }
else
  ANSIBLE_ENV_GROUPS = {
    "development:children" => [
      "app-servers",
      "database-servers",
      "celery-servers"
    ]
  }
  VAGRANT_NETWORK_OPTIONS = { auto_correct: false }
end

ANSIBLE_GROUPS = {
  "app-servers" => [ "app" ],
  "database-servers" => [ "database" ],
  "celery-servers" => [ "celery" ]
}
# Local install patch: modern OpenSSH clients (8.8+) refuse SHA-1 "ssh-rsa"
# signatures, the only RSA kind the Ubuntu 14.04 guests understand. Re-enable
# it for Ansible's connections in case an RSA key is used.
ANSIBLE_RAW_SSH_ARGS = [
  "-o PubkeyAcceptedKeyTypes=+ssh-rsa",
  "-o HostKeyAlgorithms=+ssh-rsa"
]

MOUNT_OPTIONS = if Vagrant::Util::Platform.linux? then
                  ['rw', 'tcp', 'nolock']
                else
                  ['vers=3', 'udp']
                end

Vagrant.configure("2") do |config|
  config.vm.box = "ubuntu/trusty64"

  if Vagrant.has_plugin?("vagrant-hostmanager")
    config.hostmanager.enabled = true
    config.hostmanager.manage_host = false
    config.hostmanager.ignore_private_ip = false
    config.hostmanager.include_offline = true
  else
    $stderr.puts "\nERROR: Please install the vagrant-hostmanager plugin."
    exit(1)
  end

  config.vm.define "database" do |database|
    database.vm.hostname = "database"
    # installing redis on the database server
    database.hostmanager.aliases = %w(database.service.driver.internal redis.service.driver.internal)
    database.vm.network "private_network", ip: "192.168.12.101"

    # For PGAdmin access, uncomment and `vagrant reload`
    # database.vm.network "forwarded_port", guest: 5432, host: Integer(ENV.fetch("DRIVER_DATABASE_PORT_5432", 5432))

    database.vm.synced_folder ".", "/vagrant", disabled: true

    database.vm.provision "ansible" do |ansible|
      ansible.playbook = "deployment/ansible/database.yml"
      ansible.groups = ANSIBLE_GROUPS.merge(ANSIBLE_ENV_GROUPS)
      ansible.raw_arguments = ["--timeout=60"]
      ansible.raw_ssh_args = ANSIBLE_RAW_SSH_ARGS
      ansible.compatibility_mode = "2.0"
    end

    database.ssh.forward_x11 = true

    database.vm.provider :virtualbox do |v|
      v.memory = ENV.fetch("DRIVER_DATABASE_MEM", 2048)
      v.cpus = ENV.fetch("DRIVER_DATABASE_CPU", 2)
    end
  end

  config.vm.define "app" do |app|
    app.vm.hostname = "app"
    app.hostmanager.aliases = %w(app.service.driver.internal)
    app.vm.network "private_network", ip: "192.168.12.102"

    # Disable because this will not get used.
    app.vm.synced_folder ".", "/vagrant", disabled: true

    app.vm.synced_folder "./app", "/opt/app", type: "nfs", mount_options: MOUNT_OPTIONS
    app.vm.synced_folder "./web", "/opt/web", type: "nfs", mount_options: MOUNT_OPTIONS
    app.vm.synced_folder "./windshaft", "/opt/windshaft", type: "nfs", mount_options: MOUNT_OPTIONS
    app.vm.synced_folder "./schema_editor", "/opt/schema_editor", type: "nfs", mount_options: MOUNT_OPTIONS

    # nginx
    app.vm.network "forwarded_port", guest: 80, host: Integer(ENV.fetch("DRIVER_WEB_PORT_80", 7000))
    # Runserver
    app.vm.network "forwarded_port", guest: 4000, host: Integer(ENV.fetch("DRIVER_DJANGO_PORT_3000", 3000))
    # Runserver interactive
    app.vm.network "forwarded_port", guest: 8000, host: Integer(ENV.fetch("DRIVER_DJANGO_PORT_8000", 3001))
    # Grunt serve - schema editor
    app.vm.network "forwarded_port", guest: 9000, host: Integer(ENV.fetch("DRIVER_GRUNT_PORT_7001", 7001))
    # Grunt serve - web app
    app.vm.network "forwarded_port", guest: 9001, host: Integer(ENV.fetch("DRIVER_GRUNT_PORT_7002", 7002))
    # editor livereload
    app.vm.network "forwarded_port", guest: 35731, host: 35731
    # web livereload
    app.vm.network "forwarded_port", guest: 35732, host: 35732
    # Docker
    app.vm.network "forwarded_port", guest: 2375, host: 2375

    app.vm.provision "ansible" do |ansible|
      ansible.playbook = "deployment/ansible/app.yml"
      ansible.groups = ANSIBLE_GROUPS.merge(ANSIBLE_ENV_GROUPS)
      ansible.limit = "app,database"  # local install patch: was "all"; keeps a celery problem from blocking the app VM
      ansible.raw_arguments = ["--timeout=60"]
      ansible.raw_ssh_args = ANSIBLE_RAW_SSH_ARGS
      ansible.compatibility_mode = "2.0"
    end

    app.ssh.forward_x11 = true

    app.vm.provider :virtualbox do |v|
      v.memory = ENV.fetch("DRIVER_APP_MEM", 3584)
      v.cpus = ENV.fetch("DRIVER_APP_CPUS", 2)
    end
  end

  config.vm.define "celery" do |celery|
    celery.vm.hostname = "celery"
    celery.hostmanager.aliases = %w(celery.service.driver.internal)
    celery.vm.network "private_network", ip: "192.168.12.103"

    # Disable because this will not get used.
    celery.vm.synced_folder ".", "/vagrant", disabled: true

    celery.vm.synced_folder "./app", "/opt/app", type: "nfs", mount_options: MOUNT_OPTIONS
    celery.vm.synced_folder "./web", "/opt/web", type: "nfs", mount_options: MOUNT_OPTIONS
    celery.vm.synced_folder "./analysis_tasks", "/opt/analysis_tasks", type: "nfs", mount_options: MOUNT_OPTIONS
    celery.vm.synced_folder "./schema_editor", "/opt/schema_editor", type: "nfs", mount_options: MOUNT_OPTIONS
    # jar build task on celery vm
    celery.vm.synced_folder "./gradle", "/opt/gradle", type: "nfs", mount_options: MOUNT_OPTIONS

    # Docker
    celery.vm.network "forwarded_port", guest: 2375, host: 2376

    celery.vm.provision "ansible" do |ansible|
      ansible.playbook = "deployment/ansible/celery.yml"
      ansible.groups = ANSIBLE_GROUPS.merge(ANSIBLE_ENV_GROUPS)
      ansible.limit = "celery"  # local install patch: was "all" (database firewall rules are applied by the app run)
      ansible.raw_arguments = ["--timeout=60"]
      ansible.raw_ssh_args = ANSIBLE_RAW_SSH_ARGS
      ansible.compatibility_mode = "2.0"
    end

    celery.ssh.forward_x11 = true

    celery.vm.provider :virtualbox do |v|
      v.memory = ENV.fetch("DRIVER_CELERY_MEM", 3584)
      v.cpus = ENV.fetch("DRIVER_CELERY_CPUS", 2)
    end
  end
end
