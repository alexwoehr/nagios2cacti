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

#-----------------------------------------------------------------
sub new {
    my $class=shift;
    my $attr = shift;
    my %param = %$attr if $attr;

    my $this = {};
	$this->{oreon_dir}	= $param{oreon_dir}||"/usr/lib/oreon";
    #$this->{config}= &N2Cacti::Config::load_config();
    bless($this,$class);
	$this->load_config_database();
    $this->{database} = new N2Cacti::database({
        database_type       => "mysql",
        database_schema     => $this->{oreon_config}->{db},
        database_hostname   => $this->{oreon_config}->{host}|| "localhost",
        database_username   => $this->{oreon_config}->{user},
        database_password   => $this->{oreon_config}->{password},
        database_port       => "3306",
        log_msg				=> \&log_msg}); 
    return $this;
}

#-- Accesseur
sub database{return shift->{database};}

#-- search a template by alias
sub searchTemplate {
	my ($this, $type, $name) = (@_);
	die "type must be egal : host or service" if ($type ne "host" && $type ne "service");
	my $result = $this->database->db_fetch_hash("$type", {$type."_alias" => $name, $type."_register" => '0'});
	return $result
}

#-- search a host or service by alias
sub searchItem {
	my ($this, $type, $name) = (@_);
	die "type must be egal : host or service" if ($type ne "host" && $type ne "service");
	my $result = $this->database->db_fetch_hash("$type", {$type."_alias" => $name, $type."_register" => '1'});
	return $result
}

sub searchHost_hostname {
	my ($this, $name) = (@_);
	my $result = $this->database->db_fetch_hash("host", {"host_name" => $name, "host_register" => '1'});
    return $result;
}

sub searchHost {
    my ($this, $address) = (@_);
    my $result = $this->database->db_fetch_hash("host", {host_address => $address, "host_register" => '1'});
    return $result
}



sub createHost {
	my $this 		= shift;
	my $tpl_name	= shift;
    my $attr 		= shift;
	my $debug		= shift || 0;
	my ($template, $host);
    my %param 		= %$attr if $attr;
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
	if (!defined($host)){
		print "host $param{host_name} not found, we will create\n";
		$template	= $this->searchTemplate("host", $tpl_name);
		unless(defined($template)){
			log_msg "template $tpl_name not found";
			return undef;
		}
		
		$host = ();
		#$host = $this->database->new_hash("host");
		while (my ($key, $value)=each(%param)){
			#if(defined ($host->{$key})){
				$host->{$key} = $value;
			#}
			#else{
			#	log_msg "fields $key unknow in table host";
			#}
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
	}
	else{
		#return $host;
		#-- UPDATE value
		my $hostname_tmp = $host->{host_name};
        while (my ($key, $value)=each(%param)){
            $host->{$key} = $value;
        }
		$host->{host_name} = $hostname_tmp;
		$host->{host_id} = $this->database->table_save("host", $host);
		my $hostei = {
			host_host_id =>  $host->{host_id},
			ehi_id =>  $host->{host_id}
			};
		$hostei->{ehi_id}=$this->database->table_save("extended_host_information", $hostei);
	}
	return $host;
}

sub addGroupHost{
	my ($this, $groupName, $host) = (@_);
	#-- search group
	my $group 	= $this->database->db_fetch_hash("hostgroup", { hg_name => $groupName});
	$group 		= $this->database->db_fetch_hash("hostgroup", { hg_alias => $groupName}) if (!defined($group));

	if(!defined($group)){
		log_msg "the hostgroup $groupName not found! we will create it";
		$group = $this->database->new_hash("hostgroup");
		$group->{hg_alias}			= $groupName;
		$group->{hg_name}			= $groupName;
		$group->{hg_activate}		= 1;
		$group->{hg_snmp_version}	= 1;
		delete ($group->{country_id});
		delete ($group->{city_id});
		$group->{hg_id}				= $this->database->table_save("hostgroup",$group);
		die "failed to create the group $groupName" if (!defined($group->{hg_id}));
	}
	
	my $hostgroup_relation = $this->database->db_fetch_hash("hostgroup_relation", {
		hostgroup_hg_id	=>	$group->{hg_id},
		host_host_id	=>	$host->{host_id},
		});
	if(!defined($hostgroup_relation)){
		$hostgroup_relation = $this->database->new_hash("hostgroup_relation");
		$hostgroup_relation->{hostgroup_hg_id}	= $group->{hg_id};
		$hostgroup_relation->{host_host_id}		= $host->{host_id};
		$hostgroup_relation->{hgr_id}			= $this->database->table_save("hostgroup_relation",$hostgroup_relation);
		die "failed to associate the group $groupName with the host $$host{host_name}" if (!defined($hostgroup_relation->{hgr_id}));
	}

	return $hostgroup_relation;
}

sub newVirtualAddress {
	my $this = shift;
	
	my $sth = $this->database->execute("select host_address from host where host_address like '127%'");
	my $address_max = 1;
	while (my @row 	= $sth->fetchrow()){
		my @digit	= split(/\./,$row[0]);
		my $address	= $digit[3]+$digit[2]*256;
		$address_max = $address if ($address>$address_max);
	}
	$address_max++;
	return "127.0.".floor($address_max/256).".".$address_max%256;
}


#-- Load configuration database from oreon conf file
sub load_config_database {
	my $this 		= shift; 
	my $oreon_path	= $this->{oreon_dir}."/www/oreon.conf.php";
	$oreon_path 	= $this->{oreon_dir}."/oreon.conf.php" if (!-f $oreon_path);
	die "configuration oreon introuvable at $oreon_path"  if (! -f $oreon_path);

	open CFG, '<', $oreon_path
        or log_msg("unable to open $oreon_path");
	$this->{oreon_config}={host=>'', user=>'', password=>'', db=>'', ods=>''};

    while(<CFG>){
        chomp;
        next if /^#/;               # Skip comments
        next if /^$/;               # Skip empty lines
        next if !/^\$conf_oreon/;   # Skip no parameter lines
        s/#.*//;                    # Remove partial comments
        s/\$conf_oreon//;           # Remove $conf_oreon
        s/\"//g;					# Remove "
        s/(;|\ )//g;				
        s/'//g;
        s/\[//g;
        s/\]//g;
        if(/^(.*)=(.*)$/) {
            if(defined($this->{oreon_config}->{$1})){
                $this->{oreon_config}->{$1}=$2;
            }
            else{
                log_msg("oreon configuration parameter unknown : $1 = $2");
            }
   		}
	}
}


1;
