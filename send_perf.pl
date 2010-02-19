#!/usr/bin/perl -w
# tsync::casole imola
# sync::grado
# nagios: -epn
# disable Embedded Perl Interpreter for nagios 3.0
############################################################################
##                                                                         #
## send_perf.pl                                                            #
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
#$USER1$/n2rrd.pl -d -c /etc/n2rrd/n2rrd.conf -T $LASTSERVICECHECK$ -H $HOSTNAME$ -s "$SERVICEDESC$" -o "$SERVICEPERFDATA$" -a $HOSTADDRESS$
#send_perf
#--> ecriture dans un fichier d'archivage
#--> lecture du backlog
#--> envoie udp àhaque demon enregistré   echec de l'envoie
#    --> ecriture des informations dans un fichiers de backlog
#    erreur de l'envoie (format invalide)
#    --> ecriture des informations dans un fichiers de log
#
# http://search.cpan.org/~behroozi/IO-Socket-SSL-0.97/SSL.pm
# perl -MCPAN -e 'install IO::Socket::SSL'
# perl -MCPAN -e 'install IO::Socket::UNIX'
# perl -MCPAN -e 'install IO::Socket::INET'
#
# http://www.spi.ens.fr/~beig/systeme/sockets.html
#
#---------------------------------------------------------------------------

##########################################################################
# Init
##########################################################################
use strict;
use warnings;

package Main;

require Sys::Syslog;

use lib qw(. /HOME/uxwadm/scripts/nagios/n2cacti/lib);
use Getopt::Std;

use N2Cacti::Archive;
use N2Cacti::Config;

use IO::Socket;
use Digest::MD5 qw(md5 md5_hex md5_base64);
#use IO::Socket::SSL;

#-- Do not buffer writes
$| = 1;

our $opt = {};
getopts( "H:p:d:s:C:v", $opt );

# Arguments check
if ( ( ( ! defined($$opt{H}) || ! defined($$opt{p}) ) && ! defined($$opt{s}) ) || ! defined($$opt{d}) ) {
	print "$0 parameter: 
-H <hostname>	:perf2rrd server hostname
-p <port>		: perf2rrd server port
-s <localpath>	: transmission with local AF_UNIX protocol
-C <path> 		: n2rrd configuration file\n";
	print '-d <perfdata> 	: format [SERVICEPERFDATA]|$SERVICEDESC$|$HOSTNAME$|$HOSTADDRESS$|$TIMET$|$SERVICEEXECUTIONTIME$|$SERVICELATENCY$|$SERVICESTATE$|$SERVICEOUTPUT$|$SERVICEPERFDATA$'."\n";
	print "\tyou can send data with AF_UNIX and AF_INET\n";	
	exit 1;
} 

# Configuration loading
our $config = get_config($$opt{C});
our @data = split(/\|/, $$opt{d});
our $backlog_dir = $$config{BACKLOG_DIR};
our ($service_name,$template_name) = split($$config{TEMPLATE_SEPARATOR_FIELD}, $data[1]);
our $hostname = $data[2];


my $archive = new N2Cacti::Archive({
	archive_dir	=> "$backlog_dir",
	rotation	=> "n",
	basename	=> "${hostname}_${service_name}.db"
});

##########################################################################
# Functions
##########################################################################

sub log_msg {
        my $str = shift;
        my $level = shift;

        if ( $level =~ /^$/ ) {
                $level = "LOG_INFO";
        }

	if ( $level =~ /LOG_DEBUG/ and defined $opt->{v} ) {
		return undef;
	}	

        chomp $str;

#        if ( defined ($opt->{d}) ) {
#                Sys::Syslog::openlog("n2cacti", "ndelay", "LOG_DAEMON");
#                Sys::Syslog::syslog($level, $str);
#                Sys::Syslog::closelog();
#        } else {
                print "$level:\t$str\n";
#        }
}

#-- backup perfdata in backlog before processed
sub backup_perfdata {
	my $message = shift;
	my $archive = shift;

	$archive->put($message);
}

