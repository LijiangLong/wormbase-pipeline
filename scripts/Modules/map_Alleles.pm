=pod 

=head1 NAME

map_Alleles.pm

=head1 SYNOPSIS

use map_Alleles.pm

MapAlleles::setup(LogFile::,Wormbase::)

=head1 DESCRIPTION

modules containing functions for map_Alllele.pl
like for searching through GFF files and printing in Ace format

=head1 FUNCTIONS for MapAlleles::

=cut
package MapAlleles;

# standard library
use IO::File;
use Memoize; 

# CPAN
use Ace;
use lib '/software/worm/lib/bioperl-live';
use Bio::Tools::CodonTable;

# Wormbase
use lib $ENV{CVS_DIR};
use lib "$ENV{CVS_DIR}/Modules";
use Feature_mapper;
use Sequence_extract;
use Coords_converter;
memoize('Sequence_extract::Sub_sequence') unless $ENV{DEBUG}; 
use gff_model;

# needs to be attached in main code
my ($log,$wb,$errors,$extractor,$weak_checks);

my ($index); # mem_index test

=head2 get_errors

	Title	: get_errors
	Usage	: $scalar=get_errors()
	Function: accessor for the $errors package variable
	Returns	: (integer) number of errors occured
	Args	: none 

=cut
sub get_errors{return $errors}

=head2 setup

	Title	: setup
	Usage	: MapAlleles::setup($log,$wormbase)
	Function: sets up package wide variables
	Returns	: 1 on success
	Args	: logfiles object , wormbase object

=cut

# used instead of an custom importer to keep the use statements in one place
sub setup{
	($log,$wb)=@_;
	&_build_index;
	$index=Mem_index::build;
	$extractor=Sequence_extract->invoke($wb->autoace,undef,$wb);
   	return 1;
}

=head2 setup

	Title	: set_wb_log
	Usage	: MapAlleles::set_wb_log($log,$wormbase)
	Function: sets up package wide variables ONLY
	Returns	: 1 on success
	Args	: logfiles object , wormbase object

=cut

sub set_wb_log {
	($log,$wb,$weak_checks)=@_;
	return 1
}

=head2 get_all_alleles

	Title	: get_all_alleles
	Usage	: MapAlleles::get_all_alleles()
	Function: get a list of filtered alleles from acedb
	Returns	: array_ref of Ace::Alleles
	Args	: none

=cut

# gets all alles and filters them
sub get_all_alleles {
    my $db = Ace->connect( -path => $wb->autoace ) || do { print "cannot connect to ${$wb->autoace}:", Ace->error; die };
    my @alleles = $db->fetch( -query =>'Find Variation WHERE Flanking_sequences AND species = "Caenorhabditis elegans"');
    return &_filter_alleles(\@alleles);
}        

=head2 get_all_allele

	Title	: get_all_allele
	Usage	: MapAlleles::get_all_allele('tm852')
	Function: get an allele from acedb
	Returns	: array_ref containing ONE Ace::Allele
	Args	: (string) alllele name

=cut

# get allele for testing
sub get_allele {
	my ($allele)=@_;
	my $db = Ace->connect( -path => $wb->autoace ) || do { print "cannot connect to ${$wb->autoace}:", Ace->error; die };
    my @alleles = $db->fetch(Variation => "$allele");

	return \@alleles;
}

=head2 _filter_alleles

	Title	: _filter_alleles
	Usage	: _filter_alleles(array_ref of Ace::Alleles)
	Function: removes allleles failing some sanity checks from the array PRIVATE
	Returns	: array_ref containing Ace::Alleles
	Args	: (array_ref) of Ace::Alleles 

=cut

# filter the alleles
# removes alleles without 2 flanking sequences, no Sequence or not Source attached to the parent sequence
sub _filter_alleles {
    my ($alleles) = @_;

    my @good_alleles;

    foreach my $allele (@{$alleles}) {
        my $name = $allele->name;
	my $remark = $allele->Remark;

	# print STDERR "checking $name\n";
		
	# has no sequence connection
        if ( ! defined $allele->Sequence ) {
			$log->write_to("ERROR: $name has missing Sequence tag (Remark: $remark)\n");$errors++
			}

# The bit below is commented out, as there are sadly some alleles connected to sequences without source that can't be moved :-(

#	# connected sequence has no source
#        elsif ( !defined $allele->Sequence->Source && !defined $weak_checks) { 
#            $log->write_to("ERROR: $name connects to ${\$allele->Sequence} which has no Source tag (Remark: $remark)\n");$errors++
#        }

	# no left flanking sequence
        elsif (!defined $allele->Flanking_sequences){
	    	$log->write_to("ERROR: $name has no left Flanking_sequence (Remark: $remark)\n");$errors++
		}                                                                        

	# no right flanking sequence
        elsif (!defined $allele->Flanking_sequences->right || ! defined $allele->Flanking_sequences->right->name ) {
                    $log->write_to("ERROR: $name has no right Flanking_sequence (Remark: $remark)\n");$errors++
        }       

	# empty flanking sequence
        elsif (!defined $allele->Flanking_sequences->name ) {
                    $log->write_to("ERROR: $name has no left Flanking_sequence (Remark: $remark)\n");$errors++
        }
        elsif ($allele->Type_of_mutation eq 'Substitution' && !defined $allele->Type_of_mutation->right){
                    $log->write_to("WARNING: $name has no from in the substitution tag (Remark: $remark)\n");
	}
	
	# has spaces or numbers in the DNA sequence strings
        elsif (($allele->Type_of_mutation eq 'Substitution') && 
		($allele->Type_of_mutation->right=~/\d|\s/ || $allele->Type_of_mutation->right->right=~/\d|\s/)){
		$log->write_to("ERROR: $name has numbers an/or spaces in the from/to tags (Remark: $remark)\n");$errors++
	}
	else { push @good_alleles, $allele }
    }
    return \@good_alleles;
}

