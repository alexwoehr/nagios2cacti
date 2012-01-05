# tsync:: casole
# sync:: calci
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
	data_local		=> '',
};

#
# new
#
# The constructor
#
# @args		: parameters hash ref { tables, hostname, service_description, rrd, source }
# @return	: the object
#
sub new {
	my $class	= shift;	
	my $attr	= shift;

	my %param	= %$attr if $attr;
	my $this	= {
		tables			=> $tables,
		hostname		=> $param{hostname},
		service_description	=> $param{service_description},
		rrd			=> $param{rrd}, # rrd provide template, datasource and path_rrd now!
		source			=> $param{source} || "Nagios"
	};

	Main::log_msg("--> N2Cacti::Cacti::Data::new()", "LOG_DEBUG");

	$this->{template}			= $this->{rrd}->getTemplate();
	$this->{service_name}			= $this->{rrd}->getServiceName();
	$this->{data_template_name}		= "$$this{source} - $$this{service_name}";
	$this->{data_template_data_name}	= "|host_description| - $$this{service_name}";

	my $cacti_config = get_cacticonfig();
	$this->{database} = new N2Cacti::database({
		database_type		=> $$cacti_config{database_type},
		database_schema		=> $$cacti_config{database_default},
		database_hostname	=> $$cacti_config{database_hostname},
		database_username	=> $$cacti_config{database_username},
		database_password	=> $$cacti_config{database_password},
		database_port		=> $$cacti_config{database_port}
	});

	bless ($this, $class);

	Main::log_msg("<-- N2Cacti::Cacti::Data::new()", "LOG_DEBUG");
	return $this;
}

#
# tables
#
# Tables accessor
#
# @args		: none
# @return	: the tables
#
sub tables {
	return shift->{tables};
}

#
# database
#
# Database accessor
#
# @args		: none
# @return	: the database
#
sub database {
	return shift->{database};
}

#
# get_input
#
# Creates an input method and returns it
#
# @args		: none
# @return	: the input method object
#
sub get_input {
	my $this	= shift;

	Main::log_msg("--> N2Cacti::Cacti::Data::get_input()", "LOG_DEBUG");

	my $method	= new N2Cacti::Cacti::Method({ source => $$this{source} });
	my $input	= $method->create_method();

	Main::log_msg("<-- N2Cacti::Cacti::Data::get_input()", "LOG_DEBUG");
	return $input;
}

#
# template_exist
#
# Does the template exist ?
#
# @args		: none
# @return	: yes (1) || no (0)
#
sub template_exist {
	my $this	= shift;

	Main::log_msg("--> N2Cacti::Cacti::Data::template_exist()", "LOG_DEBUG");

	my $result	= $this->database->item_exist("data_template", { hash => generate_hash($this->{data_template_name}) });

	Main::log_msg("<-- N2Cacti::Cacti::Data::template_exist()", "LOG_DEBUG");

	return $result;
}

#
# table_save
#
# Calls sql_save
#
# @args		: the table hash ref
# @return	: 
#
sub table_save {
	my $this	= shift;
	my $tablename	= shift;

	my $result	= undef;

	Main::log_msg("--> N2Cacti::Cacti::Data::table_save()", "LOG_DEBUG");

	if ( defined($this->{tables}->{$tablename}) ) {
		$result = $this->database->sql_save(shift ,$tablename);
	} else {
		Main::log_msg("N2Cacti::Cacti::Data::table_save(): wrong parameter tablename value : $tablename", "LOG_ERR");
	}

	Main::log_msg("--> N2Cacti::Cacti::Data::table_save()", "LOG_DEBUG");

	return $result;
}

