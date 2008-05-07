use strict;


#-- Class to handle socket exception
package Error::Archive;
use base 'Error::Simple';
1;

package N2Cacti::Archive;

use N2Cacti::Time;
use IO::Handle; #fdopen
use IO::File;
use Error qw(:try);

BEGIN {
        use Exporter();
        use vars qw($VERSION @ISA @EXPORT @EXPORT_OK);
        @ISA 	= 	qw(Exporter);
        @EXPORT = 	qw();
}

#our $io;

sub new {
    my $class=shift;
	my $attr = shift;
    my %param = %$attr if $attr;
	
    my $this = {
		archive_dir			=> $param{archive_dir},
		rotation			=> $param{rotation}				|| "n",
		basename			=> $param{basename}				|| "archive.dat",
		last_rotate			=> -1,
		io					=> undef,
		'open'					=> \&open_raw,
		log_msg             => $param{cb_log_msg}           || \&default_log_msg,
		fullpath			=> "",
	};
	$this->{'open'}	= \&open_hourly if ($$this{rotation} eq "h");
	$this->{'open'}	= \&open_daily if ($$this{rotation} eq "d");
	$this->{'open'}	= \&open_raw if($$this{rotation} eq "n");
	mkdir $param{archive_dir} if (!-d $param{archive_dir});
	throw Error::Archive( "parametre incorrecte pour la creation d'archive ($$this{rotation})") if($$this{rotation} ne "d" && $$this{rotation} ne "h" && $$this{rotation} ne "n");
    bless($this,$class);
    return $this;
}

#-- call the put function specialized in function of rotation selected
sub put{
	my $this= shift;
    my $data=shift;
	my $time=shift ||time;
	chomp $data;
    my $io=&{$this->{'open'}}($this,$time);
	print $io "$data\n";
}


#-- call the log_msg function
sub log_msg {
    my $this=shift;
    my $message=shift;
    &{$this->{log_msg}}($message);
}

# -- put data without rotation
sub open_raw {
	my $this	= shift;
	my $time	= shift;
	my $io		= $this->{io};
	my $mode	= shift || O_WRONLY|O_APPEND|O_CREAT;
	if(!defined($io)){
		$io->close() if(defined ($io));
		$$this{fullpath}= "$$this{archive_dir}/$$this{basename}";
		$io = new IO::File ($$this{fullpath},$mode);
		$this->{io}=$io;
		if (!defined($io)){
			my $message = "cant open $$this{fullpath}";
			$this->log_msg($message);
			throw Error::Archive($message);
		}
	}
	return $io;
}

# -- put data with rotation each hour
sub open_hourly{
	my $this 	= shift;
	my $time	= shift;
	my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime($time);
	my $io		= $this->{io};
	my $mode	= shift || O_WRONLY|O_APPEND|O_CREAT;
	$year+=1900;
	$mon +=1;
	if($hour != $$this{last_rotate} || !defined ($io)){
		$io->close() if(defined ($io));
		$$this{fullpath} = "$$this{archive_dir}/$year-$mon-$mday/$hour.$$this{basename}";
		mkdir "$$this{archive_dir}/$year-$mon-$mday/" if(! -d "$$this{archive_dir}/$year-$mon-$mday/");
		$io = new IO::File ($$this{fullpath},$mode);
		$this->{io}=$io;
		if (!defined($io)){
			my $message = "cant open $$this{fullpath}";
			$this->log_msg($message);
			throw Error::Archive($message);
		}
		$$this{last_rotate}=$hour;
	}
	return $io;
}
	
# -- put data with rotation each day
sub open_daily {
	my $this 	= shift;
	my $time	= shift;
	my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime($time);
	my $io		= $this->{io};
	my $mode	= shift || O_WRONLY|O_APPEND|O_CREAT;
	$year+=1900;
	$mon +=1;

	if($mday != $$this{last_rotate} || !defined ($io)){
		$io->close() if(defined ($io));
		$$this{fullpath} = "$$this{archive_dir}/$year-$mon-$mday.$$this{basename}";
		$io = new IO::File ($$this{fullpath}, $mode);
		$this->{io}=$io;
		if (!defined($io)){
			my $message = "cant open $$this{fullpath}";
			$this->log_msg($message);
			throw Error::Archive($message);
		}
		$$this{last_rotate}=$mday;
	}
	return $io;
}

#-- default log
sub default_log_msg{
    my $message=shift;
    $message=~ s/\n$//g;
    print "default:$message\n";
}

sub DESTROY{
	my $this = shift;
	my $io = $this->{io};
	if (defined ($io)){
		$this->{io}=undef;
	}
}

sub close {
	my $this = shift;
	my $io	= $this->{io};
    if (defined ($io)){
		$this->{io}->close;
        $this->{io}=undef;
    }

}


1;
