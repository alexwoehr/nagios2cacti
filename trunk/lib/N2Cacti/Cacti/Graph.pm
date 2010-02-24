###########################################################################
#                                                                         #
# N2Cacti::Cacti::Graph                                                   #
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


package N2Cacti::Cacti::Graph;

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
	'graph_local'				=> '',
	'graph_templates'			=> '',
	'graph_templates_graph'		=> '',
	'graph_templates_item'		=> '',
	'graph_templates_gprint'	=> '',
	'graph_template_input'		=> '',
	'graph_template_input_defs'	=> ''
};


sub new {
	# -- contient la definition des tables
	my $class = shift;
	my $attr=shift;
	my %param = %$attr if $attr;
	my $this={
		tables			=> $tables,
		hostname		=> $param{hostname},
		service_description	=> $param{service_description},
		graph_item_type		=> $param{graph_item_type} || "AREA",
		rrd			=> $param{rrd}, # rrd provide template, datasource and path_rrd now!
		source			=> $param{source} || "Nagios",
		graph_item_colors	=> $param{graph_item_colors} || ""
	};

	Main::log_msg("--> N2Cacti::Cacti::Graph::new()", "LOG_DEBUG");

	$this->{template} = $this->{rrd}->getTemplate();
	$this->{service_name} = $this->{rrd}->getServiceName();

	# need to find the data_template_rrd...
	$this->{data_template_name} = "$$this{source} - $$this{service_name}";
	$this->{data_template_data_name} = "|host_description| - $$this{service_name}";

	$this->{graph_template_name} = "$$this{source} - $$this{service_name}";
	$this->{graph_template_graph_title} = "|host_description| - $$this{service_name}";

	#-- Connexion to cacti database
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

	Main::log_msg("<-- N2Cacti::Cacti::Graph::new()", "LOG_DEBUG");
	return $this;
}

# -------------------------------------------------------------

sub tables{
	return shift->{tables};
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

	Main::log_msg("N2Cacti::Cacti::Graph::table_save(): wrong parameter tablename value : $tablename", "LOG_ERR");
	return undef;
}

# -------------------------------------------------------------



#-- create individual template and instance for each couple (service_name, datasource) not in main datasource
sub create_individual_instance {
	my $this = shift;
	my $main_rrd = $this->{rrd}->getPathRRD();

	Main::log_msg("--> N2Cacti::Cacti::Graph::create_individual_instance()", "LOG_DEBUG");
	# need to find the data_template_rrd...		
	my $data_template_name		= $this->{data_template_name};
	my $data_template_data_name	= $this->{data_template_data_name};
	my $graph_template_name		= $this->{graph_template_name};
	my $graph_template_graph_name	= $this->{graph_template_graph_name};

	my $datasource = $this->{rrd}->{datasource};

	while (my ($ds_name, $ds) = each (%$datasource)){
		next if ($main_rrd eq $ds->{rrd_file});
		$this->{data_template_name}		= "$this->{source} - $$this{service_name} - $ds_name";
		$this->{data_template_data_name}	= "|host_description| - $$this{service_name} - $ds_name";
		$this->{graph_template_name}            = "$$this{source} - $$this{service_name} - $ds_name";
		$this->{graph_template_graph_title}    	= "|host_description| - $$this{service_name} - $ds_name";
		
		$this->{rrd}->setPathRRD($ds->{rrd_file});
		$this->create_template();
		$this->create_instance();
		$this->update_input();
		
	}

	$this->{rrd}->setPathRRD($main_rrd);
	$this->{data_template_name}		= $data_template_name;
	$this->{data_template_data_name}	= $data_template_data_name;
	$this->{graph_template_name}            = $graph_template_name;
	$this->{graph_template_graph_title}    	= $graph_template_graph_name;

	Main::log_msg("<-- N2Cacti::Cacti::Graph::create_individual_instance()", "LOG_DEBUG");
}



