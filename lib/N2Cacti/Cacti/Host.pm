# tsync::casole imola
###########################################################################
#                                                                         #
# N2Cacti::Cacti::Host                                                    #
# Written by <detrak@caere.fr>                                            #
#                                                                         #
# This program is free software; you can redistribute it and/or modify it #
# under the terms of the GNU General Public License as published by the   #
# Free Software Foundation; either version 2, or (at your option) any     #
# later version.                                                          #
#                                                                         #
# This program is distributed in the hope that it will be useful, but     #
# WITHOUT ANY WARRANTY; without even the implied warranty of              #
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU       #
# General Public License for more details.                                #
#                                                                         #
###########################################################################


package N2Cacti::Cacti::Host;

use strict;
use DBI();
use N2Cacti::Cacti;
use N2Cacti::database;
use Digest::MD5 qw(md5 md5_hex md5_base64);
#use Exception qw(:try);

BEGIN {
        use Exporter   	();
        use vars       	qw($VERSION @ISA @EXPORT @EXPORT_OK);
        @ISA 		=	qw(Exporter);
        @EXPORT 	= 	qw();
}


#CREATE TABLE#  `db_cacti`.`host` (
#  `id` mediumint(8) unsigned NOT NULL auto_increment,
#  `host_template_id` mediumint(8) unsigned NOT NULL default '0',
#  `description` varchar(150) NOT NULL default '',
#  `hostname` varchar(250) default NULL,
#  `snmp_community` varchar(100) default NULL,
#  `snmp_version` tinyint(1) unsigned NOT NULL default '1',
#  `snmp_username` varchar(50) default NULL,
#  `snmp_password` varchar(50) default NULL,
#  `snmp_port` mediumint(5) unsigned NOT NULL default '161',
#  `snmp_timeout` mediumint(8) unsigned NOT NULL default '500',
#  `disabled` char(2) default NULL,
#  `status` tinyint(2) NOT NULL default '0',
#  `status_event_count` mediumint(8) unsigned NOT NULL default '0',
#  `status_fail_date` datetime NOT NULL default '0000-00-00 00:00:00',
#  `status_rec_date` datetime NOT NULL default '0000-00-00 00:00:00',
#  `status_last_error` varchar(50) default '',
#  `min_time` decimal(10,5) default '9.99999',
#  `max_time` decimal(10,5) default '0.00000',
#  `cur_time` decimal(10,5) default '0.00000',
#  `avg_time` decimal(10,5) default '0.00000',
#  `total_polls` int(12) unsigned default '0',
#  `failed_polls` int(12) unsigned default '0',
#  `availability` decimal(8,5) NOT NULL default '100.00000',
#  PRIMARY KEY  (`id`)
#) ENGINE=MyISAM DEFAULT CHARSET=latin1


#CREATE TABLE  `db_cacti`.`host_template` (
#  `id` mediumint(8) unsigned NOT NULL auto_increment,
#  `hash` varchar(32) NOT NULL default '',
#  `name` varchar(100) NOT NULL default '',
#  PRIMARY KEY  (`id`)
#) ENGINE=MyISAM DEFAULT CHARSET=latin1

my $tables ={
	'host'				=> '',
	'host_template'			=> '',
	};

sub new {
	# -- contient la definition des tables
	my $class = shift;
	my $attr=shift;
	my %param = %$attr if $attr;
	my $this={
		tables		=> $tables,
		hostname	=> $param{hostname},
		hostaddress	=> $param{hostaddress},
		source		=> $param{source} || "Nagios"
	};

	#-- Connexion to cacti database
	my $cacti_config = get_cacticonfig();
	$this->{database} = new N2Cacti::database({
		database_type		=> $$cacti_config{database_type},
		database_schema		=> $$cacti_config{database_default},
		database_hostname	=> $$cacti_config{database_hostname},
		database_username	=> $$cacti_config{database_username},
		database_password	=> $$cacti_config{database_password},
		database_port		=> $$cacti_config{database_port},
	});

#	$this->{database}->set_raise_exception(1); # for error detection with try/catch
        
	bless ($this, $class);
	return $this;
}

sub database{
	return shift->{database};
}

sub table_save {
	my $this = shift;
	my $tablename=shift;
	if ( defined($this->{tables}->{$tablename} ) ) {
		return $this->database->sql_save(shift ,$tablename);
	} else {
		Main::log_msg("N2Cacti::Graph::table_save(): wrong parameter tablename value : $tablename", "LOG_ERR");
		return undef;
	}
}

sub create_template {
	my $this = shift;
	my $template_name = "$$this{source} supervised host";

	Main::log_msg("--> N2Cacti::Cacti::Host::create_template()", "LOG_DEBUG") if $this->{debug};

	my $hash = generate_hash($template_name);

	if(!$this->database->item_exist("host_template", {hash => $hash})){
		Main::log_msg("N2Cacti::Cacti::Host::create_template(): let's create the host template", "LOG_DEBUG") if $this->{debug};

		my $ht = $this->database->new_hash("host_template");

		$ht->{name} = $template_name;
		$ht->{hash} = $hash;
		$ht->{id} = $this->table_save("host_template",$ht);

		Main::log_msg("<-- N2Cacti::Cacti::Host::create_template()", "LOG_DEBUG") if $this->{debug};
		return $ht->{id};
	} else {
		Main::log_msg("N2Cacti::Cacti::Host::create_template(): the host template already exists", "LOG_DEBUG") if $this->{debug};

		my $value = $this->{database}->get_id("host_template", {hash => $hash });

		if ( not scalar $value ) {
			Main::log_msg("N2Cacti::Cacti::Host::create_template(): cannot find host_template with hash : $hash", "LOG_ERR");
			return undef;
		} else {
			Main::log_msg("<-- N2Cacti::Cacti::Host::create_template()", "LOG_DEBUG") if $this->{debug};
			return $value;
		}
	}
}

sub create_host {
	my $this = shift;
 
	#-- create the template if needed else grab the id
	my $ht_id = $this->create_template();
	my $hostid;
	my $h;
    
	Main::log_msg("--> N2Cacti::Cacti::Host::create_host()", "LOG_DEBUG") if $this->{debug};

	#-- return if the item exist
	if( $this->database->item_exist("host",{host_template_id => $ht_id, description => $this->{hostname},}) == 0 ) {
		Main::log_msg("N2Cacti::Cacti::Host::create_host(): let's create the host", "LOG_DEBUG") if $this->{debug};

		$h = $this->database->new_hash("host");
		$h->{hostname} = $this->{hostaddress};
		$h->{host_template_id} = $ht_id;
		$h->{hostname} = $this->{hostaddress}; #hostaddress in nagios will be the unique key to identify an host
		$h->{description} = $this->{hostname}; #hostname in nagios will be display
		$h->{disabled} = "on"; #the host are supervised by nagios, they are disable in cacti!
		$h->{id} = $this->table_save("host", $h);
	} else {
		Main::log_msg("N2Cacti::Cacti::Host::create_host(): the host already exists", "LOG_DEBUG") if $this->{debug};

		$h->{id} = $this->database->get_id("host", {host_template_id => $ht_id, description => $this->{hostname},});
	}

	Main::log_msg("<-- N2Cacti::Cacti::Host::create_host()", "LOG_DEBUG") if $this->{debug};
	return $h->{id};
}

1;

