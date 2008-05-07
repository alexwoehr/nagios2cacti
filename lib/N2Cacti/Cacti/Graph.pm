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
use Error qw(:try);

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
        tables                              => $tables,
        hostname                            => $param{hostname},
        service_description                 => $param{service_description},
        graph_item_type						=> $param{graph_item_type} || "AREA",
		rrd									=> $param{rrd}, # rrd provide template, datasource and path_rrd now!
		source								=> $param{source} || "Nagios",
		log_msg								=> $param{cb_log_msg}			|| \&default_log_msg,
		graph_item_colors					=> $param{graph_item_colors} || "",
        };

	$this->{template}						= $this->{rrd}->getTemplate();
	$this->{service_name}					= $this->{rrd}->getServiceName();

	# need to find the data_template_rrd...
	$this->{data_template_name}				= "$$this{source} - $$this{service_name}";
	$this->{data_template_data_name}		= "|host_description| - $$this{service_name}";


    $this->{graph_template_name}            = "$$this{source} - $$this{service_name}";
    $this->{graph_template_graph_title}    	= "|host_description| - $$this{service_name}";

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

sub table_save {
	my $this = shift;
	my $tablename=shift;
	if(defined($this->{tables}->{$tablename})){
		return $this->database->sql_save(shift ,$tablename);
	}
	die "N2Cacti::Graph::table_save - wrong parameter tablename value : $tablename";
}

# -------------------------------------------------------------



#-- create individual template and instance for each couple (service_name, datasource) not in main datasource
sub create_individual_instance {
	my $this		= shift;
	my $debug 		= shift ||0;
	my $main_rrd	= $this->{rrd}->getPathRRD();

	$this->log_msg("-->N2Cacti::Graph::create_individual_instance();") if $debug;
	# need to find the data_template_rrd...		
	my $data_template_name	= $this->{data_template_name};
	my $data_template_data_name	= $this->{data_template_data_name};
	my $graph_template_name	= $this->{graph_template_name};
	my $graph_template_graph_name	= $this->{graph_template_graph_name};
	
	my $datasource = $this->{rrd}->{datasource};
	while (my ($ds_name, $ds) = each (%$datasource)){
		next if ($main_rrd eq $ds->{rrd_file});
		$this->{data_template_name}				= "$this->{source} - $$this{service_name} - $ds_name";
		$this->{data_template_data_name}		= "|host_description| - $$this{service_name} - $ds_name";
		$this->{graph_template_name}            = "$$this{source} - $$this{service_name} - $ds_name";
		$this->{graph_template_graph_title}    	= "|host_description| - $$this{service_name} - $ds_name";
		
		$this->{rrd}->setPathRRD($ds->{rrd_file});
		$this->create_template($debug);
		$this->create_instance($debug);
		$this->update_input($debug);
		
	}
	$this->{rrd}->setPathRRD($main_rrd);
	$this->{data_template_name}				= $data_template_name;
	$this->{data_template_data_name}		= $data_template_data_name;
	$this->{graph_template_name}            = $graph_template_name;
	$this->{graph_template_graph_title}    	= $graph_template_graph_name;
	$this->log_msg("<--N2Cacti::Graph::create_individual_instance();") if $debug;
}



