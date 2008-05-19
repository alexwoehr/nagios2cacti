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
use RRDs;
use N2Cacti::Config qw(load_config log_msg get_config);
use N2Cacti::Archive;
use N2Cacti::Oreon;
use N2Cacti::database;
use Error  qw(:try);
BEGIN {
        use Exporter   	();
        use vars       	qw($VERSION @ISA @EXPORT @EXPORT_OK);
        @ISA 		=	qw(Exporter);
        @EXPORT 	= 	qw();
}

our $ngs_perf_table_create=0;

sub new {
	my $class   = shift;
    my $attr = shift;
    my %param = %$attr if $attr;
	die "service_description and hostname required to get parameter of rrd file" if(!defined  ($param{service_description}) );
    my $this    = {
		service_description => $param{service_description},
		hostname 			=> $param{hostname} 	|| undef,
		config 				=> get_config(),
		debug 				=> $param{debug} 		|| 0,
		log_msg 			=> $param{cb_log_msg}   || \&default_log_msg,
		start_time			=> $param{start_time} 	|| time,
		template			=> "", 	# template name
		service_name		=> "",	# service name (without @template_name else service_description in maps case)
		rra_file			=> "", 	# template file .t
		rrd_file 			=> "", 	# path to main rrd file (contains datasource in template.t file)
		rrd_file_older		=> "",	# older path to rrd file, need to migrate file
		perf_rrd_file		=> "",
		datasource			=> {}, 	# hash of hash datasource -- add path to rrd file for each datasource
		ds_rewrite			=> {}, 	# detail of  datasource rewrite
		valid				=> 1,	# flag if item can be store in RRD

		# -- specific member variable for storage in mysql database
		host_id				=> 0,	# Oreon : host-id 		
		service_id			=> 0,	# Oreon : service-id 	
		table_created		=> 0,	 
		with_mysql			=> $param{with_mysql} || 0, 
		disable_mysql		=> 0,
  	};

    bless($this,$class);
    
	$$this{valid}=0 if(!$this->initialize());
    return $this;

}

sub validate{
	my $this = shift;
	$this->log_msg(__LINE__."\titem valid : $$this{valid}") if $$this{debug};
	return $$this{valid};
}

sub default_log_msg{
    my $message=shift;
    $message=~ s/\n$//g;
    print "perf2rrd::RRD:$message\n";
}

sub log_msg {
    my $this=shift;
    my $message=shift;
	$message=~ s/\n$//g;
    &{$this->{log_msg}}("$message\n");
}


sub hostname{
	my $this = shift;
	my $hostname = shift;
	$this->{hostname}=$hostname if (defined ($hostname ));
	return $this->{hostname};
}

sub service_description {
	my $this = shift;
	my $service_description = shift ||undef;
	$this->{service_description}=$service_description if (defined ($service_description ));
	return $this->{service_description};
}

sub getTemplate {
	my $this = shift;
	return $$this{template};	
}

sub getPathRRD {
	my $this 		= shift;
	my $datasource 	= shift;
	if(defined($datasource)){
		return $this->{datasource}->{$datasource}->{rrd_file};
	}
	else{
		return $this->{rrd_file};
	}
}

sub setPathRRD {
	my $this = shift;
	my $path=shift;
	my $datasource = shift;
	
	if (defined($datasource)){
		$this->{datasource}->{$datasource}->{rrd_file} = $path;
	}
	else {
		$this->{rrd_file} = $path;
	}
}


sub getDataSource {
	my $this = shift;
	return $$this{datasource};
}

sub getServiceName {
	my $this = shift;
	return $$this{service_name};
}

