###########################################################################
#                                                                         #
# N2Cacti::Cacti                                                          #
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

package N2Cacti::Cacti;

use DBI();
use N2Cacti::database;
use N2Cacti::Config qw(load_config log_msg get_config);
use Digest::MD5 'md5_hex'; 

BEGIN {
        use Exporter   ();
        use vars       qw($VERSION @ISA @EXPORT @EXPORT_OK);
        @ISA = qw(Exporter);
        @EXPORT = qw(generate_hash print_hash $data_source_type $graph_item_types $image_types $cdef_functions $consolidation_functions get_cacticonfig);
}

#---------------------------------------------------

my %__data_source_type=(
    1 => "GAUGE",
    2 => "COUNTER",
    3 => "DERIVE",
    4 => "ABSOLUTE");
my %__consolidation_functions = (
    1 => "AVERAGE",
    2 => "MIN",
    3 => "MAX",
    4 => "LAST");

my %__graph_item_types = (
    1 => "COMMENT",
    2 => "HRULE",
    3 => "VRULE",
    4 => "LINE1",
    5 => "LINE2",
    6 => "LINE3",
    7 => "AREA",
    8 => "STACK",
    9 => "GPRINT",
    10 =>"LEGEND");

my %__image_types = (
    1 => "PNG",
    2 => "GIF");

my %__cdef_functions = (
    1   => "SIN",
    2   =>  "COS",
    3   =>  "LOG",
    4   =>  "EXP",
    5   =>  "FLOOR",
    6   =>  "CEIL",
    7   =>  "LT",
    8   =>  "LE",
    9   =>  "GT",
    10  =>  "GE",
    11  =>  "EQ",
    12  =>  "IF",
    13  =>  "MIN",
    14  =>  "MAX",
    15  =>  "LIMIT",
    16  =>  "DUP",
    17  =>  "EXC",
    18  =>  "POP",
    19  =>  "UN",
    20  =>  "UNKN",
    21  =>  "PREV",
    22  =>  "INF",
    23  =>  "NEGINF",
    24  =>  "NOW",
    25  =>  "TIME",
    26  =>  "LTIME");
our $cdef_functions				= reverse_hash(\%__cdef_functions);
our $image_types 				= reverse_hash(\%__image_types);
our $graph_item_types 			= reverse_hash(\%__graph_item_types);
our $consolidation_functions	= reverse_hash(\%__consolidation_functions);
our $data_source_type         	= reverse_hash(\%__data_source_type);


#-----------------------------------------------------------------
# -- genere un clé unique via un hash md5
# -- utiliser par cacti pour eviter des doublons lors d'import/export
sub generate_hash {
	my $string=shift || "N2Cacti::Cacti".rand(1000).time();
	return md5_hex($string);
}


#--------------------------------------------------------------

sub get_cacticonfig{
	my $config = get_config();
	my $cacti_config = {
		database_type 		=> 'mysql',
		database_default 	=> 'cacti',
		database_hostname	=> 'localhost',
		database_username	=> 'cacti',
		database_password	=> '******',
		database_port		=> '3306',
		};

	open CFG, '<', $config->{CACTI_DIR}."/include/config.php"
        or die("unable to open ".$config->{CACTI_DIR}."include/config.php\n");
    while(<CFG>){
        chomp;
        next if /^#/;    			# Skip comments
        next if /^$/;    			# Skip empty lines
        next if !/^\$database/; 	# Skip no parameter lines
        s/#.*//;         			# Remove partial comments
        s/\$//; 					# Remove $
		s/\"//g;
		s/(;|\ )//g;
        if(/^(.*)=(.*)$/) {
            if(defined($$cacti_config{$1})){
                $cacti_config->{$1}=$2;
            }
            else{
                log_msg("cacti configuration parameter unknown : $1 = $2");
            }
        }
    }
    
    return $cacti_config;
}


#--------------------------------------------------------------


sub print_hash {
	print "hash:\n";
    my $hash = shift;
    while (my ($key, $value)=each (%$hash)){
        print "'$key' - '$value'\n";
    }
}

sub reverse_hash {
    my $hash = shift;
    my $hash_out = {};
    while (my ($key, $value)=each (%$hash)){
        $hash_out->{$value} = $key;
    }
    return $hash_out;
}

#---------------------------------------------------------------

sub database {
	my $this = shift;
	return $this->{database};
}







#********************** DEPRECATED ******************************

#-----------------------------------------------------------------
# find the template
sub get_host_template {
	my $this=shift;
	my $match = shift;
	my $host_templates = shift || $this->get_host_templates();
	while (my ($key,$name) =each (%$host_templates)){
		if($name=~/$match/){
			return $key;
		}
	}

	if($match ne "nagios"){
		return $this->get_host_template("nagios", $host_templates);
	}
	
	log_msg("no template found - you need to configure cacti and create a host template to nagios host - report to INSTALL file, cacti configuration");

	exit 1;
}

