#!/usr/local/bin/perl5.8.0 -w
#
# load_related_data_from_Build_to_geneace.pl
#
# by Chao-Kung Chen
#
# loads Geneace related data from Build back to /wormsrv1/geneace
# RUN this script anytime during the build or after the build when get_interpolated_map 
# and update_inferred multi-pt data are done
#
# Last updated on: $Date: 2004-11-26 13:13:14 $
# Last updated by: $Author: krb $


use strict;
use lib -e "/wormsrv2/scripts" ? "/wormsrv2/scripts" : $ENV{'CVS_DIR'};
use Wormbase;
use Ace;

######################
# ----- globals -----
######################

my $user = `whoami`; chomp $user;
if ($user ne "wormpub"){print "\nYour need to be wormpub to upload data to geneace\n"; exit 0 };

my $tace = &tace;          # tace executable path
my $release = get_wormbase_version_name(); # only the digits

my $geneace_dir = "/wormsrv1/geneace";
my $autoace = "/wormsrv2/autoace";
my $curr_db = "/nfs/disk100/wormpub/DATABASES/current_DB";


my $log = Log_files->make_build_log();


##############################
# ----- preparing data -----
##############################



# (1) interpolated map data
$log->write_to("Loading interpolated map data\n");
my @map = glob("/wormsrv2/autoace/MAPPINGS/INTERPOLATED_MAP/interpolated_map_to_geneace_$release.*ace");
my $map = $map[-1];

# need to first remove existing data before uploading new file
my $command = <<END;
Find Gene * where Interpolated_map_position
edit -D Interpolated_map_position
pparse $map
save
quit
END

open (Load_GA,"| $tace -tsuser \"update_from_autoace\" $geneace_dir") || die "Failed to upload to Geneace\n";
print Load_GA $command;
close Load_GA;


# (2) corrected reverse physicals
my $rev_phys = glob("/wormsrv2/autoace/MAPPINGS/INTERPOLATED_MAP/rev_physical_update_$release");
# load if file exists
if(-e $rev_phys){
  $log->write_to("Loading reverse physicals\n");
  
  $command = "pparse $rev_phys\nsave\nquit\n";
open (Load_GA,"| $tace -tsuser \"update_from_autoace\" $geneace_dir") || die "Failed to upload to Geneace\n";
print Load_GA $command;
close Load_GA;
}
else{
  $log->write_to("$rev_phys file did not exist\n");
}

# (3) new multipt obj created for pseudo markers
my $multi = glob("/wormsrv1/geneace/JAH_DATA/MULTI_PT_INFERRED/inferred_multi_pt_obj_$release");
if(-e $multi){
  $log->write_to("Loading multipoint objects for pseudo map markers \n");
  
  $command = "pparse $multi\nsave\nquit\n";
open (Load_GA,"| $tace -tsuser \"update_from_autoace\" $geneace_dir") || die "Failed to upload to Geneace\n";
print Load_GA $command;
close Load_GA;
}
else{
  $log->write_to("$multi file did not exist\n");
}

# (4) existing multipt obj with updated flanking marker loci
$log->write_to("Updating existing multipoint data with corrected flanking marker loci\n");
my $multi_update = glob("/wormsrv1/geneace/JAH_DATA/MULTI_PT_INFERRED/updated_multi_pt_flanking_loci_$release");
$command = "pparse $multi_update\nsave\nquit\n";
open (Load_GA,"| $tace -tsuser \"update_from_autoace\" $geneace_dir") || die "Failed to upload to Geneace\n";
print Load_GA $command;
close Load_GA;

# (5) updated geneace with person/person_name data from Caltech
# can use dumped Person class in /wormsrv2/wormbase/caltech/caltech_Person.ace
$log->write_to("Updating person name information from caltech_Person.ace file\n");

# First need to remove person/person_name data from /wormsrv1/geneace
# Not that the value of "CGC_representative_for" is kept as geneace keeps this record
# i.e. you can't delete *all* of the Person class from geneace
$log->write_to("First removing old Person data\n");
$command=<<END;
find Person *
edit -D PostgreSQL_id
edit -D Name
edit -D Laboratory
edit -D Address
edit -D Comment
edit -D Tracking
edit -D Lineage
edit -D Publication
save
quit
END

open (Load_GA,"| $tace -tsuser \"update_from_autoace\" $geneace_dir") || die "Failed to upload to Geneace\n";
print Load_GA $command;
close Load_GA;


# new Person data will have been dumped from citace
$log->write_to("Adding new person data\n");
my $person = "/wormsrv2/wormbase/caltech/caltech_Person.ace";

$command= "pparse $person\nsave\nquit\n";
open (Load_GA,"| $tace -tsuser \"update_from_autoace\" $geneace_dir") || die "Failed to upload to Geneace\n";
print Load_GA $command;
close Load_GA;


###########################
# ----- email notice -----
###########################
$log->mail("All", "BUILD REPORT: load_related_data_from_Build_to_geneace.pl");


exit(0);

__END__

