###########################################################################
#                                                                         #
# N2Cacti::Time                                                           #
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
package N2Cacti::Time;

BEGIN {
	use Exporter   ();
	use vars       qw($VERSION @ISA @EXPORT @EXPORT_OK);
	@ISA = qw(Exporter);
	@EXPORT = qw(get_time_forday);
}   

sub get_time_forday {
	my $date = shift;
	my $time = shift;
	return &Date::Manip::UnixDate(&Date::Manip::ParseDate($date." ".$time),"%s");
}

1;

