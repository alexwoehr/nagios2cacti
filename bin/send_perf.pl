#!/usr/bin/perl -w
# nagios: -epn
# disable Embedded Perl Interpreter for nagios 3.0
############################################################################
##                                                                         #
## send_perf2.pl                                                           #
## Written by <mathieu.grzybek@gmail.com>                                  #
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
# module CPAN dependency
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

use lib '/HOME/uxwadm/scripts/n2cacti/lib';
require Sys::Syslog;

# put the lib in perl path or customize "use lib"
#use lib qw(.);
use Getopt::Std;

use N2Cacti::Archive;
use N2Cacti::Config;
use N2Cacti::Client;

use IO::Socket;
use Digest::MD5 qw(md5 md5_hex md5_base64);
#use IO::Socket::SSL;

#-- Do not buffer writes
$| = 1;

my $opt = {};
getopts( "H:p:d:s:C:vf", $opt );

# Arguments check
if ( ( ( ! defined($$opt{H}) || ! defined($$opt{p}) ) && ! defined($$opt{s}) ) || ! defined($$opt{d}) ) {
	print "$0 parameter: 
-f		: prints log messages to stdout
-v		: verbose mode
-H <hostname>	: perf2rrd server hostname
-p <port>	: perf2rrd server port
-s <localpath>	: transmission with local AF_UNIX protocol
-C <path> 	: n2rrd configuration file
-d <perfdata> 	: format [SERVICEPERFDATA]|\$SERVICEDESC\$|\$HOSTNAME\$|\$HOSTADDRESS\$|\$TIMET\$|\$SERVICEEXECUTIONTIME\$|\$SERVICELATENCY\$|\$SERVICESTATE\$|\$SERVICEOUTPUT\$|\$SERVICEPERFDATA\$'
you can send data with AF_UNIX and AF_INET\n";
	exit 1;
}

my $return_code = 1;

##########################################################################
# Functions
##########################################################################

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

	if ( $level =~ /LOG_DEBUG/ and defined $opt->{v} ) {
		return 0;
	}	

	chomp $str;

	if ( not defined($opt->{f}) ) {
		Sys::Syslog::openlog("n2cacti", "ndelay", "LOG_DAEMON");
		Sys::Syslog::syslog($level, $str);
		Sys::Syslog::closelog();
	} else {
		print "$level:\t$str\n";
	}

	return 1;
}

##########################################################################
# Main
##########################################################################

my $client = new N2Cacti::Client({
	hostname		=> $$opt{H},
	port			=> $$opt{p},
	config_file		=> $$opt{C},
	process_backlogs	=> 1,
	write_backlogs		=> 1,
	check_duplicates	=> 1,
	timeout			=> 1
});

$return_code = $client->send($$opt{d});

exit $return_code;

