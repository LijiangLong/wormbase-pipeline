package Store;
#use YAML;
use Storable;

our (%Genes,%cds,%exons,%introns);


# stores genes to a bdb
sub store_gene {
  my ($chromosome,$start,$stop,$name,$orientation)=@_;

  if (not exists $Genes{$name}) {
    $Genes{$name} = {
      cdses => [],
      name  => $name,
    };
  }

  my $g = $Genes{$name};
  $g->{start} = $start;
  $g->{stop}  = $stop;
  $g->{orientation} = $orientation;
  $g->{chromosome} = $chromosome;
}

# stores cds to a bdbd, needs genes done first, makes gene->cds connections
sub store_cds {
  my ($chromosome,$start,$stop,$orientation,$cds,$gene)=@_;

  if (not exists $cds{$cds}) {
    $cds{$cds} = {
      exons   => [],
      introns => [],
      name    => $cds,
    };
  }

  my $c = $cds{$cds};
  $c->{start}       = $start;
  $c->{stop}        = $stop;
  $c->{orientation} = $orientation;
  $c->{chromosome}  = $chromosome;
  $c->{gene}        = $gene;
}

# stores exons to a bdb, needs cds done first, makes cds->exon connections
# object id is an unique int
sub store_exon {
  my ($chromosome,$start,$stop,$orientation,$exon,$cds_name,$frame)=@_;

  if (not exists $cds{$cds_name}) {
    $cds{$cds_name} = {
      name    => $cds_name,
      exons   => [],
      introns => [],
    };
  }
  push @{$cds{$cds_name}->{exons}},$exon;

  $exons{$exon} = {
    start       => $start,
    stop        => $stop,
    orientation => $orientation,
    chromosome  => $chromosome,
    cds         => $cds_name,
    phase       => $frame,
  };
}

# stores introns to a bdbd, needs cds done first, makes cds->intron connections
# object id is an uiques int
sub store_intron {
  my ($chromosome,$start,$stop,$orientation,$intron,$cds,$frame)=@_;

  if (not exists $cds{$cds_name}) {
    $cds{$cds_name} = {
      name    => $cds_name,
      exons   => [],
      introns => [],
    };
  }

  push @{$cds{$cds}->{introns}},$intron;

  $introns{$intron} = {
    start=>$start,
    stop=>$stop,
    orientation=>$orientation,
    chromosome=>$chromosome,
    cds=>$cds,
  }
}

sub freeze {
  Storable::store \%Genes, 'Genes.ice';
  Storable::store \%cds, 'cds.ice';
  Storable::store \%exons, 'exons.ice';	
  Storable::store \%introns, 'introns.ice';	
}

sub thaw {
  %Genes   = %{Storable::retrieve('Genes.ice')};
  %cds     = %{Storable::retrieve('cds.ice')};
  %exons   = %{Storable::retrieve('exons.ice')};
  %introns = %{Storable::retrieve('introns.ice')};
}

# minimalistic intron class as accessor
package Intron;

# accessor to the introns
sub get_by_id{
	my($id)=@_;
	my $obj=$introns{$id};
	bless $obj;
	return $obj;
}

# minimalistic exon class as accessor
package Exon;

# accessor to the exons
sub get_by_id {
	my ($id)=@_;
	my $obj=$exons{$id};
	bless $obj;
	return $obj;
}

# CDS class to connect exons/introns and genes
package Cds;

# accessor to the cds
sub get_by_id {
	my ($id)=@_;
	my $obj=$cds{$id};
	bless $obj;
	return $obj;
}

# returns a list of connected exons
sub get_all_exons {
	my ($self)=@_;
	my @exons=map {Exon::get_by_id($_)} @{$self->{exons}};
	return @exons;
}

# returns a list of connected introns
sub get_all_introns {
	my ($self)=@_;
	my @introns=map {Intron::get_by_id($_)} @{$self->{introns}};
	return @introns;
}

# Gene class used to create the index
package Gene;


# accessor to gene
sub get_by_id {
	my ($id)=@_;
	my $obj=$Genes{$id};
	bless $obj; 
	return $obj;
}

# returns all connected cds
sub get_all_cds {
	my ($self)=@_;
	my @cdses=map {Cds::get_by_id($_)} @{$self->{cdses}};
	return @cdses;
}

# index/search class
package Mem_index;

# create a memory index of the coordinates of all genes by chromosome
sub build{
  my $self={};
  
  # genes
  while(my ($k,$v)=each %Genes) {
    $self->{genes}->{$v->{chromosome}}||=[];
    push @{$self->{genes}->{$v->{chromosome}}}, {start => $v->{start},stop=>$v->{stop},name=>$k};
  }
  foreach my $k(keys %{$self->{genes}}){
    my @tmp = sort {$a->{start}<=>$b->{start}||$a->{stop}<=>$b->{stop}} @{$self->{genes}->{$k}};
    my $max_end = -1;
    for(my $i=0; $i < scalar(@tmp); $i++) {
      if ($tmp[$i]->{stop} > $max_end) {
        $max_end = $tmp[$i]->{stop};
      }
      $tmp[$i]->{max_end_left} = $max_end;
    }
    $self->{genes}->{$k} = \@tmp;
  }
  # cds part
  while(my ($k,$v)=each %cds) {
    $self->{cds}->{$v->{chromosome}}||=[];
    push @{$self->{cds}->{$v->{chromosome}}}, {start => $v->{start},stop=>$v->{stop},name=>$k};
  }
  foreach my $k(keys %{$self->{cds}}){
    my @tmp = sort {$a->{start}<=>$b->{start}||$a->{stop}<=>$b->{stop}} @{$self->{cds}->{$k}};
    my $max_end = -1;
    for(my $i=0; $i < scalar(@tmp); $i++) {
      if ($tmp[$i]->{stop} > $max_end) {
        $max_end = $tmp[$i]->{stop};
      }
      $tmp[$i]->{max_end_left} = $max_end;
    }
    $self->{cds}->{$k} = \@tmp;
  }
  bless $self;
  return $self;
}

# search for genes overlapping a span
# the grep leaves quite a bit open for improvement
sub search_genes{
  my ($self,$chromosome,$start,$stop)=@_;

  my @list = @{$self->{genes}->{$chromosome}};
  my $hits = $self->_bin_search($chromosome, $start, $stop, \@list);

  return map {Gene::get_by_id($_->{name})} @$hits;
}

# search for cdses overlapping a span
## probably not needed
sub search_cds{
  my ($self,$chromosome,$start,$stop)=@_;

  my @list = @{$self->{cds}->{$chromosome}}; 
  my $hits = $self->_bin_search($chromosome, $start, $stop, \@list);

  return map {Cds::get_by_id($_->{name})} @$hits;
}



sub _bin_search {
  my ($self, $chromosome, $start, $stop, $list) = @_;

  my ($low, $high) = (0, scalar(@$list));
  while($low < $high) {
    my $mid = int(($low + $high) / 2);

    if ($list->[$mid]->{start} <= $stop) {
      $low = $mid + 1;
    } else {
      $high = $mid;
    }
  }

  my @hits;
  for(my $i=$low-1; $i >= 0 and $list->[$i]->{max_end_left} >= $start; $i--) {
    if ($start <= $list->[$i]->{stop} and $stop >= $list->[$i]->{start}) {
      push @hits, $list->[$i];
    }
  }

  return \@hits;
}

1;
