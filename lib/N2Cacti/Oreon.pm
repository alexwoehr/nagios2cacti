# tsync:: casole
# sync:: calci
###########################################################################
#                                                                         #
# N2Cacti::Oreon                                                          #
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

use strict;

package N2Cacti::Oreon;

use DBI();
use N2Cacti::database;
use N2Cacti::Config;
use POSIX qw(ceil floor);

#
# new
#
# The constructor
#
# @args		: class name and parameters
# @return	: the object
#
sub new {
	my $class=shift;
	my $attr = shift;
	my %param = %$attr if $attr;

	my $this = {};
	$this->{oreon_dir}	= $param{oreon_dir}||"/usr/lib/oreon";
	bless($this,$class);
	$this->load_config_database();
	$this->{database} = new N2Cacti::database({
		database_type		=> "mysql",
		database_schema		=> $this->{oreon_config}->{db},
		database_hostname	=> $this->{oreon_config}->{host}|| "localhost",
		database_username	=> $this->{oreon_config}->{user},
		database_password	=> $this->{oreon_config}->{password},
		database_port		=> "3306"
	});
    return $this;
}

#
# database
#
# Gets the database object
#
# @args		: none
# @return	: the database object
#
sub database {
	return shift->{database};
}

#
# searchTemplate
#
# Search a template by alias
#
# @args		: its type and its name
# @return	: hash ref result
#
sub searchTemplate {
	my ($this, $type, $name)	= (@_);

	Main::log_msg("N2Cacti::Oreon::searchTemplate(): type must be egal : host or service", "LOG_ERR") if ($type ne "host" && $type ne "service");
	my $result = $this->database->db_fetch_hash("$type", {$type."_alias" => $name, $type."_register" => '0'});

	return $result
}

#
# searchItem
#
# Search a host or service by alias
#
# @args		: its type and its name
# @return	: hash ref result
#
sub searchItem {
	my ($this, $type, $name)	= (@_);

	Main::log_msg("N2Cacti::Oreon::searchItem(): type must be egal : host or service", "LOG_ERR") if ($type ne "host" && $type ne "service");
	my $result = $this->database->db_fetch_hash("$type", {$type."_alias" => $name, $type."_register" => '1'});

	return $result
}

#
# searchHost_hostname
#
# Search a host by hostname
#
# @args		: its name
# @return	: hash ref result
#
sub searchHost_hostname {
	my ($this, $name)	= (@_);
	my $result		= $this->database->db_fetch_hash("host", {"host_name" => $name, "host_register" => '1'});

	return $result;
}

#
# searchHost
#
# Search a host by ip address
#
# @args		: its address
# @return	: hash ref result
#
sub searchHost {
    my ($this, $address) = (@_);
    my $result = $this->database->db_fetch_hash("host", {host_address => $address, "host_register" => '1'});
    return $result
}

#
# createHost
#
# Creates a host in Oreon
#
# @args		: the template's name, the parameters
# @return	: host hash ref
#
sub createHost {
	my $this 	= shift;
	my $tpl_name	= shift;
	my $attr 	= shift;

	my %param 	= %$attr if $attr;

	my ($template, $host);

	return undef if (!defined($attr));

	#-- add parameter to check only the host and not the template
	$param{host_register}='1';
	$param{host_activate}='1';
	return undef if (!defined($param{host_name}));

	#-- search host by address or name	
	#--  	the first collect failed on create virtual host
	#--		the second collect is based on host_name = HOST_DBNAME
	$host =  $this->database->db_fetch_hash("host", {host_address => $param{host_address}}) if (defined($param{host_address}));
	$host =  $this->database->db_fetch_hash("host", {host_name => $param{host_name}}) if(!defined($host));

	if ( not defined($host) ) {
		print "host $param{host_name} not found, we will create\n";
		$template	= $this->searchTemplate("host", $tpl_name);
		unless(defined($template)){
			Main::log_msg("N2Cacti::Oreon::createHost(): template $tpl_name not found", "LOG_DEBUG");
			return undef;
		}
		
		$host = ();
		while (my ($key, $value)=each(%param)){
			$host->{$key} = $value;
		}

		$host->{host_template_model_htm_id} = $template->{host_id};
		delete ($host->{command_command_id});
		delete ($host->{command_command_id2});
		delete ($host->{timeperiod_tp_id});
		delete ($host->{timeperiod_tp_id2});
		delete ($host->{purge_policy_id});
		
		$host->{host_id} = $this->database->table_save("host", $host);

		my $hostei = {
			host_host_id =>  $host->{host_id},
			ehi_id =>  $host->{host_id}
		};

		$hostei->{ehi_id}=$this->database->table_save("extended_host_information", $hostei);
	} else {
		#-- UPDATE value
		my $hostname_tmp = $host->{host_name};

		while (my ($key, $value)=each(%param)){
			$host->{$key} = $value;
		}

		$host->{host_name} = $hostname_tmp;
		$host->{host_id} = $this->database->table_save("host", $host);

		my $hostei = {
			host_host_id	=> $host->{host_id},
			ehi_id		=> $host->{host_id}
		};

		$hostei->{ehi_id} = $this->database->table_save("extended_host_information", $hostei);
	}

	return $host;
}