=head2 map

	Title	: map
	Usage	: MapAlleles::map(array_ref of Ace::Alleles)
	Function: maps alleles to chromosome coordinates
	Returns	: hash_ref containing {allele_name}->{alleles}->Ace::Alleles and ->{start},->{stop},->{chromosome},->{clone},->{orientation}
	Args	: (array_ref) of Ace::Alleles 
    
=cut

# get the chromosome coordinates
sub map {
	my ($alleles)=@_;
	my %alleles;
	my $mapper = Feature_mapper->new( $wb->autoace, undef, $wb );
        my $coords = Coords_converter->invoke( $wb->autoace, 1, $wb );

	foreach my $x (@$alleles) {
		# $chromosome_name,$start,$stop
		my @map=$mapper->map_feature($x->Sequence->name,$x->Flanking_sequences->name,$x->Flanking_sequences->right->name);
		if ($map[0] eq '0'){
			$log->write_to("ERROR: Couldn't map ${\$x->name} to sequence ${\$x->Sequence->name} with ${\$x->Flanking_sequences->name} and ${\$x->Flanking_sequences->right->name} (Remark: ${\$x->Remark})\n");
			$errors++;
			next
		}
		# from flanks to variation
		if ($map[2]>$map[1]){$map[1]++;$map[2]--}
		else {$map[1]--;$map[2]++}
		#------------------------------------------------------------------------
		my ($chromosome,$start)=$mapper->Coords_2chrom_coords($map[0],$map[1]);
		my ($drop,$stop)=$mapper->Coords_2chrom_coords($map[0],$map[2]);
		
		# orientation
		my $orientation='+';
		if ($stop < $start){
			my $tmp;
			$tmp=$start;
			$start=$stop;
			$stop=$tmp;
			$orientation='-';
		}

		# in case that the parent is the chromosome
		if ($chromosome eq $map[0]){
		 ($map[0],$map[1],$map[2]) = $coords->LocateSpan( $chromosome,$start,$stop);			
		}
		$alleles{$x->name}={allele => $x, chromosome =>$chromosome, start=>$start, stop=>$stop, 
			clone => $map[0],clone_start => $map[1], clone_stop => $map[2],orientation => $orientation};

		print "${\$x->name} ($chromosome ($orientation): $start - $stop) clone: $map[0] $map[1]-$map[2]\n" if $wb->debug;
		
		#map the CGH inner seqs
		if($x->CGH_deleted_probes){
			my @map=$mapper->map_feature($x->Sequence->name,$x->CGH_deleted_probes->name,$x->CGH_deleted_probes->right->name);
			if ($map[0] eq '0'){
				$log->write_to("ERROR: Couldn't map CGH_deleted_probes for ${\$x->name} to sequence ${\$x->Sequence->name} with ${\$x->Flanking_sequences->name} and ${\$x->Flanking_sequences->right->name} (Remark: ${\$x->Remark})\n");
				$errors++;
				next
			}
			$alleles{$x->name}{'CGH5'} = $map[1] - $alleles{$x->name}->{'clone_start'} ;
			$alleles{$x->name}{'CGH3'} = $alleles{$x->name}->{'clone_stop'} - $map[2];
		}
	}
	return \%alleles
}

=head2 map_cgh 

	Title	: map_cgh
	Usage	: MapAlleles::map_cgh(hash_ref of Ace::Alleles)
	Function: maps determines cgh flank sizes
	Returns	: 
	Args	: (hash_ref) of Ace::Alleles from MapAlleles::map
    
=cut

