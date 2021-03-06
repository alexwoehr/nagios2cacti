# tsync:: casole
# sync:: calci
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

BEGIN {
        use Exporter   	();
        use vars       	qw($VERSION @ISA @EXPORT @EXPORT_OK);
        @ISA 		=	qw(Exporter);
}

#
# new
#
# The constructor
#
# @args		: the class name and the parameters
# @return	: the object
#
sub new {
	my $class	= shift;
	my $attr	= shift;

	my %param	= %$attr if $attr;
	my $this	= {
        	database_type 		=> $param{database_type} || "mysql",
	        database_schema 	=> $param{database_schema} || "cacti",
	        database_hostname 	=> $param{database_hostname} || "localhost",
	        database_username 	=> $param{database_username} || "user",
	        database_password 	=> $param{database_password} || "password",
	        database_port 		=> $param{database_port} || "3306",
		raise_exception		=> $param{raise_exception} || 0,
		older_exception_mod	=> 0,
	};
	bless($this,$class);
	$this->connect();
	return $this;
}

#
# connect
# 
# Creates the DBH
#
# @args		: none
# @return	: the DBH object
#
sub connect {
	my $this = shift;

	$this->{dbh} = undef;

	if ($this->{database_type} eq "mysql"){
		$this->{dbh} = DBI->connect (
			"DBI:mysql:database=".$this->{database_schema}.";".
			"host=".$this->{database_hostname},
			$this->{database_username},
			$this->{database_password},
			{RaiseError => 1,PrintError => 1,AutoCommit => 1}
		) or Main::log_msg("N2Cacti::database::connect(): cannot connect to database : $DBI::errstr", "LOG_CRIT") and return undef;

		$this->{dbh}->do("use $$this{database_schema}");

	} elsif ($this->{database_type} eq "sybase" || $this->{database_type} eq "sqlserver") {
		$this->{dbh} = DBI->connect(
			"DBI:Sybase:server=$$this{database_hostname}",
			$$this{database_username},
			$$this{database_password},
			{RaiseError => 1, PrintError => 1, AutoCommit => 1}
		) or Main::log_msg("N2Cacti::database::connect(): cannot connect to database : $DBI::errstr", "LOG_CRIT") and return undef;

		$this->{dbh}->do("use $$this{database_schema}");

	} elsif ($this->{database_type} eq "pg" || $this->{database_type} =~ "postgres") {
			$this->{dbh} = DBI->connect("DBI:Pg:server=$$this{database_hostname}",
			$$this{database_username},
			$$this{database_password},
			{RaiseError => 1, PrintError => 1, AutoCommit => 1}
		) or Main::log_msg("N2Cacti::database::connect(): cannot connect to database : $DBI::errstr", "LOG_CRIT") and return undef;

		$this->{dbh}->do("use $$this{database_schema}");

	} elsif ($this->{database_type} =~ /oracle/i){
		$this->{dbh} = DBI->connect("DBI:Oracle:host=$$this{database_hostname};port=$$this{database_port};sid=$$this{database_schema};",
			$this->{database_username},
			$this->{database_password},
			{RaiseError => 1, PrintError => 1, AutoCommit => 1}
		) or Main::log_msg("N2Cacti::database::connect(): cannot connect to database : $DBI::errstr", "LOG_CRIT") and return undef;
	}

	return $this->{dbh};
}

#
# begin
#
# Sets DBH's options
#
# http://www.informit.com/articles/article.asp?p=23412&rl=1
# http://www.mathematik.uni-ulm.de/help/perl5/doc/DBD/mysql.html
#
# @args		: none
# @return	: OK (1) || KO (0)
#
sub begin {
	my $this	= shift;

	$this->{old_pe} = $this->{dbh}->{PrintError}; # save and reset
	$this->{old_re} = $this->{dbh}->{RaiseError}; # error-handling

	$this->{dbh}->{PrintError} = 0;    # attributes
	$this->{dbh}->{RaiseError} = 1;
	$this->{dbh}->{AutoCommit} = 0;

	if ($this->{dbh}->{'AutoCommit'}) {
		Main::log_msg('N2Cacti::database::begin(): An error occured while passing transaction mode', "LOG_CRIT");
		return 0;
	}

	return 1;
}

