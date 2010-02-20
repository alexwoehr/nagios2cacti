use strict;

package N2Cacti::Archive;

use N2Cacti::Time;
use IO::Handle; #fdopen
use File::Basename;
use DBI;

BEGIN {
        use Exporter();
        use vars qw($VERSION @ISA @EXPORT @EXPORT_OK);
        @ISA 	= 	qw(Exporter);
        @EXPORT = 	qw();
}

sub new {
	my $class=shift;
	my $attr = shift;
	my %param = %$attr if $attr;

	my $this = {
		archive_dir	=> $param{archive_dir},
		rotation	=> $param{rotation} || "n",
		basename	=> $param{basename} || "archive.dat",
		last_rotate	=> -1,
		io		=> undef,
		open		=> \&open,
		fullpath	=> "",
		remove_log	=> \&remove,
		fetch		=> \&fetch,
		put		=> \&put,
		debug		=> $param{debug} || 0
	};
	$this->{fullpath}= "$$this{archive_dir}/$$this{basename}";
	$this->{open}	= \&open_hourly if ($$this{rotation} eq "h");
	$this->{open}	= \&open_daily if ($$this{rotation} eq "d");
	$this->{open}	= \&open if($$this{rotation} eq "n");

	if ( ! -d $param{archive_dir} ) {
		if ( ! mkdir($param{archive_dir})) {
			Main::log_msg("N2Cacti::Archve::new(): wrong parameter creating ($$this{rotation})", "LOG_ERR") if($$this{rotation} ne "d" && $$this{rotation} ne "h" && $$this{rotation} ne "n");
			return undef;
		}
	}

	Main::log_msg("N2Cacti::Archve::new(): wrong parameter creating ($$this{rotation})", "LOG_ERR") if($$this{rotation} ne "d" && $$this{rotation} ne "h" && $$this{rotation} ne "n");

	bless($this,$class);
	return $this;
}

#
# put
#
# Inserts or updates data
#
# If there is already one row -> update
# Else -> insert
#
sub put {
	my $this = shift;
	my $data = shift;

	my ($query, $sth);
	my (@data_tab, @result);

	Main::log_msg("--> N2Cacti::Archive::put()", "LOG_DEBUG");

	# $data_tab[4] is the timestamp
	@data_tab = split(/\|/, $data);

	$this->open();

	if ( ! defined $this->{io} ) {
		Main::log_msg("N2Cacti::Archive::put(): the dbh is not defined, cannot backlog perfdata)", "LOG_ERR");
		return 1;
	}
	chomp $data;

	if ( $data_tab[4] !~ /^\d+$/ ) {
		Main::log_msg("N2Cacti::Archive::put(): the given timestamp $data_tab[4] is not scalar, cannot backlog perfdata)", "LOG_ERR");
		return 1;
	}

	$query = "REPLACE log SET timestamp = '$data_tab[4]', data = '$data' WHERE timestamp = '$data_tab[4]';";

	if ( $this->{io}->do($query) ) {
		Main::log_msg("<-- N2Cacti::Archive::put()", "LOG_DEBUG") if $this->{debug};
		return 0;
	} else {
		Main::log_msg("N2Cacti::Archive::put(): cannot execute : $query : $@", "LOG_CRIT");
		Main::log_msg("<-- N2Cacti::Archive::put()", "LOG_DEBUG") if $this->{debug};
		return 1;
	}
}

#
# open
#
# Connects to the DB file
#
sub open {
	my $this = shift;

	my $sth;
	my $query;

	if ( ! defined $this->{io} ) {
		$$this{fullpath}= "$$this{archive_dir}/$$this{basename}";

		$this->{io} = DBI->connect("dbi:SQLite:$$this{fullpath}");
		$this->{io}->{AutoCommit} = 1;
		$this->{io}->{RaiseError} = 1;

		if ( ! defined $this->{io} ) {
			Main::log_msg("N2Cacti::Archive:: cannot open $$this{fullpath}", "LOG_ERR");
			$this->{io} = undef;
		} else {
			$query = "SELECT count(*) FROM sqlite_master WHERE type = 'table' AND name = 'log';";
			$sth = $this->{io}->prepare($query);
			$sth->execute();

			if ( ($sth->fetchrow_array)[0] != 1 ) {
				$this->init();
			}
		}
	}
}