# get the chromosome coordinates for CGH arrays
sub map_cgh {
	my ($alleles)=@_;

	my $mapper = Feature_mapper->new( $wb->autoace, undef, $wb );
        my $coords = Coords_converter->invoke( $wb->autoace, 1, $wb );

	while( my($k,$x)=each %$alleles ){
		my $v=$x->{allele};
		# $chromosome_name,$start,$stop
		next unless $v->CGH_deleted_probes;
		my @cgh_map=$mapper->map_feature($v->Sequence->name,$v->CGH_deleted_probes->name,$v->CGH_deleted_probes->right->name);
		if ($cgh_map[0] eq '0'){
			$log->write_to("ERROR: Couldn't map inner probes of $k to sequence ${\$v->Sequence->name} with ${\$v->CGH_deleted_probes->name} and ${\$v->CGH_deleted_probes->right->name} (Remark: ${\$v->Remark})\n");
			$errors++;
			next
		}

		# from flanks to variation
		if ($cgh_map[2]>$cgh_map[1]){$cgh_map[1]++;$cgh_map[2]--}else {$cgh_map[1]--;$cgh_map[2]++}
	
		my ($chrom,$cgh_start)=$mapper->Coords_2chrom_coords($cgh_map[0],$cgh_map[1]);
		my ($drop,$cgh_stop)=$mapper->Coords_2chrom_coords($cgh_map[0],$cgh_map[2]);
	
		# orientation
		my $orientation='+';
		if ($stop < $start){
			my $tmp=$cgh_start;
			$tmp=$cgh_start;
			$cgh_start=$cgh_stop;
			$cgh_stop=$tmp;
		}

		$$alleles{$k}->{cgh_start}=$cgh_start;
		$$alleles{$k}->{cgh_stop}=$cgh_stop;

		print "$k ($chrom ($orientation): $cgh_start - $cgh_stop) clone: $cgh_map[0] $cgh_map[1]-$cgh_map[2]\n" if $wb->debug;
	}
	# no need to return anything, as we fiddle around with the reference
}

=head2 print_cgh

	Title	: print_cgh
	Usage	: MapAlleles::print_genes(hash_ref alleles)
	Function: print ACE format for CGH arrays ranges
	Returns	: nothing
	Args	: (hash_ref) of {allele_name}={allele_data} 

=cut

sub print_cgh{
	my ($alleles,$fh)=@_;
	while (my($k,$v)=each %$alleles){
		next unless ($v->{cgh_start}&&$v->{cgh_stop}); # skip it if it is not a cgh allele

		my $left_range=$v->{cgh_start} - $v->{start};
		my $right_range=$v->{stop} - $v->{cgh_stop};

		my @order=qw(Five Three);
		@order=qw(Three Five) if ($v->{orientation} eq '+');

		print $fh "Variation : \"$k\"\n";
		print $fh "$order[0]PrimeGap $left_range\n";			
		print $fh "$order[1]PrimeGap $right_range\n\n";
	}
}



=head2 print_genes

	Title	: print_genes
	Usage	: MapAlleles::print_genes(hash_ref {$gene_name}=[$allele_name,..])
	Function: print ACE format for Allele->gene connections
	Returns	: hash_ref containing {$allele_name}=[$gene_name,..]
	Args	: (hash_ref) of {$gene_name}=[$allele_name,..] 

=cut

# create ace formatted gene links
sub print_genes {
	my ($genes,$fh)=@_;
	my %all2genes;
	while( my($key,$allele_list)=each %$genes){
		foreach my $allele(@$allele_list){
			$all2genes{$allele}||=[];
			push @{$all2genes{$allele}},$key;
		}
	}

	while( my($allele,$gene_list) = each %all2genes){
		print $fh "Variation : \"$allele\"\n";
		foreach my $gene(@$gene_list){
			print $fh "Gene $gene\n";
		}
		print $fh "\n";
	}
	return \%all2genes;
}

=head2 get_genes

	Title	: get_genes
	Usage	: MapAlleles::get_genes(array_ref of Ace::Alleles)
	Function: maps alleles to genes
	Returns	: hash_ref containing {$gene_name}=[$allele_name,..]
	Args	: (array_ref) of mapped Ace::Alleles (from map() )

=cut

# map alleles to genes (test)
sub get_genes {
	my ($alleles)=@_;
	my %genes;
	while(my($k,$v)=each(%{$alleles})){
		my @hits=$index->search_genes($v->{'chromosome'},$v->{'start'},$v->{'stop'});
		foreach my $hit(@hits){
			$genes{$hit->{name}}||=[];
			push @{$genes{$hit->{name}}}, $k;
		}
	}
	if ($wb->debug){
		foreach my $y (keys %genes) {print "$y -> ",join " ",@{$genes{$y}},"\n"}
	}
	return \%genes;
}

=head2 get_cds

	Title	: get_cds
	Usage	: MapAlleles::get_cds(array_ref of Ace::Alleles)
	Function: maps alleles to cds
	Returns	: hash_ref containing {$cds_name}{$type}{$allele_name}=1
	Args	: (array_ref) of mapped Ace::Alleles (from map())

=cut