#
# end
#
# Commit or rollback
#
# @args		: none
# @return	: commit (1) || rollback (0)
#
sub end {
	my $this	= shift;

	if ($@){
		$this->{dbh}->rollback();
		return 0;
	}

	$this->commit();
	return 1;
}

#
# commit
#
# Commits...
#
# @args		: none
# @return	: none
#
sub commit {
	my $this	= shift;

	$this->{dbh}->commit();
	$this->{dbh}->{AutoCommit} = 1;
	$this->{dbh}->{PrintError} = $this->{old_pe}; # restore error attributes
	$this->{dbh}->{RaiseError} = $this->{old_re};

	$$this{raise_exception} = $$this{older_exception_mod};
}

#
# rollback
#
# Rollback..
#
# @args		: none
# @return	: none
#
sub rollback {
	my $this	= shift;

	$this->{dbh}->rollback();
	$this->{dbh}->{PrintError} = $this->{old_pe}; # restore error attributes
	$this->{dbh}->{RaiseError} = $this->{old_re};

	Main::log_msg("N2Cacti::database:rollback: database error : " . $this->{dbh}->errstr . $@, "LOG_ERR");
}

#
# execute_with_param
#
# Executes a prepated query with the given parameters
#
# @args		: the query and the params
# @return	: the STH
#
sub execute_with_param {
	my $this    = shift;
	my $query   = shift;
	my $param   = shift;

	my $i       = 1;

        Main::log_msg("--> N2Cacti::database:execute_with_param()", "LOG_DEBUG");

        Main::log_msg("N2Cacti::database:execute_with_param(): prepare : $query", "LOG_DEBUG");
	my $sth = $this->{dbh}->prepare($query);

	if ( ! $sth && $this->{dbh}->{AutoCommit} == 1 ) {
		Main::log_msg("N2Cacti::database:execute_with_param(): error:" . $this->{dbh}->errstr . "\n", "LOG_ERR");
	}

	foreach (@$param){
		$sth->bind_param($i++, $_);
	}

	if ($this->{dbh}->{AutoCommit}==0){
		$sth->execute();
	} else{
		$sth->execute();
		Main::log_msg("N2Cacti::database:execute_with_param(): $query failed", "LOG_ERR") if $@;
	}

        Main::log_msg("<-- N2Cacti::database:execute_with_param()", "LOG_DEBUG");
	return $sth;
}

#
# execute
#
# Executes a query
#
# @args		: the query
# @return	: the STH
#
sub execute {
	my ($this, $query) = (shift, shift);

	Main::log_msg("--> N2Cacti::database::execute()", "LOG_DEBUG");
	Main::log_msg("N2Cacti::database::execute(): query : $query", "LOG_DEBUG");
	my $sth = $this->{dbh}->prepare($query);

	Main::log_msg("N2Cacti::database::execute(): cannot prepare $query : $@", "LOG_ERR") if $@;

	if ($this->{dbh}->{AutoCommit}==0){
		$sth->execute();
	} else {
		$sth->execute();
		Main::log_msg("N2Cacti::database::execute(): cannot execute $query : $@", "LOG_ERR") if $@;
	}

	Main::log_msg("<-- N2Cacti::database::execute()", "LOG_DEBUG");
	return $sth;
}

#
# finish
#
# Calls dbh->finish()
#
# @args 	: none
# @return	: none
#
sub finish {
	shift->{dbh}->finish();
}

#
# disconnect
#
# Calls dbh->disconnect()
#
# @args		: none
# @return	: none
#
sub disconnect {
	my $this	= shift;

	$this->{dbh}->disconnect();
}

#
# DESTROY
#
# The destructor
#
sub DESTROY {
	my $this	= shift;

	$this->disconnect();
}

#
# insert_id
#
# Gets the last_insert_id
#
# @args		: none
# @return	: the id
#
sub insert_id {
	my $this=shift;

	Main::log_msg("N2Cacti::Cacti::Database::insert_id() is deprecated", "LOG_DEBUG");

	return $this->last_insert_id();
}

