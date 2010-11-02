#!/software/bin/perl

# Marc Sohrmann (ms2@sanger.ac.uk)

# parses either the swissprot or trembl .dat flat files,
# and writes three DBM files: org, description, key words
use lib $ENV{'CVS_DIR'};

use strict;
use Getopt::Long;
use GDBM_File;
use Wormbase;
use Storable;
use Log_files;

my ($opt_s, $opt_t, $opt_v);
my ($test, $debug, $store, $species);
my $file;
#swissprot trembl verbose

GetOptions ("s" => \$opt_s,
	    "t" => \$opt_t,
	    "v" => \$opt_v,
	    "file:s" => \$file,
	    "test"   => \$test,
	    "store:s"=> \$store,
	    "debug:s"=> \$debug,
	    );

my $verbose = $opt_v;

my $wormbase;
if( $store ) {
    $wormbase = retrieve( $store ) or croak("cant restore wormbase from $store\n");
}
else {
    $wormbase = Wormbase->new( -debug   => $debug,
			       -test     => $test,
			       -organism => $species
			       );
}

my $log = Log_files->make_build_log($wormbase);

# store the database files in swall_data, but make them in /tmp as this goes MUCH faster
my $output_dir = "/lustre/scratch101/ensembl/wormpipe/swall_data";
my $tmp_dir = "/tmp";

my %ORG;
my %DES;
my %KEY;
my $id;
my $org;
my $total_org;
my $des;
my $key;
my $switch = 0;

my $usage = "swiss_trembl2dmb.pl -file uniprot_sprot.dat\n";
$usage .= "-s for swissprot\n";
$usage .= "-t for trembl\n";

if ($opt_s && $opt_t) {
   $log->log_and_die ("$usage");
}
elsif ($opt_s) {
  
  `rm $tmp_dir/swissprot2org` if (-e "$tmp_dir/swissprot2org" );
  `rm $tmp_dir/swissprot2des` if (-e "$tmp_dir/swissprot2des" );
  `rm $tmp_dir/swissprot2key` if (-e "$tmp_dir/swissprot2key" );
  
  tie %ORG,'GDBM_File',"$tmp_dir/swissprot2org",&GDBM_WRCREAT, 0666 or $log->log_and_die("cannot open DBM file");
  tie %DES,'GDBM_File',"$tmp_dir/swissprot2des",&GDBM_WRCREAT, 0666 or $log->log_and_die("cannot open DBM file");
  tie %KEY,'GDBM_File',"$tmp_dir/swissprot2key",&GDBM_WRCREAT, 0666 or $log->log_and_die("cannot open DBM file");
}
elsif ($opt_t) {
  
  `rm $tmp_dir/trembl2org` if (-e "$tmp_dir/trembl2org" );
  `rm $tmp_dir/trembl2des` if (-e "$tmp_dir/trembl2des" );
  `rm $tmp_dir/trembl2key` if (-e "$tmp_dir/trembl2key" );
  
  tie %ORG,'GDBM_File', "$tmp_dir/trembl2org",&GDBM_WRCREAT, 0666 or $log->log_and_die("cannot open DBM file"); 
  tie %DES,'GDBM_File', "$tmp_dir/trembl2des",&GDBM_WRCREAT, 0666 or  $log->log_and_die("cannot open DBM file");
  tie %KEY,'GDBM_File', "$tmp_dir/trembl2key",&GDBM_WRCREAT, 0666 or  $log->log_and_die("cannot open DBM file");
}
else {
    die "$usage";
}

open(SW,"<$file") or die("cant open $file:$!\n");
while (my $line = <SW>) {
    if ($line =~ /^AC\s+(\S+)\;/) {
        $id = $1;
        $switch = 1;
    }
    elsif ($line =~ /^OS\s+/) {
        $line =~ s/^OS\s+//;
        $total_org .= $line;
    }
    elsif ($line =~ /^DE\s+/) {
        $line =~ s/^DE\s+//;
        $des .= $line;
    }
    elsif ($line =~ /^KW\s+/) {
        $line =~ s/^KW\s+//;
        $key .= $line;
    }

    elsif ($line =~ /^SQ\s+/ && $switch == 1) {
        # this gets rid of the tremblnew entries that are
        # in the same file with the swissprot entries
        # (currently, swall-1 = swissprot + tremblnew, swall-2 = trembl)
        if (($opt_s) || ($opt_t)) {
            #
            $total_org =~ s/\n/ /g;
            $total_org =~ s/\.//g;
            $total_org =~ s/\,/()/g;
            $total_org =~ s/\s+and\s+/()/g;
            chomp $total_org;
            my @split;
            my @tmp;
            @split = split (/\([^\(\)]*\)/, $total_org);
            my %seen;
            foreach (@split) {
                s/^\s+//;
                s/\s+$//;
                if ($_ eq "") {
                    next;
	            }
                elsif (exists $seen{$_}) {
                    next;
	            }
                else {
                    $seen{$_} = 1;
                    push (@tmp, $_);
                }              
	        }
            $org .= join (";", @tmp);
            if (exists $ORG{$id}) {
                print "ORG PRESENT\t$id\t($org)\n" if $verbose;
            }
            else {
                $ORG{$id} = $org;
                print "ORG ADDED\t$id\t($org)\n" if $verbose;
            }
            
            chomp $des;
            $des =~ s/\n/\s/g;
	        $des =~ s/\"//g;
	        if ($des=~/Full=([^;]+)/){		
		       $des="$1";
	        }
	      
            if (exists $DES{$id}) {
                print "DES PRESENT\t$id\t($des)\n" if $verbose;
            }
            else {
                $DES{$id} = $des;
                print "DES ADDED\t$id\t($des)\n" if $verbose;
            }
            #
            chomp $key;
            $key =~ s/\n/\s/g;
            if (exists $KEY{$id}) {
                print "KEY PRESENT\t$id\t($key)\n" if $verbose;
            }
            else {
                $KEY{$id} = $key;
                print "KEY ADDED\t$id\t($key)\n" if $verbose;
            }
	    }
        else {
            print "\tINCORRECT ID: $id\n";
	    }
        $id = "";
        $org = "";
        $total_org = "";
        $des = "";
        $key = "";
        $switch = 0;
    }
}
close SW;

untie %ORG;
untie %DES;
untie %KEY;




# now copy the database files from /tmp to the directory where they will be stored
if ($opt_s) {
  
  `mv -f $tmp_dir/swissprot2org $output_dir`;
  `mv -f $tmp_dir/swissprot2des $output_dir`;
  `mv -f $tmp_dir/swissprot2key $output_dir`;
  
}
elsif ($opt_t) {
  
  `mv -f $tmp_dir/trembl2org $output_dir`;
  `mv -f $tmp_dir/trembl2des $output_dir`;
  `mv -f $tmp_dir/trembl2key $output_dir`;
  
}

$log->mail;