# -------------------------------------------------------------
sub create_instance {
	my $this        = shift;

	my ($hostid, $gl, $gt, $gtg,$gtg_instance);

	Main::log_msg("--> N2Cacti::Cacti::Graph::create_instance()", "LOG_DEBUG");
	
	# -- recuperation des templates (doivent exister)
	$hostid  = $this->database->get_id("host", { description => $$this{hostname}} );

	if ( not scalar $hostid ) {
		Main::Log_msg("host template not found - check you have put api_cacti script in cacti dir and configure cacti (create a host template and data input method)", "LOG_ERR");
	}
 
	$gt = $this->database->db_fetch_hash("graph_templates", { hash => generate_hash("graph_templates : $$this{graph_template_name}") });
	$gtg = $this->database->db_fetch_hash("graph_templates_graph", { graph_template_id => $gt->{id}, local_graph_id => 0});

	if ( ! defined($gt) or ! defined($gtg) ) {
		Main::log_msg("N2Cacti::Cacti::Graph::create_instance(): cannot fetch db", "LOG_ERR");
	}

	$this->database->begin();
	eval{
		#-- graph_local creating
		if(! $this->database->db_fetch_hash("graph_local", { host_id => $hostid, graph_template_id => $gt->{id}})){
			Main::log_msg("N2Cacti::Cacti::Graph::create_instance(): graph_local creating...", "LOG_DEBUG");
			$gl = $this->database->new_hash("graph_local");
			$gl->{id} = "0";
			$gl->{graph_template_id} = $gt->{id};
			$gl->{host_id} = $hostid;
			$gl->{id} = $this->table_save("graph_local", $gl);
		} else {
			$gl = $this->database->db_fetch_hash("graph_local", { host_id => $hostid, graph_template_id=>$gt->{id}});
		}

		if(! $this->database->item_exist("graph_templates_graph", { graph_template_id => $gt->{id}, local_graph_id => $gl->{id}}) ){
			Main::log_msg("N2Cacti::Cacti::Graph::create_instance(): creation du graph_template_graph", "LOG_DEBUG");
			$gtg->{local_graph_template_graph_id} = $gtg->{id};
			$gtg->{local_graph_id} = $gl->{id};
			$gtg->{title_cache} = $gtg->{title};
			$gtg->{title_cache} =~ s/\|host_description\|/$this->{hostname}/g;
			$gtg->{id} = "0"; 			# -- on veut créer une nouvelle instance
			$gtg->{id} = $this->table_save("graph_templates_graph", $gtg);
		}

		# if this is reached, queries succeeded; commit them
		Main::log_msg("N2Cacti::Cacti::Graph::create_instance(): commit", "LOG_DEBUG");
		$this->database->commit();
	};

	$this->database->rollback() if $@;
	Main::log_msg("N2Cacti::Cacti::Graph::create_instance(): $@", "LOG_ERR") if $@;

	Main::log_msg( "<-- N2Cacti::Cacti::Graph::create_instance()", "LOG_DEBUG");
	# -- copie du graph_templates_graph (instanciation)
	# -- pour chaque datasource : (4 itemps par datasource : libelle, current, average, maximum)
	# -- get sequence (on recupere l'instance du template)
	# -- création du graph_templates_item
	# -- suppression des graph_template_input_defs
	# -- mise a jour de toutes les instances (local_graph_template_id)
}