#
# create_individual_instance
#
# Create individual template and instance for each couple (service_name, datasource) not in main datasource
#
# @args		: none
# @return	: none
#
sub create_individual_instance {
	my $this	= shift;

	Main::log_msg("--> N2Cacti::Cacti::Data::create_individual_instance()", "LOG_DEBUG");

	my ($ds_name, $ds);

	my $data_template_name		= $this->{data_template_name};
	my $data_template_data_name	= $this->{data_template_data_name};
	my $datasource			= $this->{rrd}->{datasource};

	foreach $ds_name (keys %$datasource) {

		$this->{data_template_name}		= "$this->{source} - $$this{service_name} - $ds_name";
		$this->{data_template_data_name}	= "|host_description| - $$this{service_name} - $ds_name";

		$this->{rrd}->setPathRRD($datasource->{$ds_name}->{rrd_file});
		$this->create_instance();
		$this->update_rrd();
	}

	$this->{data_template_name} = $data_template_name;
	$this->{data_template_data_name} = $data_template_data_name;

	Main::log_msg("<-- N2Cacti::Cacti::Data::create_individual_instance()", "LOG_DEBUG");
}

#
# create_instance
#
# Creates the data template instantiate it
#
# @args		: none
# @return	: the new id or undef
#
sub create_instance {
	my $this		= shift;

	my %ids			= ();
	my $source 		= $this->{source};
	my ($dl, $dtd, $dtdt);

	Main::log_msg("--> N2Cacti::Cacti::Data::create_instance($$this{hostname},$$this{service_description})", "LOG_DEBUG");
	
	#-- if template dont exist, we must create it!
	if( $this->template_exist == 0 ) {
		$dtdt = $this->create_template(shift||0);
	}
		$this->database->begin();
		eval {
			# insert the link in data_template_data :
			# 	local_data_id : data_local->id
			# 	data_template_id : data_template->id

			#-- the data_local doesn't exist, we need to create it
			#-- create the data_local parameter in data_template_data
			$dl->{id}		= "0";
			$dl->{host_id}		= $this->database->get_id("host", {description => $$this{hostname}});
			$dl->{data_template_id}	= $this->database->get_id("data_template", { hash => generate_hash($this->{data_template_name}) });
			$dl->{id}		= $this->table_save("data_local", $dl);

			#-- create of data_template with the template parameter
			if ( $this->database->item_exist("data_template_data" , { data_template_id => $dl->{data_template_id}, local_data_id => $dl->{id} } ) == 0 ) {
				$dtd->{id}				= "0";
				$dtd->{name}				= "|host_description| - $this->{service_description}";
				$dtd->{local_data_template_data_id}	= $dtdt;
				#$dtd->{data_template_id} = $dl->{host_id};
				$dtd->{data_template_id}		= $dl->{data_template_id};
				$dtd->{local_data_id}			= $dl->{id};
				$dtd->{data_source_path}		= $this->{rrd}->{rrd_file};
				$dtd->{name_cache}			= $dtd->{name};
				$dtd->{data_input_id}			= $this->database->get_id("data_input", { name => "$$this{source} import via n2cacti" });
				$dtd->{name_cache}			=~ s/\|host_description\|/$$this{hostname}/g;
				$dtd->{id}				= $this->table_save("data_template_data", $dtd);

				Main::log_msg("N2Cacti::Cacti::Data::create_instance(): saving data_template_data($$dtd{id}", "LOG_DEBUG");
			}

			$dtd = $this->database->db_fetch_hash("data_template_data", { data_template_id => $dtd->{data_template_id}, local_data_id => $dl->{id} });
			
			Main::log_msg("N2Cacti::Cacti::Data::create_instance(): $dtd->{data_template_id} - $dtd->{id}", "LOG_DEBUG");

			#-- get the data_local
			if ( $this->database->item_exist("data_local", { host_id => $dl->{host_id}, data_template_id => $dtd->{data_template_id} }) == 1 ) {
				$dl = $this->database->db_fetch_hash("data_local", { host_id => $dl->{host_id}, data_template_id => $dl->{data_template_id}});

				Main::log_msg("N2Cacti::Cacti::Data::create_instance(): data_local for host [$$this{hostname}] and service [$$this{service_description}] exist", "LOG_DEBUG");
				return $dl->{id};
			}

			Main::log_msg("N2Cacti::Cacti::Data::create_instance(): creating rra", "LOG_DEBUG");

			#-- creating rra (we're creating four RRA (daily, weekly, monthly, yearly)
			$this->database->execute("delete from data_template_data_rra where data_template_data_id='$$dtd{id}'");
			for ( my $i=0;$i<4;$i++ ) {
				my $dtrra = $this->database->new_hash("data_template_data_rra");
				$dtrra->{data_template_data_id}=$dtd->{id};
				$dtrra->{rra_id}=$i+1;
				$this->table_save("data_template_data_rra", $dtrra);
			}
	
			Main::log_msg( "N2Cacti::Cacti::Data::create_instance(): commit", "LOG_DEBUG");
			$this->database->commit();
			Main::log_msg( "<-- N2Cacti::Cacti::Data::create_instance() with commit", "LOG_DEBUG");
			
			#-- creation des datasources
			return $dl->{id};
		};
		Main::log_msg( "<-- N2Cacti::Cacti::Data::create_instance() with rollback\n $@", "LOG_ERR") and $this->database->rollback() if $@;
		return undef;
	#}
}

