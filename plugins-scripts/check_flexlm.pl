#! /usr/bin/perl -w
#
# usage: 
#    check_flexlm.pl license_file
#
# Check available flexlm license managers.
# Use lmstat to check the status of the license server
# described by the license file given as argument.
# Check and interpret the output of lmstat
# and create returncodes and output.
#
# Contrary to the nagios concept, this script takes
# a file, not a hostname as an argument and returns
# the status of hosts and services described in that
# file. Use these hosts.cfg entries as an example
#
#host[anchor]=any host will do;some.address.com;;check-host-alive;3;120;24x7;1;1;1;
#service[anchor]=yodel;24x7;3;5;5;unix-admin;60;24x7;1;1;1;;check_flexlm!/opt/lic/licfiles/yodel_lic
#service[anchor]=yeehaw;24x7;3;5;5;unix-admin;60;24x7;1;1;1;;check_flexlm!/opt/lic/licfiles/yeehaw_lic
#command[check_flexlm]=/some/path/libexec/check_flexlm.pl $ARG1$
#
# Notes:
# - you need the lmstat utility which comes with flexlm.
# - set the correct path in the variable $lmstat.
#
# initial version: 9-10-99 Ernst-Dieter Martin edmt@infineon.com
#
# License: GPL
#
# lmstat output patches from Steve Rigler/Cliff Rice 13-Apr-2002
# srigler@marathonoil.com,cerice@marathonoil.com


use strict;
use Getopt::Long;
use vars qw($opt_V $opt_h $opt_F $opt_t $opt_w $opt_c $verbose $PROGNAME);
use lib "/usr/local/nagios/libexec" ;
use utils qw(%ERRORS &print_revision &support &usage);
use File::Basename;
use Date::Manip;

$PROGNAME="check_flexlm";

use constant {
    WARN => 30,
    CRIT => 0,
};

sub print_help ();
sub print_usage ();

#$ENV{'PATH'}='';
$ENV{'BASH_ENV'}=''; 
$ENV{'ENV'}='';

Getopt::Long::Configure('bundling');
GetOptions
	("V"   => \$opt_V,   "version"    => \$opt_V,
	 "h"   => \$opt_h,   "help"       => \$opt_h,
	 "v"   => \$verbose, "verbose"    => \$verbose,
	 "F=s" => \$opt_F,   "filename=s" => \$opt_F,
	 "t=i" => \$opt_t, "timeout=i"  => \$opt_t,
	 "w=i" => \$opt_w, "warning=i"  => \$opt_w,
	 "c=i" => \$opt_c, "critical=i"  => \$opt_c);

if ($opt_V) {
	print_revision($PROGNAME,'0.2 (Yale fork)');
	exit $ERRORS{'OK'};
}

unless (defined $opt_t) {
	$opt_t = $utils::TIMEOUT ;	# default timeout
}

unless (defined $opt_w) {
	$opt_w = WARN ;	                # default warn (days)
}

unless (defined $opt_c) {
	$opt_c = CRIT ;	                # default crit (days)
}

# doesn't make sense to have $opt_w < $opt_c
if ( $opt_w < $opt_c ) {
	print "Warn threshold $opt_w is less than crit threshold $opt_c\n";
	exit $ERRORS{'UNKNOWN'};
}


if ($opt_h) {print_help(); exit $ERRORS{'OK'};}

unless (defined $opt_F) {
	print "Missing license.dat file\n";
	print_usage();
	exit $ERRORS{'UNKNOWN'};
}
# Just in case of problems, let's not hang Nagios
$SIG{'ALRM'} = sub {
	print "Timeout: No Answer from Client\n";
	exit $ERRORS{'UNKNOWN'};
};
alarm($opt_t);

#my $lmstat = $utils::PATH_TO_LMSTAT ;
my $lmstat = dirname($opt_F);
$lmstat = "$lmstat/lmstat";
unless (-x $lmstat ) {
	print "Cannot find \"lmstat\"\n";
	exit $ERRORS{'UNKNOWN'};
}

($opt_F) || ($opt_F = shift) || usage("License file not specified\n");
my $licfile = $1 if ($opt_F =~ /^(.*)$/);
($licfile) || usage("Invalid filename: $opt_F\n");

print "$licfile\n" if $verbose;