# map the alleles to cdses (test)
sub get_cds {
	my ($alleles)=@_;
	my %cds;
	while(my($k,$v)=each(%{$alleles})){
		my @hits=$index->search_cds($v->{'chromosome'},$v->{'start'},$v->{'stop'});
		foreach my $hit(@hits){
			print $hit->{name},"\n" if $wb->debug;
			my @exons=grep {($v->{'stop'}>=$_->{start}) && ($v->{start}<=$_->{stop})} $hit->get_all_exons;
			my @introns=grep {($v->{'stop'}>=$_->{start}) && ($v->{start}<=$_->{stop})} $hit->get_all_introns;
			if (@exons){
				$cds{$hit->{name}}{Coding_exon}{$k}=1;
				
				# coding_exon $start-$stop<3 -> space for frameshifts (deletion/insertion)
				# FIX: no strange combinations and only insertions < 10 bp size as else they disrupt more than just the frame
				unless ($v->{allele}->Method eq 'Deletion_and_insertion_allele'){
					my $dsize=$v->{stop}-$v->{start}+1;
					my $isize=length $v->{allele}->Insertion;
					$cds{$hit->{name}}{"Frameshift \" $dsize bp Deletion\""}{$k}=1 
					    if ($v->{stop}-$v->{start}<3)&&($v->{allele}->Method eq 'Deletion_allele')&&($dsize < 10);
					$cds{$hit->{name}}{"Frameshift \"$isize bp Insertion\""}{$k}=1 
					    if ($v->{allele}->Insertion)&&((length $v->{allele}->Insertion)%3!=0)&&(length $v->{allele}->Insertion < 10);
				}                                                     
				# coding_exon -> space for substitutions (silent mutations / stops / AA changes)
				if ($v->{start}-$v->{stop} < 3 && $v->{allele}->Type_of_mutation eq 'Substitution'){
					
					# insanity check: insane tags are ignored and reported as warnings
					if (!$v->{allele}->Type_of_mutation->right || !$v->{allele}->Type_of_mutation->right->right){
						$log->write_to("WARNING: $k is missing FROM and/or TO (Remark: ${\$v->{allele}->Remark})\n");
                                                $errors++;
				   		next;
					}
					
					# get cds
					my @coding_exons;
					if ($hit->{orientation} eq '+'){ @coding_exons=sort {$a->{start}<=>$b->{start}} $hit->get_all_exons}
					else { @coding_exons=sort {$b->{start}<=>$a->{start}} $hit->get_all_exons}
					my $sequence;
					map{$sequence=join("",$sequence,&get_seq($_->{chromosome},$_->{start},$_->{stop},$_->{orientation}))} @coding_exons;
					
					# get position in cds
                                        my $cds_position=0;
					my $exon=1;
					foreach my $c_exon(@coding_exons){
						if ($v->{'start'}<=$c_exon->{'stop'}&&$v->{'stop'}>=$c_exon->{'start'}){
							if ($c_exon->{'orientation'} eq '+'){$cds_position+=($v->{'start'}-$c_exon->{'start'}+1)}
							else{$cds_position+=($c_exon->{'stop'}-$v->{'start'}+1)}
							last;
						}      
						else{
							$cds_position+=($c_exon->{'stop'}-$c_exon->{'start'}+1);
						}
					}
					print "SNP $k at CDS position $cds_position (${\int($cds_position/3+1)})" if $wb->debug;
					
                                        # start of the codon part

					my $offset=$cds_position-(($cds_position-1) % 3); #start of frame 1based

					my $table=Bio::Tools::CodonTable->new(-id=>1);
					
					my $frame = ($cds_position-1) % 3 ; # ( 0 1 2 ) is in reality frame-1

					my $from_na="${\$v->{allele}->Type_of_mutation->right}";
					my $from_codon=substr($sequence,$offset-1,3);

                                        # enforce some assertion
					next unless ($frame + length($from_na) < 4); # has to fit in the codon
					unless ($frame <= 2 && $frame >= 0){ # has to be 0 1 2
						$log->write_to("BUG: $k has a strange frame ($frame)\n");
						next;
					}
					unless(length($from_codon)==3){ # codons have to be 3bp long
						$log->write_to("BUG: $k has a strange mutated codon ($from_codon)\n");
						next;
					}

					substr($from_codon,$frame,length($from_na),$from_na);
					my $from_aa=$table->translate($from_codon);
					
					my $to_na="${\$v->{allele}->Type_of_mutation->right->right}";
					my $to_codon=$from_codon;

                                        next unless ($frame +length($to_na) < 4);

					substr($to_codon,$frame,length($to_na),$to_na);
					my $to_aa=$table->translate($to_codon);

					
					
					# silent mutation
					if ($to_aa eq $from_aa){
						$cds{$hit->{name}}{"Silent \"$to_aa (${\int($cds_position/3+1)})\""}{$k}=1;
						print "silent mutation: " if $wb->debug;
					}
					# premature stop
					elsif ($table->is_ter_codon($from_codon)||$table->is_ter_codon($to_codon)){
					   my $stop_codon=$table->is_ter_codon($from_codon)?$from_codon:$to_codon;
					   my $other_codon=$table->is_ter_codon($from_codon)?uc $to_codon:uc $from_codon;
					   my $other_aa=$table->translate($other_codon);
					   if (uc($stop_codon) =~ /[TWYKHDB]AG/ ){
						    $cds{$hit->{name}}{"Nonsense Amber_UAG \"$other_aa to amber stop (${\int($cds_position/3+1)})\""}{$k}=1;
							print "Nonsense Amber_UAG: " if $wb->debug;    	
						}
						elsif (uc($stop_codon) =~ /[TWYKHDB]AA/){
							$cds{$hit->{name}}{"Nonsense Ochre_UAA \"$other_aa to ochre stop (${\int($cds_position/3+1)})\""}{$k}=1;
							print "Nonsense Ochre_UAA: " if $wb->debug;
						}
						elsif (uc($stop_codon) =~ /[TWYKHDB]GA/){
							$cds{$hit->{name}}{"Nonsense Opal_UGA \"$other_aa to opal stop (${\int($cds_position/3+1)})\""}{$k}=1;
							print "Nonsense Opal_UAA: " if $wb->debug;
						}
						elsif (uc($stop_codon) eq 'TAR'){
							$cds{$hit->{name}}{"Nonsense Amber_UAG_or_Ochre_UAA \"$other_aa to amber or ochre stop (${\int($cds_position/3+1)})\""}{$k}=1;
						}
						elsif (uc($stop_codon) eq 'TRA') {
							$cds{$hit->{name}}{"Nonsense Ochre_UAA_or_Opal_UGA \"$other_aa to opal or ochre stop (${\int($cds_position/3+1)})\""}{$k}=1;
						}
						else {$log->write_to("ERROR: whatever stop $stop_codon is in $k, it is not Amber/Opal/Ochre (Remark: ${\$v->{allele}->Remark})\n");$errors++}
					}
				 	# missense
					else{
						$cds{$hit->{name}}{"Missense ${\int($cds_position/3+1)} \"$from_aa to $to_aa\""}{$k}=1;
						print "Missense: " if $wb->debug;
					}
					print "from $from_na/$from_codon($from_aa) to $to_na/$to_codon($to_aa)\n" if $wb->debug;
						
				 
				}
			}
			
			# intron part
			if (@introns){
				$cds{$hit->{name}}{Intron}{$k}=1;
				
				# 10 bp allele overlapping a splice site
				if (abs($v->{'start'}-$v->{'stop'})<=10){
					my @types=(Acceptor,Donor);
					@types=(Donor,Acceptor) if $hit->{orientation} eq '+';
					my @intron_starts= grep{$v->{start} <= $_->{start}+1 && $v->{stop}>=$_->{start} } @introns; # intron start 
					my @intron_stops = grep{$v->{start} <= $_->{stop}    && $v->{stop}>=$_->{stop}-1 } @introns; # intron stop
					
					# add the from to stuff:
				        foreach my $intron (@intron_starts){
						my $site=&get_seq($intron->{chromosome},$intron->{start},$intron->{start}+1,$intron->{orientation});
						if ($v->{start}-$v->{stop}==0 && $v->{allele}->Type_of_mutation eq 'Substitution'){
							my $from_na="${\$v->{allele}->Type_of_mutation->right}";
							my $to_na="${\$v->{allele}->Type_of_mutation->right->right}";
							my $offset=$intron->{start}-$v->{start};
							$offset=(1-$offset) if $intron->{orientation} eq '-';
							my $to_site=$site;
							my $from_site=$site;
							substr($to_site,$offset,1,lc($to_na));
							substr($from_site,$offset,1,lc($from_na));
							my ($a,$b)=($from_site eq $site)?($from_site,$to_site):($to_site,$from_site);
							$cds{$hit->{name}}{"$types[0] \"$a to $b\""}{$k}=1;
						}
						else {
							$cds{$hit->{name}}{"$types[0] \"${\$v->{allele}->Type_of_mutation} disrupts $site\""}{$k}=1; 
						}
					}
					foreach my $intron(@intron_stops){
						my $site=&get_seq($intron->{chromosome},$intron->{stop}-1,$intron->{stop},$intron->{orientation});
						if ($v->{start}-$v->{stop}==0 && $v->{allele}->Type_of_mutation eq 'Substitution'){
							my $from_na="${\$v->{allele}->Type_of_mutation->right}";
							my $to_na="${\$v->{allele}->Type_of_mutation->right->right}";
							my $offset=(1-($intron->{stop}-$v->{stop}));
							$offset=(1-$offset) if $intron->{orientation} eq '-';
							my $to_site=$site;
							my $from_site=$site;
							substr($to_site,$offset,1,lc($to_na));
							substr($site,$offset,1,lc($from_na));
							my ($a,$b)=($from_site eq $site)?($from_site,$to_site):($to_site,$from_site);          
							$cds{$hit->{name}}{"$types[1] \"$a to $b\""}{$k}=1;
						}
						else {            
							$cds{$hit->{name}}{"$types[1] \"${\$v->{allele}->Type_of_mutation} disrupts $site\""}{$k}=1;
						}
					}
				}
			}
		}
	}
	if ($wb->debug){
		foreach my $cds_name (keys %cds) {
			foreach my $type(keys %{$cds{$cds_name}}){
				print "$cds_name -> ",join " ",keys %{$cds{$cds_name}{$type}}," ($type)\n"
			}
		}
	}
	return \%cds;
}   

