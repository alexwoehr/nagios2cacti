# tsync:: casole
# sync:: calci
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
use N2Cacti::Config qw(load_config get_config);
use Digest::MD5 'md5_hex'; 

BEGIN {
        use Exporter   ();
        use vars qw($VERSION @ISA @EXPORT @EXPORT_OK);
        @ISA = qw(Exporter);
        @EXPORT = qw(generate_hash print_hash $data_source_type $graph_item_types $image_types $cdef_functions $consolidation_functions get_cacticonfig);
}

#---------------------------------------------------

my %__data_source_type=(
	1 => "GAUGE",
	2 => "COUNTER",
	3 => "DERIVE",
	4 => "ABSOLUTE"
);

my %__consolidation_functions = (
	1 => "AVERAGE",
	2 => "MIN",
	3 => "MAX",
	4 => "LAST"
);

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
	10 =>"LEGEND"
);

my %__image_types = (
	1 => "PNG",
	2 => "GIF"
);

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
	26  =>  "LTIME"
);

our $cdef_functions = reverse_hash(\%__cdef_functions);
our $image_types = reverse_hash(\%__image_types);
our $graph_item_types = reverse_hash(\%__graph_item_types);
our $consolidation_functions = reverse_hash(\%__consolidation_functions);
our $data_source_type = reverse_hash(\%__data_source_type);


#
# generate_hash
#
# Creates a md5sum to prevent duplicates
#
# @args		: the string to process
# @return	: the hash
#
sub generate_hash {
	my $string=shift || "N2Cacti::Cacti".rand(1000).time();
	return md5_hex($string);
}

#
# get_cacticonfig
#
# Gets Cacti's properties from its config file
#
# @args		:
# @return	:
#
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
	or Main::log_msg("N2Cacti::Cacti::get_cacticonfig(): unable to open ".$config->{CACTI_DIR}."include/config.php", "LOG_ERR") and return undef;
	while(<CFG>){
		chomp;
		next if /^#/;    		# Skip comments
		next if /^$/;    		# Skip empty lines
		next if !/^\$database/; 	# Skip no parameter lines
		s/#.*//;         		# Remove partial comments
		s/\$//; 			# Remove $
		s/\"//g;
		s/(;|\ )//g;

		if(/^(.*)=(.*)$/) {
			if(defined($$cacti_config{$1})){
				$cacti_config->{$1}=$2;
			} else {
				Main::log_msg("N2Cacti::Cacti::get_cacticonfig(): cacti configuration parameter unknown : $1 = $2", "LOG_WARNING");
			}
		}
	}
	return $cacti_config;
}


#
# print_hash
#
# A basic hash to string function
#
# @args		: the hash
# @return	: none
#
sub print_hash {
	print "hash:\n";
	my $hash = shift;

	while (my ($key, $value)=each (%$hash)){
		print "'$key' - '$value'\n";
	}
}

#
# reverse_hash
#
# Keys <-> values switch
#
# @args		: the hash
# @return	: the switched hash
#
sub reverse_hash {
    my $hash = shift;
    my $hash_out = {};
    while (my ($key, $value)=each (%$hash)){
        $hash_out->{$value} = $key;
    }
    return $hash_out;
}

#
# database
#
# Gets the DB object
#
sub database {
	return shift->{database};
}

1;