if ( ! open(CMD,"$lmstat -c $licfile |") ) {
	print "ERROR: Could not open \"$lmstat -c $licfile\" ($!)\n";
	exit exit $ERRORS{'UNKNOWN'};
}

my $serverup = 0;
my @upsrv; 
my @downsrv;  # list of servers up and down

#my ($ls1,$ls2,$ls3,$lf1,$lf2,$lf3,$servers);
 
# key off of the term "license server" and 
# grab the status.  Keep going until "Vendor" is found
#

#
# Collect list of license servers by their status
# Vendor daemon status is ignored for the moment.

while ( <CMD> ) {
	next if (/^lmstat/);   # ignore 1st line - copyright
	next if (/^Flexible/); # ignore 2nd line - timestamp
	(/^Vendor/) && last;   # ignore Vendor daemon status
	print $_ if $verbose;
	
		if ($_ =~ /license server /) {	# matched 1 (of possibly 3) license server
			s/^\s*//;					#some servers start at col 1, other have whitespace
										# strip staring whitespace if any
			if ( $_ =~ /UP/) {
				$_ =~ /^(.*):/ ;
				push(@upsrv, $1);
				print "up:$1:\n" if $verbose;
			} else {
				$_ =~ /^(.*):/; 
				push(@downsrv, $1);
				print "down:$1:\n" if $verbose;
			}
		
		}
	

#	if ( /^License server status: [0-9]*@([-0-9a-zA-Z_]*),[0-9]*@([-0-9a-zA-Z_]*),[0-9]*@([-0-9a-zA-Z_]*)/ ) {
#	$ls1 = $1;
#	$ls2 = $2;
#	$ls3 = $3;
#	$lf1 = $lf2 = $lf3 = 0;
#	$servers = 3;
#  } elsif ( /^License server status: [0-9]*@([-0-9a-zA-Z_]*)/ ) {
#	$ls1 = $1;
#	$ls2 = $ls3 = "";
#	$lf1 = $lf2 = $lf3 = 0;
#	$servers = 1;
#  } elsif ( / *$ls1: license server UP/ ) {
#	print "$ls1 UP, ";
#	$lf1 = 1
#  } elsif ( / *$ls2: license server UP/ ) {
#	print "$ls2 UP, ";
#	$lf2 = 1
#  } elsif ( / *$ls3: license server UP/ ) {
#	print "$ls3 UP, ";
#	$lf3 = 1
#  } elsif ( / *([^:]*: UP .*)/ ) {
#	print " license server for $1\n";
#	$serverup = 1;
#  }

}

#if ( $serverup == 0 ) {
#    print " license server not running\n";
#    exit 2;	
#}

close CMD;

#
# bw - now loop through license file and raise expiration
# alerts per opt_w and opt_c
if ( ! open(FILE, "<", "$licfile") ) {
        print "ERROR: Could not open \"$licfile\" ($!)\n";
        exit exit $ERRORS{'UNKNOWN'};
}

