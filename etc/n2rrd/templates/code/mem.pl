#
# This is just anexample perl code
# which demonstrates parsing a non standard preformance data
# value and pass the modified string to n2rrd for further processing
#
# see Nagios documentation for  Environment variables passed to plugins 
#

my $tmp_pdata = "";

if ( $ENV{NAGIOS_SERVICEPERFDATA} ) {
        $tmp_pdata = $ENV{NAGIOS_SERVICEPERFDATA};
}

#
# return string in following space seperated format
#  ds_name=ds_value [ds_name=ds_value] ..
return $tmp_pdata;