=head2 print_cds

	Title	: print_cds
	Usage	: MapAlleles::print_cds(hash_ref {$cds_name}{$type}{$allele_name}=1)
	Function: print ACE format for Allele->cds connections
	Returns	: hash_ref containing {$allele_name}{$type}{$gene_name}=1
	Args	: (hash_ref) of {$cds _name}{$type}{$allele_name}=1 

=cut

# create ace formatted gene links
sub print_cds {
	my ($cds,$fh)=@_;
	my %inversecds;
	while(my($cds,$type_allele)=each %$cds){
		 while(my($type,$allele)=each %$type_allele){
			foreach my $allele_name(keys %$allele){
				$inversecds{$allele_name}{$type}||=[];
				push @{$inversecds{$allele_name}{$type}},$cds;
			}
		}
	}

	while( my($allele_name, $type_cds) = each %inversecds){
		print $fh 'Variation : "',$allele_name,"\"\n";
		foreach my $type (keys %$type_cds){
			foreach my $cds(@{$type_cds->{$type}}){
				print $fh "Predicted_CDS $cds $type Inferred_automatically map_Alleles.pl\n";
				#print "Predicted_CDS $cds $type Inferred_automatically map_Alleles.pl\n" if $wb->debug;
			}
		}
		print $fh "\n";
	}
	return \%inversecds;
}