#
# open_hourly
#
# Creates a DB file per hour
#
sub open_hourly{
	my $this        = shift;
	my $time        = shift;
	my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime($time);

	$year +=1900;
	$mon +=1;

	if ( $hour != $$this{last_rotate} || ! defined $this->{io}  ){
		$this->{io}->close() if ( defined $this->{io} );
		$$this{fullpath} = "$$this{archive_dir}/$year-$mon-$mday/$hour.$$this{basename}";

		mkdir "$$this{archive_dir}/$year-$mon-$mday/" if(! -d "$$this{archive_dir}/$year-$mon-$mday/");

		$this->{io}->open();

		Main::log_msg("N2cacti::Archive::open_hourly(): cannot open $$this{fullpath}", "LOG_ERR") if ( ! defined $this->{io} );

		$$this{last_rotate} = $hour;
	}
}

#
# open_daily
#
# Creates a DB file per day
#
sub open_daily {
	my $this        = shift;
	my $time        = shift;
	my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime($time);

	$year +=1900;
	$mon +=1;

	if ( $mday != $$this{last_rotate} || ! defined $this->{io} ) {
		$this->{io}->close() if ( defined $this->{io} );
		$$this{fullpath} = "$$this{archive_dir}/$year-$mon-$mday.$$this{basename}";

		$this->{io}->open();

		Main::log_msg("N2cacti::Archive::open_daily(): cannot open $$this{fullpath}", "LOG_ERR") if ( ! defined $this->{io} );

		$$this{last_rotate} = $mday;
	}
}


#
# create the DB's structure
#
sub init {
	my $this = shift;

	my $query = "CREATE TABLE log ( 'timestamp' INTEGER, 'data' BLOB, CONSTRAINT cle PRIMARY KEY ( 'timestamp') )";

	if ( not defined $this->{io}) {
		$this->{io}->open();
	}

	$this->{io}->do($query);
	if ( $@ ) {
		Main::log_msg("N2Cacti::Archive::init(): cannot execute query : $query : $@", "LOG_CRIT");
		return 1;
	} else {
		return 0;
	}
}

#
# fetch
#
# Fetches the data table and retuens a hash ref
#
# @args		: the DB Handler
# @return 	: a hash ref timestamp->data or undef
#
sub fetch {
	my $this = shift;

	my $query = "SELECT timestamp, data FROM log ORDER BY timestamp;";
	my $data = {};
	my $sth;
	my @result;

	$sth = $this->{io}->prepare($query);
	if ( not $sth->execute() ) {
		Main::log_msg("N2Cacti::Archive::fetch_log(): cannot execute $query : $DBI::errstr", "LOG_CRIT");
		return undef;
	}

	while ( @result = $sth->fetchrow_array() ) {
		$data->{$result[0]} = $result[1];
	}

	return $data;
}

#
# remove
#
# Removes a log entry
#
# @args		: the DB Handler and the timestamp
# @return	: OK (1) or KO (0)
#
sub remove {
	my $this = shift;
	my $timestamp = shift;

	my $query = "DELETE FROM log WHERE timestamp = '$timestamp';";

	if ( $this->{io}->do($query) ) {
		return 0;
	} else {
		Main::log_msg("N2Cacti::Archive::remove_log(): cannot execute query : $query : $DBI::errstr", "LOG_CRIT");
		return 1;
	}
}

#
# check_duplicates
#
# Checks if the current perfdata is already in the backlog
#
# @return	: yes (0) or no (1)
#
sub check_duplicates {
	my $this = shift;
	my $data = shift;

	my ($query, $sth);
	my (@data_tab, @result);

	# $data_tab[4] is the timestamp
	@data_tab = split(/\|/, $data);

	$this->open();
	chomp $data;

	$query = "SELECT count(*) FROM log WHERE timestamp = '$data_tab[4]';";
	$sth = $this->{io}->prepare($query);
	$sth->execute();

	@result = $sth->fetchrow_array;

	if ( $result[0] == 0 ) {
		return 1;
	} else {
		return 0;
	}
}

#
# destructor
#
sub DESTROY{
	my $this = shift;
	my $io = $this->{io};
	if ( defined $io ) {
		$this->{io} = undef
	}
}

sub close {
	my $this = shift;
	my $io	= $this->{io};
	if ( defined $io ) {
		$this->{io}->close;
		$this->{io} = undef;
	}
}

1;

