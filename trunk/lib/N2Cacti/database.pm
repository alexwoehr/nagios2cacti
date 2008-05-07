###########################################################################
#                                                                         #
# connector MOM                                                           #
# Written by <detrak@caere.fr>                                            #
#                                                                         #
# This program is free software; you can redistribute it and/or modify it #
# under the terms of the GNU General Public License as published by the   #
# Free Software Foundation; either version 2, or (at your option) any     #
# later version.                                                          #
#                                                                         #
# This program is distributed in the hope that it will be useful, but     #
# WITHOUT ANY WARRANTY; without even the implied warranty of              #
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU       #
# General Public License for more details.                                #
#                                                                         #
###########################################################################


package N2Cacti::database;
use DBI();
use Error qw(:try);

BEGIN {
        use Exporter   	();
        use vars       	qw($VERSION @ISA @EXPORT @EXPORT_OK);
        @ISA 		=	qw(Exporter);
}



sub new {
	my $class	= shift;
	my $attr = shift;
	my %param = %$attr if $attr;
	my $this	= {
        database_type 		=> $param{database_type} 		|| "mysql",
        database_schema 	=> $param{database_schema} 		|| "cacti",
        database_hostname 	=> $param{database_hostname}	|| "localhost",
        database_username 	=> $param{database_username}	|| "user",
        database_password 	=> $param{database_password}	|| "password",
        database_port 		=> $param{database_port}		|| "3306",
		log_msg				=> $param{cb_log_msg}			|| \&default_log_msg,
		raise_exception		=> $param{raise_exception}			|| 0,
		older_exception_mod => 0,
	};
	bless($this,$class);
	$this->connect();
	return $this;
}

sub set_raise_exception{
	my $this=shift;
	my $raise=shift;
	$$this{raise_exception}= $raise if(defined($raise));
	return $$this{raise_exception};
}

sub default_log_msg{
	my $message=shift;
	$message=~ s/\n$//g;
	print "default:$message\n";
}

sub log_msg {
	my $this=shift;
    my $message=shift;
	&{$this->{log_msg}}($message);
}

sub connect {
    my $this = shift;
	$this->{dbh} = undef;
	if ($this->{database_type} eq "mysql"){
	    $this->{dbh} = DBI->connect ("DBI:mysql:database=".$this->{database_schema}.";".
	        "host=".$this->{database_hostname},
	        $this->{database_username},
	        $this->{database_password},
	        {
	            RaiseError  =>  1,
	            PrintError  =>  1,
	            AutoCommit  =>  1
	        }
	    )or die("cant connect to database");
		$this->{dbh}->do("use $$this{database_schema}");
	}
	elsif ($this->{database_type} eq "sybase" || $this->{database_type} eq "sqlserver"){
		$this->{dbh} = DBI->connect("DBI:Sybase:server=$$this{database_hostname}",
		    $$this{database_username},
    		$$this{database_password},  
			{
                RaiseError  =>  1,
                PrintError  =>  1,
                AutoCommit  =>  1
            }
) or die ("cant connect to database");
		$this->{dbh}->do("use $$this{database_schema}");
	}
	elsif ($this->{database_type} eq "pg" || $this->{database_type} =~ "postgres"){
		 $this->{dbh} = DBI->connect("DBI:Pg:server=$$this{database_hostname}",
            $$this{database_username},
            $$this{database_password},
            {
                RaiseError  =>  1,
                PrintError  =>  1,
                AutoCommit  =>  1
            }
) or die ("cant connect to database");
        $this->{dbh}->do("use $$this{database_schema}");
	}
	elsif ($this->{database_type} =~ /oracle/i){
		    $this->{dbh} = DBI->connect("DBI:Oracle:host=$$this{database_hostname};port=$$this{database_port};sid=$$this{database_schema};",
            $this->{database_username},
            $this->{database_password},
            {
                RaiseError  =>  1,
                PrintError  =>  1,
                AutoCommit  =>  1
            }
		) or die ("cant connect to database");
        #$dbh->do("use $$this{database_schema}");

	}

	return $this->{dbh};
}

#-----------------------------------------------------------------
#http://www.informit.com/articles/article.asp?p=23412&rl=1
#http://www.mathematik.uni-ulm.de/help/perl5/doc/DBD/mysql.html

