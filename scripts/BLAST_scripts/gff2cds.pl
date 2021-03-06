#!/usr/local/bin/perl

# ms2@sanger.ac.uk

# extracts the start and end coordinates of all the sequences from a gff file having the cds tag associated
# with their "exon's".
# the possible second fields of the gff file were:  hand_built, Genefinder, stl, stl-preliminary, Coding, assembly-default.
# now, we have only curated and preliminary


use strict;

my %line; my %cds;

while (<>) {
    chomp;
    if ((/^\S+\t(curated)\tCDS\t/) && (/\"(\S+\.\S+)\"/)) {
        print "$_\n";
    }
#    if ((/^\S+\t+\w*\tCDS\t/) && (/\"(\S+\.\S+)\"$/)) {
#        $cds{$1} = "yes";
#   }
}

#foreach (keys (%line)) {
#    if (exists $cds{$_}) {
#        print "$line{$_}\n";
#    }
#}
