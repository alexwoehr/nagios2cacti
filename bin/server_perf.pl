#!/usr/bin/perl
# tsync:: casole
# sync:: calci
############################################################################
##                                                                         #
## server_perf.pl                                                          #
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
package Main;

################################################################################
# Initialisation
################################################################################
# put the lib in perl path or customize "use lib"
#use lib qw(.);
use Cwd;
use Cwd 'abs_path';
use lib '/HOME/uxwadm/scripts/n2cacti/lib';
require Sys::Syslog;

my $chdir=abs_path($0);
$chdir =~ s/\/[^\/]+$//g;
chdir($chdir);


use IO::Socket;
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
#use N2Cacti::Cacti::Tree;
use N2Cacti::RRD;
use Net::Server::Daemonize qw(daemonize);
use IO::Handle;
use IO::File;
use Digest::MD5 qw(md5 md5_hex md5_base64);

use constant {
	SVC_SERVICEDESC			=> 1,
	SVC_HOSTNAME			=> 2,
	SVC_HOSTADDRESS			=> 3,

	SVC_TIMET			=> 4,

	SVC_SERVICEEXECUTIONTIME	=> 5,
	SVC_SERVICEOUTPUT		=> 6,
	SVC_SERVICELATENCY		=> 7,
	SVC_SERVICESTATE		=> 8,

	SVC_SERVICEPERFDATA		=> 9,


	HST_HOSTNAME			=> 1,
	HST_HOSTADDRESS			=> 2,

	HST_TIMET			=> 3,

	HST_HOSTEXECUTIONTIME		=> 4,
	HST_HOSTSTATE			=> 5,

	HST_HOSTOUTPUT			=> 6,
	HST_HOSTPERFDATA		=> 7,
};

# Do not buffer writes
$| = 1;
# -- initiatilisation
my $opt = {};
my $rrderror = "";
my $base_rrd = {};
my ($io,$line);

our $shutdown_signal = 0;

getopts( "f:mvduc:p:s:h", $opt );
usage() if (defined($opt->{h}));

my $config = get_config($opt->{c});
if ( $config == undef ) {
	exit 1;
}

set_process_name($0);


################################################################################
# Fonctions
################################################################################

#
# log_msg
#
# log error to stdout or to syslog
#
# @args		: message and level
# @return	: undef
#
sub log_msg {
	my $str = shift;
	my $level = shift;

	if ( $level =~ /^$/ ) {
		$level = "LOG_INFO";
	}

	if ( $level =~ /LOG_DEBUG/ and $opt->{v} == 0 ) {
		return undef;
	}	

	chomp $str;

	if ( defined($opt->{d}) ) {
		Sys::Syslog::openlog("n2cacti", "ndelay", "LOG_DAEMON");
		Sys::Syslog::syslog($level, $str);
		Sys::Syslog::closelog();
	} else {
		print "$level:\t$str\n";
	}
}

#
# set_shutdown_signal
#
# sets the flag to true
# the current data are processed until the end before exiting
#
sub set_shutdown_signal {
	$shutdown_signal = 1;
}

#
# clean_exit
#
# closes everything before exiting
#
# @args		: undef
# @return	: undef
#
sub clean_exit {
	log_msg("--> clean_exit()", "LOG_DEBUG");

	if ( -p $$config{SERVICE_PERFDATA_PIPE} ) {
		log_msg("clean_exit(): removing pipe", "LOG_INFO");
		unlink $$config{SERVICE_PERFDATA_PIPE};
	}

	if ( defined($$opt{s}) or defined($$opt{p}) ) {
		log_msg("clean_exit(): unbinding socket", "LOG_INFO");
		close $io;
	}

	
	log_msg("clean_exit(): removing lock file", "LOG_INFO");
	unlink $$config{PID_FILE};

	log_msg("<-- clean_exit()", "LOG_DEBUG");
	exit 0;
}

#
# usage
#
# prints how to use the n2cacti
#
# @args		: undef
# @return	: undef
#
sub usage {
	print "server_perf.pl:
 options
	-h              print usage and exit
	-c <path>/config-file-name
		n2rrd.conf in case you want to overide default values
	-d		daemonize
	-v 		verbose
	-m		with storage in mysql
	-u		update cacti configuration
	-p <port>	listen on this port
	-s <path>	listen local socket
	-f <path>	import the file
";
    exit 0;
}