# supports flexlm license file format v3.0 and later
my $line;
my $status = 0;
while ( defined($line = <FILE>) ) {
        my ($feat_name,$exp_date,$err);
        chomp $line;
        if ($line =~ s/\\$//) {
                $line .= <FILE>;
                redo unless eof(FILE);
        }
	next if ($line =~ /^\w*#.*/);   # ignore comment-only lines
        # only process FEATURE, INCREMENT, or UPGRADE lines
	if ($line =~ /^FEATURE/ || $line =~ /^INCREMENT/ ) {
                ($feat_name,$exp_date) = ($line =~ /^\S+\s+(\S+)\s+\S+\s+\S+\s+(\S+)\s+.*$/);
        }
	if ($line =~ /^UPGRADE/ ) {
                ($feat_name,$exp_date) = ($line =~ /^\S+\s+(\S+)\s+\S+\s+\S+\s+\S+\s+(\S+)\s+.*$/);
        }
        # compare exp_date with today's date, raise alert as specified. 
        if ( defined($feat_name) && defined($exp_date) ) {
                my $today = ParseDate("today");
                my $expiry = ParseDate("$exp_date");
                my $delta = DateCalc($today, $expiry, \$err, 0);
                my $warndelta = ParseDateDelta("$opt_w days");
                my $critdelta = ParseDateDelta("$opt_c days");
                if ( Date_Cmp($delta, $warndelta) == -1 ) {
                        if ( $status < 1 ) {
                                $status = 1;
                        }
                }
                if ( Date_Cmp($delta, $critdelta) == -1 ) {
                        if ( $status < 2 ) {
                                $status = 2;
                        }
                }
        }
        
}

#
# determine overall status
my $overall = 0;
my $message = "";
if ( scalar(@downsrv) == 0 && $status == 0 ) {
        $overall = 0;
        $message = scalar(@upsrv)." server(s) up, ".scalar(@downsrv)." server(s) down;";
        $message = "$message no imminent expirations.";
}
if ( ((scalar(@upsrv) > 0) && (scalar(@downsrv) > 0)) || $status == 1 ) {
        $overall = 1;
        $message = scalar(@upsrv)." server(s) up, ".scalar(@downsrv)." server(s) down;";
        if ($status == 1) {
                $message = "$message 1 or more features expiring in fewer than $opt_w days.";
        }
}
if ( ((scalar(@upsrv) <= 0) && (scalar(@downsrv) > 0)) || $status == 2 ) {
        $overall = 2;
        $message = scalar(@upsrv)." servers up, ".scalar(@downsrv)." servers down;";
        if ($status == 2) {
                $message = "$message 1 or more features expiring in fewer than $opt_c days.";
        }
}

#
# print check name, status, message
print "FLEXLM ";
if ( $overall == 0 ) { print "OK - "; }
if ( $overall == 1 ) { print "WARNING - "; }
if ( $overall == 2 ) { print "CRITICAL - "; }
if ( ($overall < 0) || ($overall > 2) ) { print "UNKNOWN "; }
print "$message ";


if ($verbose) {
	print "License Servers running: ".scalar(@upsrv) ."\n";
	foreach my $upserver (@upsrv) {
		print "$upserver\n";
	}
	print "License servers not running: ".scalar(@downsrv)."\n";
	foreach my $downserver (@downsrv) {
		print "$downserver\n";
	}
}

#
# print list of servers which are up. 
#
if (scalar(@upsrv) > 0) {
   print "License Servers running:";
   foreach my $upserver (@upsrv) {
      print "$upserver,";
   }
}
#
# Ditto for those which are down.
#
if (scalar(@downsrv) > 0) {
   print "License servers NOT running:";
   foreach my $downserver (@downsrv) {
      print "$downserver,";
   }
}

# perfdata
print "\n|flexlm::up:".scalar(@upsrv).";down:".scalar(@downsrv)."\n";

exit $ERRORS{'OK'} if ( $overall == 0 );
exit $ERRORS{'WARNING'} if ( $overall == 1 );
exit $ERRORS{'CRITICAL'} if ( $overall == 2 );
exit $ERRORS{'UNKNOWN'}; # shouldn't get here!

#exit $ERRORS{'OK'} if ( $servers == $lf1 + $lf2 + $lf3 );
#exit $ERRORS{'WARNING'} if ( $servers == 3 && $lf1 + $lf2 + $lf3 == 2 );


sub print_usage () {
	print "Usage:
   $PROGNAME -F <filename> [-v] [-t] [-V] [-h] [-w] [-c]
   $PROGNAME --help
   $PROGNAME --version
";
}

sub print_help () {
	print_revision($PROGNAME,'0.2 (Yale fork)');
	print "Copyright (c) 2000 Ernst-Dieter Martin/Karl DeBisschop

Check available flexlm license managers

";
	print_usage();
	print "
-F, --filename=FILE
   Name of license file (usually \"license.dat\")
-v, --verbose
   Print some extra debugging information (not advised for normal operation)
-t, --timeout
   Plugin time out in seconds (default = $utils::TIMEOUT )
-V, --version
   Show version and license information
-h, --help
   Show this help screen
-w, --warning=# (default = ".WARN.")
   Warning if any feature expires in less than # days
-c, --critical=# (default = ".CRIT.")
   Critical if any feature expires in less than # days

Flexlm license managers usually run as a single server or three servers and a
quorum is needed.  The plugin return OK if 1 (single) or 3 (triple) servers
are running, CRITICAL if 1(single) or 3 (triple) servers are down, and WARNING
if 1 or 2 of 3 servers are running\n
";
	support();
}