#
# create_template
#
# Creates the data template
#
# @args		: templated (does the template already exist?)
# @return	: the id or undef
#
sub create_template {
	my $this	= shift;
	my $templated	= shift || $this->template_exist;

	my $source	= $this->{source};
	my ($dtd, $dt);

	Main::log_msg("--> N2Cacti::Cacti::Data::create_template()", "LOG_DEBUG");

	if ( $this->template_exist == 0 )  {
		$this->database->begin();
		eval {
			$dt		= $this->database->new_hash("data_template");
			$dt->{id}	= "0"; # id not null implique qu'il y aura un nouvel enregistrement
			$dt->{name}	= $this->{data_template_name}; #optionnel
			$dt->{hash}	= generate_hash($this->{data_template_name});
			$dt->{id}	= $this->table_save("data_template", $dt);

			Main::log_msg("N2Cacti::Cacti::Data::create_template(): save data_template ($$dt{id})", "LOG_DEBUG");

			# -- define data_template parameter
			$dtd					= $this->database->new_hash("data_template_data");
			$dtd->{id} 				= "0";
			$dtd->{local_data_template_data_id}	= "0";
			$dtd->{local_data_id}			= "0";
			$dtd->{data_input_id}			= $this->get_input();
			$dtd->{t_name} 				= "";
			$dtd->{name} 				= $this->{data_template_data_name};
			$dtd->{t_active}			= "";
			$dtd->{active}				= ""; 			#	!!! DESACTIVER !!!
			$dtd->{t_rrd_step}			= "";
			$dtd->{rrd_step}			= "300";
			$dtd->{t_rra_id}			= "";
			$dtd->{data_template_id} 		= $dt->{id};	# identifiant du data_template
			$dtd->{data_source_path}		= "";
			$dtd->{name_cache}			= "";
			$dtd->{id}				= $this->table_save("data_template_data", $dtd);

			Main::log_msg("N2Cacti::Cacti::Data::create_template(): saving data_template_data($$dtd{id})", "LOG_DEBUG");
			Main::log_msg("N2Cacti::Cacti::Data::create_template(): creating rra for the instance", "LOG_DEBUG");

			#-- creating rra (we're creating four RRA (daily, weekly, monthly, yearly)
			$this->database->execute("delete from data_template_data_rra where data_template_data_id='$$dtd{id}'");
			for ( my $i=0;$i<4;$i++ ) {
				my $dtrra			= $this->database->new_hash("data_template_data_rra");
				$dtrra->{data_template_data_id}	= $dtd->{id};
				$dtrra->{rra_id}		= $i+1;
				$this->table_save("data_template_data_rra", $dtrra);
			}
	
			Main::log_msg("N2Cacti::Cacti::Data::create_template(): commit()", "LOG_DEBUG");
			# if this is reached, queries succeeded; commit them
			$this->database->commit();
		};

		$this->database->rollback() if $@;
		Main::log_msg("N2Cacti::Cacti::Data::create_template(): rollback :  $@", "LOG_ERR") if $@;
	}

	Main::log_msg("<-- N2Cacti::Cacti::Data::create_template()", "LOG_DEBUG");
	return $dtd->{id};
}

