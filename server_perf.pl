#!/usr/bin/perl
############################################################################
##                                                                         #
## perf2rrd.pl                                                             #
## Written by <detrak@caere.fr>                                            #
##                                                                         #
## This program is free software; you can redistribute it and/or modify it #
## under the terms of the GNU General Public License as published by the   #
## Free Software Foundation; either version 2, or (at your option) any     #
## later version.                                                          #
##                                                                         #
## This program is distributed in the hope that it will be useful, but     #
## WITHOUT ANY WARRANTY; without even the implied warranty of              #
## MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU       #
## General Public License for more details.                                #
##                                                                         #
############################################################################
#

use strict;



#-- Class to handle socket exception
package Error::Socket;
use base 'Error::Simple';
1;

package Error::File;
use base 'Error::Simple';
1;

package main;
use Cwd;
use Cwd 'abs_path';
my $chdir=abs_path($0);
$chdir =~ s/\/[^\/]+$//g;
chdir($chdir);
use lib qw(. ./lib /usr/lib/N2Cacti/lib);

use Error qw(:try);

use IO::Socket;
use RRDs;
use Getopt::Std;
use Fcntl;             # for sysopen
use POSIX;
use File::Copy;
use DBI;
use N2Cacti::Config;
use N2Cacti::database; #version generique database (sqlserver/mysql)
use N2Cacti::Time;
use N2Cacti::Archive;
use N2Cacti::Cacti;
use N2Cacti::Cacti::Data;
use N2Cacti::Cacti::Graph;
use N2Cacti::Cacti::Host;
use N2Cacti::RRD;
use Net::Server::Daemonize qw(daemonize);
use Error qw(:try);
use IO::Handle;
use IO::File;
use Digest::MD5 qw(md5 md5_hex md5_base64);

use constant {
	SVC_SERVICEDESC				=>	1,
	SVC_HOSTNAME				=>	2,
	SVC_HOSTADDRESS				=>	3,
	SVC_TIMET					=>	4,
	SVC_SERVICEEXECUTIONTIME	=>	5,
	SVC_SERVICELATENCY			=>	6,
	SVC_SERVICESTATE			=>	7,
	SVC_SERVICEOUTPUT			=>	8,
	SVC_SERVICEPERFDATA			=>	9,
    HST_HOSTNAME                =>  1,
    HST_HOSTADDRESS             =>  2,
    HST_TIMET                   =>  3,
    HST_HOSTEXECUTIONTIME       =>  4,
    HST_HOSTSTATE               =>  5,
    HST_HOSTOUTPUT              =>  6,
    HST_HOSTPERFDATA            =>  7,
	};

	
	
# Do not buffer writes
$| = 1;
# -- initiatilisation
my $opt      = {};
my $rrderror = "";
getopts( "f:mvduc:p:s:", $opt );
usage() if (defined($opt->{h}));

#load_config($opt->{c}) if $opt->{c};	
my $config = get_config($opt->{c});
set_process_name($0);


main();

	

