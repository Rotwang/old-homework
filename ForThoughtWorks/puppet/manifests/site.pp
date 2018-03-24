# $serverip wont do as it may use wrong ip if we have more than one "public" interface
# so probably those values must be hardcoded here
# however with properly set up dns we wouldn't have to worry about that
# (these two below wouldn't be necessary).
$master_ip = '10.0.2.5'
$prod_ip = '10.0.2.4'

stage { 'INIT':
        before => Stage['main'],
}
stage { 'POST': }
Stage['main'] -> Stage['POST']

exec { 'clearcron':
        # in case the cron was modified by hand
        # by someone, remove everything
        command => "/bin/sh -c 'echo | crontab'",
}

cron { 'puppetagent':
        command => 'bash -c \'sleep $((RANDOM\%600)); puppet agent\'',
        user    => root,
        minute  => '*/30',
        require => Exec['clearcron'],
}

package { ['htop',
           'ncdu',
           'unzip',
           'openjdk-7-jre-headless',
           'screen']:
        ensure => installed,
}

# puppet agent is to be started by cron
service { 'puppet':
        ensure => stopped,
        enable => false,
}

class { 'timezone':
        timezone => 'Europe/Warsaw',
}

user { 'preseed':
        ensure => absent,
        managehome => true,
}

class { 'ntp':
        servers => ['0.pl.pool.ntp.org',
                    '1.pl.pool.ntp.org',
                    '2.pl.pool.ntp.org',
                    '3.pl.pool.ntp.org']
}
service { ['ssh', 'rsyslog']:
        ensure => running,
        enable => true,
}


class { 'docker': }

node 'training' {

        service { 'tomcat7':
                ensure => running,
                enable => true,
                require => Package['tomcat7'],
        }

        service { 'dnsmasq':
                ensure => running,
                enable => true,
                require => Package['dnsmasq'],
                before => Package['tomcat7'], # es of hack because puppet is shit
        }

        file { '/etc/hosts':
                ensure => file,
                content => template("training-hosts.erb"),
                notify => Service['dnsmasq']
        }

        package { ['git', 'dnsmasq', 'tomcat7']:
                ensure => installed,
        }

        class { 'jenkins': }

        # group scm so jenkins can clone/push to the git repo
        # group tomcat7 so jenkins can deploy the application
        user { 'jenkins':
                groups => ['scm', 'tomcat7'],
                notify => Service['jenkins'],
                require => [Package['jenkins'], User['scm']]
        }

        file { "/var/lib/jenkins/.ssh/":
                ensure => directory,
                mode => '0700',
                owner => 'jenkins',
                group => 'jenkins',
                require => User['jenkins'],
        }

        file { "/var/lib/jenkins/.ssh/id_rsa":
                ensure => file,
                mode => '0600',
                source => "puppet:///files/jenkins-id_rsa",
                owner => 'jenkins',
                group => 'jenkins',
                require => File['/var/lib/jenkins/.ssh'],
        }

        file { "/var/lib/jenkins/.ssh/id_rsa.pub":
                ensure => file,
                mode => '0600',
                source => "puppet:///files/jenkins-id_rsa.pub",
                owner => 'jenkins',
                group => 'jenkins',
                require => File['/var/lib/jenkins/.ssh'],
        }

        file { '/etc/default/jenkins':
                ensure => file,
                source => 'puppet:///files/default/jenkins',
                notify => Service['jenkins'],
        }

        file { '/etc/sudoers.d/jenkins':
                ensure => file,
                source => 'puppet:///files/sudoers.d/jenkins',
                mode => '0440',
        }


        docker::image { 'tomcat':
                image_tag => '7',
                ensure => present,
        }

        docker::image { 'registry':
                ensure => present,
        }

        docker::run { 'companyregistry':
                image => 'registry',
                use_name => true,
                ports => ['5000:5000'],
                require => Docker::Image['registry'],
        }

        class { 'sysdig': }

        # Account for git repos.
        user { 'scm':
                ensure => present,
                managehome => true,
        }

        # filesystem for the persistence layer
        file { ['/home/russell', '/home/russell/persistence/']:
                ensure => directory,
                owner => "tomcat7",
                group => "tomcat7",
		require => Package['tomcat7'],
        }
}

node 'production' {
        # this is just hacking around dns (the dns servers may be prepended by the dhcpclient
        file { "/etc/dhcp/dhclient-enter-hooks.d/nodnsupdate":
                ensure => file,
                source => "puppet:///files/nodnsupdate",
        }

        file { "/etc/resolv.conf":
                ensure => file,
                source => "puppet:///files/production-resolv.conf",
        }

        user { 'blog':
                ensure => present,
                managehome => true,
        }

        file { '/home/blog/.ssh':
                ensure => directory,
                mode => '0700',
                owner => 'blog',
                group => 'blog',
                require => User['blog'],
        }

        file { '/home/blog/.ssh/authorized_keys':
                ensure => file,
                source => "puppet:///files/jenkins-id_rsa.pub",
                mode => '0600',
                owner => 'blog',
                group => 'blog',
                require => File['/home/blog/.ssh'],
        }

        file { '/etc/sudoers.d/blog':
                ensure => file,
                source => 'puppet:///files/sudoers.d/blog',
                mode => '0440',
        }

        file { '/var/lib/companynews_persistence':
                ensure => directory,
        }
}