#
# last_insert_id
#
# Gets the last_insert_id
#
# @args		: none
# @return	: the id
#
sub last_insert_id {
	my $this=shift;

	return $this->{dbh}->{ q{mysql_insertid}};
#	return  $this->{dbh}->last_insert_id(undef, undef, shift, undef);
}

#
# db_fetch_cell
#
# Gets the result cell
#
# @args		: the query
# @return	: the cell (OK) || undef (KO)
#
sub db_fetch_cell {
	my $this	= shift;
	my $sql		= shift;

	my $sth 	= $this->execute($sql);

	while ( my @row = $sth->fetchrow() ) {
		$sth->finish();
		return $row[0];
	}

	Main::log_msg("N2Cacti::database:db_fetch_cell(): no data fetched", "LOG_ERR") if ($$this{raise_exception} !=0 );

	return undef;
}

#
# db_fetch_hash_sql
#
# Gets the hash result
#
# @args		: the query and the key
# @return	: the hash ref
#
sub db_fetch_hash_sql {
	my $this	= shift;
	my $sql		= shift;
	my $key		= shift;

	my $rs		= {};
	my $sth		= $this->execute($sql);

	$rs = $sth->fetchall_hashref($key);
	$sth->finish();

	Main::log_msg("N2Cacti::database:db_fetch_hash_sql(): no hash fetched", "LOG_ERR") if ( $$this{raise_exception} != 0 );

	return $rs;
}

#
# db_fetch_array_sql
#
# Gets the array result
#
# @args		: the query and the key
# @return	: the array ref
#
sub db_fetch_array_sql {
	my $this = shift;
	my $sql = shift;
	my $key = shift;

	my $rs = {};
	my $sth = $this->execute($sql);

	$rs = $sth->fetchall_arrayref($key);
	$sth->finish();

	Main::log_msg("N2Cacti::database:db_fetch_array_sql(): no hash fetched", "LOG_ERR") if ( $$this{raise_exception} != 0 );

	return $rs;
}

#
# item_exist
#
# Checks if an item exists
#
# @args		: the table and the fields hash { field => value }
# @return	: yes (1) || no (0)
#
sub item_exist {
	my $this	= shift;
	my $table	= shift;
	my $fields	= shift;

	my $sql = "SELECT count(*) FROM $table WHERE";

	Main::log_msg("--> N2Cacti::Data::item_exist()", "LOG_DEBUG");

	while (my ($field, $value) = each (%$fields) ) {
		$sql.=" $field = '$value' AND";
	}

	$sql =~ s/WHERE$//g;
	$sql =~ s/AND$//g;
	
	Main::log_msg("N2Cacti::Data::item_exist(): $sql", "LOG_DEBUG");

	my $value = $this->db_fetch_cell($sql);

	if ( $value !~ /\d+/ ) { 
		Main::log_msg("N2Cacti::Data::item_exist(): the query did not return a scalar", "LOG_DEBUG");
		return undef;
	} else {
		Main::log_msg("N2Cacti::Data::item_exist(): value = $value", "LOG_DEBUG");
	}

	Main::log_msg("<-- N2Cacti::Data::item_exist()", "LOG_DEBUG");

	if ( $value == 0 ) {
		return 0;
	}

	return 1;
}

#
# db_fetch_hash
#
# Returns a SQL hash
#
# @args		: the table and the fields hash { field => value }
# @return	: the SQL hash or undef
#
sub db_fetch_hash {
	my $this	= shift;
	my $table	= shift;
	my $fields	= shift;

	my $sql = "SELECT * FROM $table WHERE";

	Main::log_msg("--> N2Cacti::database::db_fetch_hash()", "LOG_DEBUG");

	while (my ($field, $value) = each (%$fields) ) {
		$sql.=" $field = '$value' AND";
	}

	$sql =~ s/WHERE$//g;
	$sql =~ s/AND$//g;

	Main::log_msg("N2Cacti::database::db_fetch_hash(): query: $sql", "LOG_DEBUG");

	my $sth = $this->execute($sql);

	while(my $row = $sth->fetchrow_hashref()){
		$sth->finish();
		Main::log_msg("<-- N2Cacti::database::db_fetch_hash()", "LOG_DEBUG");
		return $row;
	}

	Main::log_msg("N2Cacti::database::db_fetch_hash(): no data from table $table", "LOG_ERR");
	return undef;
}