sub update_rrd_el {
	my $this 		= shift;
	my $execution	= shift;
	my $latency		= shift;
	my $state		= shift;	
	my $timestamp	= shift || time;
    my $config 			= $this->{config};     # variable de config issue de config.pm
	return undef if (!$this->validate());
	$this->log_msg("--> N2Cacti::RRD::update_rrd_el()") if $$this{debug};
	if ( -f $$this{perf_rrd_file} ){
		my $ds_value = "$execution:$latency";
		RRDs::update( "$$this{perf_rrd_file}", "--template", "$$this{ds_name_el}", "$timestamp:$ds_value" );
	  	my $rrderror = RRDs::error;
		$this->log_msg ("update $$this{perf_rrd_file} $$this{ds_name_el} with $ds_value") if ($$this{debug}||$rrderror);
        $this->log_msg ("Problem to update $$this{hostname};$$this{service_description};$$this{template} rrd: $rrderror") if ($rrderror);
	}
    #--------------------------------------
    #-- Support for mysql storage database
    if($this->with_mysql()){
        $this->log_msg ("store to mysql ") if ($$this{debug});
		my $database = new N2Cacti::database({
                database_type       => "mysql",
                database_schema     => $$config{PERFDB_NAME},
                database_hostname   => $$config{PERFDB_HOST},
                database_username   => $$config{PERFDB_USER},
                database_password   => $$config{PERFDB_PASSWORD},
                database_port       => "3306",
                log_msg             => \&log_msg});
		my $ngs_result={
			state 			=> $state,
			execution_time	=> $execution,
			latency			=> $latency,
			host_id			=> $$this{host_id},
			service_id		=> $$this{service_id},
			date_check 		=> $timestamp,		
			};
	    if($ngs_perf_table_create==0){
            my $fields = {
                    id          	=> 'bigint NOT NULL auto_increment primary key ',
                    date_check      => "timestamp NOT NULL default CURRENT_TIMESTAMP on update CURRENT_TIMESTAMP",
                    host_id         => 'int(11) NOT NULL',
                    service_id      => 'int(11) NOT NULL',
					state			=> 'varchar(10) NOT NULL',
					execution_time	=> 'REAL NOT NULL',
					latency			=> 'REAL NOT NULL',
                };

            $database->table_create("NGS_RESULT", $fields);
            $ngs_perf_table_create=1;
		}

        my $query = "REPLACE NGS_RESULT(date_check, host_id, service_id, state, execution_time, latency) 
				VALUES(FROM_UNIXTIME('$timestamp'),'$$this{host_id}','$$this{service_id}', '$state', '$execution', '$latency');";
        $database->execute($query);
	}
	$this->log_msg("<-- N2Cacti::RRD::update_rrd_el()") if $$this{debug};

}

#-- parse the perfdata and explode the datasource in datasource_min datasource_max... if available
sub parse_perfdata{
    my $perfdata    = shift;
    my $result      = [];
    my @suffix      = ('', 'warn','crit','min','max');
    my @uom         = ('s','us','ms','\%','B','KB','MB','TB','c');

    #-- suppression des espaces avant et apres =
    $perfdata       =~ s/\s+=/=/g;
    $perfdata       =~ s/=\s+/=/g;
    #-- ajout des quotes si necessaire
    if($perfdata!~m/\'/){
        my @temp=split('=',$perfdata);
        $perfdata="'".shift(@temp)."'=";
        foreach(@temp){
            $_ =~ s/ / '/;
            $perfdata.="$_'=";
        }
        $perfdata=~ s/'=$//;
    }

    #-- ajout d'un separateur de champs
    $perfdata       =~ s/ '/\|'/g;
    chomp($perfdata);
    my @datasource  = split /\|/ , $perfdata;

    foreach (@datasource){
        my @t1=split(/=/,$_);
        my @values=split(/;/,$t1[1]);
        my $ds_name=$t1[0];
        $ds_name =~ s/'//g;
		$ds_name =~ s/ /_/g;
        
        my $value =( $values[0] =~  /([0-9\.]+)/)[0];
        push(@$result,"$ds_name=$value");
        for( my $i=1;$i<5;$i++){
            if (defined($values[$i]) && $values[$i] ne '') {
                $value =( $values[$i] =~  /([0-9\.]+)/)[0];
                push(@$result,"$ds_name\_$suffix[$i]=$value");
            }
        }
    }
    return @$result;
}