# -------------------------------------------------------------
sub create_instance {
    my $this        = shift;
    my $debug       = shift ||0;
	my ($hostid, $gl, $gt, $gtg,$gtg_instance);
	$this->log_msg("-->N2Cacti::Graph::create_instance();") if $debug;
	
    # -- recuperation des templates (doivent exister)
    try {
	    $hostid              = $this->database->get_id("host", {
				description => $$this{hostname}} );
	}
	catch Error::Simple with{
    	die "host template not found - check you have put api_cacti script".
    		" in cacti dir and configure cacti (create a host template and data input method)";
    };
    
    try {
		$gt                  = $this->database->db_fetch_hash("graph_templates", { 
			hash => generate_hash("graph_templates : $$this{graph_template_name}") });
		$gtg                 = $this->database->db_fetch_hash("graph_templates_graph", { 
			graph_template_id => $gt->{id}, 
			local_graph_id => 0});

    	}
	catch  Error::Simple with{
		$_ =~ /DATABASE - NO RESULT/ and $this->log_msg("ERROR : $_ : ") and die "ERROR : $_";
	};
    
    
	$this->database->begin();
	eval{
		#-- graph_local creating
		if(! $this->database->db_fetch_hash("graph_local", { 
			host_id => $hostid, 
			graph_template_id => $gt->{id}})){
			
			$this->log_msg(__LINE__."\t:graph_local creating...") if $debug;
			$gl 						= $this->database->new_hash("graph_local");
			$gl->{id}					= "0";
			$gl->{graph_template_id}	= $gt->{id};
			$gl->{host_id}				= $hostid;
			$gl->{id}					= $this->table_save("graph_local", $gl);
		}
		else{
			$gl                  = $this->database->db_fetch_hash("graph_local", { 
				host_id => $hostid, 
				graph_template_id=>$gt->{id}});
		}
		
		if(! $this->database->item_exist("graph_templates_graph", { 
				graph_template_id => $gt->{id}, 
				local_graph_id => $gl->{id}}) ){
			$this->log_msg(__LINE__."\t:creation du graph_template_graph") if $debug;
			$gtg->{local_graph_template_graph_id}	= $gtg->{id};
			$gtg->{local_graph_id}					= $gl->{id};
			$gtg->{title_cache}						= $gtg->{title};
			$gtg->{title_cache}						=~ s/\|host_description\|/$this->{hostname}/g;
			$gtg->{id}								= "0"; 			# -- on veut créer une nouvelle instance
			$gtg->{id}								= $this->table_save("graph_templates_graph", $gtg);
		}

        # if this is reached, queries succeeded; commit them
        $this->log_msg(__LINE__."\t:commit") if $debug;
        $this->database->commit();
    };
    $this->database->rollback() if $@;
    $this->log_msg(__LINE__."\t:$@") if $@;

	
	$this->log_msg( "<--N2Cacti::Graph::create_instance();") if $debug;
	# -- copie du graph_templates_graph (instanciation)
	# -- pour chaque datasource : (4 itemps par datasource : libelle, current, average, maximum)
		# -- get sequence (on recupere l'instance du template)
		# -- création du graph_templates_item
		# -- suppression des graph_template_input_defs
		# -- mise a jour de toutes les instances (local_graph_template_id)
}