=head2 compare

	Title	: compare
	Usage	: MapAlleles::compare(hash_ref of mapped Ace::Allele, hash_ref of $gene->[$allele,..])
	Function: compare old and new gene connections
	Returns	: 1 / writes errors to log
	Args	: hash_ref of mapped Ace::Allele, hash_ref of $gene->[$allele,..] 

=cut

# compare (old(ace objects) - new(hash))
sub compare { 
	my ($old,$new)=@_;
	my %check;
	foreach my $allele(keys %$old){
		foreach my $gene($old->{$allele}->{allele}->Gene){
			$check{$allele}{$gene}=1 unless (qq/${\$old->{$allele}->{allele}->at("Affects.Gene.$gene")->col(1)}/ eq 'Genomic_neighbourhood');
		}
	}
	foreach my $allele(keys %$new){
		foreach my $gene(@{$new->{$allele}}){
			$check{$allele}{$gene}+=2
		}
	}
	while(my($allele,$v)=each %check){
		while(my ($gene,$y)=each %$v){           
			if ($y==1) {
				my $remark=$old->{$allele}->{allele}->Remark;
				$log->write_to("ERROR: $allele -> $gene connection is only in geneace (Remark: $remark)\n");$errors++}
			elsif($y==2){
				#$log->write_to("WARNING: $allele -> $gene connection created by script\n");
			}
			elsif($y==3){}
			else{die "comparison failed\n"}
		}
	}
	1;
}

=head2 get_seq

	Title	: get_seq
	Usage	: MapAlleles::get_seq(chromosome, start, stop, orientation)
	Function: get subsequences of the genome
	Returns	: (string) sequence
	Args	: ('I','II',...) chromosome, (integer) start, (integer) stop, ('+','-') orientation 

=cut

# get sequence from chromosome through ACeDB
# get_seq('I',1,100,'+')
sub get_seq {
	my ($chromosome,$pos1,$pos2,$orientation)=@_; 
	
	my $seq=$extractor->Sub_sequence($chromosome);
	my $len=length $seq;
	
	$pos1--;
	$pos2--;
	
	my ($p1,$p2)=sort {$a<=>$b}($pos1,$pos2);
	
	my $raw_seq=substr($seq,$p1,$p2-$p1+1);
	$raw_seq= $extractor->DNA_revcomp($raw_seq) if ($orientation eq '-');
	return $raw_seq;
}

=head2 get_seq

	Title	: _build_index
	Usage	: MapAlleles::build_index()
	Function: builds the Gene and Cds index
    Returns	: 1
	Args	: none 

=cut

