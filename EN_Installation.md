# Introduction #

**Nagios2Cacti** is a gateway between the supervised tools Nagios and the frontend RRDToll Cacti . It enable to use : Nagios to schedule the host and service checks and Cacti to generate the performance graph.

# Download source code #

you can download the last nagios2cacti version directly in the developpement SVN :
` svn checkout http://nagios2cacti.googlecode.com/svn/trunk/ nagios2cacti-read-only `

or, you can download the last archive :
[download](http://code.google.com/p/nagios2cacti/downloads/list)

# PERL librairy configuration #
required packages;
```
perl
perl-datemanip
perl-Net-Server
perl-error
```


you can use your package application of your distribution or use the CPAN command :
`perl -MCPAN -e 'install Error'`


# Installation instruction #
installation instruction :
```
# cd
# svn checkout http://nagios2cacti.googlecode.com/svn/trunk/ nagios2cacti-read-only
# cd nagios2cacti-read-only/
# mv etc/n2rrd/ /etc
# cd /etc/n2rrd/
# cp dist-n2rrd.conf n2rrd.conf
# cd
# cp -R nagios2cacti-read-only /usr/lib/N2Cacti
# chmod +x /usr/lib/N2Cacti/*.pl
```
next step, you will customize your configuration file for your specific installation (see the next part of this documentation)


# Communication method #

there're two method to communicate between Nagios and nagios2cacti:
**named pipe** UDP

## PIPE ##
This method is lighter, nagios write in a pipe and the server **perf2rrd** read these datas, proceed them and update RRDtool database and cacti configuration. If **perf2rrd** crash for any reason (filesystem full..),  these datas’ll be lost and graph'll have some hole because the PIPE cant bufferize the data.


## UDP ##
This method is safer. Nagios is configured to execute a command to handle the perfdata after the check execution. These command write the datas in a folder with a file by indicator. The file is deleted when all datas are transfered  with success. If the transfer failed, the data will be keep in files and will be proceed when the communication will be success.

# Configuration #
## Installation folder ##
The configuration files for nagios2cacti must be copied in /etc/n2rrd, with in the root of this folder the n2rrd.conf file and the templates folder.
by default, the software part must to be installed in /usr/lib/N2Cacti folder.

## N2RRD Configuration ##
### Configuration file : /etc/n2rrd/n2rrd.conf ###
Important variable list to configure in the file :
> /etc/n2rrd/n2rrd.conf
```
* CACTI_DIR : Path to root folder of cacti
* OREON_DIR : Path to root folder of oreon
* NAGIOS_CONF_DIR : Path to configuration folder of  Nagios,  /etc/nagios/ by default
* ROTATION : Rotation mode : d for daily, h for hour, n for none
* PID_FILE : path to PID file when *perf2rrd.pl* or *server_perf.pl* are started in daemon mode.
* SERVICE_PERFDATA_PIPE : Path to the named pipe (perf2rrd)
* PERFDB_NAME : database name use for PERFDB (optionnal)
* PERFDB_USER : user
* PERFDB_PASSWORD : password
* PERFDB_HOST : nom du serveur
* TEMPLATE_SEPARATOR_FIELD : "@" by default to differentiate servicename and template name, example : cpu_pload@CPULOAD
```

### Configuration templates ###
Template are in the folder :
> /etc/n2rrd/templates/rra

**Example with value added warn and crit:**
```
 WSC_CPU.t
 -s 300 # steps 5minutes
 DS:cpu:GAUGE:1200:0:U
 DS:cpu_warn:GAUGE:1200:0:U
 DS:cpu_crit:GAUGE:1200:0:U
 RRA:AVERAGE:0.25:1:4320   #day
 RRA:AVERAGE:0.25:6:1680   #week
 RRA:AVERAGE:0.25:24:1800  #month
 RRA:AVERAGE:0.25:288:1825 #year
 RRA:MAX:0.25:1:4320   #day
 RRA:MAX:0.25:6:1680   #week
 RRA:MAX:0.25:24:1800  #month
 RRA:MAX:0.25:288:1825 #year
 RRA:MIN:0.25:1:4320   #day
 RRA:MIN:0.25:6:1680   #week
 RRA:MIN:0.25:24:1800  #month
 RRA:MIN:0.25:288:1825 #year
```
**Example with value added max and min:**
```
-s 300 # steps 5minutes
DS:Free_PMem:GAUGE:1200:0:U
DS:Free_PMem_min:GAUGE:1200:0:U
DS:Free_PMem_max:GAUGE:1200:0:U
DS:Free_VMem:GAUGE:1200:0:U
DS:Free_VMem_min:GAUGE:1200:0:U
DS:Free_VMem_max:GAUGE:1200:0:U
RRA:AVERAGE:0.25:1:4320   #day
RRA:AVERAGE:0.25:6:1680   #week
RRA:AVERAGE:0.25:24:1800  #month
RRA:AVERAGE:0.25:288:1825 #year
RRA:MAX:0.25:1:4320   #day
RRA:MAX:0.25:6:1680   #week
RRA:MAX:0.25:24:1800  #month
RRA:MAX:0.25:288:1825 #year
RRA:MIN:0.25:1:4320   #day
RRA:MIN:0.25:6:1680   #week
RRA:MIN:0.25:24:1800  #month
RRA:MIN:0.25:288:1825 #year
```

### Configuration rewrite ###
There is two method to rewrite, the filename format  :


&lt;HOSTNAME&gt;



&lt;TEMPLATENAME&gt;

_rewrite :  for indicator


&lt;TEMPLATENAME&gt;

**rewrite : for service**

The file syntax is :
```
 ds_name         iso.3.6.1.4.1.791.2.9.4.5.2.3.1.0           1_minute
 ds_name         iso.3.6.1.4.1.791.2.9.4.5.2.3.6.0                       5_minutes
 ds_name         iso.3.6.1.4.1.791.2.9.4.5.2.3.11.0                      15_minutes
 ds_name         iso.3.6.1.4.1.791.2.9.4.5.2.2.13.0              cores
 #
 # change file name location
 #
 rrd_file        /var/log/nagios/rra/<HOSTNAME>_<SERVICENAME>.rrd
```_

## Configuration Cacti ##
**perf2rrd.pl** et **server\_perf.pl** must access in read the file :
` $CACTI_DIR$/include/config.php `

nagios2cacti read in this file the parameter to connect to the database Cacti.

## Configuration Oreon (FACULTATIF) ##
**perf2rrd.pl** et **server\_perf.pl** must access in read the file:
` $OREON_DIR$/oreon.conf.php `
nagios2cacti read in this file the parameter to connect to the database Oreon. These feature store in MySQL  database the perfdata and require Oreon.

## Configuration de Nagios ##

### Configuration for the PIPE ###
**/etc/nagios/nagios.cfg
```
 process_performance_data=1
 service_perfdata_file=/var/log/nagios/perfdata.pipe
 service_perfdata_file_template=[SERVICEPERFDATA]|$SERVICEDESC$|$HOSTNAME$|$HOSTADDRESS$|$TIMET$|$SERVICEEXECUTIONTIME$|$SERVICELATENCY$|$SERVICESTATE$|$SERVICEOUTPUT$|$SERVICEPERFDATA$
 service_perfdata_file_mode=w
```**

### Configuration for UDP ###
**/etc/nagios/nagios.cfg
```
 process_performance_data=1
 service_perfdata_command=send_perfdata_udp
```** /etc/nagios/checkcommand.cfg
```
 define command{
    command_name            send_perfdata_udp
    command_line            /usr/lib/N2Cacti/send_perf.pl -d  "[SERVICEPERFDATA]|$SERVICEDESC$|$HOSTNAME$|$HOSTADDRESS$|$TIMET$|$SERVICEEXECUTIONTIME$|$SERVICELATENCY$|$SERVICESTATE$|$SERVICEOUTPUT$|$SERVICEPERFDATA$"  -p 2080 -H localhost
 }
```
### Configuration servicename ###
The syntaxe of service name in Nagios configuration, or use mapping file :
SERVICENAME@TEMPLATENAME
Or use mapping file in N2RRD :
> /etc/n2rrd/templates/maps/service\_name\_maps
```
Nagios SERVICE NAME: N2RRD TEMPLATE NAME
```
Warning : the Template Name in N2RRD is not the Template in Nagios.
Alot of service can have the same template N2RRD.
The graph will name : 

&lt;HOSTNAME&gt;

 - 

&lt;SERVICENAME&gt;


The graph template will name : Nagios - 

&lt;SERVICENAME&gt;



TEMPLATENAME will able to recover N2RRD configuration
```
 templates/rra/TEMPLATENAME.t
 templates/rewrite/service/TEMPLATENAME_rewrite
```

# start daemon #

## Method UDP ##
```
/usr/lib/N2Cacti/server_perf.pl -u -d -c /etc/n2rrd/n2rrd.conf -p2080
-m enable mysql support
-d daemonize 
-c file configuration
-p UDP port
-v verbose (to debug)
```
## Method PIPE ##
```
/usr/lib/N2Cacti/perf2rrd.pl -u -d -c /etc/n2rrd/n2rrd.conf
-m enable mysql support
-d daemonize 
-c configuration file
-v verbose (to debug)
```