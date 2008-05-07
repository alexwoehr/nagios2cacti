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
use Error qw(:try);

BEGIN {
        use Exporter   	();
        use vars       	qw($VERSION @ISA @EXPORT @EXPORT_OK);
        @ISA 		=	qw(Exporter);
        @EXPORT 	= 	qw();
}



my $tables ={
	'data_input'				=> '',
	};

sub new {
    # -- contient la definition des tables
    my $class = shift;
	my $attr=shift;
	my %param = %$attr if $attr;
    my $this={
        tables                              => $tables,
		source								=> $param{source} || "Nagios",
		log_msg								=> $param{cb_log_msg}			|| \&default_log_msg,
        };

	#-- Connexion to cacti database
	my $cacti_config = get_cacticonfig();
	$this->{database} 						= new N2Cacti::database({
        database_type       => $$cacti_config{database_type},
        database_schema     => $$cacti_config{database_default},
        database_hostname   => $$cacti_config{database_hostname},
        database_username   => $$cacti_config{database_username},
        database_password   => $$cacti_config{database_password},
        database_port       => $$cacti_config{database_port},
        log_msg				=> \&log_msg });


    $this->{database}->set_raise_exception(1); # for error detection with try/catch
        
    bless ($this, $class);
    return $this;
}

sub database{
    return shift->{database};
}

sub table_save {
	my $this = shift;
	my $tablename=shift;
	if(defined($this->{tables}->{$tablename})){
		return $this->database->sql_save(shift ,$tablename);
	}
	die "N2Cacti::Graph::table_save - wrong parameter tablename value : $tablename";
}

sub create_method(){
	my $this 		= shift;
    my $command_name = "$$this{source} import via n2cacti";
    my $debug       = shift ||0;

    my $hash 		= generate_hash($command_name);
    if(!$this->database->item_exist("data_input", {
    	hash => $hash})){
	    my $di = $this->database->new_hash("data_input");
	    $di->{name}		= $command_name;
	    $di->{hash}		= $hash;
	    $di->{type_id}	= "1";
	    $di->{id}		= $this->table_save("data_input",$di);
	    return $di->{id};
	}
	try {
		return $this->database->get_id("data_input", {
			hash => $hash });
	}
	catch  Error::Simple with{
		$this->log_msg('ERROR cant to find data_input');
		die "ERROR cant to find data_input";
	}
}

sub default_log_msg{
	my $message=shift;
	$message=~ s/\n$//g;
	print "default:$message\n";
}

sub log_msg {
    my $this=shift;
    my $message=shift;
	$message=~ s/\n$//g;
    &{$this->{log_msg}}("$message\n");
}


1;

