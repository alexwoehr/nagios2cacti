# tsync:: casole
# sync:: calci
###########################################################################
#                                                                         #
# N2Cacti::RRD                                                            #
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

package N2Cacti::RRD;
use lib '/HOME/rrdtool/lib/perl/5.8.8/x86_64-linux-thread-multi';
use RRDs;
use N2Cacti::Config qw(load_config get_config);
use N2Cacti::Archive;
use N2Cacti::Oreon;
use N2Cacti::database;

BEGIN {
        use Exporter   	();
        use vars       	qw($VERSION @ISA @EXPORT @EXPORT_OK);
        @ISA 		=	qw(Exporter);
        @EXPORT 	= 	qw();
}

our $ngs_perf_table_create=0;

#
# new
#
# The constructor
#
# @args		: its name, tje parameters
# @return	: the object
#
sub new {
	my $class = shift;
	my $attr = shift;
	my %param = %$attr if $attr;

	Main::log_msg("service_description and hostname required to get parameter of rrd file", "LOG_CRIT") and return undef if ( ! defined  ($param{service_description}) );

	my $this = {
		service_description	=> $param{service_description},
		hostname		=> $param{hostname} || undef,
		config 			=> get_config(),
		start_time		=> $param{start_time} || time,
		template		=> "", 	# template name
		service_name		=> "",	# service name (without @template_name else service_description in maps case)
		rra_file		=> "", 	# template file .t
		step			=> "300",
		rrd_file 		=> "", 	# path to main rrd file (contains datasource in template.t file)
		rrd_file_older		=> "",	# older path to rrd file, need to migrate file
		perf_rrd_file		=> "",
		datasource		=> {}, 	# hash of hash datasource -- add path to rrd file for each datasource
		ds_rewrite		=> {}, 	# detail of datasource rewrite
		service_maps		=> {},	# hash of service maps
		valid			=> 1,	# flag if item can be store in RRD

		# -- specific member variable for storage in mysql database
		host_id			=> 0,	# Oreon : host-id 		
		service_id		=> 0,	# Oreon : service-id 	
		table_created		=> 0,	 
		with_mysql		=> $param{with_mysql} || 0, 
		disable_mysql		=> 0,
	};

	bless($this,$class);
    
	$$this{valid} = 0 if ( ! $this->initialize() );
	return $this;
}

#
# validate
#
# Gets the validate attribute
#
# @args		: none
# @return	: the attribute
#
sub validate {
	my $this = shift;
	Main::log_msg("N2Cacti::RRD::item valid : $$this{valid}", "LOG_DEBUG");
	return $$this{valid};
}

#
# hostname
#
# Sets/gets the hostname attribute
#
# @args		: the hostname
# @return	: the hostname
#
sub hostname {
	my $this	= shift;
	my $hostname	= shift;
	$this->{hostname}=$hostname if (defined ($hostname ));
	return $this->{hostname};
}

#
# service_description
#
# Sets/gets the service description
#
# @args		: the service description
# @return	: the service description
#
sub service_description {
	my $this		= shift;
	my $service_description	= shift ||undef;
	$this->{service_description}=$service_description if (defined ($service_description ));
	return $this->{service_description};
}

#
# getTemplate
#
# Gets the template name
#
# @args		: none
# @return	: the template name
#
sub getTemplate {
	my $this = shift;
	return $$this{template};	
}

#
# getPathRRD
#
# Gets the path of the given datasource
#
# @args		: the datasource
# @return	: the rrd file
#
sub getPathRRD {
	my $this 	= shift;
	my $datasource 	= shift;

	if ( defined($datasource) ) {
		return $this->{datasource}->{$datasource}->{rrd_file};
	} else {
		return $this->{rrd_file};
	}
}

#
# setPathRRD
#
# Sets the path of the given datasource
#
# @args		: the datasource's path and the datasource
# @return	: none
#
sub setPathRRD {
	my $this	= shift;
	my $path	= shift;
	my $datasource	= shift;
	
	if (defined($datasource)){
		$this->{datasource}->{$datasource}->{rrd_file} = $path;
	}
	else {
		$this->{rrd_file} = $path;
	}
}

#
# getDataSource
#
# Gets the datasource
#
# @args		: none
# @return	: the datasource
#
sub getDataSource {
	my $this = shift;
	return $$this{datasource};
}

#
# getServiceName
#
# Gets the service name
#
# @args		: none
# @return	: the service name
#
sub getServiceName {
	my $this = shift;
	return $$this{service_name};
}

