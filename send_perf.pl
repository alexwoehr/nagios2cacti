#!/usr/bin/perl -w
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
use strict;
use warnings;
use Error qw(:try);

#-- Class to handle socket exception
package Error::Socket;
use base 'Error::Simple';
1;

package main;
use lib qw(. ./lib /usr/lib/N2Cacti/lib);
use Getopt::Std;
use N2Cacti::Archive;
use N2Cacti::Config;
use IO::Socket;
use Digest::MD5 qw(md5 md5_hex md5_base64);
use Error qw(:try);
#use IO::Socket::SSL;
#-- Do not buffer writes
$| = 1;

#-- initiatilisation
our $opt      = {};
getopts( "H:p:d:s:C:", $opt );


#system('echo $0>/data/archive/perfdata/backlog/`date +%F`.follow');

my $cb_usage= sub {
#	system('echo $0>/data/archive/perfdata/backlog/`date +%F`.follow');
	print "$0 parameter: 
-H <hostname>	:perf2rrd server hostname
-p <port>		: perf2rrd server port
-s <localpath>	: transmission with local AF_UNIX protocol
-C <path> 		: n2rrd configuration file\n";
	print '-d <perfdata> 	: format [SERVICEPERFDATA]|$SERVICEDESC$|$HOSTNAME$|$HOSTADDRESS$|$TIMET$|$SERVICEEXECUTIONTIME$|$SERVICELATENCY$|$SERVICESTATE$|$SERVICEOUTPUT$|$SERVICEPERFDATA$'."\n";
	print "\tyou can send data with AF_UNIX and AF_INET\n";	
};

#-- verification du nombre d'argument passe en parametre
if(((!defined($$opt{H}) || !defined($$opt{p}))&& !defined($$opt{s})) || !defined($$opt{d})) {&$cb_usage; exit 1;} 


#-- chargement de la configuration
our $config 						= get_config($$opt{C});
our @data							= split(/\|/, $$opt{d});
our $backlog_dir 					= $$config{BACKLOG_DIR};
our ($service_name,$template_name) 	= split($$config{TEMPLATE_SEPARATOR_FIELD}, $data[1]);
our $hostname						= $data[2];





#-- backup perfdata in backlog before processed
my $cb_backup_perfdata = sub {
	my $message = shift;
	my $archive = new N2Cacti::Archive({
		archive_dir => "$backlog_dir",
		rotation	=> "n",
        basename    => "${hostname}_${service_name}.log",
		});
	$archive->put($message);
	$archive->close();
};


#-- process data in backlog (send to perf2rrd server) 



#-- send perfdata throw an exception if transmission has failed
my $cb_send_perfdata = sub {
	my $message 	= shift;
	my $hostname 	= shift;
	my $port		= shift || 0;
	my $sockpath	= $hostname;
	my $result;
   	my 	($sock, $MAXLEN, $PORTNO, $TIMEOUT);
	my $hash		= md5_hex($message);
	my $type 		= SOCK_DGRAM;
	$MAXLEN  		= 1024;
	$PORTNO  		= 5151;
	$TIMEOUT 		= 10;

	try {
		if($port>0){
			$sock = IO::Socket::INET->new(Proto     => 'udp',
                              	PeerPort  => $port,
                              	PeerAddr  => $hostname,
							  	Timeout	=> 10)
    			or throw Error::Socket("INET->new($hostname:$port):$!");
		}
		else{
			throw Error::Socket("$sockpath is not a socket") if ! -S $sockpath;
			$sock = IO::Socket::UNIX->new(PeerAddr  => "$sockpath",
                                Type      => $type,
                                Timeout   => 10 )
    			or throw Error::Socket("UNIX->new($sockpath):$!");
		}
		chomp($message);
		$message.="\n";
		$hash        = md5_hex($message);
		print "sending $message\n";
		$sock->send($message) 
    		or throw Error::Socket("SEND($message):$!");

		local $SIG{ALRM} = sub { throw Error::Socket( "timeout ${TIMEOUT}s"); };
  		alarm $TIMEOUT;
	    $sock->recv($result, $MAXLEN)     
    		or throw Error::Socket("RECV:$!");
		throw Error::Socket("hash incorrect") if ($result ne $hash);
		print "II\t$message - hash correct\n" if $result eq $hash;
    	alarm 0;
	}
	catch Error::Socket with{
		print "result:$result\n";
		my $E = shift;
		throw $E;
	}
	finally{
		close($sock) if defined($sock);	
	};
};


my $cb_process_backlog = sub{
	my $error=0;
    my $archive = new N2Cacti::Archive({
        archive_dir => "$backlog_dir",
		rotation	=> "n",
        basename    => "${hostname}_${service_name}.log",
        log_msg     => \&log_msg});
	my $io = $archive->open_raw(time, "r"); #-- time useless but necessary... sick!
	try {
		while(<$io>){
			&$cb_send_perfdata($_, $$opt{s}) if (defined($$opt{s}));
			&$cb_send_perfdata($_, $$opt{H}, $$opt{p}) if (defined($$opt{H}) && defined($$opt{p}));
		}
	}
	catch Error::Socket with{
		my $E = shift;
		print "EE:Socket: ".$E->stringify()."\n";
		$error++;
	}
	catch Error::Simple with{
		my $E = shift;
		print "EE: ".$E->stringify()."\n";
		$error++;
	}
	finally{
		$archive->close();
		if($error == 0){
			if(-e $$archive{fullpath}){
				unlink($archive->{fullpath});
				print "rm $$archive{fullpath}\n";
			}
		}
	};
};

my $cb_process_perfdata= sub{
	my $message = shift;
    my $archive = new N2Cacti::Archive({
        archive_dir => "$backlog_dir",
		rotation	=> "n",
        basename    => "${hostname}_${service_name}.log",
        log_msg     => \&log_msg});
			
	try{
		if (-e $archive->{fullpath}){
			print "put $$archive{fullpath}:$message\n";
			&$cb_backup_perfdata($message);
			&$cb_process_backlog;
		}
		else{
			print "file $$archive{fullpath} dont exist sending...\n";
	        &$cb_send_perfdata($message, $$opt{l}) if (defined($$opt{l}));
	        &$cb_send_perfdata($message, $$opt{H}, $$opt{p}) if (defined($$opt{H}) && defined($$opt{p}));
		}
    }
    catch Error::Simple with{
		&$cb_backup_perfdata($message);
    };
};



my $cb_main = sub {
	&$cb_process_perfdata($$opt{d});
	return 0;
};

exit &$cb_main;