#
# update_rrd
#
# We initiate all datasource to be delete
# Datasource create or update
# Delete older data_source
#
# @args		: none
# @return	: none
#
sub update_rrd {
	my $this	= shift;

	my $state	= {};
	my $datasource	= $this->{rrd}->getDataSource();
	my $source	= $this->{source};
	my ($hostid, $dt, $dtd, $dl);
	
	Main::log_msg("--> N2Cacti::Cacti::Data::update_rrd()", "LOG_DEBUG");

	# -- got templates (must exist)
	if ( ! $this->database->item_exist( "host", { description => $$this{hostname}} ) ) {
		Main::log_msg("N2Cacti::Cacti::Data::update_rrd(): host not found for  [$$this{hostname}] - check api_cacti script", "LOG_ERR");
		return undef;
	}

	$hostid = $this->database->get_id( "host", { description => $$this{hostname} } );

	# Le data template n'existe pas pour le service general donc ca plante	
	$dt = $this->database->db_fetch_hash("data_template", { hash => generate_hash($this->{data_template_name}) });

	if ( $this->database->item_exist("data_local", { host_id => $hostid, data_template_id => $dt->{id}}) == 1 ) {
		$dl = $this->database->db_fetch_hash("data_local", { host_id => $hostid, data_template_id => $dt->{id}});
	} else {
		$dl->{id} = "0";
		$dl->{host_id}  = $hostid;
		$dl->{data_template_id} = $dt->{id};
		$dl->{id} = $this->database->table_save( "data_local", $dl );
	}

	# -- we initiate all datasource to be delete
	Main::log_msg("N2Cacti::Cacti::Data::update_rrd(): init all existing datasource to be delete, update or create", "LOG_DEBUG");
	my $sth = $this->database->execute("SELECT data_source_name FROM data_template_rrd WHERE data_template_id ='$$dt{id}'");
	while ( my @row = $sth->fetchrow() ){
		$state->{$row[0]} = "del";
	}

	# -- datasource create or update
	foreach my $key (keys %$datasource) {
		next if ($datasource->{$key}->{rrd_file} ne $this->{rrd}->{rrd_file});
		Main::log_msg("N2Cacti::Cacti::Data::update_rrd(): create or update data_template_rrd [$key]", "LOG_DEBUG");

		# -- define the datasource state
		if( ! defined($state->{$key}) ) {
			$state->{$key} = "new";
		} else {
			$state->{$key} = "update";
		}

		Main::log_msg("N2Cacti::Cacti::Data::update_rrd(): creating data_template_rrd [$key]", "LOG_DEBUG");
		$this->database->begin();

		eval {
			my $dtr = {};
			if ( $state->{$key} eq "new" ) {
				Main::log_msg("N2Cacti::Cacti::Data::update_rrd(): create data_template_rrd for [$key]", "LOG_DEBUG");	

				$dtr					= $this->database->new_hash("data_template_rrd");
				$dtr->{hash}				= generate_hash($key.generate_hash($this->{data_template_name}));
				$dtr->{local_data_template_rrd_id}	= "0"; # chainage interne 0 pour un template
				$dtr->{local_data_id}			= "0"; # identifiant de l'instance 0 pour un template
				$dtr->{data_template_id}		= $dt->{id};
				$dtr->{rrd_maximum}			= $datasource->{$key}->{max}||"0";
				$dtr->{rrd_minimum}			= $datasource->{$key}->{min}||"0";
				$dtr->{rrd_heartbeat}			= $datasource->{$key}->{heartbeat};
				$dtr->{data_source_type_id}		= $data_source_type->{$datasource->{$key}->{ds_type}};
				$dtr->{data_source_name}		= $key;
				$dtr->{data_input_field_id}		= "0";
				$dtr->{id}				= $this->table_save("data_template_rrd", $dtr);

				$this->database->commit();
				$this->database->begin();
			}

			# -- load the instance if existing
			Main::log_msg("N2Cacti::Cacti::Data::update_rrd(): load data_template_rrd for [$key]", "LOG_DEBUG");	

			$dtr = $this->database->db_fetch_hash("data_template_rrd", {
				data_template_id		=> $dt->{id},
				local_data_id			=> 0 ,
				local_data_template_rrd_id 	=> 0,
				data_source_name 		=> $key
			});

			# -- if the data_local exist then we instanciate the data_template
			if ( defined $dl ) {
				my $template_id = $dtr->{id};
				# -- on recupère l'instance existante, 0 sinon
				Main::log_msg("N2Cacti::Cacti::Data::update_rrd(): instancie data_template_rrd for [$datasource->{$key}->{ds_name}] on [$$this{hostname}]", "LOG_DEBUG");

				if ( $this->database->item_exist( "data_template_rrd", { local_data_template_rrd_id => $template_id, local_data_id => $dl->{id}, data_template_id => $dt->{id} } ) == 1 ) {
					$dtr->{id} = $this->database->get_id("data_template_rrd", {
						local_data_template_rrd_id 	=> $template_id,
						local_data_id			=> $dl->{id},
						data_template_id		=> $dt->{id},
						#data_source_name 		=> $ds->{ds_name} # useless local_data_template_rrd_id defined
					});
				} else {
					$dtr->{id} = "0";
				}

				$dtr->{hash}				= "";           # il s'agit d'une instance generate_hash(); # genere un hash aléatoire
				$dtr->{local_data_template_rrd_id}	= $template_id;      # chainage interne
				$dtr->{local_data_id}			= $dl->{id};
				$dtr->{data_template_id}		= $dt->{id};
				$dtr->{rrd_maximum}			= $datasource->{$key}->{max} || 0;
				$dtr->{rrd_minimum}			= $datasource->{$key}->{min} || 0;
				$dtr->{rrd_heartbeat}			= $datasource->{$key}->{heartbeat};
				$dtr->{data_source_type_id}		= $data_source_type->{$datasource->{$key}->{ds_type}};
				$dtr->{id}				= $this->table_save("data_template_rrd", $dtr);
			}

			Main::log_msg("N2Cacti::Cacti::Data::update_rrd(): commit", "LOG_DEBUG");
			$this->database->commit();
		};

		$this->database->rollback() if $@;
		Main::log_msg("N2Cacti::Cacti::Data::update_rrd(): end of creating de [$key]", "LOG_DEBUG");
	}

	# -- delete older data_source
	Main::log_msg("N2Cacti::Cacti::Data::update_rrd(): delete older data_source", "LOG_DEBUG");
	while ( my ($key, $value) = each(%$state) ) {
		if($value eq "del"){
			my $command = "SELECT id FROM data_template_rrd WHERE data_template_id ='$$dt{id}' AND data_source_name='$key' AND local_data_id='0'";
			Main::log_msg("N2Cacti::Cacti::Data::update_rrd(): sql command : $command", "LOG_DEBUG");

			my $dtrid = $this->database->db_fetch_cell($command);
			Main::log_msg("N2Cacti::Cacti::Data::update_rrd(): suppression du ds_name : $key", "LOG_DEBUG");

			$command = "DELETE FROM graph_template_input_defs WHERE graph_template_item_id IN (SELECT id FROM graph_templates_item where task_item_id='$dtrid');";
			Main::log_msg("N2Cacti::Cacti::Data::update_rrd(): sql command : $command", "LOG_DEBUG");
			$this->database->execute($command);

			$command = "DELETE FROM graph_templates_item where task_item_id='$dtrid';";
			Main::log_msg("N2Cacti::Cacti::Data::update_rrd(): sql command : $command", "LOG_DEBUG");
			$this->database->execute($command);

			$command = "DELETE FROM data_template_rrd WHERE data_template_id ='".$$dt{id}."' AND data_source_name='$key';";
			Main::log_msg("N2Cacti::Cacti::Data::update_rrd(): sql command : $command", "LOG_DEBUG");
			$this->database->execute($command);
		}
	}

	Main::log_msg("<-- N2Cacti::Cacti::Data::update_rrd()", "LOG_DEBUG");
}