sub update_rrd {
	my $this 			= shift;
	my $output 			= shift; 
	my $timestamp 		= shift || time;
	my $store_to_mysql 	= shift ||0;
	my @data			= ();
    my $config 			= $this->{config};     # variable de config issue de config.pm
	return undef if (!$this->validate());

	$this->log_msg("--> N2Cacti::RRD::update_rrd()") if $$this{debug};
	if (! -f $$this{rrd_file}){
		$$this{debug}=1;
		$this->initialize();
		die "error the base rrd dont exist !\n\t $$this{hostname};$$this{service_description};$$this{template}" if (! -f $$this{rrd_file});
	}
	
	if( -f $$this{rrd_file}){
		#-- Loading plugin.pm 	
		if ( -f "$$config{CONF_DIR}/$$config{TEMPLATES_DIR}/plugin.pm" ) {
		    open P, '<', "$$config{CONF_DIR}/$$config{TEMPLATES_DIR}/plugin.pm"
        		or die "Can't open perl code file \"$$config{CONF_DIR}/$$config{TEMPLATES_DIR}/plugin.pm\"";

    		my @PERLCODE = <P>;
		    close P;
    		my $result_str = eval join("\n",@PERLCODE);warn $@ if $@;
		}

		#-- possibility for external performance data parsing
		if ( -f "$$config{CONF_DIR}/$$config{TEMPLATES_DIR}/code/$$this{template}.pl" ) {
   	 		open P, '<', "$$config{CONF_DIR}/$$config{TEMPLATES_DIR}/code/$$this{template}.pl"
        		or die "Can't open perl code file \"$$config{CONF_DIR}/$$config{TEMPLATES_DIR}/code/$$this{template}.pl\"";

    		my @PCODE = <P>;
    		close P;

    		my $ret_str = eval join("\n",@PCODE);warn $@ if $@;

    		$ret_str =~ s/\s+=/=/g;
    		$ret_str =~ s/=\s+/=/g;

    		@data = split /\s/, $ret_str;
		}
		else {
    		# remove spaces before and/or after "=" character
		    #$output =~ s/\s+=/=/g;
		    #$output =~ s/=\s+/=/g;
		    #@data = ( $output =~ /(\S+=[0-9\.]+)/g );
			
			@data = parse_perfdata($output);
		}

		my $ds_rewrite = $$this{ds_rewrite};

		my $perf_main={};
		my $perf_single={};
		foreach my $kv (@data) {
			my $ds_name;
		    my ( $key, $val ) = split /=/, $kv;
			
			$this->log_msg("rewrite = $key : $val : $$ds_rewrite{$key}") if $$this{debug};
			if ( defined ($$ds_rewrite{$key}) ){
				$this->log_msg("rewrite $key to $$ds_rewrite{$key}") if ($$this{debug});
				$ds_name	.= "$$ds_rewrite{$key}";
			}
			else{
		    	$ds_name 	.= "$key";
			}
			
			if(defined ($this->{datasource}->{$ds_name}) 
			&& $this->{datasource}->{$ds_name}->{rrd_file} eq $$this{rrd_file}){
				$perf_main->{$ds_name}=$val;
			}
			else{
				$perf_single->{$ds_name}=$val;
			}

		}

		#-- update main rrd database
		my $ds_names  = join(':',keys(%$perf_main));
		my $ds_value = join(':',values(%$perf_main));


		RRDs::update( "$$this{rrd_file}", "--template", $ds_names, "$timestamp:$ds_value"  );
	  	my $rrderror = RRDs::error;
	  	
		$this->log_msg ("update $$this{rrd_file} $ds_names with $ds_value at $timestamp") if ($$this{debug}||$rrderror);
        $this->log_msg ("Problem to update $$this{hostname};$$this{service_description};$$this{template} rrd: $rrderror") if ($rrderror);


		#-- update singles rrd database
		while (my ($key,$value) = each %$perf_single){
			$this->create_single_rrd($key);
			my $rrd_file = $$this->{datasource}->{$key}->{rrd_file};
			if(-f $$rrd_file){
				RRDs::update ( $rrd_file,  "--template", $key, "$timestamp:$value");
				$rrderror = RRDs::error;
		  	
				$this->log_msg ("update  $rrd_file : $key with $value at $timestamp") if ($$this{debug}||$rrderror);
		   		$this->log_msg ("Problem to update $$this{hostname};$$this{service_description};$$this{template} rrd: $rrderror") if ($rrderror);
		   	}
		}
		

		#--------------------------------------
		#-- Support for mysql storage database
		if($this->with_mysql()){
			$this->log_msg ("store to mysql ") if ($$this{debug});
			my $database = new N2Cacti::database({
		        database_type       => "mysql",
        		database_schema     => $$config{PERFDB_NAME},
		        database_hostname   => $$config{PERFDB_HOST},
        		database_username   => $$config{PERFDB_USER},
		        database_password   => $$config{PERFDB_PASSWORD},
    	    	database_port       => "3306",
	    	    log_msg             => \&log_msg});

			if($$this{table_created}==0){
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
				$$this{table_created}=1;
			}

			my $keys = $ds_names;
			$keys =~ s/:/`, `/g;
			my $values = $ds_value;
			$values =~ s/:/', '/g;
			$values ="'$values'";
			my $query = "replace $$this{template}(date_check, host_id, service_id, time,wday,mday,yday,week,month,year, `$keys`) VALUES(FROM_UNIXTIME('$timestamp'),'$$this{host_id}','$$this{service_id}', 
TIME(FROM_UNIXTIME('$timestamp')),
DAYOFWEEK(FROM_UNIXTIME('$timestamp')), 
DAYOFMONTH(FROM_UNIXTIME('$timestamp')),
DAYOFYEAR(FROM_UNIXTIME('$timestamp')),
WEEK(FROM_UNIXTIME('$timestamp'),5),
MONTH(FROM_UNIXTIME('$timestamp')),
YEAR(FROM_UNIXTIME('$timestamp')),
$values)";
			$database->execute($query);
			$this->log_msg ("store with : $query") if ($$this{debug});
		}
		
    }
  	$this->log_msg("<-- N2Cacti::RRD::update_rrd()") if $$this{debug};
}