#
# update_rrd_el
#
# Updates the statistics RRD
#
# @args		: 
# @return	:
#
sub update_rrd_el {
	my $this 	= shift;
	my $execution	= shift;
	my $latency	= shift;
	my $state	= shift;	
	my $timestamp	= shift || time;

	my $config 	= $this->{config};     # variable de config issue de config.pm

#	return undef if (!$this->validate());

	Main::log_msg("--> N2Cacti::RRD::update_rrd_el()", "LOG_DEBUG") ;
	if ( -f $$this{perf_rrd_file} ){
		my $ds_value = "$execution:$latency";
		my $rrderror = RRDs::error;

		RRDs::update( "$$this{perf_rrd_file}", "--template", "$$this{ds_name_el}", "$timestamp:$ds_value" );

		Main::log_msg ("N2Cacti::RRD::update_rrd_el(): update $$this{perf_rrd_file} $$this{ds_name_el} with $ds_value", "LOG_DEBUG");
		Main::log_msg ("N2Cacti::RRD::update_rrd_el(): update $$this{perf_rrd_file} $$this{ds_name_el} with $ds_value", "LOG_ERR") if $rrderror;
	}

	#--------------------------------------
	#-- Support for mysql storage database
	if ( $this->with_mysql() ) {
		Main::log_msg ("N2Cacti::RRD::update_rrd_el(): store to mysql ", "LOG_DEBUG");
		my $database = new N2Cacti::database({
			database_type		=> "mysql",
			database_schema		=> $$config{PERFDB_NAME},
			database_hostname	=> $$config{PERFDB_HOST},
			database_username	=> $$config{PERFDB_USER},
			database_password	=> $$config{PERFDB_PASSWORD},
			database_port		=> "3306",
		});

		my $ngs_result={
			state 			=> $state,
			execution_time		=> $execution,
			latency			=> $latency,
			host_id			=> $$this{host_id},
			service_id		=> $$this{service_id},
			date_check 		=> $timestamp,		
		};

	if ( $ngs_perf_table_create == 0 ) {
		my $fields = {
			id         	=> 'bigint NOT NULL auto_increment primary key ',
			date_check	=> "timestamp NOT NULL default CURRENT_TIMESTAMP on update CURRENT_TIMESTAMP",
			host_id		=> 'int(11) NOT NULL',
			service_id	=> 'int(11) NOT NULL',
			state		=> 'varchar(10) NOT NULL',
			execution_time	=> 'REAL NOT NULL',
			latency		=> 'REAL NOT NULL',
		};

		$database->table_create("NGS_RESULT", $fields);
		$ngs_perf_table_create = 1;
	}

	my $query = "INSERT INTO NGS_RESULT(date_check, host_id, service_id, state, execution_time, latency) 
		VALUES(FROM_UNIXTIME('$timestamp'),'$$this{host_id}','$$this{service_id}', '$state', '$execution', '$latency');";
	$database->execute($query);
	}
	Main::log_msg("<-- N2Cacti::RRD::update_rrd_el()", "LOG_DEBUG");
}

#
# parse_perfdata
#
# Parses the perfdata and explode the cleaned datasource
#
# @args		: the perfdata string
# @return	: the tab split
#
sub parse_perfdata{
	my $perfdata = shift;

	my $result = [];
	my ($key,$value);

	# removing blanck spaces around =
	$perfdata =~ s/\s+=/=/g;
	$perfdata =~ s/=\s+/=/g;

	# removing non standard characters
	foreach (split /;/, $perfdata) {
		($key, $value) = split '=', $_;

		$key =~ s/ /_/g;
		$key =~ s/'//g;

		$value =~ s/[A-Za-z\/\%]//g;

		push @$result, "$key=$value";
	}

	return @$result;
}