#-- we dont need this variable with N2Cacti::database::new_hash method
my $__tables = {
	data_template => {	# liste of template (hors instance)
		id				=> 0,	# (1)
		name				=> "", 	# format : "nagios - <TEMPLATENAME>" - the template name will be service_name return by RRD,
		# this field must be unique for template create for nagios
		hash				=> "",	# generate by generate_hash()
	},

	data_template_data => {	# template and instance parameter for data_template
		id				=> "0", # (2)
		local_data_template_data_id	=> "0",	# template = 0 / instance = id of template based (2)
		local_data_id			=> "0",	# template = 0 / the data_local id based on
		data_input_id			=> "0", # fictive nagios command
		t_name				=> "",	# valeur : on / ""
		name				=> "", 	# "|host_description| - nagios - name of services", 
		t_active			=> "",
		active				=> "",	# value : on / "" (always "" for the templates/instance from nagios)
		t_rrd_step			=> "",
		rrd_step			=> "300",
		t_rra_id			=> "",
		data_template_id		=> "",  # id return by creating of data_template (1)
		data_source_path		=> "",	# datasource path
		name_cache			=> "",
	},

	data_template_rrd => {	# datasource parameter des DS (DataSource) 
		id				=> "0", # (3)
		hash				=> "",	# generate by generate_hash() / "" for a instance
		local_data_template_rrd_id	=> "0", # 0 for template / id for instance (3)
		local_data_id			=> "0", # 0 pour un template / data_local id for instance (5)
		t_rrd_maximum			=> "",	# valeur : on ou ""
		rrd_maximum			=> "0",
		t_rrd_minimum			=> "",	# valeur : on ou ""
		rrd_minimum			=> "0",
		t_rrd_heartbeat			=> "",	# valeur : on ou ""
		rrd_heartbeat			=> "",	# ds->{heartbeat}
		t_data_source_type_id		=> "",  # valeur : on ou ""
		data_source_type_id		=> "1", # reference to N2Cacti::Cacti::$data_source_type
		t_data_source_name		=> "",  # valeur : on ou ""
		data_source_name		=> "",	# datasource name (ds->{ds_name}) 
		t_data_input_field_id		=> "",  # valeur : on ou ""
		data_input_field_id		=> "0",
		data_template_id		=> "" 	# id renvoyer par la création de data_template
	},

	data_template_data_rra => {	# affectation des rra (type & freq des agregats) au template
		# la table rra contient la description des rra 
		# la table rra_cf contient la liaison avec les fonctions d'aggrégats (min, max,average...)
		rra_id				=> "",	# (4) reference à la table rra
		data_template_data_id		=> ""	# id du template ou de l'instance
	},

	data_local => {	# instance des data_template pour les hôtes correspondant
		id				=> "0",	# (5) instance id
		data_template_id		=> "",	# id du data_template
		host_id				=> ""	# id de l'hote
	},
};

1;