sub create_template {
	my $this = shift;
	my $gt = {};
	my $i=0;

	Main::log_msg ("--> N2Cacti::Cacti::Graph::create_temlate()", "LOG_DEBUG");

	$this->database->begin();

	eval {
		#-- graph_templates creating
		if (!$this->database->item_exist("graph_templates",{ hash => generate_hash("graph_templates : " . $this->{graph_template_name})} )) {
			
			Main::log_msg ("N2Cacti::Cacti::Graph::create_template(): creation of graph_templates", "LOG_DEBUG");
			$gt		= $this->database->new_hash("graph_templates");
			$gt->{id}	= "0";
			$gt->{hash}	= generate_hash("graph_templates : $$this{graph_template_name}");
			$gt->{name}	= $this->{graph_template_name};
			$gt->{id}	= $this->table_save("graph_templates", $gt);
		} else {
			$gt		= $this->database->db_fetch_hash("graph_templates",{ hash => generate_hash("graph_templates : " . $this->{graph_template_name})} );
		}

		#--  graph_templates_graph creating
		if ( ! $this->database->item_exist("graph_templates_graph", { graph_template_id => $gt->{id}, local_graph_template_graph_id =>0, local_graph_id=>0}) ) {
			
			Main::log_msg("N2Cacti::Cacti::Graph::create_template(): creation graph_templates_graph", "LOG_DEBUG");

			my $gtg									= $this->database->new_hash("graph_templates_graph");
			$gtg->{id}				= "0"; # we want create a new template no one exist
			$gtg->{local_graph_template_graph_id}	= "0"; # it's a template.
			$gtg->{local_graph_id}			= "0";
			$gtg->{t_image_format_id}		= "";
			$gtg->{image_format_id}			= $image_types->{"PNG"};
			$gtg->{t_title}				= "";
			$gtg->{title}				= $this->{graph_template_graph_title};
			$gtg->{title_cache}			= "";
			$gtg->{t_height}			= "";
			$gtg->{height}				= "120"; # fixe
			$gtg->{t_width}				= "";
			$gtg->{width}				= "500"; # fixe
			$gtg->{t_upper_limit}			= "";
			$gtg->{upper_limit}			= "100"; #?? on va recuperer le max de tous les rrd?? 
			$gtg->{t_lower_limit}			= "";
			$gtg->{lower_limit}			= "0";
			$gtg->{t_vertical_label}		= "";
			$gtg->{vertical_label}			= "";
			$gtg->{t_auto_scale}			= "";
			$gtg->{auto_scale}			= "on";
			$gtg->{t_auto_scale_opts}		= "";
			$gtg->{auto_scale_opts}			= "2";
			$gtg->{t_auto_scale_log}		= "";
			$gtg->{auto_scale_log}			= "";
			$gtg->{t_auto_scale_rigid}		= "";
			$gtg->{auto_scale_rigid}		= "";
			$gtg->{t_auto_padding}			= "";
			$gtg->{auto_padding}			= "on";
			$gtg->{t_base_value}			= "";
			$gtg->{base_value}			= "1000";
			$gtg->{t_export}			= "";
			$gtg->{export}				= "on";
			$gtg->{t_unit_value}			= "";
			$gtg->{unit_value}			= "";
			$gtg->{t_unit_exponent_value}		= "";
			$gtg->{unit_exponent_value}		= "";
			$gtg->{graph_template_id}		= $gt->{id};
			$gtg->{id}				= $this->table_save("graph_templates_graph", $gtg);
		}

		# -- mise a jour de toutes les instances
		# soit il n'y avait pas de template ===> on ignore la mise a jour
		# soit il y avait un template et dans ce cas, on a pas grand chose a mettre à jour manuellement donc pour le moment on ignore la mise a jour en série	
	
		# if this is reached, queries succeeded; commit them
		Main::log_msg("N2Cacti::Cacti::Graph::create_template(): commit", "LOG_DEBUG");
		$this->database->commit();
	};
	$this->database->rollback() if $@;
	Main::log_msg("N2Cacti::Cacti::Graph::create_template(): $@", "LOG_ERR") if $@;
	Main::log_msg("<-- N2Cacti::Cacti::Graph::create_template()", "LOG_DEBUG");

}

# select
#		CONCAT_WS('',data_template.name,' - ',' (',data_template_rrd.data_source_name,')') as name,
#		data_template_rrd.id
#		from (data_template_data,data_template_rrd,data_template)
#		where data_template_rrd.data_template_id=data_template.id
#		and data_template_data.data_template_id=data_template.id
#		and data_template_data.local_data_id=0
#		and data_template_rrd.local_data_id=0
#		order by data_template.name,data_template_rrd.data_source_name
sub get_random_color {
	my $this=shift;
	my $init_colors = shift;
	my $id=-1;
	do {
		my @colors= split(',',$$this{graph_item_colors});
		if($init_colors>=0 && $init_colors<scalar(@colors)){
			$id=$colors[$init_colors];
			if(!$this->database->item_exist("colors", { id=> $id})){
				$id=int(rand(100))+4;
			}
		}
		else{
			$id=int(rand(100))+4;
		}
	}
	while(!$this->database->item_exist("colors", { id=> $id}));
	return $id;
}