# iterates over the GFF_SPLIT and adds them to the index
sub _build_index {
	my ( $exon, $intron );
	my $gdir=$wb->gff_splits;
	foreach my $file (glob "$gdir/*_gene.gff $gdir/*_curated.gff") {
    	print "processing $file\n" if $wb->debug;
    	my $fh = new IO::File $file, 'r';
    	my @lines = <$fh>
	      ; # works with the relatively small GFF_splits, but stay away from the full GFF files
	    foreach $_ (@lines) {
	        chomp;
	        s/\"//g;
	        my @F = split;
	        Store::store( $F[0], $F[3], $F[4], $F[9], $F[6] )
	          if ( $F[1] eq 'gene' ) && ( $F[2] eq 'gene' );
	    }

	    foreach $_ (@lines) {
	        chomp;
	        s/\"//g;
	        my @F = split;
	        Store::store_cds( $F[0], $F[3], $F[4], $F[6], $F[9],undef )
	          if ( $F[1] eq 'curated' ) && ( $F[2] eq 'CDS' );
	    }

	    foreach $_ (@lines) {
	        chomp;
	        s/\"//g;
	        my @F = split;
	        Store::store_exon( $F[0], $F[3], $F[4], $F[6], $exon++, $F[9], $F[7] )
	          if ( $F[1] eq 'curated' ) && ( $F[2] eq 'coding_exon' );
	        Store::store_intron( $F[0], $F[3], $F[4], $F[6], $intron++, $F[9],
	            $F[7] )
	          if ( $F[1] eq 'curated' ) && ( $F[2] eq 'intron' );
	    }
	    $fh->close;
		undef @lines;
	}
}
                          
=head2 load_utr

		Title	: load_utr
		Usage	: MapAlleles::load_utr()
		Function: load the *UTR.gff files
		Returns	: hash->chromosome->UTRs
		Args	: none

=cut

# load UTRs
sub load_utr{
	my @files = glob "${\$wb->gff_splits}/*UTR.gff";
	my %utrs;
	foreach my $file(@files){
		my $inf=new IO::File $file, 'r';
		print "processing: $file\n" if $wb->debug;
		while (<$inf>) {
			next if /\#/;
			next if ! /UTR/;
			s/\"//g;
			my @fields=split;
			my ($chromosome,$start,$stop,$type,$transcript)=($fields[0],$fields[3],$fields[4],$fields[2],$fields[-1]);
			my $field={
				chromosome => $chromosome,
				start	   => $start,
				stop	   => $stop,
				type	   => $type,
				transcript => $transcript,
			};
			$utrs{$chromosome}||=[];
			push @{$utrs{$chromosome}}, $field;
		}
	}
	return \%utrs;
}
             
=head2 search_utr

		Title	: search_utr
		Usage	: MapAlleles::search_utr(alleles,hashref from load_utr)
		Function: map alleles to UTRs
		Returns	: hash->allele->transcript->type
		Args	: list of alleles,hashref of UTRs

=cut

# search UTRs
sub search_utr{                          
	my ($alleles,$utrs)=@_;
	my %allele_utr;
	while(my($k,$v)=each(%{$alleles})){
		my @hits = grep {$_->{start}<=$v->{stop} && $_->{stop}>=$v->{start}} @{$$utrs{$v->{chromosome}}};
		foreach my $hit(@hits){
			$allele_utr{$k}{$hit->{transcript}}{$hit->{type}}=1;
			print "$k -> ${\$hit->{transcript}} (${\$hit->{type}})\n" if $wb->debug;
		}
	}
	return \%allele_utr;
}

=head2 print_utr

		Title	: print_utr
		Usage	: MapAlleles::print_utr(hashref of allele->utr hits,filehandle)
		Function: print Allele->UTR connections into ace format
		Returns	: nothing
		Args	: hashref of allele->utr hits,filehandle

=cut

# print UTRs
sub print_utr{
	my ($hits,$fh)=@_;
	while( my($allele_name, $type_cds) = each %$hits){
		print $fh 'Variation : "',$allele_name,"\"\n";
		foreach my $cds (keys %$type_cds){
			foreach my $type(keys %{$type_cds->{$cds}}){
				my $ace_type=$type eq 'three_prime_UTR'?'UTR_3':'UTR_5';
				print $fh "Transcript $cds $ace_type Inferred_automatically map_Alleles.pl\n";
			}
		}
		print $fh "\n";
	}
}

# load pseudogenes
sub load_pseudogenes{
	my @files = glob "${\$wb->gff_splits}/*Pseudogene.gff" ;
	my %pgenes;
	foreach my $file(@files){
		my $inf=new IO::File $file, 'r';
		print "processing: $file\n" if $wb->debug;
		while (<$inf>) {
			next if /\#/;
			next unless /Pseudogene/;
			s/\"//g;
			my @fields=split;
			my ($chromosome,$start,$stop,$type1,$type2,$gene)=($fields[0],$fields[3],$fields[4],$fields[1],$fields[2],$fields[-1]);
			next unless ($type1 eq 'Pseudogene' && $type2 eq 'Pseudogene');
			my $field={
				chromosome => $chromosome,
				start	   => $start,
				stop	   => $stop,
				pgene      => $gene,
			};
			$pgenes{$chromosome}||=[];
			push @{$pgenes{$chromosome}}, $field;
		}
	}
	return \%pgenes;
}
             
