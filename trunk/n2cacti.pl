#!/usr/bin/perl
#############################################################################
###                                                                         #
### n2cacti.pl                                                              #
### Written by <detrak@caere.fr>                                            #
###                                                                         #
### This program is free software; you can redistribute it and/or modify it #
### under the terms of the GNU General Public License as published by the   #
### Free Software Foundation; either version 2, or (at your option) any     #
### later version.                                                          #
###                                                                         #
### This program is distributed in the hope that it will be useful, but     #
### WITHOUT ANY WARRANTY; without even the implied warranty of              #
### MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU       #
### General Public License for more details.                                #
###                                                                         #
#############################################################################
#


use strict;

use lib qw(./lib ../lib /usr/lib/N2Cacti/lib);
use Getopt::Std;
use Nagios::Object;
use Nagios::Config;
use N2Cacti::Config;
use N2Cacti::Cacti;
use N2Cacti::Cacti::Data;
use N2Cacti::Cacti::Graph;
use N2Cacti::Cacti::Host;
use N2Cacti::RRD;
use File::Copy;
my $version = "0.2";

sub usage();

#
# Do not buffer writes
$| = 1;

my $opt      = {};
getopts( "tmuhsdc:i:", $opt );
usage() if($opt->{u});
#my $cacti = new N2Cacti::Cacti($opt->{c});

my $debug = defined($opt->{d});
my $config = get_config($opt->{c});
my $nagios_config = Nagios::Config->new( Filename => $config->{NAGIOS_CONF_DIR}."/nagios.cfg", Version => 2 );
set_process_name($0);


sub addHost {
	my $nagios 	= shift;
	my $debug	= shift ||0;
	my $hosts 	= $nagios->all_objects_for_type("Nagios::Host");
    if (scalar(@$hosts) == 0) {
        log_msg("No hosts have yet been defined\n") if $debug;
    } else {
        foreach my $host (@$hosts) {
			my $hostname = $host->host_name;
			if($hostname){
				
				my $address = $host->address;
				my $host = new N2Cacti::Cacti::Host({
				        hostname            => $hostname,
				        hostaddress 		=> $address,
						});
				$host->create_host();
			
				log_msg("create_host($hostname,$address)") if $debug;

			}
        }
    }
}

sub addService {
	my $nagios = shift;
	my $config = shift;
	my $migrate = shift ||0;
    my $services = $nagios->all_objects_for_type("Nagios::Service");
    if (scalar(@$services) == 0) {
        print "No services have yet been defined\n";
    } else {
        foreach my $service (@$services) {
			my %hosts=();
			if($service->register){

				# --- enumeration des host attacher au service
				foreach my $item ($service->host_name){
					foreach my $host (@$item){
						$hosts{$host->name."_".$host->address}={
							hostname	=> $host->name, 
							hostaddress => $host->address};
					}
				}

				# --- enumeration des groupes d'hotes
				foreach my $item ($service->hostgroup_name){
					foreach my $groups (@$item){
						
						foreach my $item2 ($groups->members){
							foreach my $host (@$item2){
								$hosts{$host->name."_".$host->address}={
									hostname	=> $host->name, 
									hostaddress => $host->address};
							}
						}
					}
				}

				# --- on recupere le chemin de tous les fichiers RRD 
				while( my ($key,$value) = each (%hosts)){
					my $hostname = $value->{hostname};
					my $hostaddress = $value->{hostaddress};
					my $rrd		= new N2Cacti::RRD({
						service_description => $service->name, 
						hostname			=> $hostname,
						debug				=> $debug,
						cb_log_msg			=> \&log_msg,
						with_mysql			=> 0, #-- we dont use mysql support in n2cacti
						});

					log_msg "skip ".$service->name and next  if( !$rrd->validate());

					if (defined ($$opt{m})){ #}
						if( -f $rrd->{rrd_file_older} && ($rrd->{rrd_file_older} ne $rrd->{rrd_file})){
							move($rrd->{rrd_file_older},$rrd->{rrd_file});
							log_msg "moving file \t$$rrd{rrd_file_older}\n to \t$$rrd{rrd_file}\n";
						}
						elsif($rrd->{rrd_file_older} eq $rrd->{rrd_file}){
							log_msg "$$rrd{rrd_file} : name is correct";
						}
						else{
							log_msg "$$rrd{rrd_file_older} : file not exist, will create one";
						}
					}
					
					#-- create data_template and instanciate it!
					my $data_template = new N2Cacti::Cacti::Data({
				        hostname            => $hostname,
				       	hostaddress			=> $hostaddress,
				        service_description => $service->name,
				        rrd					=> $rrd,
						});
					$data_template->create_instance($debug);
					$data_template->update_rrd($debug);
					$data_template->create_individual_instance($debug);
											
					#-- create graph_template and instanciate it!
					my $graph_template = new N2Cacti::Cacti::Graph({
                        hostname            => $hostname,
				       	hostaddress			=> $hostaddress,
                        service_description => $service->name,
                        graph_item_type		=> $config->{GRAPH_ITEM_TYPE},
                        graph_item_colors	=> $config->{GRAPH_ITEM_COLORS},
                        rrd					=> $rrd,
						});
					$graph_template->create_template($debug);
					$graph_template->create_instance($debug);
					$graph_template->update_input($debug);
					$graph_template->create_individual_instance($debug);
				}
			}
        }
    }
}


addHost($nagios_config,$debug) if ($opt->{h});
addService($nagios_config,$config) if($opt->{s});

#
# Fonction diverse (usage, config...)
# 


sub usage () {
	print "plugin.pl
    -u      print usage and exit
    -c <path>/config-file-name
            n2rrd.conf in case you want to overide default values
	-t		template only (dont bind template with host instance)
	-i		instance of nagios (if you have multiple nagios running)
    -s      process service
    -h      process host
    -d      debug mode
	-m		migrate rrd database
            pass following nagios 2.x variables as option, 1.x may differ\n\n";
	exit 0;
}



