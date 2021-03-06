# tsync:: casole
# sync:: calci
###########################################################################
#                                                                         #
# N2Cacti::Cacti::Method                                                   #
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

package N2Cacti::Cacti::Method;

use strict;
use DBI();
use N2Cacti::Cacti;
use N2Cacti::database;
use Digest::MD5 qw(md5 md5_hex md5_base64);

BEGIN {
        use Exporter   	();
        use vars       	qw($VERSION @ISA @EXPORT @EXPORT_OK);
        @ISA 		=	qw(Exporter);
        @EXPORT 	= 	qw();
}



my $tables ={
	'data_input' => '',
};

#
# new
#
# The constructor
#
# @args		: the parameters { tables, source }
# @return	: the object
# 
sub new {
	my $class	= shift;
	my $attr	= shift;

	my %param	= %$attr if $attr;
	my $this	= {
	        tables	=> $tables,
		source	=> $param{source} || "Nagios"
        };

	#-- Connexion to cacti database
	my $cacti_config	= get_cacticonfig();
	$this->{database}	= new N2Cacti::database({
		database_type		=> $$cacti_config{database_type},
		database_schema		=> $$cacti_config{database_default},
		database_hostname	=> $$cacti_config{database_hostname},
		database_username	=> $$cacti_config{database_username},
		database_password	=> $$cacti_config{database_password},
		database_port		=> $$cacti_config{database_port}
	});

	bless ($this, $class);
	return $this;
}

#
# database
#
# Database accessor
#
# @args		: none
# @return	: database object
#
sub database{
    return shift->{database};
}

#
# table_save
#
# Calls sql_save
#
# @args		: the table name
# @return	: sql_save result or undef
#
sub table_save {
	my $this	= shift;
	my $tablename	= shift;

	if ( defined($this->{tables}->{$tablename}) ) {
		return $this->database->sql_save(shift ,$tablename);
	} else {
		Main::log_msg("N2Cacti::Graph::table_save(): wrong parameter tablename value : $tablename", "LOG_ERR");
		return undef;
	}
}

#
# create_method
#
# Creates a new method
#
# @args		: none
# @return	: the method_id
#
sub create_method {
	my $this		= shift;
	my $command_name	= "$$this{source} import via n2cacti";

	Main::log_msg("--> N2Cacti::Cacti::Method::create_method()", "LOG_DEBUG");
	my $hash		= generate_hash($command_name);

	if ( not $this->database->item_exist("data_input", {hash => $hash}) ){
		my $di		= $this->database->new_hash("data_input");
		$di->{name}	= $command_name;
		$di->{hash}	= $hash;
		$di->{type_id}	= "1";
		$di->{id}	= $this->table_save("data_input",$di);

		Main::log_msg("<-- N2Cacti::Cacti::Method::create_method()", "LOG_DEBUG");
		return $di->{id};
	} else {
		my $id		= $this->database->get_id("data_input", { hash => $hash });
		Main::log_msg("<-- N2Cacti::Cacti::Method::create_method()", "LOG_DEBUG");
		return $id;
	}
}

1;