sub with_mysql {
	my ($this, $with_mysql)=(@_);
	$this->{with_mysql} = $with_mysql if (defined($with_mysql));
	return 0 if ($this->{disable_mysql}==1);
	return  $this->{with_mysql};
}

sub rewrite_namefile {
	my $this = shift;
	my $name = shift;
	$name    =~ s/<HOSTNAME>/$$this{hostname}/g;
    $name    =~ s/<SERVICENAME>/$$this{service_name}/g;
    $name    =~ s/<TEMPLATENAME>/$$this{service_name}/g;
	return $name;
}

sub rewrite_olderfile {
	my $this = shift;
	my $name = shift;
	$name    =~ s/<HOSTNAME>/$$this{hostname}/g;
    $name    =~ s/<SERVICENAME>/$$this{template}/g;
    $name    =~ s/<TEMPLATENAME>/$$this{template}/g;
	return $name;	
}


#----------------------------------------------------------------------------------------------
sub initialize {
	my $this = shift;
    my $config = $this->{config};     # config variable from config.pm module
    my $service = $this->{service_description};    # servicedescription from nagios
  	my $ds_rewrite 	= {};
	my $t_params	= [];
	my $rrderror;
	
	$this->log_msg("--> N2Cacti::RRD::initialize") if $$this{debug};
	# -- Define parameter in Oreon (Service and Host ID)
	if($this->with_mysql()){
		my $oreon 				= new N2Cacti::Oreon({oreon_dir => $$config{OREON_DIR}});
		$oreon->database->set_raise_exception(1);
		try {
			my $item 				= $oreon->database->db_fetch_hash("host", {
				host_name 			=> "$$this{hostname}",
				host_register		=> '1'});
			$$this{host_id}			= $item->{host_id};
			$item 					= $oreon->database->db_fetch_hash("service", { 
				service_description => "$$this{service_description}",
				service_register	=> '1' });
			$$this{service_id}		= $item->{service_id};
		}
		catch Error::Simple with{
			$$this{disable_mysql}=1;
		};
	}


	# -- Define the template N2RRD for the service
	my @parse_service_str = split ($config->{TEMPLATE_SEPARATOR_FIELD}, $service);
	$$this{template} 	= "";
    if ( $#parse_service_str <= 0 ) {
	    
	    $this->log_msg(__LINE__ . "Define the template N2RRD for the service with maps") if $$this{debug};
        open S_MAPS, '<', $config->{CONF_DIR}."/".$config->{SERVICE_NAME_MAPS}
          or $this->log_msg(__LINE__."\tMISSING_FILE: Can't open service maps file \"$$config{CONF_DIR}/$$config{SERVICE_NAME_MAPS}\"\n")
          and exit 1;

        $this->log_msg(
          __LINE__."\t..Searching map in file \"$$config{CONF_DIR}/$$config{SERVICE_NAME_MAPS}\" for service \"$$this{service_description}\" \n")
          if $$this{debug};

        while (<S_MAPS>) {
            next if /^#/;    # Skip comments
            next if /^$/;    # Skip empty lines
            s/#.*//;         # Remove partial comments
            chomp;

            if ( /$$this{service_description}:\s+(\S+)/i ) {
              $$this{template} 	= $1 if /$$this{service_description}:\s+(\S+)/i;
              $this->log_msg(__LINE__."\t...Mapping service $$this{service_description} -> $$this{template}\n" ) if $$this{debug};
            }
        }
        close S_MAPS;
        $$this{service_name} 	= $$this{service_description};
    }
    else {
	    $this->log_msg(__LINE__ . "\tDefine the template N2RRD for the service with parse method") if $$this{debug};
    	#-- Define template name and service_name
        $$this{template} 		= $parse_service_str[$#parse_service_str];
        $$this{service_name}	= $parse_service_str[0];
        $this->log_msg( "\t template=$$this{template}")if $$this{debug};
        $this->log_msg( "\t service_name=$$this{service_name}")if $$this{debug};
    }
	
	if($$this{template} eq "" ){
		$$this{valid}=0;
		return 0;
	}



	# -- Define the path to rrd file
	if (defined ($this->{hostname})){
		$this->log_msg(__LINE__ . "\tDefine the path to rrd file") if $$this{debug};
		$$this{rrd_file}           	= $config->{RRA_DIR}."/<HOSTNAME>/<HOSTNAME>_<SERVICENAME>.rrd";
    	$$this{perf_rrd_file}		= $config->{RRA_DIR}."/<HOSTNAME>/<HOSTNAME>_<SERVICENAME>_el.rrd";
		
    	# --  Check if a service rewrite rules exist
    	$this->log_msg(__LINE__ . "\tcheck if a rewrite rules exist ") if $$this{debug};
	    if ( -f $config->{CONF_DIR}."/".$config->{TEMPLATES_DIR}."/rewrite/$$this{hostname}_$$this{template}_rewrite" ) {
        	open REWRITE, '<',  "$$config{CONF_DIR}/$$config{TEMPLATES_DIR}/rewrite/$$this{hostname}_$$this{template}_rewrite"
          		or $this->log_msg(__LINE__."\tCan't open rewrite rules file for $$this{hostname} - check the access right")
          		and exit 1;

        	while (<REWRITE>) {
    	        next if /^#/;    # Skip comments
	            next if /^$/;    # Skip empty lines
            	s/#.*//;         # Remove partial comments
            	chomp;
				$$ds_rewrite{$1} = $2		if /^ds_name\s+(\S+)\s+(\S+)/;
				$$ds_rewrite{$1."_min"} = $2."_min"		if /^ds_name\s+(\S+)\s+(\S+)/;
				$$ds_rewrite{$1."_max"} = $2."_max"		if /^ds_name\s+(\S+)\s+(\S+)/;
				$$ds_rewrite{$1."_warn"} = $2."_warn"		if /^ds_name\s+(\S+)\s+(\S+)/;
				$$ds_rewrite{$1."_crit"} = $2."_crit"		if /^ds_name\s+(\S+)\s+(\S+)/;
            	$$this{rrd_file}      = $1 	if /^rrd_file\s+(\S+)/;
           	 	$$this{perf_rrd_file} = $1 	if /^perf_rrd_file\s+(\S+)/;
        	}
        	close REWRITE;
    	}
	}


    # --  Check if a service rewrite rules exist
  	$this->log_msg(__LINE__ . "\tcheck if a service rewrite rules exist") if $$this{debug};
    if ( -f "$$config{CONF_DIR}/$$config{TEMPLATES_DIR}/rewrite/service/$$this{template}_rewrite" ) {
        open REWRITE, '<', "$$config{CONF_DIR}/$$config{TEMPLATES_DIR}/rewrite/service/$$this{template}_rewrite"
          or $this->log_msg (__LINE__."\tCan't open rewrite rules file for $$this{hostname}")
          and exit 1;

        while (<REWRITE>) {
            next if /^#/;    # Skip comments
            next if /^$/;    # Skip empty lines
            s/#.*//;         # Remove partial comments
            chomp;

			$$ds_rewrite{$1} = $2		if /^ds_name\s+(\S+)\s+(\S+)/;
			$$ds_rewrite{$1."_min"} = $2."_min"		if /^ds_name\s+(\S+)\s+(\S+)/;
			$$ds_rewrite{$1."_max"} = $2."_max"		if /^ds_name\s+(\S+)\s+(\S+)/;
			$$ds_rewrite{$1."_warn"} = $2."_warn"		if /^ds_name\s+(\S+)\s+(\S+)/;
			$$ds_rewrite{$1."_crit"} = $2."_crit"		if /^ds_name\s+(\S+)\s+(\S+)/;
            $$this{rrd_file}      = $1 	if /^rrd_file\s+(\S+)/;
            $$this{perf_rrd_file} = $1 	if /^perf_rrd_file\s+(\S+)/;
        }
        close REWRITE;
    }

	$$this{ds_rewrite}=$ds_rewrite;


	# -- rewrite filename <HOSTNAME> and <SERVICENAME> 
	$this->log_msg(__LINE__ . "\trewrite filename") if $$this{debug};

	$$this{rrd_file_older}		= $this->rewrite_olderfile("$$this{rrd_file}");
	$$this{rrd_file}			= $this->rewrite_namefile($$this{rrd_file});
	$$this{perf_rrd_file}		= $this->rewrite_namefile($$this{perf_rrd_file});
	$this->log_msg(__LINE__ . "\trrd_file_older :  $$this{rrd_file_older}") if $$this{debug};
	$this->log_msg(__LINE__ . "\trrd_file :  $$this{rrd_file}") if $$this{debug};

	#-- lookup the template file
	my	$rra_path				= "$$config{CONF_DIR}/$$config{TEMPLATES_DIR}/rra";
	
    $this->{rra_file}            	= "$rra_path/$$this{hostname}_$$this{template}.t";
	$this->{rra_file}				= "$rra_path/$$this{template}.t" if ( !-f $this->{rra_file});

    $this->{rra_file_el}           	= "$rra_path/$$this{hostname}_$$this{template}_el.t";
	$this->{rra_file_el}			= "$rra_path/$$this{template}_el.t" if ( !-f $this->{rra_file_el});
	$this->{rra_file_el}			= "$rra_path/PERF_EL.t" if ( !-f $this->{rra_file_el});
		
	if(! -f $this->{rra_file}){
		$this->log_msg(__LINE__."\t:MISSING_RRA : rra template file in $rra_path not found for $$this{service_description} on $$this{hostname}");
		$$this{valid}=0;
		return 0;
	}


	#-- determine parameter from rrd file
 	my 	$hash    				= RRDs::info $this->{rrd_file} if (-f  $this->{rrd_file} );
    if (-f  $this->{rrd_file} && !RRDs::error){ # get parameter from rrd file
    	$this->log_msg(__LINE__ . "\tDetermine parameter from rrd_file") if $$this{debug};
		my $data                = {ds => {}, rra => {}};
	    foreach my $id (keys %$hash){

#	        next if ($id !~m/^DS/i and $id !~ /^rra/);
   	        next if ($id !~ m/^DS/i); # we dont use rra parameter only ds
#  	        $this->log_msg(__LINE__."\t$id")if $$this{debug};
	        my $key = $id;
	        $key =~ s/\.//g;
	        $key =~ s/\[/;/g;
	        $key =~ s/]/;/g;
	        my @f = split(';', $key);

	        if(scalar(@f)==3){
	            if(!defined($data->{$f[0]}->{$f[1]})){
	                $data->{$f[0]}->{$f[1]}             = {} ;
	                $data->{$f[0]}->{$f[1]}->{ds_name}  = $f[1] if ($f[0] eq "ds");
	            }
	            $data->{$f[0]}->{$f[1]}->{$f[2]}=$$hash{$id};
	        }
	    }
	    
	    my $item = $data->{ds};
	    foreach my $ds (keys %$item){
	    	my $ds_name = $item->{$ds}->{ds_name};
		    $this->log_msg(__LINE__."\tds_name=$ds_name")if $$this{debug};
	    	$this->{datasource}->{$ds_name} = {
	            ds_name     => $item->{$ds}->{ds_name},
	            ds_type     => $item->{$ds}->{type},
	            heartbeat   => $item->{$ds}->{minimal_heartbeat},
	            min         => $item->{$ds}->{min},
	            max         => $item->{$ds}->{max},
	            rrd_file	=> $$this{rrd_file},
	            };
	    }
		$$this{valid}=1;
	}
	elsif ( -f $this->{rra_file} ) { #get parameter from template
		$this->log_msg(__LINE__ . "\tDetermine parameter from $$this{rra_file}") if $$this{debug};
	    #my $$this{ds}              	= [];

        $this->log_msg(__LINE__."\t:open template rra : $$this{rra_file} for service : $$this{service_description}") if $$this{debug};

        #
        #   print "Rewrite file detected for: $opt->{H}_${service}\n";
        open RRA, '<', $this->{rra_file}
          or $this->log_msg(__LINE__."\t:Can't open rewrite rules file for $$this{hostname}")
          and exit 1;


        while (<RRA>) {
            next if /^#/;    # Skip comments
            next if /^$/;    # Skip empty lines
            s/#.*//;         # Remove partial comments
            chomp;
			push @$t_params, $_;

            next if !m/^DS/i;  # Skip no DS definition line
	        foreach my $k ( keys %$ds_rewrite ) {
    	        s/:$k:/:$$ds_rewrite{$k}:/;
        	}

            my @champs      = split(':', $_); #DS:cpuidle:GAUGE:600:0:U
            $this->{datasource}->{$champs[1]} =  {
                ds_name     => $champs[1],
                ds_type     => $champs[2],
                heartbeat   => $champs[3],
                min         => $champs[4],
                max         => $champs[5],
                rrd_file	=> $$this{rrd_file},
                };
			@champs=undef;
        }
		close RRA;
		
        # -- create rrd database
		if(!-f $$this{rrd_file}){
			$this->log_msg(__LINE__ . "\tcreating rrd database") if $$this{debug};
			mkdir  "$$config{RRA_DIR}/$$this{hostname}";
			push @$t_params, "-b $$this{start_time}";
			RRDs::create ($$this{rrd_file}, @$t_params);
	 	    $rrderror = RRDs::error;
			$this->log_msg (__LINE__."\tProblem while creating rrd: $rrderror") if ($rrderror);
		}
		

		$$this{valid}=1;
    }
    


	
	# -- create rrd database for execution and latency
	my $ds_name_el = "";
	if(-f $$this{rra_file_el}){
		my @el_params = ();
		open EL, '<', "$$this{rra_file_el}"
        	or $this->log_msg (__LINE__."\tcan't open file \"$$this{rra_file_el} - check access right")
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
    	    $this->log_msg (__LINE__."\tCreating RRD execution and latency performance file: $$this{perf_rrd_file}") if $this->{debug};
        	RRDs::create( $$this{perf_rrd_file}, @el_params );
 	        $rrderror = RRDs::error;
        	$this->log_msg (__LINE__."\tProblem while creating execution and latency rrd: $rrderror") if ($rrderror);
		}
	}
	
	#-- Look-up for individual rrd database specific to a host
	$this->lookup_individual_rrd();
	$this->log_msg("<-- N2Cacti::RRD::initialize") if $$this{debug};
	return 1;
}