#
# update_rrd
#
# Updates the RRD files
#
# @args		: the ouput (perfdata), the timestamp and the mysql storage boolean
# @return	: OK (1) || KO (0)
#
sub update_rrd {
	my $this		= shift;
	my $output		= shift; 
	my $timestamp		= shift || time;
	my $store_to_mysql	= shift || 0;

	my @data = ();
	my $config = $this->{config}; # variable de config issue de config.pm
	my $ds_names = "";
	my $ds_values = "";
	my $ret_code = 1;
	my $timestamp2 = 0;
	my $rrderror;

	Main::log_msg("--> N2Cacti::RRD::update_rrd()", "LOG_DEBUG");

#	if ( not $this->validate() ) {
#		Main::log_msg("N2Cacti::RRD::update_rrd(): validate() returned false", "LOG_DEBUG");
#		return 0;
#	}

#	if ( ! -f $$this{rrd_file} ) {
#		$this->initialize();
#		Main::log_msg("N2Cacti::RRD::update_rrd(): error the base rrd does not exist ! $$this{rrd_file}", "LOG_CRIT") and return undef if ( ! -f $$this{rrd_file} );
#	}
#
#	if ( -f $$this{rrd_file} ) {
#		#-- Loading plugin.pm
#		if ( -f "$$config{CONF_DIR}/$$config{TEMPLATES_DIR}/plugin.pm" ) {
#			if ( open P, '<', "$$config{CONF_DIR}/$$config{TEMPLATES_DIR}/plugin.pm" ) {
#	    			my @PERLCODE = <P>;
#				close P;
#				my $result_str = eval join("\n",@PERLCODE);warn $@ if $@;
#			} else {
#				Main::log_msg("N2Cacti::RRD::update_rrd(): Can't open perl code file \"$$config{CONF_DIR}/$$config{TEMPLATES_DIR}/plugin.pm\"", "LOG_CRIT");
#			}
#		}

		#-- possibility for external performance data parsing
		if ( -f "$$config{CONF_DIR}/$$config{TEMPLATES_DIR}/code/$$this{template}.pl" ) {
			if ( open P, '<', "$$config{CONF_DIR}/$$config{TEMPLATES_DIR}/code/$$this{template}.pl" ) {
				my @PCODE = <P>	;
				close P;

				my $ret_str = eval join("\n",@PCODE);warn $@ if $@;

				$ret_str =~ s/\s+=/=/g;
				$ret_str =~ s/=\s+/=/g;

				@data = split /\s/, $ret_str;
			} else {
        			Main::log_msg("N2Cacti::RRD::update_rrd(): Can't open perl code file \"$$config{CONF_DIR}/$$config{TEMPLATES_DIR}/code/$$this{template}.pl", "LOG_ERR");
				$ret_code = 0;
			}
		} else {
			# remove spaces before and/or after "=" character
			#$output =~ s/\s+=/=/g;
			#$output =~ s/=\s+/=/g;
			#@data = ( $output =~ /(\S+=[0-9\.]+)/g );

			@data = parse_perfdata($output);
		}

		my $ds_rewrite = $$this{ds_rewrite};
		my $perf_main = {};
		my $perf_single = {};

		foreach my $kv (@data) {
			my $ds_name;
			my ( $key, $val ) = split /=/, $kv;

			Main::log_msg("N2Cacti::RRD::update_rrd(): rewrite = $key : $val : $$ds_rewrite{$key}", "LOG_DEBUG");

			if ( defined ($$ds_rewrite{"$$this{service_name}_$key"}) ){
				Main::log_msg("N2Cacti::RRD::update_rrd(): rewrite $key to $$ds_rewrite{$key}", "LOG_DEBUG");
				$ds_name .= $$ds_rewrite{"$$this{service_name}_$key"};
			} else {
				$ds_name .= "$key";
			}

			$perf_single->{$ds_name} = $val;

#			if ( defined ($this->{datasource}->{$ds_name}) && $this->{datasource}->{$ds_name}->{rrd_file} eq $$this{rrd_file} ) {
#				$perf_main->{$ds_name} = $val;
#			} else {
#				$perf_single->{$ds_name} = $val;
#			}
		}
#
#		#-- update main rrd database
#		foreach my $key (keys %$perf_main) {
#			$ds_names .= "$key:";
#			$ds_values .= $perf_main->{$key}.":";
#		}
#
#		$ds_names =~ s/:$//;
#		$ds_values =~ s/:$//;
#
#		if ( $ds_names !~ /^$/ and $ds_values !~ /^$/ ) {
#			$timestamp2 = $timestamp - $timestamp % $this->{step};
#			RRDs::update( "$$this{rrd_file}", "--template", $ds_names, "$timestamp2:$ds_values" );
#			$rrderror = RRDs::error;
#
#			Main::log_msg("N2Cacti::RRD::update_rrd(): update $$this{rrd_file} $ds_names with $ds_values at $timestamp2", "LOG_DEBUG");
#			if ( $rrderror ) {
#				Main::log_msg("N2Cacti::RRD::update_rrd(): update $$this{rrd_file} $ds_names with $ds_values at $timestamp2 : $rrderror", "LOG_ERR");
#				$ret_code = 0;
#			}
#		}

		#-- update singles rrd database
		while ( my ($key,$value) = each %$perf_single ) {
			$timestamp2 = $timestamp - $timestamp % $this->{step};
			$this->create_single_rrd($key, $timestamp2);

			my $rrd_file = $this->{datasource}->{$key}->{rrd_file};

			if ( -f $rrd_file ) {

				if ( $$config{RRD_CACHED} ) {
					Main::log_msg("N2Cacti::RRD::update_rrd(): RRDs::update $rrd_file, --daemon, $$config{RRD_CACHED_URI}, --template, $key, $timestamp2:$value", "LOG_DEBUG");
					RRDs::update( $rrd_file, "--daemon", "$$config{RRD_CACHED_URI}", "--template", $key, "$timestamp2:$value" );
				} else {
					Main::log_msg("N2Cacti::RRD::update_rrd(): RRDs::update $rrd_file, --template, $key, $timestamp2:$value", "LOG_DEBUG");
					RRDs::update( $rrd_file, "--template", $key, "$timestamp2:$value" );
				}

				$rrderror = RRDs::error;

				Main::log_msg("N2Cacti::RRD::update_rrd(): update $rrd_file : $key with $value at $timestamp", "LOG_DEBUG");
				if ( $rrderror ) {
					Main::log_msg("N2Cacti::RRD::update_rrd(): Problem to update $$this{hostname};$$this{service_description};$$this{template} rrd: $rrderror", "LOG_ERR");
					$ret_code = 0;
				}
			}
		}

		#--------------------------------------
		#-- Support for mysql storage database
		if ( $this->with_mysql() ) {
			Main::log_msg ("N2Cacti::RRD::update_rrd(): store to mysql ", "LOG_DEBUG");
			my $database = new N2Cacti::database({
				database_type       => "mysql",
				database_schema     => $$config{PERFDB_NAME},
				database_hostname   => $$config{PERFDB_HOST},
				database_username   => $$config{PERFDB_USER},
				database_password   => $$config{PERFDB_PASSWORD},
				database_port       => "3306"
			});

			if ( $$this{table_created} == 0 ) {
				my @temp = split(':', $ds_names);
				my $fields = {	
					id 			=> 'bigint NOT NULL auto_increment primary key ',
					date_check 		=> "timestamp NOT NULL default CURRENT_TIMESTAMP on update CURRENT_TIMESTAMP",
					host_id 		=> 'int(11) NOT NULL',
					service_id 		=> 'int(11) NOT NULL',
					'time'			=> 'TIME',
					wday			=> 'SMALLINT',
					mday			=> 'SMALLINT',
					yday			=> 'SMALLINT',
					week			=> 'SMALLINT',
					month			=> 'SMALLINT',
					year			=> 'SMALLINT',
				};

				foreach my $field (@temp){
					$fields->{$field} = 'double',
				}

				$database->table_create("$$this{template}", $fields);
				$$this{table_created} = 1;
			}

			my $keys = $ds_names;
			$keys =~ s/:/`, `/g;
			my $values = $ds_values;
			$values =~ s/:/', '/g;
			$values ="'$values'";
			my $query = "INSERT INTO $$this{template}(date_check, host_id, service_id, time,wday,mday,yday,week,month,year, `$keys`)
				VALUES(FROM_UNIXTIME('$timestamp'),'$$this{host_id}','$$this{service_id}', 
				TIME(FROM_UNIXTIME('$timestamp')),
				DAYOFWEEK(FROM_UNIXTIME('$timestamp')), 
				DAYOFMONTH(FROM_UNIXTIME('$timestamp')),
				DAYOFYEAR(FROM_UNIXTIME('$timestamp')),
				WEEK(FROM_UNIXTIME('$timestamp'),5),
				MONTH(FROM_UNIXTIME('$timestamp')),
				YEAR(FROM_UNIXTIME('$timestamp')),
				$values)";
			$database->execute($query);
			Main::log_msg("N2Cacti::RRD::update_rrd(): store with : $query", "LOG_DEBUG");
		}

#	}

	Main::log_msg("<-- N2Cacti::RRD::update_rrd()", "LOG_DEBUG");
	return $ret_code;
}

