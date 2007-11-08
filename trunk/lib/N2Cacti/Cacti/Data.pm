###########################################################################
#                                                                         #
# N2Cacti::Cacti::Data                                                    #
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

package N2Cacti::Cacti::Data;

use strict;
use DBI();
use N2Cacti::Cacti;
use N2Cacti::Cacti::Method;
use N2Cacti::database;
use Digest::MD5 qw(md5 md5_hex md5_base64);

BEGIN {
        use Exporter   	();
        use vars       	qw($VERSION @ISA @EXPORT @EXPORT_OK);
        @ISA 		=	qw(Exporter);
        @EXPORT 	= 	qw();
}

my $tables = {
	data_template 		=> '',
	data_template_data 	=> '',
	data_template_rrd	=> '',
	data_template_data_rra	=> '',
	data_local			=> '',
};


sub new {
	#-- contient la definition des tables
	my $class = shift;	
	my $attr=shift;
	my %param = %$attr if $attr;
	my $this={
		tables 								=> $tables,
		hostname 							=> $param{hostname},
		service_description 				=> $param{service_description},
		rrd									=> $param{rrd}, # rrd provide template, datasource and path_rrd now!
		source								=> $param{source} || "Nagios",
		log_msg								=> $param{cb_log_msg}			|| \&default_log_msg,
		};
		
	$this->{template}						= $this->{rrd}->getTemplate();
	$this->{service_name}					= $this->{rrd}->getServiceName();
	$this->{data_template_name}				= "$$this{source} - $$this{service_name}";
	$this->{data_template_data_name}		= "|host_description| - $$this{service_name}";

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


# -------------------------------------------------------------

sub tables{
	my $this=shift;
	return $this->{tables};
}


sub database{
	return shift->{database};
}

# -------------------------------------------------------------
sub get_input {
	my $this = shift;
	my $debug=shift||0;
	my $method = new N2Cacti::Cacti::Method({source => $$this{source},debug=>$debug });
	return $method->create_method();
}


#-- verify if the template exist
sub template_exist {
	my $this=shift;
	return $this->database->item_exist("data_template", { 
		hash => generate_hash($this->{data_template_name}) });		
}

sub table_save {
	my $this = shift;
	my $tablename=shift;
	if(defined($this->{tables}->{$tablename})){
		return $this->database->sql_save(shift ,$tablename);
	}
	die "N2Cacti::Data::table_save - wrong parameter tablename value : $tablename";
}


#-- create individual template and instance for each couple (service_name, datasource) not in main datasource
sub create_individual_instance {
	my $this		= shift;
	my $debug 		= shift ||0;
	$this->log_msg("-->N2Cacti::Data::create_individual_instance();") if $debug;
	my $main_rrd	= $this->{rrd}->getPathRRD();
	my $data_template_name	= $this->{data_template_name};
	my $data_template_data_name	= $this->{data_template_data_name};
	
	my $datasource = $this->{rrd}->{datasource};
	while (my ($ds_name, $ds) = each (%$datasource)){
		next if ($main_rrd eq $ds->{rrd_file});
		$this->{data_template_name}				= "$this->{source} - $$this{service_name} - $ds_name";
		$this->{data_template_data_name}		= "|host_description| - $$this{service_name} - $ds_name";
		$this->{rrd}->setPathRRD($ds->{rrd_file});
		$this->create_instance($debug);
		$this->update_rrd($debug);
	}
	$this->{rrd}->setPathRRD($main_rrd);
	$this->{data_template_name}				= $data_template_name;
	$this->{data_template_data_name}		= $data_template_data_name;
	$this->log_msg("<--N2Cacti::Data::create_individual_instance();") if $debug;
}


# -------------------------------------------------------------
sub create_instance {
	my $this		= shift;
	my $debug 		= shift ||0;
	my %ids			= ();
	my $source 		= $this->{source};
	my ($dl, $dtd);

	$this->log_msg("-->N2Cacti::Data::create_instance($$this{hostname},$$this{service_description})")	if $debug;
	
	#-- if template dont exist, we must created!
	if($this->template_exist ==0){
		$this->create_template(shift||0,$debug);
	}

	
	if($this->template_exist!=0){
		$this->database->begin();
		eval{
			$ids{data_template_id} = $this->database->get_id("data_template", { 
				hash => generate_hash($this->{data_template_name}) });

			$dtd = $this->database->db_fetch_hash("data_template_data", { 
				data_template_id => $ids{data_template_id}, 
				local_data_id => 0},$debug);
			
			$this->log_msg("$ids{data_template_id} - $$dtd{id}") if ($debug);
			
			$ids{data_template_data_id}=$dtd->{id}; 		
			
			
			#-- get the data_local
			$ids{host_id}			= $this->database->get_id("host", {
				description => $$this{hostname}} );
	
			if($this->database->item_exist("data_local", { 
				host_id => $ids{host_id}, 
				data_template_id=>$ids{data_template_id}})){
				$dl = $this->database->db_fetch_hash("data_local", { 
					host_id => $ids{host_id}, 
					data_template_id=>$ids{data_template_id}});
					
				$this->log_msg	("\tdata_local for host [$$this{hostname}] and ".
					"service [$$this{service_description}] exist") if ($debug);
				return $dl->{id};
			}
			
			
			#-- the data_local dont exist, we need to create it
			#-- create the data_local parameter in data_template_data
			$dl->{id}				= "0";
			$dl->{host_id}			= $this->database->get_id("host", {
				description => $$this{hostname}} );
			$dl->{data_template_id}	= $ids{data_template_id};
			$dl->{id}				= $this->table_save("data_local", $dl);
	
			
			#-- create of data_template with the template parameter
			$dtd->{id} 							= "0";
			$dtd->{local_data_template_data_id}	= $ids{data_template_data_id};
			$dtd->{data_template_id}			= $ids{data_template_id};
			$dtd->{local_data_id}				= $dl->{id};
			$dtd->{data_source_path}			= $this->{rrd}->{rrd_file};
			$dtd->{name_cache}					= $dtd->{name};
			$dtd->{name_cache}					=~ s/\|host_description\|/$$this{hostname}/g;
			$dtd->{id}							= $this->table_save("data_template_data", $dtd);
			$this->log_msg(__LINE__."\t:saving data_template_data($$dtd{id}") if $debug;

	    	$this->log_msg(__LINE__."\t:creating rra") if $debug;    
			#-- creating rra (we're creating four RRA (daily, weekly, monthly, yearly)
	        $this->database->execute("delete from data_template_data_rra where data_template_data_id='$$dtd{id}'");
	        for (my $i=0;$i<4;$i++){
	            my $dtrra = $this->database->new_hash("data_template_data_rra");
	            $dtrra->{data_template_data_id}=$dtd->{id};
	            $dtrra->{rra_id}=$i+1;
	            $this->table_save("data_template_data_rra", $dtrra);
	        }
	
			$this->log_msg( "\tcommit")	if $debug;
			$this->database->commit();
			$this->log_msg( "<--N2Cacti::Data::create_instance() with commit")	if $debug;
			
			#-- creation des datasources
			return $dl->{id};
		};
		$this->log_msg( "<--N2Cacti::Data::create_instance() with rollback\n $@") and $this->database->rollback() if $@;
		return undef;
	}
}

sub create_template {
	my $this		= shift;
	my $templated	= shift ||$this->template_exist;
	my $debug 		= shift ||0;
	my $source 		= $this->{source};
	$this->log_msg("-->N2Cacti::Data::create_template();") if $debug;
	if($this->template_exist == 0){
        $this->database->begin();
        eval{

			my $dt = $this->database->new_hash("data_template");
			$dt->{id}		= "0"; 										# id not null implique qu'il y aura un nouvel enregistrement
			$dt->{name}		= $this->{data_template_name};	 			#optionnel
			$dt->{hash}		= generate_hash($this->{data_template_name});
			$dt->{id} 		= $this->table_save("data_template", $dt);
	
			$this->log_msg("save data_template ($$dt{id})") if $debug;
	
			# -- define data_template parameter
			my $dtd = $this->database->new_hash("data_template_data");
			$dtd->{id} 								= "0";
			$dtd->{local_data_template_data_id}		= "0";
			$dtd->{local_data_id}					= "0";
			$dtd->{data_input_id}					= $this->get_input($debug);
			$dtd->{t_name} 							= "";
			$dtd->{name} 							= $this->{data_template_data_name};
			$dtd->{t_active}						= "";
			$dtd->{active}							= ""; 			#	!!! DESACTIVER !!!
			$dtd->{t_rrd_step}						= "";
			$dtd->{rrd_step}						= "300";
			$dtd->{t_rra_id}						= "";
			$dtd->{data_template_id} 				= $dt->{id};	# identifiant du data_template
			$dtd->{data_source_path}				= "";
			$dtd->{name_cache}						= "";
			$dtd->{id}								= $this->table_save("data_template_data", $dtd);
			$this->log_msg(__LINE__."\t:saving data_template_data($$dtd{id})") if $debug;
			
			$this->log_msg("creating rra for the instance") if $debug;
			
			#-- creating rra (we're creating four RRA (daily, weekly, monthly, yearly)
			$this->database->execute("delete from data_template_data_rra where data_template_data_id='$$dtd{id}'");
			for (my $i=0;$i<4;$i++){
				my $dtrra = $this->database->new_hash("data_template_data_rra");
				$dtrra->{data_template_data_id}=$dtd->{id};
				$dtrra->{rra_id}=$i+1;
				$this->table_save("data_template_data_rra", $dtrra);
			}
	
			$this->log_msg("commit();") if $debug;
            # if this is reached, queries succeeded; commit them
            $this->database->commit();
        };
        $this->database->rollback() if $@;
		$this->log_msg( $@."\n") if $@;
	}
	$this->log_msg("<--N2Cacti::Data::create_template();") if $debug;
}


#--------------------------------------------------------------
# -- update des rrd / datasource
sub update_rrd {
	my $this        		= shift;
    my $debug       		= shift ||0;
	my $state = {};
	my $datasource 			= $this->{rrd}->getDataSource();
    my $source      		= $this->{source};
	my ($hostid, $dt, $dtd,$dl);
	
	$this->log_msg("-->N2Cacti::Data::update_rrd()") if $debug;


	# -- got templates (must exist)
	 
	if(!$this->database->item_exist("host", {
				description => $$this{hostname}} )){
		$this->log_msg( "host not found for  [$$this{hostname}] - check api_cacti script") ;
		die "host not found for  [$$this{hostname}] - check api_cacti script" ;
	}
	
	try {
		$hostid			= $this->database->get_id("host", {
				description => $$this{hostname}} );
				
		$dt 				= $this->database->db_fetch_hash("data_template", { 
			hash => generate_hash($this->{data_template_name}) });
		$dtd 			= $this->database->db_fetch_hash("data_template_data", { 
			data_template_id => $dt->{id}, 
			local_data_id => 0});
		$dl 		     	= $this->database->db_fetch_hash("data_local", { 
			host_id => $hostid, 
			data_template_id => $dt->{id}});
	}
	catch {
		$_ =~ /DATABASE - NO RESULT/ and $this->log_msg("ERROR : $_ : ") and die "ERROR : $_";
	};
            

	# -- we initiate all datasource to be delete
	$this->log_msg(__LINE__."\t:init all existing datasource to be delete, update or create") if $debug;
	my $sth = $this->database->execute("SELECT data_source_name FROM data_template_rrd WHERE data_template_id ='$$dt{id}'");
	while (my @row=$sth->fetchrow()){
		$state->{$row[0]}="del";
	}

	# -- datasource create or update
	
	while(my ($key, $ds) = each (%$datasource)){
		next if ($ds->{rrd_file} ne $this->{rrd}->{rrd_file}); # skip individual rrd
		$this->log_msg(__LINE__."\t:create or update data_template_rrd [$$ds{ds_name}]") if$debug;
		# -- define the datasource state
		if(!defined($state->{$ds->{ds_name}})){
		    $state->{$ds->{ds_name}} = "new";
		}
		else{
			$state->{$ds->{ds_name}} = "update";
		}
		$this->log_msg(__LINE__."\t:creating data_template_rrd [$$ds{ds_name}]") if$debug;
		$this->database->begin();
		eval{
			my $dtr = {};
			if($state->{$ds->{ds_name}} eq "new"){
				$this->log_msg(__LINE__."\t:create data_template_rrd for [$$ds{ds_name}]") if $debug;	
				$dtr = $this->database->new_hash("data_template_rrd");
				$dtr->{id}							= "0";
				$dtr->{hash} 						= generate_hash($$ds{ds_name}.generate_hash($$this{data_template_name}));
				$dtr->{local_data_template_rrd_id}	= "0"; # chainage interne 0 pour un template
				$dtr->{local_data_id}				= "0"; # identifiant de l'instance 0 pour un template
				$dtr->{data_template_id}			= $dt->{id};
				$dtr->{rrd_maximum}					= $ds->{max}||"0";
				$dtr->{rrd_minimum}					= $ds->{min}||"0";
				$dtr->{rrd_heartbeat}				= $ds->{heartbeat};
				$dtr->{data_source_type_id}			= $data_source_type->{$ds->{ds_type}};
				$dtr->{data_source_name}			= $ds->{ds_name};
				$dtr->{data_input_field_id}			= "0";
				$dtr->{id}							=$this->table_save("data_template_rrd",$dtr);

				$this->database->commit();
				$this->database->begin();
			}
		
			# -- load the instance if existing
			$this->log_msg(__LINE__."\t:load data_template_rrd for [$$ds{ds_name}]") if $debug;	
			
			$dtr = $this->database->db_fetch_hash("data_template_rrd", {
	            	data_template_id 			=> $dt->{id},
		            local_data_id				=> 0 ,
		            local_data_template_rrd_id 	=> 0,
	    	        data_source_name 			=> $ds->{ds_name} 
					});
	
			
			# -- if the data_local exist then we instanciate the data_template
			if(defined($dl)){
			    my $template_id = $dtr->{id};
				# -- on recupère l'instance existante, 0 sinon
				$this->log_msg(__LINE__."\t:instancie data_template_rrd for [$$ds{ds_name}] on [$$this{hostname}]") if $debug;	
				my $dtr_id = $this->database->get_id("data_template_rrd", {
					local_data_template_rrd_id 	=> $template_id,
					local_data_id				=> $dl->{id},
					data_template_id			=> $dt->{id},
	    	        #data_source_name 			=> $ds->{ds_name} # useless local_data_template_rrd_id defined
					});
					
				$dtr->{id} = $dtr_id || "0";
			    $dtr->{hash}                        = "";           # il s'agit d'une instance generate_hash(); # genere un hash aléatoire
		    	$dtr->{local_data_template_rrd_id}  = $template_id;      # chainage interne
			    $dtr->{local_data_id}               = $dl->{id};
			    $dtr->{data_template_id}            = $dt->{id};
				$dtr->{rrd_maximum}					= $ds->{max} || 0;
				$dtr->{rrd_minimum}					= $ds->{min} || 0;
				$dtr->{rrd_heartbeat}				= $ds->{heartbeat};
				$dtr->{data_source_type_id}			= $data_source_type->{$ds->{ds_type}};
			    $dtr->{id}                          = $this->table_save("data_template_rrd", $dtr);
			}
			$this->log_msg(__LINE__."\t:commit") if $debug;
			$this->database->commit();
		};
		$this->database->rollback() if $@;
		$this->log_msg(__LINE__."\t:end of creating de [$$ds{ds_name}]") if $debug;
	}

	# -- delete older data_source
	$this->log_msg(__LINE__."\t:delete older data_source") if $debug;
	while( my ($key, $value)=each(%$state)){
		if($value eq "del"){
			my $dtrid = $this->database->db_fetch_cell("SELECT id FROM data_template_rrd WHERE data_template_id ='$$dt{id}' AND data_source_name='$key' AND local_data_id='0'");
			log_msg(__LINE__."\t:suppression du ds_name : $key") if $debug;
			$this->database->execute("	DELETE FROM graph_templates_item A 
										LEFT JOIN graph_template_input_defs B ON B.graph_template_item_id=A.id 
										LEFT JOIN graph_template_input_defs C ON B.graph_template_input_id=C.id 
										WHERE A.task_item_id='$dtrid'");
			$this->database->execute("DELETE FROM data_template_rrd WHERE data_template_id ='$$dt{id}' AND data_source_name='$key'");
		}
	}
	$this->log_msg("<--N2Cacti::Data::update_rrd()") if $debug;

}


#-- try catch code :
#    sub try (&@) {
#	my($try,$catch) = @_;
#	eval { &$try };
#	if ($@) {
#	    local $_ = $@;
#	    &$catch;
#	}
#   }
#    sub catch (&) { $_[0] }

#    try {
#	die "phooey";
#    } catch {
#	/phooey/ and print "unphooey\n";
#    };  

# -- defini des array dont les données sont fixé dans le code source de cacti : /var/www/cacti/include/config_arrays.php

# -- definition de la structure des tables et valeur par défaut + description des champs en commentaire
# -- cette definition sert surtout en guise de commentaire, la liste des champs des tables sont obtenu via la fonction : new_hash



#-- we dont need this variable with N2Cacti::database::new_hash method
my $__tables = {
			data_template => {						# liste of template (hors instance)
				id 		=> 0,						# (1)
				name 	=> "", 						# format : "nagios - <TEMPLATENAME>" - the template name will be service_name return by RRD,
													# this field must be unique for template create for nagios
				hash 	=> "",	 					# generate by generate_hash()
			},										#-------------------------------------------------	
			data_template_data => {					# template and instance parameter for data_template
				id							=> "0", # (2)
				local_data_template_data_id	=> "0",	# template = 0 / instance = id of template based (2)
				local_data_id				=> "0",	# template = 0 / the data_local id based on
				data_input_id				=> "0", # fictive nagios command
				t_name						=> "",	# valeur : on / ""
				name						=> "", 	# "|host_description| - nagios - name of services", 
				t_active					=> "",
				active						=> "",	# value : on / "" (always "" for the templates/instance from nagios)
				t_rrd_step					=> "",
				rrd_step					=> "300",
				t_rra_id					=> "",
				data_template_id			=> "",  # id return by creating of data_template (1)
				data_source_path			=> "",	# datasource path
				name_cache					=> "",
			},										#-------------------------------------------------	
			data_template_rrd => {					# datasource parameter des DS (DataSource) 
				id							=> "0", # (3)
				hash						=> "",	# generate by generate_hash() / "" for a instance
				local_data_template_rrd_id	=> "0", # 0 for template / id for instance (3)
				local_data_id				=> "0", # 0 pour un template / data_local id for instance (5)
				t_rrd_maximum				=> "",	# valeur : on ou ""
				rrd_maximum					=> "0",
				t_rrd_minimum				=> "",	# valeur : on ou ""
				rrd_minimum					=> "0",
				t_rrd_heartbeat				=> "",	# valeur : on ou ""
				rrd_heartbeat				=> "",	# ds->{heartbeat}
				t_data_source_type_id		=> "",  # valeur : on ou ""
				data_source_type_id			=> "1", # reference to N2Cacti::Cacti::$data_source_type
				t_data_source_name			=> "",  # valeur : on ou ""
				data_source_name			=> "",	# datasource name (ds->{ds_name}) 
				t_data_input_field_id		=> "",  # valeur : on ou ""
				data_input_field_id			=> "0",
				data_template_id			=> "" 	# id renvoyer par la création de data_template
			},										#-------------------------------------------------	
			data_template_data_rra => {				# affectation des rra (type & freq des agregats) au template
													# la table rra contient la description des rra 
													# la table rra_cf contient la liaison avec les fonctions d'aggrégats (min, max,average...)
				rra_id						=> "",	# (4) reference à la table rra
				data_template_data_id		=> ""	# id du template ou de l'instance
			},										#-------------------------------------------------	
			data_local => { 						# instance des data_template pour les hôtes correspondant
				id							=> "0",	# (5) instance id
				data_template_id			=> "",	# id du data_template
				host_id						=> ""	# id de l'hote
			},										#-------------------------------------------------	
		};



1;