sub begin {
    my $this=shift;
    $this->{old_pe} = $this->{dbh}->{PrintError}; # save and reset
    $this->{old_re} = $this->{dbh}->{RaiseError}; # error-handling
    $this->{dbh}->{PrintError} = 0;    # attributes
    $this->{dbh}->{RaiseError} = 1;
    $this->{dbh}->{AutoCommit} = 0;
    $$this{older_exception_mod}=$$this{raise_exception};
	$$this{raise_exception}=0;
    if ($this->{dbh}->{'AutoCommit'}) {
        $this->log_msg ('An error occured while passing transaction mode');
        die ('An error occured while passing transaction mode');
    }

}

sub end {
    my $this=shift;
    if ($@){
        $this->{dbh}->rollback();
    }
    else{
        $this->commit();
    }
}

sub commit {
    my $this=shift;
    $this->{dbh}->commit();
    $this->{dbh}->{AutoCommit}=1;
    $this->{dbh}->{PrintError} = $this->{old_pe}; # restore error attributes
    $this->{dbh}->{RaiseError} = $this->{old_re};
    $$this{raise_exception}=$$this{older_exception_mod};
}

sub rollback {
    my $this=shift;
    $this->{dbh}->rollback();
    $this->{dbh}->{PrintError} = $this->{old_pe}; # restore error attributes
    $this->{dbh}->{RaiseError} = $this->{old_re};
    $this->log_msg("database error : " . $this->{dbh}->errstr . $@) ;
    print "database error : " . $this->{dbh}->errstr . " " .$@."\n";
}
#-----------------------------------------------------------------

#-----------------------------------------------------------------

sub execute_with_param {
    my $this    = shift;
    my $query   = shift;
    my $param   = shift;
    my $i       = 1;
    my $sth     = $this->{dbh}->prepare($query);
    if(!$sth && $this->{dbh}->{AutoCommit}==1){
        die "Error:" . $this->{dbh}->errstr . "\n";
    }

    foreach (@$param){
        $sth->bind_param($i++, $_);
    }

    if ($this->{dbh}->{AutoCommit}==0){
        $sth->execute();
    }
    else{
        eval {$sth->execute()or die("cant execute");};
        print $@."\nerror to execute : \n$query\n" if $@;
        $this->log_msg($query." failed") if $@;
    }

    return $sth;
}

#-----------------------------------------------------------------

sub execute {
    my ($this, $query) = (shift, shift);
    my $sth = $this->{dbh}->prepare($query);
	die $@."\nerror to prepare : \n$query\n" if $@;
    if ($this->{dbh}->{AutoCommit}==0){
        $sth->execute();
    }
    else{
        eval {$sth->execute()or die("cant execute");};
        print $@."\nerror to execute : \n$query\n" if $@;
        $this->log_msg($query." failed") if $@;
    }

    return $sth;
}


sub finish {
    shift->{dbh}->finish();
}

#-----------------------------------------------------------------

sub disconnect {
    my $this = shift;
    $this->{dbh}->disconnect();
}

#-----------------------------------------------------------------

sub DESTROY {
    my $this=shift;
    $this->disconnect();
}

#-----------------------------------------------------------------

sub insert_id {
    my $this=shift;
    $this->log_msg("Cacti::Database::insert_id is deprecated");
    return $this->last_insert_id();
}

sub last_insert_id {
    my $this=shift;
    return $this->{dbh}->{ q{mysql_insertid}};
#    return  $this->{dbh}->last_insert_id(undef, undef, shift, undef);
}

#-----------------------------------------------------------------

sub db_fetch_cell {
    my $this    = shift;
    my $sql     = shift;
    my $sth     = $this->execute($sql);
    while(my @row = $sth->fetchrow()){
        $sth->finish();
        return $row[0];
    }
    die "DATABASE - no data collected" if ($$this{raise_exception} !=0);
    return undef;
}

sub db_fetch_hash_sql{
    my $this    = shift;
    my $sql     = shift;
    my $sth = $this->execute($sql);
    while(my $row = $sth->fetchrow_hashref()){
        $sth->finish();
        return $row;
    }
    die "DATABASE - NO RESULT" if ($$this{raise_exception} !=0);
    return undef;
}