#
# with_mysql
#
# Gets/sets the mysql boolean
#
# @args		: the boolean
# @return	: the boolean
#
sub with_mysql {
	my ($this, $with_mysql)	= (@_);
	$this->{with_mysql}	= $with_mysql if defined($with_mysql);

	return 0 if $this->{disable_mysql};
	return $this->{with_mysql};
}

#
# rewrite_namefile
#
# Cleans the namefile
#
# @args		: the current name
# @return	: the new name
#
sub rewrite_namefile {
	my $this	= shift;
	my $name	= shift;

	$name		=~ s/<HOSTNAME>/$$this{hostname}/g;
	$name		=~ s/<SERVICENAME>/$$this{service_name}/g;
	$name		=~ s/<TEMPLATENAME>/$$this{service_name}/g;

	return $name;
}

#
# rewrite_olderfile
#
# Cleans the older file name
#
# @args		: the name
# @return	: the new name
#
sub rewrite_olderfile {
	my $this	= shift;
	my $name	= shift;

	$name		=~ s/<HOSTNAME>/$$this{hostname}/g;
	$name		=~ s/<SERVICENAME>/$$this{template}/g;
	$name		=~ s/<TEMPLATENAME>/$$this{template}/g;

	return $name;	
}


#
# initialize
#
# Define the template N2RRD for the service
# Check if a service rewrite rules exist
# Rewrite filename <HOSTNAME> and <SERVICENAME> 
# Lookup the template file
# Determine parameter from rrd file
# Create rrd database for execution and latency
# Look-up for individual rrd database specific to a host
#
# @args		: none
# @return	: OK (1) || KO (0)
#
sub initialize {
	my $this	= shift;

	my $config	= $this->{config};     # config variable from config.pm module
	my $service	= $this->{service_description};    # servicedescription from nagios
	my $ds_rewrite	= {};
	my $t_params	= [];
	my $rrderror;
	my $mkdir_error;

	Main::log_msg("--> N2Cacti::RRD::initialize()", "LOG_DEBUG");

	# -- Define the template N2RRD for the service
	my @parse_service_str = split ($config->{TEMPLATE_SEPARATOR_FIELD}, $service);

	$$this{template} = "";

	if ( $#parse_service_str <= 0 ) {
		Main::log_msg("N2Cacti::RRD::initialize(): Define the template N2RRD for the service with maps", "LOG_DEBUG");

		$this->{service_maps} = $this->get_maps();
		if ( defined $this->{service_maps}->{$this->{service_description}} ) {
			$this->{template} = $this->{service_maps}->{$this->{service_description}};
		}

		$$this{service_name} 	= $$this{service_description};
	} else {
		Main::log_msg("N2Cacti::RRD::initialize(): Define the template N2RRD for the service with parse method", "LOG_DEBUG");

		#-- Define template name and service_name
		$$this{template}	= $parse_service_str[$#parse_service_str];
		$$this{service_name}	= $parse_service_str[0];

		Main::log_msg("N2Cacti::RRD::initialize(): template=$$this{template}", "LOG_DEBUG");
		Main::log_msg("N2Cacti::RRD::initialize(): service_name=$$this{service_name}", "LOG_DEBUG");
	}

	# --  Check if a service rewrite rules exist
	Main::log_msg("N2Cacti::RRD::initialize(): check if a service rewrite rules exists", "LOG_DEBUG");
	if ( -f "$$config{CONF_DIR}/$$config{TEMPLATES_DIR}/rewrite/service/$$this{template}_rewrite" ) {
		open REWRITE, '<', "$$config{CONF_DIR}/$$config{TEMPLATES_DIR}/rewrite/service/$$this{template}_rewrite"
		or Main::log_msg ("N2Cacti::RRD::initialize(): Can't open rewrite rules file for $$this{hostname}", "LOG_CRIT")
		and exit 1;

		while (<REWRITE>) {
			next if /^#/;    # Skip comments
			next if /^$/;    # Skip empty lines
			s/#.*//;         # Remove partial comments
			chomp;

			$$ds_rewrite{$1}	= $2	if /^ds_name\s+(\S+)\s+(\S+)/;
			$$this{rrd_file}	= $1 	if /^rrd_file\s+(\S+)/;
			$$this{perf_rrd_file}	= $1 	if /^perf_rrd_file\s+(\S+)/;
		}
		close REWRITE;
	}

	$$this{ds_rewrite} = $ds_rewrite;

	# -- rewrite filename <HOSTNAME> and <SERVICENAME> 
	Main::log_msg("N2Cacti::RRD::initialize(): rewrite filename", "LOG_DEBUG");

	$$this{rrd_file_older}	= $this->rewrite_olderfile($$this{rrd_file});
	$$this{rrd_file}	= $this->rewrite_namefile($$this{rrd_file});
	$$this{perf_rrd_file}	= $this->rewrite_namefile($$this{perf_rrd_file});

	Main::log_msg("N2Cacti::RRD::initialize(): rrd_file_older : $$this{rrd_file_older}", "LOG_DEBUG");
	Main::log_msg("N2Cacti::RRD::initialize(): rrd_file : $$this{rrd_file}", "LOG_DEBUG");

	#-- lookup the template file
	my $rra_path = "$$config{CONF_DIR}/$$config{TEMPLATES_DIR}/rra";

	if ( $$this{template} =~ /./ ) {

		$this->{rra_file}	= "$rra_path/$$this{hostname}_$$this{template}.t";
		$this->{rra_file}	= "$rra_path/$$this{template}.t" if ( ! -f $this->{rra_file});

		$this->{rra_file_el}	= "$rra_path/$$this{hostname}_$$this{template}_el.t";
		$this->{rra_file_el}	= "$rra_path/$$this{template}_el.t" if ( ! -f $this->{rra_file_el});
		$this->{rra_file_el}	= "$rra_path/PERF_EL.t" if ( ! -f $this->{rra_file_el});
	}

	if ( ! -f $this->{rra_file} ) {
		Main::log_msg("N2Cacti::RRD::initialize(): MISSING_RRA : using default rra template for $$this{service_description} on $$this{hostname}", "LOG_INFO");

		$this->{rra_file} = "$rra_path/$config->{DEFAULT_RRA}";

		if ( not -f $this->{rra_file} ) {
			Main::log_msg("N2Cacti::RRD::initialize(): MISSING_RRA : cannot find the default rra template file $this->{rra_file}", "LOG_CRIT");
			return 0;
		}
	}

	#-- determine parameter from rrd file
 	my $hash = RRDs::info $this->{rrd_file} if ( -f  $this->{rrd_file} );

	if ( -f  $this->{rrd_file} && !RRDs::error ) { # get parameter from rrd file
		Main::log_msg("N2Cacti::RRD::initialize(): Determine parameter from rrd_file", "LOG_DEBUG");
		my $data = {ds => {}, rra => {}};
		foreach my $id (keys %$hash){
			next if ($id !~ m/^DS/i); # we dont use rra parameter only ds
			my $key = $id;

			$key =~ s/\.//g;
			$key =~ s/\[/;/g;
			$key =~ s/\]/;/g;

			my @f = split(';', $key);

			if ( scalar(@f) == 3 ) {
				if ( ! defined($data->{$f[0]}->{$f[1]}) ) {
					$data->{$f[0]}->{$f[1]} = {} ;
					$data->{$f[0]}->{$f[1]}->{ds_name} = $f[1] if ($f[0] eq "ds");
				}
				$data->{$f[0]}->{$f[1]}->{$f[2]}=$$hash{$id};
			}
		}

		my $item = $data->{ds};

		foreach my $ds (keys %$item){
			my $ds_name = $item->{$ds}->{ds_name};
			Main::log_msg("N2Cacti::RRD::initialize(): ds_name=$ds_name", "LOG_DEBUG");
			$this->{datasource}->{$ds_name} = {
				ds_name		=> $item->{$ds}->{ds_name},
				ds_type		=> $item->{$ds}->{type},
				heartbeat	=> $item->{$ds}->{minimal_heartbeat},
				min		=> $item->{$ds}->{min},
				max		=> $item->{$ds}->{max},
				rrd_file	=> $$this{rrd_file},
			};
		}
		$$this{valid} = 1;
	} elsif ( -f $this->{rra_file} ) { #get parameter from template
		Main::log_msg("N2Cacti::RRD::initialize(): Determine parameter from $$this{rra_file}", "LOG_DEBUG");
		Main::log_msg("N2Cacti::RRD::initialize(): open template rra : $$this{rra_file} for service : $$this{service_description}", "LOG_DEBUG");

		#
		#   print "Rewrite file detected for: $opt->{H}_${service}\n";
		open RRA, '<', $this->{rra_file}
		or Main::log_msg("N2Cacti::RRD::initialize(): Can't open rewrite rules file for $$this{hostname}", "LOG_CRIT")
		and exit 1;

		while (<RRA>) {
			next if /^#/;    # Skip comments
			next if /^$/;    # Skip empty lines
			s/#.*//;         # Remove partial comments
			chomp;
			push @$t_params, $_;

			if ( $_ =~ m/-s (\d+)/i ) {
				$this->{step} = $1;
				Main::log_msg("N2Cacti::RRD::initialize(): step $$this{step} for rra_file: $$this{rra_file}", "LOG_DEBUG");
			}

			next if !m/^DS/i;  # Skip no DS definition line
			foreach my $k ( keys %$ds_rewrite ) {
				s/:$k:/:$$ds_rewrite{$k}:/;
			}

			# In case of template, we skip the datasource
			my @champs = split(':', $_); #DS:cpuidle:GAUGE:600:0:U
			if ( $champs[1] !~ /<datasource>/ ) {
				$this->{datasource}->{$champs[1]} =  {
					ds_name		=> $champs[1],
					ds_type		=> $champs[2],
					heartbeat	=> $champs[3],
					min		=> $champs[4],
					max		=> $champs[5],
					rrd_file	=> "$$config{RRA_DIR}/$$this{hostname}/$$this{service_name}/$champs[1].rrd",
				};
			}
			@champs=undef;
		}
		close RRA;

		if ( not mkdir "$$config{RRA_DIR}/$$this{hostname}" ) {
			$$this{valid} = 1;
		} else {
			$$this{valid} = 0;
		}
	}

	# -- create rrd database for execution and latency
	my $ds_name_el = "";
	if(-f $$this{rra_file_el}){
		my @el_params = ();
		open EL, '<', "$$this{rra_file_el}"
		or Main::log_msg ("N2Cacti::RRD::initialize(): can't open file \"$$this{rra_file_el} - check access rights", "LOG_ERR")
		and exit 1;

		while (<EL>) {
			next if /^#/;    # Skip comments
			next if /^$/;    # Skip empty lines
			s/#.*//;         # Remove partial comments
			chomp;
			push @el_params, "$_";

			next if !m/^DS/i;  # Skip no DS definition line
			my @champs      = split(':', $_);
			$ds_name_el		.= "$champs[1]:";
			@champs			= undef;
		}
		close EL;

		$ds_name_el =~ s/:$//g;
		$$this{ds_name_el}=$ds_name_el;

		if (! -f $$this{perf_rrd_file}) {
			Main::log_msg ("N2Cacti::RRD::initialize(): Creating RRD execution and latency performance file: $$this{perf_rrd_file}", "LOG_DEBUG");
			RRDs::create( $$this{perf_rrd_file}, @el_params );
			
			$rrderror = RRDs::error;
			Main::log_msg ("N2Cacti::RRD::initialize(): Problem while creating execution and latency rrd: $rrderror", "LOG_ERR") if ($rrderror);
		}
	}
	
	#-- Look-up for individual rrd database specific to a host
	$this->lookup_individual_rrd();
	Main::log_msg("<-- N2Cacti::RRD::initialize()", "LOG_DEBUG");
	return 1;
}



#
# create_single_rrd
#
# Create a rrd file for single datasource with name hostname_service_name_datasource.rrd
#
# @args		: the datasource and the start_timestamp (RRD -s option)
# @return	: none
#
sub create_single_rrd {
	my $this = shift;
	my $datasource = shift;
	my $start_timestamp = shift;

	my $config = $this->{config};
	# we use .T instead of .t for collision risk
	my $rra_default = "$$config{CONF_DIR}/$$config{TEMPLATES_DIR}/rra/$$config{DEFAULT_RRA}";

	`mkdir -p $$config{RRA_DIR}/$$this{hostname}/$$this{service_name}`;

	my $rrd_file = "$$config{RRA_DIR}/$$this{hostname}/$$this{service_name}/$datasource.rrd";

	Main::log_msg("--> N2Cacti::RRD::create_single_rrd", "LOG_DEBUG");
	if ( ! -f $rrd_file ) {
		if ( -f $rra_default ) {
			my @t_params = ();
			open RRA, '<', "$rra_default" 
			or Main::log_msg ("N2Cacti::RRD::create_single_rrd(): can't open file \"$$this{rra_default} - check access right", "LOG_CRIT")
			and exit 1;

			while (<RRA>){
				next if /^#/;    # Skip comments
				next if /^$/;    # Skip empty lines
				s/#.*//;         # Remove partial comments
				s/<datasource>/$datasource/;
				chomp;
				push @t_params, "$_";
				next if !m/^DS/i;  # Skip no DS definition line

				my @champs      = split(':', $_); #example : DS:cpuidle:GAUGE:600:0:U

				$this->{datasource}->{$champs[1]} =  {
					ds_name		=> $champs[1],
					ds_type		=> $champs[2],
					heartbeat	=> $champs[3],
					min		=> $champs[4],
					max		=> $champs[5],
					rrd_file	=> $rrd_file,
				};
				@champs=undef;
			}
			push @t_params, sprintf("-b %u", $start_timestamp - 30); 

			Main::log_msg("N2Cacti::RRD::create_single_rrd(): Creating RRD individual : $rrd_file", "LOG_DEBUG");
			RRDs::create($rrd_file, @t_params);

			my $rrderror = RRDs::error;
			Main::log_msg ("N2Cacti::RRD::create_single_rrd(): Problem while individual rrd: \"$rrd_file\" with error \"$rrderror\" with params : @t_params", "LOG_CRIT") if ($rrderror);
		} else {
			Main::log_msg("N2Cacti::RRD::create_single_rrd(): MISSING_DEFAULTRRA : $rra_default is missing - create it!", "LOG_DEBUG");
			exit 1;
		}
	}
	Main::log_msg("<-- N2Cacti::RRD::create_single_rrd()", "LOG_DEBUG");
}



#
# lookup_individual_rrd
#
# Search the individual datasource in folder
#
# @args		: the RRD path
# @return	: none
#
sub lookup_individual_rrd {
	my $this = shift;
	my $path = $this->{config}->{RRA_DIR}."/$$this{hostname}/$$this{service_name}";

	Main::log_msg("--> N2Cacti::RRD::lookup_individual_rrd", "LOG_DEBUG");

	foreach ( getFiles("$path") ) {
		my $rrd_file = $_;

		#-- determine parameter from rrd file
		my $hash = RRDs::info $rrd_file if (-f  $rrd_file );

		if (-f  $rrd_file && !RRDs::error){
			my $data = {ds => {}, rra => {}, };

			$this->{step} = $hash->{step};

			foreach my $id (keys %$hash){
				#next if ($id !~m/^DS/i and $id !~ /^rra/);
				next if ($id !~ m/^DS/i);
				my $key = $id;
				$key =~ s/\.//g;
				$key =~ s/\[/;/g;
				$key =~ s/]/;/g;
	
				my @f = split(';', $key);
				if ( scalar(@f) == 3 ) {
					if(!defined($data->{$f[0]}->{$f[1]})){
						$data->{$f[0]}->{$f[1]}             = {} ;
						$data->{$f[0]}->{$f[1]}->{ds_name}  = $f[1] if ($f[0] eq "ds");
					}
					$data->{$f[0]}->{$f[1]}->{$f[2]} = $$hash{$id};
					$data->{$f[0]}->{$f[1]}->{rrd_file} = $rrd_file;
				}
			}

			my $item = $data->{ds};
			foreach my $ds (keys %$item){
				$this->{datasource}->{$ds} =   {
					ds_name		=> $item->{$ds}->{ds_name},
					ds_type		=> $item->{$ds}->{type},
					heartbeat	=> $item->{$ds}->{minimal_heartbeat},
					min		=> $item->{$ds}->{min},
					max		=> $item->{$ds}->{max},
					rrd_file	=> $item->{$ds}->{rrd_file},
				};
			}
		}
	}

	Main::log_msg("<-- N2Cacti::RRD::lookup_individual_rrd");
}

#
# get_maps
#
# Parses the service_maps file and gives a hash ref
#
# @in	: this
# @out	: a map hash ref
#
sub get_maps {
	my $this = shift;
	my $config = $this->{config};     # config variable from config.pm module

	my %s_maps;

	open S_MAPS, '<', $config->{CONF_DIR}."/".$config->{SERVICE_NAME_MAPS}
	or Main::log_msg("N2Cacti::RRD::get_maps(): MISSING_FILE: Can't open service maps file \"$$config{CONF_DIR}/$$config{SERVICE_NAME_MAPS}\"\n", "LOG_ERR");

	while (<S_MAPS>) {
		next if /^#/;    # Skip comments
		next if /^$/;    # Skip empty lines
		s/#.*//;         # Remove partial comments
		chomp;

		if ( /(\S+):\s+(\S+)/i ) {
			$s_maps{$1} = $2;
		}
	}
	close S_MAPS;

	return \%s_maps;
}

#
# getFiles
#
# Utility function to browse files and directories
#
# @args		: the path to scan
# @return	: the sub files tab
#
sub getFiles {
	my $path	= shift;

	my @subFiles;

	foreach (getFolders($path)) {
		push @subFiles, "$path/$_" if(!(($_ =~ /^\./) || opendir(DIR,$_)));
		closedir(DIR);
	}

	return @subFiles;
}

#
# getFolders
#
# Utility function to browse directories
#
# @args		: the path
# @return	: the directories tab
#
sub getFolders {
	my $path	= shift;

	my @subFolder;

	if ( ! ($_ =~ /^\./) && opendir(DIR, $path)) {
		foreach (readdir(DIR)) {
			push @subFolder, $_ if(!($_ =~ /^\./) || opendir(DIR1,"$path/$_"));
			closedir(DIR1);
		}
	}

	closedir(DIR);
	return @subFolder;
}

1;

