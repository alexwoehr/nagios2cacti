# tsync::riola-bck romagna-bck  emilia-bck  imola casole
# sync:: grado calci donnini-bck
############################################################################
##                                                                         #
## Client.pm                                                               #
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

##########################################################################

use strict;
use warnings;

package N2Cacti::Client;

require Sys::Syslog;

use N2Cacti::Archive;
use N2Cacti::Config;

use IO::Socket;
use Digest::MD5 qw(md5 md5_hex md5_base64);
#use IO::Socket::SSL;

##########################################################################

#
# new
#
# The constructor
#
# By default nothing is written locally and the timeout is set to 1 second
#
sub new {
	my $class = shift;
	my $param = shift;

	my $this = {
		class			=> $class,

		config_file		=> $param->{config_file},
		config			=> get_config($param->{config_file}),

		process_backlogs	=> $param->{process_backlogs}||0,
		write_backlogs		=> $param->{write_backlogs}||0,

		check_duplicates	=> $param->{check_duplicates}||0,

		timeout			=> $param->{timeout}||1
	};

	if ( not defined $param->{hostname} or not defined $param->{port} ) {
		Main::log_msg("$class: cannot send to any server, you can only write to backlogs", "LOG_WARN");
	} else {
		$this->{hostname} = $param->{hostname};
		$this->{port} = $param->{port};
	}

	bless($this,$class);
	return $this;
}

#
# send
#
# Sends the given data to n2cacti server
#
# @args		: the message
# @return	: data has been sent or backloged if not sent (1) || ko (0)
#		: $@ explains why it failed
#
sub send {
	my $this = shift;
	my $message = shift;

	my @data = split(/\|/, $message);
	my $hostname = $data[2];
	my ($service_name,$template_name) = split($this->{config}->{TEMPLATE_SEPARATOR_FIELD}, $data[1]);

	if ( $this->{process_backlogs} or $this->{write_backlogs} or $this->{check_duplicates} ) {
		$this->{archive} = new N2Cacti::Archive({
			archive_dir	=> $this->{config}->{BACKLOG_DIR},
			rotation	=> "n",
			basename	=> "$hostname\_$service_name.db"
		});
	} else {
		$this->{archive} = undef;
	}

	if ( not $this->check_message($message) ) {
		Main::log_msg("N2Cacti::Client::send(): bad message", "LOG_ERR");
		return 0;
	}

	if ( ( $this->{write_backlogs} or $this->{check_duplicates} ) and not defined $this->{archive} ) {
		Main::log_msg("N2Cacti::Client::send():: though write_backlogs or check_duplicates are true, archive is null", "LOG_ERR");
		return 0;
	}

	if ( $this->{check_duplicates} ) {
		if ( $this->{archive}->is_duplicated($message) ) {
			Main::log_msg("N2Cacti::Client::send(): the message has already been sent", "LOG_ERR");
			return 0;
		}
	}

	if ( not $this->send_perfdata($message) ) {
		if ( $this->{write_backlogs} ) {
			return $this->backup_perfdata($message);
		} else {
			return 0;
		}
	}

	return 1;
}

#
# backup_perfdata
#
# Puts the backlogs into the SQLite file
#
# @args		: message et archive object
# @return	: undef
#
sub backup_perfdata {
	my $this	= shift;
	my $message	= shift;

	Main::log_msg("send_perf.pl:backup_perfdata(): $message", "LOG_INFO");
	$this->{archive}->put($message);
}