sub main {
	my $debug 	= 0;
	$debug 		= 1 if (defined($opt->{v}));
	daemonize('nagios','nagios',"$$config{PID_FILE}") if (defined($opt->{d}));

	# define the archive mode
	my $archive = new N2Cacti::Archive({
		archive_dir	=> $$config{ARCHIVE_DIR},
		rotation	=> $$config{ROTATION},
		basename	=> "perfdata.dat",
		log_msg		=> \&log_msg,
		});

	unless (-p $$config{SERVICE_PERFDATA_PIPE}){
	    if (-e  $$config{SERVICE_PERFDATA_PIPE}) {        # but a something else
        	die "$0: won't overwrite .signature\n";
    	}
		else {
        	POSIX::mkfifo($$config{SERVICE_PERFDATA_PIPE}, 0666) or die "can't mknod $$config{SERVICE_PERFDATA_PIPE}: $!";
        	warn "$0: created $$config{SERVICE_PERFDATA_PIPE} as a named pipe\n";
		}
	}

	my $base_rrd = {};
	# -- infinite loop !
	while (1) {
		try {
	
			my ($io,$line);
	        # exit if signature file manually removed
	        if(!defined($opt->{f})&&!defined($$opt{s}) && !defined($$opt{p})){
	            throw Error::File("Pipe file disappeared") unless -p $$config{SERVICE_PERFDATA_PIPE};
	            # next line blocks until there's a reader
				$io = new IO::File ($$config{SERVICE_PERFDATA_PIPE}, "r");
	        }
	        elsif(defined($$opt{f})){
	            throw Error::File("File disappeared")  unless -f $$opt{f};
				$io = new IO::File ($$opt{f}, "r");
	        }
			elsif(defined($$opt{s})){
				unlink($$opt{s});
				log_msg("creating socket file : $$opt{s}") if $debug;
				$io = IO::Socket::UNIX->new(HostPath => $$opt{s}, Type => SOCK_DGRAM, Listen => 5)
					or throw Error::Socket( "socket: $@");
				select(undef,undef,undef,5);
				log_msg("socket created") if $debug;
			}
			elsif(defined($$opt{p})){
				log_msg( "create socket udp $$opt{p}" ) if $debug;
				$io = IO::Socket::INET->new(LocalPort => $$opt{p}, Proto => 'udp')
	    			or throw Error::Socket( "socket: $@");
				log_msg("socket created") if $debug;
			}
	

			while ($io->recv($line,16384)){
#			while (<$io>){
#				my $line=$_;
				my $hash=md5_hex($line);

				#-- return the md5 line
				if(defined($$opt{s}) ||defined($$opt{p})){
					my($port, $ipaddr) = sockaddr_in($io->peername);
   					my $hishost = gethostbyaddr($ipaddr, AF_INET);
   					#print "Client ".$io->PeerAddr." send '$line'\n" if $debug;
					log_msg("$hishost: $hash") if $debug;
					$io->send("$hash") or throw Error::Socket("sending hash failed $@");
					#close $io;
				}

				chomp $line;
				log_msg( "reception: $line") if($debug);
				$archive->put("$line");
				my @fields = split(/\|/, $line);
		        my ($servicedesc, 
					$hostname, 
					$hostaddress, 
					$timet, 
					$serviceexecutiontime, 
					$servicelatency,
					$servicestate,
					$serviceoutput, 
					$serviceperfdata) =
	              (
					$fields[SVC_SERVICEDESC], 
					$fields[SVC_HOSTNAME],
					$fields[SVC_HOSTADDRESS],
					$fields[SVC_TIMET],
					$fields[SVC_SERVICEEXECUTIONTIME],
	            	$fields[SVC_SERVICELATENCY],
					$fields[SVC_SERVICESTATE],
					$fields[SVC_SERVICEOUTPUT],
					$fields[SVC_SERVICEPERFDATA]
				);
				# -- Host perfdata process
	       		if($fields[0]=~ m/HOSTPERFDATA/i){
	           		next; # non pris en compte pour le moment
	       		}
	
				if(!defined($fields[SVC_SERVICEPERFDATA])){
					next; # ignore line without perfdata
				}
				# -- Service perfdata process
		       	if($fields[0]=~ m/SERVICEPERFDATA/i || $fields[0] =~ m/SERVICEARCHIVEPERFDATA/i){
					if (!defined ($$base_rrd{$hostname}{$servicedesc})){
						log_msg("new N2Cacti::RRD ($hostname,$servicedesc, $timet)") if($debug);
						$$base_rrd{$hostname}{$servicedesc} = new N2Cacti::RRD({
							service_description => "$servicedesc", 
							hostname			=> "$hostname",
							start_time			=> $timet,
							debug				=> $debug,
							cb_log_msg			=> \&log_msg,
							with_mysql			=> defined($opt->{m}),
							});
	 					if(defined($opt->{u}) && $$base_rrd{$hostname}{$servicedesc}->validate()){
							my $host = new N2Cacti::Cacti::Host({
							    hostname            => $hostname,
							    hostaddress 		=> $hostaddress,
								});
							$host->create_host();
						
							#-- create data_template and instanciate it!
							my $data_template = new N2Cacti::Cacti::Data({
							    hostname            => $hostname,
							   	hostaddress			=> $hostaddress,
							    service_description => $servicedesc,
							    rrd					=> $$base_rrd{$hostname}{$servicedesc},
								});
							$data_template->create_instance($debug);
							$data_template->update_rrd($debug);
							$data_template->create_individual_instance($debug);
												
							#-- create graph_template and instanciate it!
							my $graph_template = new N2Cacti::Cacti::Graph({
			                    hostname            => $hostname,
							   	hostaddress			=> $hostaddress,
			                    service_description => $servicedesc,
			                    graph_item_type		=> $config->{GRAPH_ITEM_TYPE},
			                    graph_item_colors	=> $config->{GRAPH_ITEM_COLORS},
			                    rrd					=> $$base_rrd{$hostname}{$servicedesc},
								});
							$graph_template->create_template($debug);
							$graph_template->create_instance($debug);
							$graph_template->update_input($debug);
							$graph_template->create_individual_instance($debug);
						}
					}
	
	
					if($$base_rrd{$hostname}{$servicedesc}->validate()){
						$$base_rrd{$hostname}{$servicedesc}->with_mysql($fields[0]=~m/SERVICEPERFDATA/i && defined($$opt{m}));
						$$base_rrd{$hostname}{$servicedesc}->update_rrd 	($serviceperfdata,$timet);
						$$base_rrd{$hostname}{$servicedesc}->update_rrd_el 	($serviceexecutiontime,$servicelatency,$servicestate,$timet);
					}
					$debug=1;
           		}

	
					
			}
	    	close $io && print "fermeture IO" if(defined ($$opt{p}));
			exit 0 if(defined($$opt{f}));
		    #select(undef, undef, undef, 0.2);  # sleep 1/5th second
		}
		catch Error::Simple with {
			my $E = shift;
			print STDERR $E->stringify();			
		};
	}
	close LOG;
}

#-- log error in ARCHIVE_DIR with the package N2Cacti
sub log_msg {
    my $str = shift;
	chomp $str;
	my $log = new N2Cacti::Archive({
    	archive_dir => "$$config{ARCHIVE_DIR}",
    	rotation    => "d",
    	basename    => "perf2rrd.log",
    });
    $log->put( "perf2rrd: $str");
	print "$str\n";
	$log->close();
}

sub usage {
    print "perf2rrd: \n perf2rrd options
        -h              print usage and exit
        -c <path>/config-file-name
                        n2rrd.conf in case you want to overide default values
		-d				daemonize
		-v 				verbose
		-m				with storage in mysql
		-u				update cacti configuration
		-p <port>		listen on this port
		-s <path>		listen local socket
		-f <path>		import the file
";
    exit 0;
}