sub update_input {
	my $this = shift;
	my $state = {};

	Main::log_msg( "--> N2Cacti::Cacti::Graph::update_input()", "LOG_DEBUG");

	my $datasource  = $this->{rrd}->getDataSource();
	my ($hostid, $gl, $gt, $gtg, $gt_input);

	# -- recuperation des templates (doivent exister)
	$hostid = $this->database->get_id("host",{description => $$this{hostname}} );

	if ( not scalar $hostid ) {
		Main::log_msg( "N2Cacti::Cacti::Graph::update_input(): host template not found - check you have put api_cacti script", "LOG_DEBUG");
	}
    
	$gt = $this->database->db_fetch_hash("graph_templates", { hash => generate_hash("graph_templates : $$this{graph_template_name}") });
	$gtg = $this->database->db_fetch_hash("graph_templates_graph", { graph_template_id => $gt->{id}, local_graph_id => 0});

	if ( not defined($gt) or not defined($gtg) ) {
		Main::log_msg( "N2Cacti::Cacti::Graph::update_input(): cannot fetch db", "LOG_ERR");
	}

	$this->database->begin();
	eval{
		Main::log_msg("N2Cacti::Cacti::Graph::update_input(): add, update for each datasource", "LOG_DEBUG");
		my $init_colors = 0;
		# -- add / update des datasource
		while (my ($ds_name,$ds) = each (%$datasource)){
			Main::log_msg("N2Cacti::Cacti::Graph::update_input(): ds.rrd_file=$$ds{rrd_file}", "LOG_DEBUG");
			Main::log_msg("N2Cacti::Cacti::Graph::update_input(): this.rrd.rrd_file=".$this->{rrd}->{rrd_file}, "LOG_DEBUG");
			next if ($ds->{rrd_file} ne $this->{rrd}->{rrd_file});

			my $sequence = $this->database->db_fetch_cell("select max(sequence)+1 as seq from graph_templates_item where graph_template_id=$$gt{id} and local_graph_id=0");
			$sequence = 1 if !defined($sequence);

			Main::log_msg("N2Cacti::Cacti::Graph::update_input(): sequence=$sequence", "LOG_DEBUG");

			my $dtr	= $this->database->db_fetch_hash("data_template_rrd", {hash =>generate_hash($ds->{ds_name}.generate_hash($this->{data_template_name})) });
			my $gti = $this->database->db_fetch_hash("graph_templates_item", {hash =>generate_hash("graph_template_id $$ds{ds_name} sequence $sequence")});
			my $gt_input_hash = generate_hash("graph_template_input : $$ds{ds_name} graph_template_id : $$gt{id}");

			if($this->database->item_exist("graph_template_input", {hash =>$gt_input_hash})){ 
				# items has been define, we dont custom, go to cacti interface
				Main::log_msg("N2Cacti::Graph::update_input(): items has been defined, we dont overridding the parameter", "LOG_DEBUG");
				next;
			}

			Main::log_msg("N2Cacti::Cacti::Graph::update_input(): create input for the ds_name [$$ds{ds_name}]", "LOG_DEBUG");
			$gt_input = $this->database->new_hash("graph_template_input");
			delete($gt_input->{id});
			$gt_input->{hash} = $gt_input_hash;
			$gt_input->{column_name} = "task_item_id";
			$gt_input->{name} = "Data Source [$$ds{ds_name}]";
			$gt_input->{graph_template_id} = $gt->{id};
			$gt_input->{id}	= $this->table_save("graph_template_input", $gt_input);

			# --- ITEM 1 : AVERAGE :
			Main::log_msg("N2Cacti::graph::update_input(): creating ITEM 1", "LOG_DEBUG");
			$gti 					= $this->database->new_hash("graph_templates_item");
			$gti->{id}				= "0";
			$gti->{hash}				= generate_hash("graph_template_id $$ds{ds_name} sequence $sequence");
			$gti->{graph_template_id}		= $gt->{id};
			$gti->{local_graph_id}			= "0";
			$gti->{local_graph_template_item_id}	= "0";
			$gti->{task_item_id}			= $dtr->{id};
			$gti->{color_id}			= $this->get_random_color($init_colors++);
			$gti->{graph_type_id}			= $graph_item_types->{$$this{graph_item_type}};
			$gti->{cdef_id}				= "0"; # pas de cdef definit sinon utilise $cdef_functions
			$gti->{consolidation_function_id}	= $consolidation_functions->{"AVERAGE"};
			$gti->{text_format}			= "$ds_name";
			$gti->{value}				= "";
			$gti->{hard_return}			= "";
			$gti->{gprint_id}			= "2"; # mode d'affichage des nombres?
			$gti->{sequence}			= $sequence++;
			$gti->{id}				= $this->table_save("graph_templates_item", $gti);
			
			my $gti_defs				= $this->database->new_hash("graph_template_input_defs");
			$gti_defs->{graph_template_input_id}	= $gt_input->{id};
			$gti_defs->{graph_template_item_id}	= $gti->{id};

			$this->table_save("graph_template_input_defs", $gti_defs);

			# --- ITEM 2 : Current : 
			Main::log_msg("N2Cacti::Cacti::Graph::update_input(): creating ITEM 2 - Current", "LOG_DEBUG");
			#$gti 					= $this->database->new_hash("graph_templates_item");
			$gti->{id}				= "0";
			$gti->{hash}				= generate_hash("graph_template_id $$ds{ds_name} sequence $sequence");
			$gti->{color_id}			= "0";
			$gti->{graph_type_id}			= $graph_item_types->{"GPRINT"}; 
			$gti->{consolidation_function_id}	= $consolidation_functions->{"LAST"}; 
			$gti->{text_format}			= "Current:";
			$gti->{sequence}			= $sequence++;
			$gti->{id}				= $this->table_save("graph_templates_item", $gti);

			$gti_defs				= $this->database->new_hash("graph_template_input_defs");
			$gti_defs->{graph_template_input_id}	= $gt_input->{id};
			$gti_defs->{graph_template_item_id}	= $gti->{id};

			$this->table_save("graph_template_input_defs", $gti_defs);

			# --- ITEM 3 : Average :
			Main::log_msg( "N2Cacti::graph::update_input(): creating ITEM 3 - Average", "LOG_DEBUG");
		
			#		$gti	                            = $this->database->new_hash("graph_templates_item");
			$gti->{id}				= "0";
			$gti->{hash}				= generate_hash("graph_template_id $$ds{ds_name} sequence $sequence");
			$gti->{consolidation_function_id}	= $consolidation_functions->{"AVERAGE"};
			$gti->{text_format}			= "Average:";
			$gti->{sequence}			= $sequence++;
			$gti->{id}				= $this->table_save("graph_templates_item", $gti);

			$gti_defs				= $this->database->new_hash("graph_template_input_defs");
			$gti_defs->{graph_template_input_id}	= $gt_input->{id};
			$gti_defs->{graph_template_item_id}	= $gti->{id};
			$this->table_save("graph_template_input_defs", $gti_defs);

			# --- ITEM 4 :

			Main::log_msg( "N2Cacti::graph::update_input(): creating ITEM 4 - Maximum", "LOG_DEBUG");
			#$gti					= $this->database->new_hash("graph_templates_item");
			$gti->{id}				= "0";
			$gti->{hash}				= generate_hash("graph_template_id $$ds{ds_name} sequence $sequence");
			$gti->{consolidation_function_id}	= $consolidation_functions->{"MAX"};	                                        
			$gti->{text_format}			= "Maximum:";                                                                   
			$gti->{sequence}			= $sequence++;
			$gti->{hard_return}			= "on";
			$gti->{id}				= $this->table_save("graph_templates_item", $gti);

			$gti_defs				= $this->database->new_hash("graph_template_input_defs");
			$gti_defs->{graph_template_input_id}	= $gt_input->{id};
			$gti_defs->{graph_template_item_id}	= $gti->{id};
			$this->table_save("graph_template_input_defs", $gti_defs);

			Main::log_msg("N2Cacti::Cacti::Graph::update_input(): commit", "LOG_DEBUG");
			# if this is reached, queries succeeded; commit them
			$this->database->commit();
			$this->database->begin();

			# -- pour chaque datasource : (plusieurs items par datasource : libelle, current, average, maximum)
			# -- création d'un graph_template_input (un seul par datasource)
			# -- création du graph_templates_item
			# -- suppression des graph_template_input_defs
			# -- mise a jour de toutes les instances (local_graph_template_id)
		}

		my $dt = $this->database->db_fetch_hash("data_template", { hash => generate_hash($this->{data_template_name}) });
		my $dl;

		if ( $this->database->item_exist( "data_local", { host_id => $hostid, data_template_id=>$dt->{id}} ) == 1 ) {
			$dl = $this->database->db_fetch_hash( "data_local", { host_id => $hostid, data_template_id=>$dt->{id} } );
		} else {
                        $dl->{id} = "0";
                        $dl->{host_id} = $hostid; 
                        $dl->{data_template_id} = $dt->{id};
                        $dl->{id} = $this->table_save("data_local", $dl);
		}
            
		# -- creation des instances
		if ( $this->database->item_exist( "graph_local", { host_id => $hostid, graph_template_id=>$gt->{id}} ) ) {
			Main::log_msg("N2Cacti::Cacti::Graph::update_input(): instances' creation", "LOG_DEBUG");
			$gl = $this->database->db_fetch_hash("graph_local", { host_id => $hostid, graph_template_id=>$gt->{id}});

			my $task_item_id = 0;
			my $dtr_instance = {};
			my $sth = $this->database->execute("SELECT * FROM graph_templates_item WHERE graph_template_id=$$gt{id} AND local_graph_id=0");

			while(my $gti = $sth->fetchrow_hashref()){
				if($task_item_id != $gti->{task_item_id}){
					# we get the instance of data_template_rrd (datasource) for the task_item_id
					$dtr_instance = $this->database->db_fetch_hash("data_template_rrd", { hash => "", local_data_template_rrd_id => $gti->{task_item_id}, local_data_id => $dl->{id}, data_template_id => $dt->{id} });
					Main::log_msg("N2Cacti::Cacti::Graph::update_input(): $$gti{task_item_id}:$$dl{id}:$$dt{id}", "LOG_DEBUG");
					$task_item_id = $gti->{task_item_id};
				}
				Main::log_msg("N2Cacti::Cacti::Graph::update_input(): getting instance", "LOG_DEBUG");

				if (!$this->database->item_exist("graph_templates_item",{ local_graph_template_item_id => $gti->{id}, local_graph_id => $gl->{id}, task_item_id => $dtr_instance->{id} || "0", sequence => $gti->{sequence}})){
					$gti->{local_graph_template_item_id}	= $gti->{id};
					$gti->{local_graph_id}			= $gl->{id};
					$gti->{id}				= "0";
					$gti->{hash}				= "";
					$gti->{task_item_id}			= $dtr_instance->{id} || "0";
					$gti->{id}= $this->table_save("graph_templates_item", $gti);
				}
			}
		}	

		Main::log_msg( "N2Cacti::Cacti::Graph::update_input(): commit", "LOG_DEBUG");
		# if this is reached, queries succeeded; commit them
		$this->database->commit();
	};

	$this->database->rollback() if $@;
	Main::log_msg("<-- N2Cacti::Cacti::Graph::update_input()", "LOG_DEBUG");
}

1;