#
# send_perfdata
#
# Sends the data though a UDP or socket
# A timeout is set while sending the data
# We need to use an eval bloc to limit the timoout's spread
#
# @args		: message, hostname and port number
# @return	: sucess (0) or failure (1)
#
sub send_perfdata {
	my $this	= shift;
	my $message	= shift;

	my ($result, $buffer);
   	my ($sock, $MAXLEN, $TIMEOUT);

	my $hash = md5_hex($message);
	my $type = SOCK_DGRAM;
	my $log_line = "";
	my $return_code = 0;

	$MAXLEN = 1024;
	$TIMEOUT = 1;

	if ( $this->{port} > 0 ) {
		if ( not $sock = IO::Socket::INET->new(
			Proto		=> 'udp',
			PeerPort	=> $this->{port},
			PeerAddr	=> $this->{hostname},
			Timeout		=> 10
		) ) {
			Main::log_msg("N2Cacti::Client::send_perdata(): INET->new($this->{hostname}:$this->{port}):$!", "LOG_CRIT");
			return 0;
		}
	} else {
		if ( ! -S $this->{sockpath} ) {
			Main::log_msg("N2Cacti::Client::send_perfdata(): $this->{sockpath} is not a socket", "LOG_CRIT");
			return 0;
		}

		if ( not $sock = IO::Socket::UNIX->new(
			PeerAddr	=> $this->{sockpath},
			Type		=> $type,
			Timeout		=> 10
		) ) {
			Main::log_msg("N2Cacti::Client::send_perdata(): UNIX->new($this->{sockpath}):$!", "LOG_CRIT");
			return 0;
		}
	}

	chomp($message);
	$message .= "\n";
	$hash = md5_hex($message);

	if ( not $sock->send($message) ) {
		Main::log_msg("N2Cacti::Client::send_perfdata(): $!", "LOG_ERR");
		return 0;
	}

	eval {
		no warnings 'all';
		local $SIG{ALRM} = sub {
			Main::log_msg("N2Cacti::Client::send_perfdata(): timeout ${TIMEOUT}s", "LOG_CRIT");
			die "transmit error";
		};
	  	alarm $TIMEOUT;

		my $log_line = "Receiving : ";

		if ( $sock->recv($result, $MAXLEN) ) {
			alarm 0;
			$log_line .= "OK";
			Main::log_msg("N2Cacti::Client::send_perfdata(): $log_line", "LOG_DEBUG");
		} else {
			alarm 0;
			$log_line .= $!;
			Main::log_msg("N2Cacti::Client::send_perfdata(): $log_line", "LOG_ERR");
			die "transmit error";
		}
	};

	if ( $@ =~ m/transmit error/ ) {
		return 0;
	}

	$log_line = "Checking : ";

	if ( $result ne $hash ) {
		$log_line .= "KO : incorrect hash";
		Main::log_msg("N2Cacti::Client::send_perfdata(): $log_line", "LOG_ERR");
		return 0;
	}

	return 1;
}

#
# process_backlog
#
# Gets the backlogs from the database and push them
#
# @args		: none
# @return	: success (1) || problem (0)
#
# 
sub process_backlog {
	my $this		= shift;

	my $error		= 0;
	my $errors_number	= 0;
	my $total_number	= 0;
	my $timestamp		= 0;
	my $failed		= 0;
	my $backlog		= {};

	my $io = $this->{archive}->open();

	if ( not defined $io ) {
		Main::log_msg("N2Cacti::Client::process_backlog(): db handler is not defined", "LOG_CRIT");
		return 0;
	}

	$backlog = $this->{archive}->fetch();
	$total_number = scalar (keys %$backlog);

	while ( my ($key, $data) = each(%$backlog) and not $failed ) {
		$total_number++;
		if ( defined($this->{socket}) eq 1 ) {
			if ( not send_perfdata($data->{data}, $this->{socket} ) ) {
				$failed = 1;
			}
		}

		if ( (defined($this->{hostname}) and defined($this->{port})) ) {
			if ( not send_perfdata($data->{data}, $this->{hostname}, $this->{port}) ) {
				$failed = 1;
			}
		}

		# we purge the backlog only if we dont have any failed
		if ( not $failed ) {
			$this->{archive}->remove($data->{'timestamp'}, $data->{'hash'});
		}
	}

	if ( $failed ) {
		Main::log_msg("N2Cacti::Client::process_backlog(): error while sending backlogs", "LOG_ERR");
		return 0;
	}

	Main::log_msg("N2Cacti::Client::process_backlog(): $total_number backlog lines processed without any error", "LOG_INFO");
	return 1;
}

#
# check_message
#
# Checks if the given message is perfdata compliant
# The checks are basic
#
# @args		: the message
# @return	: OK (1) || KO (0)
#
sub check_message {
	my $this	= shift;
	my $message	= shift;

	my @data = split(/\|/, $message);

	if ( scalar @data != 10 ) {
		Main::log_msg("$this->{class}:check_message(): the message does not contain 10 sections", "LOG_ERR");
		return 0;
	}

	if ( $data[0] !~ /\[SERVICEPERFDATA\]|\[HOSTPERFDATA\]/ ) {
		Main::log_msg("$this->{class}: check_message(): the data type is not SERVICEPERFDATA nor HOSTPERFDATA", "LOG_ERR");
		return 0;
	}

	return 1;
}

1;