#-- send perfdata and return false if transmission has failed
sub send_perfdata {
	my $message = shift;
	my $hostname = shift;
	my $port = shift || 0;

	my $sockpath = $hostname;
	my ($result, $buffer);
   	my ($sock, $MAXLEN, $PORTNO, $TIMEOUT);

	my $hash = md5_hex($message);
	my $type = SOCK_DGRAM;
	my $log_line = "";
	my $return_code = 0;

	$MAXLEN = 1024;
	$PORTNO = 5151;
	$TIMEOUT = 1;

	if ( $port > 0 ) {
		if ( not $sock = IO::Socket::INET->new(
			Proto		=> 'udp',
			PeerPort	=> $port,
			PeerAddr	=> $hostname,
			Timeout		=> 10
		) ) {
			Main::log_msg("send_perf.pl::send_perdata(): INET->new($hostname:$port):$!", "LOG_CRIT");
			return 1;
		}
	} else {
		if ( ! -S $sockpath ) {
			Main::log_msg("send_perf.pl::send_perfdata(): $sockpath is not a socket", "LOG_CRIT");
			return 1;
		}

		if ( not $sock = IO::Socket::UNIX->new(
			PeerAddr	=> "$sockpath",
			Type		=> $type,
			Timeout		=> 10
		) ) {
			Main::log_msg("send_perf.pl::send_perdata(): UNIX->new($sockpath):$!", "LOG_CRIT");
			return 1;
		}
	}

	chomp($message);
	$message .= "\n";
	$hash = md5_hex($message);

	$buffer = $message;
	chomp($buffer);
	$log_line = "Sending : $buffer : ";

	if ( $sock->send($message) ) {
		$log_line .= "OK";
		Main::log_msg("send_perf.pl::send_perfdata(): $log_line", "LOG_DEBUG");
	} else {
		$log_line .= "KO : $!";
		Main::log_msg("send_perf.pl::send_perfdata(): $log_line", "LOG_ERR");
		return 1;
	}

	# We need to use an eval bloc to limit the timoout's spread
	eval {
		no warnings 'all';
		local $SIG{ALRM} = sub {
			Main::log_msg("send_perf.pl::send_perfdata(): timeout ${TIMEOUT}s", "LOG_CRIT");
			return 1;
		};
	  	alarm $TIMEOUT;

		my $log_line = "Receiving : ";

		if ( $sock->recv($result, $MAXLEN) ) {
			alarm 0;
			$log_line .= "OK";
			Main::log_msg("send_perf.pl::send_perfdata(): $log_line", "LOG_DEBUG");
		} else {
			alarm 0;
			$log_line .= $!;
			Main::log_msg("send_perf.pl::send_perfdata(): $log_line", "LOG_ERR");
			return 1;
		}
	} or return 1;

	$log_line = "Checking : ";

	if ( $result ne $hash ) {
		$log_line .= "KO : incorrect hash";
		Main::log_msg("send_perf.pl::send_perfdata(): $log_line", "LOG_ERR");
		return 1;
	} else {
		$log_line .= "OK : correct hash";
		Main::log_msg("send_perf.pl::send_perfdata(): $log_line", "LOG_DEBUG");
		return 0;
	}
}

sub process_backlog {
	my $archive = shift;

	my $error = 0;
	my $errors_number = 0;
	my $total_number = 0;
	my $timestamp = 0;
	my $backlog = {};

	my $io = $archive->open();

	if ( not defined $io ) {
		log_msg("send_perf.pl::process_backlog(): db handler is not defined", "LOG_CRIT");
		return 1;
	}

	$backlog = $archive->fetch();

	foreach $timestamp (keys %$backlog) {
		$total_number++;

		if ( defined($$opt{s}) eq 1 ) {
			if ( send_perfdata($backlog->{$timestamp}, $$opt{s}) eq 0 ) {
				$archive->{io}->remove($timestamp);
			}
		}

		if ( (defined($$opt{H}) and defined($$opt{p})) ) {
			if ( send_perfdata($backlog->{$timestamp}, $$opt{H}, $$opt{p}) eq 0 ) {
				$archive->remove($timestamp);
			}
		}
	}

	if ( $errors_number > 0 ) {
		log_msg("send_perf.pl::process_backlog(): $errors_number sending errors / $total_number lines", "LOG_ERR");
	}
}

#
# process_perfdata
#
# checks how to send perfdata and send them
# backups are done in case of failure
#
sub process_perfdata {
	my $message = shift;
	my $archive = shift;

	if ( defined($$opt{s}) ) {
		if ( send_perfdata($message, $$opt{s} == 1 ) ) {
			log_msg("send_perf.pl:process_perfdata(): send_perfdata failed, let's backup the data", "LOG_DEBUG");
			backup_perfdata($message, $archive) if ( defined $archive);
		}
	}

	if ( defined($$opt{H}) && defined($$opt{p}) ) {
		if ( send_perfdata($message, $$opt{H}, $$opt{p}) == 1 ) {
			log_msg("send_perf.pl:process_perfdata(): send_perfdata failed, let's backup the data", "LOG_DEBUG");
			backup_perfdata($message, $archive) if ( defined $archive);
		}
	}
}

##########################################################################
# Main
##########################################################################

if ( defined $archive ) {
	if ( $archive->check_duplicates($$opt{d}) == 0 ) {
		process_backlog($archive);
	} else {
		process_backlog($archive);
		process_perfdata($$opt{d}, $archive);
	}
} else {
	process_perfdata($$opt{d}, undef);
}

exit 0;