#
# get_id
#
# Returns the id
#
# @args		: the table, the fields hash { field => value } and the field to return
# @return	: the id or undef
#
sub get_id {
	my $this	= shift;
	my $table	= shift;
	my $fields	= shift; 
	my $id		= shift||"id";

	my $sql = "SELECT $id FROM $table WHERE";

	Main::log_msg("--> N2Cacti::Data::get_id()", "LOG_DEBUG");

	while (my ($field, $value) = each (%$fields) ) {
		$sql.=" $field = '$value' AND";
	}

	$sql =~ s/WHERE$//g;
	$sql =~ s/AND$//g;

	Main::log_msg("N2Cacti::Data::get_id - $sql", "LOG_DEBUG");
	my $result;
	$result = $this->db_fetch_cell( $sql);

	if ( not scalar $result ) {
		Main::log_msg("N2Cacti::Data::get_id(): $sql returned no result", "LOG_DEBUG");
		Main::log_msg("<-- N2Cacti::Data::get_id()", "LOG_DEBUG");
		return undef;
	}

	Main::log_msg("<-- N2Cacti::Data::get_id()", "LOG_DEBUG");
	return $result;
}

#
# new_hash
#
# Extract table structure in hash, the key of hash are the row name
#
# @args		: the table
# @return	: the hash
#
sub new_hash {
	my $this	= shift;
	my $table	= shift;

	my $result	= {};
	my $sql		= "SELECT * FROM $table LIMIT 0";
	my $sth		= $this->execute($sql);

	Main::log_msg("--> N2Cacti::Data::new_hash()", "LOG_DEBUG");
	Main::log_msg("N2Cacti::Data::new_hash(): $sql", "LOG_DEBUG");

	foreach (@{$sth->{NAME}}){
		$result->{$_} = "";
	}

	$sth->finish();

	Main::log_msg("<-- N2Cacti::Data::new_hash()", "LOG_DEBUG");
	return $result;
}

#
# sql_save
#
# Saves data to an sql table
#
#  @args	: $array_items - an array containing each column -> value mapping in the row
#  @args	: $table_name - the name of the table to make the replacement in
#  @args	: $key_cols - the primary key(s)
#  @returns	: the auto incriment id column (if applicable) */
#
sub sql_save {
	my $this        = shift;
	my $array_items = shift;
	my $table_name  = shift;
	my $id          = shift||"id";

	my $sql = "REPLACE $table_name (";
	my $data = "";
	my $i=0;

	Main::log_msg("--> N2Cacti::Data::sql_save()", "LOG_DEBUG");

	while (my ($key, $value) = each (%$array_items)) {
		$value =~ s/;//g;
		$sql.=$key.",";
		$data.="'$value',";
	}

	$sql    =~  s/.$//g;
	$data   =~  s/.$//g;
	$sql.=") VALUES ($data)";

	Main::log_msg("N2Cacti::Data::sql_save(): query:  $sql", "LOG_DEBUG");

	$this->execute($sql);

	Main::log_msg("<-- N2Cacti::Data::sql_save()", "LOG_DEBUG");
	return $this->last_insert_id($table_name);
}

#
# table_save
#
# Save the data calling sql_save
#
# @args		: the table and the data
# @return	: sql_save result
#
sub table_save {
	my ($this, $table, $data)= (@_);
	return $this->sql_save($data,$table);
}

#
# table_create
#
# Creates the given table using the given fields
#
# @args		: the table and the given fields
# @return	: none
#
sub table_create {
	my $this 	= shift;
	my $table	= shift;
	my $fields 	= shift;

	my $query = "CREATE TABLE IF NOT EXISTS $table (";

	Main::log_msg("--> N2Cacti::database::table_create()", "LOG_DEBUG");

	while (my ($key, $value) = each (%$fields)){
		$query .= "$key $value,";
	}
	$query =~ s/,$/)/g;
	$query .= " ENGINE=MYISAM DEFAULT CHARSET=latin1;";

	Main::log_msg("N2Cacti::database(): $query", "LOG_DEBUG");
	$this->execute($query);	
	Main::log_msg("<-- N2Cacti::database::table_create()", "LOG_DEBUG");
}

1;