################################################################################
# Traitements
################################################################################

# We make a clean exit on signals SIGTERM / KILL
$SIG{TERM} = \&clean_exit;
$SIG{KILL} = \&clean_exit;;

daemonize('cacti', 'cacti', "$$config{PID_FILE}") if ( defined($opt->{d}) );

# define the archive mode
my $archive = new N2Cacti::Archive({
	archive_dir	=> $$config{ARCHIVE_DIR},
	rotation	=> $$config{ROTATION},
	basename	=> "perfdata.db"
});

unless (-p $$config{SERVICE_PERFDATA_PIPE}){
	if (-e $$config{SERVICE_PERFDATA_PIPE}) {        # but a something else
		die "$0: won't overwrite .signature\n";
	} else {
		POSIX::mkfifo($$config{SERVICE_PERFDATA_PIPE}, 0666) or die "can't mknod $$config{SERVICE_PERFDATA_PIPE}: $!";
		log_msg("$0: created $$config{SERVICE_PERFDATA_PIPE} as a named pipe", "LOG_INFO");
	}
}

# infinite loop !
while (1) {
	# exit if signature file manually removed
	if( ! defined($opt->{f}) && ! defined($$opt{s}) && ! defined($$opt{p}) ) {
		$io = new IO::File ($$config{SERVICE_PERFDATA_PIPE}, "r");
	} elsif( defined($$opt{f}) ) {
		die("File disappeared") unless -f $$opt{f};
		$io = new IO::File ($$opt{f}, "r");
	} elsif( defined($$opt{s}) ) {
		unlink($$opt{s});
		log_msg("creating socket file : $$opt{s}", "LOG_DEBUG");
		$io = IO::Socket::UNIX->new(HostPath => $$opt{s}, Type => SOCK_DGRAM, Listen => 5) or die( "socket: $@");
		select(undef,undef,undef,5);
		log_msg("socket created", "LOG_DEBUG");
	} elsif(defined($$opt{p})){
		log_msg( "create socket udp $$opt{p}", "LOG_DEBUG");
		$io = IO::Socket::INET->new(LocalPort => $$opt{p}, Proto => 'udp') or die( "socket: $@");
		log_msg("socket created", "LOG_DEBUG");
	}

	while ( $io->recv($line,16384) ) {
		my $hash = md5_hex($line);
		my $pid;

		# return the md5 line
		if( defined($$opt{s}) || defined($$opt{p}) ) {
			my($port, $ipaddr) = sockaddr_in($io->peername);
			my $hishost = gethostbyaddr($ipaddr, AF_INET);
			log_msg("$hishost: $hash", "LOG_DEBUG");
			$io->send("$hash");
		}

		chomp $line;
		log_msg("reception: $line", "LOG_DEBUG");

		# if the data is already in the backlog (failed process) it is skipped
		next if ( $archive->is_duplicated($line) );
		$archive->put($line);

		# we fork only if we can update the rrd files
#		if ( $$opt{d} ) {
#			$pid = fork;
#		}
#
#		next if $pid != 0;
#		log_msg("server_perf.pl: fork !", "LOG_DEBUG");

		my @fields = split(/\|/, $line);
		my (	$servicedesc, 
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

		log_msg("data type: ". $fields[0], "LOG_DEBUG");
		log_msg("service desc : ". $fields[SVC_SERVICEDESC], "LOG_DEBUG");
		log_msg("hostname : ". $fields[SVC_HOSTNAME], "LOG_DEBUG");
		log_msg("host address : ". $fields[SVC_HOSTADDRESS], "LOG_DEBUG");
		log_msg("timet : ".$fields[SVC_TIMET], "LOG_DEBUG");
		log_msg("service execution time : ".$fields[SVC_SERVICEEXECUTIONTIME], "LOG_DEBUG");
		log_msg("service latency : ".$fields[SVC_SERVICELATENCY], "LOG_DEBUG");
		log_msg("service state : ".$fields[SVC_SERVICESTATE], "LOG_DEBUG");
		log_msg("service output : ".$fields[SVC_SERVICEOUTPUT], "LOG_DEBUG");
		log_msg("service perfdata : ".$fields[SVC_SERVICEPERFDATA], "LOG_DEBUG");

		# Host perfdata process
		if ( $fields[0] =~ m/HOSTPERFDATA/i ) {
			log_msg("Recieved HOSTPERFDATA, skip it!", "LOG_INFO");
			next; # non pris en compte pour le moment
		}
	
		if ( not defined( $fields[SVC_SERVICEPERFDATA] ) ){
			log_msg("SVC_SERVICEPERFDATA is not defined, skip it!", "LOG_INFO");
			next; # ignore line without perfdata
		}

		# Service perfdata process
		log_msg("testing fields[0] -> SERVICEPERFDATA or SERVICEARCHIVEPERFDATA", "LOG_DEBUG");
		if ( $fields[0] !~ m/SERVICEPERFDATA|SERVICEARCHIVEPERFDATA/i ) {
			log_msg("testing fields[0] failed, skip!", "LOG_INFO");
			next;
		}

		log_msg("testing base_rrd's definition", "LOG_DEBUG");
		if ( not defined ($$base_rrd{$hostname}{$servicedesc} ) ) {
			log_msg("new N2Cacti::RRD ($hostname,$servicedesc, $timet)", "LOG_DEBUG");
			$$base_rrd{$hostname}{$servicedesc} = new N2Cacti::RRD({
				service_description => "$servicedesc", 
				hostname	=> "$hostname",
				start_time	=> $timet,
				with_mysql	=> defined($opt->{m})
			});
		}

			$$base_rrd{$hostname}{$servicedesc}->with_mysql($fields[0]=~m/SERVICEPERFDATA/i && defined($$opt{m}));
			if ( $$base_rrd{$hostname}{$servicedesc}->update_rrd($serviceperfdata,$timet) ) {
				$archive->remove($timet,$hash);
			}
			#$$base_rrd{$hostname}{$servicedesc}->update_rrd_el($serviceexecutiontime,$servicelatency,$servicestate,$timet);

			if ( defined($opt->{u}) && $$base_rrd{$hostname}{$servicedesc}->validate() ) {
				my $host = new N2Cacti::Cacti::Host({
					hostname	=> $hostname,
					hostaddress	=> $hostaddress
				});
				$host->create_host();

				# create data_template and instanciate it!
				my $data_template = new N2Cacti::Cacti::Data({
					hostname		=> $hostname,
					hostaddress		=> $hostaddress,
					service_description	=> $servicedesc,
					rrd			=> $$base_rrd{$hostname}{$servicedesc}
				});

				$data_template->create_individual_instance();
#				$data_template->create_instance();
#				$data_template->update_rrd();

				# create graph_template and instanciate it!
				my $graph_template = new N2Cacti::Cacti::Graph({
					hostname		=> $hostname,
					hostaddress		=> $hostaddress,
					service_description	=> $servicedesc,
					graph_item_type		=> $config->{GRAPH_ITEM_TYPE},
					graph_item_colors	=> $config->{GRAPH_ITEM_COLORS},
					rrd			=> $$base_rrd{$hostname}{$servicedesc}
				});

				$graph_template->create_template();
				$graph_template->create_instance();
				$graph_template->update_input();
#				$graph_template->create_individual_instance();

				# creates the graph tree
				#my $graph_tree = new N2Cacti::Cacti::Tree($config);
				#$graph_tree->update($graph_tree->get_appl_info());
			}
#		}

		# Saving the data into files and/or the database
#		if ( $$base_rrd{$hostname}{$servicedesc}->validate() ) {
#			$$base_rrd{$hostname}{$servicedesc}->with_mysql($fields[0]=~m/SERVICEPERFDATA/i && defined($$opt{m}));
#
#			if ( $$base_rrd{$hostname}{$servicedesc}->update_rrd($serviceperfdata,$timet) ) {
#				$archive->remove($timet,$hash);
#			}
#
#				$$base_rrd{$hostname}{$servicedesc}->update_rrd_el($serviceexecutiontime,$servicelatency,$servicestate,$timet);
#			}

		if ( $shutdown_signal ) {
			clean_exit;
		}
	}
}

clean_exit;

1;