=head2 search_pseudogene

		Title	: search_pseudogene
		Usage	: MapAlleles::search_pseudogene(alleles,hashref from load_pseudogene)
		Function: map alleles to pseudogeness
		Returns	: hash->allele->transcript->type
		Args	: list of alleles,hashref of pseudogenes

=cut

# search pseudogenes
sub search_pseudogenes{                          
	my ($alleles,$pgenes)=@_;
	my %allele_pgenes;
	while(my($k,$v)=each(%{$alleles})){
		my @hits = grep {$_->{start}<=$v->{stop} && $_->{stop}>=$v->{start}} @{$$pgenes{$v->{chromosome}}};
		foreach my $hit(@hits){
			$allele_pgenes{$k}{$hit->{pgene}}=1;
			print "$k -> ${\$hit->{pgene}}\n" if $wb->debug;
		}
	}
	return \%allele_pgenes;
}

=head2 print_pseudogene

		Title	: print_pseudogene
		Usage	: MapAlleles::print_pseudogene(hashref of allele->utr hits,filehandle)
		Function: print Allele->Pseudogene connections into ace format
		Returns	: nothing
		Args	: hashref of allele->pseudogene hits,filehandle

=cut

# print Pseudogene
sub print_pseudogenes{
	my ($hits,$fh)=@_;
	while( my($allele_name, $pgenes) = each %$hits){
		print $fh 'Variation : "',$allele_name,"\"\n";
		foreach my $p_gene (keys %$pgenes){
				print $fh "Pseudogene $p_gene\n";
		}
		print $fh "\n";
	}
}


# search through non_coding Transcripts

# load ncrna
sub load_ncrnas{
	my @files = glob "${\$wb->gff_splits}/*RNA.gff" ;
	my %nc_rnas;
	foreach my $file(@files){
		my $inf=new IO::File $file, 'r';
		print "processing: $file\n" if $wb->debug;
		while (<$inf>) {
			next if /\#/;
			next if ! /primary_transcript/;
			s/\"//g;
			my @fields=split;
			my ($chromosome,$start,$stop,$transcript)=($fields[0],$fields[3],$fields[4],$fields[-1]);
			my $field={
				chromosome => $chromosome,
				start	   => $start,
				stop	   => $stop,
				transcript => $transcript,
			};
			$nc_rnas{$chromosome}||=[];
			push @{$nc_rnas{$chromosome}}, $field;
		}
	}
	return \%nc_rnas;
}
             
=head2 search_ncrna

		Title	: search_ncrnas
		Usage	: MapAlleles::search_ncrnas(alleles,hashref from load_ncrna)
		Function: map alleles to ncrnas
		Returns	: hash->allele->transcript->1
		Args	: list of alleles,hashref of ncrna

=cut

# search ncrnas
sub search_ncrnas{                          
	my ($alleles,$ncrnas)=@_;
	my %allele_ncrnas;
	while(my($k,$v)=each(%{$alleles})){
		my @hits = grep {$_->{start}<=$v->{stop} && $_->{stop}>=$v->{start}} @{$$ncrnas{$v->{chromosome}}};
		foreach my $hit(@hits){
			$allele_ncrnas{$k}{$hit->{transcript}}=1;
			print "$k -> ${\$hit->{transcript}}\n" if $wb->debug;
		}
	}
	return \%allele_ncrnas;
}

=head2 print_ncrna

		Title	: print_ncrnas
		Usage	: MapAlleles::print_ncrnas(hashref of allele->ncrna hits,filehandle)
		Function: print Allele->ncrna connections into ace format
		Returns	: nothing
		Args	: hashref of allele->ncrna hits,filehandle

=cut

# print non coding RNAs
sub print_ncrnas{
	my ($hits,$fh)=@_;
	while( my($allele_name, $ncrnas) = each %$hits){
		print $fh 'Variation : "',$allele_name,"\"\n";
		foreach my $ncrna (keys %$ncrnas){
				print $fh "Transcript $ncrna\n";
		}
		print $fh "\n";
	}
}





=head2 load_ace

		Title	: load_ace
		Usage	: MapAlleles::load_ace(fh)
		Function: load the acefile into the database
		Returns	: 1 on success
		Args	: IO::File $fh

=cut
	
sub load_ace {
	my ($fh,$filename)=@_; # grml no easy way to retrieve the name from a filehandle ...                                               
	$fh->close;
	$wb->load_to_database($wb->{'autoace'},$filename,'map_Allele',$log);
	1;
}


1;