# renvoie la liste de tous les templates hotes classer par id comme clé
sub get_host_templates {
	#my $match=shift||"nagios";
	my $this=shift;
	my $db=$this->{database};
	my $sth=$this->{database}->execute("select id, name from host_template order by id");
	my $host_templates={};
	while(my @row=$sth->fetchrow()){
		$host_templates->{$row[0]}=$row[1];
	}
	return $host_templates;
}

#-----------------------------------------------------------------

sub display_host_templates {
	my $this=shift;
	my %host_templates = shift;
	print "valid host templates :\n";
	while (my ($id, $name) = each (%host_templates)){
		print "$id => $name\n";
	}
	print "\n";
}


#-----------------------------------------------------------------
#
# Retrieve all known hosts from Cacti's DB
#
sub get_hosts
{
	my $this=shift;
    my $hosts={};
    my $sth = $this->{database}->execute("select id, description from host order by description");
	while(my @row = $sth->fetchrow()){
        $hosts->{$row[0]} = $row[1];
	}

    return $hosts;
}


#-----------------------------------------------------------------

# api_device_remove - removes a device
#   @arg $device_id - the id of the device to remove 
sub api_device_remove {
	my $this=shift;
	my $device_id=shift;
    $this->{database}->execute("delete from host where id=$device_id");
    $this->{database}->execute("delete from host_graph where host_id=$device_id");
    $this->{database}->execute("delete from host_snmp_query where host_id=$device_id");
    $this->{database}->execute("delete from host_snmp_cache where host_id=$device_id");
    $this->{database}->execute("delete from poller_item where host_id=$device_id");
    $this->{database}->execute("delete from poller_reindex where host_id=$device_id");
    $this->{database}->execute("delete from graph_tree_items where host_id=$device_id");
    $this->{database}->execute("update data_local set host_id=0 where host_id=$device_id");
    $this->{database}->execute("update graph_local set host_id=0 where host_id=$device_id");
}



# api_device_dq_remove - removes a device->data query mapping
#   @arg $device_id - the id of the device which contains the mapping
#   @arg $data_query_id - the id of the data query to remove the mapping for 
sub api_device_dq_remove {
	my $this=shift;
	my $device_id=shift;
	my $data_query_id=shift;
    $this->{database}->execute("delete from host_snmp_cache where snmp_query_id=$data_query_id and host_id=$device_id");
    $this->{database}->execute("delete from host_snmp_query where snmp_query_id=$data_query_id and host_id=$device_id");
    $this->{database}->execute("delete from poller_reindex where data_query_id=$data_query_id and host_id=$device_id");
}

# api_device_gt_remove - removes a device->graph template mapping
#   @arg $device_id - the id of the device which contains the mapping
#   @arg $graph_template_id - the id of the graph template to remove the mapping for
sub api_device_gt_remove {
	my $this=shift;
    my $device_id=shift;
    my $graph_template_id=shift;

    $this->{database}->execute("delete from host_graph where graph_template_id=$graph_template_id and host_id=$device_id");
}


# ce script appel le script add_device.php pour eviter de tout reimplementer
sub add_device{
	my $this	=shift;
	my ($deviceid,$hostname,$address,$snmp_community,$snmp_version,$disabled)=(shift, shift, shift, shift || "public", shift || 2, shift || 1);
	my $debug 	= shift || 0;
	my $add_device_script=$this->{config}->{CACTI_DIR}."/add_device.php";
	`$add_device_script $deviceid $hostname $address $snmp_community $snmp_version $disabled`;
	log_msg("add device '$hostname' to '$address' in cacti") if $debug;;
}

# get_host_templates("nagios");
sub api_device_save {
	my $this=shift;
	my ($id, $host_template_id, $description, $hostname, $snmp_community, $snmp_version,
    $snmp_username, $snmp_password, $snmp_port, $snmp_timeout, $disabled) = (@_);

	my $_host_template_id = 0;
	if(defined($id)&&$id!=0){
		$_host_template_id = $this->database_fetch_cell("select host_template_id from host where id=$id");
    }

	my $save={};
    $save->{"id"} = $id;
    $save->{"host_template_id"} = $host_template_id;
    $save->{"description"} = $description;
    $save->{"hostname"} = $hostname;
    $save->{"snmp_community"} = $snmp_community;
    $save->{"snmp_version"} = $snmp_version;
    $save->{"snmp_username"} = $snmp_username;
    $save->{"snmp_password"} = $snmp_password;
    $save->{"snmp_port"} = $snmp_port;
    $save->{"snmp_timeout"} = $snmp_timeout;
    $save->{"disabled"} = $disabled;

    my $host_id = sql_save($save, "host");

    return $host_id;
}



1;


