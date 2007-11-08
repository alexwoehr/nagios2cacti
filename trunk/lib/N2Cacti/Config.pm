###########################################################################
#                                                                         #
# N2Cacti::Config                                                         #
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


use strict;

use Date::Manip;
package N2Cacti::Config;
   
BEGIN {
        use Exporter   ();
        use vars       qw($VERSION @ISA @EXPORT @EXPORT_OK);
		@ISA = qw(Exporter);
		@EXPORT = qw($config load_config log_msg get_config set_process_name);
}

our $config={
	CONF_DIR => "/etc/n2rrd",
    TEMPLATES_DIR => "templates",
    SERVICE_NAME_MAPS => "templates/maps/service_name_maps",
    ZOOM_JS => "js/zoom.js",
    RRA_DIR  => "/var/log/monitor/n2rrd/rra",
    LOGFILE => "/var/log/monitor/n2rrd/rra/n2rrd.log",
    DOCUMENT_ROOT => "/var/www/html",
    CACHE_DIR   => "rrd-images",
    RRDTOOL => "/usr/bin/rrdtool",
    RRD_PATH_HIDDEN => 0,
    NAGIOS_HOST_URL => 1,
    THUMB_WIDTH => 200,
    THUMB_HEIGHT => 100,
    THUMB_DISPLAY => "Daily",
    THUMB_DISPLAY_COLUMNS => 3,
    TMPDIR => "/tmp",
    CGIBIN => "cgi-bin",
    NAGIOS_CGIBIN => "nagios/cgi-bin",
    CACTI_DIR => "/var/www/cacti",
    OREON_DIR => "/usr/lib/oreon",
    NAGIOS_CONF_DIR => "/etc/nagios",
	TEMPLATE_SEPARATOR_FIELD => "@",
    HOST_PERFDATA_PIPE => "/var/log/nagios/host-perfdata.dat",
    SERVICE_PERFDATA_PIPE => "/var/log/nagios/perfdata.pipe",
    HOST_PERFDATA_FILE => "/var/log/nagios/host-perfdata.dat",
    SERVICE_PERFDATA_FILE => "/var/log/nagios/perfdata.pipe",
	ARCHIVE_DIR => "/var/log/nagios/archives/perfdata",
    ROTATION => "h", #rotation every hours (h) day (d) week (w)
	PID_FILE => "/var/run/perf2rrd.pid",
	PERFDB_NAME => "db_perfdata",
	PERFDB_USER => "prod",
	PERFDB_PASSWORD => "prod",
	PERFDB_HOST => "localhost",
	DEFAULT_RRA	=> "default.T",
	GRAPH_ITEM_TYPE => "AREA",
	GRAPH_ITEM_COLORS =>"", # "" to have random color for all graph
};

my $config_loaded=0;

our $process_name = "N2Cacti";

sub get_config {
	if($config_loaded==0){
		return load_config(shift or "/etc/n2rrd/n2rrd.conf");
	}
	return $config;
}



sub load_config {
    my $config_file = shift;
    my $line   		= 0;
	$config_loaded	= 1;

    open CONF, '<', "$config_file"
      or die "Can't open configuration file -> \"$config_file\":$!\n";

    #
    # Parse configuration file
    while (<CONF>) {
        $line++;  # note confirguration file line number
        chomp;    # Remove newline character
        s/ //g;    # remove spaces
        next if /^#/;    # Skip comments
        next if /^$/;    # Skip empty lines
        s/#.*//;         # Remove partial comments

        if (/^(.*)=(.*)$/) {
	        if (defined $config->{$1}) {
                $config->{$1} = $2;
            }
            else {    # A warning should be ok
    #            log_msg( "WARNING: Unknown global variable declaration in line $line:\"$1 = $2\"\n" );
            }
        }
    }
    close CONF;
	return $config;
}

sub log_msg {
    my $str = shift;
    $str =~ s/\n$//g;
    $str =~ s/$/\n/g;

	get_config() if ($config_loaded==0);

    open L, '>>', $config->{LOGFILE}
      or die "Can't open logfile \"".$config->{LOGFILE}."\"";

    open STDERR, '>&L';# dup STDERR

    print L "$process_name: $str";
	print "$process_name: $str";
    close L;
}

sub set_process_name {
	$process_name=shift;
}

1;