#-- create a rrd file for single datasource with name hostname_service_name_datasource.rrd
sub create_single_rrd{
	my $this = shift;
	my $datasource = shift;
	my $config = $this->{config};
	# we use .T instead of .t for collision risk
	my $rra_default = "$$config{CONF_DIR}/$$config{TEMPLATES_DIR}/rra/$$config{DEFAULT_RRA}";
	mkdir "$$config{RRA_DIR}/$$this{hostname}/$$this{hostname}_$$this{service_name}";
	my $rrd_file = "$$config{RRA_DIR}/$$this{hostname}/$$this{hostname}_$$this{service_name}/$datasource.rrd";
	$this->log_msg("-->N2Cacti::RRD::create_single_rrd") if $$this{debug};
	if(!-f $rrd_file){
		if(-f$rra_default){
			my @t_params = ();
			open RRA, '<', "$rra_default" 
				or $this->log_msg (__LINE__."\tcan't open file \"$$this{rra_default} - check access right")
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
		            ds_name     => $champs[1],
		            ds_type     => $champs[2],
		            heartbeat   => $champs[3],
		            min         => $champs[4],
		            max         => $champs[5],
		            rrd_file	=> $rrd_file,
		            };
				@champs=undef;
		    } 
		    $this->log_msg(__LINE__."\tCreating RRD individual : $rrd_file") if $this->{debug};
		    RRDs::create($rrd_file, @t_params);
		    my $rrderror = RRDs::error;
        	$this->log_msg (__LINE__."\tProblem while individual rrd: \"$rrd_file\" with error \"$rrderror\"") if ($rrderror);
        }
        else {
        	$this->log_msg(__LINE__."\tMISSING_DEFAULTRRA : $rra_default is missing - create it!");
        	exit 1;
        }
	}
	$this->log_msg("<-- N2Cacti::RRD::create_single_rrd") if $$this{debug};
}