#
# addGroupHost
#
# Creates a group host
#
# @args		: its name and the host
# @return	: hash ref result
#
sub addGroupHost{
	my ($this, $groupName, $host) = (@_);

	my $group 	= $this->database->db_fetch_hash("hostgroup", { hg_name => $groupName});
	$group 		= $this->database->db_fetch_hash("hostgroup", { hg_alias => $groupName}) if (!defined($group));

	if ( not defined($group) ) {
		Main::log_msg("N2Cacti::Oreon::addGroupHost(): the hostgroup $groupName not found! we will create it", "LOG_DEBUG");
		$group = $this->database->new_hash("hostgroup");
		$group->{hg_alias}		= $groupName;
		$group->{hg_name}		= $groupName;
		$group->{hg_activate}		= 1;
		$group->{hg_snmp_version}	= 1;

		delete ($group->{country_id});
		delete ($group->{city_id});

		$group->{hg_id}			= $this->database->table_save("hostgroup",$group);
		Main::log_msg("N2cacti::Oreon::addGroupHost(): failed to create the group $groupName"," LOG_ERR") if (!defined($group->{hg_id}));
	}
	
	my $hostgroup_relation	= $this->database->db_fetch_hash("hostgroup_relation", {
		hostgroup_hg_id	=> $group->{hg_id},
		host_host_id	=> $host->{host_id},
	});

	if ( not defined($hostgroup_relation) ) {
		$hostgroup_relation = $this->database->new_hash("hostgroup_relation");
		$hostgroup_relation->{hostgroup_hg_id}	= $group->{hg_id};
		$hostgroup_relation->{host_host_id}	= $host->{host_id};
		$hostgroup_relation->{hgr_id}		= $this->database->table_save("hostgroup_relation",$hostgroup_relation);

		Main::log_msg("N2Cacti::Oreon::addGroupHost(): failed to associate the group $groupName with the host $$host{host_name}", "LOG_ERR") if (!defined($hostgroup_relation->{hgr_id}));
	}

	return $hostgroup_relation;
}

#
# newVirtualAddress
#
# Gives a 127.0.*.* address
#
# @args		: none
# @return	: the address
#
sub newVirtualAddress {
	my $this	= shift;
	
	my $sth		= $this->database->execute("select host_address from host where host_address like '127%'");
	my $address_max	= 1;

	while (my @row 	= $sth->fetchrow()){
		my @digit	= split(/\./,$row[0]);
		my $address	= $digit[3]+$digit[2]*256;
		$address_max = $address if ($address>$address_max);
	}
	$address_max++;
	return "127.0.".floor($address_max/256).".".$address_max%256;
}

#
# load_config_database
#
# Loads configuration database from oreon conf file
#
# @args		: none
# @return	: none
#
sub load_config_database {
	my $this 	= shift; 

	my $oreon_path	= $this->{oreon_dir}."/www/oreon.conf.php";
	$oreon_path 	= $this->{oreon_dir}."/oreon.conf.php" if (!-f $oreon_path);

	Main::log_msg("N2Cacti::Oreon::load_config_database(): cannot find Oreon configuration at $oreon_path", "LOG_CRIT") if (! -f $oreon_path);

	open CFG, '<', $oreon_path
        or Main::log_msg("N2Cacti::Oreon::createHost():unable to open $oreon_path", "LOG_DEBUG");
	$this->{oreon_config}={host=>'', user=>'', password=>'', db=>'', ods=>''};

	while(<CFG>){
		chomp;
		next if /^#/;			# Skip comments
		next if /^$/;			# Skip empty lines
		next if !/^\$conf_oreon/;	# Skip no parameter lines
		s/#.*//;			# Remove partial comments
		s/\$conf_oreon//;		# Remove $conf_oreon
		s/\"//g;			# Remove "
		s/(;|\ )//g;				
		s/'//g;
		s/\[//g;
		s/\]//g;

		if(/^(.*)=(.*)$/) {
			if(defined($this->{oreon_config}->{$1})){
				$this->{oreon_config}->{$1}=$2;
			} else{
				Main::log_msg("N2Cacti::Oreon::load_config_database(): oreon configuration parameter unknown : $1 = $2", "LOG_DEBUG");
			}
		}
	}
}

1;