sub create_template {
	my $this = shift;
    my $debug       = shift ||0;
	my $gt = {};
	my $i=0;

	$this->log_msg ("-->N2Cacti::Graph::create_temlate();") if $debug;

	$this->database->begin();

	eval {
		#-- graph_templates creating
		if (!$this->database->item_exist("graph_templates",{
			hash=>generate_hash("graph_templates : " . $this->{graph_template_name})})){
			
			$this->log_msg ("\tcreation graph_templates") if $debug;
			$gt									= $this->database->new_hash("graph_templates");
			$gt->{id}							= "0";
			$gt->{hash}							= generate_hash("graph_templates : $$this{graph_template_name}");
			$gt->{name}							= $this->{graph_template_name};
			$gt->{id}							= $this->table_save("graph_templates", $gt);
		}
		else {
			$gt									= $this->database->db_fetch_hash("graph_templates",{
				hash=>generate_hash("graph_templates : " . $this->{graph_template_name})});
		}

		#--  graph_templates_graph creating
		if (!$this->database->item_exist("graph_templates_graph", { 
			graph_template_id => $gt->{id}, 
			local_graph_template_graph_id =>0, 
			local_graph_id=>0})){
			
			$this->log_msg(__LINE__."\t:creation graph_templates_graph") if $debug;
			my $gtg									= $this->database->new_hash("graph_templates_graph");
			$gtg->{id}								= "0"; # we want create a new template no one exist
			$gtg->{local_graph_template_graph_id}	= "0"; # it's a template.
			$gtg->{local_graph_id}					= "0";
			$gtg->{t_image_format_id}				= "";
			$gtg->{image_format_id}					= $image_types->{"PNG"};
			$gtg->{t_title}							= "";
			$gtg->{title}							= $this->{graph_template_graph_title};
			$gtg->{title_cache}						= "";
			$gtg->{t_height}						= "";
			$gtg->{height}							= "120"; # fixe
			$gtg->{t_width}							= "";
			$gtg->{width}							= "500"; # fixe
			$gtg->{t_upper_limit}					= "";
			$gtg->{upper_limit}						= "100"; #?? on va recuperer le max de tous les rrd?? 
			$gtg->{t_lower_limit}					= "";
			$gtg->{lower_limit}						= "0";
			$gtg->{t_vertical_label}				= "";
			$gtg->{vertical_label}					= "";
			$gtg->{t_auto_scale}					= "";
			$gtg->{auto_scale}						= "on";
			$gtg->{t_auto_scale_opts}				= "";
			$gtg->{auto_scale_opts}					= "2";
			$gtg->{t_auto_scale_log}				= "";
			$gtg->{auto_scale_log}					= "";
			$gtg->{t_auto_scale_rigid}				= "";
			$gtg->{auto_scale_rigid}				= "";
			$gtg->{t_auto_padding}					= "";
			$gtg->{auto_padding}					= "on";
			$gtg->{t_base_value}					= "";
			$gtg->{base_value}						= "1000";
			$gtg->{t_export}						= "";
			$gtg->{export}							= "on";
			$gtg->{t_unit_value}					= "";
			$gtg->{unit_value}						= "";
			$gtg->{t_unit_exponent_value}			= "";
			$gtg->{unit_exponent_value}				= "";
			$gtg->{graph_template_id}				= $gt->{id};
			$gtg->{id}								= $this->table_save("graph_templates_graph", $gtg);
		}

		# -- mise à jour de toutes les instances
		# soit il n'y avait pas de template ===> on ignore la mise a jour
		# soit il y avait un template et dans ce cas, on a pas grand chose a mettre à jour manuellement donc pour le moment on ignore la mise a jour en série	
	
		# if this is reached, queries succeeded; commit them
		$this->log_msg(__LINE__."\t:commit") if $debug;
		$this->database->commit();
	};
	$this->database->rollback() if $@;
	$this->log_msg(__LINE__."\t:$@") if $@;
	$this->log_msg("<--N2Cacti::Graph::create_temlate();") if $debug;

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
sub get_random_color{

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
   	my $this        = shift;
    my $debug       = shift ||0;
    my $state		= {};
   	$this->log_msg( "-->N2Cacti::Graph::update_input();") if $debug;
    my $datasource  = $this->{rrd}->getDataSource();
    my ($hostid, $gl, $gt, $gtg, $gt_input);


    # -- recuperation des templates (doivent exister)
    try {
	    $hostid              = $this->database->get_id("host",{
				description => $$this{hostname}} );
	}
	catch  Error::Simple with{
    	die "host template not found - check you have put api_cacti script".
    		" in cacti dir and configure cacti (create a host template and data input method)";
    };
    
    try {
		$gt                  = $this->database->db_fetch_hash("graph_templates", { 
			hash => generate_hash("graph_templates : $$this{graph_template_name}") });
			
		$gtg                 = $this->database->db_fetch_hash("graph_templates_graph", { 
			graph_template_id => $gt->{id}, 
			local_graph_id => 0});
			


    	}
	catch  Error::Simple with{
		$_ =~ /DATABASE - NO RESULT/ and $this->log_msg("ERROR : $_ : ") and die "ERROR : $_";
	};
    
  
 	

	$this->database->begin();
    eval{
		$this->log_msg(__LINE__."\t:add, update for each datasource") if $debug;
		my $init_colors=0;
    	# -- add / update des datasource
    	while (my ($ds_name,$ds) = each (%$datasource)){
    		$this->log_msg(__LINE__."\t:ds.rrd_file=$$ds{rrd_file}") if $debug;
    		$this->log_msg(__LINE__."\t:this.rrd.rrd_file=".$this->{rrd}->{rrd_file}) if $debug;
			next if ($ds->{rrd_file} ne $this->{rrd}->{rrd_file});
    		
			my $sequence 		= $this->database->db_fetch_cell("select max(sequence)+1 as seq 
				from graph_templates_item 
				where graph_template_id=$$gt{id} and local_graph_id=0");
			$sequence = 1 if !defined($sequence);
			$this->log_msg(__LINE__."\t:sequence=$sequence") if $debug;
			my $dtr				= $this->database->db_fetch_hash("data_template_rrd", {hash =>generate_hash($ds->{ds_name}.generate_hash($this->{data_template_name})) });
			my $gti 			= $this->database->db_fetch_hash("graph_templates_item", {hash =>generate_hash("graph_template_id $$ds{ds_name} sequence $sequence")});
			my $gt_input_hash 	= generate_hash("graph_template_input : $$ds{ds_name} graph_template_id : $$gt{id}");
			
			if($this->database->item_exist("graph_template_input", {hash =>$gt_input_hash})){ 
				# items has been define, we dont custom, go to cacti interface
				$this->log_msg("items has been define, we dont overridding the parameter") if $debug;
				next;
			}
			
			$this->log_msg(__LINE__."\t:create input for the ds_name [$$ds{ds_name}]") if $debug;
			$gt_input							= $this->database->new_hash("graph_template_input");
			delete($gt_input->{id});
			$gt_input->{hash}					= $gt_input_hash;
			$gt_input->{column_name}			= "task_item_id";
			$gt_input->{name}					= "Data Source [$$ds{ds_name}]";
			$gt_input->{graph_template_id}		= $gt->{id};
			$gt_input->{id}						= $this->table_save("graph_template_input", $gt_input);
			
			# --- ITEM 1 : AVERAGE :
			$this->log_msg( "\tcreating ITEM 1") if $debug;
			$gti 								= $this->database->new_hash("graph_templates_item");
			$gti->{id}							= "0";
			$gti->{hash}						= generate_hash("graph_template_id $$ds{ds_name} sequence $sequence");
			$gti->{graph_template_id}			= $gt->{id};
			$gti->{local_graph_id}				= "0";
			$gti->{local_graph_template_item_id}= "0";
			$gti->{task_item_id}				= $dtr->{id};
			$gti->{color_id}					= $this->get_random_color($init_colors++);
			$gti->{graph_type_id}				= $graph_item_types->{$$this{graph_item_type}};
			$gti->{cdef_id}						= "0"; # pas de cdef definit sinon utilise $cdef_functions
			$gti->{consolidation_function_id}	= $consolidation_functions->{"AVERAGE"};
			$gti->{text_format}					= "$ds_name";
			$gti->{value}						= "";
			$gti->{hard_return}					= "";
			$gti->{gprint_id}					= "2"; # mode d'affichage des nombres?
			$gti->{sequence}					= $sequence++;
			$gti->{id}							= $this->table_save("graph_templates_item", $gti);
			
			my $gti_defs						= $this->database->new_hash("graph_template_input_defs");
			$gti_defs->{graph_template_input_id}= $gt_input->{id};
			$gti_defs->{graph_template_item_id}	= $gti->{id};
			$this->table_save("graph_template_input_defs", $gti_defs);

			# --- ITEM 2 : Current : 
			$this->log_msg(__LINE__."\t:ccreating ITEM 2 - Current") if $debug;
			#$gti 								= $this->database->new_hash("graph_templates_item");
			$gti->{id}							= "0";
			$gti->{hash}						= generate_hash("graph_template_id $$ds{ds_name} sequence $sequence");
			$gti->{color_id}					= "0";																			
			$gti->{graph_type_id}				= $graph_item_types->{"GPRINT"}; 												
			$gti->{consolidation_function_id}	= $consolidation_functions->{"LAST"}; 										
			$gti->{text_format}					= "Current:";																	
			$gti->{sequence}					= $sequence++;
			$gti->{id}							= $this->table_save("graph_templates_item", $gti);

            $gti_defs                           = $this->database->new_hash("graph_template_input_defs");
            $gti_defs->{graph_template_input_id}= $gt_input->{id};
            $gti_defs->{graph_template_item_id} = $gti->{id};
			$this->table_save("graph_template_input_defs", $gti_defs);

			# --- ITEM 3 : Average :
			$this->log_msg( "\tcreating ITEM 3 - Average") if $debug;
		
	#		$gti	                            = $this->database->new_hash("graph_templates_item");
            $gti->{id}                          = "0";
            $gti->{hash}                        = generate_hash("graph_template_id $$ds{ds_name} sequence $sequence");
            $gti->{consolidation_function_id}   = $consolidation_functions->{"AVERAGE"};										
            $gti->{text_format}                 = "Average:";																	
            $gti->{sequence}                    = $sequence++;
            $gti->{id}                          = $this->table_save("graph_templates_item", $gti);

            $gti_defs                           = $this->database->new_hash("graph_template_input_defs");
            $gti_defs->{graph_template_input_id}= $gt_input->{id};
            $gti_defs->{graph_template_item_id} = $gti->{id};
			$this->table_save("graph_template_input_defs", $gti_defs);

			# --- ITEM 4 : 

			$this->log_msg( "\tcreating ITEM 4 - Maximum") if $debug;
     #       $gti                                = $this->database->new_hash("graph_templates_item");
            $gti->{id}                          = "0";
            $gti->{hash}                        = generate_hash("graph_template_id $$ds{ds_name} sequence $sequence");
            $gti->{consolidation_function_id}   = $consolidation_functions->{"MAX"};	                                        
            $gti->{text_format}                 = "Maximum:";                                                                   
            $gti->{sequence}                    = $sequence++;
			$gti->{hard_return}					= "on";
            $gti->{id}                          = $this->table_save("graph_templates_item", $gti);

            $gti_defs                           = $this->database->new_hash("graph_template_input_defs");
            $gti_defs->{graph_template_input_id}= $gt_input->{id};
            $gti_defs->{graph_template_item_id} = $gti->{id};
			$this->table_save("graph_template_input_defs", $gti_defs);

			$this->log_msg(__LINE__."\t:commit") if $debug;
	        # if this is reached, queries succeeded; commit them
		    $this->database->commit();
		    $this->database->begin();


	    # -- pour chaque datasource : (plusieurs items par datasource : libelle, current, average, maximum)
	        # -- création d'un graph_template_input (un seul par datasource)
        	# -- création du graph_templates_item
	        # -- suppression des graph_template_input_defs
    	    # -- mise a jour de toutes les instances (local_graph_template_id)
		}
		
		
	    my $dt                  = $this->database->db_fetch_hash("data_template", { hash => generate_hash($this->{data_template_name}) });
		my $dl                  = $this->database->db_fetch_hash("data_local", { host_id => $hostid, data_template_id=>$dt->{id}});
            
		# -- creation des instances
		if($this->database->item_exist("graph_local", { 
				host_id => $hostid, 
				graph_template_id=>$gt->{id}})){
					
;
			$this->log_msg(__LINE__."\t:creation des instances") if $debug;
			$gl = $this->database->db_fetch_hash("graph_local", { 
				host_id => $hostid, 
				graph_template_id=>$gt->{id}});

			my $task_item_id=0;
			my $dtr_instance={};
			my $sth = $this->database->execute("SELECT * FROM graph_templates_item WHERE graph_template_id=$$gt{id} AND local_graph_id=0");


			while(my $gti = $sth->fetchrow_hashref()){
				if($task_item_id != $gti->{task_item_id}){
					# we get the instance of data_template_rrd (datasource) for the task_item_id
					$dtr_instance        = $this->database->db_fetch_hash("data_template_rrd", {
						hash 						=> "", 
						local_data_template_rrd_id	=> $gti->{task_item_id}, 
						local_data_id				=> $dl->{id}, 
						data_template_id			=> $dt->{id} });
					$this->log_msg( "$$gti{task_item_id}:$$dl{id}:$$dt{id}") if $debug;
					$task_item_id = $gti->{task_item_id};
				}
				$this->log_msg( "\trecuperation de l'instance") if $debug;
		
				if (!$this->database->item_exist("graph_templates_item",{
					local_graph_template_item_id 	=> $gti->{id},
					local_graph_id 					=> $gl->{id},
					task_item_id					=> $dtr_instance->{id} || "0",  #BUG HERE
					sequence						=> $gti->{sequence}})){
					
					$gti->{local_graph_template_item_id}= $gti->{id};
		    	    $gti->{local_graph_id}              = $gl->{id};
		        	$gti->{id}                          = "0";
			        $gti->{hash}                        = "";
					$gti->{task_item_id}                = $dtr_instance->{id} || "0";

			        $gti->{id}                          = $this->table_save("graph_templates_item", $gti);
    	        }
			}
		}	
		$this->log_msg( "\tcommit") if $debug;
        # if this is reached, queries succeeded; commit them
	    $this->database->commit();
    };
    $this->database->rollback() if $@;
	$this->log_msg("<--N2Cacti::Graph::update_input();") if $debug;
}

1;
