use strict;

package N2Cacti::Archive;
#use N2Cacti::database; #version generique database (sqlserver/mysql)
use N2Cacti::Time;
use IO::Handle; #fdopen
use IO::File;


BEGIN {
        use Exporter   ();
        use vars       qw($VERSION @ISA @EXPORT @EXPORT_OK);
        @ISA = qw(Exporter);
        @EXPORT = qw();
}

#our $io;

sub new {
    my $class=shift;
	my $attr = shift;
    my %param = %$attr if $attr;
	
    my $this = {
		archive_dir			=> $param{archive_dir},
		rotation			=> $param{rotation}				|| "d",
		basename			=> $param{basename}				|| "archive.dat",
		last_rotate			=> -1,
		io					=> undef,
		put					=> \&put_raw,
		log_msg             => $param{cb_log_msg}           || \&default_log_msg,
	};
	$this->{put}	= \&put_hourly if ($$this{rotation} eq "h");
	$this->{put}	= \&put_daily if ($$this{rotation} eq "d");

	mkdir $param{archive_dir} if (!-d $param{archive_dir});
	die "parametre incorrecte pour la creation d'archive ($$this{rotation})" if($$this{rotation} ne "d" && $$this{rotation} ne "h" && $$this{rotation} eq "n");
    bless($this,$class);
    return $this;
}

#-- call the put function specialized in function of rotation selected
sub put{
	my $this= shift;
    my $data=shift;
	my $time=shift ||time;
	chomp $data;
    &{$this->{put}}($this,$data,$time);
}

#-- call the log_msg function
sub log_msg {
    my $this=shift;
    my $message=shift;
    &{$this->{log_msg}}($message);
}
# -- put data without rotation
sub put_raw {
	my $this	= shift;
	my $data 	= shift;
	my $time	= shift;
	my $io		= $this->{io};
	if(!defined($io)){
		my $fullpath= "$$this{archive_dir}/$$this{basename}";
		$io = new IO::File $fullpath,O_WRONLY|O_APPEND|O_CREAT;
		$this->{io}=$io;
		if (!defined($io)){
			my $message = "cant open $fullpath";
			$this->log_msg($message);
			die $message;
		}
	}
    print $io "$data\n";
}

# -- put data with rotation each hour
sub put_hourly{
	my $this 	= shift;
	my $data	= shift;
	my $time	= shift;
	my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime($time);
	my $io		= $this->{io};
	$year+=1900;
	$mon +=1;
	if($hour != $$this{last_rotate} || !defined ($io)){
		$io->close() if(defined ($io));
		my $fullpath = "$$this{archive_dir}/$year-$mon-$mday/$hour.$$this{basename}";
		mkdir "$$this{archive_dir}/$year-$mon-$mday/" if(! -d "$$this{archive_dir}/$year-$mon-$mday/");
		$io = new IO::File ($fullpath,O_WRONLY|O_APPEND|O_CREAT);
		$this->{io}=$io;
		if (!defined($io)){
			my $message = "cant open $fullpath";
			$this->log_msg($message);
			die $message;
		}
		$$this{last_rotate}=$hour;
	}
    print $io "$data\n";
}
	
# -- put data with rotation each day
sub put_daily {
	my $this 	= shift;
	my $data	= shift;
	my $time	= shift;
	my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime($time);
	my $io		= $this->{io};
	$year+=1900;
	$mon +=1;

	if($mday != $$this{last_rotate} || !defined ($io)){
		$io->close() if(defined ($io));
		my $fullpath = "$$this{archive_dir}/$year-$mon-$mday.$$this{basename}";
		$io = new IO::File ($fullpath,O_WRONLY|O_APPEND|O_CREAT);
		$this->{io}=$io;
		if (!defined($io)){
			my $message = "cant open $fullpath";
			$this->log_msg($message);
			die $message;
		}
		$$this{last_rotate}=$mday;
	}
    print $io "$data\n";
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
        $this->{io}=undef;
    }

}


1;