#-- search the individual datasource in folder
sub lookup_individual_rrd{
	my $this = shift;
	my $path = $this->{config}->{RRA_DIR}."/$$this{hostname}/$$this{hostname}_$$this{service_name}";
	$this->log_msg("--> N2Cacti::RRD::lookup_individual_rrd") if $$this{debug};
	foreach(getFiles("$path")){
		my $rrd_file=$_;
		#-- determine parameter from rrd file
	 	my 	$hash    				= RRDs::info $rrd_file if (-f  $rrd_file );
		if (-f  $rrd_file && !RRDs::error){
			my $data                = {ds => {}, rra => {}};
			foreach my $id (keys %$hash){
	#	        next if ($id !~m/^DS/i and $id !~ /^rra/);
	   	        next if ($id !~ m/^DS/i);
			    my $key = $id;
			    $key =~ s/\.//g;
			    $key =~ s/\[/;/g;
			    $key =~ s/]/;/g;
	
			    my @f = split(';', $key);
			    if(scalar(@f)==3){
			        if(!defined($data->{$f[0]}->{$f[1]})){
			            $data->{$f[0]}->{$f[1]}             = {} ;
			            $data->{$f[0]}->{$f[1]}->{ds_name}  = $f[1] if ($f[0] eq "ds");
			        }
			        $data->{$f[0]}->{$f[1]}->{$f[2]}=$$hash{$id};
			    }
			}
			
			my $item = $data->{ds};
			foreach my $ds (keys %$item){
				$this->{datasource}->{$ds} =   {
				    ds_name     => $item->{$ds}->{ds_name},
				    ds_type     => $item->{$ds}->{type},
				    heartbeat   => $item->{$ds}->{minimal_heartbeat},
				    min         => $item->{$ds}->{min},
				    max         => $item->{$ds}->{max},
				    rrd_file	=> $$this{rrd_file},
				    };
			}
		}
	}
	$this->log_msg("<-- N2Cacti::RRD::lookup_individual_rrd") if $$this{debug};
}



#-- utility function to browse file and directory
sub getFiles {
    my @subFiles;
    my $path=shift;
    foreach(getFolders($path)){
        push @subFiles, "$path/$_" if(!(($_ =~ /^\./) || opendir(DIR,$_)));
        closedir(DIR);
    }
    return @subFiles;
}

sub getFolders {
    my $path = shift;
    my @subFolder;
    if( !($_ =~ /^\./) && opendir(DIR, $path)){
        foreach( readdir(DIR)) {
            push @subFolder, $_ if(!($_ =~ /^\./) || opendir(DIR1,"$path/$_"));
            closedir(DIR1);
        }
    }
    closedir(DIR);
    return @subFolder;
}





1;