#-- verify if the item exist
sub item_exist {
	my $this	= shift;
	my $table 	= shift; # nom de la table
	my $fields	= shift; # { nomduchamps => valeur}
	my $sql 	= "SELECT count(*) FROM $table WHERE";
	while (my ($field, $value) = each (%$fields) ) {
		$sql.=" $field = '$value' AND";
	}
	$sql =~ s/WHERE$//g;
	$sql =~ s/AND$//g;
	
	try {
	    $$this{older_exception_mod}=$$this{raise_exception};
		$$this{raise_exception}=1;
		my $value= $this->db_fetch_cell( $sql);
		$$this{raise_exception}=$$this{older_exception_mod};
		return $value;
	}
	catch Error::Simple with{ # we return false in this case and put a warning into the log file
		$this->log_msg("N2Cacti::Data::item_exist - undefined error");
		return 0;
	};
}

# -- retourne un hash 
sub db_fetch_hash {
    my $this    = shift;
    my $table   = shift; # nom de la table
    my $fields  = shift; # { nomduchamps => valeur}
    my $debug 	= shift||0;
    my $sql     = "SELECT * FROM $table WHERE";
    while (my ($field, $value) = each (%$fields) ) {
        $sql.=" $field = '$value' AND";
    }
    $sql =~ s/WHERE$//g;
    $sql =~ s/AND$//g;
    $this->log_msg(__LINE__."\t:$sql")if $debug;
    my $sth = $this->execute($sql);
    while(my $row = $sth->fetchrow_hashref()){
        $sth->finish();
        return $row;
    }
    die "DATABASE - NO RESULT - from table $table" if ($$this{raise_exception}!=0);
}


#----------------------------------------------------------


sub get_id {
    my $this    = shift;
    my $table   = shift; # nom de la table
    my $fields  = shift; # { nomduchamps => valeur}
    my $id      = shift||"id"; # champs a retourner
    my $sql     = "SELECT $id FROM $table WHERE";
    while (my ($field, $value) = each (%$fields) ) {
        $sql.=" $field = '$value' AND";
    }
    $sql =~ s/WHERE$//g;
    $sql =~ s/AND$//g;
	my $result;
	try {
		return  $this->db_fetch_cell( $sql);
	}catch Error::Simple with{
		$this->log_msg("$sql return no result");
		die "$sql return no result";
	}
}

#----------------------------------------------------------
# new_hash extract table structure in hash, the key of hash are the row name
sub new_hash {
    my $this    = shift;
    my $table   = shift;
    my $result  = {};
    my $sql     = "SELECT * FROM $table LIMIT 0";
    my $sth     = $this->execute($sql);
    foreach (@{$sth->{NAME}}){
        $result->{$_}="";
    }
    $sth->finish();
    return $result;

}

#---------------------------------------------------------
#/* sql_save - saves data to an sql table
#   @arg $array_items - an array containing each column -> value mapping in the row
#   @arg $table_name - the name of the table to make the replacement in
#   @arg $key_cols - the primary key(s)
#   @returns - the auto incriment id column (if applicable) */
sub sql_save {
    my $this        = shift;
    my $array_items = shift;
    my $table_name  = shift;
    my $id          = shift||"id";
    my $sql = "REPLACE $table_name (";
    my $data = "";
    my $parametre=[];
    my $i=0;
    while (my ($key, $value) = each (%$array_items)) {
        $value =~ s/;//g;
        $sql.=$key.",";
        $data.="?,";
        push @$parametre,$value;
    }

    $sql    =~  s/.$//g;
    $data   =~  s/.$//g;
    $sql.=") VALUES ($data)";
    $this->execute_with_param($sql, $parametre);
    return $this->last_insert_id($table_name);
}

sub table_save {
	my ($this, $table, $data)= (@_);
	return $this->sql_save($data,$table);
}

sub table_create {
	my $this 	= shift;
	my $table	= shift;
	my $fields 	= shift;
	
	my $query = "CREATE TABLE IF NOT EXISTS $table (";
	while (my ($key, $value) = each (%$fields)){
		$query .= "$key $value,";
	}
	$query =~ s/,$/)/g;
	$query .= " ENGINE=MYISAM DEFAULT CHARSET=latin1;";
	$this->execute($query);	
}

#sub try (&@) {
#	my($try,$catch) = @_;
#	eval { &$try };
#	if ($@) {
#	    local $_ = $@;
#	    &$catch;
#	}
#}
#
#sub catch (&) { $_[0] }
#
#    try {
#	die "phooey";
#    } catch {
#	/phooey/ and print "unphooey\n";
#    };  

1;
